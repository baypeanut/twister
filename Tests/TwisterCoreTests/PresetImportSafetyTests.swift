import XCTest
@testable import TwisterCore

final class PresetImportSafetyTests: XCTestCase {
    func testAnImportedPresetNamesNoFolderAndNoLocalFiles() throws {
        var options = OperationOptions()
        options.quality = 0.4
        options.visualizationImage = URL(fileURLWithPath: "/Volumes/Shared/Pictures/cover.png")
        var frame = ImageFrameOptions(); frame.backdrop = .image; frame.backgroundImage = URL(fileURLWithPath: "/Volumes/Shared/Pictures/private.png"); frame.padding = 40
        options.imageFrame = frame
        var collage = CollageOptions(); collage.backgroundImage = URL(fileURLWithPath: "/Volumes/Shared/Pictures/other.png"); collage.columns = 3
        options.collage = collage
        var stamp = ImageAnnotation(kind: .image, rect: .init(x: 0, y: 0, width: 10, height: 10)); stamp.imageURL = URL(fileURLWithPath: "/Volumes/Shared/Pictures/stamp.png")
        var label = ImageAnnotation(kind: .text, rect: .init(x: 1, y: 2, width: 30, height: 12)); label.text = "Draft"
        options.imageAnnotations = [stamp, label]
        // An exported file from someone else, naming a folder on this Mac.
        let shared = Preset(name: "Shared frame", operation: .tool(.frameImage), options: options, destination: .folder(URL(fileURLWithPath: "/Volumes/Shared/LaunchAgents", isDirectory: true)))
        var library = PresetLibrary()
        let imported = try XCTUnwrap(try library.importPresets(from: PresetLibrary.exportData([shared])).first)
        XCTAssertNil(imported.destination)
        XCTAssertNil(imported.options.visualizationImage)
        XCTAssertNil(imported.options.imageFrame?.backgroundImage)
        XCTAssertEqual(imported.options.imageFrame?.backdrop, .solid)
        XCTAssertEqual(imported.options.imageFrame?.padding, 40)
        XCTAssertNil(imported.options.collage?.backgroundImage)
        XCTAssertEqual(imported.options.collage?.columns, 3)
        XCTAssertEqual(imported.options.imageAnnotations.map(\.text), ["Draft"])
        XCTAssertEqual(imported.options.quality, 0.4)
        // The request follows the caller's own destination.
        let fallback = URL(fileURLWithPath: "/tmp/Exports", isDirectory: true)
        XCTAssertEqual(try imported.request(for: [URL(fileURLWithPath: "/tmp/a.png")], fallback: fallback).options.outputDirectory, fallback)
    }

    func testPresetsSavedByTheUserKeepTheirFolder() throws {
        let root = try OutputFiles.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = PresetStore(url: root.appendingPathComponent("Presets.json"))
        try store.update { try $0.add(Preset(name: "Mine", operation: .convert("jpg"), destination: .folder(root))) }
        XCTAssertEqual(try store.load().find("Mine").destination, .folder(root))
    }
}
