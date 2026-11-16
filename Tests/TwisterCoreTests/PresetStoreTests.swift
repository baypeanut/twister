import XCTest
@testable import TwisterCore

final class PresetStoreTests:XCTestCase {
    private var root:URL!,store:PresetStore!
    override func setUpWithError() throws {
        root=try OutputFiles.temporaryDirectory()
        store=PresetStore(url:root.appendingPathComponent("Support/Presets.json"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at:root) }
    private func file(_ name:String)->URL { root.appendingPathComponent(name) }
    private func write(_ object:Any) throws {
        try FileManager.default.createDirectory(at:store.url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONSerialization.data(withJSONObject:object).write(to:store.url)
    }
    private func saved() throws -> [String:Any] { try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:store.url)) as? [String:Any]) }

    func testPresetsRoundTripWithOptionsDestinationAndOrder() throws {
        XCTAssertTrue(try store.load().presets.isEmpty)
        var web=OperationOptions();web.quality=0.45;web.preserveMetadata=false;web.pdfPageRotations=[0:90]
        web.password="secret";web.outputDirectory=root;web.revealInFinder=false
        var trim=OperationOptions();trim.start=1.5;trim.end=4;trim.imageFrame=ImageFrameOptions()
        let first=try store.update { try $0.add(Preset(name:"  Web\nJPEG ",operation:.convert("JPEG"),options:web,destination:.folder(root))) }
        try store.update { try $0.add(Preset(name:"Trim",operation:.tool(.trimVideo),options:trim,destination:.besideOriginals)) }
        try store.update { try $0.add(Preset(name:"Plain",operation:.tool(.compress))) }
        let loaded=try store.load()
        XCTAssertEqual(loaded.presets.map(\.name),["Web JPEG","Trim","Plain"])
        XCTAssertEqual(loaded.presets.map(\.operation),[.convert("jpg"),.tool(.trimVideo),.tool(.compress)])
        XCTAssertEqual(loaded.presets.map(\.destination),[.folder(root),.besideOriginals,nil])
        XCTAssertEqual(loaded.presets[0].id,first.id)
        XCTAssertEqual(loaded.presets[0].options.quality,0.45)
        XCTAssertEqual(loaded.presets[0].options.pdfPageRotations,[0:90])
        XCTAssertFalse(loaded.presets[0].options.preserveMetadata)
        XCTAssertEqual(loaded.presets[1].options.end,4)
        XCTAssertNotNil(loaded.presets[1].options.imageFrame)
        XCTAssertEqual(try saved()["version"] as? Int,1)
        XCTAssertNil(loaded.preservedCorruptFile);XCTAssertEqual(loaded.unreadableCount,0)
    }

    func testAFilePasswordAndAOneTimeFolderAreNotSaved() throws {
        var options=OperationOptions();options.password="secret";options.outputDirectory=root;options.revealInFinder=false
        try store.update { try $0.add(Preset(name:"Unlock",operation:.convert("txt"),options:options)) }
        XCTAssertFalse(String(decoding:try Data(contentsOf:store.url),as:UTF8.self).contains("secret"))
        let preset=try store.load().presets[0]
        XCTAssertEqual(preset.options.password,"");XCTAssertNil(preset.options.outputDirectory);XCTAssertTrue(preset.options.revealInFinder)
    }

    func testAnOlderFileWithMissingAndUnknownFieldsStillLoads() throws {
        try write(["presets":[
            ["name":"Old","operation":["type":"convert","format":"jpeg"],"options":["quality":0.3,"imageFrame":["padding":12],"removedLongAgo":true],"extra":1],
            ["name":"Bare","operation":["type":"tool","tool":"compress"]]
        ]])
        let library=try store.load()
        XCTAssertEqual(library.presets.map(\.name),["Old","Bare"])
        XCTAssertEqual(library.presets[0].operation,.convert("jpg"))
        XCTAssertEqual(library.presets[0].options.quality,0.3)
        XCTAssertEqual(library.presets[0].options.audioBitrate,OperationOptions().audioBitrate)
        XCTAssertNotNil(library.presets[0].options.imageFrame)
        XCTAssertEqual(library.presets[1].options.quality,OperationOptions().quality)
        XCTAssertNil(library.presets[1].destination)
    }

    func testEntriesFromANewerBuildSurviveASave() throws {
        let future:[String:Any]=["id":UUID().uuidString,"name":"Future","operation":["type":"tool","tool":"teleportFile"],"options":["warp":9]]
        try write(["version":7,"presets":[future,["name":"Known","operation":["type":"tool","tool":"compress"]],"not a preset"]])
        let library=try store.load()
        XCTAssertEqual(library.presets.map(\.name),["Known"]);XCTAssertEqual(library.unreadableCount,2)
        XCTAssertNil(library.preservedCorruptFile)
        try store.update { try $0.add(Preset(name:"Added",operation:.convert("png"))) }
        let file=try saved(),entries=try XCTUnwrap(file["presets"] as? [Any])
        XCTAssertEqual(file["version"] as? Int,7)
        XCTAssertEqual(entries.count,4)
        XCTAssertTrue(entries.contains { ($0 as? NSDictionary)==(future as NSDictionary) })
        XCTAssertTrue(entries.contains { $0 as? String=="not a preset" })
        XCTAssertEqual(try store.load().presets.map(\.name),["Known","Added"])
    }

    func testACorruptFileIsMovedAsideAndNeverOverwritten() throws {
        for (index,damaged) in [Data("{\"presets\": [ {\"name\": \"Half".utf8),Data("[1,2,3]".utf8)].enumerated() {
            try FileManager.default.createDirectory(at:store.url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try damaged.write(to:store.url)
            let library=try store.load()
            let moved=try XCTUnwrap(library.preservedCorruptFile)
            XCTAssertTrue(library.presets.isEmpty)
            XCTAssertEqual(try Data(contentsOf:moved),damaged)
            XCTAssertFalse(FileManager.default.fileExists(atPath:store.url.path))
            XCTAssertTrue(moved.lastPathComponent.hasPrefix("Presets.corrupt-"))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:store.url.deletingLastPathComponent().path).count,index+1)
        }
        try store.update { try $0.add(Preset(name:"Fresh",operation:.convert("png"))) }
        XCTAssertEqual(try store.load().presets.map(\.name),["Fresh"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:store.url.deletingLastPathComponent().path).count,3)
    }

    func testAnUnreadableFileIsAnErrorAndStaysInPlace() throws {
        try FileManager.default.createDirectory(at:store.url,withIntermediateDirectories:true)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.update { try $0.add(Preset(name:"Lost",operation:.convert("png"))) })
        XCTAssertTrue(FileManager.default.fileExists(atPath:store.url.path))
    }

    func testNamesAreUniqueWithoutRegardToCaseAccentsOrSpacing() throws {
        var library=PresetLibrary()
        let web=try library.add(Preset(name:"Web JPEG",operation:.convert("jpg")))
        XCTAssertThrowsError(try library.add(Preset(name:" web jpeg ",operation:.convert("png")))) { XCTAssertEqual($0 as? PresetError,.duplicateName("web jpeg")) }
        XCTAssertThrowsError(try library.add(Preset(name:"  \n ",operation:.convert("png")))) { XCTAssertEqual($0 as? PresetError,.emptyName) }
        let other=try library.add(Preset(name:"Küçük",operation:.tool(.compress)))
        XCTAssertThrowsError(try library.rename(other.id,to:"WEB JPEG"))
        XCTAssertThrowsError(try library.rename(web.id,to:"Kucuk"))
        try library.rename(web.id,to:"web jpeg")
        XCTAssertEqual(library.presets.map(\.name),["web jpeg","Küçük"])
        XCTAssertEqual(library.availableName("Küçük"),"Küçük 2")
        XCTAssertEqual(library.availableName("New"),"New")
        // An identifier that is already used gets a new one instead of shadowing the saved preset.
        let clash=try library.add(Preset(id:web.id,name:"Clash",operation:.convert("png")))
        XCTAssertNotEqual(clash.id,web.id)
    }

    func testDuplicateReorderRemoveAndFind() throws {
        var library=PresetLibrary(presets:[Preset(name:"A",operation:.convert("jpg")),Preset(name:"B",operation:.tool(.compress)),Preset(name:"C",operation:.convert("png"))])
        let a=library.presets[0],c=library.presets[2]
        let copy=try XCTUnwrap(library.duplicate(a.id))
        XCTAssertEqual(library.presets.map(\.name),["A","A 2","B","C"])
        XCTAssertNotEqual(copy.id,a.id);XCTAssertEqual(copy.operation,a.operation)
        XCTAssertEqual(library.duplicate(a.id)?.name,"A 3")
        library.move(c.id,by:-10);XCTAssertEqual(library.presets.map(\.name),["C","A","A 3","A 2","B"])
        library.move(c.id,by:1);XCTAssertEqual(library.presets.map(\.name),["A","C","A 3","A 2","B"])
        library.move(c.id,by:99);XCTAssertEqual(library.presets.last?.name,"C")
        library.remove(copy.id);XCTAssertEqual(library.presets.map(\.name),["A","A 3","B","C"])
        XCTAssertEqual(try library.find("b").name,"B")
        XCTAssertEqual(try library.find(c.id.uuidString).name,"C")
        XCTAssertThrowsError(try library.find("Missing")) { XCTAssertEqual($0 as? PresetError,.notFound("Missing")) }
    }

    func testOnlyPresetsTheCatalogAllowsForTheWholeSelectionAreOffered() throws {
        let library=PresetLibrary(presets:[
            Preset(name:"To JPEG",operation:.convert("jpeg")),Preset(name:"To MP3",operation:.convert("mp3")),
            Preset(name:"Shrink",operation:.tool(.compress)),Preset(name:"Edit",operation:.tool(.editImage)),
            Preset(name:"Collage",operation:.tool(.createCollage)),Preset(name:"Merge",operation:.tool(.mergePDF))
        ])
        func names(_ files:[String])->[String] { library.applicable(to:files.map(file)).map(\.name) }
        XCTAssertEqual(names(["a.png"]),["To JPEG","Shrink","Edit"])
        XCTAssertEqual(names(["a.png","b.PNG"]),["To JPEG","Shrink","Collage"])
        XCTAssertEqual(names(["a.png","b.mp4"]),["Shrink"])
        XCTAssertEqual(names(["a.mp4"]),["To MP3","Shrink"])
        XCTAssertEqual(names(["a.pdf","b.pdf"]),["To JPEG","Shrink","Merge"])
        XCTAssertEqual(names(["a.jpg"]),["Shrink","Edit"])
        XCTAssertEqual(names(["notes.xyz"]),[])
        XCTAssertEqual(names([]),[])
        try FileManager.default.createDirectory(at:file("Folder.png"),withIntermediateDirectories:true)
        XCTAssertEqual(names(["Folder.png"]),[])
    }

    func testARequestUsesThePresetDestinationOrTheCallersOwn() throws {
        let input=file("a.png"),other=file("Other")
        try FileManager.default.createDirectory(at:other,withIntermediateDirectories:true)
        var options=OperationOptions();options.quality=0.2
        func directory(_ destination:PresetDestination?,fallback:URL?=nil) throws -> URL? {
            let request=try Preset(name:"P",operation:.convert("jpg"),options:options,destination:destination).request(for:[input],fallback:fallback)
            XCTAssertEqual(request.inputs,[input]);XCTAssertEqual(request.operation,.convert("jpg"));XCTAssertEqual(request.options.quality,0.2)
            return request.options.outputDirectory
        }
        XCTAssertNil(try directory(nil))
        XCTAssertEqual(try directory(nil,fallback:other),other)
        XCTAssertNil(try directory(.besideOriginals,fallback:other))
        XCTAssertEqual(try directory(.folder(root),fallback:other),root)
        XCTAssertThrowsError(try directory(.folder(file("Gone")))) { XCTAssertEqual($0 as? PresetError,.folderUnavailable(self.file("Gone").path)) }
        XCTAssertThrowsError(try directory(.folder(input)))
    }

    func testImportNumbersATakenNameAndAddsNothingWhenAnEntryIsUnreadable() throws {
        var library=PresetLibrary(presets:[Preset(name:"Web",operation:.convert("jpg"))])
        let exported=try PresetLibrary.exportData(library.presets+[Preset(name:"Trim",operation:.tool(.trimVideo))])
        XCTAssertEqual(try library.importPresets(from:exported).map(\.name),["Web 2","Trim"])
        XCTAssertEqual(Set(library.presets.map(\.id)).count,3)
        let single=try JSONSerialization.data(withJSONObject:["name":"Single","operation":["type":"convert","format":"png"]])
        XCTAssertEqual(try library.importPresets(from:single).map(\.name),["Single"])
        let mixed=try JSONSerialization.data(withJSONObject:["presets":[["name":"Fine","operation":["type":"convert","format":"png"]],["name":"Bad","operation":["type":"tool","tool":"nope"]]]])
        for data in [mixed,Data("nonsense".utf8),Data("[]".utf8),Data("{\"presets\":[]}".utf8),Data("{\"name\":\"\"}".utf8)] {
            XCTAssertThrowsError(try library.importPresets(from:data)) { guard case .unreadable=$0 as? PresetError else { return XCTFail("\($0)") } }
        }
        XCTAssertEqual(library.presets.map(\.name),["Web","Web 2","Trim","Single"])
    }

    func testTheStandardStoreFollowsTheEnvironmentOverride() {
        setenv("TWISTER_PRESETS_FILE",file("Custom.json").path,1);defer { unsetenv("TWISTER_PRESETS_FILE") }
        XCTAssertEqual(PresetStore.standard.url,file("Custom.json"))
        unsetenv("TWISTER_PRESETS_FILE")
        XCTAssertTrue(PresetStore.standard.url.path.hasSuffix("/Library/Application Support/Twister/Presets.json"))
    }
}
