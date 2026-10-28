import AppKit
import ImageIO
import TwisterCore

/// Persist pasted content outside the application bundle, so updates keep it intact.
@MainActor enum ClipboardImport {
    struct Result { var urls:[URL]=[];var link:URL?;var label:String }
    static func read(_ pasteboard:NSPasteboard = .general,directory:URL?=nil)throws->Result {
        if let urls=pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],!urls.isEmpty {
            var seen=Set<URL>();let existing=urls.filter{FileManager.default.fileExists(atPath:$0.path) && seen.insert($0).inserted}
            guard !existing.isEmpty else { throw ImportError.unavailable };return Result(urls:existing,label:"Pasted files")
        }
        let folder=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Twister/Imports",isDirectory:true)
        func destination(_ ext:String)throws->URL {try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);let date=DateFormatter();date.dateFormat="yyyy-MM-dd HH-mm-ss";return folder.appendingPathComponent("Clipboard \(date.string(from:Date()))-\(UUID().uuidString.prefix(6)).\(ext)")}
        if let type=pasteboard.availableType(from:[.png,.tiff]),let data=pasteboard.data(forType:type) {
            // Inspect encoded dimensions before asking ImageIO to allocate the
            // raster. NSImage.tiffRepresentation would decode before this guard.
            guard data.count<=64*1024*1024,
                  let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
                  let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
                  let width=(properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int64Value,
                  let height=(properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int64Value,
                  width>0,height>0,width<=100_000_000/height,
                  let image=CGImageSourceCreateThumbnailAtIndex(source,0,[
                    kCGImageSourceCreateThumbnailFromImageAlways:true,
                    kCGImageSourceCreateThumbnailWithTransform:true,
                    kCGImageSourceThumbnailMaxPixelSize:max(width,height)
                  ] as CFDictionary) else { throw ImportError.imageTooLarge }
            let rep=NSBitmapImageRep(cgImage:image)
            guard let png=rep.representation(using:.png,properties:[:]) else { throw ImportError.imageTooLarge }
            let url=try destination("png");try png.write(to:url,options:.atomic);return Result(urls:[url],label:"Pasted image")
        }
        guard let text=pasteboard.string(forType:.string),!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {throw ImportError.empty}
        let trimmed=text.trimmingCharacters(in:.whitespacesAndNewlines)
        if let url=URL(string:trimmed),["http","https"].contains(url.scheme?.lowercased() ?? ""),url.host != nil,!trimmed.contains(where:{$0.isWhitespace}) {return Result(link:url,label:"Copied link")}
        guard text.utf8.count<=16*1024*1024 else {throw ImportError.textTooLarge}
        let url=try destination("txt");try Data(text.utf8).write(to:url,options:.atomic);return Result(urls:[url],label:"Pasted text")
    }
    enum ImportError:LocalizedError {
        case empty,unavailable,imageTooLarge,textTooLarge
        var errorDescription:String? {switch self {case .empty:return "Copy a file, some text, an image or a public media link first.";case .unavailable:return "Those files are no longer available.";case .imageTooLarge:return "This image is too large to paste. Choose the image file instead.";case .textTooLarge:return "This text is too large to paste. Choose a text file instead."}}
    }
}
