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
                VStack(alignment: .leading, spacing: 16) {
                    Text("One download per tool group. No account or GitHub token.").foregroundStyle(.secondary)
                    group(.media, "Media tools",
                          detail: "FFmpeg and ffprobe enable media conversion and previews. About a 45 MB download; 105 MB installed. FFmpeg uses a GPL license.",
                          button: "Download Media Tools", id: "SetupMedia")
                    group(.office, "Office tools",
                          detail: "LibreOffice 26.8.1 enables Office document conversions. A 285 MB download; about 1 GB installed. MPL 2.0 and its included third-party licenses.",
                          button: "Download Office Tools", id: "SetupOffice")
                    if AppFeatures.webDownloads {
                        group(.web, "Web download tools",
                              detail: "Optional. yt-dlp and Deno download media from public links; conversions do not need them. About a 75 MB download; 120 MB installed. yt-dlp uses a GPL license; Deno uses MIT.",
                              button: "Install Web Download Tools", id: "SetupWeb")
                    }
                    Link("Upstream versions, licenses and source links", destination: URL(string: "https://github.com/baypeanut/twister/blob/main/docs/dependencies.md")!).font(.callout)
                }.padding(20)
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
                        Button("Cancel Setup", action: model.cancel).accessibilityIdentifier("SetupCancel").keyboardShortcut(.cancelAction)
                    }
                    Spacer()
                    Button {
                        if model.status.ready { onDone() } else { model.install() }
                    } label: { LText(model.status.ready ? "Continue" : "Download Missing Tools") }.disabled(model.working)
                        .accessibilityIdentifier("SetupContinue").keyboardShortcut(.defaultAction)
                }
            }.padding(.horizontal, 20).padding(.vertical, 16)
        }.frame(minWidth: 590, minHeight: 560).background(Color(nsColor:.windowBackgroundColor))
            .onAppear { model.refresh() }
            .confirmationDialog("Remove these tools?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
                Button("Remove", role: .destructive) { if let removal { model.remove(removal) }; removal = nil }
                Button("Cancel", role: .cancel) { removal = nil }
            } message: { Text("Only the copy Twister downloaded is deleted. Tools from Homebrew or another location stay where they are.") }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }
    private func group(_ kind: ToolGroup, _ title: String, detail: String, button: String, id: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedStringKey(title)).font(.headline)
                LText(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.status.isReady(kind) {
                    Label { Text(LocalizedStringKey(source(kind))) } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        .accessibilityIdentifier(id + "Ready")
                } else {
                    Button { model.install(kind) } label: { LText(button) }.disabled(model.working).accessibilityIdentifier(id)
                }
                if model.reports[kind]?.removable == true {
                    HStack {
                        Text(verbatim: installed(kind)).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove") { removal = kind }.disabled(model.working).accessibilityIdentifier(id + "Remove")
                    }
                }
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
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
