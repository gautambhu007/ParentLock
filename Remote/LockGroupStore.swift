//
//  LockGroupStore.swift
//  ParentLock
//
//  Named bundles of apps the parent can lock remotely ("Games", "Social").
//
//  The split matters: group *metadata* (id, name, symbol) is what syncs to the
//  parent device, while the FamilyActivitySelection behind each group never
//  leaves the device that picked it — ApplicationTokens are device-scoped and
//  meaningless anywhere else.
//

import Foundation
import FamilyControls
import Observation

@MainActor
@Observable
final class LockGroupStore {
    private(set) var groups: [RemoteLockGroup] {
        didSet { SharedStorage.saveCodable(groups, for: .lockGroups) }
    }

    /// Device-local selections keyed by group id.
    private(set) var selections: [UUID: FamilyActivitySelection] {
        didSet { SharedStorage.saveCodable(selections, for: .lockGroupSelections) }
    }

    init() {
        groups = SharedStorage.loadCodable([RemoteLockGroup].self, for: .lockGroups) ?? []
        selections = SharedStorage.loadCodable([UUID: FamilyActivitySelection].self, for: .lockGroupSelections) ?? [:]
    }

    func group(id: UUID) -> RemoteLockGroup? {
        groups.first { $0.id == id }
    }

    func name(for id: UUID) -> String? {
        group(id: id)?.name
    }

    func selection(for id: UUID) -> FamilyActivitySelection {
        selections[id] ?? FamilyActivitySelection()
    }

    @discardableResult
    func addGroup(named name: String, symbol: String = "square.grid.2x2.fill") -> RemoteLockGroup {
        let group = RemoteLockGroup(name: name, symbol: symbol)
        groups.append(group)
        return group
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = name
    }

    func setSymbol(_ symbol: String, for id: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].symbol = symbol
    }

    func setSelection(_ selection: FamilyActivitySelection, for id: UUID) {
        selections[id] = selection
    }

    func delete(_ id: UUID) {
        groups.removeAll { $0.id == id }
        selections[id] = nil
    }

    /// Replace the local group list with the one published by the child
    /// device. Parent-side only — the parent has no selections of its own.
    func replaceGroups(with remote: [RemoteLockGroup]) {
        groups = remote
    }

    func summary(for id: UUID) -> String {
        let selection = selection(for: id)
        let apps = selection.applicationTokens.count
        let categories = selection.categoryTokens.count
        if apps == 0 && categories == 0 { return String(localized: "No apps chosen yet") }
        return String(localized: "\(apps) apps · \(categories) categories")
    }
}
