import AppKit
import SwiftUI
import Combine

/// The same chrome-free card hosts every local conversion/tool and web job.
@MainActor final class ProgressToastController {
    private(set) var panel:NSPanel?
    private var observation:AnyCancellable?

    func show(state:AppState) {
        guard NSApp.isActive else { dismiss();return }
        guard panel == nil else { return }
        let screen=NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible=screen?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
        let width=min(480,visible.width-32)
        let frame=NSRect(x:visible.midX-width/2,y:visible.minY+28,width:width,height:84)
        let toast=ProgressToastPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        toast.title="Twister — Progress"
        toast.isReleasedWhenClosed=false;toast.isOpaque=false;toast.backgroundColor = .clear
        toast.hasShadow=true;toast.level = .floating;toast.isFloatingPanel=true
        toast.hidesOnDeactivate=true;toast.animationBehavior = .none
        toast.collectionBehavior=[.transient,.ignoresCycle]
        let host=NSHostingView(rootView:JobProgressView(state:state,grouped:false).frame(maxWidth:.infinity,maxHeight:.infinity).background(ToastBackground()).twisterLanguage())
        toast.contentView=host;panel=toast;toast.orderFrontRegardless()
        observation=state.$working.combineLatest(state.$error).receive(on:RunLoop.main).sink { [weak self,weak toast] working,error in
            guard let self,let toast,self.panel === toast else { return }
            if !working && error == nil { self.dismiss();return }
            var resized=toast.frame;resized.size.height=error == nil ? 84:132
            toast.setFrame(resized,display:true)
        }
    }
    func dismiss() {
        observation?.cancel();observation=nil
        let old=panel;panel=nil;old?.orderOut(nil);old?.close()
    }
}

private final class ProgressToastPanel:NSPanel {
    override var canBecomeKey:Bool { false }
    override var canBecomeMain:Bool { false }
}

struct JobProgressBar:View {
    @ObservedObject var state:AppState
    var body:some View {
        if state.progressIsDeterminate {
            ProgressView(value:min(1,max(0,state.progress))).progressViewStyle(.linear)
                .accessibilityLabel("Progress").accessibilityValue("\(Int(state.progress*100)) percent")
        } else {
            // The native indeterminate indicator respects Reduce Motion and never
            // invents a percentage for an opaque PDFKit/Office/archive operation.
            ProgressView().progressViewStyle(.linear)
                .accessibilityLabel("In progress").accessibilityValue(state.progressLabel)
        }
    }
}

/// The material and shape of a system overlay panel, behind a toast.
struct ToastBackground:NSViewRepresentable {
    func makeNSView(context:Context)->NSVisualEffectView {
        let view=NSVisualEffectView();view.material = .hudWindow;view.blendingMode = .behindWindow;view.state = .active
        view.wantsLayer=true;view.layer?.cornerRadius=10;view.layer?.cornerCurve = .continuous;view.layer?.masksToBounds=true;return view
    }
    func updateNSView(_ view:NSVisualEffectView,context:Context) { }
}
