//
//  DeviceActivityMonitorExtension.swift
//  DeviceActivityMonitorExtension target
//
//  Runs in the background even when the app is closed (and after device
//  restart). Applies shields when schedule/bedtime intervals start, clears
//  them when intervals end, and shields limited apps when their daily
//  threshold is reached.
//

import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation
import UserNotifications

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let appGroup = "group.com.gautam.parentlock"

    private lazy var scheduleStore = ManagedSettingsStore(named: .init("schedule"))
    private lazy var bedtimeStore  = ManagedSettingsStore(named: .init("bedtime"))
    private lazy var limitsStore   = ManagedSettingsStore(named: .init("dailyLimits"))

    // MARK: - Interval lifecycle

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        if activity.rawValue == "bedtime" {
            applyBedtime()
            notify(title: String(localized: "Bedtime started"),
                   body: String(localized: "Apps are resting until morning. Sweet dreams!"))
        } else if activity.rawValue.hasPrefix("schedule-"),
                  let id = uuid(from: activity.rawValue, prefix: "schedule-") {
            applySchedule(id: id)
        }
        // Daily-limit intervals starting at midnight need no shield —
        // usage resets automatically with the new interval.
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        if activity.rawValue == "bedtime" {
            bedtimeStore.clearAllSettings()
        } else if activity.rawValue.hasPrefix("schedule-") {
            scheduleStore.clearAllSettings()
        } else if activity.rawValue.hasPrefix("limit-") {
            // New day: clear yesterday's limit shields.
            limitsStore.clearAllSettings()
        }
    }

    // MARK: - Daily limit threshold

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                         activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        guard event.rawValue == "limitReached",
              let id = uuid(from: activity.rawValue, prefix: "limit-"),
              let selection = limitSelection(for: id) else { return }

        // Shield only the apps belonging to this limit (additive union).
        let existing = limitsStore.shield.applications ?? []
        limitsStore.shield.applications = existing.union(selection.applicationTokens)
        if !selection.categoryTokens.isEmpty {
            limitsStore.shield.applicationCategories = .specific(selection.categoryTokens)
        }

        notify(title: String(localized: "Daily limit reached"),
               body: String(localized: "An app has reached its time limit for today."))
    }

    // MARK: - Helpers

    private func applyBedtime() {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: "bedtimeSelection"),
              let exceptions = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            bedtimeStore.shield.applicationCategories = .all()
            return
        }
        bedtimeStore.shield.applicationCategories = .all(except: exceptions.applicationTokens)
    }

    private func applySchedule(id: UUID) {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: "scheduleSelection-\(id.uuidString)"),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return }
        scheduleStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        if !selection.categoryTokens.isEmpty {
            scheduleStore.shield.applicationCategories = .specific(selection.categoryTokens)
        }
    }

    private func limitSelection(for id: UUID) -> FamilyActivitySelection? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: "limitSelections"),
              let map = try? JSONDecoder().decode([UUID: FamilyActivitySelection].self, from: data) else { return nil }
        return map[id]
    }

    private func uuid(from raw: String, prefix: String) -> UUID? {
        UUID(uuidString: String(raw.dropFirst(prefix.count)))
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
