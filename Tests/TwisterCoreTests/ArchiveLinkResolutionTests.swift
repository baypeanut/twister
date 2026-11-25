import XCTest
@testable import TwisterCore

/// A ustar writer for hostile archive fixtures.
struct TestTar {
    enum Kind { case file(Data), directory, link(String) }
    var entries: [(String, Kind)] = []
    mutating func file(_ path: String, _ text: String) { entries.append((path, .file(Data(text.utf8)))) }
    mutating func directory(_ path: String) { entries.append((path, .directory)) }
    mutating func link(_ path: String, _ target: String) { entries.append((path, .link(target))) }
    var data: Data {
        var archive = Data()
        for (path, kind) in entries {
            var header = [UInt8](repeating: 0, count: 512)
            func field(_ value: String, at offset: Int, length: Int) {
                for (index, byte) in value.utf8.prefix(length).enumerated() { header[offset + index] = byte }
            }
            var body = Data()
            field(path, at: 0, length: 100)
            switch kind {
            case .file(let data): body = data; field("0000644", at: 100, length: 8); field("0", at: 156, length: 1)
            case .directory: field("0000755", at: 100, length: 8); field("5", at: 156, length: 1)
            case .link(let target): field("0000777", at: 100, length: 8); field("2", at: 156, length: 1); field(target, at: 157, length: 100)
            }
            field("0000000", at: 108, length: 8)
            field("0000000", at: 116, length: 8)
            field(String(format: "%011o", body.count), at: 124, length: 12)
            field("00000000000", at: 136, length: 12)
            field("        ", at: 148, length: 8)
            field("ustar", at: 257, length: 6)
            field("00", at: 263, length: 2)
            let checksum = header.reduce(0) { $0 + Int($1) }
            field(String(format: "%06o", checksum), at: 148, length: 6)
            header[154] = 0; header[155] = 32
            archive.append(contentsOf: header)
            archive.append(body)
            if body.count % 512 != 0 { archive.append(Data(count: 512 - body.count % 512)) }
        }
        archive.append(Data(count: 1024))
        return archive
    }
}

final class ArchiveLinkResolutionTests: XCTestCase {
    private var fixture: URL!
    override func setUpWithError() throws { fixture = try OutputFiles.temporaryDirectory() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: fixture) }

    /// `B` points at its own folder, so `B/B/B/x/y/z` is physically `x/y/z`
    /// and six `..` leave the extraction folder although the text stays inside.
    private func selfLinkArchive(linkFirst: Bool) throws -> URL {
        var tar = TestTar()
        tar.directory("x"); tar.directory("x/y"); tar.directory("x/y/z")
        let links = [("secret", "B/B/B/x/y/z/../../../../../../outside/secret.txt"), ("B", ".")]
        for (path, target) in linkFirst ? links.reversed() : links { tar.link(path, target) }
        tar.file("readme.txt", "hello\n")
        let archive = fixture.appendingPathComponent("evil-\(linkFirst).tar")
        try tar.data.write(to: archive)
        return archive
    }

    func testALinkThatEscapesThroughASelfLinkIsRefused() throws {
        let outside = fixture.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("TOP SECRET\n".utf8).write(to: outside.appendingPathComponent("secret.txt"))
        for linkFirst in [false, true] {
            let extraction = fixture.appendingPathComponent("evil Extracted \(linkFirst)", isDirectory: true)
            XCTAssertThrowsError(try ArchiveCodec.extract(selfLinkArchive(linkFirst: linkFirst), into: extraction, token: .init())) { error in
                XCTAssertEqual(error.localizedDescription, "An archive link points outside the extraction folder.")
            }
        }
    }

    func testTheEscapeIsRefusedThroughTheExtractTool() throws {
        let destination = fixture.appendingPathComponent("Exports", isDirectory: true)
        var options = OperationOptions(); options.outputDirectory = destination
        XCTAssertThrowsError(try ConversionEngine.run(.init(inputs: [selfLinkArchive(linkFirst: false)], operation: .tool(.extractArchive), options: options)))
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? [], [])
    }

    func testInsideLinksIncludingParentStepsStillExtract() throws {
        var tar = TestTar()
        tar.directory("Kit.framework"); tar.directory("Kit.framework/Versions"); tar.directory("Kit.framework/Versions/A")
        tar.file("Kit.framework/Versions/A/Kit", "binary")
        tar.link("Kit.framework/Versions/Current", "A")
        tar.link("Kit.framework/Kit", "Versions/Current/Kit")
        tar.directory("lib")
        tar.link("lib/Kit", "../Kit.framework/Versions/Current/Kit")
        tar.link("here", ".")
        tar.link("pending", "later/file.txt")
        let archive = fixture.appendingPathComponent("kit.tar")
        try tar.data.write(to: archive)
        let extraction = fixture.appendingPathComponent("kit", isDirectory: true)
        try ArchiveCodec.extract(archive, into: extraction, token: .init())
        XCTAssertEqual(try String(contentsOf: extraction.appendingPathComponent("lib/Kit"), encoding: .utf8), "binary")
        XCTAssertEqual(try String(contentsOf: extraction.appendingPathComponent("here/Kit.framework/Kit"), encoding: .utf8), "binary")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: extraction.appendingPathComponent("pending").path), "later/file.txt")
    }

    func testDanglingTargetsThatClimbAndLinkLoopsAreRefused() throws {
        for (name, links) in [("climb", [("a", "missing/x/../../file")]), ("loop", [("a", "b"), ("b", "a")])] {
            var tar = TestTar()
            for (path, target) in links { tar.link(path, target) }
            let archive = fixture.appendingPathComponent("\(name).tar")
            try tar.data.write(to: archive)
            XCTAssertThrowsError(try ArchiveCodec.extract(archive, into: fixture.appendingPathComponent(name, isDirectory: true), token: .init()), name)
        }
    }

    func testRepackingRefusesAFolderWhoseLinkEscapes() throws {
        let source = fixture.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("x/y"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("B").path, withDestinationPath: ".")
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("secret").path, withDestinationPath: "B/B/x/y/../../../outside")
        XCTAssertThrowsError(try ArchiveCodec.create(from: source, at: fixture.appendingPathComponent("out.zip"), format: "zip", token: .init()))
    }
}
