//
//  RemoteControlView.swift
//  ParentLock
//
//  The parent's remote: lock everything, unlock everything, or toggle a
//  single named app group on the child's iPad. Every action is Face ID gated,
//  and the state shown is what the *child device reported back* — not what we
//  hoped would happen.
//

import SwiftUI

struct RemoteControlView: View {
    @Environment(RemoteControlCoordinator.self) private var remote
    @Environment(LockGroupStore.self) private var lockGroups
    @Environment(BiometricAuthManager.self) private var auth

    @State private var errorMessage: String?
    @State private var showUnpairConfirmation = false

    var body: some View {
        Group {
            switch remote.role {
            case .unpaired: DevicePairingView()
            case .parent:   parentControls
            case .child:    ChildDeviceStatusView()
            }
        }
        .navigationTitle("Remote Control")
    }

    // MARK: - Parent controls

    private var parentControls: some View {
        List {
            statusSection
            allAppsSection
            groupsSection

            if let message = errorMessage ?? remote.errorMessage {
                Section { Text(message).foregroundStyle(.red) }
            }

            historySection
            pairingSection
        }
        .refreshable { await remote.sync() }
        .confirmationDialog("Unpair this device?",
                            isPresented: $showUnpairConfirmation,
                            titleVisibility: .visible) {
            Button("Unpair", role: .destructive) {
                Task { await remote.unpair() }
            }
        } message: {
            Text("You'll stop being able to lock the child device remotely. Any shields already applied there stay in place.")
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusSection: some View {
        Section {
            if let status = remote.childStatus {
                LabeledContent {
                    Label(status.isOnline ? "Online" : "Offline",
                          systemImage: status.isOnline ? "checkmark.circle.fill" : "moon.zzz.fill")
                        .foregroundStyle(status.isOnline ? .green : .secondary)
                        .labelStyle(.titleAndIcon)
                } label: {
                    Text(status.deviceName)
                }
                LabeledContent("Last check-in",
                               value: status.lastSeen.formatted(date: .omitted, time: .shortened))
                LabeledContent("Apps") {
                    Text(status.isAllLocked
                         ? String(localized: "All locked")
                         : String(localized: "\(status.lockedGroupIDs.count) groups locked"))
                        .foregroundStyle(status.isAllLocked ? .red : .primary)
                }
                if let expiry = status.temporaryUnlockExpiry, expiry > .now {
                    LabeledContent("Temporary unlock until",
                                   value: expiry.formatted(date: .omitted, time: .shortened))
                }
            } else {
                Label("Waiting for the child device to pair…", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Child device")
                Spacer()
                if remote.isSyncing { ProgressView().controlSize(.mini) }
            }
        } footer: {
            if !remote.isCloudAvailable {
                Text(RemoteControlError.iCloudUnavailable.errorDescription ?? "")
            } else if remote.childStatus?.isOnline == false {
                Text("Commands are queued and apply as soon as the child's iPad is awake and online.")
            }
        }
    }

    // MARK: All apps

    private var allAppsSection: some View {
        Section {
            BigButton(title: "Lock All Apps", systemImage: "lock.fill") {
                send(reason: String(localized: "Lock all apps on the child device")) {
                    await remote.lockAllApps()
                }
            }
            .listRowBackground(Color.clear)
            .disabled(remote.inFlightCommand != nil)

            BigButton(title: "Unlock All Apps", systemImage: "lock.open.fill", role: .destructive) {
                send(reason: String(localized: "Unlock all apps on the child device")) {
                    await remote.unlockAllApps()
                }
            }
            .listRowBackground(Color.clear)
            .disabled(remote.inFlightCommand != nil)

            Menu {
                ForEach([15, 30, 60], id: \.self) { minutes in
                    Button("\(minutes) minutes") {
                        send(reason: String(localized: "Unlock all apps for \(minutes) minutes")) {
                            await remote.unlockAllApps(durationMinutes: minutes)
                        }
                    }
                }
            } label: {
                Label("Unlock for a set time…", systemImage: "clock.arrow.circlepath")
            }
        } header: {
            Text("Everything")
        } footer: {
            Text(remote.isEverythingLocked
                 ? String(localized: "Every app except the always-allowed ones is shielded right now.")
                 : String(localized: "“Lock All Apps” shields every app on the child's iPad except the ones you marked always-allowed."))
        }
    }

    // MARK: Groups

    @ViewBuilder
    private var groupsSection: some View {
        Section {
            if lockGroups.groups.isEmpty {
                Label("No app groups yet", systemImage: "square.grid.2x2")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(lockGroups.groups) { group in
                    let isLocked = remote.isGroupLocked(group)
                    Toggle(isOn: Binding(
                        get: { isLocked },
                        set: { shouldLock in toggle(group, lock: shouldLock) }
                    )) {
                        Label {
                            VStack(alignment: .leading) {
                                Text(group.name)
                                Text(isLocked
                                     ? String(localized: "Locked")
                                     : String(localized: "Available"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: group.symbol)
                                .foregroundStyle(isLocked ? .red : .green)
                        }
                    }
                    .disabled(remote.isEverythingLocked)
                }
            }
        } header: {
            Text("App groups")
        } footer: {
            if remote.isEverythingLocked {
                Text("Individual groups are unavailable while everything is locked. Unlock all apps first.")
            } else if lockGroups.groups.isEmpty {
                Text("Create groups like “Games” or “Social” on the child's iPad, in Remote Control → App Groups. Their names appear here once the device checks in.")
            } else {
                Text("Toggling a group locks or unlocks just those apps on the child's iPad.")
            }
        }
    }

    // MARK: History

    @ViewBuilder
    private var historySection: some View {
        let recent = remote.commandHistory.suffix(8).reversed()
        if !recent.isEmpty {
            Section("Recent commands") {
                ForEach(Array(recent)) { command in
                    LabeledContent {
                        statusBadge(for: command)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(command.summary(groupName: command.groupID.flatMap { lockGroups.name(for: $0) }))
                            Text(command.issuedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(for command: RemoteCommand) -> some View {
        switch command.status {
        case .pending:
            Label("Pending", systemImage: "clock")
                .foregroundStyle(.secondary)
        case .applied:
            Label("Applied", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label(command.failureReason ?? String(localized: "Failed"),
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: Pairing

    private var pairingSection: some View {
        Section("Pairing") {
            if let code = remote.pairingCode {
                LabeledContent("Code", value: PairingCode.formatted(code))
                    .textSelection(.enabled)
            }
            Button("Unpair This Device", role: .destructive) {
                showUnpairConfirmation = true
            }
        }
    }

    // MARK: Actions

    private func toggle(_ group: RemoteLockGroup, lock: Bool) {
        let reason = lock
            ? String(localized: "Lock “\(group.name)” on the child device")
            : String(localized: "Unlock “\(group.name)” on the child device")
        send(reason: reason) {
            if lock {
                await remote.lock(group: group)
            } else {
                await remote.unlock(group: group)
            }
        }
    }

    private func send(reason: String, _ work: @escaping () async -> Void) {
        Task {
            do {
                try await auth.authenticateForAction(reason: reason)
                errorMessage = nil
                await work()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
