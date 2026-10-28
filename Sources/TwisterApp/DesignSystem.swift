import AppKit
import SwiftUI

// One shared visual language, with native light/dark appearance and motion preferences.
enum TwisterPalette {
    static func adaptive(_ light:(Double,Double,Double),_ dark:(Double,Double,Double))->NSColor {
        NSColor(name:nil) { appearance in
            let rgb=appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ? dark:light
            return NSColor(srgbRed:rgb.0,green:rgb.1,blue:rgb.2,alpha:1)
        }
    }
    static let canvas=Color(nsColor:adaptive((0.975,0.970,0.956),(0.105,0.109,0.105)))
    static let surface=Color(nsColor:adaptive((1.0,0.998,0.988),(0.145,0.150,0.144)))
    static let inset=Color(nsColor:adaptive((0.938,0.933,0.917),(0.080,0.085,0.080)))
    static let forest=Color(nsColor:adaptive((0.25,0.29,0.26),(0.81,0.84,0.79)))
    static let sand=Color(nsColor:adaptive((0.945,0.906,0.875),(0.25,0.18,0.15)))
    static let sage=Color(nsColor:adaptive((0.905,0.920,0.893),(0.21,0.25,0.21)))
    static let border=Color.primary.opacity(0.12)
    // Legacy API names keep the editors and wheel using the same Twister accent.
    static let gold=TwisterArtwork.gold
    static let ink=TwisterArtwork.ink
    static let goldInk=Color(nsColor:adaptive((0.58,0.23,0.14),(0.92,0.61,0.46)))
    static let buttonInk=Color.white
    static let goldEnd=Color(nsColor:TwisterArtwork.gold)

}
extension Color { static let twister=Color(nsColor:TwisterPalette.gold) }

enum TwisterMotion {
    static var enabled:Bool { !UserDefaults.standard.bool(forKey:"reduceAnimations") && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}
enum TwisterAppearance {
    @MainActor static func apply(_ choice:String?=nil) {
        let choice=choice ?? UserDefaults.standard.string(forKey:"appAppearance") ?? "system"
        NSApp.appearance=choice=="light" ? NSAppearance(named:.aqua):choice=="dark" ? NSAppearance(named:.darkAqua):nil
    }
}

struct TwisterMotionModifier<Value:Equatable>:ViewModifier {
    let value:Value
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @AppStorage("reduceAnimations") private var reduced=false
    func body(content:Content)->some View { content.animation(systemReduced || reduced ? nil:.spring(response:0.32,dampingFraction:0.88),value:value) }
}
struct TwisterEntrance:ViewModifier {
    var delay=0.0
    @State private var visible=false
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @AppStorage("reduceAnimations") private var reduced=false
    func body(content:Content)->some View {
        content.opacity(visible ? 1:0).offset(y:visible || systemReduced || reduced ? 0:8)
            .onAppear {
                if systemReduced || reduced { visible=true }
                else { withAnimation(.easeOut(duration:0.24).delay(delay)) { visible=true } }
            }
    }
}
extension View {
    func twisterAnimation<V:Equatable>(value:V)->some View { modifier(TwisterMotionModifier(value:value)) }
    func twisterEntrance(delay:Double=0)->some View { modifier(TwisterEntrance(delay:delay)) }
    func twisterCard(radius:CGFloat=10)->some View {
        background(TwisterPalette.surface,in:RoundedRectangle(cornerRadius:min(radius,10),style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:min(radius,10),style:.continuous).strokeBorder(TwisterPalette.border,lineWidth:1))
    }
}

enum TwisterButtonKind { case primary,secondary,quiet }
struct TwisterButtonStyle:ButtonStyle {
    var kind:TwisterButtonKind = .secondary
    var compact=false
    init(_ kind:TwisterButtonKind = .secondary,compact:Bool=false) { self.kind=kind;self.compact=compact }
    func makeBody(configuration:Configuration)->some View { TwisterButtonBody(configuration:configuration,kind:kind,compact:compact) }
}
private struct TwisterButtonBody:View {
    let configuration:ButtonStyleConfiguration
    let kind:TwisterButtonKind
    let compact:Bool
    @State private var hovered=false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @AppStorage("reduceAnimations") private var reduced=false
    private var primary:Bool { kind == .primary }
    var body:some View {
        configuration.label.font(.system(size:compact ? 11:13,weight:.semibold,design:.default))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal:false,vertical:true)
            .frame(minHeight:compact ? 14:18,alignment:.center)
            .padding(.horizontal,compact ? 10:15).padding(.vertical,compact ? 7:11)
            .foregroundStyle(primary ? TwisterPalette.buttonInk:Color.primary)
            .background {
                RoundedRectangle(cornerRadius:compact ? 5:7,style:.continuous)
                    .fill(primary ? AnyShapeStyle(Color.twister):AnyShapeStyle(kind == .quiet ? Color.clear:TwisterPalette.surface))
                    .overlay(RoundedRectangle(cornerRadius:compact ? 5:7,style:.continuous).strokeBorder(primary ? Color.white.opacity(0.12):TwisterPalette.border,lineWidth:kind == .quiet ? 0:1))
            }
            .overlay(RoundedRectangle(cornerRadius:compact ? 5:7).fill(Color.primary.opacity(hovered && !primary ? 0.035:0)))
            .overlay(RoundedRectangle(cornerRadius:compact ? 5:7).strokeBorder(focused ? TwisterPalette.goldInk:Color.clear,lineWidth:2).padding(-3))

