//
//  SchedulesView.swift
//  ParentLock
//
//  Unlimited parent-created schedules + Bedtime Mode.
//

import SwiftUI
import SwiftData
import FamilyControls

struct SchedulesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ScheduleEngine.self) private var scheduleEngine
    @Environment(BiometricAuthManager.self) private var auth
    @Query(sort: \BlockSchedule.createdAt) private var schedules: [BlockSchedule]

    @State private var showEditor = false
    @State private var editingSchedule: BlockSchedule?

    // Bedtime
    @AppStorage("bedtimeEnabled") private var bedtimeEnabled = false
    @AppStorage("bedtimeStartHour") private var bedtimeStartHour = 21
    @AppStorage("bedtimeEndHour") private var bedtimeEndHour = 7

    var body: some View {
        List {
            Section("Bedtime Mode") {
                Toggle(isOn: $bedtimeEnabled) {
                    Label("Bedtime \(bedtimeStartHour):00 – \(bedtimeEndHour):00",
                          systemImage: "moon.zzz.fill")
                }
                .onChange(of: bedtimeEnabled) { _, enabled in
                    Task {
                        guard (try? await auth.authenticateForAction(reason: "Change bedtime")) != nil else {
                            bedtimeEnabled = !enabled; return
                        }
                        if enabled {
                            scheduleEngine.activateBedtime(startHour: bedtimeStartHour, startMinute: 0,
                                                           endHour: bedtimeEndHour, endMinute: 0)
                        } else {
                            scheduleEngine.deactivateBedtime()
                        }
                    }
                }
                Stepper("Starts: \(bedtimeStartHour):00", value: $bedtimeStartHour, in: 18...23)
                Stepper("Ends: \(bedtimeEndHour):00", value: $bedtimeEndHour, in: 5...10)
            }

            Section("Schedules") {
                ForEach(schedules) { schedule in
                    Button {
                        editingSchedule = schedule
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(schedule.name).font(.headline)
                                Text(schedule.timeRangeText).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { schedule.isEnabled },
                                set: { enabled in
                                    schedule.isEnabled = enabled
                                    enabled ? scheduleEngine.activate(schedule)
                                            : scheduleEngine.deactivate(schedule)
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete(perform: delete)

                Button {
                    showEditor = true
                } label: {
                    Label("New Schedule", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Schedules")
        .sheet(isPresented: $showEditor) { ScheduleEditorView(schedule: nil) }
        .sheet(item: $editingSchedule) { ScheduleEditorView(schedule: $0) }
    }

    private func delete(at offsets: IndexSet) {
        Task {
            guard (try? await auth.authenticateForAction(reason: "Delete schedule")) != nil else { return }
            for index in offsets {
                scheduleEngine.deactivate(schedules[index])
                modelContext.delete(schedules[index])
            }
        }
    }
}

struct ScheduleEditorView: View {
    let schedule: BlockSchedule?
    @Environment(\.modelContext) private var modelContext
    @Environment(ScheduleEngine.self) private var scheduleEngine
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var startTime = Calendar.current.date(from: DateComponents(hour: 17)) ?? .now
    @State private var endTime = Calendar.current.date(from: DateComponents(hour: 19)) ?? .now
    @State private var blockedSelection = FamilyActivitySelection()
    @State private var allowedSelection = FamilyActivitySelection()
    @State private var showBlockedPicker = false
    @State private var showAllowedPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Homework", text: $name)
                }
                Section("Time") {
                    DatePicker("Starts", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: $endTime, displayedComponents: .hourAndMinute)
                }
                Section("Apps") {
                    Button("Blocked during this schedule…") { showBlockedPicker = true }
                    Button("Allowed during this schedule…") { showAllowedPicker = true }
                }
            }
            .navigationTitle(schedule == nil ? "New Schedule" : "Edit Schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold().disabled(name.isEmpty)
                }
            }
            .sheet(isPresented: $showBlockedPicker) {
                FamilyPickerSheet(title: "Blocked", selection: $blockedSelection)
            }
            .sheet(isPresented: $showAllowedPicker) {
                FamilyPickerSheet(title: "Allowed", selection: $allowedSelection)
            }
            .onAppear { load() }
        }
    }

    private func load() {
        guard let schedule else { return }
        name = schedule.name
        startTime = Calendar.current.date(from: DateComponents(hour: schedule.startHour, minute: schedule.startMinute)) ?? .now
        endTime = Calendar.current.date(from: DateComponents(hour: schedule.endHour, minute: schedule.endMinute)) ?? .now
        blockedSelection = schedule.blockedSelection
        allowedSelection = schedule.allowedSelection
    }

    private func save() {
        let startComponents = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        let endComponents = Calendar.current.dateComponents([.hour, .minute], from: endTime)

        let target = schedule ?? BlockSchedule(name: name,
                                               startHour: startComponents.hour ?? 0,
                                               startMinute: startComponents.minute ?? 0,
                                               endHour: endComponents.hour ?? 0,
                                               endMinute: endComponents.minute ?? 0)
        target.name = name
        target.startHour = startComponents.hour ?? 0
        target.startMinute = startComponents.minute ?? 0
        target.endHour = endComponents.hour ?? 0
        target.endMinute = endComponents.minute ?? 0
        target.blockedSelection = blockedSelection
        target.allowedSelection = allowedSelection

        if schedule == nil { modelContext.insert(target) }
        if target.isEnabled { scheduleEngine.activate(target) }
        dismiss()
    }
}
