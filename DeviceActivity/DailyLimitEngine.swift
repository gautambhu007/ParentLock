//
//  DailyLimitEngine.swift
//  ParentLock
//
//  Daily per-app time limits using DeviceActivityEvent thresholds.
//  The monitor extension shields the app when the threshold is reached;
//  DeviceActivity resets usage automatically at the start of each interval
//  (midnight → midnight).
//

import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings
import Observation

@MainActor
@Observable
final class DailyLimitEngine {
    private let center = DeviceActivityCenter()
    private let selectionStore: SelectionStore
    private(set) var lastError: String?

    init(selectionStore: SelectionStore) {
        self.selectionStore = selectionStore
    }

    /// Start (or restart) monitoring a daily limit.
    /// The interval covers the whole day; the event fires at the minute threshold.
    func activate(_ limit: AppLimit) {
        guard let selection = selectionStore.limitSelections[limit.id] else {
            lastError = "No apps selected for this limit."
            return
        }
        let daySchedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: limit.minutesPerDay)
        )
        do {
            try center.startMonitoring(
                .dailyLimit(limit.id),
                during: daySchedule,
                events: [.limitReached: event]
            )
            lastError = nil
        } catch {
            lastError = "Could not start limit: \(error.localizedDescription)"
        }
    }

    func deactivate(_ limit: AppLimit) {
        center.stopMonitoring([.dailyLimit(limit.id)])
    }
}
