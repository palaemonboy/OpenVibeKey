import Foundation
import UserNotifications

/// Local notifications only; keep the delegate alive for foreground presentation.
final class ProfileNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ProfileNotifications()

    func configure() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        guard Bundle.main.bundleIdentifier != nil else { completion(false); return }
        configure()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            completion(granted)
        }
    }

    func post(_ message: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Open VibeKey"
        content.body = message
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "profile-switch", content: content, trigger: nil)) { error in
            if let error { NSLog("Profile notification: %@", error.localizedDescription) }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
