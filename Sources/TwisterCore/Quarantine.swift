import Foundation
import Darwin
import CoreServices

/// Gatekeeper assesses an item only while it carries the quarantine
/// attribute. Outputs derived from a quarantined input keep the input's
/// attribute, and downloads receive a new one, so an executable taken from a
/// downloaded archive is still checked when it is opened.
public enum Quarantine {
    static let attribute = "com.apple.quarantine"
    static let agentName = "Twister"
    /// kQTNFlagUserApproved: the user already confirmed opening this item.
    private static let userApproved: UInt32 = 0x0040

    /// The raw attribute value of the item itself; a link is not followed.
    public static func value(of url: URL) -> Data? {
        let size = getxattr(url.path, attribute, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, attribute, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        return read > 0 ? data.prefix(read) : nil
    }

    /// The attribute derived items receive: the first quarantined input's,
    /// without its approval, so the derived items are assessed themselves.
    static func inherited(from inputs: [URL]) -> Data? {
        inputs.lazy.compactMap { value(of: $0.standardizedFileURL) }.first.map(unapproved)
    }

    static func unapproved(_ value: Data) -> Data {
        guard let text = String(data: value, encoding: .utf8),
              let separator = text.firstIndex(of: ";"),
              let flags = UInt32(text[..<separator], radix: 16) else { return value }
        let cleared = String(format: "%04x", flags & ~userApproved)
        return Data((cleared + text[separator...]).utf8)
    }

    /// Labels the item and, for a folder, everything inside it. Links are
    /// labelled themselves and never followed.
    static func apply(_ value: Data, to url: URL) throws {
        try set(value, at: url.path)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue,
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              let children = FileManager.default.enumerator(atPath: url.path) else { return }
        for case let child as String in children { try set(value, at: url.appendingPathComponent(child).path) }
    }

    /// Copies the quarantine of the inputs, if any, onto every output.
    static func propagate(from inputs: [URL], to outputs: [URL]) throws {
        guard let value = inherited(from: inputs) else { return }
        for output in outputs { try apply(value, to: output) }
    }

    /// New quarantine for files received from the network.
    static func markDownloaded(_ urls: [URL], data: URL?, origin: URL?) throws {
        var properties: [String: Any] = [
            kLSQuarantineAgentNameKey as String: agentName,
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String
        ]
        if let data { properties[kLSQuarantineDataURLKey as String] = data }
        if let origin { properties[kLSQuarantineOriginURLKey as String] = origin }
        for url in urls {
            var values = URLResourceValues()
            values.quarantineProperties = properties
            var target = url
            try target.setResourceValues(values)
            if let value = value(of: url) { try apply(value, to: url) }
        }
    }

    /// Removes the attribute from a verified item that Twister runs itself.
    static func remove(from url: URL) {
        func clear(_ path: String) { _ = writable(path) { removexattr(path, attribute, XATTR_NOFOLLOW) } }
        clear(url.path)
        guard let children = FileManager.default.enumerator(atPath: url.path) else { return }
        for case let child as String in children { clear(url.appendingPathComponent(child).path) }
    }

    /// Changing an attribute needs write permission on the item. A read-only
    /// file or folder Twister owns is made writable for its owner only while
    /// the attribute changes, then gets its exact mode back.
    private static func writable(_ path: String, _ change: () -> Int32) -> Int32 {
        let status = change()
        guard status != 0, errno == EACCES || errno == EPERM else { return status }
        let failure = errno
        var info = stat()
        guard lstat(path, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IWUSR == 0,
              [S_IFREG, S_IFDIR].contains(info.st_mode & S_IFMT) else { errno = failure; return status }
        let mode = info.st_mode & 0o7777
        guard chmod(path, mode | S_IWUSR) == 0 else { errno = failure; return status }
        let retried = change(), retryFailure = errno
        chmod(path, mode)
        errno = retryFailure
        return retried
    }

    private static func set(_ value: Data, at path: String) throws {
        let status = writable(path) { value.withUnsafeBytes { setxattr(path, attribute, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW) } }
        guard status != 0 else { return }
        let failure = errno
        var info = stat()
        // Volumes without extended attributes cannot carry the label at all,
        // and a link is never opened by itself.
        let link = lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFLNK
        guard failure == ENOTSUP || link else {
            throw TwisterError.failed("Could not keep the download safety label on \((path as NSString).lastPathComponent).")
        }
    }
}
