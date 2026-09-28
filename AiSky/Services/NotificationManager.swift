import AiSkyKit
import Foundation
import UserNotifications

enum NotificationManager {
    /// Asks for permission; returns whether notifications are allowed.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func post(_ notification: PlannedNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = notification.threadID
        if let deepLink = notification.deepLink {
            content.userInfo = ["url": deepLink]
        }
        let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// Shows alerts while the app is open and routes taps to the matching forecast.
@MainActor
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    var onOpenURL: ((URL) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let link = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: link) else { return }
        onOpenURL?(url)
    }
}
