import AppKit

/// A folded strip: one continuous gesture, with a deliberate cut at its center.
/// The same vector is used in the menu bar, app icon and first-run experience.
enum TwisterArtwork {
    static let gold=NSColor(srgbRed:0.69,green:0.29,blue:0.18,alpha:1)
    static let ink=NSColor.white

    private static func ribbon(_ upper:Bool)->CGPath {
        let p=CGMutablePath()
        if upper {
            p.move(to:CGPoint(x:0.19,y:0.15));p.addLine(to:CGPoint(x:0.83,y:0.15))
            p.addLine(to:CGPoint(x:0.55,y:0.49));p.addLine(to:CGPoint(x:0.31,y:0.49))
            p.addLine(to:CGPoint(x:0.49,y:0.28));p.addLine(to:CGPoint(x:0.19,y:0.28))
        } else {
            p.move(to:CGPoint(x:0.45,y:0.51));p.addLine(to:CGPoint(x:0.69,y:0.51))
            p.addLine(to:CGPoint(x:0.51,y:0.72));p.addLine(to:CGPoint(x:0.81,y:0.72))
            p.addLine(to:CGPoint(x:0.81,y:0.85));p.addLine(to:CGPoint(x:0.17,y:0.85))
        }
        p.closeSubpath();return p
    }
    static func draw(in rect:NSRect,happy:Bool=false,monochrome:Bool=false) {
        guard let c=NSGraphicsContext.current?.cgContext else{return}
        c.saveGState();defer{c.restoreGState()}
        c.translateBy(x:rect.minX,y:rect.maxY);c.scaleBy(x:rect.width,y:-rect.height)
        c.setFillColor((monochrome ? NSColor.black:gold).cgColor)
        c.addPath(ribbon(true));c.fillPath();c.addPath(ribbon(false));c.fillPath()
    }
    static func mark(size:CGFloat,happy:Bool=false)->NSImage {
        NSImage(size:NSSize(width:size,height:size),flipped:false) {rect in draw(in:rect);return true}
    }
    static func menuIcon(updateAvailable:Bool=false)->NSImage {
        let image=NSImage(size:NSSize(width:20,height:20),flipped:false) {rect in
            draw(in:rect.insetBy(dx:0.5,dy:0.5),monochrome:true)
            if updateAvailable {NSColor.black.setFill();NSBezierPath(ovalIn:NSRect(x:16,y:16,width:3,height:3)).fill()}
            return true
        }
        image.isTemplate=true;image.accessibilityDescription=updateAvailable ? "Twister update available":"Twister";return image
    }
}
