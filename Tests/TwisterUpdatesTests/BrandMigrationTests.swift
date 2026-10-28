import XCTest
@testable import TwisterUpdates

final class BrandMigrationTests: XCTestCase {
    private final class UnusedCredentials: UpdateCredentialStore, @unchecked Sendable {
        var reads = 0
        func token(for repository: GitHubRepository) throws -> String { reads += 1; throw UpdateCredentialError.missing }
        func save(_ token: String, for repository: GitHubRepository) throws { XCTFail("Startup must not save credentials") }
        func remove(for repository: GitHubRepository) throws { XCTFail("Startup must not remove credentials") }
    }
    func testTwisterIgnoresAndPreservesUnrelatedApplicationsPreferences() async throws {
        let suite = "TwisterIsolationTests.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("sampleaccount/twister", forKey: "OtherAppUpdateGitHubRepository")
        defaults.set(true, forKey: "OtherAppUpdateGitHubSavedToken")
        defaults.set("preserved history", forKey: "history")
        let store = UnusedCredentials()
        let updater = await MainActor.run { AppUpdater(credentials: store, defaults: defaults, info: [:]) }
        await MainActor.run { XCTAssertNil(updater.repository); XCTAssertFalse(updater.hasSavedToken) }
        XCTAssertEqual(defaults.string(forKey: "OtherAppUpdateGitHubRepository"), "sampleaccount/twister")
        XCTAssertEqual(defaults.string(forKey: "history"), "preserved history")
        XCTAssertEqual(store.reads, 0)
    }
    func testRepositoryAndCredentialAccountNeverAliasAnotherApplication() throws {
        for slug in ["baypeanut/twister", "example/tool", "example/other-tool", "example/custom"] {
            let repository = try GitHubRepository(slug)
            XCTAssertEqual(UpdateBrandMigration.canonical(repository), repository)
            XCTAssertEqual(UpdateBrandMigration.credentialAccount(repository), repository)
        }
    }
    func testTwisterRejectsUpstreamArchiveURLs() throws {
        let client = GitHubUpdateClient(repository: try GitHubRepository("baypeanut/twister"), token: nil)
        for slug in ["example/tool-app", "example/tool", "example/other-tool", "other/twister"] {
            XCTAssertThrowsError(try client.archiveReference(for: URL(string: "https://github.com/\(slug)/releases/download/v1/app.zip")!))
        }
        XCTAssertEqual(try client.archiveReference(for: URL(string: "https://github.com/baypeanut/twister/releases/download/v1/Twister.zip")!), .release(tag: "v1", filename: "Twister.zip"))
    }
}
