import AssistantCore
import Combine
import Foundation
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published var conversation = Conversation()
    @Published var histories: [ConversationSummary] = []
    @Published var captures: [CaptureObservation] = []
    @Published var artifacts: [ArtifactRecord] = []
    @Published var attachedCaptureIDs: [UUID] = []
    @Published var draft = ""
    @Published var draftContainsHealthData = false
    @Published var libraryContainsHealthData = false
    @Published var isRunning = false
    @Published private(set) var isInitialized = false
    @Published var isDownloading = false
    @Published var isConnecting = false
    @Published var isManagingAccount = false
    @Published var downloadProgress: Double = 0
    @Published var downloadingModelID: String?
    @Published var modelStatus = "Choose a model to begin"
    @Published var activity: String?
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published var settings = ModelSettings()
    @Published var needsNetworkConsent = false
    @Published var catalog: [LocalModelCatalogEntry] = []
    @Published var downloadedModelIDs: Set<String> = []
    @Published var accounts: [ChatGPTAccountSummary] = []
    @Published var chatGPTModels: [ChatGPTModel] = []
    @Published var appleDevice = AppleModelBackend.readiness(.device)
    @Published var appleCloud = AppleModelBackend.readiness(.privateCloud)
    @Published var showModels = false
    @Published var watchRequests: [WatchRequest] = []
    private(set) var store: LocalStore?
    private var engine: AssistantEngine?
    private var localBackend: MLXLocalBackend?
    private var responseTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var draftTask: Task<Void, Never>?
    private var settingsURL: URL?
    private var draftURL: URL?
    private var modelRoot: URL?
    private var root: URL?
    private var pendingText: String?
    private var accountService: ChatGPTAccountService?
    private let signIn = ChatGPTSignIn()
    private var drafts: [String: String] = [:]
    private let watch = PhoneWatchBridge()
    private var activeWatchRequestID: UUID?
    private var isStartingWatchRequest = false
    private var initializationWaiters: [CheckedContinuation<Void, Never>] = []
    private var initializationError: String?
    private var requiresManualResume = false
    private let healthService = HealthOverviewService()

    var modelTitle: String {
        switch settings.choice {
        case .localMLX: catalog.first { $0.id == settings.localRepository }?.name ?? "Downloaded model"
        case .chatGPT: chatGPTModels.first { $0.id == settings.chatGPTModel }?.displayName ?? "ChatGPT"
        case .appleOnDevice: appleDevice.title
        case .appleCloud: appleCloud.title
        case .openAI: settings.openAIModel.isEmpty ? "OpenAI API" : settings.openAIModel
        case .compatibleServer: settings.compatibleModel.isEmpty ? "Your computer" : settings.compatibleModel
        }
    }
    var modelLocation: String {
        switch settings.choice {
        case .localMLX, .appleOnDevice: "On this iPhone"
        case .chatGPT: "Using your ChatGPT plan"
        case .appleCloud: "Apple Private Cloud Compute"
        case .openAI: "OpenAI API"
        case .compatibleServer: "Connected computer"
        }
    }

    init() {
        do {
            let root = try PrivatePaths.root(); self.root = root
            let store = try LocalStore(root: root.appendingPathComponent("data"))
            self.store = store; engine = AssistantEngine(store: store)
            settingsURL = root.appendingPathComponent("settings.json")
            draftURL = root.appendingPathComponent("data/drafts.json")
            modelRoot = root.appendingPathComponent("models")
            if let settingsURL, FileManager.default.fileExists(atPath: settingsURL.path) {
                settings = try JSONDecoder().decode(ModelSettings.self, from: Data(contentsOf: settingsURL))
            } else if appleDevice.isAvailable { settings.choice = .appleOnDevice }
            if let draftURL, let data = try? Data(contentsOf: draftURL) { drafts = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:] }
            libraryContainsHealthData = store.initiallyContainsHealthData || drafts.contains(where: { $0.key.hasPrefix("health:") && $0.value == "true" })
            if libraryContainsHealthData { settings.includeInDeviceBackup = false }
            catalog = try LocalModelCatalogEntry.bundled()
            do { accountService = try ChatGPTAccountService() }
            catch { accountService = nil }
            try PrivatePaths.configureBackup(root: root, includeUserData: settings.includeInDeviceBackup)
            rebuildLocalBackend()
            watch.onRequest = { [weak self] request in await self?.receiveWatchRequest(request) }
            watch.activate()
            Task {
                try? await store.recoverWatchRequests()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-demo") { await installDemoFixture() }
                #endif
                await refresh()
                if let raw = drafts["selected"], let id = UUID(uuidString: raw), let saved = try? await store.loadConversation(id) {
                    conversation = saved; draft = drafts[id.uuidString] ?? ""; draftContainsHealthData = drafts["health:" + id.uuidString] == "true"
                }
                await refreshDownloads()
                if let last = conversation.messages.last { requiresManualResume = last.role != .assistant || last.state != .complete }
                finishInitialization()
                await refreshAccounts()
                await processNextWatchRequest()
            }
        } catch { errorMessage = error.localizedDescription; initializationError = error.localizedDescription; finishInitialization() }
    }
    private func finishInitialization() {
        isInitialized = true
        let waiting = initializationWaiters; initializationWaiters = []
        for waiter in waiting { waiter.resume() }
    }
    func waitUntilReady() async throws {
        if !isInitialized { await withCheckedContinuation { initializationWaiters.append($0) } }
        try Task.checkCancellation()
        if let initializationError { throw AssistantError.provider(initializationError) }
    }
    func refresh() async {
        guard let store else { return }
        do {
            histories = try await store.conversationSummaries()
            captures = try await store.captures()
            artifacts = try await store.artifacts()
            watchRequests = try await store.pendingWatchRequests()
        } catch { errorMessage = error.localizedDescription }
    }
    func becameActive() {
        appleDevice = AppleModelBackend.readiness(.device); appleCloud = AppleModelBackend.readiness(.privateCloud)
        Task { await processNextWatchRequest() }
    }
    func enteredBackground() {
        flushDraft()
        guard isRunning, settings.choice == .localMLX || settings.choice == .appleOnDevice else { return }
        stop()
        let backend = localBackend, engine = engine
        Task {
            await engine?.waitUntilIdle()
            if UIApplication.shared.applicationState != .active { try? await backend?.unload() }
        }
    }
    func draftChanged() {
        drafts[conversation.id.uuidString] = draft; drafts["selected"] = conversation.id.uuidString
        draftTask?.cancel()
        let current = conversation, text = draft
        draftTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.flushDraft()
            if !text.isEmpty, current.messages.isEmpty { try? await self.store?.save(current) }
        }
    }
    func flushDraft() {
        drafts[conversation.id.uuidString] = draft; drafts["selected"] = conversation.id.uuidString
        if draft.isEmpty { draftContainsHealthData = false }
        drafts["health:" + conversation.id.uuidString] = draftContainsHealthData ? "true" : "false"
        guard let draftURL else { return }
        do { try JSONEncoder().encode(drafts).write(to: draftURL, options: .atomic) }
        catch { errorMessage = "Your draft could not be saved. Free some storage before closing the app." }
    }
    func newConversation() {
        guard !isRunning else { return }; detachWatchRequest(); flushDraft()
        conversation = Conversation(); attachedCaptureIDs = []; draft = ""; draftContainsHealthData = false; errorMessage = nil
    }
    func selectConversation(_ summary: ConversationSummary) async {
        guard !isRunning, let store else { return }; if summary.id != conversation.id { detachWatchRequest() }; flushDraft()
        do { conversation = try await store.loadConversation(summary.id); attachedCaptureIDs = []; draft = drafts[summary.id.uuidString] ?? ""; draftContainsHealthData = drafts["health:" + summary.id.uuidString] == "true" }
        catch { errorMessage = error.localizedDescription }
    }
    func searchHistory(_ query: String) async -> [HistoryMatch] { (try? await store?.searchMessages(query)) ?? [] }
    func attach(_ id: UUID) { if !attachedCaptureIDs.contains(id) { attachedCaptureIDs.append(id) } }
    func saveCapture(_ capture: CaptureObservation, jpeg: Data) async -> Bool {
        guard let store else { return false }
        do { try await store.saveCapture(capture, jpeg: jpeg); attach(capture.id); await refresh(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    func image(_ id: UUID) async -> UIImage? {
        guard let data = try? await store?.imageData(id) else { return nil }
        return UIImage(data: data)
    }
    func captureURL(_ id: UUID) async -> URL? { try? await store?.captureManifestURL(id) }
    func captureExportURLs(_ id: UUID) async -> [URL] {
        guard let store else { return [] }
        do { return [try await store.captureManifestURL(id), try await store.captureImageURL(id)] }
        catch { errorMessage = error.localizedDescription; return [] }
    }
    func artifactURL(_ artifact: ArtifactRecord) async -> URL? {
        do { return try await store?.exportArtifact(artifact) }
        catch { errorMessage = error.localizedDescription; return nil }
    }
    func reviseArtifact(_ artifact: ArtifactRecord, content: String) async -> ArtifactRecord? {
        do {
            guard let store else { return nil }
            let revised = ArtifactRecord(conversationID: artifact.conversationID, filename: artifact.filename,
                content: content, previousRevisionID: artifact.id, containsLocalOnlyContext: artifact.containsLocalOnlyContext,
                containsHealthData: artifact.containsHealthData)
            try await store.saveArtifact(revised)
            try await store.saveArtifactDraft(id: artifact.id, text: nil)
            await refresh()
            return revised
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    func send(_ suppliedText: String? = nil) {
        let text = suppliedText ?? draft
        guard isInitialized, !isRunning, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if isManagingAccount && settings.choice == .chatGPT { noticeMessage = "The account change is finishing. Your draft is saved."; return }
        conversation.networkDisabled = settings.localOnly
        if settings.localOnly && settings.networkDestination != nil {
            showModels = true; noticeMessage = "On-device-only mode is enabled. Choose a downloaded or Apple on-device model."; return
        }
        if settings.choice == .localMLX, !downloadedModelIDs.contains(settings.localRepository) {
            showModels = true; noticeMessage = "Download or import a model, or choose an available connection. Your draft is saved."; return
        }
        if let destination = settings.networkDestination,
           !conversation.allowedNetworkDestinations.contains(destination) || ((draftContainsHealthData || conversation.containsHealthData) && !conversation.allowedHealthDestinations.contains(destination)) {
            pendingText = text; needsNetworkConsent = true; return
        }
        startResponse(text)
    }
    func approveNetworkConversation() {
        guard let destination = settings.networkDestination, let text = pendingText else { return }
        conversation.allowedNetworkDestinations.insert(destination)
        if draftContainsHealthData || conversation.containsHealthData { conversation.allowedHealthDestinations.insert(destination) }
        pendingText = nil; needsNetworkConsent = false; startResponse(text)
    }
    func declineNetworkConversation() { pendingText = nil; needsNetworkConsent = false }
    func revokeNetworkConsent() {
        guard !isRunning else { return }
        conversation.allowedNetworkDestinations = []
        conversation.allowedHealthDestinations = []
        Task { do { try await store?.save(conversation); await refresh() } catch { errorMessage = error.localizedDescription } }
    }
    func stop() { responseTask?.cancel() }
    private func startResponse(_ text: String) {
        guard let engine else { return }
        let current = conversation, attachments = attachedCaptureIDs, selection = settings, healthData = draftContainsHealthData
        let previousIDs = Set(current.messages.map(\.id))
        isRunning = true; activity = "Preparing \(modelTitle)"; errorMessage = nil; flushDraft()
        requiresManualResume = false
        responseTask = Task {
            if let requestID = activeWatchRequestID {
                await publishWatch(WatchReply(requestID: requestID, conversationID: current.id, state: .working,
                    message: "Your iPhone is working on it.", modelName: modelTitle))
            }
            do {
                try Task.checkCancellation()
                try await store?.save(current)
                let selectedBackend = try await backend(for: selection)
                try Task.checkCancellation()
                let extras = selection.healthToolsEnabled && HealthOverviewService.isEnabledInThisBuild ? [HealthOverviewService.tool] : []
                let destination = selection.networkDestination
                for try await event in engine.respond(conversation: current, text: text, captureIDs: attachments, backend: selectedBackend,
                    containsHealthData: healthData, additionalTools: extras, additionalExecutor: { [weak self] call in
                        guard let self else { throw CancellationError() }
                        return try await self.executeNativeTool(call, conversationID: current.id, destination: destination)
                    }) {
                    switch event {
                    case .conversation(let updated):
                        conversation = updated
                        if updated.messages.contains(where: { $0.role == .user && $0.text == text && !previousIDs.contains($0.id) }) {
                            attachedCaptureIDs = []
                            if draft == text { draft = ""; flushDraft() }
                        }
                    case .toolResult: await refresh(); activity = "Preparing the result"
                    case .activity(let value): activity = value
                    case .finished: break
                    }
                }
            } catch {
                if !Task.isCancelled && !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
            await engine.waitUntilIdle()
            if let saved = try? await store?.loadConversation(current.id) { conversation = saved }
            requiresManualResume = errorMessage != nil || Task.isCancelled || conversation.messages.last?.state != .complete
            isRunning = false; responseTask = nil; activity = nil
            if let requestID = activeWatchRequestID {
                activeWatchRequestID = nil
                let answer = conversation.messages.last(where: { $0.role == .assistant })
                let successful = errorMessage == nil && !Task.isCancelled && answer?.state == .complete && answer.map { !previousIDs.contains($0.id) } == true
                let text = successful ? String((answer?.text ?? "Completed on iPhone.").prefix(1000)) : "The task stopped or needs attention. Continue on your iPhone."
                await publishWatch(WatchReply(requestID: requestID, conversationID: conversation.id,
                    state: successful ? .complete : .needsPhone, message: text, modelName: modelTitle))
            }
            await refresh()
        }
    }
    private func backend(for selection: ModelSettings) async throws -> any ModelBackend {
        switch selection.choice {
        case .localMLX:
            guard let localBackend else { throw AccountConnectionError.unavailable }; return localBackend
        case .appleOnDevice: return AppleModelBackend(location: .device)
        case .appleCloud: return AppleModelBackend(location: .privateCloud)
        case .chatGPT:
            guard let account = selection.chatGPTAccountID, let accountService, !selection.chatGPTModel.isEmpty else { throw AccountConnectionError.signInRequired }
            let access = try await accountService.accessToken(for: account)
            return try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: selection.chatGPTModel,
                                           wireProtocol: .responses, credential: access, chatGPTAccountID: account)
        case .openAI, .compatibleServer:
            guard let url = selection.endpoint else { throw AssistantError.invalidEndpoint("Add a valid server address in Connections.") }
            let credential = try selection.credentialAccount.map { try CredentialStore.read(account: $0) } ?? ""
            if selection.choice == .openAI && credential.isEmpty { throw AssistantError.provider("Add an OpenAI API key, or use Continue with ChatGPT in the model picker.") }
            return try NetworkModelBackend(baseURL: url, model: selection.choice == .openAI ? selection.openAIModel : selection.compatibleModel,
                wireProtocol: selection.choice == .openAI ? .responses : .chatCompletions, credential: credential)
        }
    }

    func saveSettings(_ value: ModelSettings, credential: String = "") throws {
        guard !isRunning else { throw AssistantError.busy }
        guard !value.includeInDeviceBackup || !libraryContainsHealthData else { throw AssistantError.provider("A library containing Health-derived information stays excluded from device backups. You can export selected items yourself.") }
        if let endpoint = value.endpoint { try EndpointPolicy.validate(endpoint) }
        if !credential.isEmpty, let account = value.credentialAccount { try CredentialStore.save(credential, account: account) }
        guard let settingsURL else { throw AssistantError.provider("App storage is unavailable.") }
        try JSONEncoder().encode(value).write(to: settingsURL, options: .atomic)
        let changedLocal = value.localRepository != settings.localRepository || value.localRevision != settings.localRevision || value.localResponseTokens != settings.localResponseTokens
        settings = value
        if value.localOnly { cancelConnection(); stopDownload() }
        if changedLocal { rebuildLocalBackend() }
        if let root { try PrivatePaths.configureBackup(root: root, includeUserData: value.includeInDeviceBackup) }
    }
    func chooseLocal(_ entry: LocalModelCatalogEntry) {
        var next = settings; next.choice = .localMLX; next.localRepository = entry.id; next.localRevision = entry.revision
        do { try saveSettings(next); showModels = false } catch { errorMessage = error.localizedDescription }
    }
    func chooseApple(_ location: AppleModelBackend.Location) {
        var next = settings; next.choice = location == .device ? .appleOnDevice : .appleCloud
        do { try saveSettings(next); showModels = false } catch { errorMessage = error.localizedDescription }
    }
    func chooseChatGPTModel(_ entry: ChatGPTModel) {
        var next = settings; next.choice = .chatGPT; next.chatGPTModel = entry.id
        do { try saveSettings(next); showModels = false } catch { errorMessage = error.localizedDescription }
    }
    func clearCredential() throws { if let account = settings.credentialAccount { try CredentialStore.remove(account: account) } }
    private func rebuildLocalBackend() {
        guard let modelRoot else { return }
        let previous = localBackend
        localBackend = MLXLocalBackend(repository: settings.localRepository, revision: settings.localRevision, root: modelRoot, responseTokens: settings.localResponseTokens)
        if let previous { Task { try? await previous.unload() } }
    }
    func refreshDownloads() async {
        guard let modelRoot else { return }
        var ready = Set<String>()
        for entry in catalog {
            let backend = MLXLocalBackend(repository: entry.id, revision: entry.revision, root: modelRoot, responseTokens: settings.localResponseTokens)
            if await backend.isDownloaded() { ready.insert(entry.id) }
        }
        if let localBackend, await localBackend.isDownloaded() { ready.insert(settings.localRepository) }
        downloadedModelIDs = ready
    }
    func downloadModel(_ entry: LocalModelCatalogEntry) {
        guard !settings.localOnly else { noticeMessage = "Turn off on-device-only mode to download model files, then enable it again for offline use."; return }
        guard !isDownloading, !(isRunning && settings.choice == .localMLX), let modelRoot else { return }
        let backend = MLXLocalBackend(repository: entry.id, revision: entry.revision, root: modelRoot, responseTokens: settings.localResponseTokens)
        isDownloading = true; downloadingModelID = entry.id; downloadProgress = 0; modelStatus = "Downloading \(entry.name)"
        let allowCellular = settings.allowCellularDownloads
        downloadTask = Task {
            defer { isDownloading = false; downloadingModelID = nil; downloadTask = nil }
            do {
                try await backend.download(allowCellular: allowCellular, expectedFiles: entry.files) { [weak self] value in
                    Task { @MainActor in self?.downloadProgress = value; if value >= 1 { self?.modelStatus = "Verifying model files" } }
                }
                modelStatus = "\(entry.name) is ready to use"; await refreshDownloads()
            } catch {
                modelStatus = Task.isCancelled ? "Download stopped" : "Download needs attention"
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }
    func stopDownload() { downloadTask?.cancel() }
    func importModel(_ entry: LocalModelCatalogEntry, folder: URL) {
        guard !isDownloading, !(isRunning && settings.choice == .localMLX), let modelRoot else { return }
        let scoped = folder.startAccessingSecurityScopedResource()
        let backend = MLXLocalBackend(repository: entry.id, revision: entry.revision, root: modelRoot, responseTokens: settings.localResponseTokens)
        isDownloading = true; downloadingModelID = entry.id; downloadProgress = 0; modelStatus = "Importing \(entry.name)"
        downloadTask = Task {
            defer { if scoped { folder.stopAccessingSecurityScopedResource() }; isDownloading = false; downloadingModelID = nil; downloadTask = nil }
            do {
                try await backend.importFolder(folder, expectedFiles: entry.files) { [weak self] progress in
                    Task { @MainActor in self?.downloadProgress = progress; if progress >= 1 { self?.modelStatus = "Verifying imported files" } }
                }
                modelStatus = "\(entry.name) is ready to use"; await refreshDownloads()
            } catch {
                modelStatus = Task.isCancelled ? "Import stopped" : "Import needs attention"
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }
    func unloadModel() {
        guard !isRunning, let localBackend else { return }
        Task { do { try await localBackend.unload(); modelStatus = "Model memory released" } catch { errorMessage = error.localizedDescription } }
    }
    func connectChatGPT(clientID: String? = nil) {
        guard !settings.localOnly else { noticeMessage = "Turn off on-device-only mode to connect a ChatGPT account."; return }
        guard !isConnecting, !isManagingAccount, !isRunning else { return }
        if accountService == nil {
            do { accountService = try ChatGPTAccountService() }
            catch { errorMessage = error.localizedDescription; return }
        }
        guard let accountService else { return }
        isConnecting = true
        connectionTask = Task {
            defer { isConnecting = false; connectionTask = nil }
            do {
                let id = try await signIn.connect(service: accountService, clientID: clientID)
                settings.chatGPTAccountID = id
                await refreshAccounts()
                if !isRunning, let first = chatGPTModels.first { chooseChatGPTModel(first) }
                noticeMessage = "ChatGPT is connected. Requests here use your ChatGPT plan and its app usage settings."
            } catch {
                if !(error is CancellationError) { errorMessage = error.localizedDescription }
                accounts = await accountService.summaries()
            }
        }
    }
    func cancelConnection() { connectionTask?.cancel(); signIn.cancel() }
    func composeHealthOverview(_ report: HealthOverview) {
        guard !isRunning else { return }
        do {
            let text = try report.discussionText()
            libraryContainsHealthData = true
            var updated = settings; updated.includeInDeviceBackup = false
            try saveSettings(updated)
            newConversation(); draft = text; draftContainsHealthData = true; draftChanged()
        }
        catch { errorMessage = error.localizedDescription }
    }
    func enableHealthTools() throws {
        var next = settings; next.healthToolsEnabled = true
        try saveSettings(next)
    }
    private func executeNativeTool(_ call: ToolCall, conversationID: UUID, destination: String?) async throws -> ToolResult {
        try Task.checkCancellation()
        guard isRunning, conversation.id == conversationID, settings.healthToolsEnabled,
              call.name == HealthOverviewService.tool.name, call.arguments["days"]?.stringValue == "7" else {
            throw AssistantError.invalidTool("The requested Health context is unavailable.")
        }
        if let destination, !conversation.allowedHealthDestinations.contains(destination) {
            throw AssistantError.invalidTool("This conversation has not been allowed to share Health data. Open Health overview and discuss a selected summary to establish that permission, or use an on-device model.")
        }
        libraryContainsHealthData = true
        settings.includeInDeviceBackup = false
        if let root { try PrivatePaths.configureBackup(root: root, includeUserData: false) }
        if let settingsURL { try JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic) }
        let report = try await healthService.overview()
        try Task.checkCancellation()
        var result = ToolResult(callID: call.id, name: call.name, succeeded: true,
            output: .object(["summary": .string(try report.discussionText()), "source": .string("Apple HealthKit"),
                             "read_at": .string(ISO8601DateFormatter().string(from: report.rangeEnd))]))
        result.containsHealthData = true; result.authorizedHealthDestination = destination
        return result
    }
    func refreshAccounts() async {
        guard let accountService else { return }
        accounts = await accountService.summaries()
        guard !settings.localOnly else { chatGPTModels = []; return }
        let savedID = await accountService.selectedID()
        guard let id = settings.chatGPTAccountID ?? savedID else { chatGPTModels = []; return }
        settings.chatGPTAccountID = id
        do {
            let models = try await accountService.models(for: id)
            guard settings.chatGPTAccountID == id else { return }
            chatGPTModels = models
            if !isRunning && !chatGPTModels.contains(where: { $0.id == settings.chatGPTModel }) { settings.chatGPTModel = chatGPTModels.first?.id ?? "" }
            if let settingsURL { try JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic) }
        } catch { chatGPTModels = []; noticeMessage = error.localizedDescription }
    }
    func switchAccount(_ account: ChatGPTAccountSummary) async {
        guard !isRunning, !isManagingAccount, !isConnecting, let accountService else { return }
        do { try await accountService.select(account.id); settings.chatGPTAccountID = account.id; await refreshAccounts() }
        catch { errorMessage = error.localizedDescription }
    }
    func disconnectAccount(_ account: ChatGPTAccountSummary) async {
        guard !isRunning, !isManagingAccount, !isConnecting, let accountService else { return }
        isManagingAccount = true
        defer { isManagingAccount = false }
        do {
            let confirmed = try await accountService.signOut(account.id, revokeRemotely: !settings.localOnly)
            if settings.chatGPTAccountID == account.id {
                settings.chatGPTAccountID = nil; settings.chatGPTModel = ""; chatGPTModels = []
                if settings.choice == .chatGPT { settings.choice = appleDevice.isAvailable ? .appleOnDevice : .localMLX }
            }
            accounts = await accountService.summaries()
            try saveSettings(settings)
            noticeMessage = confirmed ? "Signed out of this ChatGPT account." : "Signed out on this device. Remote revocation could not be confirmed; disconnect the app in ChatGPT Settings → Usage."
        } catch { errorMessage = error.localizedDescription }
    }
    private func receiveWatchRequest(_ request: WatchRequest) async {
        guard let store else { return }
        do {
            let inserted = try await store.enqueueWatchRequest(request)
            if !inserted {
                if let previous = try await store.watchReply(request.id) { watch.send(previous) }
                return
            }
            await publishWatch(WatchReply(requestID: request.id, conversationID: request.conversationID, state: .queued,
                message: "Saved on iPhone. Open the assistant if a reply doesn't arrive.", modelName: modelTitle))
            await refresh()
            await processNextWatchRequest()
        } catch {
            watch.send(WatchReply(requestID: request.id, conversationID: request.conversationID, state: .failed,
                message: "This request could not be accepted. Review it on iPhone or send a fresh request.", modelName: modelTitle))
        }
    }
    private func processNextWatchRequest() async {
        guard isInitialized, !requiresManualResume, UIApplication.shared.applicationState == .active, !isRunning, !needsNetworkConsent,
              activeWatchRequestID == nil, !isStartingWatchRequest, draft.isEmpty, let store else { return }
        if let next = try? await store.queuedWatchRequests().first { await resumeWatchRequest(next) }
    }
    func resumeWatchRequest(_ request: WatchRequest) async {
        guard !isRunning, !needsNetworkConsent, activeWatchRequestID == nil, !isStartingWatchRequest, let store else { return }
        isStartingWatchRequest = true
        defer { isStartingWatchRequest = false }
        guard request.isValid() else {
            await publishWatch(WatchReply(requestID: request.id, conversationID: request.conversationID, state: .failed,
                message: "This saved request has expired. Send a fresh request so relative times stay accurate.", modelName: modelTitle)); await refresh(); return
        }
        let previous = try? await store.watchReply(request.id)
        let target = previous?.conversationID ?? request.conversationID
        if let target, let summary = histories.first(where: { $0.id == target }) { await selectConversation(summary) }
        else { newConversation() }
        activeWatchRequestID = request.id
        let interrupted = conversation.messages.last?.state == .interrupted || conversation.messages.last?.state == .failed || conversation.messages.last?.role == .tool
        draft = previous?.state == .needsPhone && interrupted ? "Continue the interrupted request using the saved results." : request.text
        draftChanged()
        await publishWatch(WatchReply(requestID: request.id, conversationID: conversation.id, state: .needsPhone,
            message: "Open the iPhone app to choose a model or review the sharing request.", modelName: modelTitle))
        send()
        await refresh()
    }
    private func publishWatch(_ reply: WatchReply) async {
        do { try await store?.saveWatchReply(reply); watch.send(reply) }
        catch { noticeMessage = "The Watch task status could not be saved." }
    }
    private func detachWatchRequest() {
        guard let id = activeWatchRequestID else { return }
        activeWatchRequestID = nil
        let reply = WatchReply(requestID: id, conversationID: conversation.id, state: .needsPhone,
            message: "This task is saved in Watch requests on iPhone.", modelName: modelTitle)
        Task { await publishWatch(reply) }
    }
    #if DEBUG
    private func installDemoFixture() async {
        guard let store else { return }
        var sample = Conversation(title: "Burgundy study project")
        sample.messages = [Message(role: .user, text: "Help me turn these study blocks into a simple plan."),
            Message(role: .assistant, text: """
            Here's a starting plan you can adjust.

            | Block | Focus | Minutes |
            | --- | --- | ---: |
            | First | Read and annotate | 25 |
            | Second | Practice questions | 20 |
            | Last | Recall without notes | 10 |

            **55 minutes total.** Take a short break between blocks.

            ```javascript
            const minutes = [25, 20, 10];
            return { result: minutes.reduce((a, b) => a + b, 0) };
            ```

            The editable plan is saved below.
            """, providerID: "synthetic-ui-fixture")]
        do {
            try await store.save(sample)
            try await store.saveArtifact(ArtifactRecord(conversationID: sample.id, filename: "study-plan.md", content: "# Study plan\n\n- Read and annotate: 25 minutes\n- Practice: 20 minutes\n- Recall: 10 minutes\n"))
            conversation = sample
        } catch { errorMessage = error.localizedDescription }
    }
    #endif
}
