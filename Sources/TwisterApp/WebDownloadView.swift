import AppKit
import Combine
import SwiftUI
import TwisterCore

enum AppFeatures {
    /// False only in a copy built with `TWISTER_WEB_DOWNLOADS=0`; such a copy has no downloader interface.
    static let webDownloads=WebDownloadGate.buildIncludesDownloader(Bundle.main.infoDictionary)
    static var webDownloadAvailability:WebDownloadAvailability {
        WebDownloadGate.availability(included:webDownloads,preference:WebDownloadGate.preference(in:.standard),status:ExternalToolSetup.status)
    }
}

@MainActor final class WebDownloadModel:ObservableObject {
    @Published var linkText=""
    @Published var info:WebMediaInfo?
    @Published var mode:WebDownloadMode = .video
    @Published var maximumHeight=0
    @Published var inspecting=false
    @Published var downloading=false
    @Published var error:String?
    @Published var completed:[URL]=[]
    @Published var selectedPhotos=Set<Int>()
    @Published var shortcutAvailable=false
    @Published var destination:URL
    @Published private(set) var availability=AppFeatures.webDownloadAvailability
    let state:AppState
    var onUseFiles:(()->Void)?
    var onInstallTools:(([ToolGroup])->Void)?
    private var observers=Set<AnyCancellable>()
    private var inspection:Task<Void,Never>?
    private var inspectionToken=CancellationToken()
    private var revision=UUID()
    private var pendingMode:WebDownloadMode?
    init(state:AppState) {
        self.state=state
        destination=UserDefaults.standard.string(forKey:"webDownloadDestination").map{URL(fileURLWithPath:$0,isDirectory:true)} ?? FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask)[0]
        for name in [Notification.Name.toolSetupChanged,NSApplication.didBecomeActiveNotification,UserDefaults.didChangeNotification] {
            NotificationCenter.default.publisher(for:name).receive(on:RunLoop.main).sink { [weak self] _ in self?.refreshAvailability() }.store(in:&observers)
        }
    }
    /// A link pasted before the tools are present is kept and checked once they are.
    func refreshAvailability() {
        let current=AppFeatures.webDownloadAvailability
        guard current != availability else { return }
        availability=current
        if current == .ready,!linkText.isEmpty,info == nil,!inspecting,!downloading { inspect() }
    }
    func resolveAvailability() {
        switch availability {
        case .off:UserDefaults.standard.set(true,forKey:WebDownloadGate.preferenceKey);refreshAvailability()
        case .needsTools(let groups):onInstallTools?(groups)
        case .excluded,.ready:break
        }
    }
    func open(_ url:URL?,mode:WebDownloadMode) {
        guard !downloading else { return }
        refreshAvailability()
        pendingMode=mode
        guard availability == .ready else { if let url { linkText=url.absoluteString };return }
        if let url { linkText=url.absoluteString;inspect() }
    }
    func editedLink() {
        guard !downloading else { return }
        inspection?.cancel();inspectionToken.cancel();revision=UUID();inspecting=false;info=nil;error=nil;completed=[]
    }
    func pasteLink() {
        guard !downloading else { return }
        guard let url=WebLinkPayload.clipboardLink() else { error="Copy a video share link or an image address first.";return }
        linkText=url.absoluteString;inspect()
    }
    func inspect() {
        guard !downloading else { return }
        inspection?.cancel();inspectionToken.cancel();inspectionToken=CancellationToken();revision=UUID()
        let current=revision,token=inspectionToken
        info=nil;completed=[];error=nil;inspecting=false
        let url:URL
        do { url=try WebDownloadEngine.link(linkText,allowLocalNetwork:WebDownloadGate.allowsLocalNetwork(in:.standard)) } catch { self.error=error.localizedDescription;return }
        inspecting=true
        inspection=Task { [weak self] in
            do {
                let found=try await WebDownloadEngine.inspect(url,token:token,allowLocalNetwork:WebDownloadGate.allowsLocalNetwork(in:.standard))
                guard let self,self.revision==current,!Task.isCancelled else { return }
                self.info=found;self.maximumHeight=0;self.selectedPhotos=Set(found.photos.map(\.id))
                if found.kind == .image { self.linkText=found.url.absoluteString }
                self.mode=found.modes.contains(self.pendingMode ?? .video) ? (self.pendingMode ?? .video):(found.modes.first ?? .original)
                self.pendingMode=nil;self.inspecting=false
            } catch {
                guard let self,self.revision==current,!token.isCancelled,!Task.isCancelled else { return }
                self.error=error.localizedDescription;self.inspecting=false
            }
        }
    }
    func cancelInspection() { inspection?.cancel();inspectionToken.cancel();revision=UUID();inspecting=false }
    func configurationChanged() { guard !downloading else { return };completed=[];error=nil }
    func selectPhotos(_ ids:Set<Int>) { guard !downloading else { return };selectedPhotos=ids;configurationChanged() }
    func chooseDestination() {
        guard !downloading else { return }
        let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.canCreateDirectories=true;panel.directoryURL=destination;panel.prompt="Save Downloads Here"
        if panel.runModal() == .OK,let url=panel.url { do { try FolderAccessPreferences.add([url]);configurationChanged();destination=url;UserDefaults.standard.set(url.path,forKey:"webDownloadDestination") } catch { self.error=error.localizedDescription } }
    }
    func download() {
        guard let info,!downloading,!state.working else { return }
        let mode=mode,maximum=maximumHeight>0 ? maximumHeight:nil,folder=destination
        let selection=info.photos.isEmpty ? nil:selectedPhotos
        downloading=true;error=nil;completed=[]
        state.beginJob("Starting download…")
        let token=state.token
        Task { [state] in
            defer { downloading=false;state.finishJob() }
            do {
                let files=try await WebDownloadEngine.download(info,mode:mode,maximumHeight:maximum,destination:folder,selectedPhotos:selection,token:token,allowLocalNetwork:WebDownloadGate.allowsLocalNetwork(in:.standard)) { [weak state] fraction,label in
                    Task { @MainActor in state?.receiveProgress(fraction,label:label,token:token) }
                }
                state.stopProgressUpdates();state.outputs=files;state.inputs=files;state.progress=1;completed=files
                state.recordWebDownload(files,site:info.url.host ?? "Web")
            } catch {
                state.stopProgressUpdates();self.error=token.isCancelled ? "Download cancelled. No partial files were kept.":error.localizedDescription
                if !token.isCancelled { state.error=error.localizedDescription }
            }
        }
    }
}

