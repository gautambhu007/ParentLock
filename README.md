# ParentLock 🛡️

A modern iPadOS 18+ parental control app built entirely on Apple's public
frameworks: **SwiftUI, Swift 6, FamilyControls, ManagedSettings,
DeviceActivity, LocalAuthentication, SwiftData, and Observation**.

Everything stays on device. No accounts, no analytics, no data collection.

---

## ⚠️ Before you build — required Apple setup

Family Controls is a **restricted entitlement**:

1. **Development** works immediately: add the *Family Controls (Development)*
   capability in Xcode to the app **and all three extensions**.
2. **App Store / TestFlight distribution** requires applying to Apple for the
   distribution entitlement at
   <https://developer.apple.com/contact/request/family-controls-distribution>.
   Approval typically takes days–weeks and requires describing the app.
3. **FamilyControls does not work in the Simulator.** Test on a physical iPad.
4. Create an **App Group** (`group.com.yourteam.parentlock`) and add it to the
   app and all three extension targets, then update the ID in
   `Utilities/SharedStorage.swift` and both extensions.

## Opening the project

A ready-made `ParentLock.xcodeproj` is included (Xcode 16+, uses folder-synced
groups so new files are picked up automatically):

```bash
open ParentLock.xcodeproj
```

Then, one-time setup in Xcode:

1. Select the project → each of the 6 targets → *Signing & Capabilities* →
   set your **Team** (bundle IDs are `com.yourteam.parentlock*` — rename to
   your own prefix).
2. Confirm the **Family Controls** and **App Groups** capabilities appear on
   the app + all three extensions (they're wired via the entitlements files
   in `Config/`).
3. Register the App Group `group.com.yourteam.parentlock` in your developer
   account, or rename it everywhere (`Config/*.entitlements`,
   `Utilities/SharedStorage.swift`, both extension sources).

An XcodeGen spec (`project.yml`) is also included if you prefer regenerating
the project: `brew install xcodegen && xcodegen generate`.

The extension targets map to these extension points:

| Target | Extension point |
|---|---|
| ShieldConfigurationExtension | `com.apple.ManagedSettingsUI.shield-configuration-service` |
| ShieldActionExtension | `com.apple.ManagedSettings.shield-action-service` |
| DeviceActivityMonitorExtension | `com.apple.deviceactivity.monitor-extension` |

## Architecture

```
ParentLockApp (composition root, DI via Environment)
 ├── BiometricAuthManager        LocalAuthentication; app lock + per-action auth
 ├── FamilyControlsAuthorizationManager   authorization lifecycle + revocation
 ├── SelectionStore              FamilyActivitySelections → App Group JSON
 ├── ShieldManager               4 named ManagedSettingsStores (manual /
 │                               schedule / bedtime / limits) so features
 │                               compose without conflicts
 ├── ScheduleEngine              DeviceActivityCenter schedules + bedtime
 ├── DailyLimitEngine            DeviceActivityEvent minute thresholds
 ├── RewardEngine                timed unlock + auto-restore
 └── NotificationManager         local parent alerts
```

- **MVVM-ish with @Observable**: views bind directly to observable managers;
  SwiftData `@Query` powers list state.
- **Extensions are the enforcement layer** — they run even when the app is
  closed or the device restarts, reading selections from the App Group.
- **Shield actions can't show Face ID** (extension limitation by design);
  "Parent Unlock" routes the parent into the app where Face ID gates the
  actual unlock. This is the Apple-sanctioned pattern.

## Feature map

| Requirement | Where |
|---|---|
| Onboarding + permission flow | `Views/Onboarding/OnboardingFlowView.swift` |
| Face ID everywhere | `Authentication/BiometricAuthManager.swift` (+ per-action calls in every view) |
| Dashboard cards | `Views/Dashboard/DashboardView.swift` |
| Blocked/allowed apps | `Views/Dashboard/BlockedAppsView.swift` |
| Custom shield | `Extensions/ShieldConfigurationExtension` |
| Request More Time / Parent Unlock | `Extensions/ShieldActionExtension` |
| Schedules + Bedtime | `Views/Schedules`, `DeviceActivity/ScheduleEngine.swift` |
| Daily limits, midnight reset | `DeviceActivity/DailyLimitEngine.swift` + monitor extension |
| Rewards + confetti | `Views/Rewards`, `Rewards/RewardEngine.swift` |
| Emergency unlock | `Views/Dashboard/EmergencyUnlockView.swift` |
| Reports + charts | `Views/Reports/ReportsView.swift` |
| Notifications | `Notifications/NotificationManager.swift` |
| SwiftData models | `Persistence/Models/Models.swift` |
| Localization (en + hi) | `Resources/Localization` |
| Tests | `Tests/` |

## Known platform constraints (honest notes)

- **Detailed usage reports**: Apple only exposes raw Screen Time data inside a
  sandboxed `DeviceActivityReport` extension whose data cannot leave the
  report view. `ReportsView` charts locally recorded events (blocked attempts,
  threshold hits); add a DeviceActivityReport extension target for full
  per-app usage visuals.
- **20-schedule cap**: `DeviceActivityCenter` limits concurrent monitored
  activities (~20). "Unlimited schedules" are stored in SwiftData; only
  enabled ones register with the center.
- **iCloud sync of selections**: `ApplicationToken`s are device-scoped opaque
  tokens and cannot meaningfully sync across devices. Preferences/schedules
  metadata can sync; tokens must be re-picked per device.

## Roadmap (bonus features scaffolded, not yet wired)

Multiple child profiles (`ChildProfile` model exists), widgets, App Intents /
Siri Shortcuts, one-time unlock codes, streaks & badges, CSV/PDF export,
Apple Watch companion.
