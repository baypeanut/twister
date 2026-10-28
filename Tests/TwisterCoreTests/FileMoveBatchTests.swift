import XCTest
@testable import TwisterCore

final class FileMoveBatchTests: XCTestCase {
    func testCaseFoldedBatchNamesReceiveSeparateDestinations() throws {
        let root = try OutputFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let left=root.appendingPathComponent("left"),right=root.appendingPathComponent("right"),destination=root.appendingPathComponent("out")
        for folder in [left,right,destination] { try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false) }
        let first=left.appendingPathComponent("report.txt"),second=right.appendingPathComponent("REPORT.txt")
        try Data("first".utf8).write(to:first);try Data("second".utf8).write(to:second)
        let result=FileMoveBatch.run([first,second],to:destination)
        XCTAssertNil(result.failure);XCTAssertEqual(result.moved.count,2)
        XCTAssertNotEqual(result.moved[first]?.lastPathComponent.lowercased(),result.moved[second]?.lastPathComponent.lowercased())
        XCTAssertEqual(try Data(contentsOf:XCTUnwrap(result.moved[first])),Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf:XCTUnwrap(result.moved[second])),Data("second".utf8))
    }
    func testPreflightFailureLeavesEarlierFilesUntouched() throws {
        let root = try OutputFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("original.txt")
        try Data("keep".utf8).write(to: file)
        let destination = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let result = FileMoveBatch.run([file, root.appendingPathComponent("missing.txt")], to: destination)
        XCTAssertNotNil(result.failure)
        XCTAssertTrue(result.moved.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), Data("keep".utf8))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

    func testCollisionsAndDuplicateSelectionsPreserveExistingFiles() throws {
        let root = try OutputFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let existing = destination.appendingPathComponent("notes.txt")
        try Data("existing".utf8).write(to: existing)
        let first = root.appendingPathComponent("notes.txt")
        try Data("new".utf8).write(to: first)
        let result = FileMoveBatch.run([first, first], to: destination)
        XCTAssertNil(result.failure)
        XCTAssertEqual(result.moved.count, 1)
        XCTAssertEqual(try Data(contentsOf: existing), Data("existing".utf8))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(result.moved[first])), Data("new".utf8))
    }

    func testSelectedParentAndChildAreRejectedBeforeMoving() throws {
        let root = try OutputFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder")
        let destination = root.appendingPathComponent("out")
        for path in [folder, destination] { try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false) }
        let child = folder.appendingPathComponent("child.txt")
        try Data("keep".utf8).write(to: child)
        let result = FileMoveBatch.run([folder, child], to: destination)
        XCTAssertNotNil(result.failure)
        XCTAssertTrue(result.moved.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.path))
    }
}
