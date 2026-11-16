import AppKit
import SwiftUI
import TwisterCore

/// Receives the Services menu entries declared in Info.plist. Each selector is
/// the NSMessage of its entry followed by userData and error.
@MainActor final class FinderServicesProvider:NSObject {
    private let presets:PresetCenter
    private let perform:(FinderServiceRequest)->Void
    private let report:(String)->Void
    init(presets:PresetCenter,perform:@escaping(FinderServiceRequest)->Void,report:@escaping(String)->Void) { self.presets=presets;self.perform=perform;self.report=report }

    @objc func openInTwister(_ pasteboard:NSPasteboard,userData:String?,error:AutoreleasingUnsafeMutablePointer<NSString>) { handle(.open,pasteboard,error) }
    @objc func convertWithTwister(_ pasteboard:NSPasteboard,userData:String?,error:AutoreleasingUnsafeMutablePointer<NSString>) { handle(.convert,pasteboard,error) }
    @objc func runTwisterPreset(_ pasteboard:NSPasteboard,userData:String?,error:AutoreleasingUnsafeMutablePointer<NSString>) { handle(.preset,pasteboard,error) }

    private func handle(_ service:FinderService,_ pasteboard:NSPasteboard,_ error:AutoreleasingUnsafeMutablePointer<NSString>) {
        // twister-cli may have changed the presets since the app last looked.
        if service == .preset { presets.reload() }
        do { perform(try FinderServiceRequest(service,pasteboard:pasteboard,presets:presets.presets)) }
        catch let failure {
            let message=L10n.text(failure.localizedDescription)
            error.pointee=message as NSString;report(message)
        }
    }
}

/// The presets that fit the files a service sent. Running one closes the picker.
struct PresetPickerView:View {
    @ObservedObject var state:AppState
    let inputs:[URL]
    let onDone:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            VStack(alignment:.leading,spacing:4) {
                LText("Run a preset").font(.system(size:17,weight:.semibold))
                Group { if inputs.count==1 { Text(verbatim:inputs[0].lastPathComponent) } else { LText("\(inputs.count) files") } }
                    .font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            ScrollView { PresetListView(state:state,inputs:inputs) { _ in onDone() } }
            HStack { Spacer();Button { onDone() } label:{ LText("Cancel") }.buttonStyle(TwisterButtonStyle(.secondary)).keyboardShortcut(.cancelAction) }
        }.padding(20).frame(minWidth:380,minHeight:260).background(TwisterPalette.canvas).tint(.twister)
    }
}

extension AppDelegate {
    func installFinderServices() {
        let provider=FinderServicesProvider(presets:state.presets,perform:{ [weak self] in self?.perform($0) },report:{ message in
            let alert=NSAlert();alert.messageText="Twister";alert.informativeText=message
            alert.addButton(withTitle:L10n.text("OK"));NSApp.activate(ignoringOtherApps:true);alert.runModal()
        })
        finderServices=provider;NSApp.servicesProvider=provider
    }
    func perform(_ request:FinderServiceRequest) {
        switch request.service {
        case .open:state.inputs=request.files;showHome()
        case .convert:
            state.inputs=request.files;showHome()
            wheel.show(inputs:request.files,mode:.convert,at:NSEvent.mouseLocation,keyboard:true)
        case .preset:
            presetPicker?.close()
            let window=makeWindow(title:"Run Twister Preset",size:NSSize(width:440,height:360),view:PresetPickerView(state:state,inputs:request.files) { [weak self] in self?.presetPicker?.close();self?.presetPicker=nil })
            window.contentMinSize=NSSize(width:380,height:260)
            presetPicker=window;NativeWindowBehavior.present(window)
        }
    }
}
