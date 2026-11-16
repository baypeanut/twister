import AppKit
import SwiftUI

// System colours, text styles and control styles carry the look. What stays
// here is the motion preference, the appearance override and one container.
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
    func body(content:Content)->some View { content.animation(systemReduced || reduced ? nil:.default,value:value) }
}
extension View {
    func twisterAnimation<V:Equatable>(value:V)->some View { modifier(TwisterMotionModifier(value:value)) }
    /// The fill and hairline of a bordered list, for rows that are not in a List.
    func twisterGroup()->some View {
        background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:6,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:6,style:.continuous).strokeBorder(Color(nsColor:.separatorColor),lineWidth:1))
    }
}

/// The window behind a sidebar shows through it, as in Finder and Mail.
struct SidebarBackground:NSViewRepresentable {
    func makeNSView(context:Context)->NSVisualEffectView { let view=NSVisualEffectView();view.material = .sidebar;view.blendingMode = .behindWindow;view.state = .followsWindowActiveState;return view }
    func updateNSView(_ view:NSVisualEffectView,context:Context) { }
}

struct TwisterMark:View {
    var size:CGFloat=44
    var body:some View {
        Image(nsImage:TwisterArtwork.mark(size:size*2)).resizable().interpolation(.high).frame(width:size,height:size).accessibilityHidden(true)
    }
}
