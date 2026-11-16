import AppKit

/// The entries Twister adds to the Services menu for files. The raw value is
/// the NSMessage of the entry in Info.plist.
public enum FinderService:String,CaseIterable,Sendable {
    case open="openInTwister",convert="convertWithTwister",preset="runTwisterPreset"
    public var menuTitle:String {
        switch self {
        case .open:return "Open in Twister"
        case .convert:return "Convert with Twister…"
        case .preset:return "Run Twister Preset…"
        }
    }
}

public enum FinderServiceError:LocalizedError,Equatable {
    case noFiles,noFormats,noPresets
    public var errorDescription:String? {
        switch self {
        case .noFiles:return "Select at least one file to use this service."
        case .noFormats:return "Twister cannot convert these files together."
        case .noPresets:return "No preset fits these files. Save one in Twister first."
        }
    }
}

/// What a service invocation asks for, read from the pasteboard the system hands over.
public struct FinderServiceRequest:Sendable {
    public let service:FinderService
    public let files:[URL]
    /// The formats every file converts to, for the conversion chooser.
    public let formats:[String]
    /// The saved presets that fit every file, in their saved order.
    public let presets:[Preset]

    public init(_ service:FinderService,pasteboard:NSPasteboard,presets:[Preset]=[]) throws {
        let files=Self.files(on:pasteboard)
        guard !files.isEmpty else { throw FinderServiceError.noFiles }
        self.service=service;self.files=files
        formats=service == .convert ? FeatureCatalog.formats(for:files):[]
        self.presets=service == .preset ? presets.filter { $0.applies(to:files) }:[]
        if service == .convert,formats.isEmpty { throw FinderServiceError.noFormats }
        if service == .preset,self.presets.isEmpty { throw FinderServiceError.noPresets }
    }

    /// Existing local files in the order given, each once. Web links and missing paths are left out.
    public static func files(on pasteboard:NSPasteboard)->[URL] {
        var urls=(pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL]) ?? []
        if urls.isEmpty,let paths=pasteboard.propertyList(forType:NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] { urls=paths.map { URL(fileURLWithPath:$0) } }
        var seen=Set<String>()
        return urls.map(\.standardizedFileURL).filter { $0.isFileURL && FileManager.default.fileExists(atPath:$0.path) && seen.insert($0.path).inserted }
    }
}
