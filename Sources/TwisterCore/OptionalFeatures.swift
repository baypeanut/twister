import Foundation

/// What the web download entry points show.
public enum WebDownloadAvailability: Equatable, Sendable {
    /// This copy was built without the downloader; no entry point is shown.
    case excluded
    /// The user turned web downloads off in Settings.
    case off
    /// Turned on or never decided, but these tool groups are not installed.
    case needsTools([ToolGroup])
    case ready
}

/// Web downloads are opt-in. Until the user decides, the setting follows
/// whether the Web tools are present, so a copy that already has them keeps
/// working and a new one starts with the feature off.
public enum WebDownloadGate {
    public static let preferenceKey = "webDownloadsEnabled"
    /// `scripts/build-app.sh` writes this key as false for a build without the downloader.
    public static let buildKey = "TwisterWebDownloads"

    public static func buildIncludesDownloader(_ info: [String: Any]?) -> Bool { info?[buildKey] as? Bool != false }
    public static func isOn(preference: Bool?, status: ToolSetupStatus) -> Bool { preference ?? status.webReady }
    public static func availability(included: Bool, preference: Bool?, status: ToolSetupStatus) -> WebDownloadAvailability {
        guard included else { return .excluded }
        if preference == false { return .off }
        // Link downloads merge and convert with FFmpeg.
        let needed = [ToolGroup.media, .web].filter { !status.isReady($0) }
        return needed.isEmpty ? .ready : .needsTools(needed)
    }
    public static func preference(in defaults: UserDefaults) -> Bool? { defaults.object(forKey: preferenceKey) as? Bool }
    /// Links to this Mac or the local network are refused unless the user
    /// stored `true` for this key, for example with `defaults write`.
    public static let localNetworkKey = "webDownloadsAllowLocalNetwork"
    public static func allowsLocalNetwork(in defaults: UserDefaults) -> Bool { defaults.object(forKey: localNetworkKey) as? Bool == true }
}

/// Window arrangement is an optional extra that stays off until the user
/// turns it on. Only a stored `true` counts: a new install has no value and
/// never polls or asks for a permission, and a user who enabled the feature
/// keeps it without any migration step.
public enum WindowArrangementPreference {
    public static let key = "windowManagementEnabled"
    public static func isOn(appEnabled: Bool, stored: Any?) -> Bool { appEnabled && (stored as? Bool) == true }
    public static func isOn(in defaults: UserDefaults) -> Bool {
        isOn(appEnabled: defaults.bool(forKey: "enabled"), stored: defaults.object(forKey: key))
    }
}

/// Owns the polling handle of an optional feature. Nothing is created while
/// the feature is off, and turning it off releases the handle at once.
public final class OptionalPolling<Handle> {
    private let start: () -> Handle
    private let stop: (Handle) -> Void
    private var handle: Handle?
    public init(start: @escaping () -> Handle, stop: @escaping (Handle) -> Void) { self.start = start; self.stop = stop }
    public var isRunning: Bool { handle != nil }
    public func set(_ on: Bool) {
        if on { if handle == nil { handle = start() } }
        else if let current = handle { handle = nil; stop(current) }
    }
    deinit { if let handle { stop(handle) } }
}
