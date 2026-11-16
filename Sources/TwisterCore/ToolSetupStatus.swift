import Foundation

/// Each group is installed, reported and removed by itself. Media and Office
/// back the conversions; Web only serves link downloads and is opt-in.
public enum ToolGroup: String, CaseIterable, Sendable {
    case media, web, office
    public var tools: [String] {
        switch self {
        case .media: return ["ffmpeg", "ffprobe"]
        case .web: return ["yt-dlp", "deno"]
        case .office: return ["soffice"]
        }
    }
    /// Setup counts as finished without the optional groups.
    public var isOptional: Bool { self == .web }
}

/// Readiness follows the same executable resolution as conversions, including
/// tools already installed on the user's computer.
public struct ToolSetupStatus: Equatable, Sendable {
    public var mediaReady: Bool
    public var webReady: Bool
    public var officeReady: Bool
    public init(mediaReady: Bool, webReady: Bool = false, officeReady: Bool) {
        self.mediaReady = mediaReady; self.webReady = webReady; self.officeReady = officeReady
    }
    public init(resolve: (String) -> URL?) {
        func found(_ group: ToolGroup) -> Bool { group.tools.allSatisfy { resolve($0) != nil } }
        mediaReady = found(.media); webReady = found(.web); officeReady = found(.office)
    }
    public func isReady(_ group: ToolGroup) -> Bool {
        switch group {
        case .media: return mediaReady
        case .web: return webReady
        case .office: return officeReady
        }
    }
    /// Conversions need Media and Office only.
    public var ready: Bool { missing.isEmpty }
    public var missing: [ToolGroup] { ToolGroup.allCases.filter { !$0.isOptional && !isReady($0) } }
}

/// Replace an incomplete installation only after the new directory is complete.
/// A failed publish restores the original; a retry never asks users to delete it.
enum ToolInstallation {
    static func publish(_ stage: URL, to target: URL, complete: (URL) -> Bool) throws {
        let fm = FileManager.default
        guard complete(stage) else { throw TwisterError.failed("The downloaded tools are incomplete. Please try setup again.") }
        if complete(target) { return }
        let backup = target.deletingLastPathComponent().appendingPathComponent(".previous-" + UUID().uuidString)
        let existing = fm.fileExists(atPath: target.path)
        if existing { try fm.moveItem(at: target, to: backup) }
        do { try fm.moveItem(at: stage, to: target) }
        catch {
            if existing { try fm.moveItem(at: backup, to: target) }
            throw error
        }
        if existing { try? fm.removeItem(at: backup) }
    }
}
