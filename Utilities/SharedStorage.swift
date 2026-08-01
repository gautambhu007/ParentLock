//
//  SharedStorage.swift
//  ParentLock
//
//  App Group storage shared between the main app and the three extensions
//  (shield configuration, shield action, device activity monitor).
//  FamilyActivitySelection is Codable, so it round-trips through JSON.
//

import Foundation
import FamilyControls

enum SharedStorage {
    /// ⚠️ Must match the App Group added to the main app AND all extension targets.
    static let appGroupID = "group.com.gautam.parentlock"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    enum Key: String {
        case blockedSelection          // FamilyActivitySelection (blocked apps/categories/domains)
        case allowedSelection          // FamilyActivitySelection (always-allowed apps)
        case bedtimeSelection          // Exceptions kept available during bedtime
        case limitSelections           // [UUID: FamilyActivitySelection] for daily limits
        case pendingTimeRequest        // Set by ShieldActionExtension, read by the app
        case temporaryUnlockExpiry     // Date — active emergency/temporary unlock
        case blockedAttemptCount       // Incremented by ShieldActionExtension for reports
        case shieldTheme               // Custom shield theme name

        // MARK: Remote control
        case deviceRole                // DeviceRole — parent / child / unpaired
        case pairingCode               // String — shared secret linking the two devices
        case pairedDeviceName          // String — name of the device on the other end
        case lockGroups                // [RemoteLockGroup] metadata (id + name + symbol)
        case lockGroupSelections       // [UUID: FamilyActivitySelection] — device-local
        case remoteLockState           // RemoteLockState — what the parent has locked
        case appliedCommandIDs         // [UUID] — commands already applied (dedupe)
    }

    static func saveString(_ value: String?, for key: Key) {
        if let value {
            defaults.set(value, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    static func loadString(for key: Key) -> String? {
        defaults.string(forKey: key.rawValue)
    }

    static func saveCodable<T: Codable>(_ value: T, for key: Key) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key.rawValue)
    }

    static func loadCodable<T: Codable>(_ type: T.Type, for key: Key) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func remove(_ key: Key) {
        defaults.removeObject(forKey: key.rawValue)
    }
}
