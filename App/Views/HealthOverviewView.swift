import AssistantCore
import Charts
import SwiftUI

struct HealthOverviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var service = HealthOverviewService()
    @State private var report: HealthOverview?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("A clearer view of your week", systemImage: "heart.text.square").font(.title3.weight(.semibold))
                        Text("A quick look at your week, with a broader Health connection for the questions that need it.").foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                    Button(report == nil ? "Connect Health context" : "Review Health access") { load(requestAccess: true) }.disabled(loading || !service.isAvailable || model.isRunning)
                    NavigationLink("Connected data · \(model.settings.healthTypeIDs.count) types", destination: HealthDataAccessView())
                    Text(HealthOverviewService.isEnabledInThisBuild ? "After connecting, on-device models can refresh these overviews when you ask. Connected models can do so only in conversations where you've allowed Health sharing." : HealthOverviewService.signingMessage).font(.footnote).foregroundStyle(.secondary)
                    if loading { ProgressView("Reading selected Health data") }
                    if let error { Text(error).foregroundStyle(.secondary).font(.footnote) }
                }
                if let report {
                    Section("Steps") {
                        if report.days.contains(where: { $0.steps != nil }) {
                            Chart(report.days) { day in
                                if let steps = day.steps { BarMark(x: .value("Day", day.date, unit: .day), y: .value("Steps", steps)).cornerRadius(4) }
                            }.frame(height: 170).accessibilityLabel("Daily recorded steps")
                        } else { Text("No step data was shared for this period.").foregroundStyle(.secondary) }
                    }
                    Section("Recorded sleep by calendar day") {
                        if report.days.contains(where: { $0.sleepHours != nil }) {
                            Chart(report.days) { day in
                                if let hours = day.sleepHours { BarMark(x: .value("Day", day.date, unit: .day), y: .value("Hours", hours)).cornerRadius(4).foregroundStyle(.indigo) }
                            }.frame(height: 170).accessibilityLabel("Recorded sleep hours by calendar day")
                        } else { Text("No sleep data was shared for this period.").foregroundStyle(.secondary) }
                        Text("Overlapping asleep records are counted once. Calendar-day totals may differ from Health's nightly view.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Workouts") {
                        if report.workouts.isEmpty { Text("No workouts were shared for this period.").foregroundStyle(.secondary) }
                        ForEach(report.workouts.prefix(12)) { workout in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text(workout.activity); Spacer(); Text("\(workout.minutes, format: .number.precision(.fractionLength(0))) min") }
                                Text("\(workout.start.formatted(date: .abbreviated, time: .shortened)) · \(workout.source)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Sources and coverage") {
                        Text("\(report.rangeStart.formatted(date: .abbreviated, time: .omitted)) through \(report.rangeEnd.formatted())").font(.subheadline)
                        Text(report.timeZoneIdentifier).font(.caption).foregroundStyle(.secondary)
                        Text(report.coverageNote).font(.footnote).foregroundStyle(.secondary)
                        if !report.sleepSources.isEmpty { Text("Sleep sources: " + report.sleepSources.joined(separator: ", ")).font(.caption) }
                    }
                    Section {
                        Button("Discuss in a new conversation", systemImage: "bubble.left.and.bubble.right") {
                            model.composeHealthOverview(report); dismiss()
                        }.disabled(model.isRunning)
                        Text("You can review the summary before sending it. Sharing it with a connected model requires a separate choice.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Health overview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if report != nil { ToolbarItem(placement: .topBarTrailing) { Button("Refresh", systemImage: "arrow.clockwise") { load(requestAccess: false) }.disabled(loading) } }
            }
        }
    }
    private func load(requestAccess: Bool) {
        loading = true; error = nil
        Task {
            defer { loading = false }
            do {
                if requestAccess { try await HealthDataReader().requestAccess(model.settings.healthTypeIDs); try model.enableHealthTools() }
                report = try await service.overview(selected: model.settings.healthTypeIDs)
            } catch { self.error = "Health data could not be read. Unlock your phone, review the shared data types, and try again. " + error.localizedDescription }
        }
    }
}
