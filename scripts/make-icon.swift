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
        let mark=bitmap(256,256){rect in TwisterArtwork.draw(in:rect)}
        for name in ["TwisterMark.png","TwisterMarkHappy.png"] {
            try mark.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name))
        }
        let icon=bitmap(1024,1024) {_ in
            let background=NSBezierPath(roundedRect:NSRect(x:55,y:55,width:914,height:914),xRadius:202,yRadius:202)
            NSColor(srgbRed:0.96,green:0.94,blue:0.90,alpha:1).setFill();background.fill()
            TwisterArtwork.draw(in:NSRect(x:210,y:160,width:604,height:704))
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
