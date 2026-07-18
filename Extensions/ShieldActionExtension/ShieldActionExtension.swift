//
//  ShieldActionExtension.swift
//  ShieldActionExtension target
//
//  Handles taps on the shield buttons.
//
//  Extensions cannot present Face ID UI themselves, so both actions record a
//  pending request in the shared App Group and notify the parent. The parent
//  then authenticates *in the main app* to grant time — this is the
//  Apple-sanctioned pattern for parent approval flows.
//

import ManagedSettings
import UserNotifications

struct PendingTimeRequest: Codable {
    let requestedAt: Date
    let source: String
}

final class ShieldActionExtension: ShieldActionDelegate {

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleCommon(action: action, source: "app", completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleCommon(action: action, source: "web", completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction,
                         for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleCommon(action: action, source: "category", completionHandler: completionHandler)
    }

    private func handleCommon(action: ShieldAction,
                              source: String,
                              completionHandler: @escaping (ShieldActionResponse) -> Void) {
        let defaults = UserDefaults(suiteName: "group.com.yourteam.parentlock")

        // Count blocked attempts for reports.
        let attempts = defaults?.integer(forKey: "blockedAttemptCount") ?? 0
        defaults?.set(attempts + 1, forKey: "blockedAttemptCount")

        switch action {
        case .primaryButtonPressed: // "Request More Time"
            let request = PendingTimeRequest(requestedAt: .now, source: source)
            if let data = try? JSONEncoder().encode(request) {
                defaults?.set(data, forKey: "pendingTimeRequest")
            }
            notifyParent(body: String(localized: "Your child is requesting more screen time."))
            completionHandler(.defer) // Keep the shield up; parent approves in the app.

        case .secondaryButtonPressed: // "Parent Unlock"
            notifyParent(body: String(localized: "Open ParentLock and use Face ID to unlock."))
            completionHandler(.close) // Close the blocked app; parent unlocks from the app.

        @unknown default:
            completionHandler(.none)
        }
    }

    private func notifyParent(body: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "ParentLock")
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
