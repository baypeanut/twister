import XCTest
@testable import TwisterCore

final class ToolVerificationTests: XCTestCase {
    private let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private var root: URL!
    override func setUpWithError() throws { root = try OutputFiles.temporaryDirectory() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root); VerifiedTools.shared.removeAll() }

    func testBuildScriptsPinTheSameExecutablesAsSetup() throws {
        let script = try String(contentsOf: repository.appendingPathComponent("scripts/tool-pins.sh"), encoding: .utf8)
        func table(_ name: String) throws -> [String: String] {
            let body = try XCTUnwrap(script.range(of: "typeset -gA \(name)=(\n").flatMap { start in script[start.upperBound...].range(of: "\n)").map { script[start.upperBound..<$0.lowerBound] } })
            return Dictionary(uniqueKeysWithValues: body.split(separator: "\n").map { line in
                let parts = line.split(separator: " ").map(String.init); return (parts[0], parts[1])
            })
        }
        XCTAssertEqual(try table("twister_tool_sha256"), Dictionary(uniqueKeysWithValues: ["ffmpeg", "ffprobe", "yt-dlp", "deno"].map { ($0, ExternalToolSetup.pinnedDigest($0)!) }))
        XCTAssertEqual(try table("twister_archive_sha256"), Dictionary(uniqueKeysWithValues: ExternalToolSetup.mediaPackages.map { ($0.name, $0.download) }))
        XCTAssertTrue(script.contains("twister_libreoffice_team=\(ExternalToolSetup.officeTeam)"))
        XCTAssertTrue(script.contains("twister_libreoffice_version=\(ExternalToolSetup.officeVersion)\n"))
    }

    func testAnInstalledToolThatNoLongerMatchesItsPinIsNotRun() throws {
        let tool = root.appendingPathComponent("ffmpeg")
        try Data("#!/bin/sh\necho replaced\n".utf8).write(to: tool)
        XCTAssertThrowsError(try ExternalToolSetup.verifyInstalled(tool, tool: "ffmpeg")) { error in
            XCTAssertTrue(error.localizedDescription.hasPrefix("The installed ffmpeg no longer matches"), error.localizedDescription)
        }
        XCTAssertThrowsError(try ExternalToolSetup.verifyInstalled(tool, tool: "unknown"))
    }

    func testAVerifiedToolIsCheckedAgainAfterItChanges() throws {
        let original = repository.appendingPathComponent("Tools/yt-dlp")
        guard FileManager.default.fileExists(atPath: original.path) else { throw XCTSkip("Run scripts/setup-web-download-tools.py first") }
        let tool = root.appendingPathComponent("yt-dlp")
        try FileManager.default.copyItem(at: original, to: tool)
        try ExternalToolSetup.verifyInstalled(tool, tool: "yt-dlp")
        try ExternalToolSetup.verifyInstalled(tool, tool: "yt-dlp")
        let handle = try FileHandle(forWritingTo: tool); try handle.seekToEnd(); try handle.write(contentsOf: Data([0])); try handle.close()
        XCTAssertThrowsError(try ExternalToolSetup.verifyInstalled(tool, tool: "yt-dlp"))
    }

    func testAToolRewrittenInPlaceWithItsOldTimestampIsCheckedAgain() throws {
        let original = repository.appendingPathComponent("Tools/yt-dlp")
        guard FileManager.default.fileExists(atPath: original.path) else { throw XCTSkip("Run scripts/setup-web-download-tools.py first") }
        let tool = root.appendingPathComponent("yt-dlp")
        try FileManager.default.copyItem(at: original, to: tool)
        try ExternalToolSetup.verifyInstalled(tool, tool: "yt-dlp")
        var before = stat(); XCTAssertEqual(stat(tool.path, &before), 0)
        // Same inode, same size, and the modification time put back.
        let handle = try FileHandle(forUpdating: tool)
        try handle.seek(toOffset: 4096); let byte = try XCTUnwrap(handle.read(upToCount: 1))
        try handle.seek(toOffset: 4096); try handle.write(contentsOf: Data([byte[0] ^ 0xFF])); try handle.close()
        var times = [timespec(tv_sec: before.st_atimespec.tv_sec, tv_nsec: before.st_atimespec.tv_nsec), timespec(tv_sec: before.st_mtimespec.tv_sec, tv_nsec: before.st_mtimespec.tv_nsec)]
        XCTAssertEqual(utimensat(AT_FDCWD, tool.path, &times, 0), 0)
        var after = stat(); XCTAssertEqual(stat(tool.path, &after), 0)
        XCTAssertEqual([after.st_ino, UInt64(after.st_size)], [before.st_ino, UInt64(before.st_size)])
        XCTAssertEqual(after.st_mtimespec.tv_nsec, before.st_mtimespec.tv_nsec)
        XCTAssertThrowsError(try ExternalToolSetup.verifyInstalled(tool, tool: "yt-dlp"))
    }

    func testTheOfficeBundleIsCheckedAgainWhenAnotherFileInsideChanges() throws {
        let original = repository.appendingPathComponent("Tools/LibreOffice.app")
        guard FileManager.default.fileExists(atPath: original.path) else { throw XCTSkip("LibreOffice is not in Tools") }
        // An APFS clone; the executable itself is never modified.
        let office = root.appendingPathComponent("LibreOffice.app")
        try FileManager.default.copyItem(at: original, to: office)
        let soffice = office.appendingPathComponent("Contents/MacOS/soffice")
        try ExternalToolSetup.verifyInstalled(soffice, tool: "soffice")
        let resources = office.appendingPathComponent("Contents/Resources")
        let resource = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.sorted { $0.path < $1.path }.first)
        let handle = try FileHandle(forWritingTo: resource); try handle.seekToEnd(); try handle.write(contentsOf: Data([0])); try handle.close()
        XCTAssertThrowsError(try ExternalToolSetup.verifyInstalled(soffice, tool: "soffice"))
    }

    func testOfficeToolsMustCarryThePublishersSignature() throws {
        let candidates = [repository.appendingPathComponent("Tools/LibreOffice.app"), URL(fileURLWithPath: "/Applications/LibreOffice.app")]
        guard let office = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { throw XCTSkip("LibreOffice is not installed") }
        XCTAssertNoThrow(try ExternalToolSetup.verifySignature(office, team: ExternalToolSetup.officeTeam))
        XCTAssertThrowsError(try ExternalToolSetup.verifySignature(office, team: "AAAAAAAAAA"))
        let copy = root.appendingPathComponent("Unsigned.app/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: copy.appendingPathComponent("soffice"))
        XCTAssertThrowsError(try ExternalToolSetup.verifySignature(root.appendingPathComponent("Unsigned.app"), team: ExternalToolSetup.officeTeam))
    }

    func testDebugAndCommandLineBuildsHonorOverrides() {
        XCTAssertTrue(Dependencies.honorsOverrides)
        XCTAssertEqual(Dependencies.override("ffmpeg", environment: ["TWISTER_FFMPEG": "/tmp/ffmpeg"]), "/tmp/ffmpeg")
        XCTAssertNil(Dependencies.override("ffmpeg", environment: ["TWISTER_FFMPEG": ""]))
    }

    func testOfficeProfilesNeverUpdateLinks() throws {
        let settings = DocumentEngine.officeProfileSettings
        XCTAssertFalse(settings.contains("UpdateLinkMode"))
        let document = try XMLDocument(xmlString: settings, options: [.nodeLoadExternalEntitiesNever])
        func value(_ path: String, _ name: String) throws -> String? {
            try document.nodes(forXPath: "//*[local-name()='item'][@*[local-name()='path']='\(path)']/*[local-name()='prop'][@*[local-name()='name']='\(name)']/*[local-name()='value']").first?.stringValue
        }
        XCTAssertEqual(try value("/org.openoffice.Office.Writer/Content/Update", "Link"), "0")
        XCTAssertEqual(try value("/org.openoffice.Office.Calc/Content/Update", "Link"), "1")
        XCTAssertEqual(try value("/org.openoffice.Office.Common/Security/Scripting", "MacroSecurityLevel"), "3")
    }

    func testTheOfficeDownloadIsTheCurrentPinnedRelease() {
        XCTAssertEqual(ExternalToolSetup.officePackage.url, "https://download.documentfoundation.org/libreoffice/stable/\(ExternalToolSetup.officeVersion)/mac/aarch64/LibreOffice_\(ExternalToolSetup.officeVersion)_MacOS_aarch64.dmg")
        XCTAssertEqual(ToolStore.pinnedVersions[.office], "LibreOffice \(ExternalToolSetup.officeVersion)")
        XCTAssertEqual(ToolStore.officeDirectory, "office-\(ExternalToolSetup.officeVersion)")
        XCTAssertTrue(ToolStore.executablePaths("soffice").contains("office-26.8.1/LibreOffice.app/Contents/MacOS/soffice"))
    }
}
