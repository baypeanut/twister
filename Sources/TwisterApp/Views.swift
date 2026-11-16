import AppKit
import SwiftUI
import TwisterCore
import UniformTypeIdentifiers
import ServiceManagement
import TwisterUpdates
import ApplicationServices
import Combine

struct SettingsView:View {
    @ObservedObject var updater:AppUpdater
    /// The workspace whose presets and selection the Presets page uses.
    private let state:AppState?
    /// The toolbar tabs of the Settings window; absent when the view is shown alone.
    private let navigation:SettingsNavigation?
    @State private var section=SettingsSection.general
    @State private var selectedFormat="jpg"
    @State private var formatSearch=""
    @ObservedObject private var preferences=FormatPreferences.shared
    @AppStorage("enabled") private var enabled=true
    @AppStorage("reveal") private var reveal=false
    @AppStorage("wheelScale") private var wheelScale=1.0
    @AppStorage("conversionFanTheme") private var fanTheme="glass"
    @AppStorage("soundsAndHapticsEnabled") private var feedback=true
    @AppStorage("floatWheelBehavior") private var floatBehavior="createNew"
    @AppStorage("fileActionsTerminalApplication") private var terminalApplication="com.apple.Terminal"
    @State private var shortcutsRevision=0
    @State private var launch=false
    @State private var launchNeedsApproval=false
    @State private var launchUnavailable=false
    @State private var launchError:String?
    @AppStorage("reduceAnimations") private var reduceAnimations=false
    @AppStorage("appAppearance") private var appAppearance="system"
    @AppStorage("appLanguage") private var appLanguage="en"
    @AppStorage("windowManagementEnabled") private var windowManagementEnabled=false
    @AppStorage(JobNotifier.preferenceKey) private var jobNotifications=true
    @State private var windowAccessibility=false
    @State private var webDownloads=WebDownloadGate.preference(in:.standard)
    @State private var toolStatus=ExternalToolSetup.status
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    init(updater:AppUpdater,state:AppState?=nil,navigation:SettingsNavigation?=nil,showingUpdates:Bool=false,initialSection:SettingsSection = .general) {
        self.updater=updater;self.state=state;self.navigation=navigation
        _section=State(initialValue:showingUpdates ? .updates:initialSection)
    }
    private var terminalApplications:[(String,String)] {
        var apps=[("com.apple.Terminal","Terminal")]
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.googlecode.iterm2") != nil { apps.append(("com.googlecode.iterm2","iTerm2")) }
        if !apps.contains(where:{$0.0==terminalApplication}) { apps.append((terminalApplication,"\(terminalApplication) (Not installed)")) }
        return apps
    }
    var body:some View {
        Group {
            switch section {
            case .general:general
            case .formats:formats
            case .presets:presetsPage
            case .compatibility:CompatibilitySettingsView { format in selectedFormat=format;section = .formats }
            case .folders:FolderSettingsView()
            case .updates:UpdateSettingsView(updater:updater)
            case .about:AboutSettingsView()
            }
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity).id(section)
        .frame(minWidth:620,minHeight:460).background(Color(nsColor:.windowBackgroundColor))
        .onAppear(perform:readLaunchStatus)
        .onAppear { navigation?.section=section }
        .onChange(of:section) { navigation?.section=$0 }
        .onReceive(navigation?.$section.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { if section != $0 { section=$0 } }
        .onReceive(NotificationCenter.default.publisher(for:.showUpdateSettings)) { _ in section = .updates }
        .onReceive(NotificationCenter.default.publisher(for:.showPresetSettings)) { _ in section = .presets }
        .onChange(of:feedback) { UserDefaults.standard.set($0,forKey:"sound") }
        .onChange(of:appAppearance) { TwisterAppearance.apply($0) }
        .onChange(of:appLanguage) { _ in NotificationCenter.default.post(name:.twisterLanguageChanged,object:nil) }
        .onChange(of:windowManagementEnabled) { _ in NotificationCenter.default.post(name:.windowManagementPreferencesChanged,object:nil) }
        .onChange(of:enabled) { _ in NotificationCenter.default.post(name:.windowManagementPreferencesChanged,object:nil) }
        .onChange(of:terminalApplication) { UserDefaults.standard.set($0=="com.googlecode.iterm2" ? "iTerm2":"Terminal",forKey:"terminalApp") }
    }
    @ViewBuilder private var presetsPage:some View { if let state { PresetSettingsView(state:state) } }
    private func refreshOptionalExtras() { toolStatus=ExternalToolSetup.status;webDownloads=WebDownloadGate.preference(in:.standard) }
    /// Instructions and the permission check appear only after the feature is turned on.
    @ViewBuilder private var windowArrangementDetails:some View {
        VStack(alignment:.leading,spacing:4) {
            Text("Drag a window by its title bar or resize border, then tap Shift or Command. Hover over a layout and release the mouse to place it. Escape cancels.")
            Text("1/3 left · middle · right   /   1/2 left · right   /   2/3 left · right")
        }.font(.subheadline).foregroundStyle(.secondary)
        Group {
            if !windowAccessibility {
                LabeledContent {
                    Button("Open Permission Settings…") { WindowManagementController.requestAccess() }
                } label:{
                    Text("Allow \(WindowManagementController.permissionName) once to move and resize other apps’ windows.").font(.subheadline).foregroundStyle(.secondary)
                }
                if Bundle.main.bundleIdentifier == "app.twister.desktop" {
                    LabeledContent {
                        Button("Show Twister in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                    } label:{
                        Text("Choose this copy of Twister when adding it to \(WindowManagementController.permissionName).").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            } else { Label("\(WindowManagementController.permissionName) is enabled",systemImage:"checkmark.circle").font(.subheadline).foregroundStyle(.secondary) }
        }
        .onAppear { windowAccessibility=AXIsProcessTrusted() }
        .onReceive(Timer.publish(every:2,on:.main,in:.common).autoconnect()) { _ in windowAccessibility=AXIsProcessTrusted() }
    }
    private var general:some View {
        Form {
            Section {
                Picker("Language",selection:$appLanguage) { Text(verbatim:"English").tag("en");Text(verbatim:"Türkçe").tag("tr") }.accessibilityIdentifier("AppLanguage").uiAuditSelection("languagePicker",appLanguage=="tr" ? "Türkçe":"English")
                Picker("Appearance",selection:$appAppearance) { Text("System").tag("system");Text("Light").tag("light");Text("Dark").tag("dark") }.uiAuditSelection("appearancePicker",appAppearance)
                Picker("Wheel finish",selection:$fanTheme) { Text("Glass").tag("glass");Text("Solid").tag("metallic") }
            }
            Section {
                Toggle(isOn:Binding(get:{launch},set:updateLaunch)) {
                    Text("Launch at login")
                    if launchUnavailable { Text("Launch at login is unavailable for this copy.") }
                    if let launchError { Text(launchError) }
                }.disabled(launchUnavailable)
                if launchNeedsApproval { LabeledContent { Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() } } label:{ Text("Allow Twister in macOS Login Items.").font(.subheadline).foregroundStyle(.secondary) } }
                Toggle(isOn:$feedback) {
                    Text("Sound and haptic feedback")
                    Text("Sound follows your Mac’s volume. Haptics need a compatible Force Touch trackpad.")
                }
                HStack { Spacer();Button("Try Feedback") { _ = WheelFeedback.shared.testPreview() }.disabled(!feedback) }
                Toggle("Notify when a task finishes in the background",isOn:$jobNotifications)
                Toggle(isOn:Binding(get:{!reduceAnimations},set:{reduceAnimations = !$0})) {
                    Text("Subtle animations")
                    if systemReducedMotion { Text("macOS Reduce Motion is on. Twister keeps motion off.") }
                }
            }
            Section {
                ForEach(WheelShortcut.allCases) { wheel in
                    Picker(selection:shortcut(wheel)) { ForEach(ModifierPreferences.available(for:wheel)) { chord in Text("\(chord.symbols)  \(chord.title)").tag(chord.rawValue) } } label:{ LText(wheel.title) }
                }
            } header:{ Text("Drag shortcuts") } footer:{ Text("Tap the chosen modifier combination while dragging files.").frame(maxWidth:.infinity,alignment:.leading) }
            .id(shortcutsRevision)
            Section("Optional extras") {
                if AppFeatures.webDownloads {
                    Toggle(isOn:Binding(get:{ WebDownloadGate.isOn(preference:webDownloads,status:toolStatus) },set:{ webDownloads=$0;UserDefaults.standard.set($0,forKey:WebDownloadGate.preferenceKey) })) {
                        Text("Web downloads")
                        Text("Save media from a public link. This uses separate tools that file conversion does not need.")
                    }.accessibilityIdentifier("WebDownloadsEnabled")
                    if WebDownloadGate.isOn(preference:webDownloads,status:toolStatus),case .needsTools=WebDownloadGate.availability(included:true,preference:webDownloads,status:toolStatus) {
                        LabeledContent {
                            Button("Install Web Download Tools…") { NotificationCenter.default.post(name:.showToolSetup,object:nil) }
                        } label:{ Text("The web download tools are not installed.").font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
                Toggle(isOn:$windowManagementEnabled) {
                    Text("Arrange windows while dragging")
                    Text("Window arrangement is an optional extra. It keeps working but is no longer being extended.")
                }
                if windowManagementEnabled { windowArrangementDetails }
            }
            .onReceive(NotificationCenter.default.publisher(for:.toolSetupChanged)) { _ in refreshOptionalExtras() }
            .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in refreshOptionalExtras() }
            Section("File actions") {
                Picker("Float behavior",selection:$floatBehavior) { Text("Create a New Float").tag("createNew");Text("Add Files to an Existing Float").tag("addToExisting") }
                Picker("Terminal app",selection:$terminalApplication) { ForEach(terminalApplications,id:\.0) { app in Text(app.1).tag(app.0) } }
            }
            Section("Advanced") {
                Toggle("Enable Twister",isOn:$enabled)
                Toggle("Reveal finished files in Finder while Twister is active",isOn:$reveal)
                LabeledContent("Wheel size") { HStack { Slider(value:$wheelScale,in:0.85...1.4).frame(width:200);Text("\(Int(wheelScale*100))%").monospacedDigit().frame(width:44,alignment:.trailing) } }
            }
        }.formStyle(.grouped)
    }
    private var formats:some View {
        HStack(spacing:0) {
            VStack(spacing:0) {
                TextField("Search",text:$formatSearch).textFieldStyle(.roundedBorder).padding(8).accessibilityLabel(L10n.text("Search formats"))
                Divider()
                List(selection:$selectedFormat) {
                    ForEach(FormatPreferenceItem.groups,id:\.0) { group in
                        let entries=FormatPreferenceItem.all.filter{$0.group==group.0 && (formatSearch.isEmpty || $0.title.localizedCaseInsensitiveContains(formatSearch) || $0.id.localizedCaseInsensitiveContains(formatSearch))}
                        if !entries.isEmpty { Section(LocalizedStringKey(group.0)) { ForEach(entries) { item in Text(item.id=="gz" ? "GZIP":item.id.uppercased()).tag(item.id).listRowSeparator(.hidden) } } }
                    }
                }.listStyle(.inset)
            }.frame(width:160)
            Divider()
            FormatSettingsDetail(format:FormatPreferenceItem.all.first{$0.id==selectedFormat} ?? FormatPreferenceItem.all[0],preferences:preferences,state:state).frame(maxWidth:.infinity,maxHeight:.infinity)
        }
    }
    private func shortcut(_ wheel:WheelShortcut)->Binding<UInt> {
        Binding(get:{ModifierPreferences.chord(for:wheel).rawValue},set:{if ModifierPreferences.set(.init(rawValue:$0),for:wheel) { shortcutsRevision += 1 }})
    }
    private func readLaunchStatus() {
        let status=SMAppService.mainApp.status
        launch=status == .enabled || status == .requiresApproval;launchNeedsApproval=status == .requiresApproval;launchUnavailable=status == .notFound
    }
    private func updateLaunch(_ value:Bool) {
        do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() };launchError=nil } catch { launchError=error.localizedDescription }
        readLaunchStatus()
    }
}

enum SettingsSection:String,CaseIterable,Identifiable {
    case general="General",formats="Formats",presets="Presets",compatibility="Compatibility",folders="Folders",updates="Updates",about="About"
    var id:String { rawValue }
    var symbol:String { switch self { case .general:return "gearshape";case .formats:return "doc";case .presets:return "bookmark";case .compatibility:return "arrow.left.arrow.right";case .folders:return "folder";case .updates:return "arrow.down.circle";case .about:return "info.circle" } }
}

private struct FormatSettingsDetail:View {
    let format:FormatPreferenceItem
    @ObservedObject var preferences:FormatPreferences
    let state:AppState?
    private var isVideo:Bool { ["mp4","mov","mkv","webm","avi","wmv"].contains(format.id) }
    private var hasQuality:Bool { ["jpg","webp","heic","avif"].contains(format.id) || isVideo }
    private var hasMetadata:Bool { ["jpg","png","webp","heic","tiff","avif"].contains(format.id) }
    private var hasAudioBitrate:Bool { ["mp3","m4a","ogg","opus","wma"].contains(format.id) }
    private var hasDepth:Bool { ["wav","aiff"].contains(format.id) }
    private var hasCompression:Bool { ["flac","zip","gz"].contains(format.id) }
    private var hasLayout:Bool { ["docx","pages","epub"].contains(format.id) }
    private var hasControls:Bool { hasQuality || hasMetadata || hasAudioBitrate || hasDepth || hasCompression || hasLayout || format.id=="gif" }
    var body:some View {
        Form {
            Section {
                LabeledContent { LText(format.compatibilityLabel) } label:{ Text(verbatim:format.title) }
            } footer:{
                if format.isInputOnly { Text("This format can be imported. Choose an output format in the sidebar to configure its defaults.").frame(maxWidth:.infinity,alignment:.leading) }
                else if !hasControls { Text("This output format has no adjustable conversion defaults.").frame(maxWidth:.infinity,alignment:.leading) }
            }
            if !format.isInputOnly,hasControls {
                Section("Conversion Settings") {
                    if hasQuality { Picker("Quality",selection:profile(\.quality)) { ForEach(OutputQuality.allCases) { LText($0.title).tag($0) } } }
                    if hasMetadata { Toggle("Preserve metadata",isOn:profile(\.preserveMetadata)) }
                    if hasAudioBitrate { Picker("Bitrate",selection:profile(\.audioBitrate)) { ForEach([128,192,256,320],id:\.self) { Text("\($0) kbps").tag($0) } } }
                    if hasDepth { Picker("Sample depth",selection:profile(\.audioSampleDepth)) { Text("Match Source").tag("matchSource");Text("16-bit integer").tag("pcm16");Text("24-bit integer").tag("pcm24");Text("32-bit integer").tag("pcm32");Text("32-bit float").tag("float32") } }
                    if isVideo { Picker("Maximum height",selection:profile(\.videoMaxHeight)) { Text("Original").tag(0);ForEach([2160,1080,720,480],id:\.self) { Text("\($0)p").tag($0) } } }
                    if hasCompression { compressionPicker(profile(\.compressionPreset)) }
                    if format.id=="gif" {
                        Picker("Frame rate",selection:profile(\.gifFrameRate)) { ForEach([10,15,24],id:\.self) { Text("\($0) fps").tag($0) } }
                        Picker("Maximum width",selection:profile(\.gifMaxWidth)) { ForEach([480,960,1280],id:\.self) { Text("\($0) px").tag($0) } }
                        compressionPicker(profile(\.compressionPreset))
                    }
                    if ["docx","pages"].contains(format.id) { Picker("PDF layout",selection:profile(\.pdfOfficeLayout)) { Text("Editable paragraphs and tables").tag("editable");Text("Preserve original pages").tag("preservePages") } }
                    if format.id=="epub" { Picker("PDF layout",selection:profile(\.epubLayout)) { Text("Reflowable text").tag("reflowable");Text("Preserve original pages").tag("fixed") } }
                    HStack { Spacer();Button("Restore Defaults") { preferences.restoreDefaults(for:format.id) } }
                }
            }
            if ["jpg","png"].contains(format.id) { imageCompression }
            if isVideo || format.id=="gif" { videoCompression }
            if let state,!format.isInputOnly {
                Section {
                    LabeledContent {
                        Button { PresetPrompt.save(.convert(format.id),options:preferences.options(for:format.id),state:state) } label:{ LText("Save as Preset…").lineLimit(1).fixedSize() }
                    } label:{ LText("Keep these settings as a preset you can run on any files that convert to \(format.title).").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
                }
            }
        }.formStyle(.grouped).id(format.id)
    }
    private var imageCompression:some View {
        Section("Compression Settings") {
            Picker("Image Compression",selection:Binding(get:{preferences.imageCompressionStrength},set:{preferences.setCompression($0,key:"defaultImageCompressionStrength")})) { Text("Balanced").tag("balanced");Text("Strong").tag("strong") }
            Picker("Image size",selection:Binding(get:{preferences.imageCompressionSize},set:{preferences.setCompression($0,key:"defaultImageCompressionSize")})) { Text("Keep original dimensions").tag("original");Text("Large · 2560 px").tag("large");Text("Medium · 1920 px").tag("medium");Text("Small · 1280 px").tag("small") }
            HStack { Spacer();Button("Restore Defaults") { preferences.restoreCompressionDefaults(video:false) } }
        }
    }
    private var videoCompression:some View {
        Section("Compression Settings") {
            Picker("Video Compression",selection:Binding(get:{preferences.videoCompressionStrength},set:{preferences.setCompression($0,key:"defaultVideoCompressionStrength")})) { Text("Balanced").tag("balanced");Text("Strong").tag("strong") }
            HStack { Spacer();Button("Restore Defaults") { preferences.restoreCompressionDefaults(video:true) } }
        }
    }
    private func profile<T>(_ key:WritableKeyPath<OutputFormatProfile,T>)->Binding<T> {
        Binding(get:{preferences.profile(for:format.id)[keyPath:key]},set:{value in var p=preferences.profile(for:format.id);p[keyPath:key]=value;preferences.save(p,for:format.id)})
    }
    private func compressionPicker(_ binding:Binding<String>)->some View { Picker("Compression",selection:binding) { Text("Faster").tag("fast");Text("Balanced").tag("balanced");Text("Smallest").tag("maximum") } }
}

private struct FolderSettingsView:View {
    @State private var folders:[AllowedFolder]=[]
    @State private var error:String?
    var body:some View {
        Form {
            Section {
                if folders.isEmpty { Text("No folders allowed yet.").foregroundStyle(.secondary) }
                ForEach(folders) { grant in HStack {
                    Image(nsImage:NSWorkspace.shared.icon(forFile:grant.path)).resizable().frame(width:24,height:24).accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:2) { Text(URL(fileURLWithPath:grant.path).lastPathComponent);Text((grant.path as NSString).abbreviatingWithTildeInPath).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
                    Spacer();Button { FolderAccessPreferences.remove(grant);refresh() } label:{Image(systemName:"minus.circle")}.buttonStyle(.borderless).help("Remove folder access").accessibilityLabel(L10n.text("Remove folder access"))
                } }
                HStack { Spacer();Button("Allow Home Folder Access…") { choose(home:true) };Button("Allow Folder…") { choose(home:false) } }
            } header:{ Text("Folders") } footer:{
                VStack(alignment:.leading,spacing:4) {
                    Text("Twister saves results beside the originals. Allow a folder once to include every folder inside it.")
                    if let error { LText(error).foregroundStyle(.red) }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
        }.formStyle(.grouped).onAppear(perform:refresh)
    }
    private func refresh() { folders=FolderAccessPreferences.grants() }
    private func choose(home:Bool) {
        let panel=NSOpenPanel();panel.title="Allow Folder Access";panel.prompt="Allow Access";panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.allowsMultipleSelection=true
        panel.message="Choose a folder where Twister may save results. Every folder inside it is included."
        if home { panel.directoryURL=FileManager.default.homeDirectoryForCurrentUser }
        if panel.runModal() == .OK { do { try FolderAccessPreferences.add(panel.urls);error=nil;refresh() } catch { self.error=error.localizedDescription } }
    }
}

private struct CompatibilitySettingsView:View {
    let onSelectFormat:(String)->Void
    @State private var source="jpg"
    private var targets:[String] { FeatureCatalog.conversionMatrix[source] ?? [] }
    var body:some View {
        Form {
            Section {
                Picker("Input format",selection:$source) { ForEach(FormatPreferenceItem.all.filter{!$0.isOutputOnly}) { LText($0.title).tag($0.id) } }
            } footer:{ Text("Choose an input format to see its available outputs.").frame(maxWidth:.infinity,alignment:.leading) }
            Section("Convert to") {
                if targets.isEmpty { Text("No output formats").foregroundStyle(.secondary) }
                LazyVGrid(columns:[GridItem(.adaptive(minimum:76),spacing:8)],alignment:.leading,spacing:8) { ForEach(targets,id:\.self) { format in Button { onSelectFormat(format) } label:{ Text(format=="gz" ? "GZIP":format.uppercased()).frame(maxWidth:.infinity) } } }
            }
        }.formStyle(.grouped)
    }
}

private struct AboutSettingsView:View {
    private var version:String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "Development" }
    private var build:String { Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "—" }
    var body:some View {
        VStack(spacing:8) {
            Image(nsImage:NSApp.applicationIconImage).resizable().frame(width:96,height:96).accessibilityHidden(true)
            Text(verbatim:"Twister").font(.title.weight(.semibold))
            Text("Version \(version) (\(build))").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Text("Convert, edit, and organize your files.\nProcessed locally on your Mac.").font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.top,8)
        }.padding(32).frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}

/// The selected Settings pane, shared by the toolbar tabs and the view.
@MainActor final class SettingsNavigation:ObservableObject {
    @Published var section=SettingsSection.general
}

/// Standard preference tabs in the window toolbar, one per pane.
@MainActor final class SettingsToolbar:NSObject,NSToolbarDelegate {
    let navigation:SettingsNavigation
    private let toolbar=NSToolbar(identifier:"Twister.Settings")
    private var observations:Set<AnyCancellable>=[]
    init(navigation:SettingsNavigation) { self.navigation=navigation;super.init() }
    func install(in window:NSWindow) {
        toolbar.delegate=self;toolbar.displayMode = .iconAndLabel;toolbar.allowsUserCustomization=false
        window.toolbar=toolbar;window.toolbarStyle = .preference
        toolbar.selectedItemIdentifier=identifier(navigation.section)
        navigation.$section.sink { [weak self,weak window] section in
            guard let self else{return}
            self.toolbar.selectedItemIdentifier=self.identifier(section)
            // A preference window is titled after its pane.
            if let window { L10n.windowTitle(window,source:section.rawValue) }
        }.store(in:&observations)
        NotificationCenter.default.publisher(for:.twisterLanguageChanged).sink { [weak self] _ in
            guard let self else{return}
            for item in self.toolbar.items { if let section=SettingsSection(rawValue:item.itemIdentifier.rawValue) { item.label=L10n.text(section.rawValue) } }
        }.store(in:&observations)
    }
    private func identifier(_ section:SettingsSection)->NSToolbarItem.Identifier { .init(section.rawValue) }
    func toolbarAllowedItemIdentifiers(_ toolbar:NSToolbar)->[NSToolbarItem.Identifier] { SettingsSection.allCases.map(identifier) }
    func toolbarDefaultItemIdentifiers(_ toolbar:NSToolbar)->[NSToolbarItem.Identifier] { SettingsSection.allCases.map(identifier) }
    func toolbarSelectableItemIdentifiers(_ toolbar:NSToolbar)->[NSToolbarItem.Identifier] { SettingsSection.allCases.map(identifier) }
    func toolbar(_ toolbar:NSToolbar,itemForItemIdentifier itemIdentifier:NSToolbarItem.Identifier,willBeInsertedIntoToolbar flag:Bool)->NSToolbarItem? {
        guard let section=SettingsSection(rawValue:itemIdentifier.rawValue) else { return nil }
        let item=NSToolbarItem(itemIdentifier:itemIdentifier)
        item.label=L10n.text(section.rawValue);item.image=NSImage(systemSymbolName:section.symbol,accessibilityDescription:nil)
        item.target=self;item.action=#selector(select(_:));return item
    }
    @objc private func select(_ sender:NSToolbarItem) { if let section=SettingsSection(rawValue:sender.itemIdentifier.rawValue) { navigation.section=section } }
}
