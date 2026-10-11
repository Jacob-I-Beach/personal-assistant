import AssistantCore
import EventKit
import EventKitUI
import MessageUI
import SwiftUI

struct NativeActionRequest: Identifiable, Sendable {
    enum Kind: Sendable, Equatable { case approval, calendar, message, folder, exportFile, fileEdit, placeSelection, planningConnection, question }
    let id = UUID()
    var kind: Kind
    var title: String
    var detail: String
    var arguments: JSONValue
    var fileURL: URL?
    var proposal: FileEditProposal?
    var places: [RoutePlace] = []
    var questionID: UUID?
}

struct NativeActionView: View {
    @EnvironmentObject private var model: AppModel
    let request: NativeActionRequest
    var body: some View {
        Group {
            switch request.kind {
            case .planningConnection:
                PlanningAccessView(service: model.planning) { model.resolveNativeAction($0, for: request.id) }
            case .question:
                if let id = request.questionID { TaskQuestionView(questionID: id) }
            case .placeSelection:
                NavigationStack {
                    List {
                        Section { Text(request.detail).font(.subheadline).foregroundStyle(.secondary) }
                        ForEach(request.places) { place in
                            Button { model.resolveNativeAction(place.id.uuidString, for: request.id) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "mappin.and.ellipse").foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(place.name).foregroundStyle(.primary)
                                        Text(place.address).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 6)
                            }
                        }
                    }.navigationTitle(request.title).navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.resolveNativeAction("cancelled", for: request.id) } } }
                }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            case .approval:
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(request.title).font(.title2.weight(.semibold))
                            Text(request.detail).foregroundStyle(.secondary).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    }
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 12) {
                            Button { model.resolveNativeAction("approved", for: request.id) } label: { Text("Continue").fontWeight(.semibold).frame(maxWidth: .infinity).padding(8).foregroundStyle(Color(uiColor: .systemBackground)) }
                                .buttonStyle(.borderedProminent).tint(.primary)
                            Button("Cancel", role: .cancel) { model.resolveNativeAction("cancelled", for: request.id) }.frame(maxWidth: .infinity)
                        }.padding(20).background(.bar)
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.resolveNativeAction("cancelled", for: request.id) } } }
                }.presentationDetents([.medium, .large])
            case .calendar:
                CalendarEventEditor(arguments: request.arguments) { model.resolveNativeAction($0, for: request.id) }
            case .message:
                TextMessageEditor(arguments: request.arguments) { model.resolveNativeAction($0, for: request.id) }
            case .folder:
                FolderPicker { url in
                    guard model.isPendingNativeAction(request.id) else { return }
                    model.pickedFolderURL = url; model.resolveNativeAction(url == nil ? "cancelled" : "selected", for: request.id)
                }
            case .exportFile:
                if let url = request.fileURL { DocumentExportPicker(url: url) { model.resolveNativeAction($0, for: request.id) } }
            case .fileEdit:
                if let proposal = request.proposal { FileEditReviewView(proposal: proposal) { model.resolveNativeAction($0, for: request.id) } }
            }
        }
        .interactiveDismissDisabled(request.kind != .folder && request.kind != .exportFile)
        .onDisappear {
            if request.kind == .folder || request.kind == .exportFile {
                model.resolveNativeAction("cancelled", for: request.id)
            }
        }
    }
}

private struct CalendarEventEditor: UIViewControllerRepresentable {
    let arguments: JSONValue
    let complete: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(complete) }
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController(), store = EKEventStore()
        controller.eventStore = store
        let event = EKEvent(eventStore: store)
        event.title = arguments["title"]?.stringValue
        event.notes = arguments["notes"]?.stringValue
        event.location = arguments["location"]?.stringValue
        event.startDate = ISO8601DateFormatter().date(from: arguments["start"]?.stringValue ?? "")
        event.endDate = ISO8601DateFormatter().date(from: arguments["end"]?.stringValue ?? "")
        controller.event = event; controller.editViewDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let complete: (String) -> Void
        init(_ complete: @escaping (String) -> Void) { self.complete = complete }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { complete(action == .saved ? "saved" : "cancelled") }
    }
}

private struct TextMessageEditor: UIViewControllerRepresentable {
    let arguments: JSONValue
    let complete: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(complete) }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        let recipients = (arguments["recipients"]?.stringValue ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        controller.recipients = recipients; controller.body = arguments["body"]?.stringValue; controller.messageComposeDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let complete: (String) -> Void
        init(_ complete: @escaping (String) -> Void) { self.complete = complete }
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            complete(result == .sent ? "sent" : result == .cancelled ? "cancelled" : "failed")
        }
    }
}
