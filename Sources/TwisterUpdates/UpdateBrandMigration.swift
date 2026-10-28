import Foundation

/// Twister never aliases another application's update channel or credential account.
/// The adapter name is retained internally to keep the update transport API stable.
enum UpdateBrandMigration {
    static func canonical(_ repository: GitHubRepository) -> GitHubRepository { repository }
    static func credentialAccount(_ repository: GitHubRepository) -> GitHubRepository { repository }
    static func acceptsArchive(owner: String, name: String, for repository: GitHubRepository) -> Bool {
        owner.lowercased() + "/" + name.lowercased() == repository.slug
    }
    static func latestFeed(repository: GitHubRepository, token: String?, configuration: URLSessionConfiguration = .ephemeral) async throws -> (GitHubUpdateClient, Data) {
        let client = GitHubUpdateClient(repository: repository, token: token, configuration: configuration)
        return (client, try await client.fetchLatestAppcast())
    }
}
