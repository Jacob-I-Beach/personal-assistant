import AssistantCore
import EventKit
import EventKitUI
import MessageUI
import SwiftUI

struct NativeActionRequest: Identifiable, Sendable {
    enum Kind: Sendable { case approval, calendar, message }
    let id = UUID()
    var kind: Kind
    var title: String
    var detail: String
    var arguments: JSONValue
}

struct NativeActionView: View {
    @EnvironmentObject private var model: AppModel
    let request: NativeActionRequest
    var body: some View {
        Group {
            switch request.kind {
            case .approval:
                NavigationStack {
                    VStack(alignment: .leading, spacing: 22) {
                        Text(request.title).font(.title2.weight(.semibold))
                        Text(request.detail).foregroundStyle(.secondary)
                        Spacer()
                        Button { model.resolveNativeAction("approved") } label: { Text("Continue").fontWeight(.semibold).frame(maxWidth: .infinity).padding(8).foregroundStyle(Color(uiColor: .systemBackground)) }
                            .buttonStyle(.borderedProminent).tint(.primary)
                        Button("Cancel", role: .cancel) { model.resolveNativeAction("cancelled") }.frame(maxWidth: .infinity)
                    }.padding(24).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.resolveNativeAction("cancelled") } } }
                }.presentationDetents([.medium, .large])
            case .calendar:
                CalendarEventEditor(arguments: request.arguments) { model.resolveNativeAction($0) }
            case .message:
                TextMessageEditor(arguments: request.arguments) { model.resolveNativeAction($0) }
            }
        }.interactiveDismissDisabled()
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
