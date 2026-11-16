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
        let mark=bitmap(256,256){rect in TwisterArtwork.draw(in:rect,rest:NSColor(srgbRed:0.56,green:0.56,blue:0.58,alpha:1),selected:NSColor(srgbRed:1.0,green:0.58,blue:0.0,alpha:1),hub:NSColor(srgbRed:0.56,green:0.56,blue:0.58,alpha:1))}
        for name in ["TwisterMark.png","TwisterMarkHappy.png"] {
            try mark.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name))
        }
        let icon=bitmap(1024,1024) {_ in
            // The standard macOS icon grid: an 824-point body in a 1024 canvas, with the system's soft drop shadow.
            let body=NSBezierPath(roundedRect:NSRect(x:100,y:100,width:824,height:824),xRadius:185,yRadius:185)
            func shadowed(_ alpha:CGFloat,_ blur:CGFloat,_ drop:CGFloat,_ draw:()->Void) {
                NSGraphicsContext.saveGraphicsState()
                let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(alpha);shadow.shadowBlurRadius=blur;shadow.shadowOffset=NSSize(width:0,height:-drop);shadow.set()
                draw();NSGraphicsContext.restoreGraphicsState()
            }
            let top=NSColor(srgbRed:0.36,green:0.36,blue:0.40,alpha:1),bottom=NSColor(srgbRed:0.16,green:0.16,blue:0.19,alpha:1)
            shadowed(0.3,20,10){bottom.setFill();body.fill()}
            NSGradient(starting:bottom,ending:top)!.draw(in:body,angle:90)
            // A graphite wheel with the chosen part in orange, and a pale button for the hub.
            let wheel=NSRect(x:209,y:209,width:606,height:606)
            shadowed(0.16,12,6){TwisterArtwork.draw(in:wheel,rest:NSColor(srgbRed:0.51,green:0.51,blue:0.535,alpha:1),selected:NSColor(srgbRed:1.0,green:0.58,blue:0.0,alpha:1),hub:nil)}
            let radius=TwisterArtwork.hubRadius*wheel.width,hub=NSBezierPath(ovalIn:NSRect(x:512-radius,y:512-radius,width:radius*2,height:radius*2))
            let pale=NSColor(srgbRed:0.92,green:0.92,blue:0.94,alpha:1),shade=NSColor(srgbRed:0.74,green:0.74,blue:0.78,alpha:1)
            shadowed(0.2,12,6){shade.setFill();hub.fill()}
            NSGradient(starting:shade,ending:pale)!.draw(in:hub,angle:90)
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
