//
//  Models.swift
//  ParentLock
//
//  SwiftData models. FamilyActivitySelection tokens are opaque and Codable,
//  so selections are stored as encoded Data blobs.
//

import Foundation
import SwiftData
import FamilyControls

// MARK: - Schedules

@Model
final class BlockSchedule {
    @Attribute(.unique) var id: UUID
    var name: String
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var isEnabled: Bool
    /// Encoded FamilyActivitySelection of blocked apps during this schedule.
    var blockedSelectionData: Data?
    /// Encoded FamilyActivitySelection of apps allowed during this schedule.
    var allowedSelectionData: Data?
    var createdAt: Date

    init(name: String, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) {
        self.id = UUID()
        self.name = name
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.isEnabled = true
        self.createdAt = .now
    }

    var blockedSelection: FamilyActivitySelection {
        get { blockedSelectionData.flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) } ?? FamilyActivitySelection() }
        set { blockedSelectionData = try? JSONEncoder().encode(newValue) }
    }

    var allowedSelection: FamilyActivitySelection {
        get { allowedSelectionData.flatMap { try? JSONDecoder().decode(FamilyActivitySelection.self, from: $0) } ?? FamilyActivitySelection() }
        set { allowedSelectionData = try? JSONEncoder().encode(newValue) }
    }

    var timeRangeText: String {
        String(format: "%d:%02d – %d:%02d", startHour, startMinute, endHour, endMinute)
    }
}

// MARK: - Daily limits

@Model
final class AppLimit {
    @Attribute(.unique) var id: UUID
    var name: String              // e.g. "YouTube"
    var minutesPerDay: Int
    var isEnabled: Bool
    var createdAt: Date

    init(name: String, minutesPerDay: Int) {
        self.id = UUID()
        self.name = name
        self.minutesPerDay = minutesPerDay
        self.isEnabled = true
        self.createdAt = .now
    }
}

// MARK: - Rewards

@Model
final class Reward {
    @Attribute(.unique) var id: UUID
    var taskDescription: String   // "Complete homework"
    var unlockDescription: String // "Unlock games"
    var unlockMinutes: Int
    var isCompleted: Bool
    var redeemedAt: Date?
    /// Encoded selection to unlock when redeemed.
    var unlockSelectionData: Data?
    var createdAt: Date

    init(taskDescription: String, unlockDescription: String, unlockMinutes: Int) {
        self.id = UUID()
        self.taskDescription = taskDescription
        self.unlockDescription = unlockDescription
        self.unlockMinutes = unlockMinutes
        self.isCompleted = false
        self.createdAt = .now
    }

    var expiresAt: Date? {
        redeemedAt?.addingTimeInterval(TimeInterval(unlockMinutes * 60))
    }

    var isActive: Bool {
        guard let expiresAt else { return false }
        return expiresAt > .now
    }
}

// MARK: - Usage / reports

@Model
final class UsageRecord {
    var date: Date
    var appName: String
    var minutes: Int
    var category: String          // "education" | "entertainment" | "other"
    var blockedAttempts: Int

    init(date: Date, appName: String, minutes: Int, category: String, blockedAttempts: Int = 0) {
        self.date = date
        self.appName = appName
        self.minutes = minutes
        self.category = category
        self.blockedAttempts = blockedAttempts
    }
}

// MARK: - Profiles & preferences

@Model
final class ChildProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var avatarSymbol: String
    var createdAt: Date

    init(name: String, avatarSymbol: String = "person.crop.circle.fill") {
        self.id = UUID()
        self.name = name
        self.avatarSymbol = avatarSymbol
        self.createdAt = .now
    }
}

@Model
final class ParentPreferences {
    var accentColorName: String
    var notificationsEnabled: Bool
    var faceIDRequired: Bool
    var autoLockSeconds: Int

    init() {
        self.accentColorName = "blue"
        self.notificationsEnabled = true
        self.faceIDRequired = true
        self.autoLockSeconds = 60
    }
}