struct WebDownloadView:View {
    @ObservedObject var model:WebDownloadModel
    @ObservedObject var state:AppState
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            WindowHeader(title:"Download from the Web")
            if model.availability == .ready {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    HStack(spacing:8) {
                        TextField("Paste a video share link or image address",text:Binding(get:{model.linkText},set:{ if model.linkText != $0 { model.linkText=$0;model.editedLink() } })).textFieldStyle(.roundedBorder).onSubmit { if model.info != nil { model.download() } else { model.inspect() } }.disabled(model.downloading).accessibilityLabel("Media link")
                        Button("Paste") { model.pasteLink() }.disabled(model.downloading)
                    }
                    if model.inspecting {
                        HStack { ProgressView().controlSize(.small);Text("Finding the media…").font(.callout);Spacer();Button("Cancel") { model.cancelInspection() } }
                    }
                    if let info=model.info {
                        HStack(spacing:12) {
                            Image(systemName:info.kind == .image ? "photo":info.kind == .audio ? "waveform":"play.rectangle").font(.title).foregroundStyle(.secondary).frame(width:32).accessibilityHidden(true)
                            VStack(alignment:.leading,spacing:2) {
                                Text(info.title).font(.headline).lineLimit(3).textSelection(.enabled)
                                Text(details(info)).font(.subheadline).foregroundStyle(.secondary)
                            };Spacer(minLength:0)
                        }.padding(12).twisterGroup()
                        if !info.photos.isEmpty {
                            VStack(alignment:.leading,spacing:10) {
                                HStack {
                                    Text("Select photos").font(.headline);Spacer()
                                    Button("Select All") { model.selectPhotos(Set(info.photos.map(\.id))) }.controlSize(.small)
                                    Button("Deselect All") { model.selectPhotos([]) }.controlSize(.small)
                                }
                                if info.skippedVideoCount>0 { Text("\(info.skippedVideoCount) video items are not included. Only photos will be saved.").font(.subheadline).foregroundStyle(.secondary) }
                                Text("Saved in post order in a new Instagram folder.").font(.subheadline).foregroundStyle(.secondary)
                                ForEach(info.photos) { photo in
                                    Toggle(isOn:Binding(get:{model.selectedPhotos.contains(photo.id)},set:{ selected in
                                        var ids=model.selectedPhotos;if selected { ids.insert(photo.id) } else { ids.remove(photo.id) };model.selectPhotos(ids)
                                    })) {
                                        HStack(spacing:12) {
                                            AsyncImage(url:photo.url) { image in image.resizable().scaledToFit() } placeholder:{Image(systemName:"photo").foregroundStyle(.secondary)}
                                                .frame(width:64,height:48).background(.quaternary,in:RoundedRectangle(cornerRadius:4))
                                            VStack(alignment:.leading,spacing:4) {
                                                Text("Photo \(photo.id)")
                                                if let width=photo.width,let height=photo.height { Text("\(width) × \(height)").font(.subheadline).foregroundStyle(.secondary) }
                                            };Spacer()
                                        }
                                    }.toggleStyle(.checkbox)
                                }
                            }.padding(12).twisterGroup().disabled(model.downloading)
                        }
                        if info.modes.count>1 {
                            Picker("Save as",selection:$model.mode) { ForEach(info.modes,id:\.self) { LText($0.title).tag($0) } }.pickerStyle(.segmented).disabled(model.downloading)
                        }
                        if model.mode == .video,(info.heights.max() ?? 0)>720 {
                            Picker("Video quality",selection:$model.maximumHeight) {
                                Text("Best available").tag(0)
                                if (info.heights.max() ?? 0)>1080 { Text("Up to 1080p").tag(1080) }
                                if (info.heights.max() ?? 0)>720 { Text("Up to 720p").tag(720) }
                            }.disabled(model.downloading)
                        }
                    }
                    LabeledContent {
                        HStack(spacing:8) {
                            Text((model.destination.path as NSString).abbreviatingWithTildeInPath).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                            Button("Change…") { model.chooseDestination() }.disabled(model.downloading)
                        }
                    } label:{ Text("Save to") }
                    if model.downloading {
                        VStack(alignment:.leading,spacing:6) { HStack { LText(state.progressLabel);Spacer();if state.progressIsDeterminate { Text("\(Int(state.progress*100))%").monospacedDigit() } }.font(.subheadline).foregroundStyle(.secondary);JobProgressBar(state:state) }
                    }
                    if !model.completed.isEmpty { Label { Text("Ready on your Mac") } icon:{ Image(systemName:"checkmark.circle.fill").foregroundStyle(.green) };Text(model.completed.map(\.lastPathComponent).joined(separator:"\n")).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
                    if let error=model.error { Label { LText(error) } icon:{ Image(systemName:"exclamationmark.triangle.fill").symbolRenderingMode(.multicolor) }.fixedSize(horizontal:false,vertical:true) }
                    if state.working,!model.downloading { Text("Another task is running. Your link is ready when it finishes.").font(.subheadline).foregroundStyle(.secondary) }
                    VStack(alignment:.leading,spacing:4) {
                        LText(model.shortcutAvailable ? "Copy a link → ⌃⇧D, or drag it with ⌘.":"Copy a link, then choose Download Link from the Twister menu.")
                        Text("Instagram photo posts open a photo selection. For videos, use the share link; for other photos, drag the image or use Copy Image Address. Public media only; login-required and protected items may be unavailable.").fixedSize(horizontal:false,vertical:true)
                    }.font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }
            Divider()
            HStack {
                if model.downloading { Button("Cancel Download") { state.token.cancel() } }
                else if !model.completed.isEmpty { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(model.completed) } }
                Spacer()
                if !model.completed.isEmpty { Button("Use in Twister") { model.onUseFiles?() }.keyboardShortcut(.defaultAction) }
                else if let info=model.info { Button { model.download() } label:{ LText(!info.photos.isEmpty ? (model.selectedPhotos.count==1 ? "Download 1 Photo":"Download \(model.selectedPhotos.count) Photos"):model.mode == .audioMP3 ? "Download MP3":info.kind == .image ? "Download Image":"Download") }.keyboardShortcut(.defaultAction).disabled(model.downloading || state.working || (!info.photos.isEmpty && model.selectedPhotos.isEmpty)) }
                else { Button("Check Link") { model.inspect() }.keyboardShortcut(.defaultAction).disabled(model.linkText.isEmpty || model.inspecting) }
            }.padding(.horizontal,20).padding(.vertical,12)
            } else { unavailable }
        }.onChange(of:model.mode) { _ in model.configurationChanged() }.onChange(of:model.maximumHeight) { _ in model.configurationChanged() }.frame(minWidth:620,minHeight:520).background(Color(nsColor:.windowBackgroundColor))
    }
    /// Shown in place of the link form until the user has opted in and the tools are present.
    private var unavailable:some View {
        let off=model.availability == .off
        return VStack(alignment:.leading,spacing:10) {
            Text(LocalizedStringKey(off ? "Web downloads are turned off":"Web downloads need their own tools")).font(.headline)
            LText(off ? "Turn them on here or in Settings → General → Optional extras.":"Downloading from a link uses extra tools that media conversion does not need. Twister downloads them once from pinned, checksum-verified sources, and you can remove them again in tool setup. Converting and editing files works without them.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if !model.linkText.isEmpty { Text("Your link is kept and checked as soon as web downloads are ready.").font(.subheadline).foregroundStyle(.secondary) }
            Button { model.resolveAvailability() } label:{ LText(off ? "Turn On Web Downloads":"Install Web Download Tools…") }
                .keyboardShortcut(.defaultAction).accessibilityIdentifier("WebDownloadSetup")
            Spacer(minLength:0)
        }.padding(20).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
    }
    func details(_ info:WebMediaInfo)->String {
        var details=[info.site,info.kind.rawValue.capitalized]
        if !info.photos.isEmpty { details.append("\(info.photos.count) \(info.photos.count==1 ? "photo":"photos")") }
        if let width=info.imageWidth,let height=info.imageHeight { details.append("\(width) × \(height)") }
        if let duration=info.duration { details.append("\(Int(duration)/60):\(String(format:"%02d",Int(duration)%60))") }
        if let height=info.heights.max() { details.append("\(height)p") }
        if let bytes=info.byteCount { details.append(ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file)) }
        return details.joined(separator:" · ")
    }
}
