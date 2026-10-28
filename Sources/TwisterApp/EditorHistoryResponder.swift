import AppKit

/// Joins only its own editor's responder chain. Native field undo gets the
/// first opportunity; editor history is available from Edit as well as ⌘Z.
@MainActor final class EditorHistoryResponder:NSResponder,NSMenuItemValidation {
    weak private(set) var owner:NSWindow?
    private weak var anchor:NSResponder?
    var enabled=false
    var canUndo=false
    var canRedo=false
    var onCommand:((EditorKeyboardCommand)->Bool)?
    private static let undoAction=Selector(("undo:")),redoAction=Selector(("redo:"))

    func attach(to window:NSWindow) {
        guard let content=window.contentView else { return }
        guard owner !== window || anchor !== content else { return }
        detach();owner=window;anchor=content;nextResponder=content.nextResponder;content.nextResponder=self
    }
    func detach() {
        if anchor?.nextResponder === self { anchor?.nextResponder=nextResponder }
        owner=nil;anchor=nil;nextResponder=nil
    }
    private var canHandle:Bool {
        guard enabled,let owner,owner.isKeyWindow,NSApp.isActive,
              owner.attachedSheet == nil,NSApp.modalWindow == nil,
              !(owner.childWindows ?? []).contains(where:{$0.isVisible}) else { return false }
        return !EditorKeyboardCommand.preservesControlInput(owner.firstResponder,allowingButtons:true)
    }
    override func responds(to selector:Selector!)->Bool {
        if selector == Self.undoAction || selector == Self.redoAction { return canHandle }
        return super.responds(to:selector)
    }
    @objc func undo(_ sender:Any?) { if canHandle && canUndo { _=onCommand?(.undo) } }
    @objc func redo(_ sender:Any?) { if canHandle && canRedo { _=onCommand?(.redo) } }
    func validateMenuItem(_ item:NSMenuItem)->Bool {
        guard canHandle else { return false }
        if item.action == Self.undoAction { return canUndo }
        if item.action == Self.redoAction { return canRedo }
        return false
    }
}
