import AppKit
import UserNotifications
import TwisterCore

/// Tells the user that a task ended while Twister was out of sight.
/// Permission is requested the first time there is something to say. A denied
/// request, or a copy macOS cannot deliver for, stays silent.
enum JobNotifier {
    static let preferenceKey="jobNotifications"
    static var enabled:Bool { UserDefaults.standard.object(forKey:preferenceKey) as? Bool ?? true }
    /// The notification centre raises an exception in a process without an app bundle.
    static var available:Bool { Bundle.main.bundleURL.pathExtension=="app" && Bundle.main.bundleIdentifier != nil }

    static func post(title:String,report:BatchReport) {
        guard enabled,available else { return }
        let heading=L10n.text(title),body=L10n.text(report.summary)
        UNUserNotificationCenter.current().requestAuthorization(options:[.alert]) { granted,_ in
            guard granted else { return }
            let content=UNMutableNotificationContent()
            content.title=heading;content.body=body
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:UUID().uuidString,content:content,trigger:nil))
        }
    }
}
