# ParentLock 🛡️

A modern iPadOS 18+ parental control app built entirely on Apple's public
frameworks: **SwiftUI, Swift 6, FamilyControls, ManagedSettings,
DeviceActivity, LocalAuthentication, SwiftData, and Observation**.

Everything stays on device. No accounts, no analytics, no data collection —
with one deliberate exception: **remote lock/unlock** syncs commands through
your own iCloud (CloudKit) container. See
[Remote control](#remote-control-parent--child) for exactly what crosses the
network.

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
5. For remote control, add **iCloud → CloudKit** (container
   `iCloud.com.yourteam.parentlock`) and **Push Notifications** to the *app*
   target only — extensions don't need either. Update the container ID in
   `Remote/CloudCommandChannel.swift` if you rename it.

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
 ├── NotificationManager         local parent alerts
 └── RemoteControlCoordinator    parent ⇄ child remote lock/unlock
      ├── RemotePairingStore     device role + pairing code
      ├── LockGroupStore         named app groups (selections stay local)
      └── CloudCommandChannel    CloudKit transport + silent push
```

- **MVVM-ish with @Observable**: views bind directly to observable managers;
  SwiftData `@Query` powers list state.
- **Extensions are the enforcement layer** — they run even when the app is
  closed or the device restarts, reading selections from the App Group.
- **Shield actions can't show Face ID** (extension limitation by design);
  "Parent Unlock" routes the parent into the app where Face ID gates the
  actual unlock. This is the Apple-sanctioned pattern.

## Remote control (parent ⇄ child)

Install the same app on both devices and pick a role once:

1. **Parent device** → Dashboard → *Remote Control* → "This is my device" →
   an 8-character pairing code appears.
2. **Child iPad** → Dashboard → *Remote Control* → type the code.
3. On the child iPad, open *App Groups* and create the buckets you want to
   control — "Games", "Social" — picking the actual apps for each.

The parent can then:

| Action | Effect on the child iPad |
|---|---|
| **Lock All Apps** | Shields every app except the always-allowed ones, including apps installed later |
| **Unlock All Apps** | Releases the remote shield entirely |
| **Unlock for 15/30/60 min** | Lifts *all* shields, then restores them automatically |
| **Toggle an app group** | Shields/releases just that group's apps |

Everything is Face ID gated on the parent device, and the parent sees the
status the child device actually reported back — not an optimistic guess.

### What crosses the network — and what doesn't

Only these go into CloudKit: the pairing code, each device's name, the
**names** of app groups, and lock/unlock commands with their status.

`ApplicationToken`s never leave the device that picked them. They're opaque
and device-scoped, so a token is meaningless anywhere else — which is exactly
why groups are defined on the child iPad and referenced by id from the parent.

### Design notes

- **Public database, deterministic record names.** Parent and child usually
  use different Apple IDs, and the private database can't be read across
  accounts. The pairing code is the shared secret (31⁸ ≈ 8.5 × 10¹¹
  combinations, ambiguous characters excluded). Every read/write is a direct
  `fetch(withRecordID:)`, so no CloudKit query indexes are required.
- **Push is an optimisation, not a dependency.** Silent pushes make commands
  land in seconds; if subscriptions can't be created the app still syncs on
  launch, on foreground, on pull-to-refresh, and on a 60-second poll.
  To enable push, mark the `code` field **Queryable** on the `PLCommandQueue`
  and `PLStatus` record types in the CloudKit Dashboard.
- **Remote locks compose, they don't override.** They live in their own
  `ManagedSettingsStore` (`remoteControl`), so a remote *unlock* can never
  remove blocks the parent configured on the device itself. An on-device
  emergency unlock does outrank remote locks — until it expires, at which
  point the remote locks come back.
- **Commands are idempotent.** Applied ids are recorded in the App Group, so a
  duplicate push or a replayed queue can't re-fire a command.
- **Unpairing is local-only.** A child device unpairing needs Face ID, and it
  does *not* release shields already applied.

### Testing it

Remote control needs two physical devices (FamilyControls doesn't run in the
Simulator) and both signed into iCloud. The pairing, command, and state logic
is covered without CloudKit in `Tests/ParentLockTests/RemoteControlTests.swift`.

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
| Remote lock/unlock | `Remote/`, `Views/Remote/` |
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
  metadata can sync; tokens must be re-picked per device. This is why remote
  control targets *named groups* rather than individual apps chosen from the
  parent device.
- **SwiftData stays local**: the container is pinned to
  `cloudKitDatabase: .none`. Adding the CloudKit entitlement would otherwise
  make SwiftData try to mirror the models, which its `@Attribute(.unique)` ids
  don't support — the app crashes on launch without the pin.
- **Remote commands need the child device awake enough to run**: silent pushes
  wake the app in the background, but iOS can throttle them. Worst case a
  command applies the next time the child's iPad is unlocked and online, which
  is why the parent UI shows pending vs. applied honestly.

## Roadmap (bonus features scaffolded, not yet wired)

Multiple child profiles (`ChildProfile` model exists), widgets, App Intents /
Siri Shortcuts, one-time unlock codes, streaks & badges, CSV/PDF export,
Apple Watch companion, remote control of *schedules and limits* (today the
remote is lock/unlock only).
