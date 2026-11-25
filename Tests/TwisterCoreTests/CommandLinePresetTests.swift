import XCTest
import CoreGraphics
@testable import TwisterCore

final class CommandLinePresetTests:XCTestCase {
    private var root:URL!,exports:URL!,store:PresetStore!
    private var out:[String]=[],err:[String]=[]
    override func setUpWithError() throws {
        root=try OutputFiles.temporaryDirectory()
        exports=root.appendingPathComponent("Exports",isDirectory:true)
        try FileManager.default.createDirectory(at:exports,withIntermediateDirectories:true)
        store=PresetStore(url:root.appendingPathComponent("Presets.json"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at:root) }

    private func image(_ name:String) throws -> URL {
        let context=try XCTUnwrap(CGContext(data:nil,width:40,height:20,bitsPerComponent:8,bytesPerRow:160,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red:0.1,green:0.5,blue:0.9,alpha:1));context.fill(CGRect(x:0,y:0,width:40,height:20))
        let file=root.appendingPathComponent(name)
        try ImageEngine.write(XCTUnwrap(context.makeImage()),to:file)
        return file
    }
    private func corrupt(_ name:String) throws -> URL {
        let file=root.appendingPathComponent(name)
        try Data("Not an image".utf8).write(to:file)
        return file
    }
    private func run(_ words:String...) -> Int32 {
        out=[];err=[]
        return TwisterCommandLine.run(arguments:["Twister","preset"]+words,presets:store,output:{ self.out.append($0) },errorOutput:{ self.err.append($0) })
    }
    private func exported() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath:exports.path).sorted() }
    private func addPresets() throws {
        var options=OperationOptions();options.preserveMetadata=false
        try store.update {
            try $0.add(Preset(name:"Web JPEG",operation:.convert("jpg"),options:options,destination:.folder(exports)))
            try $0.add(Preset(name:"Small",operation:.tool(.editImage),options:try OperationOptions.overlay(["width":10,"height":5]),destination:.besideOriginals))
        }
    }

    func testListPrintsNamesOrAnImportableDocument() throws {
        XCTAssertEqual(run("list"),0);XCTAssertTrue(out.isEmpty);XCTAssertTrue(err.isEmpty)
        try addPresets()
        XCTAssertEqual(run("list"),0)
        XCTAssertEqual(out,["Web JPEG\tConvert to JPG","Small\tEdit Image"])
        XCTAssertEqual(run("list","--json"),0)
        var copy=PresetLibrary()
        XCTAssertEqual(try copy.importPresets(from:Data(try XCTUnwrap(out.first).utf8)).map(\.name),["Web JPEG","Small"])
        // An imported preset saves where the user chooses, never in a folder the file names.
        XCTAssertNil(copy.presets[0].destination)
        XCTAssertEqual(copy.presets[1].destination,.besideOriginals)
    }

    func testRunUsesThePresetOptionsAndDestinationWithTheConvertExitCodes() throws {
        try addPresets()
        let good=try image("Good.png"),broken=try corrupt("Broken.png")
        XCTAssertEqual(run("run","Web JPEG",good.path),0)
        XCTAssertEqual(out,[exports.appendingPathComponent("Good.jpg").path]);XCTAssertTrue(err.isEmpty)
        XCTAssertEqual(run("run","web jpeg","--json",good.path,broken.path),TwisterCommandLine.partialFailureExitCode)
        XCTAssertEqual(try JSONDecoder().decode([String].self,from:Data(try XCTUnwrap(out.first).utf8)),[exports.appendingPathComponent("Good 2.jpg").path])
        XCTAssertEqual(err.count,1);XCTAssertTrue(err[0].hasPrefix(broken.path+": "))
        XCTAssertEqual(run("run","Web JPEG",broken.path),1)
        XCTAssertTrue(out.isEmpty);XCTAssertEqual(err.count,1)
        XCTAssertEqual(try exported(),["Good 2.jpg","Good.jpg"])
        XCTAssertEqual(run("run","Small",good.path),0)
        let small=try ImageEngine.load(URL(fileURLWithPath:try XCTUnwrap(out.first)))
        XCTAssertEqual([small.width,small.height],[10,5])
        XCTAssertEqual(URL(fileURLWithPath:out[0]).deletingLastPathComponent().resolvingSymlinksInPath().path,root.resolvingSymlinksInPath().path)
        // Options on the command line change the preset for this run only.
        let override=String(decoding:try JSONSerialization.data(withJSONObject:["width":20,"outputDirectory":exports.path]),as:UTF8.self)
        XCTAssertEqual(run("run","Small","--options",override,good.path),0)
        let wider=try ImageEngine.load(URL(fileURLWithPath:try XCTUnwrap(out.first)))
        XCTAssertEqual([wider.width,wider.height],[20,5])
        XCTAssertEqual(URL(fileURLWithPath:out[0]).deletingLastPathComponent().resolvingSymlinksInPath().path,exports.resolvingSymlinksInPath().path)
        XCTAssertEqual(try store.load().presets[1].options.width,10)
    }

    func testEverythingAfterTheSeparatorIsAFile() throws {
        try addPresets()
        let odd=try image("--json.png")
        let directory=FileManager.default.currentDirectoryPath
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(root.path));defer { FileManager.default.changeCurrentDirectoryPath(directory) }
        XCTAssertEqual(run("run","Web JPEG","--","--json.png"),0)
        XCTAssertEqual(out,[exports.appendingPathComponent("--json.jpg").path])
        XCTAssertEqual(try Data(contentsOf:odd).isEmpty,false)
        XCTAssertEqual(run("run","Web JPEG","--json","--","--json.png"),0)
        XCTAssertEqual(try JSONDecoder().decode([String].self,from:Data(try XCTUnwrap(out.first).utf8)).count,1)
    }

    func testUnknownPresetsMissingFoldersAndUsageErrors() throws {
        try addPresets()
        let good=try image("Good.png")
        XCTAssertEqual(run("run","Nope",good.path),1)
        XCTAssertEqual(err,["There is no preset named “Nope”."]);XCTAssertTrue(out.isEmpty)
        XCTAssertEqual(run("export","Nope"),1)
        try FileManager.default.removeItem(at:exports)
        XCTAssertEqual(run("run","Web JPEG",good.path),1)
        XCTAssertEqual(err,["The preset’s folder is no longer available: \(exports.path)"])
        XCTAssertFalse(FileManager.default.fileExists(atPath:exports.path))
        for words in [[],["run"],["run","Web JPEG"],["run","Web JPEG","--json"],["list","extra"],["export"],["import"],["import","a","b"],["remove","Web JPEG"]] as [[String]] {
            out=[];err=[]
            XCTAssertEqual(TwisterCommandLine.run(arguments:["Twister","preset"]+words,presets:store,output:{ self.out.append($0) },errorOutput:{ self.err.append($0) }),64,"\(words)")
            XCTAssertTrue(out.first?.contains("twister-cli preset run NAME") == true)
        }
        XCTAssertEqual(run("run","Web JPEG",good.path,"--options"),64)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path).sorted(),["Good.png","Presets.json"])
    }

    func testExportAndImportMoveAPresetBetweenStores() throws {
        try addPresets()
        XCTAssertEqual(run("export","Small"),0)
        let document=root.appendingPathComponent("small.json")
        try Data(try XCTUnwrap(out.first).utf8).write(to:document)
        XCTAssertEqual(run("import",document.path),0)
        XCTAssertEqual(out,["Small 2"])
        let presets=try store.load().presets
        XCTAssertEqual(presets.map(\.name),["Web JPEG","Small","Small 2"])
        XCTAssertEqual(presets[2].operation,.tool(.editImage));XCTAssertEqual(presets[2].options.width,10);XCTAssertEqual(presets[2].destination,.besideOriginals)
        XCTAssertNotEqual(presets[2].id,presets[1].id)
        let saved=try Data(contentsOf:store.url)
        try Data("{\"name\":\"Broken\"}".utf8).write(to:document)
        XCTAssertEqual(run("import",document.path),1)
        XCTAssertTrue(err.first?.hasPrefix("This is not a Twister preset.") == true)
        XCTAssertEqual(run("import",root.appendingPathComponent("missing.json").path),1)
        XCTAssertEqual(try Data(contentsOf:store.url),saved)
    }

    func testADamagedPresetsFileIsReportedAndKept() throws {
        try Data("{ damaged".utf8).write(to:store.url)
        XCTAssertEqual(run("list"),0)
        XCTAssertTrue(out.isEmpty);XCTAssertEqual(err.count,1)
        let kept=try FileManager.default.contentsOfDirectory(atPath:root.path).filter { $0.hasPrefix("Presets.corrupt-") }
        XCTAssertEqual(kept.count,1)
        XCTAssertTrue(err[0].hasSuffix(kept[0]+"."))
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent(kept[0])),Data("{ damaged".utf8))
    }

    /// The built command with its real environment, streams and exit status.
    func testBuiltCommandImportsAndRunsAPreset() throws {
        let cli=Bundle(for:Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("twister-cli")
        guard FileManager.default.isExecutableFile(atPath:cli.path) else { throw XCTSkip("twister-cli is not built.") }
        let good=try image("Good.png"),document=root.appendingPathComponent("preset.json")
        try PresetLibrary.exportData([Preset(name:"To TIFF",operation:.convert("tiff"),destination:.folder(exports))]).write(to:document)
        func launch(_ arguments:[String]) throws -> (Int32,String,String) {
            let process=Process(),stdout=Pipe(),stderr=Pipe()
            process.executableURL=cli;process.arguments=arguments
            process.environment=ProcessInfo.processInfo.environment.merging(["TWISTER_PRESETS_FILE":store.url.path]) { $1 }
            process.standardOutput=stdout;process.standardError=stderr
            try process.run()
            let out=String(decoding:stdout.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self),err=String(decoding:stderr.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self)
            process.waitUntilExit()
            return (process.terminationStatus,out,err)
        }
        var result=try launch(["preset","import",document.path])
        XCTAssertEqual(result.0,0);XCTAssertEqual(result.1,"To TIFF\n")
        result=try launch(["preset","list"])
        XCTAssertEqual(result.1,"To TIFF\tConvert to TIFF\n")
        result=try launch(["preset","run","To TIFF","--",good.path])
        // The imported preset does not keep the folder named in the file.
        XCTAssertEqual(result.0,0);XCTAssertEqual(result.1,root.appendingPathComponent("Good.tiff").path+"\n");XCTAssertEqual(result.2,"")
        XCTAssertEqual(try ImageEngine.load(root.appendingPathComponent("Good.tiff")).width,40)
        result=try launch(["preset","run","Missing",good.path])
        XCTAssertEqual(result.0,1);XCTAssertEqual(result.1,"");XCTAssertTrue(result.2.contains("Missing"))
        XCTAssertEqual(try launch(["preset","run"]).0,64)
    }
}
