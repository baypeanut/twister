import AppKit
import SwiftUI
import ServiceManagement
import TwisterCore

struct WelcomeView:View {
    let onDone:()->Void
    let onClose:()->Void
    let onMinimize:()->Void
    var onSetUpTools:(()->Void)?=nil
    @Environment(\.nativeWindowChrome) private var nativeWindowChrome
    @State private var page=0
    @State private var folderAllowed=false
    @State private var folderError:String?
    @State private var launchAtLogin=false
    @State private var launchNeedsApproval=false
    @State private var launchUnavailable=false
    @State private var launchError:String?
    private let names=["Welcome","Convert","Edit","Move & share","Folders","Ready"]
    private var toolsReady:Bool { ExternalToolSetup.status.ready }
    private var titles:[String] { ["Welcome to Twister","Convert with a Drag","Edit with Tools","Move, Copy, and Share","Choose Where You Work",toolsReady ? "Twister Is Ready":"Add Media and Office Tools"] }
    var body:some View {
        VStack(spacing:0) {
            if !nativeWindowChrome {
                HStack(spacing:8) {
                    Button(action:onClose) { Image(systemName:"xmark") }.buttonStyle(.borderless).accessibilityLabel("Close welcome").keyboardShortcut(.cancelAction)
                    ZStack { WindowDragRegion();LText("Welcome to Twister").font(.headline).allowsHitTesting(false) }
                }.padding(.horizontal,16).frame(height:36)
                Divider()
            }
            HStack(spacing:32) {
                ZStack {
                    if page==0 || page==5 { TwisterMark(size:128) }
                    else if page==4 { Image(systemName:folderAllowed ? "folder.badge.gearshape":"folder").font(.system(size:96,weight:.light)).foregroundStyle(.secondary) }
                    else { WelcomeWheelPreview(mode:page==1 ? .convert:page==2 ? .tools:.actions,items:page==1 ? converterItems:page==2 ? toolItems:actionItems).frame(width:300,height:300).allowsHitTesting(false).accessibilityHidden(true) }
                }.frame(width:300,height:300).id("art-\(page)").transition(.opacity)
                VStack(alignment:.leading,spacing:12) {
                    LText(titles[page]).font(.largeTitle).fixedSize(horizontal:false,vertical:true)
                    detail
                }.frame(width:320,alignment:.leading).id("copy-\(page)").transition(.opacity)
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
            Divider()
            HStack(spacing:8) {
                Button("Skip Tour",action:onDone)
                Spacer()
                HStack(spacing:8) { ForEach(0..<6,id:\.self) { index in Button { page=index } label:{ Circle().fill(page==index ? Color.accentColor:Color.secondary.opacity(0.4)).frame(width:7,height:7).frame(width:11,height:20).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("Step \(index+1) of 6: \(names[index])").accessibilityAddTraits(page==index ? .isSelected:[]) } }
                Spacer()
                if page>0 { Button("Back") { page-=1 } }
                if page==5,!toolsReady,let onSetUpTools { Button("Set Up Tools…",action:onSetUpTools) }
                Button(action:page==5 ? onDone:next) { LText(page==5 ? "Open Twister":"Continue") }.keyboardShortcut(.defaultAction)
            }.padding(.horizontal,20).padding(.vertical,12)
        }.frame(width:760,height:520).background(Color(nsColor:.windowBackgroundColor))
            .twisterAnimation(value:page)
            .onAppear { folderAllowed = !FolderAccessPreferences.grants().isEmpty;readLaunchStatus() }
            .onChange(of:page) { if $0==5 { readLaunchStatus() } }
    }
    @ViewBuilder private var detail:some View {
        switch page {
        case 0:
            Text("Twister converts, edits, and organizes files. Everything runs on your Mac.").foregroundStyle(.secondary)
        case 1,2,3:
            LText(page==1 ? "Drag a file in Finder, tap Shift, and drop it onto a format.":page==2 ? "Tap Command while dragging to crop, compress, annotate, or edit a file.":"Tap Control while dragging to copy, move, share, or carry files in a floating shelf.").foregroundStyle(.secondary)
            Text("You can also choose files from the main window.").font(.subheadline).foregroundStyle(.secondary)
        case 4:
            Text("Pick a folder you work in. Results are saved beside the originals by default.").foregroundStyle(.secondary)
            Button(action:chooseFolder) { LText(folderAllowed ? "Choose Another Folder…":"Choose Folder…") }
            if folderAllowed { Label { Text("Folder access ready") } icon:{ Image(systemName:"checkmark.circle.fill").foregroundStyle(.green) }.font(.subheadline) }
            Text("Optional. You can change this in Settings.").font(.subheadline).foregroundStyle(.secondary)
            if let folderError { Text(folderError).font(.subheadline).foregroundStyle(.red).lineLimit(2) }
        default:
            LText(toolsReady ? "Your tools are ready. Choose a file to get started.":"Image and PDF tools are ready to use. Media and Office tools are optional; install them now or later from Finish Setup.").foregroundStyle(.secondary)
            Toggle("Launch at login",isOn:Binding(get:{launchAtLogin},set:updateLaunch)).disabled(launchUnavailable)
            if launchNeedsApproval { Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() } }
            if launchUnavailable { Text("Launch at login is unavailable for this copy.").font(.subheadline).foregroundStyle(.secondary) }
            if let launchError { Text(launchError).font(.subheadline).foregroundStyle(.red).lineLimit(2) }
        }
    }
    private var converterItems: [WheelItem] {
        ["PNG", "WEBP", "HEIC", "TIFF", "AVIF", "BMP", "PDF"].map { WheelItem(title: $0) }
    }
    private var toolItems: [WheelItem] {
        [WheelItem(title: "Compress", symbol: "arrow.down.right.and.arrow.up.left"),
         WheelItem(title: "Metadata", symbol: "tag"),
         WheelItem(title: "Edit", symbol: "slider.horizontal.3"),
         WheelItem(title: "Annotate", symbol: "pencil.and.outline"),
         WheelItem(title: "Add Background", symbol: "photo.artframe"),
         WheelItem(title: "Crop", symbol: "crop"),
         WheelItem(title: "Redact", symbol: "eye.slash")]
    }
    private var actionItems: [WheelItem] {
        [WheelItem(title: "AirDrop", symbol: "dot.radiowaves.left.and.right"),
         WheelItem(title: "Float", symbol: "rectangle.on.rectangle"),
         WheelItem(title: "Copy", symbol: "doc.on.doc"),
         WheelItem(title: "Move", symbol: "folder"),
         WheelItem(title: "Copy Path", symbol: "link"),
         WheelItem(title: "Terminal", symbol: "terminal")]
    }

    private func next() { page = min(5, page + 1) }

    private func chooseFolder() {
        let picker = NSOpenPanel()
        picker.title = "Allow Home Folder Access"
        picker.message = "Choose your home folder or a folder where you save files."
        picker.prompt = "Allow Access"
        picker.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.canCreateDirectories = false
        picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            try FolderAccessPreferences.add([url])
            folderAllowed = true
            folderError = nil
        } catch {
            folderError = error.localizedDescription
        }
    }

    private func readLaunchStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        launchNeedsApproval = status == .requiresApproval
        launchUnavailable = status == .notFound
    }

    private func updateLaunch(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch {
            launchError = error.localizedDescription
        }
        readLaunchStatus()
    }
}

private struct WelcomeWheelPreview: NSViewRepresentable {
    let mode: WheelMode
    let items: [WheelItem]
    func makeNSView(context: Context) -> WheelView {
        let view = WheelView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view: WheelView, context: Context) {
        view.mode = mode
        view.items = items
        view.inputs = []
        view.onSelect = nil
        view.onCancel = nil
        view.onDragInputs = nil
        view.needsDisplay = true
    }
}
