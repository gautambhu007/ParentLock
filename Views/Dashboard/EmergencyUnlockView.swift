//
//  EmergencyUnlockView.swift
//  ParentLock
//
//  Face ID → choose duration → all shields lifted → auto-restore.
//

import SwiftUI

struct EmergencyUnlockView: View {
    @Environment(ShieldManager.self) private var shieldManager
    @Environment(BiometricAuthManager.self) private var auth
    @State private var errorMessage: String?

    private let durations: [(label: LocalizedStringKey, minutes: Int)] = [
        ("15 minutes", 15), ("30 minutes", 30), ("1 hour", 60)
    ]

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundStyle(.pink)
                .symbolEffect(.bounce, value: shieldManager.temporaryUnlockExpiry)

            if let expiry = shieldManager.temporaryUnlockExpiry, expiry > .now {
                Text("Unlocked until \(expiry.formatted(date: .omitted, time: .shortened))")
                    .font(.title2.bold())
                BigButton(title: "End Unlock Now", systemImage: "lock.fill", role: .destructive) {
                    endEarly()
                }
            } else {
                Text("Temporarily remove all blocks")
                    .font(.title2.bold())
                Text("All shields come back automatically when the time is up.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                ForEach(durations, id: \.minutes) { duration in
                    BigButton(title: duration.label, systemImage: "clock") {
                        unlock(minutes: duration.minutes)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: 480)
        .navigationTitle("Emergency Unlock")
    }

    private func unlock(minutes: Int) {
        Task {
            do {
                try await auth.authenticateForAction(reason: "Emergency unlock for \(minutes) minutes")
                withAnimation(.spring) {
                    shieldManager.temporarilyUnlockAll(for: TimeInterval(minutes * 60))
                }
                errorMessage = nil
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func endEarly() {
        Task {
            do {
                try await auth.authenticateForAction(reason: "Restore blocks now")
                withAnimation(.spring) { shieldManager.endTemporaryUnlock() }
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
