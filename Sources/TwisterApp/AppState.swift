import AppKit
import SwiftUI
import TwisterCore

struct JobRecord:Codable,Identifiable {
    var id=UUID()
    var title:String
    var inputs:[String]
    var outputs:[String]
    var date=Date()
}

/// A conversion or tool request with the destination it captured when it was made.
struct QueuedJob:Identifiable {
    let id=UUID()
    let operation:TwisterCore.Operation
    /// As requested, before the destination is resolved, so a retry resolves it again.
    let options:OperationOptions
    let inputs:[URL]
    let destination:OutputDestinationSnapshot
    /// A preset that saves beside the originals whatever the app's own folder is.
    var besideOriginals=false
    var tool:ToolKind? { if case .tool(let tool)=operation { return tool };return nil }
    /// Sorted keys: two equal option sets must encode to the same bytes.
    private static func canonical(_ options:OperationOptions)->Data? { let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys;return try? encoder.encode(options) }
    func repeats(_ other:QueuedJob)->Bool {
        operation.title==other.operation.title && inputs==other.inputs && Self.canonical(options)==Self.canonical(other.options)
    }
}

/// Per-file status of a conversion, kept after it ends so failures can be read and retried.
struct JobBatch:Identifiable {
    var id:UUID { job.id }
    let job:QueuedJob
    var items:[BatchItem]
    var finished=false
    var report:BatchReport { BatchReport(items:items) }
}

@MainActor final class AppState:NSObject,ObservableObject {
    @Published var inputs:[URL]=[] {
        didSet { if oldValue != inputs && !working { outputs=[];error=nil;batch=nil } }
    }
    /// Requests made while another task runs. They start in order as each task ends.
    @Published private(set) var queue:[QueuedJob]=[]
    /// The running conversion, or the last one that ended.
    @Published var batch:JobBatch?
    /// Earlier conversions with failed files that a queued task has since replaced.
    @Published private(set) var unresolved:[JobBatch]=[]
    private var running:QueuedJob?
    @Published var working=false
    @Published var progress=0.0
    @Published var progressIsDeterminate=false
    private var acceptsProgress=false
    @Published var progressLabel=""
    @Published var error:String?
    @Published var outputs:[URL]=[]
    @Published var activeTool:ToolKind?
    @Published var activeInputs:[URL]=[]
    @Published var history:[JobRecord]=[]
    @Published var libraryVisible=false
    @Published var libraryQuery=""
    @Published var selectedHistoryID:UUID?
    @Published var libraryFocusRequest=0
    let filePreview=FilePreview()
    var filteredHistory:[JobRecord] {history.filter{libraryQuery.isEmpty || AppLocalization.matches(([$0.title,AppLocalization.text($0.title,language:historyDefaults.string(forKey:"appLanguage") ?? "en")]+$0.outputs.map{URL(fileURLWithPath:$0).lastPathComponent}).joined(separator:" "),query:libraryQuery,language:historyDefaults.string(forKey:"appLanguage") ?? "en")}}
    func availableFiles(_ job:JobRecord)->[URL] {job.outputs.map{URL(fileURLWithPath:$0)}.filter{FileManager.default.fileExists(atPath:$0.path)}}
    func preview(_ job:JobRecord) {
        let files=availableFiles(job)
        guard !files.isEmpty else {error="These files have moved or been removed. Choose another result.";return}
        filePreview.show(files)
    }
    func reuse(_ job:JobRecord) {
        guard !working else{return}
        let files=availableFiles(job)
        guard !files.isEmpty else {error="These files have moved or been removed. Choose another result.";return}
        inputs=files;error=nil;libraryVisible=false;selectedHistoryID=job.id
    }
    func navigateLibrary(_ direction:Int) {let rows=filteredHistory;guard !rows.isEmpty else{return};let old=rows.firstIndex{$0.id==selectedHistoryID};selectedHistoryID=rows[min(rows.count-1,max(0,(old ?? (direction>0 ? -1:1))+direction))].id}
    func pasteContent(_ pasteboard:NSPasteboard = .general) {
        do {let result=try ClipboardImport.read(pasteboard)
            if let link=result.link {onWebDownload?(link,.video);return}
            inputs=result.urls;outputs=[];error=nil;libraryVisible=false
            history.insert(JobRecord(title:result.label,inputs:[],outputs:result.urls.map(\.path)),at:0);history=Array(history.prefix(50))
            if let data=try? JSONEncoder().encode(history) {historyDefaults.set(data,forKey:"history")}
        }catch{self.error=error.localizedDescription}
    }
    var token=CancellationToken()
    var onOpenWheel:(()->Void)?
    var onChooseFiles:(()->Void)?
    var onSettings:(()->Void)?
    var onPresetSettings:(()->Void)?
    var onWebDownload:((URL?,WebDownloadMode)->Void)?
    var onWebDrop:(([URL])->Void)?
    @Published var webShortcutAvailable=false
    var onShowTool:((ToolKind)->Void)?
    var onEPUBOptions:(()->Void)?
    var onJobStarted:(()->Void)?
    var onSuccess:((SuccessNotice)->Void)?
    /// A conversion ended with at least one file done or failed: its title and result.
    var onJobFinished:((String,BatchReport)->Void)?
    var toolWindows:[NSWindow]=[]
    var floatShelves:[FloatShelfController]=[]
    private var windowObservers:[ObjectIdentifier:NSObjectProtocol]=[:]
    private var sharingService:NSSharingService?

