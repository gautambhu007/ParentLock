//
//  ParentLockApp.swift
//  ParentLock
//
//  App entry point. Wires up SwiftData, dependency injection, and the
//  biometric app-lock overlay that re-locks the dashboard on background.
//

import SwiftUI
import SwiftData
import FamilyControls

@main
struct ParentLockApp: App {
    /// Single SwiftData container shared across the app.
    let modelContainer: ModelContainer

    /// App-wide dependencies (constructed once, injected via Environment).
    @State private var dependencies = AppDependencies()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            modelContainer = try ModelContainer(
                for: BlockSchedule.self,
                     AppLimit.self,
                     Reward.self,
                     UsageRecord.self,
                     ChildProfile.self,
                     ParentPreferences.self
            )
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies.auth)
                .environment(dependencies.authorization)
                .environment(dependencies.selectionStore)
                .environment(dependencies.shieldManager)
                .environment(dependencies.scheduleEngine)
                .environment(dependencies.limitEngine)
                .environment(dependencies.rewardEngine)
                .environment(dependencies.notifications)
                .task {
                    // On launch, make sure blocks from a previous session are
                    // live even if no screen re-applied them.
                    dependencies.shieldManager.reassertPersistentShields()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .background:
                        dependencies.auth.lock()          // Re-lock when backgrounded
                    case .active:
                        Task { await dependencies.authorization.refreshStatus() }
                        // Re-assert shields in case they were dropped while away.
                        dependencies.shieldManager.reassertPersistentShields()
                    default:
                        break
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}

/// Simple composition root — constructor injection, no singletons.
@MainActor
@Observable
final class AppDependencies {
    let auth: BiometricAuthManager
    let authorization: FamilyControlsAuthorizationManager
    let selectionStore: SelectionStore
    let shieldManager: ShieldManager
    let scheduleEngine: ScheduleEngine
    let limitEngine: DailyLimitEngine
    let rewardEngine: RewardEngine
    let notifications: NotificationManager

    init() {
        let selectionStore = SelectionStore()
        let shieldManager = ShieldManager(selectionStore: selectionStore)
        self.auth = BiometricAuthManager()
        self.authorization = FamilyControlsAuthorizationManager()
        self.selectionStore = selectionStore
        self.shieldManager = shieldManager
        self.scheduleEngine = ScheduleEngine(shieldManager: shieldManager)
        self.limitEngine = DailyLimitEngine(selectionStore: selectionStore)
        self.rewardEngine = RewardEngine(shieldManager: shieldManager)
        self.notifications = NotificationManager()
    }
}
