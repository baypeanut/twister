import Foundation

/// Where the executable of a tool was found.
public enum ToolSource: String, Sendable {
    /// A `TWISTER_` environment override.
    case override
    /// Inside the application bundle.
    case bundled
    /// Downloaded by setup into Twister's own tool directory.
    case installed
    /// Anywhere else on the computer, such as Homebrew.
    case system
}

public struct ToolReport: Equatable, Sendable {
    public let name: String
    public let path: URL?
    public let source: ToolSource?
    public init(name: String, path: URL?, source: ToolSource?) { self.name = name; self.path = path; self.source = source }
}

public struct ToolGroupReport: Equatable, Sendable {
    public let group: ToolGroup
    public let tools: [ToolReport]
    /// Setup wrote files for this group; only those can be removed.
    public let removable: Bool
    public init(group: ToolGroup, tools: [ToolReport], removable: Bool) { self.group = group; self.tools = tools; self.removable = removable }
    public var ready: Bool { tools.allSatisfy { $0.path != nil } }
    /// One source when every tool shares it, otherwise nil.
    public var source: ToolSource? {
        let sources = Set(tools.compactMap(\.source))
        return ready && sources.count == 1 ? sources.first : nil
    }
    /// Known only for the pinned downloads of setup.
    public var version: String? { source == .installed ? ToolStore.pinnedVersions[group] : nil }
}

public struct ToolRemovalPlan: Equatable, Sendable {
    /// Existing items that setup wrote for the group.
    public let remove: [URL]
    /// Items left in place because an override points at them.
    public let kept: [URL]
}

/// The layout of Twister's own tool directory. Removal is limited to the fixed
/// paths below; Homebrew, the application bundle and override targets are
/// never candidates.
public struct ToolStore: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }

    static let mediaDirectory = "media-v1", webDirectory = "web-v1", officeDirectory = "office-26.8.1"
    static let pinnedVersions: [ToolGroup: String] = [.media: "FFmpeg 9.0", .web: "yt-dlp 2026.08.19 · Deno 2.9.7", .office: "LibreOffice 26.8.1"]

    /// Earlier setups stored the web tools beside FFmpeg; those files still
    /// belong to the Web group.
    static func ownedPaths(_ group: ToolGroup) -> [String] {
        switch group {
        case .media: return [mediaDirectory + "/ffmpeg", mediaDirectory + "/ffprobe"]
        case .web: return [webDirectory, mediaDirectory + "/yt-dlp", mediaDirectory + "/deno"]
        case .office: return [officeDirectory]
        }
    }
    static func executablePaths(_ name: String) -> [String] {
        switch name {
        case "ffmpeg", "ffprobe": return [mediaDirectory + "/" + name]
        case "yt-dlp", "deno": return [webDirectory + "/" + name, mediaDirectory + "/" + name]
        case "soffice": return [officeDirectory + "/LibreOffice.app/Contents/MacOS/soffice"]
        default: return []
        }
    }
    static func usable(_ url: URL) -> Bool {
        guard let values = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return false }
        return FileManager.default.isExecutableFile(atPath: url.path) && values.isRegularFile == true && (values.fileSize ?? 0) > 0
    }
    public func executable(_ name: String) -> URL? {
        Self.executablePaths(name).map { root.appendingPathComponent($0) }.first(where: Self.usable)
    }

    private static func resolved(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }
    private static func exists(_ url: URL) -> Bool { (try? url.checkResourceIsReachable()) == true || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil }
    /// The item's directory must really be inside the tool directory, so a
    /// link that replaced `media-v1` cannot lead a removal elsewhere.
    func owns(_ item: URL) -> Bool {
        let base = Self.resolved(root), parent = Self.resolved(item.deletingLastPathComponent())
        return ![".", "..", ""].contains(item.lastPathComponent) && (parent == base || parent.hasPrefix(base + "/"))
    }
    public func installedItems(_ group: ToolGroup) -> [URL] {
        Self.ownedPaths(group).map { root.appendingPathComponent($0) }.filter { Self.exists($0) && owns($0) }
    }
    public func removalPlan(_ group: ToolGroup, protected: [URL] = []) -> ToolRemovalPlan {
        let guarded = protected.map(Self.resolved)
        var remove: [URL] = [], kept: [URL] = []
        for item in installedItems(group) {
            let path = Self.resolved(item)
            if guarded.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) { kept.append(item) } else { remove.append(item) }
        }
        return ToolRemovalPlan(remove: remove, kept: kept)
    }
    /// Removes what setup installed for one group and nothing else. A link is
    /// unlinked, never followed.
    @discardableResult public func remove(_ group: ToolGroup, protected: [URL] = []) throws -> ToolRemovalPlan {
        let plan = removalPlan(group, protected: protected), fm = FileManager.default
        for item in plan.remove {
            guard owns(item) else { throw TwisterError.failed("These tools are outside Twister's tool folder and were not removed.") }
            try fm.removeItem(at: item)
        }
        let shared = root.appendingPathComponent(Self.mediaDirectory)
        if owns(shared), (try? shared.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
           (try? fm.contentsOfDirectory(atPath: shared.path))?.isEmpty == true { try? fm.removeItem(at: shared) }
        return plan
    }
    /// Bytes used by the files setup installed for a group.
    public func size(_ group: ToolGroup) -> Int64 {
        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        for item in installedItems(group) {
            if let values = try? item.resourceValues(forKeys: keys), values.isRegularFile == true { total += Int64(values.totalFileAllocatedSize ?? 0); continue }
            guard let files = FileManager.default.enumerator(at: item, includingPropertiesForKeys: Array(keys)) else { continue }
            for case let file as URL in files {
                if let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true { total += Int64(values.totalFileAllocatedSize ?? 0) }
            }
        }
        return total
    }

    public static func overrideVariable(_ tool: String) -> String { "TWISTER_" + tool.uppercased() }
    public static func overrides(_ group: ToolGroup, environment: [String: String]) -> [URL] {
        group.tools.compactMap { environment[overrideVariable($0)] }.filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0) }
    }
    public func source(of path: URL, tool: String, environment: [String: String], bundle: URL?) -> ToolSource {
        let target = Self.resolved(path)
        func inside(_ directory: URL) -> Bool { target.hasPrefix(Self.resolved(directory) + "/") }
        if let override = environment[Self.overrideVariable(tool)], !override.isEmpty, Self.resolved(URL(fileURLWithPath: override)) == target { return .override }
        if let bundle, inside(bundle) { return .bundled }
        return inside(root) ? .installed : .system
    }
    public func report(_ group: ToolGroup, environment: [String: String], bundle: URL?, resolve: (String) -> URL?) -> ToolGroupReport {
        let tools = group.tools.map { name -> ToolReport in
            let path = resolve(name)
            return ToolReport(name: name, path: path, source: path.map { source(of: $0, tool: name, environment: environment, bundle: bundle) })
        }
        return ToolGroupReport(group: group, tools: tools, removable: !removalPlan(group, protected: Self.overrides(group, environment: environment)).remove.isEmpty)
    }
}
