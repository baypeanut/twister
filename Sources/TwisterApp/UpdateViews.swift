import SwiftUI
import TwisterUpdates

extension Notification.Name {
    static let showUpdateSettings=Notification.Name("TwisterShowUpdateSettings")
    static let showUpdateConnection=Notification.Name("TwisterShowUpdateConnection")
}

struct UpdateBanner:View {
    @ObservedObject var updater:AppUpdater
    let version:String
    var body:some View {
        HStack(spacing:10) {
            Image(systemName:"arrow.down.circle.fill").font(.title2).foregroundStyle(Color.accentColor).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:2) {
                Text("An update is available.").font(.headline)
                LText(updater.waitingForCurrentTask ? "Your task will finish before Twister restarts.":"Version \(version) is ready to install.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength:12)
            Button("Update…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates || updater.isBusy || updater.waitingForCurrentTask)
        }.padding(12).twisterGroup()
        .accessibilityElement(children:.contain)
    }
}

struct UpdateSettingsView:View {
    @ObservedObject var updater:AppUpdater
    private var version:String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "Development" }
    private var build:String { Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "—" }
    private var setupMessage:String? {
        if let error=updater.configurationError { return error }
        if !updater.isConfigured { return "Automatic updates are disabled until this build has a trusted release feed and signing key." }
        return nil
    }

    var body:some View {
        Form {
            Section {
                LabeledContent {
                    Text(verbatim:"\(version) (\(build))").textSelection(.enabled)
                } label:{
                    Text("Version")
                    if updater.availableVersion != nil { Text("Update ready") }
                }
                if setupMessage == nil {
                    LabeledContent {
                        if let official=updater.officialRepository,updater.repository == nil { Link("View Releases",destination:official.websiteURL.appendingPathComponent("releases")) }
                        else { Button { NotificationCenter.default.post(name:.showUpdateConnection,object:nil) } label:{ LText(updater.repository == nil ? "Connect…":"Manage…") } }
                    } label:{
                        LText(updater.repository?.slug ?? updater.officialRepository?.slug ?? "GitHub release connection")
                        LText(updater.repository == nil ? (updater.officialRepository == nil ? "Connect a private or public updates repository.":"Official public releases · No account or token needed"):updater.requiresToken ? "Private repository · Token saved in Keychain":"Public repository · No token needed")
                    }
                }
            }
            if let error=setupMessage {
                Section {
                    LabeledContent { EmptyView() } label:{ Text("Automatic updates are disabled");LText(error) }
                }
            } else {
                Section {
                    Toggle(isOn:Binding(get:{updater.automaticallyChecksForUpdates},set:updater.setAutomaticChecks)) {
                        Text("Check for updates automatically")
                        Text("Twister checks once an hour while it’s running. You choose when to download and install.")
                    }
                    LabeledContent {
                        Button { updater.checkForUpdates() } label:{ LText(updater.availableVersion == nil ? "Check for Updates…":"Update…") }
                            .disabled(!updater.canCheckForUpdates || updater.isBusy || updater.waitingForCurrentTask)
                    } label:{
                        LText(statusTitle)
                        if let date=updater.lastCheckedAt { Text("Last checked \(date.formatted(date:.abbreviated,time:.shortened))") }
                        else { Text("No update checks yet") }
                    }
                    if updater.isBusy { Text("Your current task will finish before an update restarts the app.").font(.subheadline).foregroundStyle(.secondary) }
                    if let error=updater.lastError { Label { Text(error) } icon:{ Image(systemName:"exclamationmark.triangle.fill").symbolRenderingMode(.multicolor) }.font(.subheadline).textSelection(.enabled) }
                }
            }
            Section { } footer:{
                Text("Updates are verified before installation. Your settings and recent history stay with you.").frame(maxWidth:.infinity,alignment:.leading)
            }
        }.formStyle(.grouped).twisterAnimation(value:updater.availableVersion)
    }

    private var statusTitle:String {
        if updater.waitingForCurrentTask { return "Ready after your current task" }
        if let version=updater.availableVersion { return "Version \(version) is available" }
        if updater.sessionInProgress { return "Checking for updates…" }
        if updater.lastError != nil { return "The update could not be completed" }
        return "Ready to check for updates"
    }
}

struct UpdateConnectionView:View {
    @ObservedObject var updater:AppUpdater
    @State private var repository=""
    @State private var token=""
    @State private var privateRepository=true
    @State private var message:String?
    @State private var error:String?

