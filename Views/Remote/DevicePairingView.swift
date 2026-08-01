//
//  DevicePairingView.swift
//  ParentLock
//
//  One-time setup that links a parent device to a child device.
//  The parent mints a code; the child types it in.
//

import SwiftUI

struct DevicePairingView: View {
    @Environment(RemoteControlCoordinator.self) private var remote
    @Environment(BiometricAuthManager.self) private var auth

    @State private var generatedCode: String?
    @State private var enteredCode = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("Pair two devices so you can lock and unlock apps on your child's iPad from your own — even when you're not in the room.")
                    .foregroundStyle(.secondary)
            }

            if !remote.isCloudAvailable {
                Section {
                    Label(RemoteControlError.iCloudUnavailable.errorDescription ?? "",
                          systemImage: "exclamationmark.icloud.fill")
                        .foregroundStyle(.orange)
                }
            }

            parentSection
            childSection

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Pair Devices")
        .disabled(isWorking)
    }

    // MARK: Parent

    @ViewBuilder
    private var parentSection: some View {
        Section {
            if let generatedCode {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter this code on your child's iPad")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(PairingCode.formatted(generatedCode))
                        .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    Text("The code stays valid until you unpair. It's the only thing protecting these commands, so share it with nobody else.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Button {
                    becomeParent()
                } label: {
                    Label("This is my device — show a pairing code", systemImage: "person.badge.shield.checkmark.fill")
                }
            }
        } header: {
            Text("Parent device")
        } footer: {
            Text("Use this on the iPhone or iPad you'll control from.")
        }
    }

    // MARK: Child

    @ViewBuilder
    private var childSection: some View {
        Section {
            TextField("ABCD-EFGH", text: $enteredCode)
                .font(.system(.title3, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button {
                becomeChild()
            } label: {
                Label("Pair this device as the child iPad", systemImage: "ipad")
            }
            .disabled(!PairingCode.isValid(PairingCode.normalize(enteredCode)))
        } header: {
            Text("Child device")
        } footer: {
            Text("Use this on the iPad your child uses. Apps and categories are still chosen here — only their group names travel to the parent device.")
        }
    }

    // MARK: Actions

    private func becomeParent() {
        run(reason: String(localized: "Set up this device as the parent")) {
            generatedCode = try await remote.startPairingAsParent()
        }
    }

    private func becomeChild() {
        run(reason: String(localized: "Pair this device as the child iPad")) {
            try await remote.pairAsChild(code: enteredCode)
        }
    }

    private func run(reason: String, _ work: @escaping () async throws -> Void) {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try await auth.authenticateForAction(reason: reason)
                try await work()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
