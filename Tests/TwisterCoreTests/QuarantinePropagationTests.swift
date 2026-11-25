import XCTest
import Darwin
import CoreServices
@testable import TwisterCore

final class QuarantinePropagationTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws { root = try OutputFiles.temporaryDirectory() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// A value as a browser writes it, including the user-approved flag.
    private let browserValue = Data("00c3;6745a1b2;Safari;1C0D4E2B-6F1A-4C33-9E33-4F8A3C9B2D10".utf8)

    private func quarantine(_ url: URL, _ value: Data) throws {
        let status = value.withUnsafeBytes { setxattr(url.path, Quarantine.attribute, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW) }
        XCTAssertEqual(status, 0)
    }

    private func commandArchive() throws -> URL {
        let source = root.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Docs"), withIntermediateDirectories: true)
        let command = source.appendingPathComponent("Read Me.command")
        try Data("#!/bin/sh\necho hello\n".utf8).write(to: command)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: command.path)
        try Data("notes".utf8).write(to: source.appendingPathComponent("Docs/notes.txt"))
        let archive = root.appendingPathComponent("pkg.zip")
        try ArchiveCodec.create(from: source, at: archive, format: "zip", token: .init())
        return archive
    }

    func testEveryExtractedEntryKeepsTheArchiveQuarantine() throws {
        let archive = try commandArchive()
        try quarantine(archive, browserValue)
        let destination = root.appendingPathComponent("out", isDirectory: true)
        var options = OperationOptions(); options.outputDirectory = destination
        let outputs = try ConversionEngine.run(.init(inputs: [archive], operation: .tool(.extractArchive), options: options))
        let folder = try XCTUnwrap(outputs.first)
        let expected = Data("0083;6745a1b2;Safari;1C0D4E2B-6F1A-4C33-9E33-4F8A3C9B2D10".utf8)
        for item in [folder, folder.appendingPathComponent("Read Me.command"), folder.appendingPathComponent("Docs"), folder.appendingPathComponent("Docs/notes.txt")] {
            XCTAssertEqual(Quarantine.value(of: item), expected, item.lastPathComponent)
        }
        // Gatekeeper reads the same attribute through the resource value.
        let properties = try folder.appendingPathComponent("Read Me.command").resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties
        XCTAssertEqual(properties?[kLSQuarantineAgentNameKey as String] as? String, "Safari")
    }

    func testReadOnlyEntriesOfAQuarantinedArchiveExtractWithTheLabel() throws {
        let source = root.appendingPathComponent("read-only", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let readme = source.appendingPathComponent("README")
        try Data("read only".utf8).write(to: readme)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: readme.path)
        let archive = root.appendingPathComponent("read-only.zip")
        try ArchiveCodec.create(from: source, at: archive, format: "zip", token: .init())
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: readme.path)
        try quarantine(archive, browserValue)
        var options = OperationOptions(); options.outputDirectory = root.appendingPathComponent("read-only out", isDirectory: true)
        let folder = try XCTUnwrap(ConversionEngine.run(.init(inputs: [archive], operation: .tool(.extractArchive), options: options)).first)
        let extracted = folder.appendingPathComponent("README")
        XCTAssertEqual(try Data(contentsOf: extracted), Data("read only".utf8))
        XCTAssertNotNil(Quarantine.value(of: extracted))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: extracted.path)[.posixPermissions] as? NSNumber)?.intValue, 0o444)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: extracted.path)
    }

    func testCommandLineExtractionAndConversionKeepTheQuarantine() throws {
        let archive = try commandArchive()
        try quarantine(archive, browserValue)
        let destination = root.appendingPathComponent("cli", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let options = String(decoding: try JSONSerialization.data(withJSONObject: ["outputDirectory": destination.path]), as: UTF8.self)
        var printed: [String] = []
        XCTAssertEqual(TwisterCommandLine.run(arguments: ["twister-cli", "tool", "extractArchive", "--options", options, "--", archive.path], output: { printed.append($0) }, errorOutput: { _ in }), 0)
        let folder = URL(fileURLWithPath: try XCTUnwrap(printed.first))
        XCTAssertNotNil(Quarantine.value(of: folder.appendingPathComponent("Read Me.command")))

        printed = []
        XCTAssertEqual(TwisterCommandLine.run(arguments: ["twister-cli", "convert", "tar", "--options", options, "--", archive.path], output: { printed.append($0) }, errorOutput: { _ in }), 0)
        XCTAssertNotNil(Quarantine.value(of: URL(fileURLWithPath: try XCTUnwrap(printed.first))))
    }

    func testAnUnlabelledInputProducesUnlabelledOutputs() throws {
        let archive = try commandArchive()
        var options = OperationOptions(); options.outputDirectory = root.appendingPathComponent("plain", isDirectory: true)
        let folder = try XCTUnwrap(ConversionEngine.run(.init(inputs: [archive], operation: .tool(.extractArchive), options: options)).first)
        XCTAssertNil(Quarantine.value(of: folder.appendingPathComponent("Read Me.command")))
    }

    func testDownloadsReceiveTheirOwnQuarantineWithTheSource() throws {
        let file = root.appendingPathComponent("clip.mp4")
        try Data("media".utf8).write(to: file)
        let source = URL(string: "https://media.example.com/clip.mp4")!, page = URL(string: "https://example.com/watch")!
        try Quarantine.markDownloaded([file], data: source, origin: page)
        let properties = try XCTUnwrap(try file.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties)
        XCTAssertEqual(properties[kLSQuarantineAgentNameKey as String] as? String, "Twister")
        XCTAssertEqual(properties[kLSQuarantineTypeKey as String] as? String, kLSQuarantineTypeWebDownload as String)
        // The source addresses go to the system's quarantine event record,
        // which macOS may not return; the attribute itself is what Gatekeeper reads.
        XCTAssertNotNil(Quarantine.value(of: file))
    }

    /// Helper processes unpack their own runtimes, which the system refuses
    /// to load once quarantined. Outputs are labelled explicitly instead.
    func testTheApplicationDoesNotQuarantineEverythingItsHelpersCreate() throws {
        let plist = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Info.plist")
        let info = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any])
        XCTAssertNil(info["LSFileQuarantineEnabled"])
    }

    func testVerifiedToolDownloadsAreNotLeftQuarantined() throws {
        let stage = root.appendingPathComponent("stage", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        let download = stage.appendingPathComponent("download-0")
        let bytes = Data("#!/bin/sh\nexit 0\n".utf8)
        try bytes.write(to: download)
        try quarantine(download, Data("0083;6745a1b2;Twister;".utf8))
        let digest = SHA256Digest.hex(bytes)
        try ExternalToolSetup.place(.init(name: "helper", url: "https://example.com/helper", download: digest, member: nil), download: download, in: stage, unpack: stage.appendingPathComponent("unpack"), token: .init())
        XCTAssertNil(Quarantine.value(of: stage.appendingPathComponent("helper")))
    }
}

import CryptoKit
enum SHA256Digest {
    static func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
