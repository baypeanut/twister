import AppKit
import SwiftUI

/// Shared by production windows and the native lifecycle regression fixture.
@MainActor enum NativeWindowBehavior {
    static func configure(_ window:NSWindow,autosaveName:String?=nil) {
        window.level = .normal
        window.hidesOnDeactivate=true
        window.collectionBehavior=[.managed,.moveToActiveSpace]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed=false
        window.isMovableByWindowBackground=false
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent=false
        if let autosaveName { window.setFrameAutosaveName(autosaveName) }
    }

    static func present(_ window:NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
    }
}

private struct NativeWindowChromeKey:EnvironmentKey { static let defaultValue=false }
extension EnvironmentValues {
    var nativeWindowChrome:Bool {
        get { self[NativeWindowChromeKey.self] }
        set { self[NativeWindowChromeKey.self]=newValue }
    }
}

/// Workspace dismissal hides the existing view instead of closing it. Selection,
/// Library search, editor drafts and background jobs therefore remain intact.
@MainActor final class WorkspaceDismissalController {
    weak var window:NSWindow?
    private let center:NotificationCenter
    private let workspaceCenter:NotificationCenter
    private var observers:[NSObjectProtocol]=[]
    private var workspaceObservers:[NSObjectProtocol]=[]
    private let dismissTransients:()->Void

    init(center:NotificationCenter = .default,
         workspaceCenter:NotificationCenter? = nil,
         application:NSApplication? = nil,dismissTransients:@escaping()->Void) {
        let workspaceCenter=workspaceCenter ?? NSWorkspace.shared.notificationCenter
        let application=application ?? .shared
        self.center=center;self.workspaceCenter=workspaceCenter;self.dismissTransients=dismissTransients
        for name in [NSApplication.didResignActiveNotification,NSApplication.willHideNotification] {
            observers.append(center.addObserver(forName:name,object:application,queue:.main) { [weak self] _ in
                Task { @MainActor in self?.dismiss() }
            })
        }
        for name in [NSWorkspace.activeSpaceDidChangeNotification,NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(workspaceCenter.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                Task { @MainActor in self?.dismiss() }
            })
        }
    }

    func dismiss() { window?.orderOut(nil);dismissTransients() }

    deinit {
        for observer in observers { center.removeObserver(observer) }
        for observer in workspaceObservers { workspaceCenter.removeObserver(observer) }
    }
}

/// Names a window that has no title bar. A native title bar already does, so nothing is drawn below one.
struct WindowHeader:View {
    let title:String
    @Environment(\.nativeWindowChrome) private var nativeWindowChrome
    var body:some View {
        if !nativeWindowChrome {
            HStack(spacing:8) {
                WindowCloseButton().frame(width:16,height:16)
                ZStack { WindowDragRegion();HStack { LText(title).font(.headline);Spacer() }.allowsHitTesting(false) }
            }.padding(.horizontal,16).frame(height:36)
            Divider()
        }
    }
}
