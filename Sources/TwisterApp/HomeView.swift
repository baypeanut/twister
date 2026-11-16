import AppKit
import SwiftUI
import TwisterCore
import UniformTypeIdentifiers
import TwisterUpdates

struct HomeView:View {
    @ObservedObject var state:AppState
    @ObservedObject var updater:AppUpdater
    @ObservedObject private var presets:PresetCenter
    init(state:AppState,updater:AppUpdater) { self.state=state;self.updater=updater;presets=state.presets }
    @AppStorage("convertKey") private var convertKey="shift"
    @AppStorage("toolsKey") private var toolsKey="command"
    @AppStorage("actionsKey") private var actionsKey="control"
    @FocusState private var librarySearchFocused:Bool
    @State private var targeted=false
    @State private var historySearch=""
    @State private var allHistory=false
    @State private var toolsReady=ExternalToolSetup.status.ready
    private var formats:[String] { FeatureCatalog.formats(for:state.inputs) }
    private var tools:[ToolKind] { FeatureCatalog.tools(for:state.inputs) }
    private var recent:[JobRecord] {
        let filtered=state.history.filter { historySearch.isEmpty || AppLocalization.matches(([$0.title,AppLocalization.text($0.title,language:L10n.language)]+$0.outputs.map{URL(fileURLWithPath:$0).lastPathComponent}).joined(separator:" "),query:historySearch,language:L10n.language) }
        return Array(filtered.prefix(allHistory || !historySearch.isEmpty ? 50:3))
    }
    var body:some View {
        HStack(spacing:0) {
            navigation
            Divider()
            Group {
                if state.libraryVisible { libraryPage }
                else { workspace }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(nsColor:.windowBackgroundColor))
        }.frame(minWidth:700,minHeight:580)
            .twisterAnimation(value:state.inputs.isEmpty).twisterAnimation(value:state.working)
            .twisterAnimation(value:updater.availableVersion)
            .onChange(of:state.libraryFocusRequest) { _ in librarySearchFocused=true }
            .onReceive(NotificationCenter.default.publisher(for:.toolSetupChanged)) { _ in toolsReady=ExternalToolSetup.status.ready }
            .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in toolsReady=ExternalToolSetup.status.ready;presets.reload() }
    }
    private var navigation:some View {
        VStack(alignment:.leading,spacing:1) {
            navigationItem("Workspace",symbol:"tray.full",selected:!state.libraryVisible) { state.libraryVisible=false }
            navigationItem("Library",symbol:"clock",selected:state.libraryVisible) { state.libraryVisible=true }
            Spacer(minLength:16)
            if AppFeatures.webDownloads { navigationItem("Download Link…",symbol:"arrow.down.circle",selected:false) { state.onWebDownload?(WebLinkPayload.clipboardLink(),.video) } }
            if Bundle.main.object(forInfoDictionaryKey:"TwisterExternalTools") as? Bool == true {
                navigationItem(toolsReady ? "Manage Tools…":"Finish Setup…",symbol:"shippingbox",selected:false) { NotificationCenter.default.post(name:.showToolSetup,object:nil) }
            }
            navigationItem("Settings…",symbol:"gearshape",selected:false) { state.onSettings?() }
        }.padding(.horizontal,10).padding(.vertical,10).frame(width:176).frame(maxHeight:.infinity).background(SidebarBackground())
    }
    private func navigationItem(_ title:String,symbol:String,selected:Bool,action:@escaping()->Void)->some View {
        Button(action:action) {
            HStack(spacing:6) {
                Image(systemName:symbol).foregroundStyle(Color.accentColor).frame(width:20)
                LText(title).lineLimit(1)
                Spacer(minLength:0)
            }.font(.body).padding(.horizontal,6).frame(height:28).contentShape(Rectangle())
                .background(selected ? Color(nsColor:.unemphasizedSelectedContentBackgroundColor):Color.clear,in:RoundedRectangle(cornerRadius:5,style:.continuous))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected:[])
    }
    private var workspace:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                if let version=updater.availableVersion { UpdateBanner(updater:updater,version:version) }
                if updater.repository != nil,let updateError=updater.lastError {
                    Label(updateError,systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                }
                dropZone
                if !state.inputs.isEmpty { selectionActions }
                if state.working || state.error != nil || !state.outputs.isEmpty { JobProgressView(state:state) }
                if JobQueueView.hasContent(state) { JobQueueView(state:state) }
                if !state.history.isEmpty { historySection }
                Text("Files are processed on this Mac.").font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }
    }
    private var libraryPage:some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    TextField("Search Library",text:$state.libraryQuery).textFieldStyle(.roundedBorder).focused($librarySearchFocused)
                    if let error=state.error {HStack{Label(error,systemImage:"exclamationmark.triangle").font(.callout).foregroundStyle(.secondary);Spacer();Button("Dismiss"){state.error=nil}.controlSize(.small)}}
                    if state.filteredHistory.isEmpty {LText(state.history.isEmpty ? "Your processed files will appear here.":"No matches. Try a file name or tool.").foregroundStyle(.secondary).padding(.vertical,12)}
                    else {
                        VStack(spacing:0) {
                            ForEach(Array(state.filteredHistory.enumerated()),id:\.element.id) {index,job in
                                if index>0 { Divider().padding(.leading,54) }
                                RecentFileRow(job:job,canReuse:!state.working,onPreview:{state.preview(job)},onReuse:{_ in state.reuse(job)})
                                    .background(state.selectedHistoryID==job.id ? Color(nsColor:.unemphasizedSelectedContentBackgroundColor):Color.clear)
                                    .contentShape(Rectangle()).onTapGesture {state.selectedHistoryID=job.id;librarySearchFocused=false}.id(job.id)
                            }
                        }.clipShape(RoundedRectangle(cornerRadius:6,style:.continuous)).twisterGroup()
                    }
                    Text("↑/↓ choose · Space preview · Return use in Twister").font(.footnote).foregroundStyle(.secondary)
                }.padding(20)
            }.onChange(of:state.selectedHistoryID) { id in if let id {scroll.scrollTo(id)} }
        }
    }
    private var dropZone:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.center,spacing:12) {
                Group {
                    if !targeted,state.inputs.count==1 { AsyncFileArtwork(url:state.inputs[0]) }
                    else { Image(systemName:state.inputs.isEmpty || targeted ? "arrow.down.doc":"doc.on.doc").font(.system(size:24,weight:.light)).foregroundStyle(targeted ? AnyShapeStyle(Color.accentColor):AnyShapeStyle(.secondary)) }
                }.frame(width:32,height:32).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:2) {
                    Group { if targeted { LText("Release to add files") } else if state.inputs.isEmpty { LText("Drop files here") } else if state.inputs.count==1 { Text(state.inputs[0].lastPathComponent) } else { LText("\(state.inputs.count) files selected") } }
                        .font(.headline).lineLimit(2).textSelection(.enabled)
                    Group { if state.inputs.isEmpty { LText("Images, documents, audio, and video.") } else if state.inputs.count==1 { Text(selectionDescription) } else { LText(selectionDescription) } }
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            HStack(spacing:8) {
                chooseFilesButton
                Button("Paste") {state.pasteContent()}.help("⌘V · Paste files, text, an image or link")
                Spacer(minLength:0)
                if !state.inputs.isEmpty { Button("Clear") { state.inputs=[] } }
            }
            if state.inputs.count>1 {
                VStack(alignment:.leading,spacing:4) {
                    ForEach(Array(state.inputs.prefix(3)),id:\.self) { url in
                        HStack(spacing:6) {
                            AsyncFileArtwork(url:url).frame(width:16,height:16)
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength:0)
                            Button { state.inputs.removeAll{$0==url} } label:{Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary)}
                                .buttonStyle(.plain).help("Remove \(url.lastPathComponent) from selection").accessibilityLabel("Remove \(url.lastPathComponent)")
                        }
                    }
                    if state.inputs.count>3 { Text("+\(state.inputs.count-3)").foregroundStyle(.secondary) }
                }.font(.subheadline)
            }
            Divider()
            HStack(spacing:12) {
                shortcut(convertKey,"Convert");shortcut(toolsKey,"Tools");shortcut(actionsKey,"Actions")
                Spacer(minLength:0)
                Button { state.onOpenWheel?() } label:{ Image(systemName:"circle.hexagongrid") }
                    .buttonStyle(.borderless).help("Open wheel").accessibilityLabel("Open wheel").disabled(state.inputs.isEmpty)
            }
        }.padding(16).background(targeted ? Color.accentColor.opacity(0.08):Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:6,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:6,style:.continuous).strokeBorder(targeted ? Color.accentColor:Color(nsColor:.separatorColor),lineWidth:targeted ? 2:1))
            .onDrop(of:WebLinkPayload.providerTypes,isTargeted:$targeted,perform:receiveDrop)
    }
    @ViewBuilder private var chooseFilesButton:some View {
        // The one thing to do in an empty workspace is the prominent button.
        if state.inputs.isEmpty { Button { state.onChooseFiles?() } label:{ LText("Choose Files…") }.buttonStyle(.borderedProminent).help("⌘O") }
        else { Button { state.onChooseFiles?() } label:{ LText("Change Files…") }.help("⌘O") }
    }
    private var selectionDescription:String {
        if state.inputs.count==1 { return state.inputs[0].deletingLastPathComponent().abbreviatingWithTildeInPath }
        return "Choose an output format or a tool below."
    }
    private func shortcut(_ key:String,_ title:String)->some View {
        HStack(spacing:4) { Text(ModifierChord.legacy(key)?.symbols ?? key);LText(title) }
            .font(.footnote).foregroundStyle(.secondary)
    }
    private func formatName(_ format:String)->String { format=="gz" ? "GZIP":format.uppercased() }
    private var selectionActions:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:8) {
                Menu { ForEach(formats,id:\.self) { format in Button(formatName(format)) { state.select(.convert(format)) } } } label:{ LText("Convert") }
                    .disabled(formats.isEmpty).help(L10n.text(formats.isEmpty ? "No output formats":"\(formats.count) formats"))
                Menu { ForEach(tools,id:\.self) { tool in Button { state.select(.tool(tool)) } label:{ LText(tool.title) } } } label:{ LText("Tools") }
                    .disabled(tools.isEmpty).help(L10n.text(tools.isEmpty ? "No tools for this selection":"Edit, compress, and more"))
                Menu { ForEach(FileAction.allCases,id:\.self) { action in Button { state.perform(action) } label:{ LText(action.title) } } } label:{ LText("Actions") }
                    .disabled(state.working)
                Spacer(minLength:0)
            }.fixedSize(horizontal:false,vertical:true)
            if !formats.isEmpty {
                HStack(spacing:6) {
                    LText("Convert to").font(.subheadline).foregroundStyle(.secondary)
                    ForEach(Array(formats.prefix(4)),id:\.self) { format in
                        Button(formatName(format)) { state.select(.convert(format)) }.controlSize(.small)
                    }
                    Spacer()
                }
            }
            OutputDestinationControl(state:state)
            if !presets.library.applicable(to:state.inputs).isEmpty || presets.issue != nil {
                HStack(spacing:8) {
                    LText("Presets").font(.headline)
                    Spacer()
                    Button { state.onPresetSettings?() } label:{ LText("Manage Presets…") }.buttonStyle(.link)
                }.padding(.top,4)
                PresetListView(state:state)
            }
        }
    }
    private var historySection:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                LText("Recent Files").font(.headline)
                Spacer()
                TextField("Search",text:$historySearch).textFieldStyle(.roundedBorder).frame(width:180).accessibilityLabel(L10n.text("Find a recent file"))
            }
            VStack(spacing:0) {
                if recent.isEmpty { Text("No matches. Try a file name or tool.").foregroundStyle(.secondary).padding(16).frame(maxWidth:.infinity) }
                ForEach(Array(recent.enumerated()),id:\.element.id) { index,job in
                    if index>0 { Divider().padding(.leading,54) }
                    RecentFileRow(job:job,canReuse:!state.working,onPreview:{state.preview(job)},onReuse:{ _ in state.reuse(job) })
                }
            }.twisterGroup()
            if state.history.count>3 && historySearch.isEmpty {
                Button { allHistory.toggle() } label:{ LText(allHistory ? "Show Less":"Show All") }.buttonStyle(.link)
            }
        }.padding(.top,4)
    }
    private func receiveDrop(_ providers:[NSItemProvider])->Bool {
        WebLinkPayload.urls(from:providers) { urls in
            if urls.first?.isFileURL == false { state.onWebDrop?(urls) }
            else if !urls.isEmpty { state.inputs=urls }
        }
        return !providers.isEmpty
    }
}

