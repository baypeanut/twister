import Foundation
import Darwin

public struct ProcessResult: Sendable {
    public let output: Data
    public let errorOutput: Data
    public var text: String { String(decoding: output, as: UTF8.self) }
}

public enum ProcessRunner {
    // Codec diagnostics are untrusted. Keep the useful tail while continuing to
    // drain the pipe, so a noisy input cannot consume unbounded memory or block.
    static let diagnosticByteLimit = 1_000_000
    static let localProtocols = "file,pipe,crypto,data"
    /// Bounds for helpers that never run for long. Encodes stay unbounded:
    /// their duration follows the media, and Cancel remains available.
    static let probeTimeout: TimeInterval = 120
    static let metadataTimeout: TimeInterval = 300
    static let officeTimeout: TimeInterval = 900

    static func failureReason(from diagnostics: String, tool: String, code: Int32) -> String {
        let causes = ["invalid", "no such file", "permission denied", "not on whitelist", "error:",
                      "could not", "cannot", "failed", "unsupported", "not found", "not permitted"]
        let noise = ["terminating thread", "task finished with error code", "conversion failed!",
                     "ffmpeg version", "configuration:", "libav", "libsw", "fontconfig warning:",
                     "input #", "output #", "duration:", "stream #", "stream mapping:", "press [q]", "frame="]
        var fallback: String?
        for raw in diagnostics.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            var component: String?
            while line.hasPrefix("["), let end = line.firstIndex(of: "]") {
                let prefix = String(line[line.index(after: line.startIndex)..<end])
                if let address = prefix.range(of: " @ ") { component = String(prefix[..<address.lowerBound]) }
                line = String(line[line.index(after: end)...]).trimmingCharacters(in: .whitespaces)
            }
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            guard !noise.contains(where: { lower.hasPrefix($0) }) else { continue }
            // MediaEngine retries unsupported managed bitrates by recognizing
            // the encoder and its setup failure. Keep that semantic context,
            // without exposing the pointer address or shutdown chatter.
            if lower.contains("encoder setup failed"), let component {
                return String("\(component): \(line)".prefix(300))
            }
            if causes.contains(where: { lower.contains($0) }) {
                let head = String(line.prefix(300))
                return causes.contains(where: { head.lowercased().contains($0) }) ? head : String(line.suffix(300))
            }
            // Unknown tools still keep a diagnostic tail, including an
            // unterminated line after a large burst of output.
            if fallback == nil { fallback = String(line.suffix(300)) }
        }
        return fallback ?? "\(tool) exited with code \(code)."
    }

    /// Conversion inputs stay local even if a media container references an
    /// external playlist segment. Local pipes/data/encrypted files still work.
    /// ffmpeg applies an input option only to the next `-i`, so every input
    /// receives its own restriction; an override path may have any file name.
    static func localOnlyArguments(_ executable: URL, _ arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        func isTool(_ name: String) -> Bool {
            if executable.lastPathComponent == name { return true }
            guard let override = Dependencies.override(name, environment: environment) else { return false }
            return URL(fileURLWithPath: override).standardizedFileURL.path == executable.standardizedFileURL.path
        }
        let option = "-protocol_whitelist", restriction = [option, localProtocols]
        let probe = isTool("ffprobe")
        guard probe || isTool("ffmpeg") else { return arguments }
        if probe || !arguments.contains("-i") { return arguments.contains(option) ? arguments : restriction + arguments }
        var result: [String] = [], restricted = false, index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == option { restricted = true }
            if argument == "-i" {
                if !restricted { result += restriction }
                result.append(argument)
                if index + 1 < arguments.count { index += 1; result.append(arguments[index]) }
                restricted = false
            } else { result.append(argument) }
            index += 1
        }
        return result
    }

    /// The child leads its own process group, so Cancel or an expired `timeout`
    /// also stops helpers it started. `timeout` is wall-clock seconds; nil waits
    /// for as long as the work takes. `onDiagnostics` receives bounded original
    /// stderr on the calling thread before a nonzero exit is thrown.
    @discardableResult
    public static func run(_ executable: URL, _ arguments: [String], directory: URL? = nil, token: CancellationToken = .init(), environment: [String: String] = [:], timeout: TimeInterval? = nil, onDiagnostics: ((Data) -> Void)? = nil, onOutput: (@Sendable (Data) -> Void)? = nil) throws -> ProcessResult {
        try token.check()
        let output = Pipe(), errors = Pipe()
        var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        // A background process group must not read the terminal.
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, output.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, errors.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        if let directory { posix_spawn_file_actions_addchdir_np(&actions, directory.path) }
        // Only the three standard streams are inherited, and the child starts
        // with default signal handling even when the caller ignores a signal.
        var defaults = sigset_t(), mask = sigset_t()
        sigfillset(&defaults); sigemptyset(&mask)
        posix_spawnattr_setsigdefault(&attributes, &defaults); posix_spawnattr_setsigmask(&attributes, &mask)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        posix_spawnattr_setpgroup(&attributes, 0)
        let argv = ([executable.path] + localOnlyArguments(executable, arguments)).map { strdup($0) } + [nil]
        let variables = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for pointer in argv { free(pointer) }; for pointer in variables { free(pointer) } }
        var pid: pid_t = 0
        let started = argv.withUnsafeBufferPointer { argv in variables.withUnsafeBufferPointer { variables in
            posix_spawn(&pid, executable.path, &actions, &attributes, UnsafeMutablePointer(mutating: argv.baseAddress!), UnsafeMutablePointer(mutating: variables.baseAddress!))
        } }
        try? output.fileHandleForWriting.close(); try? errors.fileHandleForWriting.close()
        guard started == 0 else {
            throw TwisterError.failed("\(executable.lastPathComponent) could not be started: \(String(cString: strerror(started))).")
        }
        // Drain both streams concurrently: codec diagnostics can exceed a pipe buffer.
        let group = DispatchGroup()
        let captured = Capture(trimsOutput: onOutput != nil)
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            // availableData returns as soon as bytes arrive; read(upToCount:) can
            // wait for a full buffer and leave a short progress stream stuck at 0%.
            while true {
                let chunk = output.fileHandleForReading.availableData
                guard !chunk.isEmpty else { break }
                captured.appendOutput(chunk)
                onOutput?(chunk)
            }
        }
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            while true {
                let chunk = errors.fileHandleForReading.availableData
                guard !chunk.isEmpty else { break }
                captured.appendErrors(chunk)
            }
        }
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        var status: Int32 = 0, stoppingAt: Date?, timedOut = false, reaped = true
        while true {
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == pid { break }
            if waited < 0 {
                if errno == EINTR { continue }
                reaped = false; kill(-pid, SIGKILL); break
            }
            if let stoppingAt {
                if Date().timeIntervalSince(stoppingAt) > 2 { kill(-pid, SIGKILL) }
            } else if token.isCancelled || deadline.map({ Date() > $0 }) == true {
                timedOut = !token.isCancelled; stoppingAt = Date(); kill(-pid, SIGTERM)
            }
            Thread.sleep(forTimeInterval: 0.03)
        }
        // A helper must not keep the pipes, and with them this job, alive after
        // its parent has exited.
        if stoppingAt != nil { kill(-pid, SIGTERM) }
        if group.wait(timeout: .now() + 2) == .timedOut {
            kill(-pid, SIGTERM)
            if group.wait(timeout: .now() + 2) == .timedOut { kill(-pid, SIGKILL); _ = group.wait(timeout: .now() + 2) }
        }
        try token.check()
        if timedOut { throw TwisterError.failed("\(executable.lastPathComponent) took too long to respond and was stopped.") }
        guard reaped else { throw TwisterError.failed("\(executable.lastPathComponent) stopped unexpectedly.") }
        let (text, diagnostics) = captured.snapshot()
        onDiagnostics?(diagnostics)
        // WIFEXITED ? WEXITSTATUS : WTERMSIG
        let code = status & 0x7f == 0 ? (status >> 8) & 0xff : status & 0x7f
        guard code == 0 else {
            throw TwisterError.failed(failureReason(from: String(decoding: diagnostics, as: UTF8.self), tool: executable.lastPathComponent, code: code))
        }
        return ProcessResult(output: text, errorOutput: diagnostics)
    }
    private final class Capture: @unchecked Sendable {
        private let lock = NSLock(), trimsOutput: Bool
        private var output = Data(), errors = Data()
        init(trimsOutput: Bool) { self.trimsOutput = trimsOutput }
        func appendOutput(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            output.append(chunk)
            if trimsOutput && output.count > 2_000_000 { output.removeFirst(output.count - 2_000_000) }
        }
        func appendErrors(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            errors.append(chunk)
            if errors.count > diagnosticByteLimit { errors.removeFirst(errors.count - diagnosticByteLimit) }
        }
        func snapshot() -> (Data, Data) { lock.lock(); defer { lock.unlock() }; return (output, errors) }
    }
}

