//
//  RemoteControlCoordinator.swift
//  ParentLock
//
//  Orchestrates remote lock/unlock for whichever role this device plays.
//
//  Parent role: issues commands, mirrors the child's group list, and shows
//  what the child device actually reports back.
//  Child role: applies pending commands to the shields, acknowledges them,
//  and publishes a heartbeat + its group names.
//
//  Both roles refresh on launch, on foreground, on silent push, and on a slow
//  poll — so a missed push only ever costs latency, never correctness.
//

import Foundation
import SwiftUI
import Observation
import os

@MainActor
@Observable
final class RemoteControlCoordinator {
    // MARK: Published state

    private(set) var childStatus: ChildDeviceStatus?
    private(set) var commandHistory: [RemoteCommand] = []
    private(set) var isSyncing = false
    private(set) var lastSyncedAt: Date?
    private(set) var isCloudAvailable = true
    var errorMessage: String?

    /// Set while a parent-issued command is in flight, so the UI can show
    /// which button is working without disabling the whole screen.
    private(set) var inFlightCommand: RemoteCommandKind?

    // MARK: Dependencies

    private let pairing: RemotePairingStore
    private let lockGroups: LockGroupStore
    private let shieldManager: ShieldManager
    private let notifications: NotificationManager
    private let channel: CloudCommandChannel
    private let logger = Logger(subsystem: "com.gautam.parentlock", category: "remote")

    /// Safety net for a dropped push. Long enough to be near-free on battery.
    private static let pollInterval: Duration = .seconds(60)

    private var pollTask: Task<Void, Never>?
    private var appliedCommandIDs: Set<UUID>

    init(pairing: RemotePairingStore,
         lockGroups: LockGroupStore,
         shieldManager: ShieldManager,
         notifications: NotificationManager,
         channel: CloudCommandChannel = CloudCommandChannel()) {
        self.pairing = pairing
        self.lockGroups = lockGroups
        self.shieldManager = shieldManager
        self.notifications = notifications
        self.channel = channel
        self.appliedCommandIDs = Set(SharedStorage.loadCodable([UUID].self, for: .appliedCommandIDs) ?? [])
    }

    var role: DeviceRole { pairing.role }
    var isPaired: Bool { pairing.isPaired }
    var pairingCode: String? { pairing.pairingCode }
    var pairedDeviceName: String? { pairing.pairedDeviceName }

    // MARK: - Lifecycle

    /// Call on launch and every foreground.
    func activate() async {
        guard pairing.isPaired else { return }
        isCloudAvailable = await channel.isAccountAvailable()
        guard isCloudAvailable else {
            errorMessage = RemoteControlError.iCloudUnavailable.errorDescription
            return
        }
        if let code = pairing.pairingCode {
            await channel.subscribe(code: code, role: pairing.role)
        }
        await sync()
        startPolling()
    }

