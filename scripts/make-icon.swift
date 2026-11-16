import AppKit

@main struct MakeTwisterIcon {
    static func main()throws {
        guard CommandLine.arguments.count==2 else{fatalError("Usage: make-icon OUTPUT_DIRECTORY")}
        let output=URL(fileURLWithPath:CommandLine.arguments[1])
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func bitmap(_ width:Int,_ height:Int,_ draw:(NSRect)->Void)->NSBitmapImageRep {
            let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
            draw(NSRect(x:0,y:0,width:width,height:height));NSGraphicsContext.restoreGraphicsState();return rep
        }
        let mark=bitmap(256,256){rect in TwisterArtwork.draw(in:rect,color:.systemBlue)}
        for name in ["TwisterMark.png","TwisterMarkHappy.png"] {
            try mark.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name))
        }
        let icon=bitmap(1024,1024) {_ in
            // The standard macOS icon grid: an 824-point body in a 1024 canvas, with the system's soft drop shadow.
            let body=NSRect(x:100,y:100,width:824,height:824)
            let background=NSBezierPath(roundedRect:body,xRadius:185,yRadius:185)
            NSGraphicsContext.saveGraphicsState()
            let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.3);shadow.shadowBlurRadius=20;shadow.shadowOffset=NSSize(width:0,height:-10);shadow.set()
            NSColor.white.setFill();background.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGradient(starting:NSColor(srgbRed:0.10,green:0.42,blue:0.92,alpha:1),ending:NSColor(srgbRed:0.31,green:0.66,blue:1.0,alpha:1))!.draw(in:background,angle:90)
            TwisterArtwork.draw(in:NSRect(x:262,y:222,width:500,height:580),color:.white)
        }
        let png=icon.representation(using:.png,properties:[:])!
        try png.write(to:output.appendingPathComponent("TwisterIcon.png"))
        let iconset=output.appendingPathComponent("TwisterIcon.iconset")
        try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
        let image=NSImage(data:png)!
        for size in [16,32,128,256,512] {for factor in [1,2] {
            let pixels=size*factor
            let rep=bitmap(pixels,pixels){rect in NSGraphicsContext.current?.imageInterpolation = .high;image.draw(in:rect)}
            try rep.representation(using:.png,properties:[:])!.write(to:iconset.appendingPathComponent("icon_\(size)x\(size)\(factor==2 ? "@2x":"").png"))
        }}
        print(output.path)
    }
}
