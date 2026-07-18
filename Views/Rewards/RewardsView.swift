//
//  RewardsView.swift
//  ParentLock
//
//  Task → reward flow with confetti when a reward is redeemed.
//

import SwiftUI
import SwiftData

struct RewardsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RewardEngine.self) private var rewardEngine
    @Environment(BiometricAuthManager.self) private var auth
    @Query(sort: \Reward.createdAt, order: .reverse) private var rewards: [Reward]

    @State private var showEditor = false
    @State private var showConfetti = false

    var body: some View {
        List {
            Section("Waiting") {
                ForEach(rewards.filter { !$0.isCompleted }) { reward in
                    RewardRow(reward: reward) { redeem(reward) }
                }
            }
            Section("Completed") {
                ForEach(rewards.filter(\.isCompleted)) { reward in
                    VStack(alignment: .leading) {
                        Text(reward.taskDescription).strikethrough()
                        if reward.isActive, let expiry = reward.expiresAt {
                            Text("Unlocked until \(expiry.formatted(date: .omitted, time: .shortened))")
                                .font(.footnote).foregroundStyle(.green)
                        }
                    }
                }
            }
            Button { showEditor = true } label: {
                Label("New Reward", systemImage: "plus")
            }
        }
        .navigationTitle("Rewards")
        .sheet(isPresented: $showEditor) { RewardEditorView() }
        .overlay { if showConfetti { ConfettiView().allowsHitTesting(false) } }
    }

    private func redeem(_ reward: Reward) {
        Task {
            guard (try? await auth.authenticateForAction(reason: "Redeem reward")) != nil else { return }
            withAnimation(.bouncy) { rewardEngine.redeem(reward) }
            showConfetti = true
            try? await Task.sleep(for: .seconds(2.5))
            showConfetti = false
        }
    }
}

private struct RewardRow: View {
    let reward: Reward
    let onRedeem: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(reward.taskDescription).font(.headline)
                Label("\(reward.unlockDescription) · \(reward.unlockMinutes) min",
                      systemImage: "gift.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done!", action: onRedeem)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
    }
}

struct RewardEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var task = ""
    @State private var unlock = ""
    @State private var minutes = 30

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task (e.g. Complete homework)", text: $task)
                TextField("Reward (e.g. Unlock games)", text: $unlock)
                Stepper("\(minutes) minutes", value: $minutes, in: 5...120, step: 5)
            }
            .navigationTitle("New Reward")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        modelContext.insert(Reward(taskDescription: task,
                                                   unlockDescription: unlock,
                                                   unlockMinutes: minutes))
                        dismiss()
                    }
                    .bold()
                    .disabled(task.isEmpty || unlock.isEmpty)
                }
            }
        }
    }
}

/// Lightweight confetti burst using pure SwiftUI.
struct ConfettiView: View {
    @State private var animate = false
    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<40, id: \.self) { index in
                    Circle()
                        .fill(colors[index % colors.count])
                        .frame(width: 10, height: 10)
                        .position(x: .random(in: 0...proxy.size.width),
                                  y: animate ? proxy.size.height + 30 : -30)
                        .animation(.easeIn(duration: .random(in: 1.2...2.4))
                                    .delay(.random(in: 0...0.5)),
                                   value: animate)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { animate = true }
    }
}
