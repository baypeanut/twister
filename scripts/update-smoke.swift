// Test-only application. Never compiled into Twister or shipped in a release.
import AppKit
import Sparkle

@MainActor final class UpdateSmoke: NSObject, NSApplicationDelegate, SPUUserDriver, SPUUpdaterDelegate {
    var updater: SPUUpdater!
    let root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "SmokeRoot") as! String)
    func record(_ value: String) { try! Data(value.utf8).write(to: root.appendingPathComponent("result.txt"), options: .atomic) }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2" {
            record("installed-and-relaunched")
            NSApp.terminate(nil)
            return
        }
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        do {
            try updater.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.updater.checkForUpdates() }
        } catch { fail(error) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 100) { self.record("timeout"); NSApp.terminate(nil) }
    }
    func fail(_ error: Error) { record("rejected: \(error)"); NSApp.terminate(nil) }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { fail(error) }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { fail(error) }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { fail(error) }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
}
let application = NSApplication.shared
let delegate = UpdateSmoke()
application.setActivationPolicy(.prohibited)
application.delegate = delegate
application.run()
