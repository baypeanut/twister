import Foundation
import Network
import Darwin

/// A loopback HTTP proxy that exists only while one web download or
/// inspection runs. Every connection the extractor or URLSession makes goes
/// through it, including redirects and media addresses found inside pages.
/// The proxy resolves each destination itself, refuses addresses that are not
/// public, and connects to exactly the address it checked.
final class WebDownloadProxy: @unchecked Sendable {
    /// One resolved destination address.
    enum Address: Equatable, CustomStringConvertible {
        case v4(UInt32), v6([UInt8])
        var isLocal: Bool {
            switch self {
            case .v4(let value): return NetworkAddress.isLocal(ipv4: value)
            case .v6(let bytes): return NetworkAddress.isLocal(ipv6: bytes)
            }
        }
        var host: NWEndpoint.Host? {
            switch self {
            case .v4(let value): return IPv4Address(withUnsafeBytes(of: value.bigEndian) { Data($0) }).map { .ipv4($0) }
            case .v6(let bytes): return IPv6Address(Data(bytes)).map { .ipv6($0) }
            }
        }
        var description: String { host.map { "\($0)" } ?? "?" }
    }

    struct Policy: Sendable {
        /// The user's own override; then every destination is allowed.
        var allowLocalNetwork = false
        var resolve: @Sendable (String) -> [Address] = WebDownloadProxy.systemResolve
        /// Whether a destination may be reached. By default the name must not
        /// be a local one and no address it resolves to may be local.
        var permits: (@Sendable (_ host: String, _ addresses: [Address]) -> Bool)? = nil

        /// A name or literal that is local by its text is refused before any lookup.
        func allowsName(_ host: String) -> Bool { allowLocalNetwork || permits != nil || !NetworkAddress.isLocal(host: host) }
        func allows(_ host: String, _ addresses: [Address]) -> Bool {
            if allowLocalNetwork { return !addresses.isEmpty }
            if let permits { return permits(host, addresses) }
            return !addresses.isEmpty && !NetworkAddress.isLocal(host: host) && !addresses.contains(where: \.isLocal)
        }
    }

    private let policy: Policy
    private let queue = DispatchQueue(label: "Twister.WebDownloadProxy")
    private let lock = NSLock()
    private var listener: NWListener?
    private var tunnels: [ObjectIdentifier: Tunnel] = [:]
    private var refusals = 0
    private static let maximumTunnels = 64
    private static let maximumHead = 32 * 1024

    private(set) var port: UInt16 = 0
    /// True once any destination was refused.
    var refused: Bool { lock.lock(); defer { lock.unlock() }; return refusals > 0 }

    init(policy: Policy) { self.policy = policy }

    /// Starts listening on 127.0.0.1 at a port the system chooses.
    static func start(_ policy: Policy) throws -> WebDownloadProxy {
        let proxy = WebDownloadProxy(policy: policy)
        try proxy.listen()
        return proxy
    }

    /// The `--proxy` argument for the extractor.
    var address: String { "http://127.0.0.1:\(port)" }

    /// The proxy settings for URLSession. Nothing bypasses it.
    var connectionProxyDictionary: [AnyHashable: Any] {
        [kCFNetworkProxiesHTTPEnable as String: true, kCFNetworkProxiesHTTPProxy as String: "127.0.0.1", kCFNetworkProxiesHTTPPort as String: Int(port),
         kCFNetworkProxiesHTTPSEnable as String: true, kCFNetworkProxiesHTTPSProxy as String: "127.0.0.1", kCFNetworkProxiesHTTPSPort as String: Int(port),
         kCFNetworkProxiesExceptionsList as String: [String](), kCFNetworkProxiesExcludeSimpleHostnames as String: false]
    }

    /// An ephemeral session configuration that sends everything through this proxy.
    func sessionConfiguration(_ base: URLSessionConfiguration = .ephemeral) -> URLSessionConfiguration {
        let configuration = base.copy() as! URLSessionConfiguration
        configuration.connectionProxyDictionary = connectionProxyDictionary
        return configuration
    }

