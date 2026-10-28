import AppKit
import PDFKit
import SwiftUI
import TwisterCore

/// Exercises the production local shortcut router with isolated AppKit controls.
/// No events are posted globally and no user document or clipboard is touched.
@MainActor enum PDFEditingKeyboardChecks {
    @discardableResult static func run()throws->[String] {
        var checks:[String]=[]
        func check(_ condition:Bool,_ message:String)throws {
            guard condition else { throw UIAuditError("PDF keyboard check failed: "+message) }
            checks.append(message)
        }
        func key(_ character:String,modifiers:NSEvent.ModifierFlags,repeatKey:Bool=false)throws->NSEvent {
            guard let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:modifiers,
                timestamp:0,windowNumber:0,context:nil,characters:character,
                charactersIgnoringModifiers:character,isARepeat:repeatKey,keyCode:6) else {
                throw UIAuditError("Could not create a PDF keyboard fixture")
            }
            return event
        }
        let undo=try key("z",modifiers:.command)
        let redo=try key("Z",modifiers:[.command,.shift])
        try check(EditorKeyboardCommand.decode(undo) == .undo,"Command-Z decodes as PDF undo")
        try check(EditorKeyboardCommand.decode(redo) == .redo,"Shift-Command-Z decodes as PDF redo")
        let plain=try key("z",modifiers:[]),option=try key("z",modifiers:[.command,.option])
        try check(EditorKeyboardCommand.decode(plain) == nil && EditorKeyboardCommand.decode(option) == nil,
                  "Unassigned Z shortcuts retain normal responder handling")

        let button=NSButton(title:"Rotate",target:nil,action:nil)
        let text=NSTextView();text.isEditable=true
        let field=NSTextField(string:"Draft name"),secure=NSSecureTextField()
        let slider=NSSlider(),popup=NSPopUpButton()
        let nestedFieldView=NSView();field.addSubview(nestedFieldView)
        for (command,event) in [(EditorKeyboardCommand.undo,undo),(.redo,redo)] {
            var performed=0
            for responder in [text,field,secure,slider,popup,nestedFieldView] as [NSView] {
                let result=command.route(event,responder:responder,historyEnabled:true) { _ in performed+=1;return true }
                try check(result === event,"\(command) preserves native input for \(type(of:responder))")
            }
            try check(performed == 0,"\(command) never edits PDF history while a native input control owns focus")
            let buttonResult=command.route(event,responder:button,historyEnabled:true) { value in
                performed+=1;return value == command
            }
            try check(buttonResult == nil && performed == 1,"\(command) follows a focused page-edit button")
            performed=0
            let unhandled=command.route(event,responder:button,historyEnabled:true) { _ in performed+=1;return false }
            try check(unhandled === event && performed == 1,"An editor that declines \(command) preserves the event")
            for responder in [nil,button,text] as [NSResponder?] {
                performed=0
                let result=command.route(event,responder:responder,historyEnabled:false) { _ in performed+=1;return true }
                try check(result === event && performed == 0,"\(command) stays inactive outside the PDF organizer")
            }
            let repeating=try key(command == .undo ? "z":"Z",modifiers:command == .undo ? .command:[.command,.shift],repeatKey:true)
            performed=0
            let repeatResult=command.route(repeating,responder:button,historyEnabled:true) { _ in performed+=1;return true }
            try check(repeatResult == nil && performed == 0,"Holding \(command) does not drain PDF history")
            let unrelatedRepeat=command.route(repeating,responder:button,historyEnabled:false) { _ in performed+=1;return true }
            try check(unrelatedRepeat === repeating && performed == 0,"PDF key repeats remain untouched in other editors")
        }

