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
            VStack(spacing:0) {
                HStack(spacing:8) {
                    LText(state.libraryVisible ? "Library":"Workspace").font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                    Spacer()
                    if Bundle.main.object(forInfoDictionaryKey:"TwisterExternalTools") as? Bool == true {
                        Button { NotificationCenter.default.post(name:.showToolSetup,object:nil) } label:{ LText(toolsReady ? "Tools ready":"Finish setup") }
                            .buttonStyle(TwisterButtonStyle(.quiet,compact:true))
                    }
                }.padding(.horizontal,26).frame(height:48)
                Divider()
                if state.libraryVisible { libraryPage }
                else { workspace }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(minWidth:700,minHeight:580).background(TwisterPalette.canvas).tint(.twister)
            .twisterAnimation(value:state.inputs.isEmpty).twisterAnimation(value:state.working)
            .twisterAnimation(value:updater.availableVersion)
            .onChange(of:state.libraryFocusRequest) { _ in librarySearchFocused=true }
            .onReceive(NotificationCenter.default.publisher(for:.toolSetupChanged)) { _ in toolsReady=ExternalToolSetup.status.ready }
            .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in toolsReady=ExternalToolSetup.status.ready;presets.reload() }
    }
    private var navigation:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:8) {
                TwisterMark(size:27)
                Text("twister").font(.system(size:19,weight:.semibold)).tracking(-0.8)
            }.padding(.top,27).padding(.bottom,36)
            Text("FILES").font(.system(size:9,weight:.semibold)).tracking(1.5).foregroundStyle(.secondary).padding(.horizontal,10).padding(.bottom,9)
            navigationItem("Workspace",symbol:"square.stack.3d.up",selected:!state.libraryVisible) { state.libraryVisible=false }
            navigationItem("Library",symbol:"clock",selected:state.libraryVisible) { state.libraryVisible=true }
            Divider().padding(.vertical,20)
            Text("TOOLS").font(.system(size:9,weight:.semibold)).tracking(1.5).foregroundStyle(.secondary).padding(.horizontal,10).padding(.bottom,9)
            if AppFeatures.webDownloads { navigationItem("Download a link",symbol:"arrow.down.to.line",selected:false) { state.onWebDownload?(WebLinkPayload.clipboardLink(),.video) } }
            navigationItem("Settings",symbol:"slider.horizontal.3",selected:false) { state.onSettings?() }
            Spacer(minLength:24)
            VStack(alignment:.leading,spacing:7) {
                HStack(spacing:5) { Circle().fill(TwisterPalette.forest).frame(width:5,height:5);Text("On your Mac").font(.system(size:10,weight:.medium)) }
                Text("Local by design").font(.system(size:10)).foregroundStyle(.secondary)
            }.padding(.horizontal,10).padding(.bottom,24)
        }.padding(.horizontal,12).frame(width:154).frame(maxHeight:.infinity).background(TwisterPalette.inset.opacity(0.65))
    }
    private func navigationItem(_ title:String,symbol:String,selected:Bool,action:@escaping()->Void)->some View {
        Button(action:action) {
            HStack(spacing:9) {
                Image(systemName:symbol).font(.system(size:12,weight:.medium)).frame(width:16)
                LText(title).font(.system(size:11,weight:selected ? .semibold:.regular)).lineLimit(2).fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:0)
            }.foregroundStyle(selected ? Color.primary:Color.secondary).padding(.horizontal,10).padding(.vertical,11)
                .background(selected ? TwisterPalette.surface:Color.clear,in:RoundedRectangle(cornerRadius:6))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected:[])
    }
    private var workspace:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:23) {
                if let version=updater.availableVersion { UpdateBanner(updater:updater,version:version) }
                if updater.repository != nil,let updateError=updater.lastError {
                    Label(updateError,systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment:.leading,spacing:9) {
                    Text("A little order.").font(.system(size:31,weight:.semibold,design:.serif)).tracking(-0.8)
                    Text("Convert, edit, and organize your files.").font(.system(size:12)).foregroundStyle(.secondary)
                }.padding(.top,6)
                dropZone
                if state.inputs.isEmpty { formatGuide }
                else { selectionActions }
                if state.working || state.error != nil || !state.outputs.isEmpty { JobProgressView(state:state) }
                if JobQueueView.hasContent(state) { JobQueueView(state:state) }
                if !state.history.isEmpty { historySection }
                Divider()
                HStack(spacing:5) {
                    Image(systemName:"lock").font(.system(size:9))
                    Text("Files are processed on this Mac.").font(.system(size:10))
                    Spacer(minLength:0)
                    Text("⌘O").font(.system(size:10,design:.monospaced))
                }.foregroundStyle(.secondary)
            }.padding(26)
        }
    }
    private var formatGuide:some View {
        VStack(alignment:.leading,spacing:13) {
            Text("ONE PLACE FOR THE EVERYDAY").font(.system(size:9,weight:.semibold)).tracking(1.2).foregroundStyle(.secondary)
            HStack(alignment:.top,spacing:0) {
                formatColumn("Images",symbol:"photo",detail:"Resize, crop, convert")
                Spacer(minLength:8)
                formatColumn("Documents",symbol:"doc.text",detail:"Merge, split, export")
                Spacer(minLength:8)
                formatColumn("Media",symbol:"waveform",detail:"Trim, compress, edit")
            }
        }.padding(.vertical,3)
    }
    private func formatColumn(_ title:String,symbol:String,detail:String)->some View {
        VStack(alignment:.leading,spacing:7) {
            Image(systemName:symbol).font(.system(size:16,weight:.regular)).foregroundStyle(TwisterPalette.forest).frame(height:20)
            LText(title).font(.system(size:11,weight:.semibold))
            LText(detail).font(.system(size:9)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var libraryPage:some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text("Library").font(.system(size:29,weight:.semibold,design:.serif)).tracking(-0.6)
                    Text("Your recent files, ready to use again.").font(.callout).foregroundStyle(.secondary)
                    TextField("Find a file or tool · ⌘F",text:$state.libraryQuery).textFieldStyle(.roundedBorder).focused($librarySearchFocused)
                    if let error=state.error {HStack{Label(error,systemImage:"exclamationmark.circle").font(.caption).foregroundStyle(.orange);Spacer();Button("Dismiss"){state.error=nil}.buttonStyle(TwisterButtonStyle(.quiet,compact:true))}}
                    if state.filteredHistory.isEmpty {LText(state.history.isEmpty ? "Your processed files will appear here.":"No matches. Try a file name or tool.").foregroundStyle(.secondary).padding(20)}
                    ForEach(state.filteredHistory) {job in
                        RecentFileRow(job:job,canReuse:!state.working,onPreview:{state.preview(job)},onReuse:{_ in state.reuse(job)})
                            .background(TwisterPalette.surface).overlay(RoundedRectangle(cornerRadius:5).strokeBorder(state.selectedHistoryID==job.id ? Color.twister:Color.clear,lineWidth:1.5))
                            .contentShape(Rectangle()).onTapGesture {state.selectedHistoryID=job.id;librarySearchFocused=false}.id(job.id)
                    }
                    Text("↑/↓ choose · Space preview · Return use in Twister").font(.caption).foregroundStyle(.secondary)
                }.padding(26)
            }.onChange(of:state.selectedHistoryID) { id in if let id {scroll.scrollTo(id)} }
        }
    }
    private var dropZone:some View {
        VStack(alignment:.leading,spacing:18) {
            HStack(alignment:.top,spacing:14) {
                Image(systemName:state.inputs.isEmpty ? "arrow.down.doc":"doc.on.doc")
                    .font(.system(size:25,weight:.ultraLight)).foregroundStyle(targeted ? Color.twister:TwisterPalette.forest)
                    .frame(width:44,height:48).background(TwisterPalette.inset,in:RoundedRectangle(cornerRadius:5))
                VStack(alignment:.leading,spacing:7) {
                    Group { if targeted { LText("Release to add files") } else if state.inputs.isEmpty { LText("Drop your files here") } else if state.inputs.count==1 { Text(state.inputs[0].lastPathComponent) } else { LText("\(state.inputs.count) files selected") } }
                        .font(.system(size:17,weight:.medium)).tracking(-0.3).lineLimit(2).textSelection(.enabled)
                    Group { if state.inputs.isEmpty { LText("Images, documents, audio, and video.") } else if state.inputs.count==1 { Text(selectionDescription) } else { LText(selectionDescription) } }
                        .font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            HStack(spacing:8) {
                Button { state.onChooseFiles?() } label:{LText(state.inputs.isEmpty ? "Choose files":"Change files")}
                    .buttonStyle(TwisterButtonStyle(.primary))
                Button("Paste") {state.pasteContent()}.buttonStyle(TwisterButtonStyle(.secondary)).help("⌘V · Paste files, text, an image or link")
                Spacer(minLength:0)
                if !state.inputs.isEmpty {
                    Button("Clear") { state.inputs=[] }.buttonStyle(TwisterButtonStyle(.quiet,compact:true))
                }
            }
            if !state.inputs.isEmpty {
                VStack(alignment:.leading,spacing:5) {
                    ForEach(Array(state.inputs.prefix(3)),id:\.self) { url in
                        HStack(spacing:7) {
                            AsyncFileArtwork(url:url).frame(width:14,height:14)
                            Text(url.lastPathComponent).font(.system(size:10)).lineLimit(1)
                            Spacer(minLength:0)
                            Button { state.inputs.removeAll{$0==url} } label:{Image(systemName:"xmark").font(.system(size:8))}
                                .buttonStyle(.plain).help("Remove \(url.lastPathComponent) from selection").accessibilityLabel("Remove \(url.lastPathComponent)")
                        }
                    }
                    if state.inputs.count>3 { Text("+\(state.inputs.count-3)").font(.caption).foregroundStyle(.secondary) }
                }
            }
            Divider()
            HStack(spacing:12) {
                shortcut(convertKey,"Convert");shortcut(toolsKey,"Tools");shortcut(actionsKey,"Actions")
                Spacer(minLength:0)
                Button { state.onOpenWheel?() } label:{ Image(systemName:"circle.hexagongrid").font(.system(size:13)) }
                    .buttonStyle(.plain).help("Open wheel").accessibilityLabel("Open wheel").disabled(state.inputs.isEmpty)
            }
        }.padding(20).background(targeted ? TwisterPalette.sand.opacity(0.35):TwisterPalette.surface,in:RoundedRectangle(cornerRadius:9))
            .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(targeted ? Color.twister:TwisterPalette.border,style:StrokeStyle(lineWidth:targeted ? 1.5:1,dash:targeted ? [5,4]:[])))
            .twisterAnimation(value:targeted)
            .onDrop(of:WebLinkPayload.providerTypes,isTargeted:$targeted,perform:receiveDrop)
    }
    private var selectionDescription:String {
        if state.inputs.count==1 { return state.inputs[0].deletingLastPathComponent().abbreviatingWithTildeInPath }
        return "Choose an output format or a tool below."
    }
    private func shortcut(_ key:String,_ title:String)->some View {
        HStack(spacing:5) { Text(ModifierChord.legacy(key)?.symbols ?? key).font(.system(size:12,weight:.semibold));LText(title).font(.system(size:10,weight:.medium)) }
            .foregroundStyle(.secondary)
    }
    private var selectionActions:some View {
        VStack(alignment:.leading,spacing:12) {
            OutputDestinationControl(state:state)
            HStack(spacing:12) {
                Button { HomeActionMenu.show(formats.map{format in (format=="gz" ? "GZIP":format.uppercased(),{state.select(.convert(format))})}) } label:{HomeActionTile(title:"Convert",subtitle:formats.isEmpty ? "No output formats":"\(formats.count) formats",symbol:"arrow.triangle.2.circlepath",color:.twister)}
                    .buttonStyle(.plain).disabled(formats.isEmpty)
                Button { HomeActionMenu.show(tools.map{tool in (tool.title,{state.select(.tool(tool))})}) } label:{HomeActionTile(title:"Tools",subtitle:tools.isEmpty ? "No tools for this selection":"Edit, compress, and more",symbol:"slider.horizontal.3",color:TwisterPalette.forest)}
                    .buttonStyle(.plain).disabled(tools.isEmpty)
                Button { HomeActionMenu.show(FileAction.allCases.map{action in (action.title,{state.perform(action)})}) } label:{HomeActionTile(title:"Move & share",subtitle:"File actions",symbol:"paperplane",color:Color(red:0.34,green:0.47,blue:0.67))}
                    .buttonStyle(.plain).disabled(state.working)
            }
            if !formats.isEmpty {
                HStack(spacing:7) {
                    Text("QUICK PICKS").font(.system(size:9,weight:.bold,design:.default)).tracking(0.8).foregroundStyle(.secondary)
                    ForEach(Array(formats.prefix(4)),id:\.self) { format in
                        Button { state.select(.convert(format)) } label:{HStack(spacing:5) { Text(format=="gz" ? "GZIP":format.uppercased());Image(systemName:"arrow.up.right").font(.system(size:8,weight:.bold)) }}
                            .buttonStyle(TwisterButtonStyle(.secondary,compact:true))
                    }
                    Spacer()
                }
            }
            if !presets.library.applicable(to:state.inputs).isEmpty || presets.issue != nil {
                HStack(spacing:7) {
                    Text("PRESETS").font(.system(size:9,weight:.bold,design:.default)).tracking(0.8).foregroundStyle(.secondary)
                    Spacer()
                    Button { state.onPresetSettings?() } label:{ LText("Manage presets") }.buttonStyle(TwisterButtonStyle(.quiet,compact:true))
                }
                PresetListView(state:state)
            }
        }
    }
    private var historySection:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text("Recent files").font(.system(size:16,weight:.bold,design:.default))
                TwisterPill(title:"\(state.history.count)")
                Spacer()
                HStack(spacing:6) { Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("Find a recent file",text:$historySearch).textFieldStyle(.plain).font(.system(size:11)) }
                    .padding(8).frame(width:185).background(TwisterPalette.inset,in:RoundedRectangle(cornerRadius:10))
            }
            VStack(spacing:3) {
                if recent.isEmpty { Text("No matches. Try a file name or tool.").font(.callout).foregroundStyle(.secondary).padding(20).frame(maxWidth:.infinity) }
                ForEach(recent) { job in
                    RecentFileRow(job:job,canReuse:!state.working,onPreview:{state.preview(job)},onReuse:{ _ in state.reuse(job) })
                }
            }.padding(7).twisterCard()
            if state.history.count>3 && historySearch.isEmpty {
                Button(allHistory ? "Show less":"See all recent files") { allHistory.toggle() }.buttonStyle(TwisterButtonStyle(.quiet,compact:true))
            }
        }.twisterAnimation(value:allHistory)
    }
    private func receiveDrop(_ providers:[NSItemProvider])->Bool {
        WebLinkPayload.urls(from:providers) { urls in
            if urls.first?.isFileURL == false { state.onWebDrop?(urls) }
            else if !urls.isEmpty { state.inputs=urls }
        }
        return !providers.isEmpty
    }
}

