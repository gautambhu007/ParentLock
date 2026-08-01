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

    /// Owns push registration; forwards CloudKit silent pushes to the coordinator.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let schema = Schema([
                BlockSchedule.self,
                AppLimit.self,
                Reward.self,
                UsageRecord.self,
                ChildProfile.self,
                ParentPreferences.self
            ])
            // `.none` is required, not just preferred: the CloudKit entitlement
            // that remote control needs would otherwise make SwiftData try to
            // mirror these models, which its `@Attribute(.unique)` ids don't
            // support. Schedules, limits and rewards stay on device — only
            // remote-control commands ever touch CloudKit.
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            modelContainer = try ModelContainer(for: schema, configurations: configuration)
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
                .environment(dependencies.pairingStore)
                .environment(dependencies.lockGroupStore)
                .environment(dependencies.remoteControl)
                .task {
                    // On launch, make sure blocks from a previous session are
                    // live even if no screen re-applied them.
                    dependencies.shieldManager.reassertPersistentShields()
                    RemotePushBridge.shared.coordinator = dependencies.remoteControl
                    await dependencies.remoteControl.activate()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .background:
                        dependencies.auth.lock()          // Re-lock when backgrounded
                        dependencies.remoteControl.deactivate()
                    case .active:
                        Task { await dependencies.authorization.refreshStatus() }
                        // Re-assert shields in case they were dropped while away.
                        dependencies.shieldManager.reassertPersistentShields()
                        // Catch up on anything a missed push would have delivered.
                        Task { await dependencies.remoteControl.activate() }
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
    let pairingStore: RemotePairingStore
    let lockGroupStore: LockGroupStore
    let remoteControl: RemoteControlCoordinator

    init() {
        let selectionStore = SelectionStore()
        let lockGroupStore = LockGroupStore()
        let shieldManager = ShieldManager(selectionStore: selectionStore, lockGroupStore: lockGroupStore)
        let pairingStore = RemotePairingStore()
        let notifications = NotificationManager()
        self.auth = BiometricAuthManager()
        self.authorization = FamilyControlsAuthorizationManager()
        self.selectionStore = selectionStore
        self.lockGroupStore = lockGroupStore
        self.pairingStore = pairingStore
        self.shieldManager = shieldManager
        self.remoteControl = RemoteControlCoordinator(
            pairing: pairingStore,
            lockGroups: lockGroupStore,
            shieldManager: shieldManager,
            notifications: notifications
        )
        self.scheduleEngine = ScheduleEngine(shieldManager: shieldManager)
        self.limitEngine = DailyLimitEngine(selectionStore: selectionStore)
        self.rewardEngine = RewardEngine(shieldManager: shieldManager)
        self.notifications = notifications
    }
}
