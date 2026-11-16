import AppKit
import SwiftUI
import TwisterCore

extension Notification.Name { static let showPresetSettings=Notification.Name("TwisterShowPresetSettings") }

/// The saved presets as the app shows them. Every change reads the shared file
/// first, so presets added by twister-cli in the meantime are kept.
@MainActor final class PresetCenter:ObservableObject {
    @Published private(set) var library=PresetLibrary()
    @Published var issue:String?
    /// Nil keeps the presets in memory, for QA runs that must not touch the user's file.
    private let store:PresetStore?
    init(store:PresetStore?) { self.store=store;reload() }
    var presets:[Preset] { library.presets }

    func reload() {
        guard let store else { return }
        do { accept(try store.load()) } catch { issue=error.localizedDescription }
    }
    private func accept(_ loaded:PresetLibrary) {
        if let moved=loaded.preservedCorruptFile { issue="The presets file could not be read and was kept as \(moved.lastPathComponent)." }
        library=loaded
    }
    @discardableResult func change<T>(_ body:(inout PresetLibrary) throws -> T) throws -> T {
        var updated=library
        let result:T
        if let store { result=try store.update { let value=try body(&$0);updated=$0;return value } }
        else { result=try body(&updated) }
        accept(updated);return result
    }
    @discardableResult func save(name:String,operation:TwisterCore.Operation,options:OperationOptions,destination:PresetDestination?) throws -> Preset {
        try change { try $0.add(Preset(name:name,operation:operation,options:options,destination:destination)) }
    }
    /// Swaps a preset with its neighbour in the list the user is looking at.
    func move(_ preset:Preset,by direction:Int,among visible:[Preset]) {
        guard let index=visible.firstIndex(where:{$0.id==preset.id}),visible.indices.contains(index+direction) else { return }
        let neighbour=visible[index+direction].id
        attempt { library in
            guard let from=library.presets.firstIndex(where:{$0.id==preset.id}),let to=library.presets.firstIndex(where:{$0.id==neighbour}) else { return }
            library.move(preset.id,by:to-from)
        }
    }
    func attempt(_ body:(inout PresetLibrary) throws -> Void) {
        do { try change(body);issue=library.preservedCorruptFile == nil ? nil:issue } catch { issue=error.localizedDescription }
    }
}

