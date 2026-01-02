import Foundation
import UserNotifications

enum NotificationManager {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    static func showError(bee: Bee, error: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(bee.displayName) Failed"
        content.body = error.prefix(100).description
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "bee-error-\(bee.id)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to show notification: \(error.localizedDescription)")
            }
        }
    }

    static func showSuccess(bee: Bee, duration: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "\(bee.displayName) Completed"
        content.body = String(format: "Finished in %.1fs", duration)

        let request = UNNotificationRequest(
            identifier: "bee-success-\(bee.id)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