    private func listen() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.acceptLocalOnly = true
        parameters.allowLocalEndpointReuse = false
        let listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        var failure: Error?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let error): failure = error; ready.signal()
            case .cancelled: ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 10) == .success, failure == nil, let port = listener.port?.rawValue, port > 0 else {
            listener.cancel()
            throw TwisterError.failed("The download connection could not be prepared.")
        }
        self.listener = listener
        self.port = port
    }

    /// Closes the listener and every open connection.
    func stop() {
        lock.lock(); let listener = self.listener; self.listener = nil; let open = Array(tunnels.values); tunnels = [:]; lock.unlock()
        listener?.cancel()
        queue.async { for tunnel in open { tunnel.close() } }
    }

    deinit { stop() }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        guard listener != nil, tunnels.count < Self.maximumTunnels else { lock.unlock(); connection.cancel(); return }
        let tunnel = Tunnel(client: connection, proxy: self)
        tunnels[ObjectIdentifier(tunnel)] = tunnel
        lock.unlock()
        tunnel.start(queue: queue)
    }

    fileprivate func finished(_ tunnel: Tunnel) {
        lock.lock(); tunnels[ObjectIdentifier(tunnel)] = nil; lock.unlock()
    }

    fileprivate func noteRefusal() { lock.lock(); refusals += 1; lock.unlock() }

    /// The request a client sent, read from the head of its connection.
    struct Request: Equatable {
        let tunnel: Bool
        let host: String
        let port: UInt16
        /// For a plain HTTP request: the head to send upstream in origin form.
        let head: Data
    }

    /// Parses `CONNECT host:port` or an absolute-form `http://` request.
    static func parse(_ head: Data) -> Request? {
        guard let text = String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1) else { return nil }
        var lines = text.components(separatedBy: "\r\n")
        guard let line = lines.first else { return nil }
        let parts = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1."), !parts[0].isEmpty,
              parts[0].unicodeScalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }) else { return nil }
        if parts[0] == "CONNECT" {
            guard let (host, port) = authority(parts[1], defaultPort: nil) else { return nil }
            return Request(tunnel: true, host: host, port: port, head: Data())
        }
        guard let components = URLComponents(string: parts[1]), components.scheme?.lowercased() == "http",
              components.user == nil, components.password == nil, let host = components.host, !host.isEmpty else { return nil }
        let port = components.port ?? 80
        guard (1...65_535).contains(port) else { return nil }
        let path = (components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath) + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        lines.removeFirst()
        // Hop-by-hop and proxy headers stay here; the upstream connection
        // carries this one request only.
        let dropped: Set<String> = ["proxy-connection", "proxy-authorization", "connection", "keep-alive"]
        var headers = lines.prefix { !$0.isEmpty }.filter { header in
            guard let colon = header.firstIndex(of: ":") else { return false }
            return !dropped.contains(header[..<colon].trimmingCharacters(in: .whitespaces).lowercased())
        }
        if !headers.contains(where: { $0.lowercased().hasPrefix("host:") }) {
            headers.insert("Host: " + (host.contains(":") ? "[\(host)]" : host) + (components.port.map { ":\($0)" } ?? ""), at: 0)
        }
        headers.append("Connection: close")
        let rewritten = ([parts[0] + " " + path + " " + parts[2]] + headers).joined(separator: "\r\n") + "\r\n\r\n"
        return Request(tunnel: false, host: host, port: UInt16(port), head: Data(rewritten.utf8))
    }

    private static func authority(_ value: String, defaultPort: UInt16?) -> (String, UInt16)? {
        var host: Substring, portText: Substring?
        if value.hasPrefix("[") {
            guard let close = value.firstIndex(of: "]") else { return nil }
            host = value[value.index(after: value.startIndex)..<close]
            let rest = value[value.index(after: close)...]
            if rest.isEmpty { portText = nil } else { guard rest.hasPrefix(":") else { return nil }; portText = rest.dropFirst() }
        } else {
            guard let colon = value.lastIndex(of: ":"), !value[..<colon].contains(":") else { return defaultPort.map { (value, $0) } }
            host = value[..<colon]; portText = value[value.index(after: colon)...]
        }
        guard !host.isEmpty, let port = portText.flatMap({ UInt16($0) }) ?? defaultPort, port > 0 else { return nil }
        return (String(host), port)
    }

    /// The addresses of a name, or of a literal address, from the system resolver.
    @Sendable static func systemResolve(_ host: String) -> [Address] {
        var hints = addrinfo(ai_flags: AI_ADDRCONFIG, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: IPPROTO_TCP, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return [] }
        defer { freeaddrinfo(first) }
        var addresses: [Address] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let entry = cursor {
            if let address = entry.pointee.ai_addr {
                switch Int32(address.pointee.sa_family) {
                case AF_INET:
                    addresses.append(.v4(address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }))
                case AF_INET6:
                    addresses.append(.v6(address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in withUnsafeBytes(of: pointer.pointee.sin6_addr) { Array($0) } }))
                default: break
                }
            }
            cursor = entry.pointee.ai_next
        }
        return addresses
    }

    /// One client connection and, once its destination is allowed, the
    /// upstream connection it is joined to.
    fileprivate final class Tunnel: @unchecked Sendable {
        let client: NWConnection
        weak var proxy: WebDownloadProxy?
        private let policy: Policy
        private var upstream: NWConnection?
        private var head = Data()
        private var closed = false
        private var openDirections = 2
        private var queue: DispatchQueue!

        init(client: NWConnection, proxy: WebDownloadProxy) { self.client = client; self.proxy = proxy; policy = proxy.policy }

        func start(queue: DispatchQueue) {
            self.queue = queue
            client.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .cancelled: self?.queue.async { self?.close() }
                default: break
                }
            }
            client.start(queue: queue)
            readHead()
        }

        private func readHead() {
            client.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, complete, error in
                guard let self, !self.closed else { return }
                if let data { self.head.append(data) }
                if let end = self.head.range(of: Data("\r\n\r\n".utf8)) {
                    let request = self.head[..<end.upperBound], rest = self.head[end.upperBound...]
                    self.route(Data(request), rest: Data(rest))
                } else if error != nil || complete || self.head.count > WebDownloadProxy.maximumHead {
                    self.respond("400 Bad Request")
                } else { self.readHead() }
            }
        }

        private func route(_ head: Data, rest: Data) {
            guard let request = WebDownloadProxy.parse(head) else { respond("400 Bad Request"); return }
            let policy = self.policy
            guard policy.allowsName(request.host) else { proxy?.noteRefusal(); respond("403 Forbidden"); return }
            // The lookup blocks; it runs off the proxy's queue.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let addresses = policy.resolve(request.host)
                let allowed = policy.allows(request.host, addresses)
                self?.queue.async {
                    guard let self, !self.closed else { return }
                    guard allowed else { self.proxy?.noteRefusal(); self.respond("403 Forbidden"); return }
                    self.connect(addresses.compactMap(\.host), port: request.port, request: request, rest: rest)
                }
            }
        }

        /// Tries each checked address in turn; nothing is looked up again.
        private func connect(_ hosts: [NWEndpoint.Host], port: UInt16, request: Request, rest: Data) {
            guard let host = hosts.first, let endpointPort = NWEndpoint.Port(rawValue: port) else { respond("502 Bad Gateway"); return }
            let parameters = NWParameters.tcp
            parameters.preferNoProxies = true
            let upstream = NWConnection(host: host, port: endpointPort, using: parameters)
            self.upstream = upstream
            var established = false
            upstream.stateUpdateHandler = { [weak self] state in
                guard let self, !self.closed else { upstream.cancel(); return }
                switch state {
                case .ready:
                    established = true
                    if request.tunnel {
                        self.client.send(content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), completion: .contentProcessed { _ in })
                        if !rest.isEmpty { upstream.send(content: rest, completion: .contentProcessed { _ in }) }
                    } else {
                        upstream.send(content: request.head + rest, completion: .contentProcessed { _ in })
                    }
                    self.pipe(from: self.client, to: upstream)
                    self.pipe(from: upstream, to: self.client)
                case .waiting, .failed:
                    guard !established else { self.close(); return }
                    upstream.stateUpdateHandler = nil; upstream.cancel()
                    self.connect(Array(hosts.dropFirst()), port: port, request: request, rest: rest)
                case .cancelled: if established { self.close() }
                default: break
                }
            }
            upstream.start(queue: queue)
        }

        private func pipe(from source: NWConnection, to target: NWConnection) {
            source.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, complete, error in
                guard let self, !self.closed else { return }
                if error != nil { self.close(); return }
                let finish = { [weak self] in
                    guard let self else { return }
                    target.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in })
                    self.openDirections -= 1
                    if self.openDirections <= 0 { self.close() }
                }
                if let data, !data.isEmpty {
                    target.send(content: data, completion: .contentProcessed { [weak self] sendError in
                        guard let self else { return }
                        self.queue.async {
                            guard !self.closed else { return }
                            if sendError != nil { self.close() } else if complete { finish() } else { self.pipe(from: source, to: target) }
                        }
                    })
                } else if complete { finish() }
                else { self.pipe(from: source, to: target) }
            }
        }

        private func respond(_ status: String) {
            guard !closed else { return }
            let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            client.send(content: Data(response.utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
                self?.queue.async { self?.close() }
            })
        }

        func close() {
            guard !closed else { return }
            closed = true
            upstream?.cancel(); client.cancel()
            proxy?.finished(self)
        }
    }
}
