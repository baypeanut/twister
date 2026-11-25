import XCTest
import Darwin
@testable import TwisterCore

/// An HTTP server on 127.0.0.1 that answers each path from a table and
/// records the paths it was asked for.
final class RoutingServer: @unchecked Sendable {
    let port: UInt16
    private let descriptor: Int32
    private let lock = NSLock(); private var seen: [String] = []
    private let routes: @Sendable (String, UInt16) -> (status: String, headers: [String: String], body: Data)
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return seen }

    init(_ routes: @escaping @Sendable (_ path: String, _ port: UInt16) -> (status: String, headers: [String: String], body: Data)) throws {
        self.routes = routes
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in(); address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1"); address.sin_port = 0
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0, listen(descriptor, 16) == 0 else { close(descriptor); throw TwisterError.failed("Loopback server could not start.") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) } }
        self.descriptor = descriptor
        port = UInt16(bigEndian: address.sin_port)
        Thread.detachNewThread { [self] in serve() }
    }
    private func serve() {
        while true {
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else { return }
            Thread.detachNewThread { [self] in answer(client) }
        }
    }
    private func answer(_ client: Int32) {
        defer { close(client) }
        var request = Data(), buffer = [UInt8](repeating: 0, count: 16_384)
        while request.range(of: Data("\r\n\r\n".utf8)) == nil {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { return }
            request.append(contentsOf: buffer[0..<count])
        }
        let line = String(decoding: request.prefix(while: { $0 != 13 }), as: UTF8.self).split(separator: " ")
        guard line.count == 3 else { return }
        let path = String(line[1])
        lock.lock(); seen.append(path); lock.unlock()
        let reply = routes(path, port)
        var head = "HTTP/1.1 \(reply.status)\r\nContent-Length: \(reply.body.count)\r\nConnection: close\r\n"
        for (key, value) in reply.headers { head += "\(key): \(value)\r\n" }
        let payload = Data((head + "\r\n").utf8) + (line[0] == "HEAD" ? Data() : reply.body)
        payload.withUnsafeBytes { _ = write(client, $0.baseAddress, payload.count) }
    }
    func stop() { shutdown(descriptor, SHUT_RDWR); close(descriptor) }
}