    var body:some View {
        VStack(spacing:0) {
            Form {
                Section {
                    TextField("GitHub repository",text:$repository,prompt:Text("owner/repository or GitHub URL"))
                    Toggle("This repository is private",isOn:$privateRepository)
                    if privateRepository {
                        SecureField("Fine-grained access token",text:$token,prompt:Text(L10n.text(updater.hasSavedToken && repositoryMatches ? "Saved token · Leave blank to keep it":"Paste your GitHub token"))).privacySensitive()
                        if updater.hasSavedToken && repositoryMatches {
                            LabeledContent {
                                Button("Authorize Saved Token…") { token="";save() }
                            } label:{ Text("Use once if macOS needs permission for your saved update connection.").font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }
                } header:{
                    if let connected=updater.repository { Text("Connected to \(connected.slug)") }
                } footer:{
                    VStack(alignment:.leading,spacing:4) {
                        if privateRepository {
                            Text("Select only this repository and give Contents read access. The token stays in this Mac’s Keychain.")
                            Link("Create a fine-grained token on GitHub",destination:URL(string:"https://github.com/settings/personal-access-tokens/new")!)
                        } else { Text("Public updates work without a token.") }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }.disabled(!updater.canChangeConnection)
                if updater.isConfigured {
                    Section {
                        LabeledContent {
                            Button { updater.checkForUpdates() } label:{ LText(updater.availableVersion == nil ? "Check for Updates…":"Update…") }.disabled(!updater.canCheckForUpdates || updater.isBusy)
                        } label:{
                            LText(updater.isPreparingCheck ? "Checking releases…":"Software update")
                            if let checked=updater.lastCheckedAt { Text("Last checked \(checked.formatted(date:.abbreviated,time:.shortened))") }
                        }
                        Toggle("Check automatically while Twister is running",isOn:Binding(get:{updater.automaticallyChecksForUpdates},set:updater.setAutomaticChecks))
                        if let lastError=updater.lastError { Label { Text(lastError) } icon:{ Image(systemName:"exclamationmark.triangle.fill").symbolRenderingMode(.multicolor) }.font(.subheadline) }
                    }
                }
                Section { } footer:{
                    VStack(alignment:.leading,spacing:4) {
                        Text("Twister \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "Development") · Build \(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "—")")
                        Text("Updates are signed and verified before installation. Changing repositories keeps the same trusted signing key. Your settings and files stay with you.")
                        if let configurationError=updater.configurationError { Text(configurationError) }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
            }.formStyle(.grouped)
            Divider()
            VStack(alignment:.leading,spacing:8) {
                if let message { Label { Text(message) } icon:{ Image(systemName:"checkmark.circle.fill").foregroundStyle(.green) }.font(.subheadline).fixedSize(horizontal:false,vertical:true) }
                if let error { Label { Text(error) } icon:{ Image(systemName:"exclamationmark.triangle.fill").symbolRenderingMode(.multicolor) }.font(.subheadline).fixedSize(horizontal:false,vertical:true) }
                HStack(spacing:8) {
                    if updater.isConnecting { ProgressView().controlSize(.small);Text("Checking the connection…").font(.subheadline).foregroundStyle(.secondary) }
                    else if updater.repository != nil {
                        Button("Disconnect & Forget Token") { disconnect() }.disabled(!updater.canChangeConnection)
                    }
                    Spacer()
                    Button("Save Connection") { save() }.keyboardShortcut(.defaultAction)
                        .disabled(!updater.canChangeConnection || repository.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                }
            }.padding(.horizontal,20).padding(.vertical,12)
        }.frame(minWidth:530,minHeight:570).background(Color(nsColor:.windowBackgroundColor))
        .onAppear {
            repository=updater.repository?.slug ?? updater.officialRepository?.slug ?? Bundle.main.object(forInfoDictionaryKey:"TwisterSuggestedGitHubRepository") as? String ?? ""
            privateRepository=updater.requiresToken
        }
        .onDisappear { token="" }
    }

    private var repositoryMatches:Bool {
        (try? TwisterUpdates.GitHubRepository(repository)) == updater.repository && updater.repository != nil
    }

    private func save() {
        message=nil;error=nil
        Task { @MainActor in
            do {
                try await updater.connectGitHub(repository:repository,token:token,requiresToken:privateRepository)
                token=""
                repository=updater.repository?.slug ?? repository
                message=updater.isConfigured ? "Connection saved. Future checks use it automatically.":"Connection saved. This build still needs its release signing configuration."
            } catch { self.error=error.localizedDescription }
        }
    }

    private func disconnect() {
        Task { @MainActor in
            do {
                try await updater.disconnectGitHub()
                token="";message="Connection removed and its saved token deleted.";error=nil
            } catch { self.error=error.localizedDescription;message=nil }
        }
    }
}
