import Foundation

/// A move may cross volumes and cannot be made atomic. Validate the entire
/// selection first and always return the paths that actually changed.
public enum FileMoveBatch {
    public struct Result: Sendable {
        public var moved: [URL: URL] = [:]
        public var failure: String?
    }

    public static func run(_ inputs: [URL], to directory: URL, token: CancellationToken = .init()) -> Result {
        let manager = FileManager.default
        var result = Result()
        do {
            try token.check()
            let destination = directory.standardizedFileURL.resolvingSymlinksInPath()
            guard try destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw TwisterError.invalidInput("Choose a destination folder.")
            }
            var seen = Set<URL>()
            let sources = inputs.map(\.standardizedFileURL).filter { seen.insert($0).inserted }
            var reserved = Set<String>()
            var plan: [(URL, URL)] = []
            for source in sources {
                try token.check()
                let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isDirectory == true, values.isSymbolicLink != true {
                    let root = source.resolvingSymlinksInPath().path
                    guard destination.path != root, !destination.path.hasPrefix(root + "/") else {
                        throw TwisterError.invalidInput("A folder cannot be moved inside itself.")
                    }
                    guard !sources.contains(where: { $0 != source && $0.path.hasPrefix(source.path + "/") }) else {
                        throw TwisterError.invalidInput("Choose a folder or its contents, rather than both.")
                    }
                }
                var target = destination.appendingPathComponent(source.lastPathComponent)
                if source == target { continue }
                let isDirectory = values.isDirectory == true
                let ext = isDirectory ? "" : source.pathExtension
                let stem = isDirectory || ext.isEmpty ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
                var index = 2
                while manager.fileExists(atPath: target.path) || reserved.contains(target.path.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))) {
                    target = destination.appendingPathComponent("\(stem) \(index)" + (ext.isEmpty ? "" : ".\(ext)"))
                    index += 1
                }
                reserved.insert(target.path.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX")))
                plan.append((source, target))
            }
            for (source, target) in plan {
                try token.check()
                try manager.moveItem(at: source, to: target)
                result.moved[source] = target
            }
        } catch {
            result.failure = error.localizedDescription
        }
        return result
    }
}
