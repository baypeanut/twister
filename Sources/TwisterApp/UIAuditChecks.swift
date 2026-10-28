import Foundation
import AppKit
import ImageIO
import zlib

/// Adversarial geometry cases keep an audit failure meaningful. These checks
/// exercise the report validator without launching a window or changing state.
@MainActor enum UIAuditChecks {
    @discardableResult static func run()throws->[String] {
        let bounds=CGRect(x:0,y:0,width:900,height:420)
        let valid:[String:CGRect]=[
            "editor.header":CGRect(x:0,y:0,width:900,height:80),
            "editor.body":CGRect(x:0,y:81,width:900,height:250),
            "editor.preview":CGRect(x:0,y:81,width:480,height:250),
            "editor.options":CGRect(x:481,y:81,width:419,height:250),
            "editor.footer":CGRect(x:0,y:332,width:900,height:88),
            "editor.reset":CGRect(x:20,y:350,width:100,height:48),
            "editor.primary":CGRect(x:600,y:350,width:280,height:48),
            "editor.primary.label":CGRect(x:620,y:364,width:240,height:20)
        ]
        var checks:[String]=[]
        func check(_ condition:Bool,_ message:String)throws {
            guard condition else{throw UIAuditError("Layout validator check failed: "+message)}
            checks.append(message)
        }
        func issues(_ changes:[String:CGRect?]=[:],in visible:CGRect?=nil)->[String] {
            let recorder=UIAuditLayout();recorder.frames=valid
            for (name,frame) in changes {if let frame {recorder.frames[name]=frame}else{recorder.frames[name]=nil}}
            return recorder.issues(in:visible ?? bounds,editor:true)
        }
        try check(issues().isEmpty,"Accepts an aligned, contained editor layout")
        try check(issues(["editor.options":nil]).contains("Missing layout probe: editor.options"),"Rejects a missing required layout probe")
        try check(issues(["editor.preview":nil]).contains("Missing layout probe: editor.preview"),"Rejects an unmeasured editor preview")
        try check(issues(["editor.primary.label":CGRect(x:630,y:364,width:240,height:20)]).contains("Primary button label is not centered"),"Detects a label shifted within a sufficiently large button")
        try check(issues(["editor.primary.label":CGRect(x:590,y:364,width:300,height:20)]).contains("Primary button label is clipped"),"Detects centered text that exceeds the button bounds")
        try check(issues(["editor.primary":CGRect(x:100,y:350,width:280,height:48)]).contains("Footer controls overlap"),"Detects overlapping footer action targets")
        try check(issues(["editor.reset":CGRect(x:20,y:300,width:100,height:48)]).contains("Footer control is clipped: editor.reset"),"Detects a footer control extending into the body")
        try check(issues(["editor.options":CGRect(x:481,y:70,width:419,height:250)]).contains("Body region is clipped: editor.options"),"Detects options extending outside their body region")
        try check(issues(["editor.body":CGRect(x:0,y:70,width:900,height:261)]).contains("Body overlaps: editor.header"),"Detects body content overlapping the header")
        try check(issues(["editor.footer":CGRect(x:0,y:322,width:900,height:98)]).contains("Body overlaps: editor.footer"),"Detects body content overlapping the footer")
        try check(issues(["editor.options":CGRect(x:481,y:81,width:430,height:250)]).contains("Outside visible content: editor.options"),"Detects content extending past the visible right edge")
        try check(issues(["editor.options":CGRect(x:481,y:81,width:0,height:250)]).contains("Invalid layout frame: editor.options"),"Rejects a zero-sized layout frame")
        try check(issues(["editor.options":CGRect(x:481,y:81,width:Double.nan,height:250)]).contains("Invalid layout frame: editor.options"),"Rejects non-finite geometry")
        try check(issues(in:.zero)==["Invalid visible content bounds"],"Rejects a zero-sized visible surface")
        let noProbe=UIAuditLayout()
        try check(noProbe.issues(in:bounds,editor:true).count==valid.count,"An empty editor measurement cannot pass")
        var pixels=[UInt8](repeating:0,count:64*64*4)
        func raster()throws->UIAuditRaster {
            let provider=CGDataProvider(data:Data(pixels) as CFData)!
            guard let image=CGImage(width:64,height:64,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:256,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else{throw UIAuditError("Raster validator fixture allocation failed")}
            return UIAuditRaster.inspect(NSBitmapImageRep(cgImage:image))
        }
        try check(!raster().nonBlank,"Rejects a fully transparent scene capture")
        for offset in stride(from:0,to:pixels.count,by:4) {pixels[offset]=128;pixels[offset+1]=128;pixels[offset+2]=128;pixels[offset+3]=255}
        try check(!raster().nonBlank,"Rejects a uniform scene capture")
        for y in 0..<64 {for x in 0..<64 {let offset=(y*64+x)*4;pixels[offset]=x<21 ? 255:0;pixels[offset+1]=(21..<42).contains(x) ? 255:0;pixels[offset+2]=x>=42 ? 255:0}}
        let sampled=try raster()
        try check(sampled.nonBlank && sampled.samples==4096 && sampled.colors==3,"Accepts a visible scene with sampled color variation")
        let selected=Array(repeating:URL(fileURLWithPath:"/tmp/twister-scope-fixture"),count:20_000)
        try check(withGrantedFolderAccess(selected) { true },"Acquires a 20,000-file selection without recursive stack growth")

        let suite="Twister.InputAudit."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let state=AppState(defaults:defaults),file=URL(fileURLWithPath:"/tmp/twister-input-fixture")
        state.inputs=[file];state.outputs=[file];state.inputs=[file]
        try check(state.outputs==[file],"Reusing the same selection preserves completed outputs")
        state.inputs=[file.appendingPathExtension("new")]
        try check(state.outputs.isEmpty,"Changing the selection clears stale completed outputs")

        // A private clipboard and temporary destination keep the user's data
        // outside the audit. Inspect dimensions before any oversized decode.
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("Twister-ClipboardAudit-"+UUID().uuidString)
        let board=NSPasteboard.withUniqueName()
        defer { board.releaseGlobally();try? FileManager.default.removeItem(at:folder) }
        let context=CGContext(data:nil,width:6,height:3,bitsPerComponent:8,bytesPerRow:24,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1));context.fill(CGRect(x:0,y:0,width:6,height:3))
        let encoded=NSMutableData()
        let encoder=CGImageDestinationCreateWithData(encoded,"public.tiff" as CFString,1,nil)!
        CGImageDestinationAddImage(encoder,context.makeImage()!,[kCGImagePropertyOrientation:6] as CFDictionary)
        try check(CGImageDestinationFinalize(encoder),"Creates a rotated clipboard image fixture")
        board.setData(encoded as Data,forType:.tiff)
        let pasted=try ClipboardImport.read(board,directory:folder)
        let image=try NSBitmapImageRep(data:Data(contentsOf:pasted.urls[0]))
        try check(image?.pixelsWide==3 && image?.pixelsHigh==6,"Clipboard import applies encoded image orientation")

        // A valid one-bit PNG compresses to ~12 KB but declares over 100M
        // pixels. Building scanline bytes does not allocate an image raster.
        let dimension=10_001
        let scanlines=[UInt8](repeating:0,count:((dimension+7)/8+1)*dimension)
        var compressed=[UInt8](repeating:0,count:Int(compressBound(uLong(scanlines.count))))
        var compressedCount=uLongf(compressed.count)
        try check(compress2(&compressed,&compressedCount,scanlines,uLong(scanlines.count),Z_BEST_COMPRESSION)==Z_OK,"Creates a valid compressed oversized clipboard fixture")
        var oversized=Data([137,80,78,71,13,10,26,10])
        func bigEndian(_ number:UInt32)->Data {
            var value=number.bigEndian
            return withUnsafeBytes(of:&value) { Data($0) }
        }
        func appendChunk(_ name:String,_ payload:Data) {
            let content=Data(name.utf8)+payload
            let checksum=content.withUnsafeBytes { crc32(0,$0.bindMemory(to:Bytef.self).baseAddress,uInt(content.count)) }
            oversized.append(bigEndian(UInt32(payload.count)));oversized.append(content);oversized.append(bigEndian(UInt32(checksum)))
        }
        appendChunk("IHDR",bigEndian(UInt32(dimension))+bigEndian(UInt32(dimension))+Data([1,0,0,0,0]))
        appendChunk("IDAT",Data(compressed.prefix(Int(compressedCount))))
        appendChunk("IEND",Data())
        let source=CGImageSourceCreateWithData(oversized as CFData,nil)!
        let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as! [CFString:Any]
        try check((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue==dimension && (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue==dimension,"Oversized clipboard fixture declares dimensions without raster allocation")
        let before=try FileManager.default.contentsOfDirectory(atPath:folder.path)
        board.clearContents();board.setData(oversized,forType:.png)
        var rejected=false
        do { _=try ClipboardImport.read(board,directory:folder) }
        catch ClipboardImport.ImportError.imageTooLarge { rejected=true }
        try check(rejected,"Rejects oversized clipboard metadata before image decoding")
        try check(try FileManager.default.contentsOfDirectory(atPath:folder.path)==before,"Rejected clipboard imagery produces no partial import")
        checks += try PDFEditingKeyboardChecks.run()
        return checks
    }
}
