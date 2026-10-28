import XCTest
@testable import TwisterCore

final class ArchiveSymlinkBoundaryTests: XCTestCase {
    func testDeferredLinksCannotCreateDirectoriesOutsideExtractionRoot() throws {
        let manager = FileManager.default
        let fixture = try OutputFiles.temporaryDirectory()
        defer { try? manager.removeItem(at: fixture) }
        let archive = fixture.appendingPathComponent("hostile.tar")
        let extraction = fixture.appendingPathComponent("staging/root", isDirectory: true)
        // The first link aliases root. The next link would then be created at
        // root/escape and resolve to fixture. A third entry used to create a
        // directory in fixture before the final link check rejected the archive.
        try tar(links: [
            ("deep/dir/zero", "../.."),
            ("deep/dir/zero/escape", "../.."),
            ("deep/dir/zero/escape/leaked/payload", "target")
        ]).write(to: archive)

        XCTAssertThrowsError(try ArchiveCodec.extract(archive, into: extraction, token: .init()))
        XCTAssertFalse(manager.fileExists(atPath: fixture.appendingPathComponent("leaked").path))
        XCTAssertFalse(manager.fileExists(atPath: extraction.appendingPathComponent("escape").path))
    }

    func testOrdinaryRelativeSymlinksStillExtract() throws {
        let manager = FileManager.default
        let fixture = try OutputFiles.temporaryDirectory()
        defer { try? manager.removeItem(at: fixture) }
        let archive = fixture.appendingPathComponent("links.tar")
        let extraction = fixture.appendingPathComponent("output", isDirectory: true)
        try tar(links: [("nested/link", "../target"), ("alias", "nested/link")]).write(to: archive)

        try ArchiveCodec.extract(archive, into: extraction, token: .init())
        XCTAssertEqual(try manager.destinationOfSymbolicLink(atPath: extraction.appendingPathComponent("nested/link").path), "../target")
        XCTAssertEqual(try manager.destinationOfSymbolicLink(atPath: extraction.appendingPathComponent("alias").path), "nested/link")
    }

    private func tar(links: [(String, String)]) -> Data {
        var archive = Data()
        for (path, target) in links {
            var header = [UInt8](repeating: 0, count: 512)
            func field(_ value: String, at offset: Int, length: Int) {
                for (index, byte) in value.utf8.prefix(length).enumerated() { header[offset + index] = byte }
            }
            field(path, at: 0, length: 100)
            field("0000777", at: 100, length: 8)
            field("0000000", at: 108, length: 8)
            field("0000000", at: 116, length: 8)
            field("00000000000", at: 124, length: 12)
            field("00000000000", at: 136, length: 12)
            field("        ", at: 148, length: 8)
            field("2", at: 156, length: 1)
            field(target, at: 157, length: 100)
            field("ustar", at: 257, length: 6)
            field("00", at: 263, length: 2)
            let checksum = header.reduce(0) { $0 + Int($1) }
            field(String(format: "%06o", checksum), at: 148, length: 6)
            header[154] = 0; header[155] = 32
            archive.append(contentsOf: header)
        }
        archive.append(Data(repeating: 0, count: 1024))
        return archive
    }
}
