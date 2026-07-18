//
//  RootView.swift
//  ParentLock
//
//  Decides between onboarding, the locked screen, and the dashboard.
//

import SwiftUI

struct RootView: View {
    @Environment(FamilyControlsAuthorizationManager.self) private var authorization
    @Environment(BiometricAuthManager.self) private var auth
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            if !hasCompletedOnboarding {
                OnboardingFlowView {
                    hasCompletedOnboarding = true
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if auth.isLocked {
                AppLockView()
                    .transition(.opacity)
            } else {
                DashboardView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: auth.isLocked)
        .animation(.smooth(duration: 0.35), value: hasCompletedOnboarding)
    }
}

/// Full-screen lock requiring Face ID / passcode before showing the dashboard.
struct AppLockView: View {
    @Environment(BiometricAuthManager.self) private var auth
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse)
                Text("ParentLock")
                    .font(.largeTitle.bold())
                Text("Authenticate to open the parent dashboard.")
                    .foregroundStyle(.secondary)
                Button {
                    unlock()
                } label: {
                    Label("Unlock with Face ID", systemImage: "faceid")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .task { unlock() }   // Prompt immediately on appear
    }

    private func unlock() {
        Task {
            do {
                try await auth.authenticate(reason: "Unlock the ParentLock dashboard")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
