import Foundation
import UserNotifications

/// Notification category identifiers
private let confirmCategoryId = "BEE_CONFIRM"
private let confirmActionId = "CONFIRM_ACTION"
private let rejectActionId = "REJECT_ACTION"

/// Handles macOS notifications including actionable confirmation requests
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()

    private override init() {
        super.init()
    }

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Request permission
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }

        // Register confirmation category with actions
        let confirmAction = UNNotificationAction(
            identifier: confirmActionId,
            title: "Confirm",
            options: [.foreground]
        )

        let rejectAction = UNNotificationAction(
            identifier: rejectActionId,
            title: "Reject",
            options: [.destructive]
        )

        let confirmCategory = UNNotificationCategory(
            identifier: confirmCategoryId,
            actions: [rejectAction, confirmAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([confirmCategory])
    }

    // MARK: - Show Notifications

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

        UNUserNotificationCenter.current().add(request)
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

    static func showConfirmation(id: String, beeId: String, beeName: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = beeName
        content.body = message
        content.sound = .default
        content.categoryIdentifier = confirmCategoryId
        content.userInfo = [
            "requestId": id,
            "beeId": beeId
        ]

        let request = UNNotificationRequest(
            identifier: "bee-confirm-\(id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to show confirmation: \(error.localizedDescription)")
                // If we can't show notification, auto-reject
                ConfirmServer.handleResponse(requestId: id, confirmed: false, reason: "notification failed")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        guard let requestId = userInfo["requestId"] as? String else {
            completionHandler()
            return
        }

        switch response.actionIdentifier {
        case confirmActionId:
            print("✅ User confirmed: \(requestId)")
            ConfirmServer.handleResponse(requestId: requestId, confirmed: true)

        case rejectActionId:
            print("❌ User rejected: \(requestId)")
            ConfirmServer.handleResponse(requestId: requestId, confirmed: false, reason: "rejected")

        case UNNotificationDismissActionIdentifier:
            print("👋 User dismissed: \(requestId)")
            ConfirmServer.handleResponse(requestId: requestId, confirmed: false, reason: "dismissed")

        default:
            // Default action (clicked notification body) - treat as needing more interaction
            // For MVP, treat as confirm since they engaged with it
            print("👆 User clicked: \(requestId)")
            ConfirmServer.handleResponse(requestId: requestId, confirmed: true)
        }

        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notifications even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
}
