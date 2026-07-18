//
//  DailyLimitsView.swift
//  ParentLock
//
//  Per-app daily time limits (e.g. YouTube 30 min/day). Usage resets at
//  midnight via the DeviceActivity interval.
//

import SwiftUI
import SwiftData
import FamilyControls

struct DailyLimitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DailyLimitEngine.self) private var limitEngine
    @Environment(SelectionStore.self) private var selectionStore
    @Environment(BiometricAuthManager.self) private var auth
    @Query(sort: \AppLimit.createdAt) private var limits: [AppLimit]

    @State private var showEditor = false

    var body: some View {
        List {
            ForEach(limits) { limit in
                HStack {
                    VStack(alignment: .leading) {
                        Text(limit.name).font(.headline)
                        Text("\(limit.minutesPerDay) minutes per day")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { limit.isEnabled },
                        set: { enabled in
                            limit.isEnabled = enabled
                            enabled ? limitEngine.activate(limit) : limitEngine.deactivate(limit)
                        }
                    ))
                    .labelsHidden()
                }
            }
            .onDelete(perform: delete)

            Button { showEditor = true } label: {
                Label("New Limit", systemImage: "plus")
            }
        }
        .navigationTitle("Daily Limits")
        .sheet(isPresented: $showEditor) { LimitEditorView() }
    }

    private func delete(at offsets: IndexSet) {
        Task {
            guard (try? await auth.authenticateForAction(reason: "Delete limit")) != nil else { return }
            for index in offsets {
                limitEngine.deactivate(limits[index])
                modelContext.delete(limits[index])
            }
        }
    }
}

struct LimitEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DailyLimitEngine.self) private var limitEngine
    @Environment(SelectionStore.self) private var selectionStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var minutes = 30
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. YouTube)", text: $name)
                Stepper("\(minutes) minutes per day", value: $minutes, in: 5...240, step: 5)
                Button("Choose Apps…") { showPicker = true }
            }
            .navigationTitle("New Limit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold().disabled(name.isEmpty)
                }
            }
            .sheet(isPresented: $showPicker) {
                FamilyPickerSheet(title: "Limited Apps", selection: $selection)
            }
        }
    }

    private func save() {
        let limit = AppLimit(name: name, minutesPerDay: minutes)
        modelContext.insert(limit)
        selectionStore.limitSelections[limit.id] = selection
        limitEngine.activate(limit)
        dismiss()
    }
}