final class WebDownloadProxyTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws { root = try OutputFiles.temporaryDirectory() }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private static let loopback = WebDownloadProxy.Address.v4(0x7F00_0001)
    private static func fakeResolver(_ names: [String: [WebDownloadProxy.Address]]) -> @Sendable (String) -> [WebDownloadProxy.Address] {
        { host in names[host.lowercased()] ?? WebDownloadProxy.systemResolve(host) }
    }

    /// The status line the proxy answers a raw request with.
    private func ask(_ proxy: WebDownloadProxy, _ request: String) throws -> String {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0); defer { close(descriptor) }
        var address = sockaddr_in(); address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1"); address.sin_port = proxy.port.bigEndian
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard connected == 0 else { throw TwisterError.failed("proxy unreachable") }
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = request.withCString { write(descriptor, $0, strlen($0)) }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(descriptor, &buffer, buffer.count)
        return String(decoding: buffer[0..<max(0, count)], as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
    }

    private func fetch(_ url: URL, through proxy: WebDownloadProxy, redirects: URLSessionTaskDelegate? = nil) async -> (Int?, Data?) {
        let session = URLSession(configuration: proxy.sessionConfiguration(), delegate: redirects, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.timeoutInterval = 10
        guard let (data, response) = try? await session.data(for: request) else { return (nil, nil) }
        return ((response as? HTTPURLResponse)?.statusCode, data)
    }

    func testRequestsAreParsedAndRewrittenToOneOriginRequest() throws {
        let tunnel = try XCTUnwrap(WebDownloadProxy.parse(Data("CONNECT media.example.com:443 HTTP/1.1\r\nHost: media.example.com:443\r\n\r\n".utf8)))
        XCTAssertEqual([tunnel.host, String(tunnel.port)], ["media.example.com", "443"]); XCTAssertTrue(tunnel.tunnel)
        let literal = try XCTUnwrap(WebDownloadProxy.parse(Data("CONNECT [2001:db8::1]:8443 HTTP/1.1\r\n\r\n".utf8)))
        XCTAssertEqual([literal.host, String(literal.port)], ["2001:db8::1", "8443"])
        let plain = try XCTUnwrap(WebDownloadProxy.parse(Data("GET http://example.com:8080/a/b.mp4?x=1 HTTP/1.1\r\nHost: example.com:8080\r\nProxy-Connection: keep-alive\r\nProxy-Authorization: Basic eA==\r\nConnection: keep-alive\r\nRange: bytes=0-\r\n\r\n".utf8)))
        XCTAssertEqual([plain.host, String(plain.port)], ["example.com", "8080"]); XCTAssertFalse(plain.tunnel)
        XCTAssertEqual(String(decoding: plain.head, as: UTF8.self), "GET /a/b.mp4?x=1 HTTP/1.1\r\nHost: example.com:8080\r\nRange: bytes=0-\r\nConnection: close\r\n\r\n")
        for head in ["GET /relative HTTP/1.1\r\n\r\n", "GET https://example.com/ HTTP/1.1\r\n\r\n", "GET ftp://example.com/ HTTP/1.1\r\n\r\n",
                     "CONNECT example.com HTTP/1.1\r\n\r\n", "CONNECT example.com:0 HTTP/1.1\r\n\r\n", "GET http://user:pw@example.com/ HTTP/1.1\r\n\r\n", "garbage\r\n\r\n"] {
            XCTAssertNil(WebDownloadProxy.parse(Data(head.utf8)), head)
        }
    }

    func testANameThatResolvesToThisMacIsRefusedUnlessTheOverrideIsOn() async throws {
        let server = try RoutingServer { _, _ in ("200 OK", ["Content-Type": "image/png"], Data("pixels".utf8)) }
        defer { server.stop() }
        let resolver = Self.fakeResolver(["example.test": [Self.loopback]])
        let refusing = try WebDownloadProxy.start(.init(resolve: resolver))
        defer { refusing.stop() }
        let (status, _) = await fetch(URL(string: "http://example.test:\(server.port)/a.png")!, through: refusing)
        XCTAssertEqual(status, 403)
        let (tunnelled, _) = await fetch(URL(string: "https://example.test:\(server.port)/a.png")!, through: refusing)
        XCTAssertNil(tunnelled)
        // Literal addresses, including other spellings of loopback, are
        // checked the same way. (URLSession itself never proxies a loopback
        // literal; its redirect check refuses those by their text.)
        for host in ["127.0.0.1", "[::1]", "[::ffff:127.0.0.1]", "2130706433", "0x7f000001", "localhost", "192.168.1.1", "169.254.169.254"] {
            XCTAssertEqual(try ask(refusing, "CONNECT \(host):\(server.port) HTTP/1.1\r\n\r\n"), "HTTP/1.1 403 Forbidden", host)
            XCTAssertEqual(try ask(refusing, "GET http://\(host):\(server.port)/a.png HTTP/1.1\r\n\r\n"), "HTTP/1.1 403 Forbidden", host)
        }
        XCTAssertTrue(refusing.refused)
        XCTAssertEqual(server.paths, [], "a refused destination must receive nothing")

        let allowing = try WebDownloadProxy.start(.init(allowLocalNetwork: true, resolve: resolver))
        defer { allowing.stop() }
        let (allowed, body) = await fetch(URL(string: "http://example.test:\(server.port)/a.png")!, through: allowing)
        XCTAssertEqual(allowed, 200); XCTAssertEqual(body, Data("pixels".utf8))
        XCTAssertEqual(server.paths, ["/a.png"])
        XCTAssertFalse(allowing.refused)
    }

    func testTheCheckedAddressIsTheOneConnectedTo() async throws {
        let server = try RoutingServer { _, _ in ("200 OK", [:], Data("ok".utf8)) }
        defer { server.stop() }
        final class Lookups: @unchecked Sendable { let lock = NSLock(); var count = 0 }
        let lookups = Lookups()
        // A rebinding name answers differently on every later lookup.
        let proxy = try WebDownloadProxy.start(.init(resolve: { _ in
            lookups.lock.lock(); defer { lookups.lock.unlock() }; lookups.count += 1
            return lookups.count == 1 ? [Self.loopback] : [.v4(0)]
        }, permits: { _, addresses in addresses == [Self.loopback] }))
        defer { proxy.stop() }
        let (status, body) = await fetch(URL(string: "http://rebinding.test:\(server.port)/")!, through: proxy)
        XCTAssertEqual(status, 200); XCTAssertEqual(body, Data("ok".utf8))
        XCTAssertEqual(lookups.count, 1)
        XCTAssertEqual(server.paths, ["/"])
    }

    func testRedirectsToThisMacAreRefused() async throws {
        let server = try RoutingServer { path, port in
            switch path {
            case "/by-name": return ("302 Found", ["Location": "http://loopback.test:\(port)/private"], Data())
            case "/by-address": return ("302 Found", ["Location": "http://127.0.0.1:\(port)/private"], Data())
            case "/private": return ("200 OK", ["Content-Type": "video/mp4"], Data("private".utf8))
            default: return ("404 Not Found", [:], Data())
            }
        }
        defer { server.stop() }
        let proxy = try WebDownloadProxy.start(.init(resolve: Self.fakeResolver(["public.test": [Self.loopback], "loopback.test": [Self.loopback]]),
                                                     permits: { host, _ in host == "public.test" }))
        defer { proxy.stop() }
        // A name the proxy resolves to this Mac is refused by the proxy.
        let (status, body) = await fetch(URL(string: "http://public.test:\(server.port)/by-name")!, through: proxy)
        XCTAssertNotEqual(body, Data("private".utf8)); XCTAssertEqual(status, 403)
        XCTAssertTrue(proxy.refused)
        // A literal loopback address is refused before it is requested.
        let redirects = WebDownloadEngine.RedirectPolicy(allowLocalNetwork: false)
        let (literal, literalBody) = await fetch(URL(string: "http://public.test:\(server.port)/by-address")!, through: proxy, redirects: redirects)
        XCTAssertNotEqual(literalBody, Data("private".utf8)); XCTAssertEqual(literal, 302)
        XCTAssertTrue(redirects.refused)
        XCTAssertEqual(server.paths, ["/by-name", "/by-address"])
    }

    /// The extractor reaches pages only through the proxy, so neither a
    /// redirect nor a media address inside a page can reach this Mac.
    func testTheExtractorCannotReachThisMacThroughAPublicPage() throws {
        guard let ytdlp = try? Dependencies.executable("yt-dlp"), (try? Dependencies.executable("deno")) != nil, (try? Dependencies.executable("ffmpeg")) != nil else {
            throw XCTSkip("Run scripts/setup-web-download-tools.py and scripts/setup-tools.sh first")
        }
        let clip = Data(repeating: 7, count: 4_096)
        let server = try RoutingServer { path, port in
            func page(_ media: String) -> (String, [String: String], Data) {
                ("200 OK", ["Content-Type": "text/html"], Data("<!doctype html><title>Clip</title><video src=\"\(media)\" type=\"video/mp4\"></video>".utf8))
            }
            switch path {
            case "/embedded": return page("http://127.0.0.1:\(port)/private.mp4")
            case "/redirect": return ("302 Found", ["Location": "http://127.0.0.1:\(port)/embedded"], Data())
            case "/public": return page("http://public.test:\(port)/clip.mp4")
            case "/clip.mp4", "/private.mp4": return ("200 OK", ["Content-Type": "video/mp4"], clip)
            default: return ("404 Not Found", [:], Data())
            }
        }
        defer { server.stop() }
        let proxy = try WebDownloadProxy.start(.init(resolve: Self.fakeResolver(["public.test": [Self.loopback]]), permits: { host, _ in host == "public.test" }))
        defer { proxy.stop() }
        func download(_ path: String, into name: String) throws -> Data {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let arguments = try WebDownloadEngine.baseArguments(proxy: proxy) + ["--no-simulate", "--downloader", "native", "--format", "best",
                "--output", directory.appendingPathComponent("%(id)s.%(ext)s").path, "--print", "after_move:TWISTER_FILE:%(filepath)j", "--", "http://public.test:\(server.port)\(path)"]
            return try WebDownloadProcess.run(ytdlp, arguments, token: .init(), timeout: 120)
        }
        let saved = try download("/public", into: "public")
        XCTAssertTrue(String(decoding: saved, as: UTF8.self).contains("TWISTER_FILE:"))
        XCTAssertFalse(proxy.refused)
        XCTAssertThrowsError(try download("/embedded", into: "embedded"))
        XCTAssertThrowsError(try download("/redirect", into: "redirect"))
        XCTAssertTrue(proxy.refused)
        XCTAssertFalse(server.paths.contains("/private.mp4"), "\(server.paths)")
        XCTAssertEqual(server.paths.filter { $0 == "/embedded" }.count, 1, "only the page fetched through the allowed name: \(server.paths)")
    }

    func testProxySettingsFromTheEnvironmentDoNotReachTheExtractor() {
        let environment = ["PATH": "/usr/bin", "HTTP_PROXY": "http://elsewhere:3128", "https_proxy": "x", "ALL_PROXY": "x", "no_proxy": "*", "NO_PROXY": "*", "HOME": "/tmp"]
        XCTAssertEqual(WebDownloadProcess.childEnvironment(environment), ["PATH": "/usr/bin", "HOME": "/tmp"])
    }

    func testExtractorArgumentsNameTheProxy() throws {
        let proxy = try WebDownloadProxy.start(.init())
        defer { proxy.stop() }
        guard (try? Dependencies.executable("deno")) != nil, (try? Dependencies.executable("ffmpeg")) != nil else { throw XCTSkip("Web download tools are not installed") }
        let arguments = try WebDownloadEngine.baseArguments(proxy: proxy)
        let index = try XCTUnwrap(arguments.firstIndex(of: "--proxy"))
        XCTAssertEqual(arguments[index + 1], "http://127.0.0.1:\(proxy.port)")
        XCTAssertGreaterThan(proxy.port, 0)
    }
}
