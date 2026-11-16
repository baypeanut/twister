import AppKit

/// The wheel the app is built around: six parts round a hub, the chosen one lifted out.
/// The same vector is used in the menu bar, app icon and first-run experience.
enum TwisterArtwork {
    private static let center=CGPoint(x:0.5,y:0.5),inner:CGFloat=0.2475,outer:CGFloat=0.4455,lift:CGFloat=0.043,edge:CGFloat=0.023
    static let hubRadius:CGFloat=0.1155

    private static func part(_ index:Int)->CGPath {
        let angle=(90-CGFloat(index)*60) * .pi/180,half=25 * CGFloat.pi/180,raised:CGFloat=index==0 ? lift:0
        let narrow=half*(1-(outer-inner)/(outer*6)),p=CGMutablePath()
        p.addArc(center:center,radius:outer+raised,startAngle:angle-half,endAngle:angle+half,clockwise:false)
        p.addArc(center:center,radius:inner+raised,startAngle:angle+narrow,endAngle:angle-narrow,clockwise:true)
        p.closeSubpath();return p
    }
    /// Draws the wheel in `rect`. A colour's alpha applies to its whole shape, so translucent parts stay even.
    static func draw(in rect:NSRect,rest:NSColor = .tertiaryLabelColor,selected:NSColor = .controlAccentColor,hub:NSColor? = .tertiaryLabelColor) {
        guard let c=NSGraphicsContext.current?.cgContext else{return}
        c.saveGState();defer{c.restoreGState()}
        c.translateBy(x:rect.minX,y:rect.minY);c.scaleBy(x:rect.width,y:rect.height)
        func paint(_ color:NSColor,_ path:CGPath,stroke:Bool) {
            let resolved=color.usingColorSpace(.sRGB) ?? color
            c.saveGState();c.setAlpha(resolved.alphaComponent);c.beginTransparencyLayer(auxiliaryInfo:nil)
            let opaque=resolved.withAlphaComponent(1).cgColor;c.setFillColor(opaque);c.addPath(path);c.fillPath()
            if stroke {c.setStrokeColor(opaque);c.setLineWidth(edge);c.setLineJoin(.round);c.addPath(path);c.strokePath()}
            c.endTransparencyLayer();c.restoreGState()
        }
        for index in (0..<6).reversed() {paint(index==0 ? selected:rest,part(index),stroke:true)}
        if let hub {paint(hub,CGPath(ellipseIn:CGRect(x:center.x-hubRadius,y:center.y-hubRadius,width:hubRadius*2,height:hubRadius*2),transform:nil),stroke:false)}
    }
    static func mark(size:CGFloat)->NSImage {
        NSImage(size:NSSize(width:size,height:size),flipped:false) {rect in draw(in:rect);return true}
    }
    static func menuIcon(updateAvailable:Bool=false)->NSImage {
        let image=NSImage(size:NSSize(width:20,height:20),flipped:false) {rect in
            draw(in:rect.insetBy(dx:0.5,dy:0.5),rest:NSColor.black.withAlphaComponent(0.5),selected:.black,hub:NSColor.black.withAlphaComponent(0.5))
            if updateAvailable {NSColor.black.setFill();NSBezierPath(ovalIn:NSRect(x:16,y:16,width:3,height:3)).fill()}
            return true
        }
        image.isTemplate=true;image.accessibilityDescription=updateAvailable ? "Twister update available":"Twister";return image
    }
}
