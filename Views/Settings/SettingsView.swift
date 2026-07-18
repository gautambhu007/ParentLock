//
//  SettingsView.swift
//  ParentLock
//
//  Appearance, security, notifications, export/reset.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(BiometricAuthManager.self) private var auth
    @Environment(NotificationManager.self) private var notifications
    @Environment(\.modelContext) private var modelContext

    @AppStorage("preferredColorScheme") private var preferredScheme = "system"
    @AppStorage("accentColor") private var accentColor = "blue"
    @AppStorage("faceIDEnabled") private var faceIDEnabled = true
    @AppStorage("autoLockSeconds") private var autoLockSeconds = 60

    @State private var showResetConfirmation = false
    @State private var exportURL: URL?

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $preferredScheme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Picker("Accent Color", selection: $accentColor) {
                    ForEach(["blue", "purple", "pink", "orange", "green", "teal"], id: \.self) {
                        Text($0.capitalized).tag($0)
                    }
                }
            }

            Section("Security") {
                Toggle("Require Face ID", isOn: $faceIDEnabled)
                    .onChange(of: faceIDEnabled) { _, newValue in
                        // Turning Face ID *off* itself requires Face ID.
                        guard !newValue else { return }
                        Task {
                            if (try? await auth.authenticateForAction(reason: "Disable Face ID lock")) == nil {
                                faceIDEnabled = true
                            }
                        }
                    }
                Picker("Auto-Lock", selection: $autoLockSeconds) {
                    Text("Immediately").tag(0)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                }
                .onChange(of: autoLockSeconds) { _, seconds in
                    auth.autoLockTimeout = TimeInterval(seconds)
                }
            }

            Section("Notifications") {
                Toggle("Parent Alerts", isOn: .init(
                    get: { notifications.isAuthorized },
                    set: { enabled in if enabled { Task { await notifications.requestPermission() } } }
                ))
            }

            Section("Data") {
                Button("Export Settings") { exportSettings() }
                Button("Reset All Settings", role: .destructive) { showResetConfirmation = true }
            }

            Section {
                LabeledContent("Version", value: "1.0")
                LabeledContent("Privacy", value: "All data stays on this device")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Reset all settings?",
                            isPresented: $showResetConfirmation,
                            titleVisibility: .visible) {
            Button("Reset Everything", role: .destructive) { resetAll() }
        } message: {
            Text("Removes all schedules, limits, rewards, and blocks. This cannot be undone.")
        }
    }

    private func exportSettings() {
        // Exports non-sensitive preferences as JSON to the Files app.
        let export: [String: String] = [
            "theme": preferredScheme,
            "accentColor": accentColor,
            "autoLockSeconds": "\(autoLockSeconds)"
        ]
        guard let data = try? JSONEncoder().encode(export) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ParentLockSettings.json")
        try? data.write(to: url)
        exportURL = url
    }

    private func resetAll() {
        Task {
            guard (try? await auth.authenticateForAction(reason: "Reset all settings")) != nil else { return }
            try? modelContext.delete(model: BlockSchedule.self)
            try? modelContext.delete(model: AppLimit.self)
            try? modelContext.delete(model: Reward.self)
            try? modelContext.delete(model: UsageRecord.self)
        }
    }
}
