import XCTest
import CoreGraphics
@testable import TwisterCore

final class CommandLineBatchTests:XCTestCase {
    private var root:URL!,exports:URL!
    override func setUpWithError() throws {
        root=try OutputFiles.temporaryDirectory()
        exports=root.appendingPathComponent("Exports",isDirectory:true)
        try FileManager.default.createDirectory(at:exports,withIntermediateDirectories:true)
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
    private func exported() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath:exports.path).sorted() }

    func testCommandLineKeepsFinishedFilesAndReportsFailuresSeparately() throws {
        let good=try image("Good.png"),broken=try corrupt("Broken.png")
        let settings=String(decoding:try JSONSerialization.data(withJSONObject:["outputDirectory":exports.path,"preserveMetadata":false]),as:UTF8.self)
        var out:[String]=[],err:[String]=[]
        func run(_ words:[String]) -> Int32 {
            out=[];err=[]
            return TwisterCommandLine.run(arguments:["Twister","convert","jpg"]+words+["--options",settings],output:{ out.append($0) },errorOutput:{ err.append($0) })
        }
        XCTAssertEqual(run([good.path,broken.path]),TwisterCommandLine.partialFailureExitCode)
        XCTAssertEqual(TwisterCommandLine.partialFailureExitCode,3)
        XCTAssertEqual(out,[exports.appendingPathComponent("Good.jpg").path])
        XCTAssertEqual(err.count,1)
        XCTAssertTrue(err[0].hasPrefix(broken.path+": "))
        XCTAssertEqual(run([broken.path,good.path,"--json"]),3)
        XCTAssertEqual(try JSONDecoder().decode([String].self,from:Data(try XCTUnwrap(out.first).utf8)),[exports.appendingPathComponent("Good 2.jpg").path])
        XCTAssertEqual(out.count,1);XCTAssertEqual(err.count,1)
        XCTAssertEqual(run([broken.path]),1)
        XCTAssertTrue(out.isEmpty);XCTAssertEqual(err.count,1)
        XCTAssertEqual(run([good.path]),0)
        XCTAssertEqual(out.count,1);XCTAssertTrue(err.isEmpty)
        XCTAssertEqual(try exported(),["Good 2.jpg","Good 3.jpg","Good.jpg"])
    }

    /// The built command, so the real stdout, stderr and exit status are checked.
    func testBuiltCommandSeparatesOutputStreamsAndExitsWithThePartialFailureCode() throws {
        let cli=Bundle(for:Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("twister-cli")
        guard FileManager.default.isExecutableFile(atPath:cli.path) else { throw XCTSkip("twister-cli is not built.") }
        let good=try image("Good.png"),broken=try corrupt("Broken.png")
        let process=Process(),stdout=Pipe(),stderr=Pipe()
        process.executableURL=cli
        process.arguments=["convert","jpg","--options","{\"preserveMetadata\":false}","--json",good.path,broken.path]
        process.standardOutput=stdout;process.standardError=stderr
        try process.run()
        let out=stdout.fileHandleForReading.readDataToEndOfFile(),err=String(decoding:stderr.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus,3)
        XCTAssertEqual(try JSONDecoder().decode([String].self,from:out).map { URL(fileURLWithPath:$0).lastPathComponent },["Good.jpg"])
        XCTAssertTrue(err.contains("Broken.png: "))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path).sorted(),["Broken.png","Exports","Good.jpg","Good.png"])
    }
}
