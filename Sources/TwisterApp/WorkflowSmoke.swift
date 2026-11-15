import AppKit
import SwiftUI
import PDFKit
import TwisterCore
import TwisterUpdates

/// Real application state, exports and editor lifecycles with private files and
/// preferences. No global input, shared pasteboard or user Library is involved.
@MainActor final class WorkflowSmoke:NSObject,NSApplicationDelegate {
    let output:URL
    let hold:Bool
    private var checks:[String]=[]
    private var windows:[NSWindow]=[]
    private var suite:String?
    private var fixture:URL?
    private var retainedState:AppState?
    init(output:URL,hold:Bool=false) {self.output=output;self.hold=hold}
    func applicationDidFinishLaunching(_ notification:Notification) {
        setvbuf(stdout,nil,_IOLBF,0)
        let main=NSMenu(),application=NSMenu(),appItem=NSMenuItem()
        let quit=application.addItem(withTitle:"Quit Workflow QA",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");quit.target=NSApp
        appItem.submenu=application;main.addItem(appItem)
        let edit=NSMenu(title:"Edit"),editItem=NSMenuItem(title:"Edit",action:nil,keyEquivalent:"")
        for (title,key,action) in [("Undo","z","undo:"),("Redo","Z","redo:"),("Cut","x","cut:"),("Copy","c","copy:"),("Paste","v","paste:"),("Select All","a","selectAll:")] {edit.addItem(withTitle:title,action:Selector(action),keyEquivalent:key)}
        editItem.submenu=edit;main.addItem(editItem);NSApp.mainMenu=main
        Task {
            var failure:String?
            do {try await run()} catch {failure=error.localizedDescription}
            let report:[String:Any]=["passed":failure == nil,"checks":checks,"error":failure as Any? ?? NSNull(),"scope":"Generated files through AppState, real image/PDF/audio/video exports, failure/cancel recovery, Library and production SwiftUI editor lifecycle. No global input or third-party service claim."]
            if FileManager.default.fileExists(atPath:output.appendingPathComponent(".twister-workflow-qa").path),let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {try? data.write(to:output.appendingPathComponent("workflow.json"),options:.atomic)}
            print("WORKFLOW \(failure == nil ? "PASS":"FAIL") \(checks.count)")
            if let failure {fputs(failure+"\n",stderr)}
            if !hold || failure != nil {cleanUp();exit(failure == nil ? 0:1)}
        }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {
        if let home=windows.first(where:{$0.title=="Twister Workflow QA"}) {NativeWindowBehavior.present(home)}
        return true
    }
    func applicationWillTerminate(_ notification:Notification) {cleanUp()}
    private func cleanUp() {
        for window in windows {window.close()};windows=[]
        if let suite {UserDefaults.standard.removePersistentDomain(forName:suite);self.suite=nil}
        if let fixture {try? FileManager.default.removeItem(at:fixture);self.fixture=nil}
    }
    private func check(_ value:Bool,_ message:String)throws {
        guard value else {throw UIAuditError("Workflow: "+message)}
        checks.append(message)
    }
    private func wait(_ description:String,seconds:Double=20,until condition:()->Bool)async throws {
        let deadline=Date().addingTimeInterval(seconds)
        while !condition() && Date()<deadline {try await Task.sleep(nanoseconds:30_000_000)}
        guard condition() else {throw UIAuditError("Workflow timeout: "+description)}
    }
    private func finish(_ state:AppState,expectFailure:Bool=false)async throws {
        try await wait("operation finishes") {!state.working}
        try check(expectFailure ? state.error != nil:state.error == nil,expectFailure ? "Failed batch reports an application error":"Completed job has no stale application error")
    }
    private func contents(_ folder:URL)throws->Set<String> {Set(try FileManager.default.contentsOfDirectory(atPath:folder.path))}
    private func verifyJPEGWheel(state: AppState, originals: URL, jpegBytes: Data) async throws {
        let jpeg = originals.appendingPathComponent("First.JPEG")
        let second = originals.appendingPathComponent("Second.jpg")
        try jpegBytes.write(to: jpeg)
        try jpegBytes.write(to: second)

        let board = NSPasteboard.withUniqueName()
        let wheel = WheelController(state: state)
        defer {
            wheel.hide()
            board.releaseGlobally()
        }
        let cases: [(mode: WheelMode, files: [URL], title: String, pages: Int)] = [
            (.tools, [jpeg], "Create PDF", 1),
            (.convert, [jpeg], "PDF", 1),
            (.tools, [jpeg, second], "Create PDF", 2),
        ]
        for test in cases {
            board.clearContents()
            guard board.writeObjects(test.files.map { $0 as NSURL }) else {
                throw UIAuditError("Could not prepare the JPEG file drag")
            }
            let inputs = WebLinkPayload.urls(from: board)
            try check(inputs == test.files, "File drag keeps all JPEG inputs in order")
            wheel.show(inputs: inputs, mode: test.mode, at: NSEvent.mouseLocation)
            guard let view = wheel.wheel,
                  let firstItem = view.accessibilityChildren()?.first as? WheelAccessibilityItem else {
                throw UIAuditError("The JPEG wheel has no selectable items")
            }
            try check(view.items.first?.title == test.title, "JPEG \(test.mode.rawValue) wheel starts with \(test.title)")
            try check(firstItem.accessibilityPerformPress(), "The first JPEG wheel option starts an export")
            try await finish(state)
            guard let result = state.outputs.first, state.outputs.count == 1 else {
                throw UIAuditError("JPEG wheel did not export exactly one PDF")
            }
            let pdf = try PDFEngine.open(result)
            try check(result.pathExtension == "pdf" && pdf.pageCount == test.pages,
                      "JPEG \(test.mode.rawValue) wheel exports a \(test.pages)-page PDF")
        }
        try check(try Data(contentsOf: jpeg) == jpegBytes && Data(contentsOf: second) == jpegBytes,
                  "Wheel exports preserve the original JPEG files")
    }
    private func editor(_ tool:ToolKind,state:AppState,defaults:UserDefaults)async throws {
        let recorder=UIAuditLayout()
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1020,height:780),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        NativeWindowBehavior.configure(window);window.title="Workflow QA · "+tool.title
        let content=NSHostingView(rootView:ToolEditor(state:state,tool:tool).twisterLanguage().defaultAppStorage(defaults).environment(\.nativeWindowChrome,true).uiAuditRoot(recorder))
        window.contentView=content;windows.append(window);NativeWindowBehavior.present(window)
        try await wait(tool.title+" loads") {recorder.status == "ready" || recorder.status.hasPrefix("failed:")}
        try check(recorder.status == "ready",tool.title+" prepares a real generated file")
        window.orderOut(nil);try await Task.sleep(nanoseconds:180_000_000)
        NativeWindowBehavior.present(window);try await Task.sleep(nanoseconds:180_000_000)
        try check(recorder.status == "ready" && window.contentView === content,tool.title+" stays ready after hide and reopen")
        window.miniaturize(nil);try await Task.sleep(nanoseconds:100_000_000)
        NativeWindowBehavior.present(window);try await Task.sleep(nanoseconds:180_000_000)
        try check(recorder.status == "ready" && !window.isMiniaturized,tool.title+" stays usable after minimize and restore")
        window.close();windows.removeAll{$0 === window}
    }
    private func makeWindow<V:View>(title:String,view:V)->NSWindow {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1020,height:780),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        NativeWindowBehavior.configure(window);window.hidesOnDeactivate=false;window.title=title
        window.contentView=NSHostingView(rootView:view.twisterLanguage().environment(\.nativeWindowChrome,true));return window
    }
    private func run()async throws {
        let manager=FileManager.default,marker=output.appendingPathComponent(".twister-workflow-qa")
        if manager.fileExists(atPath:output.path),!manager.fileExists(atPath:marker.path),try !manager.contentsOfDirectory(atPath:output.path).isEmpty {throw UIAuditError("Choose an empty workflow QA directory.")}
        try manager.createDirectory(at:output,withIntermediateDirectories:true);try Data("Twister own-process workflow QA\n".utf8).write(to:marker)
        let suite="Twister.WorkflowQA."+UUID().uuidString;self.suite=suite
        let defaults=UserDefaults(suiteName:suite)!;defaults.set(false,forKey:"reveal")
        let state=AppState(defaults:defaults);retainedState=state
        let fixture=try OutputFiles.temporaryDirectory();self.fixture=fixture
        let originals=fixture.appendingPathComponent("Originals",isDirectory:true),exports=fixture.appendingPathComponent("Exports",isDirectory:true)
        for folder in [originals,exports] {try manager.createDirectory(at:folder,withIntermediateDirectories:true)}
        let context=CGContext(data:nil,width:320,height:180,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red:0.2,green:0.5,blue:0.7,alpha:1));context.fill(CGRect(x:0,y:0,width:320,height:180))
        let cg=context.makeImage()!,image=originals.appendingPathComponent("Türkçe 'quoted' $image.png"),broken=originals.appendingPathComponent("Broken.png")
        try ImageEngine.write(cg,to:image);let originalBytes=try Data(contentsOf:image)
        try Data("This is not a PNG".utf8).write(to:broken)
        try state.outputDestination.choose(exports);state.inputs=[image]
        var options=OperationOptions();options.preserveMetadata=false
        state.execute(.convert("jpg"),options:options);try await finish(state)
        try check(state.outputs.count==1 && state.history.count==1,"An image export reaches output and Library through the application")
        let first=state.outputs[0],firstBytes=try Data(contentsOf:first)
        try check(first.deletingLastPathComponent().resolvingSymlinksInPath().path==exports.resolvingSymlinksInPath().path && (try ImageEngine.load(first)).width==320,"Custom destination receives a decodable full-size image")
        state.execute(.convert("jpg"),options:options);try await finish(state)
        try check(state.outputs[0] != first && (try Data(contentsOf:first))==firstBytes,"Repeating an export preserves the earlier result")
        try check(AppState(defaults:defaults).history.count==2,"Successful exports survive application-state reload")
        let before=try contents(exports),historyCount=state.history.count
        state.inputs=[image,broken];state.execute(.convert("jpg"),options:options);try await finish(state,expectFailure:true)
        try check(state.outputs.isEmpty && state.history.count==historyCount && (try contents(exports))==before,"A corrupt item rolls back the complete batch without adding a success record")
        try originalBytes.write(to:broken)
        state.execute(.convert("jpg"),options:options);try await finish(state)
        try check(state.outputs.count==2 && state.history.count==historyCount+1,"A corrected input can be retried without stale failure state")
        state.inputs=[image];let countBeforeCancel=state.history.count,filesBeforeCancel=try contents(exports)
        state.execute(.convert("jpg"),options:options);state.token.cancel();try await finish(state)
        try check(state.outputs.isEmpty && state.history.count==countBeforeCancel && (try contents(exports))==filesBeforeCancel,"Cancellation leaves no partial export or false Library success")
        state.execute(.convert("png"),options:options);try await finish(state)
        try check(state.outputs.count==1 && state.history.count==countBeforeCancel+1,"The next export succeeds after cancellation")
        let validSelection=state.inputs,missing=JobRecord(title:"Removed",inputs:[],outputs:[fixture.appendingPathComponent("Missing.png").path])
        state.history.insert(missing,at:0);state.selectedHistoryID=missing.id;state.libraryVisible=true
        let keyboardWindow=NSWindow(contentRect:.zero,styleMask:.titled,backing:.buffered,defer:false);keyboardWindow.isReleasedWhenClosed=false
        let enter=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:keyboardWindow.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
        _=state.handleHomeKey(enter,window:keyboardWindow)
        try check(state.inputs==validSelection && state.libraryVisible && state.error != nil,"Return on a missing Library result keeps the current files and displays a recoverable error")
        state.preview(missing);try check(state.inputs==validSelection && state.error != nil,"Previewing a missing Library result preserves selection and reports why")
        let partial=JobRecord(title:"Partial",inputs:[],outputs:[missing.outputs[0],image.path]);state.reuse(partial)
        try check(state.inputs==[image] && !state.libraryVisible && state.error == nil,"Library reuse accepts available files and clears the prior missing-file error")
        var resized=options;resized.width=64;resized.height=36
        state.execute(.tool(.editImage),options:resized);try await finish(state)
        let result=try ImageEngine.load(state.outputs[0]);try check(result.width==64 && result.height==36,"Image editor export applies both requested dimensions")
        let pdfURL=originals.appendingPathComponent("Pages.pdf"),pdf=PDFDocument()
        for _ in 0..<2 {pdf.insert(PDFPage(image:NSImage(cgImage:cg,size:.zero))!,at:pdf.pageCount)}
        guard pdf.write(to:pdfURL) else{throw UIAuditError("PDF fixture could not be created")}
        let pdfBytes=try Data(contentsOf:pdfURL)
        var pdfOptions=options;pdfOptions.pdfPageOrder=[1,0,1];pdfOptions.pdfPageRotations=[0:90,2:180]
        state.inputs=[pdfURL];state.execute(.tool(.organizePDF),options:pdfOptions);try await finish(state)
        let edited=try PDFEngine.open(state.outputs[0]);try check(edited.pageCount==3 && edited.page(at:0)?.rotation==90 && edited.page(at:2)?.rotation==180,"PDF export keeps duplicated pages and their independent rotations")
        try await verifyJPEGWheel(state: state, originals: originals, jpegBytes: firstBytes)
        let audio=originals.appendingPathComponent("Tone.wav"),video=originals.appendingPathComponent("Clip.mp4")
        try await Task.detached {
            let ffmpeg=try Dependencies.executable("ffmpeg")
            try ProcessRunner.run(ffmpeg,["-v","error","-nostdin","-n","-f","lavfi","-i","sine=frequency=660:sample_rate=48000:duration=3","-c:a","pcm_s16le",audio.path])
            try ProcessRunner.run(ffmpeg,["-v","error","-nostdin","-n","-f","lavfi","-i","testsrc2=size=320x180:rate=12:duration=3","-i",audio.path,"-c:v","libx264","-preset","ultrafast","-pix_fmt","yuv420p","-c:a","aac",video.path])
        }.value
        let audioBytes=try Data(contentsOf:audio),videoBytes=try Data(contentsOf:video)
        var trim=options;trim.start=0.5;trim.end=1.5
        for (source,tool) in [(audio,ToolKind.trimAudio),(video,.trimVideo)] {
            state.inputs=[source];state.execute(.tool(tool),options:trim);try await finish(state)
            let info=try MediaEngine.inspect(state.outputs[0]);try check(abs(info.duration-1)<0.2 && info.hasAudio,"\(tool.title) exports the selected one-second interval with audio")
        }
        for tool in [ToolKind.editImage,.annotateImage,.cropImage,.frameImage] {state.inputs=[image];try await editor(tool,state:state,defaults:defaults)}
        state.inputs=[pdfURL];try await editor(.organizePDF,state:state,defaults:defaults)
        state.inputs=[audio];try await editor(.trimAudio,state:state,defaults:defaults)
        state.inputs=[video];try await editor(.trimVideo,state:state,defaults:defaults);try await editor(.splitVideo,state:state,defaults:defaults)
        try check((try Data(contentsOf:image))==originalBytes && (try Data(contentsOf:pdfURL))==pdfBytes && (try Data(contentsOf:audio))==audioBytes && (try Data(contentsOf:video))==videoBytes,"All application workflows preserve original image, PDF, audio and video bytes")
        if hold {
            state.inputs=[image];state.outputs=[];state.error=nil
            let home=makeWindow(title:"Twister Workflow QA",view:HomeView(state:state,updater:AppUpdater()).defaultAppStorage(defaults))
            state.onChooseFiles={let panel=NSOpenPanel();panel.directoryURL=originals;panel.allowsMultipleSelection=true;if panel.runModal() == .OK {state.inputs=panel.urls}}
            state.onShowTool={tool in
                let window=self.makeWindow(title:tool.title,view:ToolEditor(state:state,tool:tool).defaultAppStorage(defaults))
                self.windows.append(window);NativeWindowBehavior.present(window)
            }
            let wheel=WheelController(state:state);state.onOpenWheel={wheel.show(inputs:state.inputs,mode:.tools,at:NSEvent.mouseLocation,keyboard:true)}
            state.onSettings={
                let window=self.makeWindow(title:"Workflow QA Settings",view:SettingsView(updater:AppUpdater()).defaultAppStorage(defaults));self.windows.append(window);NativeWindowBehavior.present(window)
            }
            state.onSuccess={ _ in
                if let data=try? JSONEncoder().encode(state.history) {try? data.write(to:self.output.appendingPathComponent("live-history.json"),options:.atomic)}
            }
            windows.append(home);NativeWindowBehavior.present(home)
        }
    }
}
