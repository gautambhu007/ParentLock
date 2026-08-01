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
    nonisolated(unsafe) static let manual   = Self("manualBlocks")
    nonisolated(unsafe) static let schedule = Self("schedule")
    nonisolated(unsafe) static let bedtime  = Self("bedtime")
    nonisolated(unsafe) static let limits   = Self("dailyLimits")
    nonisolated(unsafe) static let remote   = Self("remoteControl")
}

@MainActor
@Observable
final class ShieldManager {
    private let selectionStore: SelectionStore
    private let lockGroupStore: LockGroupStore

    private let manualStore   = ManagedSettingsStore(named: .manual)
    private let scheduleStore = ManagedSettingsStore(named: .schedule)
    private let bedtimeStore  = ManagedSettingsStore(named: .bedtime)
    private let limitsStore   = ManagedSettingsStore(named: .limits)
    private let remoteStore   = ManagedSettingsStore(named: .remote)

    /// Expiry of an active emergency / temporary unlock, if any.
    private(set) var temporaryUnlockExpiry: Date?
    private var restoreTask: Task<Void, Never>?

    /// What the parent device has asked this device to lock. Persisted so a
    /// relaunch or reboot re-asserts the same shields.
    private(set) var remoteLockState: RemoteLockState

    init(selectionStore: SelectionStore, lockGroupStore: LockGroupStore) {
        self.selectionStore = selectionStore
        self.lockGroupStore = lockGroupStore
        temporaryUnlockExpiry = SharedStorage.loadCodable(Date.self, for: .temporaryUnlockExpiry)
        remoteLockState = SharedStorage.loadCodable(RemoteLockState.self, for: .remoteLockState) ?? .none
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

    /// Re-assert the persistent manual shield. Call on launch and every
    /// foreground so a block is never silently missing — unless a
    /// temporary unlock is currently in effect.
    func reassertPersistentShields() {
        if let expiry = temporaryUnlockExpiry, expiry > .now {
            return   // parent granted a temporary all-clear; leave it be
        }
        applyManualBlocks()
        applyRemoteLockState()
    }

    // MARK: - Remote control (child device)

    /// Lock or release everything the parent can reach, except the
    /// always-allowed apps. Applied on top of — never instead of — the local
    /// blocks, so a remote unlock can't undo what the parent set up on device.
    func setRemoteAllLocked(_ locked: Bool) {
        remoteLockState.isAllLocked = locked
        if !locked { remoteLockState.lockedGroupIDs.removeAll() }
        persistAndApplyRemoteState()
    }

    func setRemoteGroup(_ id: UUID, locked: Bool) {
        if locked {
            remoteLockState.lockedGroupIDs.insert(id)
        } else {
            remoteLockState.lockedGroupIDs.remove(id)
        }
        persistAndApplyRemoteState()
    }

    func clearRemoteLocks() {
        remoteLockState = .none
        persistAndApplyRemoteState()
    }

    private func persistAndApplyRemoteState() {
        SharedStorage.saveCodable(remoteLockState, for: .remoteLockState)
        applyRemoteLockState()
    }

    /// Translate `remoteLockState` into the remote store's shield.
    private func applyRemoteLockState() {
        if let expiry = temporaryUnlockExpiry, expiry > .now {
            return   // an emergency unlock outranks remote locks until it expires
        }
        guard !remoteLockState.isEmpty else {
            remoteStore.clearAllSettings()
            return
        }

        if remoteLockState.isAllLocked {
            // `.all(except:)` covers every app on the device, including ones
            // installed after the command was sent.
            remoteStore.shield.applicationCategories =
                .all(except: selectionStore.allowedSelection.applicationTokens)
            remoteStore.shield.webDomainCategories = .all()
            remoteStore.shield.applications = nil
            return
        }

        let selections = remoteLockState.lockedGroupIDs.map { lockGroupStore.selection(for: $0) }
        let apps = selections.reduce(into: Set<ApplicationToken>()) { $0.formUnion($1.applicationTokens) }
        let categories = selections.reduce(into: Set<ActivityCategoryToken>()) { $0.formUnion($1.categoryTokens) }
        let domains = selections.reduce(into: Set<WebDomainToken>()) { $0.formUnion($1.webDomainTokens) }

        remoteStore.shield.webDomainCategories = nil
        remoteStore.shield.applications = apps.isEmpty ? nil : apps
        remoteStore.shield.applicationCategories = categories.isEmpty
            ? nil
            : .specific(categories, except: selectionStore.allowedSelection.applicationTokens)
        remoteStore.shield.webDomains = domains.isEmpty ? nil : domains
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
        // The remote lock is lifted too, but `remoteLockState` is kept so the
        // parent's locks come back when the unlock expires.
        remoteStore.clearAllSettings()

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
        applyRemoteLockState()
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
