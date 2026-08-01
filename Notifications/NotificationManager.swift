//
//  NotificationManager.swift
//  ParentLock
//
//  Local notifications for the parent: limit reached, blocked attempt,
//  reward expired, schedule started/ended. No remote push, no data leaves
//  the device.
//

import Foundation
import UserNotifications
import Observation

@MainActor
@Observable
final class NotificationManager {
    private(set) var isAuthorized = false

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            isAuthorized = false
        }
    }

    enum Event {
        case limitReached(app: String)
        case blockedAttempt(app: String)
        case rewardExpired(task: String)
        case scheduleStarted(name: String)
        case scheduleEnded(name: String)
        case remoteCommandApplied(action: String)
        case remoteCommandFailed(action: String, reason: String)

        var title: String {
            switch self {
            case .limitReached: String(localized: "Daily limit reached")
            case .blockedAttempt: String(localized: "Blocked app attempted")
            case .rewardExpired: String(localized: "Reward expired")
            case .scheduleStarted: String(localized: "Schedule started")
            case .scheduleEnded: String(localized: "Schedule ended")
            case .remoteCommandApplied: String(localized: "Applied on child device")
            case .remoteCommandFailed: String(localized: "Remote command failed")
            }
        }

        var body: String {
            switch self {
            case .limitReached(let app): String(localized: "\(app) has reached its daily time limit.")
            case .blockedAttempt(let app): String(localized: "Your child tried to open \(app).")
            case .rewardExpired(let task): String(localized: "The reward for “\(task)” has ended.")
            case .scheduleStarted(let name): String(localized: "“\(name)” is now active.")
            case .scheduleEnded(let name): String(localized: "“\(name)” has ended.")
            case .remoteCommandApplied(let action): String(localized: "\(action) — done.")
            case .remoteCommandFailed(let action, let reason): String(localized: "\(action) couldn't be applied: \(reason)")
            }
        }
    }

    func notify(_ event: Event) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }
}
