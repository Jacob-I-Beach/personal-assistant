import AssistantCore
import SwiftUI

struct HealthDataAccessView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selected: Set<String> = []
    @State private var search = ""
    @State private var busy = false
    @State private var notice: String?
    @AppStorage("assistant.health.selectionDraft") private var selectionDraft = ""
    private var entries: [HealthDataType] { HealthDataCatalog.matching(search) }
    private var isFiltering: Bool { !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var groups: [String] { Array(Set(entries.map(\.group))).sorted() }
    private var supported: Set<String> { Set(HealthDataCatalog.entries.filter { HealthDataReader.objectType($0) != nil }.map(\.id)) }
    var body: some View {
        List {
            Section {
                if !isFiltering {
                    Text("Choose what your assistant can read when it is relevant.").font(.headline)
                    Text("Health asks which records you want to share. Selecting a type here does not send its history to a model; reads use the types and dates needed for your request.").font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Button("Select all available") { selected = supported; AppFeedback.play(.selection) }
                        Spacer()
                        Button("Clear") { selected = []; AppFeedback.play(.selection) }
                    }.buttonStyle(.borderless)
                }
                Text("\(selected.intersection(supported).count) selected · \(supported.count) available").font(.caption).foregroundStyle(.secondary)
                Button {
                    busy = true; notice = nil
                    Task {
                        defer { busy = false }
                        do {
                            if !selected.isEmpty { try await HealthDataReader().requestAccess(selected) }
                            var settings = model.settings; settings.healthTypeIDs = selected.intersection(supported); settings.healthToolsEnabled = !selected.isEmpty
                            try model.saveSettings(settings); AppFeedback.play(.saved)
                            selectionDraft = ""
                            notice = selected.isEmpty ? "Assistant Health reads are off. Existing Health permissions can be managed in iPhone Settings." : "Your selection is saved. Health controls which read records are shared."
                        } catch { notice = "Health access could not be updated. " + error.localizedDescription }
                    }
                } label: { Text(busy ? "Saving…" : selected.isEmpty ? "Turn off Health reads" : "Connect selected data").frame(maxWidth: .infinity).foregroundStyle(Color(uiColor: .systemBackground)) }
                    .buttonStyle(.borderedProminent).tint(.primary).disabled(busy || !HealthOverviewService.isEnabledInThisBuild || model.isRunning)
                if let notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                if !isFiltering && !HealthOverviewService.isEnabledInThisBuild { Text(HealthOverviewService.signingMessage).font(.footnote).foregroundStyle(.secondary) }
            }
            ForEach(groups, id: \.self) { group in
                Section(group) {
                    ForEach(entries.filter { $0.group == group }) { entry in
                        let available = HealthDataReader.objectType(entry) != nil
                        Toggle(isOn: Binding(get: { selected.contains(entry.id) }, set: { enabled in
                            if enabled { selected.insert(entry.id) } else { selected.remove(entry.id) }; AppFeedback.play(.selection)
                        })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name)
                                if !available { Text(entry.kind == "clinical" ? "Clinical-record access is not available in this installation." : "Not available on this system.").font(.caption).foregroundStyle(.secondary) }
                            }
                        }.disabled(!available || busy)
                    }
                }
            }
            if !isFiltering {
                Section {
                    Text("This covers the data HealthKit exposes, including detailed measurements and supported specialist records. Health's own private insights, sharing settings and unavailable clinical connections are separate. Empty reads do not reveal whether permission was denied.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Connected Health data").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Find a measurement or category")
        .onAppear {
            if let data = selectionDraft.data(using: .utf8), let ids = try? JSONDecoder().decode([String].self, from: data) {
                selected = Set(ids).intersection(Set(HealthDataCatalog.entries.map(\.id)))
            } else { selected = model.settings.healthTypeIDs }
        }
        .onChange(of: selected) { _, ids in
            if let data = try? JSONEncoder().encode(ids.sorted()) { selectionDraft = String(decoding: data, as: UTF8.self) }
        }
    }
}
