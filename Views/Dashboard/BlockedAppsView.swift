//
//  BlockedAppsView.swift
//  ParentLock
//
//  FamilyActivityPicker-backed blocked apps management. Applying changes
//  requires Face ID and a valid FamilyControls authorization.
//

import SwiftUI
import FamilyControls

struct BlockedAppsView: View {
    @Environment(SelectionStore.self) private var selectionStore
    @Environment(ShieldManager.self) private var shieldManager
    @Environment(BiometricAuthManager.self) private var auth
    @Environment(FamilyControlsAuthorizationManager.self) private var authorization

    @State private var showPicker = false
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var store = selectionStore
        List {
            Section {
                LabeledContent("Currently blocked", value: selectionStore.blockedSummary)
                Button {
                    showPicker = true
                } label: {
                    Label("Choose Apps, Categories & Websites", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("Selected apps show a friendly shield when opened. Your child can request more time from the shield.")
            }

            Section {
                BigButton(title: "Apply Blocks", systemImage: "lock.fill") {
                    applyBlocks()
                }
                .listRowBackground(Color.clear)
                BigButton(title: "Remove All Blocks", systemImage: "lock.open.fill", role: .destructive) {
                    removeBlocks()
                }
                .listRowBackground(Color.clear)
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Blocked Apps")
        .sheet(isPresented: $showPicker) {
            FamilyPickerSheet(title: "Blocked Apps", selection: $store.blockedSelection)
        }
    }

    private func applyBlocks() {
        Task {
            do {
                try authorization.validateAuthorized()
                try await auth.authenticateForAction(reason: "Apply app blocks")
                withAnimation(.spring) { shieldManager.applyManualBlocks() }
                errorMessage = nil
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func removeBlocks() {
        Task {
            do {
                try await auth.authenticateForAction(reason: "Remove all app blocks")
                withAnimation(.spring) { shieldManager.clearManualBlocks() }
                errorMessage = nil
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

struct AllowedAppsView: View {
    @Environment(SelectionStore.self) private var selectionStore
    @State private var showPicker = false

    var body: some View {
        @Bindable var store = selectionStore
        List {
            Section {
                LabeledContent("Always allowed",
                               value: "\(selectionStore.allowedSelection.applicationTokens.count) apps")
                Button {
                    showPicker = true
                } label: {
                    Label("Choose Allowed Apps", systemImage: "checkmark.circle.fill")
                }
            } footer: {
                Text("These apps stay available during schedules — for example Safari, Books, Calculator, or school apps.")
            }
        }
        .navigationTitle("Allowed Apps")
        .sheet(isPresented: $showPicker) {
            FamilyPickerSheet(title: "Allowed Apps", selection: $store.allowedSelection)
        }
    }
}