    private let historyDefaults:UserDefaults
    let outputDestination:OutputDestinationPreferences
    let presets:PresetCenter
    /// Private preferences are a QA run; it keeps its presets in memory unless it names a file.
    init(defaults:UserDefaults = .standard,presets:PresetStore?=nil) {
        historyDefaults=defaults;outputDestination=OutputDestinationPreferences(defaults:defaults)
        self.presets=PresetCenter(store:presets ?? (defaults === UserDefaults.standard ? .standard:nil));super.init()
        if let data=historyDefaults.data(forKey:"history"),let items=try? JSONDecoder().decode([JobRecord].self,from:data) { history=items }
    }
    func retainToolWindow(_ window:NSWindow) {
        toolWindows.append(window);let id=ObjectIdentifier(window)
        windowObservers[id]=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:window,queue:.main) { [weak self] _ in Task { @MainActor in guard let self else { return };self.toolWindows.removeAll{ObjectIdentifier($0)==id};if let token=self.windowObservers.removeValue(forKey:id) { NotificationCenter.default.removeObserver(token) } } }
    }
    func select(_ operation:TwisterCore.Operation,options:TwisterCore.OperationOptions? = nil,immediate:Bool=false) {
        var settings=options ?? OperationOptions()
        if options == nil,case .convert(let format)=operation { settings=FormatPreferences.shared.options(for:format) }
        if case .convert("epub")=operation,inputs.allSatisfy({FileCategory.detect($0) == .pdf}),!immediate { onEPUBOptions?();return }
        if case .tool(.removeMetadata)=operation,inputs.count>1 { execute(operation,options:settings);return }
        if case .tool(let kind)=operation,!immediate,!([.muteVideo,.extractArchive,.createPDF,.splitPDF].contains(kind)) {
            onShowTool?(kind);return
        }
        execute(operation,options:settings)
    }
    /// Queues a preset for the files, with its own options and destination.
    func run(_ preset:Preset,inputs:[URL]?=nil) {
        let selected=inputs ?? self.inputs
        guard preset.applies(to:selected) else { error="This preset does not fit the selected files.";return }
        do { execute(preset.operation,options:try preset.request(for:selected).options,inputs:selected,besideOriginals:preset.destination == .besideOriginals) }
        catch { self.error=error.localizedDescription }
    }
    func execute(_ operation:TwisterCore.Operation,options:TwisterCore.OperationOptions = .init(),inputs:[URL]?=nil,besideOriginals:Bool=false) {
        let selected=inputs ?? self.inputs
        let destination:OutputDestinationSnapshot
        do { destination=besideOriginals ? .besideOriginals:try outputDestination.snapshot(explicitDirectory:options.outputDirectory) }
        catch {
            if !working {
                activeInputs=selected
                if case .tool(let tool)=operation { activeTool=tool } else { activeTool=nil }
                outputs=[]
            }
            self.error=error.localizedDescription;return
        }
        let job=QueuedJob(operation:operation,options:options,inputs:selected,destination:destination,besideOriginals:besideOriginals)
        guard working else { start(job);return }
        // A second click on the same request must not export everything twice.
        if running?.repeats(job) != true,!queue.contains(where:{$0.repeats(job)}) { queue.append(job) }
    }
    /// True while this exact tool request is running or waiting.
    func hasJob(_ tool:ToolKind,inputs:[URL])->Bool {
        ([running].compactMap{$0}+queue).contains { $0.tool==tool && $0.inputs==inputs }
    }
    func clearQueue() { queue=[] }
    func dismiss(_ ended:JobBatch) {
        unresolved.removeAll{$0.id==ended.id}
        if batch?.id==ended.id,!working { batch=nil }
    }
    /// Runs the same operation again for the files that failed, and only those.
    func retryFailed(_ ended:JobBatch) {
        let failed=ended.report.failedInputs
        guard ended.finished,!failed.isEmpty else { return }
        dismiss(ended)
        execute(ended.job.operation,options:ended.job.options,inputs:failed,besideOriginals:ended.job.besideOriginals)
    }
    private func start(_ job:QueuedJob,queued:Bool=false) {
        let operation=job.operation,selected=job.inputs,destination=job.destination
        // Starting a task by hand replaces the last result; a queued start must not hide its failures.
        if queued,let ended=batch,ended.finished,ended.report.failed>0 { unresolved=Array(([ended]+unresolved).prefix(5)) }
        beginJob(operation.title)
        let cancel=token
        running=job;activeInputs=selected;activeTool=job.tool
        var options=job.options;options.outputDirectory=destination.directory;options.revealInFinder=historyDefaults.bool(forKey:"reveal")
        let request=ConversionRequest(inputs:selected,operation:operation,options:options)
        batch=JobBatch(job:job,items:ConversionEngine.units(for:request).map{BatchItem(inputs:$0)})
        Task { [self] in
            // A deferred update may restart the app as soon as working becomes false.
            // Keep the job active until its outputs and recent history are committed.
            defer { finishJob() }
            do {
                let report=try await Task.detached(priority:.userInitiated) {
                    try destination.withAccess {
                        try withGrantedFolderAccess(request.inputs + [request.options.outputDirectory].compactMap{$0}) {
                            try ConversionEngine.runBatch(request,token:cancel,progress:{ [weak self] value,label in
                                Task { @MainActor in self?.receiveProgress(value,label:label,token:cancel) }
                            },itemChanged:{ [weak self] index,status in
                                Task { @MainActor in self?.receiveItem(index,status:status,token:cancel) }
                            })
                        }
                    }
                }.value
                stopProgressUpdates();batch?.items=report.items;batch?.finished=true
                let result=report.outputs
                outputs=result;progress=1
                if report.failed>0,result.isEmpty { error=report.items.count==1 ? report.items[0].failure:report.summary }
                guard !result.isEmpty else { if report.failed>0 { onJobFinished?(operation.title,report) };return }
                let record=JobRecord(title:operation.title,inputs:report.items.filter{!$0.outputs.isEmpty}.flatMap(\.inputs).map(\.path),outputs:result.map(\.path))
                history.insert(record,at:0);history=Array(history.prefix(50))
                if let data=try? JSONEncoder().encode(history) { historyDefaults.set(data,forKey:"history") }
                onSuccess?(report.succeeded==report.items.count ? .filesReady(result):SuccessNotice(title:report.summary,detail:result[0].lastPathComponent,files:result))
                onJobFinished?(operation.title,report)
                if options.revealInFinder && NSApp.isActive { NSWorkspace.shared.activateFileViewerSelecting(result) }
            } catch {
                stopProgressUpdates()
                guard !cancel.isCancelled else { batch=nil;return }
                let reason=error.localizedDescription
                self.error=reason;batch?.finished=true
                for index in batch?.items.indices ?? 0..<0 { batch?.items[index].status = .failed(reason) }
            }
        }
    }
    func beginJob(_ label:String) {
        token=CancellationToken();acceptsProgress=true
        error=nil;outputs=[];progress=0;progressIsDeterminate=false;progressLabel=label
        activeTool=nil;activeInputs=[];batch=nil;working=true
        onJobStarted?()
    }
    func receiveItem(_ index:Int,status:BatchItem.Status,token:CancellationToken) {
        guard working,acceptsProgress,self.token === token,batch?.items.indices.contains(index) == true else { return }
        batch?.items[index].status=status
    }
    func receiveProgress(_ value:Double,label:String,token:CancellationToken) {
        guard working,acceptsProgress,self.token === token,!token.isCancelled else { return }
        progressIsDeterminate=value.isFinite && value>=0
        if progressIsDeterminate { progress=min(0.99,max(0,value)) }
        progressLabel=label
    }
    func stopProgressUpdates() { acceptsProgress=false }
    func finishJob() {
        stopProgressUpdates();running=nil
        // The next request starts without an idle moment in which the app could restart.
        if queue.isEmpty { working=false } else { start(queue.removeFirst(),queued:true) }
    }

    func perform(_ action:FileAction,urls:[URL]?=nil) {
        guard !working else { return }
        let urls=urls ?? inputs
        guard !urls.isEmpty else { return }
        switch action {
        case .copyPath:
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(urls.map(\.path).joined(separator:"\n"),forType:.string) { reportSuccess(.action("File paths copied.",files:urls)) }
            else { error="Could not copy the selected file paths." }
        case .copy:
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.writeObjects(urls as [NSURL]) { reportSuccess(.action("Files copied.",files:urls)) }
            else { error="Could not copy the selected files." }
        case .airDrop:
            if let service=NSSharingService(named:.sendViaAirDrop),service.canPerform(withItems:urls) { sharingService=service;service.delegate=self;service.perform(withItems:urls) }
            else { error="AirDrop is unavailable on this Mac." }
        case .move:
            let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.canCreateDirectories=true;panel.prompt="Move Here"
            NSApp.activate(ignoringOtherApps:true)
            if panel.runModal() == .OK,let directory=panel.url {
                moveFiles(urls,to:directory)
            }
        case .terminal:
            let directory=((try? urls[0].resourceValues(forKeys:[.isDirectoryKey]).isDirectory) ?? false) ? urls[0] : urls[0].deletingLastPathComponent()
            // Terminal's Services integration opens the chosen folder without shell interpolation.
            let preferred=UserDefaults.standard.string(forKey:"terminalApp") ?? "Terminal"
            let app=preferred=="iTerm2" ? NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.googlecode.iterm2"):URL(fileURLWithPath:"/System/Applications/Utilities/Terminal.app")
            if let app {
                NSWorkspace.shared.open([directory],withApplicationAt:app,configuration:NSWorkspace.OpenConfiguration()) { [weak self] _,error in
                    Task { @MainActor in
                        if let error { self?.error=error.localizedDescription }
                        else { self?.reportSuccess(.action("Opened in \(preferred).",files:[directory])) }
                    }
                }
            }
            else { error="\(preferred) is not installed." }
        case .float:
            if UserDefaults.standard.string(forKey:"floatWheelBehavior")=="addToExisting",let existing=floatShelves.reversed().first(where:{$0.window?.isVisible == true}) {
                existing.append(urls);existing.showWindow(nil);reportSuccess(.action("Added to Float.",files:urls));return
            }
            let shelf=FloatShelfController(urls:urls)
            shelf.onClose={ [weak self,weak shelf] in guard let shelf else { return };self?.floatShelves.removeAll{$0 === shelf} }
            floatShelves.append(shelf);shelf.showWindow(nil);reportSuccess(.action("Added to Float.",files:urls))
        }
    }
    private func moveFiles(_ urls:[URL],to directory:URL) {
        let previousOutputs=outputs
        beginJob("Moving files…")
        let cancel=token
        Task {
            defer { finishJob() }
            let result=await Task.detached(priority:.userInitiated) {
                withGrantedFolderAccess(urls+[directory]) { FileMoveBatch.run(urls,to:directory,token:cancel) }
            }.value
            func remap(_ url:URL)->URL {
                let source=url.standardizedFileURL
                if let target=result.moved[source] { return target }
                for (old,new) in result.moved where source.path.hasPrefix(old.path+"/") {
                    return new.appendingPathComponent(String(source.path.dropFirst(old.path.count+1)))
                }
                return url
            }
            inputs=inputs.map(remap);outputs=previousOutputs.map(remap);activeInputs=activeInputs.map(remap)
            for index in history.indices {
                history[index].inputs=history[index].inputs.map { remap(URL(fileURLWithPath:$0)).path }
                history[index].outputs=history[index].outputs.map { remap(URL(fileURLWithPath:$0)).path }
            }
            if let data=try? JSONEncoder().encode(history) { historyDefaults.set(data,forKey:"history") }
            if let failure=result.failure {
                error=result.moved.isEmpty ? failure:"\(result.moved.count) files moved before the operation stopped. \(failure)"
            } else { reportSuccess(.action("Files moved.",files:urls.map(remap))) }
        }
    }
    func reportSuccess(_ notice:SuccessNotice) { error=nil;onSuccess?(notice) }
    func recordWebDownload(_ files:[URL],site:String) {
        history.insert(JobRecord(title:"Download · \(site)",inputs:files.map(\.path),outputs:files.map(\.path)),at:0)
        history=Array(history.prefix(50))
        if let data=try? JSONEncoder().encode(history) { historyDefaults.set(data,forKey:"history") }
        reportSuccess(.filesReady(files))
    }
}