    func deactivate() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Called from the silent push handler.
    func handleRemoteNotification() async {
        guard pairing.isPaired else { return }
        await sync()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { return }
                await self?.sync()
            }
        }
    }

    // MARK: - Pairing

    /// Parent side: mint a code and publish it for a child device to claim.
    func startPairingAsParent() async throws -> String {
        guard await channel.isAccountAvailable() else {
            isCloudAvailable = false
            throw RemoteControlError.iCloudUnavailable
        }
        isCloudAvailable = true
        let code = pairing.becomeParent()
        try await channel.createPairing(code: code, parentDeviceName: Self.deviceName)
        await channel.subscribe(code: code, role: .parent)
        startPolling()
        return code
    }

    /// Child side: claim the code shown on the parent device.
    func pairAsChild(code input: String) async throws {
        guard await channel.isAccountAvailable() else {
            isCloudAvailable = false
            throw RemoteControlError.iCloudUnavailable
        }
        isCloudAvailable = true
        let code = PairingCode.normalize(input)
        guard PairingCode.isValid(code) else { throw RemoteControlError.invalidCode }

        let parentName = try await channel.claimPairing(code: code, childDeviceName: Self.deviceName)
        try pairing.becomeChild(code: code)
        pairing.rememberPairedDevice(named: parentName)

        await channel.subscribe(code: code, role: .child)
        try await channel.publishGroups(lockGroups.groups, code: code)
        await sync()
        startPolling()
    }

    /// Unpair this device only. A child device dropping the pairing does not
    /// release its shields — those stay until a parent clears them on device.
    func unpair() async {
        if let code = pairing.pairingCode {
            await channel.unsubscribeAll(code: code)
        }
        deactivate()
        pairing.unpair()
        childStatus = nil
        commandHistory = []
    }

    // MARK: - Parent commands

    func lockAllApps() async {
        await send(RemoteCommand(kind: .lockAll))
    }

    /// `durationMinutes == nil` unlocks until the parent locks again.
    func unlockAllApps(durationMinutes: Int? = nil) async {
        await send(RemoteCommand(kind: .unlockAll, durationMinutes: durationMinutes))
    }

    func lock(group: RemoteLockGroup) async {
        await send(RemoteCommand(kind: .lockGroup, groupID: group.id))
    }

    func unlock(group: RemoteLockGroup) async {
        await send(RemoteCommand(kind: .unlockGroup, groupID: group.id))
    }

    /// True when the child last reported this group as shielded.
    func isGroupLocked(_ group: RemoteLockGroup) -> Bool {
        guard let childStatus else { return false }
        return childStatus.isAllLocked || childStatus.lockedGroupIDs.contains(group.id)
    }

    var isEverythingLocked: Bool { childStatus?.isAllLocked ?? false }

    private func send(_ command: RemoteCommand) async {
        guard pairing.role == .parent else {
            errorMessage = RemoteControlError.wrongRole.errorDescription
            return
        }
        guard let code = pairing.pairingCode else {
            errorMessage = RemoteControlError.notPaired.errorDescription
            return
        }
        inFlightCommand = command.kind
        defer { inFlightCommand = nil }
        do {
            try await channel.send(command, code: code)
            errorMessage = nil
            // Show it as pending immediately rather than waiting for the sync.
            commandHistory.append(command)
            await sync()
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Failed to send command: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Sync

    func sync() async {
        guard let code = pairing.pairingCode, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            switch pairing.role {
            case .parent:   try await syncAsParent(code: code)
            case .child:    try await syncAsChild(code: code)
            case .unpaired: return
            }
            lastSyncedAt = .now
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Remote sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func syncAsParent(code: String) async throws {
        let previouslyPending = Set(commandHistory.filter { $0.status == .pending }.map(\.id))

        async let remoteGroups = channel.groups(code: code)
        async let remoteStatus = channel.status(code: code)
        async let remoteCommands = channel.commands(code: code)
        let (groups, status, commands) = try await (remoteGroups, remoteStatus, remoteCommands)

        lockGroups.replaceGroups(with: groups)
        childStatus = status
        commandHistory = commands

        if let name = try? await channel.pairedChildName(code: code) {
            pairing.rememberPairedDevice(named: name)
        }

        // Tell the parent when something they sent actually landed.
        for command in commands where previouslyPending.contains(command.id) {
            switch command.status {
            case .applied:
                notifications.notify(.remoteCommandApplied(
                    action: command.summary(groupName: command.groupID.flatMap { lockGroups.name(for: $0) })))
            case .failed:
                notifications.notify(.remoteCommandFailed(
                    action: command.summary(groupName: command.groupID.flatMap { lockGroups.name(for: $0) }),
                    reason: command.failureReason ?? String(localized: "Unknown error")))
            case .pending:
                break
            }
        }
    }

    private func syncAsChild(code: String) async throws {
        let commands = try await channel.commands(code: code)
        let pending = commands
            .filter { $0.status == .pending && !appliedCommandIDs.contains($0.id) }
            .sorted { $0.issuedAt < $1.issuedAt }

        var results: [RemoteCommand] = []
        for command in pending {
            var result = command
            do {
                try apply(command)
                result.status = .applied
                result.appliedAt = .now
            } catch {
                result.status = .failed
                result.failureReason = error.localizedDescription
            }
            appliedCommandIDs.insert(command.id)
            results.append(result)
        }

        if !results.isEmpty {
            persistAppliedIDs()
            try await channel.acknowledge(results, code: code)
        }

        try await channel.publishGroups(lockGroups.groups, code: code)
        try await channel.publishStatus(currentStatus, code: code)
        commandHistory = commands
    }

    /// Push the child's group list up so the parent's buttons stay in sync
    /// right after the groups are edited.
    func publishGroups() async {
        guard pairing.role == .child, let code = pairing.pairingCode else { return }
        do {
            try await channel.publishGroups(lockGroups.groups, code: code)
            try await channel.publishStatus(currentStatus, code: code)
        } catch {
            logger.error("Failed to publish groups: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ command: RemoteCommand) throws {
        switch command.kind {
        case .lockAll:
            shieldManager.setRemoteAllLocked(true)
        case .unlockAll:
            shieldManager.clearRemoteLocks()
            if let minutes = command.durationMinutes {
                // A timed unlock reuses the emergency-unlock machinery, which
                // already restores every shield when the timer runs out.
                shieldManager.temporarilyUnlockAll(for: TimeInterval(minutes * 60))
            }
        case .lockGroup:
            guard let id = command.groupID, lockGroups.group(id: id) != nil else {
                throw RemoteApplyError.unknownGroup
            }
            guard !lockGroups.selection(for: id).applicationTokens.isEmpty
                    || !lockGroups.selection(for: id).categoryTokens.isEmpty else {
                throw RemoteApplyError.emptyGroup
            }
            shieldManager.setRemoteAllLocked(false)
            shieldManager.setRemoteGroup(id, locked: true)
        case .unlockGroup:
            guard let id = command.groupID else { throw RemoteApplyError.unknownGroup }
            shieldManager.setRemoteGroup(id, locked: false)
        }
    }

    private var currentStatus: ChildDeviceStatus {
        let state = shieldManager.remoteLockState
        return ChildDeviceStatus(
            deviceName: Self.deviceName,
            lastSeen: .now,
            isAllLocked: state.isAllLocked,
            lockedGroupIDs: Array(state.lockedGroupIDs),
            temporaryUnlockExpiry: shieldManager.temporaryUnlockExpiry
        )
    }

    private func persistAppliedIDs() {
        // Bounded so the App Group entry can't grow without limit.
        let trimmed = Array(appliedCommandIDs.suffix(200))
        appliedCommandIDs = Set(trimmed)
        SharedStorage.saveCodable(trimmed, for: .appliedCommandIDs)
    }

    private static var deviceName: String {
        UIDevice.current.name
    }
}

enum RemoteApplyError: LocalizedError {
    case unknownGroup
    case emptyGroup

    var errorDescription: String? {
        switch self {
        case .unknownGroup:
            String(localized: "That app group no longer exists on this device.")
        case .emptyGroup:
            String(localized: "That app group has no apps chosen on this device yet.")
        }
    }
}
