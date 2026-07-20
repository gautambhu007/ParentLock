//
//  ScheduleEngine.swift
//  ParentLock
//
//  Registers DeviceActivitySchedules for parent-created schedules and bedtime.
//  The DeviceActivityMonitor extension receives intervalDidStart/End callbacks
//  and applies/clears the shields even when this app isn't running.
//

import Foundation
import DeviceActivity
import FamilyControls
import Observation

extension DeviceActivityName {
    nonisolated(unsafe) static let bedtime = Self("bedtime")
    static func schedule(_ id: UUID) -> Self { Self("schedule-\(id.uuidString)") }
    static func dailyLimit(_ id: UUID) -> Self { Self("limit-\(id.uuidString)") }
}

extension DeviceActivityEvent.Name {
    nonisolated(unsafe) static let limitReached = Self("limitReached")
}

@MainActor
@Observable
final class ScheduleEngine {
    private let center = DeviceActivityCenter()
    private let shieldManager: ShieldManager
    private(set) var lastError: String?

    init(shieldManager: ShieldManager) {
        self.shieldManager = shieldManager
    }

    /// Start monitoring a parent-created schedule (e.g. Homework 5–7 PM).
    func activate(_ schedule: BlockSchedule) {
        let activitySchedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: schedule.startHour, minute: schedule.startMinute),
            intervalEnd: DateComponents(hour: schedule.endHour, minute: schedule.endMinute),
            repeats: true
        )
        do {
            try center.startMonitoring(.schedule(schedule.id), during: activitySchedule)
            // Persist this schedule's selection so the monitor extension can shield it.
            SharedStorage.saveCodable(schedule.blockedSelection, forScheduleID: schedule.id)
            lastError = nil
        } catch {
            lastError = "Could not start schedule: \(error.localizedDescription)"
        }
    }

    func deactivate(_ schedule: BlockSchedule) {
        center.stopMonitoring([.schedule(schedule.id)])
        SharedStorage.removeScheduleSelection(for: schedule.id)
    }

    /// Bedtime spans midnight (e.g. 21:00 → 07:00) — DeviceActivity handles this.
    func activateBedtime(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: startHour, minute: startMinute),
            intervalEnd: DateComponents(hour: endHour, minute: endMinute),
            repeats: true
        )
        do {
            try center.startMonitoring(.bedtime, during: schedule)
            lastError = nil
        } catch {
            lastError = "Could not start bedtime: \(error.localizedDescription)"
        }
    }

    func deactivateBedtime() {
        center.stopMonitoring([.bedtime])
        shieldManager.clearBedtimeShield()
    }

    func deactivateAll() {
        center.stopMonitoring()
    }
}

// MARK: - Per-schedule selection persistence for the extension

extension SharedStorage {
    static func saveCodable(_ selection: FamilyActivitySelection, forScheduleID id: UUID) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: "scheduleSelection-\(id.uuidString)")
    }

    static func scheduleSelection(for id: UUID) -> FamilyActivitySelection? {
        guard let data = defaults.data(forKey: "scheduleSelection-\(id.uuidString)") else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    static func removeScheduleSelection(for id: UUID) {
        defaults.removeObject(forKey: "scheduleSelection-\(id.uuidString)")
    }
}
