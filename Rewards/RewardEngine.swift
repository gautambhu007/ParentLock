//
//  RewardEngine.swift
//  ParentLock
//
//  Redeems rewards: temporarily lifts the shield for the reward's selection,
//  then restores it when the reward expires.
//

import Foundation
import FamilyControls
import Observation

@MainActor
@Observable
final class RewardEngine {
    private let shieldManager: ShieldManager
    private var expiryTasks: [UUID: Task<Void, Never>] = [:]

    init(shieldManager: ShieldManager) {
        self.shieldManager = shieldManager
    }

    /// Parent marks the task complete (after Face ID) → unlock for N minutes.
    func redeem(_ reward: Reward) {
        reward.isCompleted = true
        reward.redeemedAt = .now

        // Simple approach: lift all shields for the reward window.
        // For per-app precision, subtract the reward selection from the
        // manual store instead.
        shieldManager.temporarilyUnlockAll(for: TimeInterval(reward.unlockMinutes * 60))

        expiryTasks[reward.id]?.cancel()
        expiryTasks[reward.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(reward.unlockMinutes * 60))
            guard !Task.isCancelled else { return }
            self?.expiryTasks[reward.id] = nil
            // ShieldManager restores shields itself when its timer fires.
        }
    }

    func cancelExpiry(for reward: Reward) {
        expiryTasks[reward.id]?.cancel()
        expiryTasks[reward.id] = nil
    }
}
