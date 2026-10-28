import AppKit
import SwiftUI
import TwisterCore

/// Exercises production window behavior in this process only. No global input,
/// other application, clipboard or user's preferences participate in the fixture.
@MainActor final class WindowLifecycleSmoke:NSObject,NSApplicationDelegate {
    private let output:URL
    private var checks:[String]=[]
    private var windows:[NSWindow]=[]
    init(output:URL) { self.output=output }

    func applicationDidFinishLaunching(_ notification:Notification) {
        Task {
            var failure:String?
            do { try await run() } catch { failure=error.localizedDescription }
            let report:[String:Any]=["passed":failure == nil,"checks":checks,
                "error":failure as Any? ?? NSNull(),
                "scope":"Own-process app/Space/session notifications, native window controls, dismissal, task/draft preservation, minimize/reopen and opt-in monitoring. No external-app click or global-input claim."]
            if FileManager.default.fileExists(atPath:output.appendingPathComponent(".twister-window-lifecycle").path),
               let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {
                try? data.write(to:output.appendingPathComponent("window-lifecycle.json"),options:.atomic)
            }
            for window in windows { window.close() }
            print("WINDOW_LIFECYCLE \(failure == nil ? "PASS":"FAIL") \(checks.count)")
            if let failure { fputs(failure+"\n",stderr) }
            exit(failure == nil ? 0:1)
        }
    }