private struct RecentFileRow:View {
    let job:JobRecord
    let canReuse:Bool
    let onPreview:()->Void
    let onReuse:([URL])->Void
    @Environment(\.locale) private var locale
    private var urls:[URL] { job.outputs.map{URL(fileURLWithPath:$0)} }
    private var available:[URL] { urls.filter{FileManager.default.fileExists(atPath:$0.path)} }
    var body:some View {
        HStack(spacing:10) {
            if let first=urls.first { AsyncFileArtwork(url:first).frame(width:32,height:32) }
            VStack(alignment:.leading,spacing:2) {
                Text(urls.first?.lastPathComponent ?? job.title).lineLimit(1).truncationMode(.middle)
                HStack(spacing:3) { if available.isEmpty { Text("Moved or removed") } else { LText(job.title);Text("· "+job.date.formatted(.relative(presentation:.named).locale(locale))) } }.font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength:8)
            if urls.count>1 { Text("\(urls.count) files").font(.subheadline).foregroundStyle(.secondary) }
            Group {
                Button(action:onPreview) {Image(systemName:"eye")}.disabled(available.isEmpty).help("Preview").accessibilityLabel("Preview \(urls.first?.lastPathComponent ?? "result")")
                Button { onReuse(available) } label:{Image(systemName:"tray.and.arrow.down")}
                    .disabled(available.isEmpty || !canReuse)
                    .help(canReuse ? "Use these files again":"Available after the current task finishes")
                    .accessibilityLabel("Use \(urls.first?.lastPathComponent ?? "result") again")
                Button { NSWorkspace.shared.activateFileViewerSelecting(available) } label:{Image(systemName:"magnifyingglass")}
                    .disabled(available.isEmpty).help("Show in Finder").accessibilityLabel("Show \(urls.first?.lastPathComponent ?? "result") in Finder")
            }.buttonStyle(.borderless)
        }.padding(.horizontal,12).padding(.vertical,6)
    }
}
private extension URL { var abbreviatingWithTildeInPath:String { (path as NSString).abbreviatingWithTildeInPath } }