        // Button focus is an exception only for PDF history; Space and arrows
        // must continue to operate native buttons rather than media playback.
        var performed=false
        let space=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,
            windowNumber:0,context:nil,characters:" ",charactersIgnoringModifiers:" ",isARepeat:false,keyCode:49)!
        let normal=EditorKeyboardCommand.togglePlayback.route(space,responder:button,historyEnabled:true) { _ in performed=true;return true }
        try check(normal === space && !performed,"Other editor shortcuts preserve focused buttons")

        let original=PDFDocument();original.insert(PDFPage(),at:0)
        var editor=PDFPageEditorState();editor.reset(document:original);editor.select(0);editor.rotateSelected()
        let undoResult=EditorKeyboardCommand.undo.route(undo,responder:button,historyEnabled:true) { _ in editor.undo();return true }
        try check(undoResult == nil && editor.pages[0].rotation == 0 && editor.canRedo,
                  "A focused Rotate button can undo its page edit through the production router")
        let redoResult=EditorKeyboardCommand.redo.route(redo,responder:button,historyEnabled:true) { _ in editor.redo();return true }
        try check(redoResult == nil && editor.pages[0].rotation == 90 && !editor.canRedo && original.page(at:0)?.rotation == 0,
                  "PDF redo restores the edit while leaving the source document unchanged")
        return checks
    }
    static func menuChecks()async throws->[String] {
        var checks:[String]=[]
        func check(_ condition:Bool,_ message:String)throws {
            guard condition else { throw UIAuditError("PDF menu check failed: "+message) }
            checks.append(message)
        }
        let previous=NSApp.keyWindow
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:240,height:140),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let fixture=PDFMenuFixtureModel()
        let content=NSHostingView(rootView:AnyView(PDFMenuFixtureView(model:fixture)))
        window.contentView=content
        defer {content.rootView=AnyView(EmptyView());window.close();previous?.makeKeyAndOrderFront(nil)}
        window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        func waitFor(_ condition:()->Bool)async throws {
            let deadline=Date().addingTimeInterval(2)
            while !condition() && Date()<deadline {
                content.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds:20_000_000)
            }
        }
        func responderChain()->[NSResponder] {
            var result:[NSResponder]=[],seen=Set<ObjectIdentifier>()
            var candidate:NSResponder?=window.firstResponder ?? content
            while let current=candidate,seen.insert(ObjectIdentifier(current)).inserted {
                result.append(current);candidate=current.nextResponder
            }
            return result
        }
        func installedHistory()->EditorHistoryResponder? { responderChain().compactMap{$0 as? EditorHistoryResponder}.first }
        try await waitFor { NSApp.isActive && window.isKeyWindow }
        try check(window.makeFirstResponder(content),"The production SwiftUI hosting view can own editor focus")
        try await waitFor { installedHistory() != nil }
        guard let history=installedHistory() else {
            throw UIAuditError("The production SwiftUI shortcut attachment did not install PDF history; chain="+responderChain().map{String(describing:type(of:$0))}.joined(separator:" → "))
        }
        try check(history.owner === window && history.enabled,"The production shortcut representable installs an enabled PDF responder in its own hosting window")
        let undo=NSMenuItem(title:"Undo",action:Selector(("undo:")),keyEquivalent:"z")
        let redo=NSMenuItem(title:"Redo",action:Selector(("redo:")),keyEquivalent:"Z")
        let edit=NSMenu(title:"Edit");edit.addItem(undo);edit.addItem(redo);edit.update()
        try check(!undo.isEnabled && !redo.isEnabled,"The actual native Edit menu starts disabled before a hosted PDF edit")
        fixture.rotate()
        try await waitFor { history.canUndo && !history.canRedo }
        try check(history.canUndo && !history.canRedo,"A SwiftUI page edit updates history through the production shortcut representable")
        let target=NSApp.target(forAction:undo.action!,to:nil,from:undo) as AnyObject?
        try check(target === history,"Edit Undo resolves past the production SwiftUI hosting view to PDF history (target=\(String(describing:target)), chain=\(responderChain().map{String(describing:type(of:$0))}.joined(separator:" → ")))")
        edit.update()
        try check(undo.isEnabled && !redo.isEnabled,"The actual native Edit menu enables Undo after rotating a hosted PDF page")
        try check(NSApp.sendAction(undo.action!,to:nil,from:undo) && fixture.editor.pages[0].rotation == 0 && fixture.editor.canRedo,
                  "Native Edit Undo restores the PDF from the production hosting responder chain")
        try await waitFor { !history.canUndo && history.canRedo }
        edit.update()
        try check(!undo.isEnabled && redo.isEnabled,"Native Edit menu validation follows the hosted SwiftUI state after undo")
        try check(NSApp.sendAction(redo.action!,to:nil,from:redo) && fixture.editor.pages[0].rotation == 90 && !fixture.editor.canRedo,
                  "Native Edit Redo reapplies the PDF page rotation")
        try await waitFor { history.canUndo && !history.canRedo }
        let field=NSTextView(frame:NSRect(x:0,y:0,width:180,height:30));field.isEditable=true;field.allowsUndo=true
        content.addSubview(field);window.makeFirstResponder(field)
        field.insertText("Draft",replacementRange:NSRange(location:0,length:0))
        try check(!history.validateMenuItem(undo),"Native text input does not enable PDF history menu actions")
        let fieldTarget=NSApp.target(forAction:undo.action!,to:nil,from:undo) as AnyObject?
        try check(fieldTarget !== history && NSApp.sendAction(undo.action!,to:nil,from:undo) && field.string.isEmpty && fixture.editor.pages[0].rotation == 90,
                  "Edit Undo retains text-field undo without changing PDF pages")
        field.removeFromSuperview();window.makeFirstResponder(content);fixture.enabled=false
        try await waitFor { !history.enabled }
        try check(!history.responds(to:undo.action!),"Inactive or other-tool editors do not claim native PDF Undo")
        content.rootView=AnyView(EmptyView())
        try await waitFor { history.owner == nil }
        try check(history.owner == nil && !responderChain().contains(where:{$0 === history}),"Dismantling the production SwiftUI shortcut attachment removes its PDF responder")
        return checks
    }
}

@MainActor private final class PDFMenuFixtureModel:ObservableObject {
    @Published var editor=PDFPageEditorState()
    @Published var enabled=true
    init() {
        let document=PDFDocument();document.insert(PDFPage(),at:0)
        editor.reset(document:document);editor.select(0)
    }
    func rotate() { editor.rotateSelected() }
    func perform(_ command:EditorKeyboardCommand)->Bool {
        if command == .undo {editor.undo()} else if command == .redo {editor.redo()} else {return false}
        return true
    }
}

private struct PDFMenuFixtureView:View {
    @ObservedObject var model:PDFMenuFixtureModel
    var body:some View {
        VStack(spacing:8) {
            Button("Rotate",action:model.rotate)
            HStack {
                Button("Undo") { _=model.perform(.undo) }.disabled(!model.editor.canUndo)
                Button("Redo") { _=model.perform(.redo) }.disabled(!model.editor.canRedo)
            }
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        .background(EditorKeyboardShortcuts(enabled:model.enabled,historyEnabled:true,
            canUndo:model.editor.canUndo,canRedo:model.editor.canRedo,onCommand:model.perform))
    }
}
