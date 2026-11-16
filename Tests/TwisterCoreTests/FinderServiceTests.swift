import XCTest
import AppKit
@testable import TwisterCore

final class FinderServiceTests:XCTestCase {
    private var root:URL!,board:NSPasteboard!
    override func setUpWithError() throws {
        root=try OutputFiles.temporaryDirectory().standardizedFileURL
        board=NSPasteboard.withUniqueName()
    }
    override func tearDownWithError() throws { board.releaseGlobally();try? FileManager.default.removeItem(at:root) }
    private func file(_ name:String) throws -> URL {
        let url=root.appendingPathComponent(name)
        try Data("fixture".utf8).write(to:url)
        return url.standardizedFileURL
    }
    private func write(_ urls:[URL]) { board.clearContents();XCTAssertTrue(board.writeObjects(urls as [NSURL])) }
    private let presets=[
        Preset(name:"To JPEG",operation:.convert("jpg")),Preset(name:"Shrink",operation:.tool(.compress)),
        Preset(name:"Merge",operation:.tool(.mergePDF)),Preset(name:"Join",operation:.tool(.joinVideos))
    ]

    func testFileURLsBecomeARequestInOrderAndOnce() throws {
        let a=try file("b first.png"),b=try file("a second.png")
        write([a,b,a,root.appendingPathComponent("missing.png")])
        board.writeObjects([NSURL(string:"https://example.com/picture.png")!])
        let request=try FinderServiceRequest(.open,pasteboard:board,presets:presets)
        XCTAssertEqual(request.files,[a,b]);XCTAssertEqual(request.service,.open)
        XCTAssertTrue(request.formats.isEmpty);XCTAssertTrue(request.presets.isEmpty)
    }

    func testLegacyFileNameListsAreRead() throws {
        let a=try file("a.png")
        board.clearContents();board.declareTypes([NSPasteboard.PasteboardType("NSFilenamesPboardType")],owner:nil)
        XCTAssertTrue(board.setPropertyList([a.path],forType:NSPasteboard.PasteboardType("NSFilenamesPboardType")))
        XCTAssertEqual(FinderServiceRequest.files(on:board),[a])
    }

    func testAPasteboardWithoutFilesIsRefused() throws {
        board.clearContents();board.setString("Just text",forType:.string)
        for service in FinderService.allCases {
            XCTAssertThrowsError(try FinderServiceRequest(service,pasteboard:board,presets:presets)) { XCTAssertEqual($0 as? FinderServiceError,.noFiles) }
        }
        board.clearContents();board.writeObjects([NSURL(string:"https://example.com/a.png")!])
        XCTAssertThrowsError(try FinderServiceRequest(.open,pasteboard:board))
    }

    func testConvertOffersTheFormatsSharedByEveryFile() throws {
        let png=try file("a.png"),jpg=try file("b.jpg"),video=try file("c.mp4"),unknown=try file("d.xyz")
        write([png,jpg])
        XCTAssertEqual(try FinderServiceRequest(.convert,pasteboard:board).formats,FeatureCatalog.formats(for:[png,jpg]))
        XCTAssertFalse(try FinderServiceRequest(.convert,pasteboard:board).formats.contains("jpg"))
        for files in [[png,video],[unknown]] {
            write(files)
            XCTAssertThrowsError(try FinderServiceRequest(.convert,pasteboard:board)) { XCTAssertEqual($0 as? FinderServiceError,.noFormats) }
            XCTAssertEqual(try FinderServiceRequest(.open,pasteboard:board).files,files)
        }
    }

    func testThePresetServiceOffersOnlyPresetsThatFitEveryFile() throws {
        let png=try file("a.png"),pdf=try file("b.pdf"),other=try file("c.pdf"),unknown=try file("d.xyz")
        func names(_ files:[URL]) throws -> [String] { write(files);return try FinderServiceRequest(.preset,pasteboard:board,presets:presets).presets.map(\.name) }
        XCTAssertEqual(try names([png]),["To JPEG","Shrink"])
        XCTAssertEqual(try names([pdf,other]),["To JPEG","Shrink","Merge"])
        XCTAssertEqual(try names([png,pdf]),["To JPEG","Shrink"])
        XCTAssertThrowsError(try names([unknown])) { XCTAssertEqual($0 as? FinderServiceError,.noPresets) }
        write([png])
        XCTAssertThrowsError(try FinderServiceRequest(.preset,pasteboard:board,presets:[])) { XCTAssertEqual($0 as? FinderServiceError,.noPresets) }
    }

    /// Info.plist, the receiver selectors and both menu tables must name the same three entries.
    func testInfoPlistDeclaresEveryServiceForFilesWithLocalizedTitles() throws {
        let repository=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let info=try XCTUnwrap(NSDictionary(contentsOf:repository.appendingPathComponent("Resources/Info.plist")))
        let services=try XCTUnwrap(info["NSServices"] as? [[String:Any]])
        XCTAssertEqual(services.map { $0["NSMessage"] as? String },FinderService.allCases.map(\.rawValue))
        XCTAssertEqual(services.map { ($0["NSMenuItem"] as? [String:String])?["default"] },FinderService.allCases.map(\.menuTitle))
        for service in services {
            XCTAssertEqual(service["NSPortName"] as? String,info["CFBundleName"] as? String)
            XCTAssertEqual(service["NSSendFileTypes"] as? [String],["public.item"])
            XCTAssertNotNil(service["NSRequiredContext"])
            XCTAssertNil(service["NSReturnTypes"])
        }
        for language in ["en","tr"] {
            let table=try XCTUnwrap(NSDictionary(contentsOf:repository.appendingPathComponent("Resources/Localizations/\(language).lproj/ServicesMenu.strings")) as? [String:String])
            XCTAssertEqual(Set(table.keys),Set(FinderService.allCases.map(\.menuTitle)))
            for (title,value) in table { XCTAssertEqual(value != title,language=="tr",title) }
        }
    }
}
