import AssistantCore
import SwiftUI

struct PlanningAccessView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var service: PlanningService
    var finish: ((String) -> Void)? = nil
    @State private var calendars = Set<String>()
    @State private var lists = Set<String>()
    @State private var connected = false
    @State private var error: String?
    @State private var connecting = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose what the assistant can use").font(.headline)
                    Text("Your selection is remembered for future tasks. Reads use only these sources; changes are shown for review before saving.").foregroundStyle(.secondary)
                }
                sourceSection("Calendar", kind: "calendar", selected: $calendars)
                sourceSection("Reminders", kind: "reminder", selected: $lists)
                Section {
                    Toggle("Use with connected models", isOn: $connected)
                    Text("Relevant event and reminder details can be sent to your selected model when a task needs them. The Today view itself reads on this iPhone.").font(.footnote).foregroundStyle(.secondary)
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Button("iPhone permission settings", systemImage: "gearshape") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                }
            }.navigationTitle("Planning access").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { finish?("cancelled"); dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        do { try model.setPlanningAccess(calendars: Array(calendars), reminders: Array(lists), connected: connected); finish?("approved"); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(connecting) }
                }
                .onAppear { calendars = Set(model.settings.calendarSourceIDs); lists = Set(model.settings.reminderSourceIDs); connected = model.settings.planningConnectedAccess; service.refreshSources() }
        }
    }
    private func sourceSection(_ title: String, kind: String, selected: Binding<Set<String>>) -> some View {
        Section(title) {
            let sources = service.sources.filter { $0.kind == kind }
            if sources.isEmpty {
                Button(connecting ? "Connecting…" : "Connect \(title)") {
                    connecting = true
                    Task { defer { connecting = false }; do { try await service.connect(kind) } catch { self.error = error.localizedDescription } }
                }.disabled(connecting)
            }
            ForEach(sources) { source in
                Toggle(isOn: Binding(get: { selected.wrappedValue.contains(source.id) }, set: { if $0 { selected.wrappedValue.insert(source.id) } else { selected.wrappedValue.remove(source.id) } })) {
                    VStack(alignment: .leading) { Text(source.title); if !source.writable { Text("Read only").font(.caption).foregroundStyle(.secondary) } }
                }
            }
            if !sources.isEmpty { Button("Select all \(title.lowercased())") { selected.wrappedValue = Set(sources.map(\.id)) } }
        }
    }
}
