import XCTest
import Darwin
import CoreServices
@testable import TwisterCore

/// A one-route HTTP server on 127.0.0.1 that counts the requests it receives.
final class LoopbackServer: @unchecked Sendable {
    let port: UInt16
    private let socketDescriptor: Int32
    private let lock = NSLock(); private var served = 0
    private let response: Data
    var requests: Int { lock.lock(); defer { lock.unlock() }; return served }

    init(body: Data, headers: [String: String]) throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in(); address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1"); address.sin_port = 0
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(descriptor, 8) == 0 else { close(descriptor); throw TwisterError.failed("Loopback server could not start.") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) } }
        socketDescriptor = descriptor
        port = UInt16(bigEndian: address.sin_port)
        var head = "HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (key, value) in headers { head += "\(key): \(value)\r\n" }
        response = Data((head + "\r\n").utf8) + body
        Thread.detachNewThread { [self] in serve() }
    }
    private func serve() {
        while true {
            let client = accept(socketDescriptor, nil, nil)
            guard client >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 16_384)
            let count = read(client, &buffer, buffer.count)
            if count > 0 {
                lock.lock(); served += 1; lock.unlock()
                let isHead = String(decoding: buffer[0..<count], as: UTF8.self).hasPrefix("HEAD")
                let payload = isHead ? response.prefix(upTo: response.range(of: Data("\r\n\r\n".utf8))!.upperBound) : response
                payload.withUnsafeBytes { _ = write(client, $0.baseAddress, payload.count) }
            }
            close(client)
        }
    }
    func stop() { shutdown(socketDescriptor, SHUT_RDWR); close(socketDescriptor) }
}

final class WebDownloadSafetyTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws { root = try OutputFiles.temporaryDirectory() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testLinksToThisMacAndTheLocalNetworkAreRefused() {
        let local = ["http://127.0.0.1/a.png", "http://127.1/a.png", "http://2130706433/a.png", "http://0x7f000001/a.png", "http://0.0.0.0/",
                     "http://localhost:8080/", "http://LOCALHOST./", "http://media.localhost/", "http://printer.local/scan.jpg", "http://router/",
                     "http://10.0.0.8/", "http://172.20.1.1/", "http://192.168.1.10/", "http://169.254.169.254/latest/", "http://100.64.0.1/",
                     "http://[::1]/", "http://[fe80::1]/", "http://[fd12:3456::1]/", "http://[::ffff:127.0.0.1]/", "http://[::ffff:192.168.0.1]/",
                     "http://224.0.0.1/", "http://nas.home.arpa/"]
        for link in local {
            XCTAssertThrowsError(try WebDownloadEngine.link(link), link) { error in
                XCTAssertEqual(error.localizedDescription, "Twister downloads only from public internet addresses, not from this Mac or the local network.")
            }
        }
        for link in ["https://example.com/video", "https://93.184.216.34/a.png", "https://[2606:4700:4700::1111]/", "https://cdn.example.org./a.jpg"] {
            XCTAssertNoThrow(try WebDownloadEngine.link(link), link)
        }
        XCTAssertNoThrow(try WebDownloadEngine.link("http://127.0.0.1:8080/a.png", allowLocalNetwork: true))
    }

    func testRedirectsMayNotLeaveThePublicInternet() {
        let policy = WebDownloadEngine.RedirectPolicy(allowLocalNetwork: false)
        XCTAssertFalse(policy.permits(URL(string: "http://127.0.0.1/admin")))
        XCTAssertFalse(policy.permits(URL(string: "http://192.168.0.1/")))
        XCTAssertFalse(policy.permits(URL(string: "file:///etc/hosts")))
        XCTAssertTrue(NetworkAddress.resolvesToLocal(host: "localhost"))
        XCTAssertTrue(WebDownloadEngine.RedirectPolicy(allowLocalNetwork: true).permits(URL(string: "http://127.0.0.1/a.png")))
    }