private struct HomeActionTile:View {
    let title:String;let subtitle:String;let symbol:String;let color:Color
    @State private var hovered=false
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Image(systemName:symbol).font(.system(size:16,weight:.regular)).foregroundStyle(TwisterPalette.forest);Spacer();Image(systemName:"chevron.down").font(.system(size:8)).foregroundStyle(.secondary) }
            LText(title).font(.system(size:11,weight:.semibold))
            LText(subtitle).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(2).frame(height:25,alignment:.top)
        }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            .background(hovered ? TwisterPalette.inset:TwisterPalette.surface,in:RoundedRectangle(cornerRadius:6))
            .overlay(RoundedRectangle(cornerRadius:6).strokeBorder(TwisterPalette.border,lineWidth:1))
            .onHover{hovered=$0}
    }
}
private struct RecentFileRow:View {
    let job:JobRecord
    let canReuse:Bool
    let onPreview:()->Void
    let onReuse:([URL])->Void
    @State private var hovered=false
    @Environment(\.locale) private var locale
    private var urls:[URL] { job.outputs.map{URL(fileURLWithPath:$0)} }
    private var available:[URL] { urls.filter{FileManager.default.fileExists(atPath:$0.path)} }
    var body:some View {
        HStack(spacing:12) {
            if let first=urls.first { AsyncFileArtwork(url:first).frame(width:29,height:29).padding(5).background(TwisterPalette.inset,in:RoundedRectangle(cornerRadius:11)) }
            VStack(alignment:.leading,spacing:4) {
                Text(urls.first?.lastPathComponent ?? job.title).font(.system(size:12,weight:.semibold)).lineLimit(1)
                HStack(spacing:3) { if available.isEmpty { Text("Moved or removed") } else { LText(job.title);Text("· "+job.date.formatted(.relative(presentation:.named).locale(locale))) } }.font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if urls.count>1 { Text("\(urls.count) files").font(.caption2).foregroundStyle(.secondary) }
            Button(action:onPreview) {Image(systemName:"eye").font(.system(size:13))}.buttonStyle(TwisterButtonStyle(.quiet,compact:true)).disabled(available.isEmpty).help("Preview").accessibilityLabel("Preview \(urls.first?.lastPathComponent ?? "result")")
            Button { onReuse(available) } label:{Image(systemName:"arrow.up.left").font(.system(size:12,weight:.medium))}
                .buttonStyle(TwisterButtonStyle(.quiet,compact:true)).disabled(available.isEmpty || !canReuse)
                .help(canReuse ? "Use these files again":"Available after the current task finishes")
                .accessibilityLabel("Use \(urls.first?.lastPathComponent ?? "result") again")
            Button { NSWorkspace.shared.activateFileViewerSelecting(available) } label:{Image(systemName:"folder").font(.system(size:13))}
                .buttonStyle(TwisterButtonStyle(.quiet,compact:true)).disabled(available.isEmpty).help("Show in Finder").accessibilityLabel("Show \(urls.first?.lastPathComponent ?? "result") in Finder")
        }.padding(.horizontal,10).padding(.vertical,8).background(hovered ? TwisterPalette.inset.opacity(0.75):Color.clear,in:RoundedRectangle(cornerRadius:14))
            .onHover{hovered=$0}.twisterAnimation(value:hovered)
    }
}
private extension URL { var abbreviatingWithTildeInPath:String { (path as NSString).abbreviatingWithTildeInPath } }

struct JobProgressView:View {
    @ObservedObject var state:AppState
    var body:some View {
        VStack(spacing:10) {
            if state.working {
                VStack(alignment:.leading,spacing:12) {
                    HStack(spacing:10) {
                        ProgressView().controlSize(.small)
                        VStack(alignment:.leading,spacing:4) { Text("Processing files…").font(.system(size:13,weight:.semibold,design:.default));LText(state.progressLabel).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer()
                        if state.progressIsDeterminate { Text("\(Int(state.progress*100))%").font(.system(size:12,weight:.semibold,design:.default)).monospacedDigit().foregroundStyle(.secondary) }
                        Button("Cancel") { state.token.cancel() }.buttonStyle(TwisterButtonStyle(.secondary,compact:true))
                    }
                    JobProgressBar(state:state)
                }.padding(17).twisterCard(radius:18).transition(.opacity.combined(with:.move(edge:.top)))
            }
            if let error=state.error {
                HStack(alignment:.top,spacing:10) {
                    Image(systemName:"exclamationmark.circle.fill").foregroundStyle(.orange)
                    VStack(alignment:.leading,spacing:4) { Text("Could not complete this task").font(.system(size:12,weight:.semibold,design:.default));LText(error).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled) }
                    Spacer();Button { state.error=nil } label:{Image(systemName:"xmark")}.buttonStyle(TwisterButtonStyle(.quiet,compact:true)).accessibilityLabel("Dismiss error")
                }.padding(15).background(Color.orange.opacity(0.07)).background(TwisterPalette.canvas).clipShape(RoundedRectangle(cornerRadius:17)).transition(.opacity)
            }
        }.twisterAnimation(value:state.working).twisterAnimation(value:state.outputs.count).twisterAnimation(value:state.error != nil)
    }
}

/// Keep the complete tile as the button label; NSPopUpButton otherwise flattens it to an icon/title.
@MainActor private enum HomeActionMenu {
    private final class Action:NSObject {
        let run:()->Void
        init(_ run:@escaping()->Void){self.run=run}
        @objc func invoke(){run()}
    }
    static func show(_ choices:[(String,()->Void)]) {
        let menu=NSMenu();let handlers=choices.map{Action($0.1)}
        for (index,choice) in choices.enumerated(){let item=NSMenuItem(title:L10n.text(choice.0),action:#selector(Action.invoke),keyEquivalent:"");item.target=handlers[index];menu.addItem(item)}
        _ = withExtendedLifetime(handlers){menu.popUp(positioning:nil,at:NSEvent.mouseLocation,in:nil)}
    }
}
