//
//  ShieldManager.swift
//  ParentLock
//
//  Applies and clears ManagedSettings shields. Uses *named* stores so each
//  feature (manual blocks, schedules, bedtime, limits, rewards) can be
//  enabled/cleared independently without stepping on the others.
//

import Foundation
import ManagedSettings
import FamilyControls
import Observation

extension ManagedSettingsStore.Name {
    static let manual   = Self("manualBlocks")
    static let schedule = Self("schedule")
    static let bedtime  = Self("bedtime")
    static let limits   = Self("dailyLimits")
}

@MainActor
@Observable
final class ShieldManager {
    private let selectionStore: SelectionStore

    private let manualStore   = ManagedSettingsStore(named: .manual)
    private let scheduleStore = ManagedSettingsStore(named: .schedule)
    private let bedtimeStore  = ManagedSettingsStore(named: .bedtime)
    private let limitsStore   = ManagedSettingsStore(named: .limits)

    /// Expiry of an active emergency / temporary unlock, if any.
    private(set) var temporaryUnlockExpiry: Date?
    private var restoreTask: Task<Void, Never>?

    init(selectionStore: SelectionStore) {
        self.selectionStore = selectionStore
        temporaryUnlockExpiry = SharedStorage.loadCodable(Date.self, for: .temporaryUnlockExpiry)
        scheduleRestoreIfNeeded()
    }

    // MARK: - Manual blocks

    /// Apply the parent's blocked-apps selection as a persistent shield.
    func applyManualBlocks() {
        let selection = selectionStore.blockedSelection
        manualStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        manualStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens, except: selectionStore.allowedSelection.applicationTokens)
        manualStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    func clearManualBlocks() {
        manualStore.clearAllSettings()
    }

    // MARK: - Schedule shields (called by DeviceActivityMonitor extension too)

    func applyScheduleShield(_ selection: FamilyActivitySelection, allowed: FamilyActivitySelection) {
        scheduleStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        scheduleStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens, except: allowed.applicationTokens)
    }

    func clearScheduleShield() {
        scheduleStore.clearAllSettings()
    }

    // MARK: - Bedtime

    /// Bedtime blocks everything except the parent-chosen exceptions
    /// (Messages, Clock, emergency apps, …).
    func applyBedtimeShield() {
        bedtimeStore.shield.applicationCategories =
            .all(except: selectionStore.bedtimeExceptions.applicationTokens)
    }

    func clearBedtimeShield() {
        bedtimeStore.clearAllSettings()
    }

    // MARK: - Emergency / temporary unlock

    /// Remove all shields for a fixed duration, then restore automatically.
    /// Caller must have already passed Face ID.
    func temporarilyUnlockAll(for duration: TimeInterval) {
        manualStore.clearAllSettings()
        scheduleStore.clearAllSettings()
        bedtimeStore.clearAllSettings()
        limitsStore.clearAllSettings()

        let expiry = Date.now.addingTimeInterval(duration)
        temporaryUnlockExpiry = expiry
        SharedStorage.saveCodable(expiry, for: .temporaryUnlockExpiry)
        scheduleRestoreIfNeeded()
    }

    /// Cancel a temporary unlock early and restore all shields.
    func endTemporaryUnlock() {
        restoreTask?.cancel()
        restoreTask = nil
        temporaryUnlockExpiry = nil
        SharedStorage.remove(.temporaryUnlockExpiry)
        applyManualBlocks()
        // Schedule + limit shields are restored by their DeviceActivity intervals.
    }

    private func scheduleRestoreIfNeeded() {
        guard let expiry = temporaryUnlockExpiry else { return }
        guard expiry > .now else { endTemporaryUnlock(); return }
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(expiry.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.endTemporaryUnlock()
        }
    }
}
