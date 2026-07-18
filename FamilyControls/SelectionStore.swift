//
//  SelectionStore.swift
//  ParentLock
//
//  Owns the FamilyActivitySelections (blocked / allowed / bedtime exceptions)
//  and persists them to the shared App Group so extensions can read them.
//

import Foundation
import FamilyControls
import Observation

@MainActor
@Observable
final class SelectionStore {
    var blockedSelection: FamilyActivitySelection {
        didSet { SharedStorage.saveCodable(blockedSelection, for: .blockedSelection) }
    }
    var allowedSelection: FamilyActivitySelection {
        didSet { SharedStorage.saveCodable(allowedSelection, for: .allowedSelection) }
    }
    var bedtimeExceptions: FamilyActivitySelection {
        didSet { SharedStorage.saveCodable(bedtimeExceptions, for: .bedtimeSelection) }
    }
    /// Per-limit selections keyed by the SwiftData AppLimit id.
    var limitSelections: [UUID: FamilyActivitySelection] {
        didSet { SharedStorage.saveCodable(limitSelections, for: .limitSelections) }
    }

    init() {
        blockedSelection = SharedStorage.loadCodable(FamilyActivitySelection.self, for: .blockedSelection) ?? FamilyActivitySelection()
        allowedSelection = SharedStorage.loadCodable(FamilyActivitySelection.self, for: .allowedSelection) ?? FamilyActivitySelection()
        bedtimeExceptions = SharedStorage.loadCodable(FamilyActivitySelection.self, for: .bedtimeSelection) ?? FamilyActivitySelection()
        limitSelections = SharedStorage.loadCodable([UUID: FamilyActivitySelection].self, for: .limitSelections) ?? [:]
    }

    var blockedSummary: String {
        let apps = blockedSelection.applicationTokens.count
        let categories = blockedSelection.categoryTokens.count
        let domains = blockedSelection.webDomainTokens.count
        return "\(apps) apps · \(categories) categories · \(domains) domains"
    }
}