            .scaleEffect(systemReduced || reduced ? 1:configuration.isPressed ? 0.985:1)
            .opacity(enabled ? 1:0.4).contentShape(RoundedRectangle(cornerRadius:7))
            .onHover { hovered=$0 }
            .animation(systemReduced || reduced ? nil:.easeOut(duration:0.14),value:configuration.isPressed)
            .animation(systemReduced || reduced ? nil:.easeOut(duration:0.16),value:hovered)
    }
}
struct TwisterGroupBoxStyle:GroupBoxStyle {
    func makeBody(configuration:Configuration)->some View {
        VStack(alignment:.leading,spacing:16) {
            configuration.label.font(.system(size:13,weight:.semibold,design:.default)).foregroundStyle(TwisterPalette.forest)
            configuration.content
        }.padding(20).frame(maxWidth:.infinity,alignment:.leading).twisterCard()
    }
}

struct TwisterMark:View {
    var size:CGFloat=44
    var happy=false
    var body:some View {
        Image(nsImage:TwisterArtwork.mark(size:size*2,happy:happy)).resizable().interpolation(.high).frame(width:size,height:size).accessibilityHidden(true)
    }
}

struct TwisterPill:View {
    let title:String
    var symbol:String?=nil
    var color:Color=TwisterPalette.forest
    var body:some View {
        HStack(spacing:5) { if let symbol { Image(systemName:symbol) };LText(title) }
            .font(.system(size:10,weight:.semibold,design:.default)).foregroundStyle(color == .twister ? TwisterPalette.goldInk:color)
            .padding(.horizontal,7).padding(.vertical,4).background(color.opacity(0.07),in:RoundedRectangle(cornerRadius:4))
    }
}
struct TwisterPageHeading:View {
    let eyebrow:String
    let title:String
    let subtitle:String
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            LText(eyebrow.uppercased()).font(.system(size:10,weight:.bold,design:.default)).tracking(1.4).foregroundStyle(TwisterPalette.goldInk)
            LText(title).font(.system(size:27,weight:.semibold,design:.default)).tracking(-0.7)
            LText(subtitle).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
}
struct TwisterCheck:View {
    @State private var arrived=false
    var body:some View {
        Image(systemName:"checkmark").font(.system(size:14,weight:.bold)).foregroundStyle(TwisterPalette.forest)
            .frame(width:34,height:34).background(TwisterPalette.sage,in:Circle())
            .scaleEffect(arrived ? 1:0.75).opacity(arrived ? 1:0)
            .twisterAnimation(value:arrived).onAppear{arrived=true}.accessibilityHidden(true)
    }
}
