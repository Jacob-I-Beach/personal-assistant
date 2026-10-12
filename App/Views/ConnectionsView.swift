import SwiftUI

struct ConnectionsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var destination: Destination?
    private enum Destination: String, Identifiable { case planning, context, health, folders, models, watch, computer, contacts; var id: String { rawValue } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bring your day into the conversation").font(.title3.weight(.semibold))
                        Text("Connect a source once, then use it naturally in chat. You choose what is available, and review changes before they happen.").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section("Your day") {
                    connection("Contacts", detail: "Find the right person for a reviewed message, email or call.", state: model.settings.contactsConnected && ContactsConnection.allowed ? "Connected" : "Choose access", icon: "person.crop.circle", destination: .contacts)
                    connection("Calendar & Reminders", detail: "Check your schedule, find time and save reviewed plans.", state: model.settings.calendarSourceIDs.isEmpty && model.settings.reminderSourceIDs.isEmpty ? "Choose sources" : "Sources selected", icon: "calendar", destination: .planning)
                    connection("Location & weather", detail: "Use your area for relevant requests and the Home greeting.", state: model.settings.locationContextEnabled ? "Context enabled" : "Choose access", icon: "location", destination: .context)
                    connection("Health", detail: "Connect measurements and records for relevant questions.", state: HealthOverviewService.isEnabledInThisBuild ? "Review Health access" : "Signing setup needed", icon: "heart", destination: .health)
                }
                Section("Your work") {
                    connection("Computer", detail: "Extra tools and background continuation when needed.", state: model.settings.companion == nil ? "Connect your PC" : model.settings.useComputer ? "Available when needed" : "Connected · optional tools off", icon: "desktopcomputer", destination: .computer)
                    connection("Folders & files", detail: "Read selected folders and review edits in place.", state: "Manage selected folders", icon: "folder", destination: .folders)
                    connection("Models", detail: "Choose connected intelligence or an on-device model.", state: model.modelTitle, icon: "sparkles", destination: .models)
                    connection("Apple Watch", detail: "See requests handed to your iPhone.", state: "Open requests", icon: "applewatch", destination: .watch)
                }
                Section("Also available in chat") {
                    Label("Research the web and check sources", systemImage: "globe")
                    Label("Create documents, charts and small tools", systemImage: "doc.badge.gearshape")
                    Label("Work from a photo, capture or document", systemImage: "viewfinder")
                    Label("Prepare a route, call or text for review", systemImage: "arrow.triangle.turn.up.right.diamond")
                    Text("Saved work, files and memory are in Library. Captured thoughts are in Inbox. The model can find the right tool when your request needs one.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Connections")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $destination) { destination in
                    switch destination {
                    case .planning: PlanningAccessView(service: model.planning)
                    case .context: HomeContextSettingsView()
                    case .health: HealthOverviewView()
                    case .folders: NavigationStack { ConnectedFoldersView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { self.destination = nil } } } }
                    case .models: ModelLibraryView()
                    case .watch: WatchRequestsView()
                    case .computer: ComputerConnectionView(openedTask: { id in
                        self.destination = nil; dismiss()
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            do { try await model.openComputerJob(id) } catch { model.errorMessage = error.localizedDescription }
                        }
                    })
                    case .contacts: ContactsConnectionView()
                    }
                }
        }
    }
    private func connection(_ title: String, detail: String, state: String, icon: String, destination: Destination) -> some View {
        Button { AppFeedback.play(.selection); self.destination = destination } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.title3).frame(width: 27).padding(.top, 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    Text(state).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 7).contentShape(Rectangle())
        }.buttonStyle(QuietPressStyle()).foregroundStyle(.primary)
    }
}
