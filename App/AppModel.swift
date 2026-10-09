import AssistantCore
import Combine
import Foundation
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published var conversation = Conversation()
    @Published var histories: [Conversation] = []
    @Published var captures: [CaptureObservation] = []
    @Published var attachedCaptureIDs: [UUID] = []
    @Published var isRunning = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var modelStatus = "Model has not been loaded"
    @Published var errorMessage: String?
    @Published var settings = ModelSettings()
    @Published var needsNetworkConsent = false
    private(set) var store: LocalStore?
    private var engine: AssistantEngine?
    private var localBackend: MLXLocalBackend?
    private var responseTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var settingsURL: URL?
    private var modelRoot: URL?
    private var pendingText: String?

    init() {
        do {
            let root = try PrivatePaths.root()
            let store = try LocalStore(root: root.appendingPathComponent("data"))
            self.store = store; self.engine = AssistantEngine(store: store)
            self.settingsURL = root.appendingPathComponent("settings.json")
            self.modelRoot = root.appendingPathComponent("models")
            if let settingsURL, FileManager.default.fileExists(atPath: settingsURL.path) {
                settings = try JSONDecoder().decode(ModelSettings.self, from: Data(contentsOf: settingsURL))
            }
            rebuildLocalBackend()
            Task { await refresh() }
        } catch { errorMessage = error.localizedDescription }
    }
    func refresh() async {
        guard let store else { return }
        do { histories = try await store.conversations(); captures = try await store.captures() }
        catch { errorMessage = error.localizedDescription }
    }
    func newConversation() { guard !isRunning else { return }; conversation = Conversation(); attachedCaptureIDs = [] }
    func selectConversation(_ value: Conversation) { guard !isRunning else { return }; conversation = value; attachedCaptureIDs = [] }
    func attach(_ id: UUID) { if !attachedCaptureIDs.contains(id) { attachedCaptureIDs.append(id) } }
    func saveCapture(_ capture: CaptureObservation, jpeg: Data) async -> Bool {
        guard let store else { return false }
        do { try await store.saveCapture(capture, jpeg: jpeg); attach(capture.id); await refresh(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    func image(_ id: UUID) async -> UIImage? {
        guard let store, let data = try? await store.imageData(id) else { return nil }
        return UIImage(data: data)
    }
    func captureURL(_ id: UUID) async -> URL? { try? await store?.captureManifestURL(id) }
    func captureExportURLs(_ id: UUID) async -> [URL] {
        guard let store else { return [] }
        do {
            let manifest = try await store.captureManifestURL(id)
            let image = try await store.captureImageURL(id)
            return [manifest, image]
        }
        catch { errorMessage = error.localizedDescription; return [] }
    }

    func send(_ text: String) {
        guard !isRunning, !isDownloading, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let destination = settings.endpoint?.absoluteString,
           !conversation.allowedNetworkDestinations.contains(destination) {
            pendingText = text; needsNetworkConsent = true; return
        }
        startResponse(text)
    }
    func approveNetworkConversation() {
        guard let destination = settings.endpoint?.absoluteString, let text = pendingText else { return }
        conversation.allowedNetworkDestinations.insert(destination)
        pendingText = nil; needsNetworkConsent = false
        startResponse(text)
    }
    func declineNetworkConversation() { pendingText = nil; needsNetworkConsent = false }
    func revokeNetworkConsent() {
        guard !isRunning else { return }
        conversation.allowedNetworkDestinations = []
        Task { do { try await store?.save(conversation); await refresh() } catch { errorMessage = error.localizedDescription } }
    }
    func stop() { responseTask?.cancel() }

    private func startResponse(_ text: String) {
        guard let engine else { return }
        do {
            let backend: any ModelBackend
            switch settings.choice {
            case .localMLX:
                guard let localBackend else { return }
                backend = localBackend
            case .openAI, .compatibleServer:
                guard let url = settings.endpoint else { throw AssistantError.invalidEndpoint("Enter a valid server URL in Settings.") }
                let credential = try settings.credentialAccount.map { try CredentialStore.read(account: $0) } ?? ""
                if settings.choice == .openAI && credential.isEmpty { throw AssistantError.provider("Add your OpenAI API key in Settings. ChatGPT subscription sign-in is not implemented in this build.") }
                backend = try NetworkModelBackend(baseURL: url,
                    model: settings.choice == .openAI ? settings.openAIModel : settings.compatibleModel,
                    wireProtocol: settings.choice == .openAI ? .responses : .chatCompletions, credential: credential)
            }
            let current = conversation, attachments = attachedCaptureIDs
            isRunning = true; errorMessage = nil
            responseTask = Task {
                defer { isRunning = false; responseTask = nil }
                do {
                    for try await event in engine.respond(conversation: current, text: text, captureIDs: attachments, backend: backend) {
                        switch event {
                        case .conversation(let updated): conversation = updated; attachedCaptureIDs = []
                        case .toolResult: break
                        case .finished: break
                        }
                    }
                } catch {
                    if let saved = try? await store?.loadConversation(current.id) { conversation = saved }
                    if !Task.isCancelled && !(error is CancellationError) { errorMessage = error.localizedDescription }
                }
                await engine.waitUntilIdle()
                if let saved = try? await store?.loadConversation(current.id) { conversation = saved }
                await refresh()
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func saveSettings(_ value: ModelSettings, credential: String) throws {
        guard !isRunning, !isDownloading else { throw AssistantError.busy }
        if let endpoint = value.endpoint { try EndpointPolicy.validate(endpoint) }
        if !credential.isEmpty, let account = value.credentialAccount { try CredentialStore.save(credential, account: account) }
        guard let settingsURL else { throw AssistantError.provider("App storage is unavailable.") }
        try JSONEncoder().encode(value).write(to: settingsURL, options: .atomic)
        settings = value; rebuildLocalBackend()
    }
    func clearCredential() throws { if let account = settings.credentialAccount { try CredentialStore.remove(account: account) } }
    private func rebuildLocalBackend() {
        guard let modelRoot else { return }
        localBackend = MLXLocalBackend(repository: settings.localRepository, revision: settings.localRevision,
                                       root: modelRoot, responseTokens: settings.localResponseTokens)
        modelStatus = "Model will load from disk when needed"
    }
    func downloadModel() {
        guard !isRunning, !isDownloading, let localBackend else { return }
        isDownloading = true; downloadProgress = 0; modelStatus = "Downloading model files"
        downloadTask = Task {
            defer { isDownloading = false; downloadTask = nil }
            do {
                try await localBackend.download(allowCellular: settings.allowCellularDownloads) { [weak self] value in
                    Task { @MainActor in self?.downloadProgress = value }
                }
                modelStatus = "Model loaded on this device"
            } catch {
                modelStatus = Task.isCancelled ? "Download stopped" : "Model could not be loaded"
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }
    func stopDownload() { downloadTask?.cancel() }
    func unloadModel() {
        guard !isRunning, !isDownloading, let localBackend else { return }
        Task {
            do { try await localBackend.unload(); modelStatus = "Model unloaded; downloaded files retained" }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
