import AppKit
import SwiftUI
import TwisterCore

@MainActor struct ToolSetupView: View {
    @StateObject private var model: ToolSetupModel
    let onDone: () -> Void
    @State private var removal: ToolGroup?
    init(model: ToolSetupModel, onDone: @escaping () -> Void = {}) {
        _model = StateObject(wrappedValue: model); self.onDone = onDone
    }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TwisterPageHeading(eyebrow: "FIRST-TIME SETUP", title: "A few tools. More possibilities.", subtitle: "One download per tool group. No account or GitHub token.")
                    group(.media, "Media tools", symbol: "film",
                          detail: "FFmpeg and ffprobe enable media conversion and previews. About a 45 MB download; 105 MB installed. FFmpeg uses a GPL license.",
                          button: "Download media tools", id: "SetupMedia")
                    group(.office, "Office tools", symbol: "doc.text",
                          detail: "LibreOffice 26.8.1 enables Office document conversions. A 285 MB download; about 1 GB installed. MPL 2.0 and its included third-party licenses.",
                          button: "Download office tools", id: "SetupOffice")
                    if AppFeatures.webDownloads {
                        group(.web, "Web download tools", symbol: "arrow.down.to.line",
                              detail: "Optional. yt-dlp and Deno download media from public links; conversions do not need them. About a 75 MB download; 120 MB installed. yt-dlp uses a GPL license; Deno uses MIT.",
                              button: "Install web download tools", id: "SetupWeb")
                    }
                    Link("Upstream versions, licenses and source links", destination: URL(string: "https://github.com/baypeanut/twister/blob/main/docs/dependencies.md")!).font(.callout)
                }.padding(28)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                LText(model.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("SetupStatus")
                if model.working {
                    if let value = model.fraction { ProgressView(value: value) }
                    else { ProgressView().controlSize(.small) }
                }
                HStack {
                    if model.working {
                        Button("Cancel setup", action: model.cancel).accessibilityIdentifier("SetupCancel").keyboardShortcut(.cancelAction)
                    }
                    Spacer()
                    Button(model.status.ready ? "Continue to Twister" : "Download missing tools") {
                        if model.status.ready { onDone() } else { model.install() }
                    }.buttonStyle(TwisterButtonStyle(.primary)).disabled(model.working)
                        .accessibilityIdentifier("SetupContinue").keyboardShortcut(.defaultAction)
                }
            }.padding(24)
        }.frame(minWidth: 590, minHeight: 560).background(TwisterPalette.canvas).tint(.twister).buttonStyle(TwisterButtonStyle())
            .onAppear { model.refresh() }
            .confirmationDialog("Remove these tools?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
                Button("Remove", role: .destructive) { if let removal { model.remove(removal) }; removal = nil }
                Button("Cancel", role: .cancel) { removal = nil }
            } message: { Text("Only the copy Twister downloaded is deleted. Tools from Homebrew or another location stay where they are.") }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }
    private func group(_ kind: ToolGroup, _ title: String, symbol: String, detail: String, button: String, id: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label(LocalizedStringKey(title), systemImage: symbol).font(.headline)
                LText(detail).font(.callout).foregroundStyle(.secondary)
                if model.status.isReady(kind) {
                    Label(LocalizedStringKey(source(kind)), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(TwisterPalette.forest).accessibilityIdentifier(id + "Ready")
                } else {
                    Button { model.install(kind) } label: { LText(button) }.disabled(model.working).accessibilityIdentifier(id)
                }
                if model.reports[kind]?.removable == true {
                    HStack {
                        Text(verbatim: installed(kind)).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove") { removal = kind }.disabled(model.working).accessibilityIdentifier(id + "Remove")
                    }
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func source(_ kind: ToolGroup) -> String {
        switch model.reports[kind]?.source {
        case .installed: return "Installed by Twister"
        case .bundled: return "Included with this copy of Twister"
        case .override: return "Set by a TWISTER_ environment override"
        case .system: return "Found on your computer"
        case nil: return "Already available on your computer"
        }
    }
    /// Version and size of the copy that setup downloaded.
    private func installed(_ kind: ToolGroup) -> String {
        var parts = [(ExternalToolSetup.root.path as NSString).abbreviatingWithTildeInPath]
        if let version = model.reports[kind]?.version { parts.insert(version, at: 0) }
        if let bytes = model.sizes[kind] { parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
        return parts.joined(separator: " · ")
    }
}
extension Notification.Name {
    static let showToolSetup = Notification.Name("TwisterShowToolSetup")
    static let toolSetupChanged = Notification.Name("TwisterToolSetupChanged")
}
