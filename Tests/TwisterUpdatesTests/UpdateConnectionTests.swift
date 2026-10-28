import XCTest
@testable import TwisterUpdates

final class UpdateConnectionTests: XCTestCase {
    private static var configuredInfo: [String: Any] {
        ["SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(),
         "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true]
    }
    private final class MemoryCredentials: UpdateCredentialStore, @unchecked Sendable {
        var values: [String: String] = [:]
        var reads = 0
        func token(for repository: GitHubRepository) throws -> String {
            reads += 1
            guard let value = values[repository.slug.lowercased()] else { throw UpdateCredentialError.missing }
            return value
        }
        func save(_ token: String, for repository: GitHubRepository) throws { values[repository.slug.lowercased()] = token }
        func remove(for repository: GitHubRepository) throws { values.removeValue(forKey: repository.slug.lowercased()) }
    }

    func testUnconfiguredBuildRejectsConnectionBeforeCredentialsOrNetwork() async throws {
        let suite = "TwisterUnconfiguredConnectionTests.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoryCredentials()
        let updater = await MainActor.run {
            AppUpdater(credentials: store, defaults: defaults, validateAccess: { _, _ in
                XCTFail("An unconfigured build must not contact an update repository")
            }, info: [:])
        }
        do {
            try await updater.connectGitHub(repository: "example/private", token: "fixture", requiresToken: true)
            XCTFail("No signing trust is configured")
        } catch { XCTAssertEqual(error as? UpdateConfiguration.ConfigurationError, .notConfigured) }
        XCTAssertEqual(store.reads, 0)
        XCTAssertTrue(store.values.isEmpty)
        await MainActor.run { XCTAssertNil(updater.repository); XCTAssertFalse(updater.hasSavedToken) }
    }

    func testPrivateConnectionRestoresWithoutReadingTheTokenAndCanReuseIt() async throws {
        let suite = "TwisterUpdateConnectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoryCredentials()
        let updater = await MainActor.run {
            AppUpdater(credentials: store, defaults: defaults, validateAccess: { repository, token in
                XCTAssertEqual(repository.slug.lowercased(), "example/private")
                XCTAssertEqual(token, "github_pat_fixture")
            }, info: Self.configuredInfo)
        }
        try await updater.connectGitHub(repository: "example/private", token: "github_pat_fixture", requiresToken: true)
        XCTAssertEqual(store.reads, 0)
        XCTAssertEqual(store.values.count, 1)
        XCTAssertFalse(String(describing: defaults.dictionaryRepresentation()).contains("github_pat_fixture"))
        let restored = await MainActor.run {
            AppUpdater(credentials: store, defaults: defaults, validateAccess: { _, token in XCTAssertEqual(token, "github_pat_fixture") }, info: Self.configuredInfo)
        }
        await MainActor.run {
            XCTAssertEqual(restored.repository?.slug.lowercased(), "example/private")
            XCTAssertTrue(restored.hasSavedToken)
        }
        XCTAssertEqual(store.reads, 0, "Opening the app must not trigger a Keychain access prompt")
        try await restored.connectGitHub(repository: "example/private", token: "", requiresToken: true)
        XCTAssertEqual(store.reads, 1)
        try await restored.disconnectGitHub()
        XCTAssertTrue(store.values.isEmpty)
        await MainActor.run { XCTAssertNil(restored.repository); XCTAssertFalse(restored.hasSavedToken) }
    }

    func testRejectedTokenDoesNotReplaceWorkingConnection() async throws {
        let suite = "TwisterUpdateConnectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoryCredentials()
        let updater = await MainActor.run {
            AppUpdater(credentials: store, defaults: defaults, validateAccess: { _, token in
                if token == "rejected_fixture" { throw UpdateCredentialError.missing }
            }, info: Self.configuredInfo)
        }
        try await updater.connectGitHub(repository: "example/private", token: "accepted_fixture", requiresToken: true)
        do {
            try await updater.connectGitHub(repository: "example/new", token: "rejected_fixture", requiresToken: true)
            XCTFail("Rejected token should fail")
        } catch { }
        await MainActor.run { XCTAssertEqual(updater.repository?.slug.lowercased(), "example/private") }
        XCTAssertEqual(store.values, ["example/private": "accepted_fixture"])
    }

    func testSwitchingToPublicDoesNotReadOrForwardPrivateToken() async throws {
        let suite = "TwisterUpdateConnectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MemoryCredentials()
        let updater = await MainActor.run {
            AppUpdater(credentials: store, defaults: defaults, validateAccess: { repository, token in
                if repository.slug.lowercased() == "example/public" { XCTAssertNil(token) }
            }, info: Self.configuredInfo)
        }
        try await updater.connectGitHub(repository: "example/private", token: "github_pat_fixture", requiresToken: true)
        try await updater.connectGitHub(repository: "example/public", token: "ignored_private_fixture", requiresToken: false)
        XCTAssertEqual(store.reads, 0)
        XCTAssertTrue(store.values.isEmpty)
        await MainActor.run {
            XCTAssertFalse(updater.requiresToken)
            XCTAssertFalse(updater.hasSavedToken)
            XCTAssertEqual(updater.repository?.slug.lowercased(), "example/public")
            updater.setBusy(true)
            XCTAssertFalse(updater.canChangeConnection)
        }
        do {
            try await updater.disconnectGitHub()
            XCTFail("Connection changes must wait for the current task")
        } catch { }
        await MainActor.run { updater.setBusy(false) }
        try await updater.disconnectGitHub()
    }
}
