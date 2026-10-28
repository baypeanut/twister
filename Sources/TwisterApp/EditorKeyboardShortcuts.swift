import AppKit
import SwiftUI

enum EditorKeyboardCommand: Equatable {
    case togglePlayback, nudge(direction: Int, fine: Bool), beginning, end
    case playRange, markIn, markOut, addMarker, save, confirmCrop, undo, redo

    static func decode(_ event: NSEvent) -> Self? {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        // Turkish I/ı/İ should invoke the same marked-in shortcut as Latin I/i.
        let key = event.charactersIgnoringModifiers?
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().replacingOccurrences(of: "ı", with: "i")
        let command: Self?
        if modifiers == .command, key == "s" { command = .save }
        else if modifiers == .command, key == "z" { command = .undo }
        else if modifiers == [.command, .shift], key == "z" { command = .redo }
        else if modifiers.isEmpty || modifiers == .shift {
            switch event.keyCode {
            case 36 where modifiers.isEmpty,76 where modifiers.isEmpty: command = .confirmCrop
            case 49: command = modifiers == .shift ? .playRange : .togglePlayback
            case 123: command = .nudge(direction: -1, fine: modifiers == .shift)
            case 124: command = .nudge(direction: 1, fine: modifiers == .shift)
            case 115 where modifiers.isEmpty: command = .beginning
            case 119 where modifiers.isEmpty: command = .end
            default:
                command = key == "i" ? .markIn : key == "o" ? .markOut : key == "m" ? .addMarker : nil
            }
        } else { command = nil }
        return command
    }

    var acceptsRepeat: Bool { if case .nudge = self { return true }; return false }
    var isHistory: Bool { self == .undo || self == .redo }

    func route(_ event: NSEvent, responder: NSResponder?, historyEnabled: Bool = false,
               perform: (Self) -> Bool) -> NSEvent? {
        guard !isHistory || historyEnabled else { return event }
        guard !Self.preservesControlInput(responder, allowingButtons: isHistory) else { return event }
        if event.isARepeat, !acceptsRepeat { return nil }
        return perform(self) ? nil : event
    }

    static func preservesControlInput(_ responder: NSResponder?, allowingButtons: Bool = false) -> Bool {
        // Field editors, secure fields, sliders, pop-up controls and focused native
        // buttons keep their usual text/caret/arrow/Space behavior. History can
        // follow a Rotate/Delete button without taking a text field's native undo.
        if let text = responder as? NSTextView, text.isEditable { return true }
        var view = responder as? NSView
        while let current = view {
            if current is NSControl, !(allowingButtons && current is NSButton && !(current is NSPopUpButton)) { return true }
            view = current.superview
        }
        return false
    }

    static func seekTarget(current: Double, duration: Double, direction: Int,
                           fine: Bool, video: Bool, frameRate: Double) -> Double {
        let step = fine ? (video ? 1 / max(1, frameRate) : 0.1) : 1
        return min(max(0, duration), max(0, current + Double(direction) * step))
    }
}

/// A local monitor belongs to one editor window and is removed with its host view.
/// It neither installs a global hotkey nor asks for input-monitoring permission.
struct EditorKeyboardShortcuts: NSViewRepresentable {
    let enabled: Bool
    let historyEnabled: Bool
    let canUndo: Bool
    let canRedo: Bool
    let onCommand: (EditorKeyboardCommand) -> Bool

    final class MonitorView: NSView {
        var enabled = false
        var historyEnabled = false
        var onCommand: ((EditorKeyboardCommand) -> Bool)?
        private var monitor: Any?
        private let historyResponder=EditorHistoryResponder()
        func updateHistory(canUndo:Bool,canRedo:Bool) {
            historyResponder.enabled=enabled && historyEnabled
            historyResponder.canUndo=canUndo;historyResponder.canRedo=canRedo
            historyResponder.onCommand=onCommand
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            historyResponder.attach(to:window)
            DispatchQueue.main.async { [weak self,weak window] in
                guard let self,let window,self.window === window else {return}
                self.historyResponder.attach(to:window)
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }
        func handle(_ event: NSEvent) -> NSEvent? {
            guard enabled, let window, window.isKeyWindow, NSApp.isActive,
                  event.window === window, window.attachedSheet == nil,
                  NSApp.modalWindow == nil,
                  !(window.childWindows ?? []).contains(where: { $0.isVisible }),
                  let command = EditorKeyboardCommand.decode(event) else { return event }
            if command == .save {
                if event.isARepeat { return nil }
                // Commit a numeric/text field before saving, just like clicking Save.
                guard window.makeFirstResponder(nil) else { return event }
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, self.enabled, let window, self.window === window,
                          window.isKeyWindow, window.attachedSheet == nil else { return }
                    _ = self.onCommand?(.save)
                }
                return nil
            }
            return command.route(event, responder: window.firstResponder,
                                 historyEnabled: historyEnabled) { onCommand?($0) == true }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil;historyResponder.detach() }
        deinit { stop() }
    }
    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.setAccessibilityElement(false)
        view.enabled = enabled; view.historyEnabled = historyEnabled; view.onCommand = onCommand
        view.updateHistory(canUndo:canUndo,canRedo:canRedo)
        return view
    }
    func updateNSView(_ view: MonitorView, context: Context) {
        view.enabled = enabled; view.historyEnabled = historyEnabled; view.onCommand = onCommand
        view.updateHistory(canUndo:canUndo,canRedo:canRedo)
    }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop(); view.onCommand = nil }
}