    private func check(_ condition:Bool,_ message:String)throws {
        guard condition else { throw NSError(domain:"Twister Window QA",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
        checks.append(message)
    }
    private func settle()async { try? await Task.sleep(nanoseconds:120_000_000) }

    private func run()async throws {
        let manager=FileManager.default,marker=output.appendingPathComponent(".twister-window-lifecycle")
        if manager.fileExists(atPath:output.path),!manager.fileExists(atPath:marker.path),
           try !manager.contentsOfDirectory(atPath:output.path).isEmpty {
            throw NSError(domain:"Twister Window QA",code:2,userInfo:[NSLocalizedDescriptionKey:"Choose an empty lifecycle output directory."])
        }
        try manager.createDirectory(at:output,withIntermediateDirectories:true)
        try Data("Twister own-process window lifecycle QA\n".utf8).write(to:marker,options:.atomic)
        let suite="Twister.WindowQA."+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let fixture=try OutputFiles.temporaryDirectory()
        defer { try? manager.removeItem(at:fixture) }
        let source=fixture.appendingPathComponent("Original.txt"),bytes=Data("Unchanged original\n".utf8)
        try bytes.write(to:source)
        let job=JobRecord(title:"Fixture",inputs:[source.path],outputs:[source.path])
        let stored=try JSONEncoder().encode([job]);defaults.set(stored,forKey:"history")
        let state=AppState(defaults:defaults);state.inputs=[source];state.libraryQuery="Draft search"
        state.beginJob("Background operation fixture")
        let token=state.token

        let workspace=NSWindow(contentRect:NSRect(x:80,y:100,width:720,height:600),
            styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        NativeWindowBehavior.configure(workspace);workspace.title="Twister Window Lifecycle QA"
        let content=NSHostingView(rootView:VStack(alignment:.leading,spacing:12) {
            Text("Window lifecycle regression").font(.title2)
            Text("Background work and the selected file survive dismissal.")
            TextField("Draft search",text:Binding(get:{state.libraryQuery},set:{state.libraryQuery=$0}))
        }.padding(24))
        workspace.contentView=content;windows.append(workspace)
        let editor=NSWindow(contentRect:NSRect(x:120,y:140,width:500,height:400),
            styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        NativeWindowBehavior.configure(editor);editor.title="Twister Editor Fixture";windows.append(editor)
        let editorContent=NSHostingView(rootView:HStack {
            WindowCloseButton().frame(width:26,height:26)
            Text("Native editor chrome fixture")
        }.padding().environment(\.nativeWindowChrome,true))
        editor.contentView=editorContent;editorContent.layoutSubtreeIfNeeded()
        func closeButtons(_ view:NSView)->[NSButton] {
            let own=(view as? NSButton).flatMap { $0.accessibilityLabel()=="Close" ? $0:nil }
            return (own.map { [$0] } ?? [])+view.subviews.flatMap(closeButtons)
        }
        let customClose=closeButtons(editorContent)
        try check(customClose.count==1 && customClose[0].isHidden,"Native editor chrome suppresses the duplicate custom close button")
        try check(!(editor is NSPanel),"Editors use a normal document window instead of a persistent panel")
        try check(editor.level == .normal && workspace.level == .normal,"Workspace and editor do not float above other apps")
        try check(editor.hidesOnDeactivate && workspace.hidesOnDeactivate,"Native windows hide when the application becomes inactive")
        try check(!workspace.collectionBehavior.contains(.canJoinAllSpaces) && !editor.collectionBehavior.contains(.fullScreenAuxiliary),"Document windows do not follow every desktop or overlay another app's fullscreen")
        try check([NSWindow.ButtonType.closeButton,.miniaturizeButton,.zoomButton].allSatisfy { editor.standardWindowButton($0) != nil },"Editors provide the native close, minimize and zoom controls")

        let center=NotificationCenter(),spaces=NotificationCenter()
        var dismissals=0,closed=0
        let closeObserver=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:workspace,queue:.main) { _ in closed+=1 }
        defer { NotificationCenter.default.removeObserver(closeObserver) }
        var controller:WorkspaceDismissalController?=WorkspaceDismissalController(center:center,workspaceCenter:spaces,application:NSApp) { dismissals+=1 }
        controller?.window=workspace
        NativeWindowBehavior.present(workspace);await settle()
        try check(workspace.isVisible,"The workspace opens through the production presentation helper")
        center.post(name:NSWindow.didResignKeyNotification,object:workspace);await settle()
        try check(workspace.isVisible && dismissals==0,"An in-app key-window transition does not discard the workspace")
        center.post(name:NSApplication.didResignActiveNotification,object:NSObject());await settle()
        try check(workspace.isVisible && dismissals==0,"Another notification sender cannot dismiss this application")
        center.post(name:NSApplication.didResignActiveNotification,object:NSApp);await settle()
        try check(!workspace.isVisible && dismissals==1,"App deactivation dismisses the workspace and transient overlays")
        try check(closed==0 && workspace.contentView === content,"Dismissal retains the existing view instead of closing it")
        try check(state.inputs==[source] && state.libraryQuery=="Draft search","Selection and the editing draft survive focus loss")
        try check(state.working && state.token === token && !token.isCancelled,"Background work continues with the same uncancelled token")
        try check(defaults.data(forKey:"history")==stored && state.history.count==1,"Dismissal preserves Library storage")
        try check(try Data(contentsOf:source)==bytes,"Dismissal leaves the original file unchanged")
        center.post(name:NSApplication.didResignActiveNotification,object:NSApp);await settle()
        try check(!workspace.isVisible && closed==0,"Repeated deactivation stays safe and does not close the draft")
        NativeWindowBehavior.present(workspace);await settle()
        try check(workspace.isVisible && workspace.contentView === content,"Explicit reopen restores the same workspace view")
        workspace.miniaturize(nil);await settle()
        try check(workspace.isMiniaturized,"The native minimize control works")
        NativeWindowBehavior.present(workspace);await settle()
        try check(!workspace.isMiniaturized && workspace.isVisible,"Opening Twister restores a minimized workspace")
        workspace.makeFirstResponder(nil)
        let escape=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:workspace.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!
        try check(state.handleHomeKey(escape,window:workspace) && !workspace.isVisible,"Escape dismisses the workspace without cancelling its operation")
        try check(state.working && !token.isCancelled,"Escape preserves background work")
        NativeWindowBehavior.present(workspace);await settle()
        spaces.post(name:NSWorkspace.activeSpaceDidChangeNotification,object:nil);await settle()
        try check(!workspace.isVisible,"Changing desktops dismisses the transient workspace")
        NativeWindowBehavior.present(workspace);await settle()
        spaces.post(name:NSWorkspace.sessionDidResignActiveNotification,object:nil);await settle()
        try check(!workspace.isVisible,"Locking the session dismisses the workspace")
        controller=nil
        NativeWindowBehavior.present(workspace);await settle()
        let before=dismissals
        center.post(name:NSApplication.didResignActiveNotification,object:NSApp);await settle()
        try check(workspace.isVisible && dismissals==before,"Releasing the lifecycle controller removes its notification observers")

        defaults.set(true,forKey:"enabled");defaults.set(false,forKey:"windowManagementEnabled")
        let monitor=WindowManagementController(fileWheelIsVisible:{false},preferences:defaults)
        try check(!monitor.isMonitoring,"Window management does not poll before explicit opt-in")
        defaults.set(true,forKey:"windowManagementEnabled");monitor.refreshMonitoring()
        try check(monitor.isMonitoring,"Explicitly enabling window management starts its observer")
        defaults.set(false,forKey:"enabled");monitor.refreshMonitoring()
        try check(!monitor.isMonitoring,"Disabling Twister stops window-management polling immediately")
        monitor.stop();state.finishJob()
        try check(state.history.count==1 && (try Data(contentsOf:source))==bytes,"Completing the fixture preserves Library and source bytes")
    }
}
