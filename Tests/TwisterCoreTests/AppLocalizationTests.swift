import XCTest
@testable import TwisterCore

final class AppLocalizationTests:XCTestCase {
    func testPackagedCatalogIsFoundInsideRelocatedApplicationResources() throws {
        let root=try OutputFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at:root) }
        let resources=root.appendingPathComponent("Relocated Twister.app/Contents/Resources")
        let catalog=resources.appendingPathComponent("Twister_TwisterCore.bundle/Resources/Turkish.json")
        try FileManager.default.createDirectory(at:catalog.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("{}".utf8).write(to:catalog)
        XCTAssertEqual(AppLocalization.catalogURL(in:[resources]),catalog)
        XCTAssertNil(AppLocalization.catalogURL(in:[root.appendingPathComponent("missing")]))
    }
    func testEveryToolAndWindowPlacementHasTurkishCopy() {
        for source in Array(FeatureCatalog.toolNames.values)+ToolKind.allCases.map(\.title)+WindowPlacement.allCases.map(\.title) {
            XCTAssertNotEqual(AppLocalization.text(source,language:"tr"),source,source)
        }
        XCTAssertEqual(AppLocalization.text("Language",language:"tr"),"Dil")
        XCTAssertEqual(AppLocalization.text("Library",language:"tr"),"Kitaplık")
        XCTAssertEqual(AppLocalization.text("READ QR CODES",language:"tr"),"QR KODLARINI OKU")
        XCTAssertEqual(AppLocalization.text("Resize Image".uppercased(),language:"tr"),"GÖRSELİ BOYUTLANDIR")
    }
    func testFallbackAndFormattingKeepOriginalInput() {
        XCTAssertEqual(AppLocalization.normalizedLanguage(nil),"en")
        XCTAssertEqual(AppLocalization.normalizedLanguage("fr"),"en")
        XCTAssertEqual(AppLocalization.text("Library",language:"en"),"Library")
        XCTAssertTrue(AppLocalization.matches("Crop Image",query:"kırp",language:"tr"))
        XCTAssertTrue(AppLocalization.matches("Crop Image",query:"görsel",language:"tr"))
        XCTAssertEqual(AppLocalization.text("Home.png",language:"tr"),"Home.png")
        let path="Türkçe {0} $1 \\ image.png"
        XCTAssertEqual(AppLocalization.text("Original size: "+path,language:"tr"),"Orijinal boyut: "+path)
        XCTAssertEqual(AppLocalization.text("12 files are ready",language:"tr"),"12 dosya hazır")
    }
    func testBatchSummariesKeepEveryCount() {
        XCTAssertEqual(AppLocalization.text("9 of 9 done",language:"tr"),"9/9 tamamlandı")
        XCTAssertEqual(AppLocalization.text("7 of 9 done, 2 failed",language:"tr"),"7/9 tamamlandı, 2 başarısız")
        XCTAssertEqual(AppLocalization.text("3 of 9 done, 6 cancelled",language:"tr"),"3/9 tamamlandı, 6 iptal edildi")
        XCTAssertEqual(AppLocalization.text("3 of 9 done, 2 failed, 4 cancelled",language:"tr"),"3/9 tamamlandı, 2 başarısız, 4 iptal edildi")
        XCTAssertEqual(AppLocalization.text(BatchReport(items:[.init(inputs:[],status:.failed("x")),.init(inputs:[],status:.cancelled)]).summary,language:"tr"),"0/2 tamamlandı, 1 başarısız, 1 iptal edildi")
    }
    func testCatalogPlaceholdersMatchWithoutChangingFormatsOrShortcuts() {
        let marker=try! NSRegularExpression(pattern:#"\{[0-9]\}"#)
        func tokens(_ value:String)->[String] { marker.matches(in:value,range:NSRange(value.startIndex...,in:value)).compactMap{Range($0.range,in:value).map{String(value[$0])}}.sorted() }
        for (source,translation) in AppLocalization.turkish {
            XCTAssertFalse(translation.isEmpty,source)
            XCTAssertEqual(tokens(source),tokens(translation),source)
        }
        for code in ["png","MP4","Ctrl+Shift","⌘S","00:01.250"] { XCTAssertEqual(AppLocalization.text(code,language:"tr"),code) }
    }
}
