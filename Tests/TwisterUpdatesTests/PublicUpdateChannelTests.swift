import XCTest
@testable import TwisterUpdates

final class PublicUpdateChannelTests:XCTestCase {
    private let info:[String:Any]=["TwisterPublicUpdateRepository":"baypeanut/twister","SUFeedURL":"https://github.com/baypeanut/twister/releases/latest/download/appcast.xml"]
    private final class NoCredentials:UpdateCredentialStore,@unchecked Sendable {
        func token(for repository:GitHubRepository) throws->String { XCTFail("Anonymous migration read a private token");throw UpdateCredentialError.missing }
        func save(_ token:String,for repository:GitHubRepository) throws { XCTFail("Anonymous migration wrote a credential") }
        func remove(for repository:GitHubRepository) throws { XCTFail("Anonymous migration deleted a credential") }
    }
    func testOfficialChannelRequiresExactBundledFeed() {
        XCTAssertNotNil(PublicUpdateChannel(info:info))
        for address in ["http://github.com/baypeanut/twister/releases/latest/download/appcast.xml","https://github.com/attacker/twister-app/releases/latest/download/appcast.xml","https://github.com/baypeanut/twister/releases/latest/download/appcast.xml?token=x"] {
            var altered=info;altered["SUFeedURL"]=address;XCTAssertNil(PublicUpdateChannel(info:altered))
        }
    }
    func testNewUsersAndLegacyUsersDoNotTouchCredentials() async {
        for previous in [nil,"baypeanut/twister"] as [String?] {
            let suite="TwisterPublicChannelTests.\(UUID())",defaults=UserDefaults(suiteName:suite)!
            defer { defaults.removePersistentDomain(forName:suite) }
            if let previous { defaults.set(previous,forKey:"TwisterUpdateGitHubRepository");defaults.set(true,forKey:"TwisterUpdateGitHubRequiresToken");defaults.set(true,forKey:"TwisterUpdateGitHubSavedToken") }
            defaults.set("retained",forKey:"history");defaults.set(false,forKey:"TwisterUpdateGitHubAutomaticChecks")
            await MainActor.run {
                let updater=AppUpdater(credentials:NoCredentials(),defaults:defaults,info:info)
                XCTAssertNil(updater.repository);XCTAssertFalse(updater.requiresToken);XCTAssertFalse(updater.hasSavedToken)
                XCTAssertEqual(updater.officialRepository?.slug,"baypeanut/twister")
            }
            XCTAssertEqual(defaults.string(forKey:"history"),"retained")
            if previous != nil { XCTAssertEqual(defaults.object(forKey:"SUEnableAutomaticChecks") as? Bool,false) }
        }
    }
    func testUnrelatedCustomChannelIsPreserved() async {
        let suite="TwisterPublicChannelTests.\(UUID())",defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set("example/custom",forKey:"TwisterUpdateGitHubRepository");defaults.set(true,forKey:"TwisterUpdateGitHubRequiresToken")
        await MainActor.run {
            let updater=AppUpdater(credentials:NoCredentials(),defaults:defaults,info:info)
            XCTAssertEqual(updater.repository?.slug,"example/custom");XCTAssertTrue(updater.requiresToken)
        }
    }
}
