import Foundation
import UserNotifications

/// Real macOS notifications for the moments that need you even when the notch is out of sight:
/// an action waiting for your OK (with Allow and Deny right in the notification), and a
/// background task that finished.
@MainActor
final class SpeekNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SpeekNotifications()
    static let approvalID = "speek.approval"
    private let center = UNUserNotificationCenter.current()

    func start() {
        center.delegate = self
        let allow = UNNotificationAction(identifier: "allow", title: "Allow", options: [])
        let deny = UNNotificationAction(identifier: "deny", title: "Deny", options: [.destructive])
        let show = UNNotificationAction(identifier: "show", title: "Show", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "approval", actions: [allow, deny], intentIdentifiers: []),
            UNNotificationCategory(identifier: "done", actions: [show], intentIdentifiers: [])
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func approvalNeeded(_ title: String, detail: String?) {
        post(id: Self.approvalID, title: "Speek needs your OK", body: title + (detail.map { "\n" + $0 } ?? ""), category: "approval", info: [:])
    }

    func approvalResolved() {
        center.removeDeliveredNotifications(withIdentifiers: [Self.approvalID])
        center.removePendingNotificationRequests(withIdentifiers: [Self.approvalID])
    }

    func taskFinished(_ notice: BackgroundTaskNotice) {
        let title = (notice.succeeded ? "Done: " : "Couldn't finish: ") + String(notice.request.prefix(60))
        post(id: "speek.task." + notice.id.uuidString, title: title, body: String(notice.result.prefix(220)), category: "done",
             info: ["notice": notice.id.uuidString])
    }

    private func post(id: String, title: String, body: String, category: String, info: [String: String]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = info
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // Shown even while Speek is the active app (the notch counts as Speek).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let noticeID = response.notification.request.content.userInfo["notice"] as? String
        await MainActor.run {
            let controller = AssistantController.shared
            switch (category, action) {
            case ("approval", "allow"): controller.runProposal()
            case ("approval", "deny"): controller.cancelProposal()
            case ("approval", _): controller.presentApproval()
            default:
                if let noticeID, let notice = controller.taskNotices.first(where: { $0.id.uuidString == noticeID }) {
                    controller.openTaskNotice(notice)
                }
            }
        }
    }
}
