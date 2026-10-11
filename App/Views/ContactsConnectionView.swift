import SwiftUI
import Contacts

struct ContactsConnectionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Start with a person’s name", systemImage: "person.crop.circle").font(.title3.weight(.semibold))
                    Text("Ask for Alex instead of finding a number yourself. iOS controls which contacts are available. The assistant asks when more than one person or number could fit.").foregroundStyle(.secondary)
                }
                Section {
                    if model.settings.contactsConnected && ContactsConnection.allowed {
                        Label("Contacts connected", systemImage: "checkmark.circle")
                        Button("Turn off in this app") { save(false) }
                    } else {
                        Button("Connect Contacts") { Task {
                            do { let allowed = try await ContactsConnection.connect(); if allowed { save(true) } else { error = "Allow selected contacts in iPhone Settings to connect them here." } }
                            catch { self.error = error.localizedDescription }
                        } }
                    }
                    Button("Manage iOS access") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    Text("Only requested search matches enter the conversation. Sending a text or email still opens a native review where you control Send.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Contacts")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func save(_ enabled: Bool) {
        do { var next = model.settings; next.contactsConnected = enabled; try model.saveSettings(next); AppFeedback.play(.selection) }
        catch { self.error = error.localizedDescription }
    }
}
