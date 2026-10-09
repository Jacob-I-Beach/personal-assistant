import SwiftUI

struct WatchRequestsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(model.watchRequests) { request in
                VStack(alignment: .leading, spacing: 8) {
                    Text(request.text)
                    Text(request.createdAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    Button("Continue on iPhone") { Task { await model.resumeWatchRequest(request); dismiss() } }
                        .disabled(model.isRunning || model.needsNetworkConsent)
                }.padding(.vertical, 5)
            }
            .overlay { if model.watchRequests.isEmpty { ContentUnavailableView("No waiting requests", systemImage: "applewatch", description: Text("Ask or capture a thought from the Watch companion. Requests wait here when the phone is unavailable.")) } }
            .navigationTitle("Watch requests")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await model.refresh() }
        }
    }
}
