//
//  OnboardingFlowView.swift
//  ParentLock
//
//  First-launch onboarding: explains Screen Time + Family Controls
//  permissions and privacy, then requests authorization. If denied,
//  shows recovery instructions.
//

import SwiftUI
import FamilyControls

struct OnboardingFlowView: View {
    let onFinished: () -> Void
    @Environment(FamilyControlsAuthorizationManager.self) private var authorization
    @Environment(NotificationManager.self) private var notifications
    @State private var page = 0
    @State private var requesting = false

    var body: some View {
        TabView(selection: $page) {
            OnboardingPage(
                symbol: "shield.lefthalf.filled",
                tint: .blue,
                title: "Welcome to ParentLock",
                message: "Gently guide your child's screen time with schedules, limits, and rewards — all managed by you."
            ).tag(0)

            OnboardingPage(
                symbol: "hourglass",
                tint: .purple,
                title: "Screen Time Permission",
                message: "ParentLock uses Apple's Screen Time technology to know when apps are used, so limits and schedules work automatically — even when the app is closed."
            ).tag(1)

            OnboardingPage(
                symbol: "person.2.fill",
                tint: .green,
                title: "Family Controls Permission",
                message: "Family Controls lets ParentLock show a friendly shield over blocked apps. Only you can change what's blocked, protected by Face ID."
            ).tag(2)

            OnboardingPage(
                symbol: "lock.icloud.fill",
                tint: .orange,
                title: "Your Privacy",
                message: "Everything stays on this iPad. No accounts, no analytics, no data collection — nothing ever leaves the device."
            ).tag(3)

            authorizationPage.tag(4)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background {
            LinearGradient(colors: [.blue.opacity(0.12), .purple.opacity(0.10)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private var authorizationPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: authorization.isAuthorized ? "checkmark.seal.fill" : "hand.raised.square.fill")
                .font(.system(size: 80))
                .foregroundStyle(authorization.isAuthorized ? .green : .blue)
                .contentTransition(.symbolEffect(.replace))

            if authorization.isAuthorized {
                Text("All set!").font(.largeTitle.bold())
                BigButton(title: "Open Dashboard", systemImage: "arrow.right") {
                    Task { await notifications.requestPermission() }
                    onFinished()
                }
            } else if authorization.status == .denied {
                Text("Permission Needed").font(.largeTitle.bold())
                Text("To enable later: open Settings → Screen Time → Apps with Screen Time Access → ParentLock, then return here.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                BigButton(title: "Try Again", systemImage: "arrow.clockwise") { request() }
                Button("Continue without permission") { onFinished() }
                    .foregroundStyle(.secondary)
            } else {
                Text("Enable Family Controls").font(.largeTitle.bold())
                Text("Apple will ask you to approve Screen Time access for ParentLock.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                BigButton(title: requesting ? "Requesting…" : "Grant Permission",
                          systemImage: "checkmark.shield") { request() }
                    .disabled(requesting)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: 520)
    }

    private func request() {
        requesting = true
        Task {
            await authorization.requestAuthorization()
            requesting = false
        }
    }
}

private struct OnboardingPage: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 80))
                .foregroundStyle(tint)
                .symbolEffect(.pulse)
            Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(message)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Swipe to continue").font(.footnote).foregroundStyle(.tertiary)
                .padding(.bottom, 40)
        }
        .padding(32)
        .frame(maxWidth: 520)
    }
}
