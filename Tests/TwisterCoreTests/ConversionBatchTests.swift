import XCTest
import CoreGraphics
import PDFKit
@testable import TwisterCore

final class ConversionBatchTests:XCTestCase {
    final class Log:@unchecked Sendable {
        private let lock=NSLock()
        private var statuses:[(Int,BatchItem.Status)]=[],fractions:[Double]=[]
        func add(_ index:Int,_ status:BatchItem.Status) { lock.lock();statuses.append((index,status));lock.unlock() }
        func add(_ value:Double) { lock.lock();fractions.append(value);lock.unlock() }
        var items:[(Int,BatchItem.Status)] { lock.lock();defer { lock.unlock() };return statuses }
        var progress:[Double] { lock.lock();defer { lock.unlock() };return fractions }
    }
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
    private var options:OperationOptions { var options=OperationOptions();options.outputDirectory=exports;options.preserveMetadata=false;return options }
    /// Hidden staging folders are listed too, so a leftover fails the comparison.
    private func exported() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath:exports.path).sorted() }

    func testCorruptInputFailsAloneAndKeepsTheOtherExports() throws {
        let first=try image("First.png"),broken=try corrupt("Broken.png"),last=try image("Last.png")
        let originals=try [first,broken,last].map { try Data(contentsOf:$0) }
        let previous=exports.appendingPathComponent("First.jpg"),bytes=Data("An earlier export".utf8)
        try bytes.write(to:previous)
        let log=Log()
        let report=try ConversionEngine.runBatch(.init(inputs:[first,broken,last],operation:.convert("jpg"),options:options),progress:{ value,_ in log.add(value) },itemChanged:{ log.add($0,$1) })
        XCTAssertEqual(report.items.map(\.inputs),[[first],[broken],[last]])
        XCTAssertEqual(report.items[0].outputs.map(\.lastPathComponent),["First 2.jpg"])
        XCTAssertEqual(report.items[2].outputs.map(\.lastPathComponent),["Last.jpg"])
        XCTAssertFalse(try XCTUnwrap(report.items[1].failure).isEmpty)
        XCTAssertEqual([report.succeeded,report.failed,report.cancelled],[2,1,0])
        XCTAssertEqual(report.failedInputs,[broken])
        XCTAssertEqual(report.summary,"2 of 3 done, 1 failed")
        XCTAssertEqual(try exported(),["First 2.jpg","First.jpg","Last.jpg"])
        XCTAssertEqual(try Data(contentsOf:previous),bytes)
        for output in report.outputs { XCTAssertEqual(try ImageEngine.load(output).width,40) }
        XCTAssertEqual(try [first,broken,last].map { try Data(contentsOf:$0) },originals)
        XCTAssertEqual(log.items.map(\.0),[0,0,1,1,2,2])
        XCTAssertEqual(log.items.map(\.1),[.running,report.items[0].status,.running,report.items[1].status,.running,report.items[2].status])
        let fractions=log.progress.filter { $0>=0 }
        XCTAssertEqual(fractions.last,1)
        XCTAssertTrue(zip(fractions,fractions.dropFirst()).allSatisfy { $0<=$1 })
    }

    func testMissingInputIsAPerFileFailureInsteadOfRejectingTheBatch() throws {
        let first=try image("First.png"),missing=root.appendingPathComponent("Missing.png")
        let report=try ConversionEngine.runBatch(.init(inputs:[missing,first],operation:.convert("jpg"),options:options))
        XCTAssertEqual(report.items[0].failure,"File not found: Missing.png")
        XCTAssertEqual(try exported(),["First.jpg"])
        XCTAssertThrowsError(try ConversionEngine.runBatch(.init(inputs:[],operation:.convert("jpg"),options:options)))
    }

    func testCancellationKeepsPublishedFilesAndCleansTheFileInFlight() throws {
        let inputs=try ["One.png","Two.png","Three.png"].map(image)
        let token=CancellationToken(),log=Log()
        let report=try ConversionEngine.runBatch(.init(inputs:inputs,operation:.convert("jpg"),options:options),token:token,progress:{ value,_ in log.add(value) },itemChanged:{ index,status in
            // The second file is staged and published after this point.
            if index==1,status == .running { token.cancel() }
        })
        XCTAssertEqual(report.items.map(\.status),[.succeeded([exports.appendingPathComponent("One.jpg")]),.cancelled,.cancelled])
        XCTAssertEqual(report.summary,"1 of 3 done, 2 cancelled")
        XCTAssertEqual(try exported(),["One.jpg"])
        XCTAssertFalse(log.progress.contains(1))
    }

    func testCancellationAfterTheLastFileIsStagedRemovesOnlyThatFile() throws {
        let inputs=try ["One.png","Two.png"].map(image)
        let token=CancellationToken()
        let report=try ConversionEngine.runBatch(.init(inputs:inputs,operation:.convert("jpg"),options:options),token:token,progress:{ _,label in
            if label.hasPrefix("File 2 of 2"),label.hasSuffix("Saving your files…") { token.cancel() }
        })
        XCTAssertEqual(report.items.map(\.status),[.succeeded([exports.appendingPathComponent("One.jpg")]),.cancelled])
        XCTAssertEqual(try exported(),["One.jpg"])
    }

    func testCombinedOperationStaysOneAtomicUnit() throws {
        let first=try image("First.png"),second=try image("Second.png"),broken=try corrupt("Broken.png")
        XCTAssertEqual(ConversionEngine.units(for:.init(inputs:[first,second],operation:.tool(.createPDF))),[[first,second]])
        XCTAssertEqual(ConversionEngine.units(for:.init(inputs:[first,second],operation:.tool(.mergePDF))).count,1)
        XCTAssertEqual(ConversionEngine.units(for:.init(inputs:[first,second],operation:.tool(.createCollage))).count,1)
        XCTAssertEqual(ConversionEngine.units(for:.init(inputs:[first,second],operation:.tool(.joinVideos))).count,1)
        XCTAssertEqual(ConversionEngine.units(for:.init(inputs:[first,second],operation:.tool(.compress))),[[first],[second]])
        let failed=try ConversionEngine.runBatch(.init(inputs:[first,broken,second],operation:.tool(.createPDF),options:options))
        XCTAssertEqual(failed.items.count,1)
        XCTAssertEqual(failed.items[0].inputs,[first,broken,second])
        XCTAssertNotNil(failed.items[0].failure)
        XCTAssertEqual(failed.summary,"0 of 1 done, 1 failed")
        XCTAssertEqual(try exported(),[])
        let report=try ConversionEngine.runBatch(.init(inputs:[first,second],operation:.tool(.createPDF),options:options))
        XCTAssertEqual(report.outputs.count,1)
        XCTAssertEqual(PDFDocument(url:report.outputs[0])?.pageCount,2)
        XCTAssertEqual(try exported().count,1)
    }

    func testFilesThatShareAnOutputNameReceiveSeparateFiles() throws {
        let png=try image("Photo.png"),tiff=try image("Photo.tiff"),bmp=try image("Photo.bmp")
        let report=try ConversionEngine.runBatch(.init(inputs:[png,tiff,bmp],operation:.convert("jpg"),options:options))
        XCTAssertEqual(report.outputs.map(\.lastPathComponent),["Photo.jpg","Photo 2.jpg","Photo 3.jpg"])
        XCTAssertEqual(Set(report.outputs).count,3)
        XCTAssertEqual(try exported(),["Photo 2.jpg","Photo 3.jpg","Photo.jpg"])
        let again=try ConversionEngine.runBatch(.init(inputs:[png],operation:.convert("jpg"),options:options))
        XCTAssertEqual(again.outputs.map(\.lastPathComponent),["Photo 4.jpg"])
    }

    func testOutputsBesideOriginalsLeaveNoStagingFolderForAFailedFile() throws {
        let good=try image("Good.png"),broken=try corrupt("Broken.png")
        var beside=options;beside.outputDirectory=nil
        let report=try ConversionEngine.runBatch(.init(inputs:[broken,good],operation:.convert("jpg"),options:beside))
        XCTAssertEqual(report.summary,"1 of 2 done, 1 failed")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.path).sorted(),["Broken.png","Exports","Good.jpg","Good.png"])
    }
}
