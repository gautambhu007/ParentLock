//
//  ReportsView.swift
//  ParentLock
//
//  Daily / weekly / monthly reports with Swift Charts.
//
//  Note: Apple restricts raw Screen Time data to a DeviceActivityReport
//  extension (sandboxed UI). This view combines locally recorded
//  UsageRecords (blocked attempts, threshold events) with a slot where a
//  DeviceActivityReport view can be embedded for full usage detail.
//

import SwiftUI
import SwiftData
import Charts

enum ReportRange: String, CaseIterable, Identifiable {
    case daily = "Daily", weekly = "Weekly", monthly = "Monthly"
    var id: String { rawValue }

    var startDate: Date {
        let calendar = Calendar.current
        switch self {
        case .daily:   return calendar.startOfDay(for: .now)
        case .weekly:  return calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        case .monthly: return calendar.date(byAdding: .month, value: -1, to: .now) ?? .now
        }
    }
}

struct ReportsView: View {
    var initialRange: ReportRange = .daily
    @Query private var records: [UsageRecord]
    @State private var range: ReportRange = .daily

    private var filtered: [UsageRecord] {
        records.filter { $0.date >= range.startDate }
    }

    private var blockedAttempts: Int {
        let stored = SharedStorage.defaults.integer(forKey: SharedStorage.Key.blockedAttemptCount.rawValue)
        return stored + filtered.reduce(0) { $0 + $1.blockedAttempts }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("Range", selection: $range) {
                    ForEach(ReportRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                summaryCards

                GroupBox("Most Used Apps") {
                    if filtered.isEmpty {
                        ContentUnavailableView("No usage recorded yet",
                                               systemImage: "chart.bar",
                                               description: Text("Usage appears here as limits and schedules run."))
                    } else {
                        Chart(topApps, id: \.name) { item in
                            BarMark(x: .value("Minutes", item.minutes),
                                    y: .value("App", item.name))
                            .foregroundStyle(.blue.gradient)
                            .cornerRadius(6)
                        }
                        .frame(height: 220)
                    }
                }

                GroupBox("Education vs Entertainment") {
                    Chart(categoryTotals, id: \.category) { item in
                        SectorMark(angle: .value("Minutes", item.minutes),
                                   innerRadius: .ratio(0.6))
                            .foregroundStyle(by: .value("Category", item.category))
                    }
                    .frame(height: 200)
                }
            }
            .padding()
        }
        .navigationTitle("Reports")
        .onAppear { range = initialRange }
    }

    private var summaryCards: some View {
        HStack(spacing: 16) {
            statCard("Screen Time", "\(filtered.reduce(0) { $0 + $1.minutes }) min", "iphone", .teal)
            statCard("Blocked Attempts", "\(blockedAttempts)", "hand.raised.fill", .red)
        }
    }

    private func statCard(_ title: LocalizedStringKey, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(tint)
            Text(value).font(.title.bold()).contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
    }

    private var topApps: [(name: String, minutes: Int)] {
        Dictionary(grouping: filtered, by: \.appName)
            .map { (name: $0.key, minutes: $0.value.reduce(0) { $0 + $1.minutes }) }
            .sorted { $0.minutes > $1.minutes }
            .prefix(6)
            .map { $0 }
    }

    private var categoryTotals: [(category: String, minutes: Int)] {
        Dictionary(grouping: filtered, by: \.category)
            .map { (category: $0.key.capitalized, minutes: $0.value.reduce(0) { $0 + $1.minutes }) }
    }
}
