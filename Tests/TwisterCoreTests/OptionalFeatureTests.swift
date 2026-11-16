import XCTest
@testable import TwisterCore

final class OptionalFeatureTests:XCTestCase {
    private let none=ToolSetupStatus(mediaReady:false,webReady:false,officeReady:false)
    private let mediaOnly=ToolSetupStatus(mediaReady:true,webReady:false,officeReady:true)
    private let all=ToolSetupStatus(mediaReady:true,webReady:true,officeReady:true)

    func testWebDownloadsWaitForTheirToolsWithAnInstallAction() {
        XCTAssertEqual(WebDownloadGate.availability(included:true,preference:nil,status:mediaOnly),.needsTools([.web]))
        XCTAssertEqual(WebDownloadGate.availability(included:true,preference:true,status:mediaOnly),.needsTools([.web]))
        XCTAssertEqual(WebDownloadGate.availability(included:true,preference:nil,status:none),.needsTools([.media,.web]))
        XCTAssertEqual(WebDownloadGate.availability(included:true,preference:true,status:ToolSetupStatus(mediaReady:false,webReady:true,officeReady:false)),.needsTools([.media]))
        XCTAssertEqual(WebDownloadGate.availability(included:true,preference:nil,status:ToolSetupStatus(mediaReady:true,webReady:true,officeReady:false)),.ready)
    }
    func testSettingFollowsInstalledToolsUntilTheUserDecides() {
        XCTAssertFalse(WebDownloadGate.isOn(preference:nil,status:mediaOnly))
        XCTAssertTrue(WebDownloadGate.isOn(preference:nil,status:all))
        XCTAssertEqual(WebDownloadGate.availability(included:true,preference:nil,status:all),.ready)
        XCTAssertTrue(WebDownloadGate.isOn(preference:true,status:mediaOnly))
        XCTAssertFalse(WebDownloadGate.isOn(preference:false,status:all))
        XCTAssertEqual(WebDownloadGate.availability(included:true,preference:false,status:all),.off)
        XCTAssertEqual(WebDownloadGate.availability(included:true,preference:false,status:none),.off)
    }
    func testStoredSettingIsReadOnlyWhenTheUserWroteOne() {
        let suite="Twister.Tests."+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        XCTAssertNil(WebDownloadGate.preference(in:defaults))
        defaults.set(false,forKey:WebDownloadGate.preferenceKey);XCTAssertEqual(WebDownloadGate.preference(in:defaults),false)
        defaults.set(true,forKey:WebDownloadGate.preferenceKey);XCTAssertEqual(WebDownloadGate.preference(in:defaults),true)
        defaults.removeObject(forKey:WebDownloadGate.preferenceKey);XCTAssertNil(WebDownloadGate.preference(in:defaults))
    }
    func testBuildSwitchRemovesTheDownloaderOnlyWhenWrittenAsFalse() {
        XCTAssertTrue(WebDownloadGate.buildIncludesDownloader(nil))
        XCTAssertTrue(WebDownloadGate.buildIncludesDownloader([:]))
        XCTAssertTrue(WebDownloadGate.buildIncludesDownloader(["TwisterWebDownloads":true]))
        XCTAssertTrue(WebDownloadGate.buildIncludesDownloader(["TwisterWebDownloads":"no"]))
        XCTAssertFalse(WebDownloadGate.buildIncludesDownloader(["TwisterWebDownloads":false]))
        for preference in [nil,true,false] as [Bool?] {
            XCTAssertEqual(WebDownloadGate.availability(included:false,preference:preference,status:all),.excluded)
        }
    }
    func testBuildScriptWritesTheSwitchTheAppReads() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script=try String(contentsOf:root.appendingPathComponent("scripts/build-app.sh"),encoding:.utf8)
        XCTAssertTrue(script.contains("TWISTER_WEB_DOWNLOADS"))
        XCTAssertTrue(script.contains("plutil -replace \(WebDownloadGate.buildKey) -bool false"))
    }

    func testWindowArrangementIsOffUntilTheUserTurnsItOn() {
        XCTAssertFalse(WindowArrangementPreference.isOn(appEnabled:true,stored:nil))
        XCTAssertFalse(WindowArrangementPreference.isOn(appEnabled:true,stored:false))
        XCTAssertFalse(WindowArrangementPreference.isOn(appEnabled:true,stored:"yes"))
        XCTAssertTrue(WindowArrangementPreference.isOn(appEnabled:true,stored:true))
        XCTAssertTrue(WindowArrangementPreference.isOn(appEnabled:true,stored:NSNumber(value:true)))
        XCTAssertFalse(WindowArrangementPreference.isOn(appEnabled:false,stored:true))
    }
    func testExistingWindowArrangementChoiceSurvivesAndNewInstallsStayOff() {
        let suite="Twister.Tests."+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.register(defaults:["enabled":true])
        XCTAssertFalse(WindowArrangementPreference.isOn(in:defaults),"A new install has no stored choice")
        defaults.set(true,forKey:"windowManagementEnabled")
        XCTAssertTrue(WindowArrangementPreference.isOn(in:defaults),"A user who enabled it keeps it")
        defaults.set(false,forKey:"enabled");XCTAssertFalse(WindowArrangementPreference.isOn(in:defaults))
        defaults.set(true,forKey:"enabled");defaults.set(false,forKey:"windowManagementEnabled")
        XCTAssertFalse(WindowArrangementPreference.isOn(in:defaults))
    }
    func testDisabledFeatureCreatesNoTimer() {
        var created=0,stopped=0
        var polling:OptionalPolling<Int>?=OptionalPolling(start:{ created+=1;return created },stop:{ _ in stopped+=1 })
        polling?.set(WindowArrangementPreference.isOn(appEnabled:true,stored:nil))
        polling?.set(false)
        XCTAssertEqual([created,stopped],[0,0]);XCTAssertEqual(polling?.isRunning,false)
        polling?.set(WindowArrangementPreference.isOn(appEnabled:true,stored:true));polling?.set(true)
        XCTAssertEqual([created,stopped],[1,0]);XCTAssertEqual(polling?.isRunning,true)
        polling?.set(false);polling?.set(false)
        XCTAssertEqual([created,stopped],[1,1]);XCTAssertEqual(polling?.isRunning,false)
        polling?.set(true);polling=nil
        XCTAssertEqual([created,stopped],[2,2],"Releasing the owner stops its timer")
    }
}
