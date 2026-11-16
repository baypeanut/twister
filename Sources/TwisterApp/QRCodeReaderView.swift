import SwiftUI
import AppKit
import TwisterCore

@MainActor final class QRCodeReaderModel:ObservableObject {
    @Published var report=QRCodeScanReport()
    @Published var busy=false
    @Published var progress=0.0
    @Published var label=""
    @Published var password=""
    @Published var copied:Set<UUID>=[]
    @Published var copiedAll=false
    @Published var error:String?
    let inputs:[URL]
    let onSuccess:(SuccessNotice)->Void
    var token=CancellationToken()
    init(inputs:[URL],onSuccess:@escaping(SuccessNotice)->Void) { self.inputs=inputs;self.onSuccess=onSuccess }
    func scan() {
        guard !busy else { return }
        busy=true;progress=0;error=nil;copied=[];copiedAll=false;report=QRCodeScanReport();token=CancellationToken()
        let source=inputs,password=password,cancel=token,model=self
        Task {
            do {
                report=try await Task.detached(priority:.userInitiated) {
                    try QRCodeEngine.scan(source,password:password,token:cancel) { amount,message in Task { @MainActor in model.progress=amount;model.label=message } }
                }.value
                if report.errors.isEmpty { onSuccess(SuccessNotice(title:"Scan complete.",detail:"\(report.results.count) QR code\(report.results.count == 1 ? "":"s") found.")) }
            } catch { self.error=error.localizedDescription }
            busy=false
        }
    }
    func copy(_ result:QRCodeMatch) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(result.text,forType:.string) { copied.insert(result.id);onSuccess(SuccessNotice(title:"QR code copied.",detail:"Ready to paste.")) }
        else { error="Could not copy the QR code." }
    }
    func copyAll() {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(report.results.map(\.text).joined(separator:"\n"),forType:.string) { copiedAll=true;onSuccess(SuccessNotice(title:"QR codes copied.",detail:"\(report.results.count) ready to paste.")) }
        else { error="Could not copy the QR codes." }
    }
    func saveReport() {
        let panel=NSSavePanel();panel.nameFieldStringValue="QR Codes.json";panel.allowedContentTypes=[.json]
        if panel.runModal() == .OK,let url=panel.url {
            do { let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];try encoder.encode(report).write(to:url,options:.atomic);onSuccess(.action("Report saved.",files:[url])) } catch { self.error=error.localizedDescription }
        }
    }
}

struct QRCodeReaderView:View {
    @StateObject private var model:QRCodeReaderModel
    @MainActor init(inputs:[URL],onSuccess:@escaping(SuccessNotice)->Void) { _model=StateObject(wrappedValue:QRCodeReaderModel(inputs:inputs,onSuccess:onSuccess)) }
    var body:some View {
        VStack(spacing:0) {
            WindowHeader(title:"Read QR Codes")
            if model.busy {
                HStack(spacing:10) { ProgressView().controlSize(.small);VStack(alignment:.leading,spacing:2) { Text("Scanning for QR codes…");Text(model.label).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) };Spacer();Button("Cancel") { model.token.cancel() } }.padding(.horizontal,16).padding(.vertical,10)
                Divider()
            }
            ScrollView {
                VStack(alignment:.leading,spacing:10) {
                    if model.report.results.isEmpty,!model.busy {
                        VStack(alignment:.leading,spacing:2) { Text("No QR codes found.");Text("Try a clearer image or another PDF.").font(.subheadline).foregroundStyle(.secondary) }
                    }
                    ForEach(model.report.results) { result in
                        VStack(alignment:.leading,spacing:8) {
                            HStack { Text(result.sourceName).lineLimit(1).truncationMode(.middle);if let page=result.page { Text("Page \(page)") };Spacer();Button { model.copy(result) } label:{ LText(model.copied.contains(result.id) ? "Copied":"Copy") }.controlSize(.small) }.font(.subheadline).foregroundStyle(.secondary)
                            Text(result.text).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)
                        }.padding(12).twisterGroup()
                    }
                    ForEach(model.report.errors,id:\.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
                    if let error=model.error { LText(error).font(.subheadline).foregroundStyle(.red) }
                }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
            }
            Divider()
            if model.inputs.contains(where:{FileCategory.detect($0) == .pdf}) { SecureField("PDF password (if needed)",text:$model.password).textFieldStyle(.roundedBorder).padding(.horizontal,16).padding(.top,12) }
            HStack { Button("Scan Again") { model.scan() }.disabled(model.busy);Text("\(model.report.results.count) found").font(.subheadline).foregroundStyle(.secondary);Spacer();Button("Save Report…") { model.saveReport() }.disabled(model.busy);Button { model.copyAll() } label:{ LText(model.copiedAll ? "Copied All":"Copy All") }.disabled(model.report.results.isEmpty).keyboardShortcut(.defaultAction) }.padding(.horizontal,16).padding(.vertical,12)
        }.frame(minWidth:530,minHeight:440).background(Color(nsColor:.windowBackgroundColor)).twisterAnimation(value:model.busy).twisterAnimation(value:model.copiedAll).onAppear { model.scan() }.onDisappear { model.token.cancel() }
    }
}
