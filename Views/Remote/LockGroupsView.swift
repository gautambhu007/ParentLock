//
//  LockGroupsView.swift
//  ParentLock
//
//  Child-device screens for remote control:
//  • ChildDeviceStatusView — what the parent currently has locked here.
//  • LockGroupsView — name the groups and pick which apps go in each.
//
//  Apps are picked here because ApplicationTokens are device-scoped: only the
//  device that ran the FamilyActivityPicker can shield the apps it returned.
//

import SwiftUI
import FamilyControls

// MARK: - Child status

struct ChildDeviceStatusView: View {
    @Environment(RemoteControlCoordinator.self) private var remote
    @Environment(LockGroupStore.self) private var lockGroups
    @Environment(ShieldManager.self) private var shieldManager
    @Environment(BiometricAuthManager.self) private var auth

    @State private var showUnpairConfirmation = false
    @State private var errorMessage: String?

    private var state: RemoteLockState { shieldManager.remoteLockState }

    var body: some View {
        List {
            Section {
                LabeledContent("Managed by", value: remote.pairedDeviceName ?? String(localized: "Parent device"))
                LabeledContent("Apps") {
                    if state.isAllLocked {
                        Label("All locked", systemImage: "lock.fill").foregroundStyle(.red)
                    } else if state.lockedGroupIDs.isEmpty {
                        Label("Nothing locked remotely", systemImage: "lock.open").foregroundStyle(.green)
                    } else {
                        Text("\(state.lockedGroupIDs.count) groups locked")
                    }
                }
                if let synced = remote.lastSyncedAt {
                    LabeledContent("Last check-in",
                                   value: synced.formatted(date: .omitted, time: .shortened))
                }
            } header: {
                Text("This device")
            } footer: {
                Text("This iPad applies locks sent from the parent device. Remote locks sit on top of the blocks set up here — unlocking remotely never removes them.")
            }

            if !state.lockedGroupIDs.isEmpty && !state.isAllLocked {
                Section("Locked right now") {
                    ForEach(Array(state.lockedGroupIDs), id: \.self) { id in
                        Label(lockGroups.name(for: id) ?? String(localized: "Removed group"),
                              systemImage: "lock.fill")
                    }
                }
            }

            Section {
                NavigationLink {
                    LockGroupsView()
                } label: {
                    Label("App Groups", systemImage: "square.grid.2x2.fill")
                }
            } footer: {
                Text("Set up the groups the parent device can lock, like “Games” or “Social”.")
            }

            if let message = errorMessage ?? remote.errorMessage {
                Section { Text(message).foregroundStyle(.red) }
            }

            Section("Pairing") {
                if let code = remote.pairingCode {
                    LabeledContent("Code", value: PairingCode.formatted(code))
                }
                Button("Unpair This Device", role: .destructive) {
                    showUnpairConfirmation = true
                }
            }
        }
        .refreshable { await remote.sync() }
        .confirmationDialog("Unpair this device?",
                            isPresented: $showUnpairConfirmation,
                            titleVisibility: .visible) {
            Button("Unpair", role: .destructive) { unpair() }
        } message: {
            Text("The parent device will no longer be able to lock this iPad. Shields already applied stay in place.")
        }
    }

    private func unpair() {
        Task {
            do {
                // Face ID here is the point: it stops the child from quietly
                // cutting the parent's remote off.
                try await auth.authenticateForAction(reason: "Unpair this device from the parent")
                await remote.unpair()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Group management

struct LockGroupsView: View {
    @Environment(LockGroupStore.self) private var lockGroups
    @Environment(RemoteControlCoordinator.self) private var remote
    @Environment(BiometricAuthManager.self) private var auth

    @State private var editingGroup: RemoteLockGroup?
    @State private var newGroupName = ""
    @State private var showNewGroupPrompt = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(lockGroups.groups) { group in
                    Button {
                        editingGroup = group
                    } label: {
                        LabeledContent {
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name).foregroundStyle(.primary)
                                    Text(lockGroups.summary(for: group.id))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: group.symbol)
                            }
                        }
                    }
                }
                .onDelete(perform: delete)
            } header: {
                Text("Groups")
            } footer: {
                Text("An empty group can't be locked — the parent device gets a clear error instead of a silent no-op.")
            }

            Section {
                Button {
                    newGroupName = ""
                    showNewGroupPrompt = true
                } label: {
                    Label("Add Group", systemImage: "plus.circle.fill")
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("App Groups")
        .toolbar { EditButton() }
        .sheet(item: $editingGroup) { group in
            LockGroupEditor(group: group)
        }
        .alert("New group", isPresented: $showNewGroupPrompt) {
            TextField("Name", text: $newGroupName)
            Button("Cancel", role: .cancel) {}
            Button("Add") { addGroup() }
        } message: {
            Text("Give it a name your co-parent will recognise, like “Games”.")
        }
        .onChange(of: lockGroups.groups) { _, _ in
            Task { await remote.publishGroups() }
        }
    }

    private func addGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let group = lockGroups.addGroup(named: name)
        editingGroup = group
    }

    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { lockGroups.groups[$0].id }
        Task {
            do {
                try await auth.authenticateForAction(reason: "Delete an app group")
                for id in ids { lockGroups.delete(id) }
                await remote.publishGroups()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Group editor

private struct LockGroupEditor: View {
    let group: RemoteLockGroup

    @Environment(LockGroupStore.self) private var lockGroups
    @Environment(RemoteControlCoordinator.self) private var remote
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false

    private let symbols = ["square.grid.2x2.fill", "gamecontroller.fill", "bubble.left.and.bubble.right.fill",
                           "play.rectangle.fill", "music.note", "book.fill", "safari.fill"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Group name", text: $name)
                }

                Section("Icon") {
                    Picker("Icon", selection: Binding(
                        get: { lockGroups.group(id: group.id)?.symbol ?? group.symbol },
                        set: { lockGroups.setSymbol($0, for: group.id) }
                    )) {
                        ForEach(symbols, id: \.self) { symbol in
                            Image(systemName: symbol).tag(symbol)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    LabeledContent("Chosen", value: lockGroups.summary(for: group.id))
                    Button {
                        showPicker = true
                    } label: {
                        Label("Choose Apps & Categories", systemImage: "plus.circle.fill")
                    }
                } footer: {
                    Text("These apps stay on this device. The parent device only ever sees the group's name.")
                }
            }
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }.bold()
                }
            }
            .sheet(isPresented: $showPicker) {
                FamilyPickerSheet(title: "Group Apps", selection: $selection)
            }
            .onAppear {
                name = lockGroups.group(id: group.id)?.name ?? group.name
                selection = lockGroups.selection(for: group.id)
            }
            .onChange(of: selection) { _, newValue in
                lockGroups.setSelection(newValue, for: group.id)
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { lockGroups.rename(group.id, to: trimmed) }
        Task { await remote.publishGroups() }
        dismiss()
    }
}