    func testPastingALoopbackLinkMakesNoRequest() async throws {
        let server = try LoopbackServer(body: Data("x".utf8), headers: ["Content-Type": "image/png"])
        defer { server.stop() }
        do {
            _ = try await WebDownloadEngine.inspect(URL(string: "http://127.0.0.1:\(server.port)/a.png")!)
            XCTFail("A loopback link must be refused")
        } catch {}
        XCTAssertEqual(server.requests, 0)
    }

    private func pngData() throws -> Data {
        try DecodeBudgetTests.compressedPNG(side: 32)
    }

    func testDirectDownloadsTakeTheirExtensionFromTheContent() async throws {
        let server = try LoopbackServer(body: try pngData(), headers: ["Content-Type": "application/octet-stream", "Content-Disposition": "attachment; filename=\"Installer.dmg\""])
        defer { server.stop() }
        let url = URL(string: "http://127.0.0.1:\(server.port)/photo.png")!
        let info = try await WebDownloadEngine.inspect(url, allowLocalNetwork: true)
        XCTAssertEqual(info.kind, .image)
        let destination = root.appendingPathComponent("Downloads", isDirectory: true)
        let files = try await WebDownloadEngine.download(info, mode: .original, maximumHeight: nil, destination: destination, allowLocalNetwork: true, progress: { _, _ in })
        let file = try XCTUnwrap(files.first)
        XCTAssertEqual(file.lastPathComponent, "Installer.png")
        let properties = try XCTUnwrap(try file.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties)
        XCTAssertEqual(properties[kLSQuarantineAgentNameKey as String] as? String, "Twister")
        XCTAssertEqual(properties[kLSQuarantineTypeKey as String] as? String, kLSQuarantineTypeWebDownload as String)
    }

    func testDetectedExtensionsKeepAMatchingNameAndRejectOtherContent() throws {
        let png = root.appendingPathComponent("a")
        try pngData().write(to: png)
        XCTAssertEqual(try WebDownloadEngine.detectedExtension(of: png, kind: .image, proposed: "PNG", token: .init()), "PNG".lowercased())
        XCTAssertEqual(try WebDownloadEngine.detectedExtension(of: png, kind: .image, proposed: "html", token: .init()), "png")
        let page = root.appendingPathComponent("b")
        try Data("<html><script>alert(1)</script></html>".utf8).write(to: page)
        XCTAssertThrowsError(try WebDownloadEngine.detectedExtension(of: page, kind: .image, proposed: "jpg", token: .init()))
    }

    func testOnlyRegularFilesOfTheStagingFolderArePublished() throws {
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let inside = staging.appendingPathComponent("clip.mp4"), outside = root.appendingPathComponent("private.txt")
        try Data("clip".utf8).write(to: inside); try Data("private".utf8).write(to: outside)
        let link = staging.appendingPathComponent("link.mp4")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertNoThrow(try WebDownloadEngine.stagedFiles([inside], in: staging))
        XCTAssertThrowsError(try WebDownloadEngine.stagedFiles([outside], in: staging))
        XCTAssertThrowsError(try WebDownloadEngine.stagedFiles([link], in: staging))
        XCTAssertThrowsError(try WebDownloadEngine.stagedFiles([staging.appendingPathComponent("../private.txt")], in: staging))
        XCTAssertThrowsError(try WebDownloadEngine.stagedFiles([staging.appendingPathComponent("missing.mp4")], in: staging))
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "private")
    }

    func testTheDownloaderInheritsOnlyTheStandardStreams() throws {
        let file = open(root.appendingPathComponent("open.txt").path, O_CREAT | O_RDWR, 0o600)
        // A high number cannot collide with descriptors the child opens itself.
        let descriptor = fcntl(file, F_DUPFD, 200)
        close(file)
        XCTAssertGreaterThanOrEqual(descriptor, 200)
        defer { close(descriptor) }
        let listing = try WebDownloadProcess.run(URL(fileURLWithPath: "/bin/ls"), ["/dev/fd"], token: .init(), timeout: 20)
        let inherited = Set(String(decoding: listing, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { Int32($0) })
        XCTAssertFalse(inherited.contains(descriptor), "inherited \(inherited.sorted())")
    }
}
