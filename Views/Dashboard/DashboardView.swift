//
//  DashboardView.swift
//  ParentLock
//
//  Parent home screen: adaptive grid of cards over a soft gradient +
//  material background. Supports Split View / all size classes.
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(SelectionStore.self) private var selectionStore
    @Environment(ShieldManager.self) private var shieldManager
    @Environment(BiometricAuthManager.self) private var auth
    @Query private var schedules: [BlockSchedule]
    @Query private var limits: [AppLimit]
    @Query private var rewards: [Reward]

    @State private var navigationPath = NavigationPath()

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 16)]

    enum Destination: Hashable {
        case allowedApps, blockedApps, schedules, dailyLimits
        case rewards, reports, screenTime, emergencyUnlock, settings
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    card(.allowedApps, "Allowed Apps", "\(selectionStore.allowedSelection.applicationTokens.count) always available", "checkmark.circle.fill", .green)
                    card(.blockedApps, "Blocked Apps", selectionStore.blockedSummary, "hand.raised.fill", .red)
                    card(.schedules, "Schedules", "\(schedules.count) schedules", "calendar.badge.clock", .blue)
                    card(.dailyLimits, "Daily Limits", "\(limits.count) limits", "hourglass", .orange)
                    card(.rewards, "Rewards", "\(rewards.filter { !$0.isCompleted }.count) waiting", "star.fill", .yellow)
                    card(.reports, "Reports", "Daily · Weekly · Monthly", "chart.bar.fill", .purple)
                    card(.screenTime, "Screen Time", "Today's usage", "iphone", .teal)
                    card(.emergencyUnlock, "Emergency Unlock", unlockSubtitle, "key.fill", .pink)
                    card(.settings, "Settings", "Appearance · Security", "gearshape.fill", .gray)
                }
                .padding(20)
            }
            .background {
                LinearGradient(colors: [.blue.opacity(0.10), .purple.opacity(0.08)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            }
            .navigationTitle("ParentLock")
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .allowedApps:     AllowedAppsView()
                case .blockedApps:     BlockedAppsView()
                case .schedules:       SchedulesView()
                case .dailyLimits:     DailyLimitsView()
                case .rewards:         RewardsView()
                case .reports:         ReportsView()
                case .screenTime:      ReportsView(initialRange: .daily)
                case .emergencyUnlock: EmergencyUnlockView()
                case .settings:        SettingsView()
                }
            }
        }
    }

    private var unlockSubtitle: String {
        if let expiry = shieldManager.temporaryUnlockExpiry, expiry > .now {
            return "Active until \(expiry.formatted(date: .omitted, time: .shortened))"
        }
        return "Temporarily lift all blocks"
    }

    @ViewBuilder
    private func card(_ destination: Destination,
                      _ title: LocalizedStringKey,
                      _ subtitle: String,
                      _ symbol: String,
                      _ tint: Color) -> some View {
        NavigationLink(value: destination) {
            DashboardCard(title: title, subtitle: subtitle, systemImage: symbol, tint: tint)
        }
        .buttonStyle(.plain)
    }
}
