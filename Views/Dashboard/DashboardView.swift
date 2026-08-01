//
//  DashboardView.swift
//  ParentLock
//
//  Parent home page: branded hero header, live protection-status banner,
//  quick stats, and grouped feature cards over a soft gradient.
//  Adapts across Split View / all size classes.
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(SelectionStore.self) private var selectionStore
    @Environment(ShieldManager.self) private var shieldManager
    @Environment(FamilyControlsAuthorizationManager.self) private var authorization
    @Environment(BiometricAuthManager.self) private var auth
    @Environment(RemoteControlCoordinator.self) private var remote
    @Query private var schedules: [BlockSchedule]
    @Query private var limits: [AppLimit]
    @Query private var rewards: [Reward]
    @Query private var children: [ChildProfile]

    @State private var navigationPath = NavigationPath()

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 16)]

    enum Destination: Hashable {
        case allowedApps, blockedApps, schedules, dailyLimits
        case rewards, reports, screenTime, emergencyUnlock, settings
        case remoteControl
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 20) {
                    HomeHeader(childName: children.first?.name)

                    ProtectionStatusBanner(state: bannerState, detail: bannerDetail)

                    quickStats

                    section(String(localized: "Protection")) {
                        card(.blockedApps, "Blocked Apps", selectionStore.blockedSummary, "hand.raised.fill", .red)
                        card(.allowedApps, "Allowed Apps", "\(selectionStore.allowedSelection.applicationTokens.count) always available", "checkmark.circle.fill", .green)
                        card(.schedules, "Schedules", scheduleSubtitle, "calendar.badge.clock", .blue)
                        card(.dailyLimits, "Daily Limits", limitSubtitle, "hourglass", .orange)
                        card(.remoteControl, "Remote Control", remoteSubtitle, "antenna.radiowaves.left.and.right", .indigo)
                    }

                    section(String(localized: "Insights & Rewards")) {
                        card(.rewards, "Rewards", "\(rewards.filter { !$0.isCompleted }.count) waiting", "star.fill", .yellow)
                        card(.reports, "Reports", "Daily · Weekly · Monthly", "chart.bar.fill", .purple)
                        card(.screenTime, "Screen Time", "Today's usage", "iphone", .teal)
                    }

                    section(String(localized: "Manage")) {
                        card(.emergencyUnlock, "Emergency Unlock", unlockSubtitle, "key.fill", .pink)
                        card(.settings, "Settings", "Appearance · Security", "gearshape.fill", .gray)
                    }
                }
                .padding(20)
            }
            .background {
                LinearGradient(colors: [.blue.opacity(0.10), .purple.opacity(0.08)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
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
                case .remoteControl:   RemoteControlView()
                case .settings:        SettingsView()
                }
            }
        }
    }

    // MARK: Quick stats

    private var quickStats: some View {
        HStack(spacing: 12) {
            StatChip(value: "\(blockedAppCount)", label: "Apps blocked",
                     symbol: "hand.raised.fill", tint: .red)
            StatChip(value: "\(activeScheduleCount)", label: "Active schedules",
                     symbol: "calendar.badge.clock", tint: .blue)
            StatChip(value: "\(blockedAttemptsToday)", label: "Blocked today",
                     symbol: "shield.lefthalf.filled", tint: .indigo)
        }
    }

    // MARK: Derived state

    private var blockedAppCount: Int {
        selectionStore.blockedSelection.applicationTokens.count
            + selectionStore.blockedSelection.categoryTokens.count
    }

    private var activeScheduleCount: Int {
        schedules.filter { $0.isEnabled }.count
    }

    private var blockedAttemptsToday: Int {
        UserDefaults(suiteName: "group.com.gautam.parentlock")?
            .integer(forKey: "blockedAttemptCount") ?? 0
    }

    private var isTemporarilyUnlocked: Bool {
        if let expiry = shieldManager.temporaryUnlockExpiry, expiry > .now { return true }
        return false
    }

    private var bannerState: ProtectionStatusBanner.State {
        if isTemporarilyUnlocked { return .unlocked }
        if !authorization.isAuthorized || blockedAppCount == 0 { return .attention }
        return .active
    }

    private var bannerDetail: String {
        if let expiry = shieldManager.temporaryUnlockExpiry, expiry > .now {
            return String(localized: "All blocks lifted until \(expiry.formatted(date: .omitted, time: .shortened)).")
        }
        if !authorization.isAuthorized {
            return String(localized: "Screen Time access is off. Tap Settings to grant it.")
        }
        if blockedAppCount == 0 {
            return String(localized: "No apps are blocked yet. Choose some in Blocked Apps.")
        }
        return String(localized: "\(blockedAppCount) apps or categories are being protected right now.")
    }

    private var scheduleSubtitle: String {
        let active = activeScheduleCount
        return active > 0
            ? String(localized: "\(active) of \(schedules.count) active")
            : String(localized: "\(schedules.count) schedules")
    }

    private var limitSubtitle: String {
        String(localized: "\(limits.count) limits set")
    }

    private var remoteSubtitle: String {
        switch remote.role {
        case .unpaired:
            return String(localized: "Pair a child device")
        case .parent:
            if let status = remote.childStatus {
                let reach = status.isOnline
                    ? String(localized: "online")
                    : String(localized: "offline")
                return status.isAllLocked
                    ? String(localized: "All apps locked · \(reach)")
                    : String(localized: "\(status.lockedGroupIDs.count) groups locked · \(reach)")
            }
            return String(localized: "Waiting for the child device")
        case .child:
            return String(localized: "Managed by \(remote.pairedDeviceName ?? String(localized: "a parent device"))")
        }
    }

    private var unlockSubtitle: String {
        if let expiry = shieldManager.temporaryUnlockExpiry, expiry > .now {
            return String(localized: "Active until \(expiry.formatted(date: .omitted, time: .shortened))")
        }
        return String(localized: "Temporarily lift all blocks")
    }

    // MARK: Building blocks

    @ViewBuilder
    private func section(_ title: String,
                         @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: LocalizedStringKey(title))
            LazyVGrid(columns: columns, spacing: 16) {
                content()
            }
        }
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