func withGrantedFolderAccess<T>(_ urls:[URL],_ action:() throws -> T) rethrows -> T {
    let paths=Set(urls.map { $0.standardizedFileURL.path })
    let folders=FolderAccessPreferences.grants().compactMap(FolderAccessPreferences.resolved).filter { url in
        let parent=url.standardizedFileURL.path
        return paths.contains { $0==parent || $0.hasPrefix(parent=="/" ? "/":parent+"/") }
    }
    var seen=Set<URL>()
    let active=(folders+urls).filter { seen.insert($0.standardizedFileURL).inserted && $0.startAccessingSecurityScopedResource() }
    defer { for url in active.reversed() { url.stopAccessingSecurityScopedResource() } }
    return try action()
}

extension AppState:NSSharingServiceDelegate {
    nonisolated func sharingService(_ sharingService:NSSharingService,didShareItems items:[Any]) {
        let files=items.compactMap{$0 as? URL}
        Task { @MainActor [weak self] in self?.sharingService=nil;self?.reportSuccess(.action("Shared with AirDrop.",files:files)) }
    }
    nonisolated func sharingService(_ sharingService:NSSharingService,didFailToShareItems items:[Any],error:Error) {
        let description=(error as NSError).code == NSUserCancelledError ? nil:error.localizedDescription
        Task { @MainActor [weak self] in self?.error=description;self?.sharingService=nil }
    }
}

enum FileAction:String,CaseIterable {
    case airDrop,float,copy,move,copyPath,terminal
    var title:String { switch self { case .airDrop:return "AirDrop";case .float:return "Float";case .copy:return "Copy";case .move:return "Move";case .copyPath:return "Copy Path";case .terminal:return "Terminal" } }
    var symbol:String { switch self { case .airDrop:return "dot.radiowaves.left.and.right";case .float:return "rectangle.on.rectangle";case .copy:return "doc.on.doc";case .move:return "folder";case .copyPath:return "link";case .terminal:return "terminal" } }
}