public enum Dependencies {
    /// `TWISTER_` executable overrides serve development and the command-line
    /// tool. A packaged app never takes its tools from the environment.
    public static var honorsOverrides: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.bundleURL.pathExtension != "app"
        #endif
    }
    public static func override(_ name: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard honorsOverrides, let value = environment["TWISTER_" + name.uppercased()], !value.isEmpty else { return nil }
        return value
    }
    /// Where a tool would run from, without verifying it. Readiness checks
    /// use this; `executable` verifies tools that setup installed.
    public static func locate(_ name: String) throws -> URL {
        let fm = FileManager.default
        var paths: [String] = []
        if let override = override(name) { paths.append(override) }
        if let resource = Bundle.main.resourceURL {
            paths.append(resource.appendingPathComponent("Tools/\(name)").path)
            if name == "exiftool" { paths.append(resource.appendingPathComponent("Tools/ExifTool/exiftool").path) }
            if name == "soffice" { paths.append(resource.appendingPathComponent("Tools/LibreOffice.app/Contents/MacOS/soffice").path) }
        }
        if let external=ExternalToolSetup.executable(name) { paths.append(external.path) }
        #if DEBUG
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        paths.append(root.appendingPathComponent("Tools/\(name)").path)
        if name == "exiftool" { paths.append(root.appendingPathComponent("Tools/ExifTool/exiftool").path) }
        if name == "soffice" { paths.append(root.appendingPathComponent("Tools/LibreOffice.app/Contents/MacOS/soffice").path) }
        #endif
        paths += ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        if name == "soffice" { paths.append("/Applications/LibreOffice.app/Contents/MacOS/soffice") }
        guard let found = paths.first(where: { path in
            // Search permission makes a directory "executable" too. In
            // particular, ExifTool and exiftool collide on the default macOS
            // filesystem; select the actual script inside that directory.
            let resolved=URL(fileURLWithPath:path).resolvingSymlinksInPath()
            let values=try? resolved.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
            return fm.isExecutableFile(atPath:resolved.path) && values?.isRegularFile == true && (values?.fileSize ?? 0)>0
        }) else { throw TwisterError.missingDependency(name) }
        return URL(fileURLWithPath: found)
    }
    /// The tool to run. A tool from Twister's own tool folder must still match
    /// its pinned hash or signature; that is checked once per session and
    /// again whenever the file changes.
    public static func executable(_ name: String) throws -> URL {
        let url = try locate(name)
        if url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(ExternalToolSetup.root.resolvingSymlinksInPath().standardizedFileURL.path + "/") {
            try ExternalToolSetup.verifyInstalled(url, tool: name)
        }
        return url
    }
}

