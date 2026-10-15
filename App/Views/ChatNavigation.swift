import Foundation
import AssistantCore
import SwiftUI

enum ChatDestination: Hashable, Identifiable {
    case artifact(UUID), file(UUID), capture(UUID), surface(UUID, selectedRevision: Int?), outputs(UUID)
    var id: String {
        switch self { case .artifact(let id): "artifact-" + id.uuidString; case .file(let id): "file-" + id.uuidString; case .capture(let id): "capture-" + id.uuidString; case .surface(let id, _): "surface-" + id.uuidString; case .outputs(let id): "outputs-" + id.uuidString }
    }
}
@MainActor
final class ChatNavigation: ObservableObject {
    @Published var destination: ChatDestination?
    @Published var keyboardDismissalRequest = UUID()
    func dismissKeyboard() { keyboardDismissalRequest = UUID() }
    weak var model: AppModel?
    var showLibrary: Bool { get { model?.rootPresentation == .library } set { if newValue { model?.present(.library) } else { model?.dismissPresentation(.library) } } }
    var showConnections: Bool { get { model?.rootPresentation == .connections } set { if newValue { model?.present(.connections) } else { model?.dismissPresentation(.connections) } } }
    @Published var historyQuery = ""
    @Published var historyMatches: [HistoryMatch] = []
    @Published var selectedHistoryMatchID: UUID?
    @Published var restoreHistoryPosition = false
    @Published var searchLanding: HistoryLanding?
    @Published var showHistoryRequest = UUID()
    func returnToSearch() { restoreHistoryPosition = true; showHistoryRequest = UUID() }
    @Published private(set) var dismissalRequest = UUID()
    @Published private(set) var routingReady = UUID()
    private(set) var pendingContext: ContextualDraftProposal?
    private(set) var pendingComputerJob: String?
    private(set) var waitsForDismissal = false
    func compose(_ proposal: ContextualDraftProposal, afterDismissal: Bool) {
        pendingContext = proposal; pendingComputerJob = nil; waitsForDismissal = afterDismissal
        destination = nil; dismissalRequest = UUID()
    }
    func openComputerJob(_ id: String) {
        pendingComputerJob = id; pendingContext = nil; waitsForDismissal = true; dismissalRequest = UUID()
    }
    func presentationDidDismiss() { waitsForDismissal = false; routingReady = UUID() }
    func takeContext() -> ContextualDraftProposal? { defer { pendingContext = nil }; return pendingContext }
    func takeComputerJob() -> String? { defer { pendingComputerJob = nil }; return pendingComputerJob }
}
