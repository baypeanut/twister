import XCTest
import PDFKit
import ImageIO
@testable import TwisterCore

final class DecodeBudgetTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws { root = try OutputFiles.temporaryDirectory() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private static func crc32(_ bytes: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
    private static func bigEndian(_ value: UInt32) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
    private static func chunk(_ type: String, _ body: Data) -> Data {
        let typed = Data(type.utf8) + body
        return bigEndian(UInt32(body.count)) + typed + bigEndian(crc32(typed))
    }
    /// A valid one-bit greyscale PNG that is tiny on disk but declares a
    /// large canvas: every row is zero, so the zlib stream compresses away.
    static func compressedPNG(side: Int) throws -> Data { try compressedPNG(width: side, height: side) }
    static func compressedPNG(width: Int, height: Int) throws -> Data {
        let row = Data(count: 1 + (width + 7) / 8)
        var raw = Data(capacity: row.count * height)
        for _ in 0..<height { raw.append(row) }
        let deflated = try (raw as NSData).compressed(using: .zlib) as Data
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in raw { a = (a + UInt32(byte)) % 65_521; b = (b + a) % 65_521 }
        let stream = Data([0x78, 0x9C]) + deflated + bigEndian(b << 16 | a)
        let header = bigEndian(UInt32(width)) + bigEndian(UInt32(height)) + Data([1, 0, 0, 0, 0])
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + chunk("IHDR", header) + chunk("IDAT", stream) + chunk("IEND", Data())
    }

    func testASmallPNGDeclaringAHugeCanvasIsRefusedBeforeDecoding() throws {
        let bomb = root.appendingPathComponent("bomb.png")
        try Self.compressedPNG(side: 16_000).write(to: bomb)
        XCTAssertLessThan(try bomb.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max, 100_000)
        XCTAssertThrowsError(try ImageEngine.load(bomb)) { error in
            XCTAssertTrue(error.localizedDescription.hasPrefix("This image is too large to open (16000 × 16000 pixels)."), error.localizedDescription)
        }
        XCTAssertThrowsError(try ImageEngine.loadPreview(bomb, maximumSide: 512))
        var options = OperationOptions(); options.outputDirectory = root.appendingPathComponent("out", isDirectory: true)
        XCTAssertThrowsError(try ConversionEngine.run(.init(inputs: [bomb], operation: .convert("jpg"), options: options)))
    }

    func testImagesWithinTheBudgetStillOpen() throws {
        let image = root.appendingPathComponent("ok.png")
        try Self.compressedPNG(side: 4_000).write(to: image)
        let decoded = try ImageEngine.load(image)
        XCTAssertEqual([decoded.width, decoded.height], [4_000, 4_000])
    }

    /// A medium-format camera frame, 11648 × 8736, is above the earlier limit.
    func testLargeCameraFramesStillConvert() throws {
        guard (try? Dependencies.executable("exiftool")) != nil else { throw XCTSkip("ExifTool is not available") }
        let image = root.appendingPathComponent("camera.png")
        try Self.compressedPNG(width: 11_648, height: 8_736).write(to: image)
        var options = OperationOptions(); options.outputDirectory = root.appendingPathComponent("camera", isDirectory: true)
        let output = try XCTUnwrap(ConversionEngine.run(.init(inputs: [image], operation: .convert("jpg"), options: options)).first)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        XCTAssertEqual(ImageEngine.declaredSize(source).map { [$0.0, $0.1] }, [11_648, 8_736])
        let preview = try ImageEngine.loadPreview(image, maximumSide: 1_024)
        XCTAssertEqual([preview.width, preview.height], [1_024, 768])
    }

    func testVectorImagesRenderAtExactlyTheCheckedSize() throws {
        let svg = root.appendingPathComponent("vector.svg")
        try Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="300" height="200"><rect width="100%" height="100%" fill="red"/></svg>"#.utf8).write(to: svg)
        let decoded = try ImageEngine.load(svg)
        XCTAssertEqual([decoded.width, decoded.height], [300, 200])
        let preview = try ImageEngine.loadPreview(svg, maximumSide: 150)
        XCTAssertEqual([preview.width, preview.height], [150, 100])
        let huge = root.appendingPathComponent("huge.svg")
        try Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="20000" height="20000"><rect width="100%" height="100%" fill="red"/></svg>"#.utf8).write(to: huge)
        XCTAssertThrowsError(try ImageEngine.load(huge)) { error in
            XCTAssertTrue(error.localizedDescription.hasPrefix("This image is too large to open (20000 × 20000 pixels)."), error.localizedDescription)
        }
    }

    /// A QOI image is decoded only by FFmpeg. Its header declares more pixels
    /// than the limit, so the decoder refuses before allocating the frame.
    func testTheFallbackDecoderRefusesOversizedFramesBeforeDecoding() throws {
        guard (try? Dependencies.executable("ffmpeg")) != nil else { throw XCTSkip("FFmpeg is not available") }
        let side: UInt32 = 16_000
        var qoi = Data("qoif".utf8) + Self.bigEndian(side) + Self.bigEndian(side) + Data([4, 0])
        // QOI_OP_RUN repeats the previous pixel up to 62 times per byte.
        let runs = Int(side) * Int(side) / 62
        qoi.append(Data(repeating: 0xFD, count: runs))
        qoi.append(Data(repeating: 0xC0 | UInt8(Int(side) * Int(side) - runs * 62 - 1), count: Int(side) * Int(side) % 62 == 0 ? 0 : 1))
        qoi.append(Data([0, 0, 0, 0, 0, 0, 0, 1]))
        let image = root.appendingPathComponent("frame.qoi")
        try qoi.write(to: image)
        let started = Date()
        XCTAssertThrowsError(try ImageEngine.load(image)) { error in
            XCTAssertFalse(error.localizedDescription.hasPrefix("This image is too large to open"), "FFmpeg decoded the whole frame first: \(error.localizedDescription)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    func testACancelledLoadStopsBeforeDecoding() throws {
        let image = root.appendingPathComponent("small.png")
        try Self.compressedPNG(side: 16).write(to: image)
        let token = CancellationToken(); token.cancel()
        XCTAssertThrowsError(try ImageEngine.load(image, token: token)) { error in
            guard case .cancelled? = error as? TwisterError else { return XCTFail("\(error)") }
        }
    }

    /// The largest page PDF allows, 200 inches square, in a few hundred bytes.
    private func hugePagePDF() throws -> URL {
        let objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                       "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 14400 14400] /Contents 4 0 R >>", "<< /Length 0 >>\nstream\n\nendstream"]
        var text = "%PDF-1.4\n", offsets: [Int] = []
        for (index, object) in objects.enumerated() { offsets.append(text.utf8.count); text += "\(index + 1) 0 obj\n\(object)\nendobj\n" }
        let xref = text.utf8.count
        text += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n" + offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
        text += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        let url = root.appendingPathComponent("big.pdf")
        try Data(text.utf8).write(to: url)
        return url
    }

    func testPDFCompressionRastersStayWithinThePixelBudget() throws {
        let size = PDFEngine.rasterSize(CGRect(x: 0, y: 0, width: 14_400, height: 14_400), dpi: 144)
        XCTAssertLessThanOrEqual(size.width * size.height, PDFEngine.rasterPixelBudget)
        XCTAssertEqual(size.width, size.height)
        let letter = PDFEngine.rasterSize(CGRect(x: 0, y: 0, width: 612, height: 792), dpi: 144)
        XCTAssertEqual([letter.width, letter.height], [1224, 1584])

        let input = try hugePagePDF()
        var options = OperationOptions(); options.outputDirectory = root.appendingPathComponent("compressed", isDirectory: true)
        let output = try XCTUnwrap(ConversionEngine.run(.init(inputs: [input], operation: .tool(.compress), options: options)).first)
        let page = try XCTUnwrap(PDFDocument(url: output)?.page(at: 0))
        XCTAssertEqual(page.bounds(for: .mediaBox).width, 14_400)
    }

    private func pagePDF(width: Double, height: Double, name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: width, height: height)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil); context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2)); context.endPDFPage(); context.closePDF()
        return url
    }
    private func pixelSize(_ data: Data) throws -> [Int] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let size = try XCTUnwrap(ImageEngine.declaredSize(source)); return [size.0, size.1]
    }

    func testEveryPDFRasterStaysWithinTheBudget() throws {
        let page = try XCTUnwrap(PDFDocument(url: hugePagePDF())?.page(at: 0))
        for dpi in [36, 144, 600] {
            let pixels = try pixelSize(PDFOfficeCodec.rasterPNG(page, dpi: dpi, token: .init()))
            XCTAssertLessThanOrEqual(Double(pixels[0] * pixels[1]), PDFEngine.rasterPixelBudget, "\(dpi) dpi")
            XCTAssertEqual(pixels[0], pixels[1])
        }
        let region = try pixelSize(PDFOfficeCodec.rasterPNG(page, rect: CGRect(x: 0, y: 0, width: 14_400, height: 7_200), dpi: 600, token: .init()))
        XCTAssertLessThanOrEqual(Double(region[0] * region[1]), PDFEngine.rasterPixelBudget)
        XCTAssertEqual(region[0], region[1] * 2, accuracy: 1)
        let small = try PDFEngine.raster(page, dpi: 300, budget: 1_000_000, annotations: true, token: .init())
        XCTAssertLessThanOrEqual(small.width * small.height, 1_000_000)
        // A page at an ordinary size and DPI keeps its exact pixel size.
        let letter = try XCTUnwrap(PDFDocument(url: pagePDF(width: 612, height: 792, name: "letter.pdf"))?.page(at: 0))
        XCTAssertEqual(try pixelSize(PDFOfficeCodec.rasterPNG(letter, dpi: 144, token: .init())), [1224, 1584])
        // Slides and recognized text use the same budget.
        let work = root.appendingPathComponent("office", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        XCTAssertNoThrow(try PDFOfficeCodec.prepare(hugePagePDF(), to: "pptx", at: work, options: OperationOptions(), token: .init()))
        XCTAssertNoThrow(try PDFOfficeCodec.recognizedCells(page, token: .init()))
    }

    func testPDFPagesTooLargeForTheDPIAreRenderedSmaller() throws {
        var options = OperationOptions(); options.dpi = 300; options.outputDirectory = root.appendingPathComponent("pages", isDirectory: true)
        let size = PDFEngine.rasterSize(CGRect(x: 0, y: 0, width: 14_400, height: 14_400), dpi: 300, budget: PDFEngine.exportPixelBudget)
        XCTAssertLessThanOrEqual(size.width * size.height, PDFEngine.exportPixelBudget)
        XCTAssertLessThanOrEqual(size.width, 32_000)
        // A0 at 300 dpi is within the budget and keeps its full resolution.
        let a0 = try pagePDF(width: 2_384, height: 3_370, name: "a0.pdf")
        let pages = try PDFEngine.render(a0, to: "png", options: options, token: .init(), progress: { _, _ in })
        XCTAssertEqual(pages.count, 1)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(pages[0] as CFURL, nil))
        XCTAssertEqual(ImageEngine.declaredSize(source).map { [$0.0, $0.1] }, [9_933, 14_041])
    }

    private func manyEntryPackage(_ count: Int, name: String) throws -> URL {
        let source = root.appendingPathComponent("\(name) contents", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try Data("application/epub+zip".utf8).write(to: source.appendingPathComponent("mimetype"))
        for index in 0..<count { try Data([UInt8(index % 251)]).write(to: source.appendingPathComponent("META-INF/item-\(index).txt")) }
        let package = root.appendingPathComponent(name)
        try ArchiveCodec.create(from: source, at: package, format: "zip", token: .init())
        return package
    }

    func testDocumentPackagesUseTheSmallerLimits() throws {
        let package = try manyEntryPackage(10_001, name: "Book.epub")
        XCTAssertThrowsError(try EPUBCodec.unpackToHTML(package, in: root.appendingPathComponent("epub", isDirectory: true), token: .init())) { error in
            XCTAssertTrue(error.localizedDescription.contains("too many entries"), error.localizedDescription)
        }
        XCTAssertThrowsError(try ArchiveCodec.checkLimits(package, limits: .document, token: .init()))
        // An ordinary archive of the same size is still within the general limit.
        try ArchiveCodec.checkLimits(package, limits: .init(), token: .init())
        XCTAssertEqual(ArchiveCodec.ExtractionLimits.document.maximumBytes, 500 * 1024 * 1024)
    }

    func testDocumentPackagesThatExpandTooFarAreRefusedWhileReading() throws {
        let source = root.appendingPathComponent("expanding", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(count: 3 * 1024 * 1024).write(to: source.appendingPathComponent("zeros.bin"))
        let package = root.appendingPathComponent("expanding.zip")
        try ArchiveCodec.create(from: source, at: package, format: "zip", compressionLevel: 9, token: .init())
        XCTAssertThrowsError(try ArchiveCodec.checkLimits(package, limits: .init(maximumEntries: 10, maximumBytes: 1024 * 1024), token: .init()))
        try ArchiveCodec.checkLimits(package, limits: .document, token: .init())
    }
}