public enum OutputFiles {
    /// Re-encoding an already optimized file must not increase its size or lose
    /// quality. Call only when output format and requested geometry are unchanged.
    static func retainSmallerOriginal(_ input:URL,output:URL,target:Int64?) throws {
        guard input.pathExtension.lowercased()==output.pathExtension.lowercased() else { return }
        let manager=FileManager.default
        let source=input.resolvingSymlinksInPath()
        let original=(try manager.attributesOfItem(atPath:source.path)[.size] as? NSNumber)?.int64Value ?? 0
        let encoded=(try manager.attributesOfItem(atPath:output.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard original>0,encoded>original,target == nil || original<=target! else { return }
        try manager.removeItem(at:output);try manager.copyItem(at:source,to:output)
    }
    public static func unique(for input: URL, extension ext: String, suffix: String = "", directory: URL? = nil) -> URL {
        let dir = directory ?? input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent + suffix
        let cleanExt = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        var candidate = dir.appendingPathComponent(stem).appendingPathExtension(cleanExt)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem) \(index)").appendingPathExtension(cleanExt); index += 1
        }
        return candidate
    }
    public static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Twister-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    public static func validate(_ urls: [URL]) throws {
        guard !urls.isEmpty else { throw TwisterError.failed("No output was produced.") }
        for url in urls {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            guard values.isDirectory == true || (values.fileSize ?? 0) > 0 else { throw TwisterError.failed("An empty output was produced: \(url.lastPathComponent)") }
        }
    }
}
