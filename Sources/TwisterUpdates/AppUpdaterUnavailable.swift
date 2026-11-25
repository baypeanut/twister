#if TWISTER_WITHOUT_UPDATES
import AppKit
import Combine

/// Builds without update support neither link nor embed the updater
/// framework. Such a build carries no update signing key, so the full updater
/// could never start either; this keeps the same interface, always inactive.
@MainActor public final class AppUpdater: NSObject, ObservableObject {
    @Published public private(set) var availableVersion: String?
    @Published public private(set) var configurationError: String?
    @Published public private(set) var lastError: String?
    @Published public private(set) var canCheckForUpdates = false
    @Published public private(set) var automaticallyChecksForUpdates = false
    @Published public private(set) var lastCheckedAt: Date?
    @Published public private(set) var sessionInProgress = false
    @Published public private(set) var waitingForCurrentTask = false
    @Published public private(set) var isBusy = false
    @Published public private(set) var repository: GitHubRepository?
    @Published public private(set) var requiresToken = true
    @Published public private(set) var hasSavedToken = false
    @Published public private(set) var isConnecting = false
    @Published public private(set) var isPreparingCheck = false
    public var officialRepository: GitHubRepository? { nil }
    public var isConfigured: Bool { false }
    public var canChangeConnection: Bool { false }

    public override convenience init() { self.init(credentials: KeychainUpdateCredentialStore(), defaults: .standard) }
    public init(credentials: UpdateCredentialStore, defaults: UserDefaults, info: [String: Any]? = nil) { super.init() }

    public func start() { configurationError = UpdateConfiguration.ConfigurationError.notConfigured.localizedDescription }
    public func checkForUpdates() {}
    public func setAutomaticChecks(_ enabled: Bool) {}
    public func connectGitHub(repository input: String, token inputToken: String, requiresToken: Bool) async throws {
        throw UpdateConfiguration.ConfigurationError.notConfigured
    }
    public func disconnectGitHub() async throws {}
    public func setBusy(_ busy: Bool) { isBusy = busy }
    public var supportsGentleScheduledUpdateReminders: Bool { true }
}
#endif
