import Foundation

/// The anonymous release channel is selected only by signed bundle metadata.
public struct PublicUpdateChannel: Equatable {
    public let repository: GitHubRepository
    public init?(info: [String: Any]) {
        guard let slug = info["TwisterPublicUpdateRepository"] as? String,
              let repository = try? GitHubRepository(slug),
              info["SUFeedURL"] as? String == repository.websiteURL.appendingPathComponent("releases/latest/download/appcast.xml").absoluteString else { return nil }
        self.repository = repository
    }

    /// Clear a matching saved private connection without reading any credentials.
    /// Preferences belonging to other apps are never migrated or modified.
    public func migrate(_ defaults: UserDefaults) {
        let key = "TwisterUpdateGitHubRepository"
        guard defaults.string(forKey: key)?.lowercased() == repository.slug else { return }
        for name in [key, "TwisterUpdateGitHubRequiresToken", "TwisterUpdateGitHubSavedToken"] {
            defaults.removeObject(forKey: name)
        }
        if let automatic = defaults.object(forKey: "TwisterUpdateGitHubAutomaticChecks") as? Bool {
            defaults.set(automatic, forKey: "SUEnableAutomaticChecks")
        }
    }
}
