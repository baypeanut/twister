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
        observeMinimizing()
    }

    static func present(_ window:NSWindow) {
        observeMinimizing()
        // A window on its way into the Dock is not minimized yet; bring it back once it has arrived.
        if minimizing.contains(ObjectIdentifier(window)) { restoring.insert(ObjectIdentifier(window)) }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
    }

    /// False while a minimize animation, or the restore that follows it, is still in flight.
    static func isSettled(_ window:NSWindow)->Bool {
        !minimizing.contains(ObjectIdentifier(window)) && !restoring.contains(ObjectIdentifier(window))
    }

    private static var minimizing=Set<ObjectIdentifier>(),restoring=Set<ObjectIdentifier>(),observing=false
    private static func observeMinimizing() {
        guard !observing else { return }
        observing=true
        let center=NotificationCenter.default
        center.addObserver(forName:NSWindow.willMiniaturizeNotification,object:nil,queue:.main) { note in
            guard let window=note.object as? NSWindow else { return }
            MainActor.assumeIsolated { _ = minimizing.insert(ObjectIdentifier(window)) }
        }
        center.addObserver(forName:NSWindow.didMiniaturizeNotification,object:nil,queue:.main) { note in
            guard let window=note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                let id=ObjectIdentifier(window)
                minimizing.remove(id)
                guard restoring.remove(id) != nil else { return }
                window.deminiaturize(nil);window.makeKeyAndOrderFront(nil)
            }
        }
        center.addObserver(forName:NSWindow.willCloseNotification,object:nil,queue:.main) { note in
            guard let window=note.object as? NSWindow else { return }
            MainActor.assumeIsolated { minimizing.remove(ObjectIdentifier(window));restoring.remove(ObjectIdentifier(window)) }
        }
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