struct JobProgressView:View {
    @ObservedObject var state:AppState
    /// The toasts draw their own panel behind the rows.
    var grouped=true
    var body:some View {
        VStack(spacing:8) {
            if state.working {
                VStack(alignment:.leading,spacing:8) {
                    HStack(spacing:10) {
                        VStack(alignment:.leading,spacing:2) { Text("Processing files…").font(.headline);LText(state.progressLabel).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer()
                        if state.progressIsDeterminate { Text("\(Int(state.progress*100))%").font(.subheadline).monospacedDigit().foregroundStyle(.secondary) }
                        Button("Cancel") { state.token.cancel() }
                    }
                    JobProgressBar(state:state)
                }.padding(12).modifier(JobProgressGroup(grouped:grouped)).transition(.opacity)
            }
            if let error=state.error {
                HStack(alignment:.top,spacing:10) {
                    Image(systemName:"exclamationmark.triangle.fill").symbolRenderingMode(.multicolor).font(.title3)
                    VStack(alignment:.leading,spacing:2) { Text("Could not complete this task").font(.headline);LText(error).font(.subheadline).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled) }
                    Spacer();Button { state.error=nil } label:{Image(systemName:"xmark")}.buttonStyle(.borderless).accessibilityLabel("Dismiss error")
                }.padding(12).modifier(JobProgressGroup(grouped:grouped)).transition(.opacity)
            }
        }.twisterAnimation(value:state.working).twisterAnimation(value:state.outputs.count).twisterAnimation(value:state.error != nil)
    }
}
private struct JobProgressGroup:ViewModifier {
    let grouped:Bool
    @ViewBuilder func body(content:Content)->some View { if grouped { content.twisterGroup() } else { content } }
}