@MainActor enum PresetPrompt {
    /// Asks for a name and a destination, and repeats while the name cannot be used.
    static func save(_ operation:TwisterCore.Operation,options:OperationOptions,state:AppState) {
        let center=state.presets;center.reload()
        let alert=NSAlert()
        alert.messageText=L10n.text("Save as preset");alert.informativeText=L10n.text("Keeps this operation and its options, ready to run on other files.")
        let field=NSTextField(string:center.library.availableName(L10n.text(operation.title)));field.placeholderString=L10n.text("Preset name")
        let destination=NSPopUpButton(frame:.zero,pullsDown:false)
        destination.addItems(withTitles:[L10n.text("Save where Twister is set to save"),L10n.text("Always save beside originals")])
        let folder=state.outputDestination.folder
        if let folder { destination.addItem(withTitle:"");destination.lastItem?.title=L10n.text("Always save to \(folder.lastPathComponent)") }
        destination.setAccessibilityLabel(L10n.text("Save to"))
        let stack=NSStackView(views:[field,destination]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=8
        stack.frame=NSRect(x:0,y:0,width:300,height:58);field.widthAnchor.constraint(equalToConstant:300).isActive=true
        alert.accessoryView=stack;alert.window.initialFirstResponder=field
        alert.addButton(withTitle:L10n.text("Save"));alert.addButton(withTitle:L10n.text("Cancel"))
        NSApp.activate(ignoringOtherApps:true)
        while alert.runModal() == .alertFirstButtonReturn {
            let choice:PresetDestination?=destination.indexOfSelectedItem==1 ? .besideOriginals:destination.indexOfSelectedItem==2 ? folder.map(PresetDestination.folder):nil
            do {
                let preset=try center.save(name:field.stringValue,operation:operation,options:options,destination:choice)
                state.reportSuccess(SuccessNotice(title:"Preset saved",detail:preset.name));return
            } catch { alert.informativeText=L10n.text(error.localizedDescription) }
        }
    }
    static func rename(_ preset:Preset,in center:PresetCenter) {
        let alert=NSAlert();alert.messageText=L10n.text("Rename preset")
        let field=NSTextField(string:preset.name);field.frame=NSRect(x:0,y:0,width:300,height:24)
        alert.accessoryView=field;alert.window.initialFirstResponder=field
        alert.addButton(withTitle:L10n.text("Rename"));alert.addButton(withTitle:L10n.text("Cancel"))
        while alert.runModal() == .alertFirstButtonReturn {
            do { try center.change { try $0.rename(preset.id,to:field.stringValue) };return }
            catch { alert.informativeText=L10n.text(error.localizedDescription) }
        }
    }
    static func delete(_ preset:Preset,in center:PresetCenter) {
        let alert=NSAlert();alert.messageText=L10n.text("Delete “\(preset.name)”?");alert.informativeText=L10n.text("The preset is removed. Files it made stay where they are.")
        alert.addButton(withTitle:L10n.text("Delete"));alert.addButton(withTitle:L10n.text("Cancel"))
        alert.buttons.first?.hasDestructiveAction=true
        if alert.runModal() == .alertFirstButtonReturn { center.attempt { $0.remove(preset.id) } }
    }
}

/// Icon-only entry to the save prompt, for the footer of an editor.
struct SavePresetButton:View {
    let action:()->Void
    var body:some View {
        Button(action:action) { Image(systemName:"bookmark") }
            .buttonStyle(TwisterButtonStyle(.quiet,compact:true)).help(L10n.text("Save as preset…")).accessibilityLabel(L10n.text("Save as preset…")).accessibilityIdentifier("editor.savePreset")
    }
}

/// Presets with run, rename, duplicate, reorder and delete. The workspace
/// lists the presets that fit the selected files; Settings lists all of them.
struct PresetListView:View {
    @ObservedObject var state:AppState
    @ObservedObject private var center:PresetCenter
    private let all:Bool
    /// Called after a preset starts, with the files it runs on.
    private let onRun:((Preset)->Void)?
    private let inputs:[URL]?
    init(state:AppState,all:Bool=false,inputs:[URL]?=nil,onRun:((Preset)->Void)?=nil) { self.state=state;center=state.presets;self.all=all;self.inputs=inputs;self.onRun=onRun }
    private var files:[URL] { inputs ?? state.inputs }
    private var presets:[Preset] { all ? center.presets:center.library.applicable(to:files) }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            if let issue=center.issue {
                HStack(alignment:.top) { Label { LText(issue) } icon:{ Image(systemName:"exclamationmark.circle") }.font(.caption).foregroundStyle(.orange).textSelection(.enabled);Spacer(minLength:8);Button { center.issue=nil } label:{ Image(systemName:"xmark") }.buttonStyle(TwisterButtonStyle(.quiet,compact:true)).accessibilityLabel(L10n.text("Dismiss")) }
            }
            if !presets.isEmpty {
                VStack(spacing:0) {
                    ForEach(Array(presets.enumerated()),id:\.element.id) { index,preset in
                        if index>0 { Divider() }
                        row(preset,index:index)
                    }
                }.padding(.horizontal,12).padding(.vertical,4).twisterCard()
            }
        }
    }
    private func detail(_ preset:Preset)->String {
        let title=L10n.text(preset.operation.title)
        switch preset.destination {
        case .besideOriginals:return title+" · "+L10n.text("Beside originals")
        case .folder(let url):return title+" · "+url.lastPathComponent
        case nil:return title
        }
    }
    private func symbol(_ preset:Preset)->String {
        if case .tool(let tool)=preset.operation { return FeatureCatalog.toolSymbols[tool] ?? "slider.horizontal.3" }
        return "arrow.triangle.2.circlepath"
    }
    private func row(_ preset:Preset,index:Int)->some View {
        let fits=preset.applies(to:files)
        return HStack(spacing:10) {
            Image(systemName:symbol(preset)).font(.system(size:12)).foregroundStyle(TwisterPalette.forest).frame(width:18).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:2) {
                Text(verbatim:preset.name).font(.system(size:12,weight:.semibold)).lineLimit(1).truncationMode(.middle)
                Text(verbatim:detail(preset)).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength:8)
            Button { state.run(preset,inputs:files);onRun?(preset) } label:{ LText("Run").lineLimit(1).fixedSize() }
                .buttonStyle(TwisterButtonStyle(.secondary,compact:true)).disabled(!fits)
                .help(L10n.text(fits ? "Run on the selected files":files.isEmpty ? "Choose files to run this preset.":"This preset does not fit the selected files."))
                .accessibilityLabel(L10n.text("Run preset \(preset.name)"))
            Menu {
                Button { PresetPrompt.rename(preset,in:center) } label:{ LText("Rename…") }
                Button { center.attempt { $0.duplicate(preset.id) } } label:{ LText("Duplicate") }
                Button { center.move(preset,by:-1,among:presets) } label:{ LText("Move Up") }.disabled(index==0)
                Button { center.move(preset,by:1,among:presets) } label:{ LText("Move Down") }.disabled(index==presets.count-1)
                Divider()
                Button(role:.destructive) { PresetPrompt.delete(preset,in:center) } label:{ LText("Delete…") }
            } label:{ Image(systemName:"ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel(L10n.text("Preset actions for \(preset.name)"))
        }.padding(.vertical,7)
    }
}

struct PresetSettingsView:View {
    @ObservedObject var state:AppState
    @ObservedObject private var center:PresetCenter
    init(state:AppState) { self.state=state;center=state.presets }
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:18) {
            LText("Presets").font(.title2.weight(.semibold))
            LText("A preset keeps an operation with its options. Save one from a tool or from Formats, then run it on any files it fits, from Finder or with twister-cli.").foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            if center.presets.isEmpty { VStack(spacing:9) { Image(systemName:"bookmark").font(.system(size:36)).foregroundStyle(.secondary);LText("No presets yet.").foregroundStyle(.secondary) }.frame(maxWidth:.infinity).padding(.vertical,40) }
            PresetListView(state:state,all:true)
            if !center.presets.isEmpty { LText(state.inputs.isEmpty ? "Choose files in the workspace to run a preset.":"Run uses the files selected in the workspace.").font(.caption).foregroundStyle(.secondary) }
        }.padding(24).frame(maxWidth:680,alignment:.leading) }.frame(maxWidth:.infinity).onAppear { center.reload() }
    }
}
