//
//  RemoteModels.swift
//  ParentLock
//
//  Value types shared by the parent and child sides of remote control.
//  Everything here is Codable + Sendable so it can cross the CloudKit
//  channel and the App Group boundary unchanged.
//
//  ⚠️ ApplicationTokens are device-scoped opaque values and are deliberately
//  *never* part of these types. Only group ids and names travel between
//  devices; the child device resolves an id to its own local selection.
//

import Foundation

// MARK: - Device role

/// Which side of the pairing this device plays. Chosen once during setup.
enum DeviceRole: String, Codable, Sendable, CaseIterable {
    case unpaired
    case parent
    case child

    var title: String {
        switch self {
        case .unpaired: String(localized: "Not paired")
        case .parent:   String(localized: "Parent device")
        case .child:    String(localized: "Child device")
        }
    }

    var symbol: String {
        switch self {
        case .unpaired: "link.badge.plus"
        case .parent:   "person.badge.shield.checkmark.fill"
        case .child:    "ipad"
        }
    }
}

// MARK: - Pairing code

enum PairingCode {
    /// Ambiguous characters (0/O, 1/I/L) are excluded so a code read aloud
    /// or copied off a screen can't be mistyped into someone else's pairing.
    private static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    /// 8 characters from a 31-symbol alphabet ≈ 8.5 × 10¹¹ combinations,
    /// which is what keeps one family's commands out of another's.
    static func generate() -> String {
        String((0..<8).map { _ in alphabet.randomElement()! })
    }

    /// "ABCDEFGH" → "ABCD-EFGH" for display only.
    static func formatted(_ code: String) -> String {
        guard code.count == 8 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 4)
        return "\(code[code.startIndex..<mid])-\(code[mid...])"
    }

    /// Accepts user input in any case, with or without the separator.
    static func normalize(_ input: String) -> String {
        input.uppercased().filter { alphabet.contains($0) }
    }

    static func isValid(_ code: String) -> Bool {
        code.count == 8 && code.allSatisfy { alphabet.contains($0) }
    }
}

// MARK: - Lock groups

/// A parent-named bundle of apps ("Games", "Social") that lives on the child
/// device. Only `id`, `name` and `symbol` sync — the actual
/// FamilyActivitySelection stays local to the device that picked it.
struct RemoteLockGroup: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var symbol: String

    init(id: UUID = UUID(), name: String, symbol: String = "square.grid.2x2.fill") {
        self.id = id
        self.name = name
        self.symbol = symbol
    }
}

// MARK: - Commands

enum RemoteCommandKind: String, Codable, Sendable {
    case lockAll        // shield everything except the always-allowed apps
    case unlockAll      // release the remote shield entirely
    case lockGroup      // shield one named group
    case unlockGroup    // release one named group

    var isLock: Bool { self == .lockAll || self == .lockGroup }
}

enum RemoteCommandStatus: String, Codable, Sendable {
    case pending
    case applied
    case failed
}

/// One instruction issued by the parent device, applied once by the child.
struct RemoteCommand: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let kind: RemoteCommandKind
    /// Set for `.lockGroup` / `.unlockGroup`.
    let groupID: UUID?
    /// Set for `.unlockAll` to make the unlock temporary; nil means indefinite.
    let durationMinutes: Int?
    let issuedAt: Date
    var status: RemoteCommandStatus
    var appliedAt: Date?
    var failureReason: String?

    init(kind: RemoteCommandKind,
         groupID: UUID? = nil,
         durationMinutes: Int? = nil,
         id: UUID = UUID(),
         issuedAt: Date = .now,
         status: RemoteCommandStatus = .pending,
         appliedAt: Date? = nil,
         failureReason: String? = nil) {
        self.id = id
        self.kind = kind
        self.groupID = groupID
        self.durationMinutes = durationMinutes
        self.issuedAt = issuedAt
        self.status = status
        self.appliedAt = appliedAt
        self.failureReason = failureReason
    }

    func summary(groupName: String?) -> String {
        switch kind {
        case .lockAll:   String(localized: "Lock all apps")
        case .unlockAll:
            if let durationMinutes {
                String(localized: "Unlock all apps for \(durationMinutes) min")
            } else {
                String(localized: "Unlock all apps")
            }
        case .lockGroup:   String(localized: "Lock “\(groupName ?? "group")”")
        case .unlockGroup: String(localized: "Unlock “\(groupName ?? "group")”")
        }
    }
}

// MARK: - Child status

/// What the child device reports back after applying commands. The parent
/// dashboard renders this, so it doubles as the "is it actually locked?" proof.
struct ChildDeviceStatus: Codable, Hashable, Sendable {
    var deviceName: String
    var lastSeen: Date
    var isAllLocked: Bool
    var lockedGroupIDs: [UUID]
    var temporaryUnlockExpiry: Date?

    /// A status older than this is shown as "offline" — the child device is
    /// asleep, out of network, or the app was force-quit.
    static let stalenessThreshold: TimeInterval = 15 * 60

    var isOnline: Bool { Date.now.timeIntervalSince(lastSeen) < Self.stalenessThreshold }
}

// MARK: - Local remote-lock state

/// The child device's own record of what remote control has asked for. Kept
/// in the App Group so a relaunch (or a reboot) re-asserts the same shields.
struct RemoteLockState: Codable, Hashable, Sendable {
    var isAllLocked: Bool = false
    var lockedGroupIDs: Set<UUID> = []

    var isEmpty: Bool { !isAllLocked && lockedGroupIDs.isEmpty }

    static let none = RemoteLockState()
}

// MARK: - Errors

enum RemoteControlError: LocalizedError {
    case notPaired
    case iCloudUnavailable
    case pairingNotFound
    case invalidCode
    case wrongRole

    var errorDescription: String? {
        switch self {
        case .notPaired:
            String(localized: "This device isn't paired yet.")
        case .iCloudUnavailable:
            String(localized: "Sign in to iCloud in Settings to use remote control.")
        case .pairingNotFound:
            String(localized: "No parent device found for that code. Check the code and try again.")
        case .invalidCode:
            String(localized: "That pairing code isn't valid. Codes are 8 letters and numbers.")
        case .wrongRole:
            String(localized: "This action is only available on the parent device.")
        }
    }
}
