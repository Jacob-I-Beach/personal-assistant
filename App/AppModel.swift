import AssistantCore
import Combine
import Foundation
import UIKit
import MessageUI
import PDFKit

@MainActor
final class AppModel: ObservableObject {
    @Published var conversation = Conversation()
    @Published var histories: [ConversationSummary] = []
    @Published var folders: [ChatFolder] = []
    @Published var files: [WorkspaceFile] = []
    @Published var attachedFileIDs: [UUID] = []
    @Published var isImportingFiles = false
    @Published var attachmentPreparation: [AttachmentDraft] = []
    @Published var captures: [CaptureObservation] = []
    @Published var artifacts: [ArtifactRecord] = []
    @Published var attachedCaptureIDs: [UUID] = []
    @Published var selectedImagePoints: [String: [ImagePoint]] = [:]
    @Published var draft = ""
    @Published var draftContextReferences: [ContextReference] = []
    @Published var pendingContextualDraft: ContextualDraftProposal?
    @Published var composerFocusRequest = UUID()
    @Published var editingMessageID: UUID?
    private var draftBeforeEditing: (text: String, captures: [UUID], files: [UUID], health: Bool, selections: [String: [ImagePoint]], references: [ContextReference])?
    @Published var draftContainsHealthData = false
    @Published var libraryContainsHealthData = false
    @Published var isRunning = false
    @Published private(set) var isInitialized = false
    @Published private(set) var isRestoringBackgroundRoute = false
    @Published var isDownloading = false
    @Published var isConnecting = false
    @Published var isManagingAccount = false
    @Published var downloadProgress: Double = 0
    @Published var downloadingModelID: String?
    @Published var modelStatus = "Choose a model to begin"
    @Published var activity: String?
    @Published var activeToolCall: ToolCall?
    @Published var localRecovery: LocalRecovery?
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published var settings = ModelSettings()
    @Published var needsNetworkConsent = false
    @Published var catalog: [LocalModelCatalogEntry] = []
    @Published var downloadedModelIDs: Set<String> = []
    @Published var accounts: [ChatGPTAccountSummary] = []
    @Published private(set) var computerAccount: ComputerAccountRecord?
    @Published private(set) var computerAccountReachability = ComputerAccountReachability.unchecked
    @Published var modelCatalog = ModelCatalogState()
    var chatGPTModels: [ChatGPTModel] { get { modelCatalog.models } set { modelCatalog.models = newValue } }
    private var savedModelCatalogs: [String: AccountModelCatalog] = [:]
    private var modelCatalogURL: URL?
    @Published var appleDevice = AppleModelBackend.readiness(.device)
    @Published var appleCloud = AppleModelBackend.readiness(.privateCloud)
    @Published var presentationState = PresentationState()
    var showModels: Bool { get { rootPresentation == .models } set { if newValue { present(.models) } else { dismissPresentation(.models) } } }
    @Published var watchRequests: [WatchRequest] = []
    @Published var unfinishedReplies: [WorkTurn] = []
    @Published var inbox: [InboxEntry] = []
    @Published var pendingQuestions: [TaskQuestion] = []
    var showInbox: Bool { get { rootPresentation == .inbox } set { if newValue { present(.inbox) } else { dismissPresentation(.inbox) } } }
    var showPlanningAccess: Bool { get { rootPresentation == .planning } set { if newValue { present(.planning) } else { dismissPresentation(.planning) } } }
    var routedInboxID: UUID?
    let planning = PlanningService()
    private var pausedForInput = false
    private var pausedForWorkBudget = false
    private var responseAwaitingAttention = false
    private var attentionDestination: UUID?
    @Published var contextRefresh = 0
    @Published var nativeAction: NativeActionRequest?
    var nativeReviewVisible = false
    var questionResumeAfterDismiss: WorkTurn?
    @Published var connectedFolders: [FolderConnection] = []
    var showConnectedFolders: Bool { get { rootPresentation == .folders } set { if newValue { present(.folders) } else { dismissPresentation(.folders) } } }
    private(set) var workspaceService: FolderWorkspaceService?
    var pickedFolderURL: URL?
    private var nativeActionWaiter: CheckedContinuation<String, any Error>?
    private var nativeActionWaiterID: UUID?
    private var deferredNativeAction: NativeActionRequest?
    private var deferredReviewIdentity: ToolExecutionIdentity?
    let locationService = ForegroundLocation()
    let routeService = RouteService()
    private(set) var store: LocalStore?
    private var engine: AssistantEngine?
    private var localBackend: MLXLocalBackend?
    private var localBackendTransition: Task<Void, Never>?
    private var responseTask: Task<Void, Never>?
    private let completionWindow = ResponseCompletionWindow.shared
    private let replyActivity = ReplyLiveActivity()
    private var responseOnComputer = false
    private var handingOffToComputer = false
    private var computerHandoff: Task<Void, Never>?
    private let taskAttention = TaskAttentionService.shared
    private var systemEndedBackgroundWork = false
    private var responseWasBackgrounded = false
    private var userRequestedStop = false
    private(set) var activeTurnID: UUID?
    private var titleTask: Task<Void, Never>?
    private var titleGenerationID = UUID()
    private var downloadTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var draftTask: Task<Void, Never>?
    private var conversationSelectionID = UUID()
    private var settingsURL: URL?
    private var computerAccountURL: URL?
    private var accountRefreshID = UUID()
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

    var usesComputerChatGPT: Bool { settings.useComputer && settings.companion != nil }
    private var modelCatalogOwner: String? {
        if usesComputerChatGPT, let connection = settings.companion { return "computer:\(connection.serverID):\(connection.profileID)" }
        return settings.chatGPTAccountID.map { "account:" + $0 }
    }
    var activeComputerAccount: ComputerAccountRecord? {
        guard let connection = settings.companion, let computerAccount, computerAccount.matches(connection) else { return nil }
        return computerAccount
    }
    var shouldOfferChatGPTSignIn: Bool {
        !settings.localOnly && !usesComputerChatGPT && !accounts.contains(where: \.isConnected)
    }
    var chatGPTAccountLabel: String {
        if usesComputerChatGPT { return activeComputerAccount?.label ?? "Your ChatGPT account" }
        return accounts.first(where: { $0.id == settings.chatGPTAccountID })?.label ?? accounts.first(where: \.isConnected)?.label ?? "ChatGPT"
    }
    var computerAccountDetail: String {
        if settings.localOnly { return "Connection paused in on-device mode" }
        switch computerAccountReachability {
        case .unchecked: return activeComputerAccount == nil ? "Checking your connected account" : "Account saved on your computer"
        case .checking: return "Refreshing connection…"
        case .unavailable: return "Computer temporarily unavailable · your account is kept"
        case .reachable: return activeComputerAccount?.detail ?? "Check your computer connection"
        }
    }
    var computerAccountNeedsAttention: Bool {
        usesComputerChatGPT && !settings.localOnly && (computerAccountReachability == .unavailable || activeComputerAccount?.needsAttention == true)
    }

    var modelTitle: String {
        switch settings.choice {
        case .localMLX: catalog.first { $0.id == settings.localRepository }?.name ?? "Downloaded model"
        case .chatGPT: ChatGPTModel.displayTitle(for: settings.chatGPTModel, catalog: chatGPTModels)
        case .appleOnDevice: appleDevice.title
        case .appleCloud: appleCloud.title
        case .openAI: settings.openAIModel.isEmpty ? "OpenAI API" : settings.openAIModel
        case .compatibleServer: settings.compatibleModel.isEmpty ? "Your computer" : settings.compatibleModel
        }
    }
    var modelLocation: String {
        switch settings.choice {
        case .localMLX, .appleOnDevice: return "On this iPhone"
        case .chatGPT:
            if modelCatalog.phase == .unavailable || modelCatalog.phase == .stale { return "Model availability needs a refresh" }
            return usesComputerChatGPT ? (computerAccountNeedsAttention ? "Check your computer connection" : "Using your ChatGPT plan") : (accounts.contains(where: \.isConnected) ? "Using your ChatGPT plan" : "Connect your account")
        case .appleCloud: return "Apple Private Cloud Compute"
        case .openAI: return "OpenAI API"
        case .compatibleServer: return "Connected computer"
        }
    }

    init() {
        do {
            let root = try PrivatePaths.root(); self.root = root
            try PrivatePaths.applyPendingLibrary(root: root)
            let dataRoot = try PrivatePaths.activeData(root: root)
            let store = try LocalStore(root: dataRoot, outputsRoot: PrivatePaths.outputs())
            self.store = store; engine = AssistantEngine(store: store)
            taskAttention.onOpen = { [weak self] id in await self?.openTaskAttention(id) }
            workspaceService = try FolderWorkspaceService(storage: root.appendingPathComponent("data/workspaces"))
            settingsURL = root.appendingPathComponent("settings.json")
            computerAccountURL = root.appendingPathComponent("computer-account.json")
            draftURL = dataRoot.appendingPathComponent("drafts.json")
            modelRoot = root.appendingPathComponent("models")
            if let settingsURL, FileManager.default.fileExists(atPath: settingsURL.path) {
                settings = try JSONDecoder().decode(ModelSettings.self, from: Data(contentsOf: settingsURL))
            }
            if let computerAccountURL, let data = try? Data(contentsOf: computerAccountURL) {
                computerAccount = try? JSONDecoder().decode(ComputerAccountRecord.self, from: data)
            }
            modelCatalogURL = root.appendingPathComponent("model-catalogs.json")
            if let modelCatalogURL, let data = try? Data(contentsOf: modelCatalogURL), data.count <= 2 * 1024 * 1024 {
                savedModelCatalogs = (try? JSONDecoder().decode([String: AccountModelCatalog].self, from: data)) ?? [:]
            }
            if let owner = modelCatalogOwner {
                modelCatalog.begin(owner: owner, saved: savedModelCatalogs[owner])
            }
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
            let backgroundDestination = ReplyReturnRoute.take()
            isRestoringBackgroundRoute = backgroundDestination != nil
            Task {
                try? await store.recoverWatchRequests()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-demo") { await installDemoFixture() }
                if ProcessInfo.processInfo.arguments.contains("--ui-presentation") { await installPresentationFixture() }
                if ProcessInfo.processInfo.arguments.contains("--ui-workspace") { await installWorkspaceFixture() }
                if ProcessInfo.processInfo.arguments.contains("--ui-interactions") { await installInteractionFixture() }
                if ProcessInfo.processInfo.arguments.contains("--ui-streaming") { await installStreamingFixture() }
                if ProcessInfo.processInfo.arguments.contains("--ui-continuity") { await installContinuityFixture() }
                if ProcessInfo.processInfo.arguments.contains("--ui-background") { await installBackgroundFixture() }
                if ProcessInfo.processInfo.arguments.contains("--ui-long-task") { await installLongTaskFixture() }
                if ProcessInfo.processInfo.arguments.contains("--ui-daily-work") { await installDailyWorkflowFixture() }
                if ProcessInfo.processInfo.arguments.contains("--ui-coherence") { await installCoherenceFixture() }
                if ProcessInfo.processInfo.arguments.contains("--ui-local-controls") { settings.choice = .localMLX; rebuildLocalBackend() }
                if ProcessInfo.processInfo.arguments.contains("--ui-recovery09") { await installRecovery09Fixture() }
                if ProcessInfo.processInfo.arguments.contains("--ui-activity103") { await installActivityFixture() }
                if ProcessInfo.processInfo.arguments.contains("--ui-product117") { await installProductFixture() }
                #endif
                await refresh()
                await refreshWorkspaces()
                // A cold launch opens a fresh canvas. Saved chats/drafts are resumed only by selection.
                // Scene activation after a picker or authentication does not replace the current chat.
                await refreshDownloads()
                if let last = conversation.messages.last { requiresManualResume = last.role != .assistant || last.state != .complete }
                finishInitialization()
                await taskAttention.openQueued()
                if attentionDestination == nil, let destination = backgroundDestination {
                    await openTaskAttention(destination)
                }
                if attentionDestination == nil { isRestoringBackgroundRoute = false }
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
            folders = try await store.folders()
            files = try await store.workspaceFiles()
            captures = try await store.captures()
            artifacts = try await store.artifacts()
            watchRequests = try await store.pendingWatchRequests()
            unfinishedReplies = try await store.unfinishedWork()
            inbox = try await store.inboxEntries()
            pendingQuestions = try await store.pendingQuestions()
        } catch { errorMessage = error.localizedDescription }
    }
    func becameActive() {
        contextRefresh += 1
        Task { await flushComputerStops() }
        appleDevice = AppleModelBackend.readiness(.device); appleCloud = AppleModelBackend.readiness(.privateCloud)
        Task {
            do { try await waitUntilReady() } catch { return }
            await replyActivity.viewed(conversationID: conversation.id)
            await planning.refreshHome(settings: settings)
            await presentDeferredReview()
            if !isRunning { await continueInterruptedReplyIfEligible() }
            await processNextWatchRequest()
        }
    }
    func enteredBackground() {
        flushDraft()
        titleTask?.cancel()
        guard isRunning else { return }
        responseWasBackgrounded = true
        ReplyReturnRoute.remember(conversation.id)
        if let request = deferredNativeAction ?? nativeAction { Task { await notifyReview(request) } }
        // Connected work already belongs to the server. Backgrounding only
        // changes this client's subscription; there is no ownership transfer.
        guard settings.choice == .localMLX || settings.choice == .appleOnDevice else { return }
        pauseResponseForBackground()
        guard settings.choice == .localMLX else { return }
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
        if draft.isEmpty && !draftContextReferences.contains(where: \.containsHealthData) && attachedFileIDs.allSatisfy({ id in files.first { $0.id == id }?.containsHealthData != true }) { draftContainsHealthData = false }
        drafts["health:" + conversation.id.uuidString] = draftContainsHealthData ? "true" : "false"
        drafts["files:" + conversation.id.uuidString] = attachedFileIDs.map(\.uuidString).joined(separator: ",")
        drafts["captures:" + conversation.id.uuidString] = attachedCaptureIDs.map(\.uuidString).joined(separator: ",")
        if let data = try? JSONEncoder().encode(selectedImagePoints) { drafts["points:" + conversation.id.uuidString] = String(decoding: data, as: UTF8.self) }
        if let data = try? JSONEncoder().encode(draftContextReferences) { drafts["references:" + conversation.id.uuidString] = String(decoding: data, as: UTF8.self) }
        guard let draftURL else { return }
        do { try JSONEncoder().encode(drafts).write(to: draftURL, options: .atomic) }
        catch { errorMessage = "Your draft could not be saved. Free some storage before closing the app." }
    }
    func newConversation(folderID: UUID? = nil) {
        guard !isRunning else { return }; cancelEditing(); detachWatchRequest(); draftTask?.cancel(); flushDraft()
        conversationSelectionID = UUID()
        ReplyReturnRoute.clear()
        if conversation.messages.isEmpty && (!draft.isEmpty || !attachedCaptureIDs.isEmpty || !attachedFileIDs.isEmpty || !draftContextReferences.isEmpty) {
            let savedDraft = conversation
            Task {
                do { try await store?.save(savedDraft); await refresh() }
                catch { errorMessage = error.localizedDescription }
            }
        }
        conversation = Conversation(); conversation.folderID = folderID
        attachedCaptureIDs = []; selectedImagePoints = [:]; attachedFileIDs = []; draftContextReferences = []; pendingContextualDraft = nil; draft = ""; draftContainsHealthData = false; errorMessage = nil; noticeMessage = nil
        requiresManualResume = false
    }
    func selectConversation(_ summary: ConversationSummary) async {
        guard !isRunning, let store else { return }; cancelEditing(); if summary.id != conversation.id { detachWatchRequest() }; draftTask?.cancel(); flushDraft()
        let selection = UUID(); conversationSelectionID = selection
        do {
            if conversation.messages.isEmpty && (!draft.isEmpty || !attachedCaptureIDs.isEmpty || !attachedFileIDs.isEmpty || !draftContextReferences.isEmpty) { try await store.save(conversation) }
            let loaded = try await store.loadConversation(summary.id)
            guard conversationSelectionID == selection, !isRunning else { return }
            conversation = loaded
            await replyActivity.viewed(conversationID: summary.id)
            guard conversationSelectionID == selection, conversation.id == summary.id, !isRunning else { return }
            attachedFileIDs = (drafts["files:" + summary.id.uuidString] ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) }.filter { id in files.contains { $0.id == id } }
            attachedCaptureIDs = (drafts["captures:" + summary.id.uuidString] ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) }
            selectedImagePoints = (try? JSONDecoder().decode([String: [ImagePoint]].self, from: Data((drafts["points:" + summary.id.uuidString] ?? "{}").utf8))) ?? [:]
            draft = drafts[summary.id.uuidString] ?? ""; draftContainsHealthData = drafts["health:" + summary.id.uuidString] == "true"
            draftContextReferences = (try? JSONDecoder().decode([ContextReference].self, from: Data((drafts["references:" + summary.id.uuidString] ?? "[]").utf8))) ?? []
            pendingContextualDraft = nil
            noticeMessage = nil; errorMessage = nil
            if settings.choice == .chatGPT, let work = unfinishedReplies.first(where: { $0.conversationID == summary.id && $0.backendID.hasPrefix("companion:") }),
               let record = try? await store.companionRun(work.id), !record.stopRequested,
               !["failed", "cancelled", "interrupted"].contains(record.status) {
                Task { if !self.isRunning && self.conversation.id == summary.id { await self.resumeReply(work, reconnectOnly: true) } }
            }
        }
        catch { errorMessage = error.localizedDescription }
    }
    func searchHistory(_ query: String) async -> [HistoryMatch] { (try? await store?.searchMessages(query)) ?? [] }
    func saveFolder(_ folder: ChatFolder) async -> Bool {
        guard !isRunning else { return false }
        do { try await store?.saveFolder(folder); await refresh(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    func removeFolder(_ id: UUID) async {
        guard !isRunning else { return }
        do {
            try await store?.removeFolder(id)
            if conversation.folderID == id { conversation.folderID = nil }
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }
    enum ChatChange { case rename(String), move(UUID?), archive(Bool), delete }
    func changeChat(_ id: UUID, _ change: ChatChange) async {
        guard !isRunning, let store else { return }
        draftTask?.cancel()
        do {
            switch change {
            case .rename(let title): try await store.renameConversation(id, title: title)
            case .move(let folder): try await store.moveConversation(id, to: folder)
            case .archive(let archived): try await store.setArchived(id, archived: archived)
            case .delete:
                try await store.removeConversation(id)
                if conversation.id == id {
                    detachWatchRequest(); conversation = Conversation(); draft = ""; attachedCaptureIDs = []; attachedFileIDs = []; draftContextReferences = []; pendingContextualDraft = nil; draftContainsHealthData = false
                }
                for key in [id.uuidString, "files:" + id.uuidString, "captures:" + id.uuidString, "health:" + id.uuidString, "points:" + id.uuidString, "references:" + id.uuidString] { drafts.removeValue(forKey: key) }
                flushDraft(); await refresh(); return
            }
            if id == conversation.id { conversation = try await store.loadConversation(id) }
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }
    func importFiles(_ urls: [URL], attach: Bool = true) {
        guard !isImportingFiles, let store else { return }
        isImportingFiles = true
        let targetID = conversation.id
        Task {
            defer { isImportingFiles = false }
            for url in urls.prefix(8) {
                let item = AttachmentDraft(conversationID: targetID, source: url.lastPathComponent)
                attachmentPreparation.append(item)
                do {
                    let (file, data) = try await DocumentImporter.shared.read(url)
                    try await store.saveWorkspaceFile(file, data: data)
                    let partial = file.text.isEmpty || ["truncated", "not extracted", "may omit", "extraction limit"].contains { file.extractionNote.localizedCaseInsensitiveContains($0) }
                    if let index = attachmentPreparation.firstIndex(where: { $0.id == item.id }) {
                        attachmentPreparation[index].state = partial ? .partial : .ready
                        attachmentPreparation[index].fileID = file.id
                        attachmentPreparation[index].detail = partial ? (file.extractionNote.isEmpty ? "Original saved; readable text could not be extracted. Preview the original before relying on it." : file.extractionNote) : "Ready"
                        attachmentPreparation[index].containsHealthData = file.containsHealthData
                    }
                    if attach && conversation.id == targetID && !isRunning { attachFile(file.id) }
                } catch {
                    if let index = attachmentPreparation.firstIndex(where: { $0.id == item.id }) { attachmentPreparation[index].state = .unreadable; attachmentPreparation[index].detail = error.localizedDescription + " Other attachments and your draft are kept. Choose this file again to retry." }
                }
            }
            if urls.count > 8 { noticeMessage = "The first eight files were processed. Add the remaining files in another selection." }
            await refresh(); flushDraft()
        }
    }
    func attachFile(_ id: UUID) {
        guard !isRunning else { return }
        if let file = files.first(where: { $0.id == id }), file.containsHealthData {
            guard file.conversationID == conversation.id else { noticeMessage = "Open the original conversation to use this Health-derived file."; return }
            draftContainsHealthData = true
        }
        if !attachedFileIDs.contains(id) { attachedFileIDs.append(id) }
        flushDraft()
    }
    func fileURL(_ id: UUID) async -> URL? {
        do { return try await store?.workspaceFileURL(id) }
        catch { localRecovery = LocalRecovery(conversationID: conversation.id, category: .missingSource, title: "Original file unavailable", detail: error.localizedDescription, retained: "Your chat and saved file metadata remain. Inspect the Library or choose the original again."); return nil }
    }
    func removeFile(_ id: UUID) async {
        guard !isRunning else { return }
        do { try await store?.removeWorkspaceFile(id); attachedFileIDs.removeAll { $0 == id }; flushDraft(); await refresh() }
        catch { localRecovery = LocalRecovery(conversationID: conversation.id, category: .unknownWriteOutcome, title: "Check the file before trying again", detail: error.localizedDescription, retained: "The original removal could not be fully confirmed. Inspect Library; exported copies remain separate.") }
    }
    func shareFile(_ id: UUID, workspace: Bool, connected: Bool) async {
        guard !isRunning else { return }
        do { try await store?.setFileSharing(id, workspace: workspace, connected: connected); await refresh() }
        catch { errorMessage = error.localizedDescription }
    }
    func attach(_ id: UUID) { if !attachedCaptureIDs.contains(id) { attachedCaptureIDs.append(id) } }
    func saveCapture(_ capture: CaptureObservation, jpeg: Data, attachTo conversationID: UUID? = nil) async -> Bool {
        guard let store else { return false }
        let target = conversationID ?? conversation.id
        do {
            try Task.checkCancellation()
            try await store.saveCapture(capture, jpeg: jpeg)
            if !Task.isCancelled, conversation.id == target { attach(capture.id); flushDraft() }
            await refresh(); return !Task.isCancelled
        } catch { if !Task.isCancelled { errorMessage = error.localizedDescription }; return false }
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
    func publishArtifactEdit(previous: ArtifactRecord, saved: ArtifactRecord) async -> String? {
        var warning: String?
        do {
            if let result = try await store?.refreshPublishedOutput(id: saved.id, filename: saved.filename, previous: Data(previous.content.utf8), replacement: Data(saved.content.utf8), conversationID: saved.conversationID) {
                warning = result.warning
            }
        } catch { warning = "The revision is saved in Library, but its Files copy could not be updated. Export the saved revision when needed." }
        await refresh()
        return warning
    }

    func send(_ suppliedText: String? = nil) {
        let enteredText = suppliedText ?? draft
        let hasAttachments = !attachedCaptureIDs.isEmpty || !attachedFileIDs.isEmpty || !draftContextReferences.isEmpty
        let text = enteredText
        guard isInitialized, !isRunning, hasAttachments || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if settings.networkDestination != nil && draftContextReferences.contains(where: \.containsLocalOnlyContext) {
            noticeMessage = "This selected context stays on this iPhone. Choose an on-device model or remove its context chip before sending."; showModels = true; return
        }
        if isManagingAccount && settings.choice == .chatGPT { noticeMessage = "The account change is finishing. Your draft is saved."; return }
        if settings.choice == .chatGPT && ((settings.chatGPTAccountID == nil && !(settings.useComputer && settings.companion != nil)) || settings.chatGPTModel.isEmpty) {
            showModels = true; noticeMessage = "Connect ChatGPT or choose an on-device model. Your draft is saved."; return
        }
        conversation.networkDisabled = settings.localOnly
        if settings.localOnly && settings.networkDestination != nil {
            showModels = true; noticeMessage = "On-device-only mode is enabled. Choose a downloaded or Apple on-device model."; return
        }
        if settings.choice == .localMLX, !downloadedModelIDs.contains(settings.localRepository) {
            showModels = true; noticeMessage = "Download or import a model, or choose an available connection. Your draft is saved."; return
        }
        if let destination = settings.networkDestination {
            if ConversationSharing.needsReview(conversation, destination: destination, includesHealth: draftContainsHealthData, confirmNewChats: settings.confirmNewConnectedChats) {
                pendingText = text; needsNetworkConsent = true; return
            }
            // Pressing Send with an explicitly selected connection authorizes this
            // chat's ordinary content. Health sharing remains a separate decision.
            conversation.allowedNetworkDestinations.insert(destination)
        }
        AppFeedback.play(.sent)
        startResponse(text)
    }
    func approveNetworkConversation() {
        guard let destination = settings.networkDestination, let text = pendingText else { return }
        conversation.allowedNetworkDestinations.insert(destination)
        conversation.requiresNetworkReview = false
        if draftContainsHealthData || conversation.containsHealthData { conversation.allowedHealthDestinations.insert(destination) }
        pendingText = nil; needsNetworkConsent = false; startResponse(text)
    }
    func declineNetworkConversation() { pendingText = nil; needsNetworkConsent = false }
    func revokeNetworkConsent() {
        guard !isRunning else { return }
        titleTask?.cancel()
        conversation.allowedNetworkDestinations = []
        conversation.allowedHealthDestinations = []
        conversation.requiresNetworkReview = true
        Task { do { try await store?.save(conversation); await refresh() } catch { errorMessage = error.localizedDescription } }
    }
    func stop() {
        userRequestedStop = true; responseWasBackgrounded = false; ReplyReturnRoute.clear()
        computerHandoff?.cancel()
        let turn = activeTurnID, connection = settings.companion, store = store
        responseTask?.cancel()
        if let turn, let connection, let store {
            Task {
                if (try? await store.computerToolWorkspace(turn)) != nil { try? await store.markComputerToolStop(turn); await flushComputerStops() }
                guard var saved = try? await store.companionRun(turn) else { return }
                saved.stopRequested = true; try? await store.saveCompanionRun(saved)
                do {
                    let client = try CompanionClient(baseURL: connection.baseURL, fingerprint: connection.certificateSHA256, token: CredentialStore.read(account: connection.credentialAccount))
                    let result = try await client.json("/v1/cancel-request", method: "POST", body: .object(["request_key": saved.payload["request_key"] ?? .string(turn.uuidString)]))
                    saved.status = result["status"]?.stringValue ?? saved.status
                    try await store.saveCompanionRun(saved)
                } catch { noticeMessage = "Stop is saved on this iPhone. The computer could not be reached; it may still be working until the stop request reconnects." }
            }
        }
    }
    func deferQuestion() { pausedForInput = true; responseTask?.cancel() }
    private func pauseResponseForBackground() {
        guard isRunning, !userRequestedStop else { return }
        responseWasBackgrounded = true; responseTask?.cancel()
    }
    private func continueInterruptedReplyIfEligible() async {
        if settings.choice == .chatGPT, !isRunning, !handingOffToComputer, !userRequestedStop, UIApplication.shared.applicationState == .active,
           let work = try? await store?.unfinishedWork().first(where: { $0.conversationID == conversation.id }),
           work.backendID.hasPrefix("companion:"), work.interruptionKind != "computer_sync_attention", let record = try? await store?.companionRun(work.id), !record.stopRequested,
           !["failed", "cancelled", "interrupted"].contains(record.status) {
            await resumeReply(work, reconnectOnly: true); return
        }
        guard !isRunning, !userRequestedStop, !pausedForInput, !pausedForWorkBudget, !systemEndedBackgroundWork, responseWasBackgrounded, UIApplication.shared.applicationState == .active,
              let work = try? await store?.unfinishedWork().first(where: { $0.conversationID == conversation.id }),
              !work.backendID.hasPrefix("companion:"),
              work.automaticResumeCount < 3, work.needsChangedRequest != true, Date().timeIntervalSince(work.updatedAt) < 86_400 else { return }
        await resumeReply(work, automatic: true)
    }
    func resumeReply(_ work: WorkTurn, automatic: Bool = false, reconnectOnly: Bool = false) async {
        guard !isRunning, let store, UIApplication.shared.applicationState == .active else { return }
        if work.backendID.hasPrefix("companion:"), settings.choice != .chatGPT {
            if !automatic { noticeMessage = "This saved reply uses ChatGPT. Send a new message with \(modelTitle), or select ChatGPT to continue the original task." }
            return
        }
        do {
            let restored = try await store.loadConversation(work.conversationID)
            guard restored.messages.last(where: \.isRequest)?.id == work.userMessageID else { throw AssistantError.provider("A newer request followed this reply. Open its conversation to choose what should continue.") }
            if work.conversationID != conversation.id {
                guard !automatic, let summary = histories.first(where: { $0.id == work.conversationID }) else { return }
                await selectConversation(summary)
            }
            guard work.conversationID == conversation.id else { return }
            // Never silently change the selected account, model or its access policy.
            let selectedSettings = settings
            if work.backendID.hasPrefix("companion:"), selectedSettings.choice != .chatGPT { return }
            let selected = try await backend(forSavedWork: work, selection: selectedSettings)
            guard selected.id == work.backendID, selected.networkDestination == work.destination else {
                throw AssistantError.provider("Choose the model previously used for this reply before continuing it.")
            }
            guard !settings.localOnly || selected.networkDestination == nil else { throw AssistantError.networkNotAuthorized }
            guard conversation.id == work.conversationID, !isRunning, settings == selectedSettings, !automatic || !userRequestedStop else { return }
            conversation = restored
            startResponse("", resuming: work, automaticResume: automatic, reconnectOnly: reconnectOnly)
        } catch {
            if automatic { noticeMessage = "The saved reply needs your attention. Open it and choose Continue when ready." }
            else { errorMessage = error.localizedDescription }
        }
    }
    func beginEditing(_ message: Message) {
        guard !isRunning, message.isRequest, conversation.messages.contains(where: { $0.id == message.id }) else { return }
        if editingMessageID == nil { draftBeforeEditing = (draft, attachedCaptureIDs, attachedFileIDs, draftContainsHealthData, selectedImagePoints, draftContextReferences) }
        editingMessageID = message.id; draft = message.text
        attachedCaptureIDs = message.captureIDs; attachedFileIDs = message.fileIDs; draftContainsHealthData = message.containsHealthData
        selectedImagePoints = message.imageSelections
        draftContextReferences = message.contextReferences
    }
    func cancelEditing() {
        guard editingMessageID != nil else { return }
        if let prior = draftBeforeEditing { draft = prior.text; attachedCaptureIDs = prior.captures; attachedFileIDs = prior.files; draftContainsHealthData = prior.health; selectedImagePoints = prior.selections; draftContextReferences = prior.references }
        editingMessageID = nil; draftBeforeEditing = nil; flushDraft()
    }
    private func startResponse(_ text: String, resuming savedWork: WorkTurn? = nil, automaticResume: Bool = false, reconnectOnly: Bool = false) {
        guard let engine else { return }
        conversationSelectionID = UUID()
        let original = conversation, editID = editingMessageID, attachments = attachedCaptureIDs, fileAttachments = attachedFileIDs, selection = settings, healthData = draftContainsHealthData
        let imageSelections = selectedImagePoints.filter { key, _ in attachments.contains { $0.uuidString == key } }
        let contextReferences = draftContextReferences
        let previousIDs = Set(original.messages.map(\.id))
        draftTask?.cancel()
        isRunning = true; activity = "Preparing \(modelTitle)"; errorMessage = nil; noticeMessage = nil; flushDraft()
        responseWasBackgrounded = UIApplication.shared.applicationState != .active; userRequestedStop = false; pausedForInput = false; pausedForWorkBudget = false; responseAwaitingAttention = false; systemEndedBackgroundWork = false; activeTurnID = savedWork?.id
        taskAttention.clear(conversation.id)
        responseOnComputer = savedWork.map { $0.backendID.hasPrefix("companion:") }
            ?? (selection.choice == .chatGPT && selection.useComputer && selection.companion != nil && !selection.localOnly)
        let computerReply = responseOnComputer
        beginResponseWindow()
        replyActivity.begin(conversationID: original.id, modelName: modelTitle, computer: computerReply, reconnecting: savedWork != nil,
            externalPresentation: computerReply && activeComputerAccount?.activityProvider == "pushward")
        if computerReply { ReplyReturnRoute.remember(original.id) }
        requiresManualResume = false
        let previousTitleTask = titleTask
        previousTitleTask?.cancel(); titleTask = nil
        responseTask = Task {
            var current = original
            var signalledReply = false
            await previousTitleTask?.value
            var titleBackend: (any ModelBackend)?
            if let requestID = activeWatchRequestID {
                await publishWatch(WatchReply(requestID: requestID, conversationID: current.id, state: .working,
                    message: "Your iPhone is working on it.", modelName: modelTitle))
            }
            do {
                if selection.taskNotifications { await taskAttention.requestPermission() }
                try Task.checkCancellation()
                var selectedBackend: any ModelBackend
                if let savedWork { selectedBackend = try await backend(forSavedWork: savedWork, selection: selection) }
                else { selectedBackend = try await backend(for: selection, onComputer: computerReply) }
                if var computer = selectedBackend as? CompanionModelBackend {
                    computer.allowJobRestart = savedWork != nil && !automaticResume && !reconnectOnly
                    let client = computer.client
                    computer.onJobAccepted = { [weak self] jobID, provider in
                        await self?.attachRemoteActivity(jobID: jobID, client: client, provider: provider)
                    }
                    selectedBackend = computer
                }
                titleBackend = selectedBackend
                try Task.checkCancellation()
                if savedWork == nil, let editID, let store {
                    current = try await store.prepareMessageEdit(in: original, messageID: editID)
                    conversation = current; editingMessageID = nil; draftBeforeEditing = nil
                    if current.excludedArtifactIDs != original.excludedArtifactIDs || current.excludedSurfaceIDs != original.excludedSurfaceIDs || current.invalidatedProjectRevisions != original.invalidatedProjectRevisions {
                        noticeMessage = "Work changed by the removed messages is kept, but excluded from this revised chat. Project context will be rebuilt from the remaining conversation."
                    }
                } else { try await store?.save(current) }
                let extras = NativeTools.definitions + CommunicationTools.definitions + WorkspaceTools.definitions + PlanningTools.definitions + [QuestionTools.request]
                    + (computerReply ? [ComputerScheduleTools.create, ComputerFileTools.transfer, ComputerActionReview.definition] + ComputerTools.definitions : [])
                    + (selection.healthToolsEnabled && HealthOverviewService.isEnabledInThisBuild ? [HealthOverviewService.tool] + HealthDataReader.tools : [])
                let destination = selectedBackend.networkDestination
                let appContext = AssistantAppContext(planningConnected: (!selection.calendarSourceIDs.isEmpty && planning.calendarAuthorized) || (!selection.reminderSourceIDs.isEmpty && planning.remindersAuthorized),
                    planningSharedWithModel: selection.planningConnectedAccess, locationEnabled: selection.locationContextEnabled,
                    healthAvailable: HealthOverviewService.isEnabledInThisBuild, backgroundEnabled: selection.continueInBackground,
                    computerEnabled: computerReply, contactsEnabled: selection.contactsConnected && ContactsConnection.allowed)
                let execute: @Sendable (ToolCall) async throws -> ToolResult = { [weak self, conversationID = original.id] call in
                        guard let self else { throw CancellationError() }
                        return try await self.executeNativeTool(call, conversationID: conversationID, destination: destination)
                    }
                let events: AsyncThrowingStream<AssistantEvent, any Error>
                if let savedWork {
                    events = engine.resume(conversation: current, turnID: savedWork.id, backend: selectedBackend,
                        workspaceEnabled: selection.workspaceSearchEnabled, automaticMemory: selection.automaticMemory, additionalTools: extras, additionalExecutor: execute, appContext: appContext, automatic: automaticResume)
                    activity = "Continuing from saved work"
                } else {
                    events = engine.respond(conversation: current, text: text, captureIDs: attachments, backend: selectedBackend,
                        containsHealthData: healthData, fileIDs: fileAttachments, imageSelections: imageSelections, contextReferences: contextReferences, workspaceEnabled: selection.workspaceSearchEnabled,
                        automaticMemory: selection.automaticMemory, additionalTools: extras, additionalExecutor: execute, appContext: appContext)
                }
                for try await event in events {
                    switch event {
                    case .transportProgress(let bytes): completionWindow.received(bytes: bytes)
                    case .conversation(let updated):
                        conversation = updated
                        let newMessages = updated.messages.filter { !previousIDs.contains($0.id) }
                        if !signalledReply, newMessages.contains(where: { $0.role == .assistant && !$0.answerText.isEmpty }) {
                            signalledReply = true; AppFeedback.play(.reply)
                        }
                        // Reconnected projections retain their IDs. They must
                        // still drive live status, even if present before resume.
                        let streamingReply = updated.messages.last { $0.role == .assistant && $0.state == .streaming }
                        if let web = streamingReply?.displayParts.last?.web {
                            let title = ActivitySummaries.web([web]).title
                            completionWindow.status(title); replyActivity.update(title)
                        }
                        else if streamingReply?.answerText.isEmpty == false && activeToolCall == nil { completionWindow.status("Writing your reply"); replyActivity.update("Writing your reply") }
                        else { completionWindow.status(activity ?? (activeToolCall.map(ToolResultPresentation.activeTitle) ?? "Receiving reply")) }
                        if let user = updated.messages.last(where: \.isRequest) {
                            activeTurnID = savedWork?.id ?? user.id
                            completionWindow.identifyTurn(savedWork?.id ?? user.id)
                        }
                        if savedWork == nil, updated.messages.contains(where: { $0.role == .user && $0.text == text && !previousIDs.contains($0.id) }) {
                            if let id = routedInboxID, let entry = inbox.first(where: { $0.id == id && $0.text == text && $0.captureIDs == attachments }) { routedInboxID = nil; await finishInboxEntry(entry) }
                            attachedCaptureIDs = []
                            selectedImagePoints = [:]
                            attachedFileIDs = []
                            draftContextReferences = []
                            if draft == text || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft = ""; flushDraft() }
                        }
                    case .toolResult(let result):
                        completionWindow.received(bytes: (try? result.output.jsonString().utf8.count) ?? 0)
                        activeToolCall = nil; await refresh(); activity = "Preparing the result"
                    case .toolStarted(let call): activeToolCall = call; activity = nil; completionWindow.status(ToolResultPresentation.activeTitle(call)); replyActivity.update(ToolResultPresentation.activeTitle(call))
                    case .activity(let value):
                        activeToolCall = nil; activity = value
                        let reconnecting = value.localizedCaseInsensitiveContains("reconnect")
                        let waiting = value.localizedCaseInsensitiveContains("waiting")
                        let latest = conversation.messages.last(where: { $0.role == .assistant && $0.state == .streaming })
                        let title = !waiting && !reconnecting && latest?.displayParts.last?.web != nil ? ActivitySummaries.web([latest!.displayParts.last!.web!]).title : value
                        completionWindow.status(title); replyActivity.update(title, waiting: waiting, reconnecting: reconnecting)
                    case .finished: break
                    }
                }
            } catch {
                completionWindow.recordFailure(error)
                if let failure = error as? AssistantError, case .workBudgetReached = failure { pausedForWorkBudget = true; completionWindow.status("Progress saved · Ready to continue") }
                if let failure = error as? AssistantError, case .outputCapacity = failure { pausedForWorkBudget = true; completionWindow.status("Progress saved · Reply allowance reached") }
                if !Task.isCancelled && !(error is CancellationError) {
                    if activeTurnID == nil { noticeMessage = error.localizedDescription }
                }
            }
            await engine.waitUntilIdle()
            if let saved = try? await store?.loadConversation(current.id) { conversation = saved }
            var completedTurn = false
            if let id = activeTurnID, let work = try? await store?.workTurn(id) {
                completedTurn = work.phase == .completed
                if !completedTurn {
                    if userRequestedStop { try? await store?.finishWork(id, phase: .cancelled, reason: "Stopped by the user", kind: "cancelled") }
                    else if pausedForInput || responseAwaitingAttention { try? await store?.finishWork(id, phase: .interrupted, reason: "Waiting for your answer or review", kind: "waiting_for_input") }
                    else if computerReply, work.interruptionKind != "computer_sync_attention", let run = try? await store?.companionRun(id),
                            !["failed", "cancelled", "interrupted", "completed"].contains(run.status) {
                        try? await store?.finishWork(id, phase: .interrupted, reason: "Your task is saved. The chat will catch up when the connection returns.", kind: "computer_detached")
                    }
                    else if responseWasBackgrounded && (systemEndedBackgroundWork || work.phase == .cancelled) { try? await store?.finishWork(id, phase: .interrupted, reason: "Background processing ended or was cancelled. Your progress is saved.", kind: "system_ended") }
                }
            }
            requiresManualResume = !completedTurn && !handingOffToComputer
            let savedComputerRun = if let id = activeTurnID { try? await store?.companionRun(id) } else { nil as CompanionRunRecord? }
            let computerStillWorking = !completedTurn && !userRequestedStop && computerReply && savedComputerRun?.jobID != nil && !["failed", "interrupted", "cancelled", "completed"].contains(savedComputerRun?.status ?? "unknown")
            if computerStillWorking { requiresManualResume = false }
            await replyActivity.finish(completed: completedTurn, detached: computerStillWorking,
                handingOff: handingOffToComputer && !completedTurn, waiting: pausedForInput || responseAwaitingAttention,
                keepReady: UIApplication.shared.applicationState != .active)
            if completedTurn && UIApplication.shared.applicationState == .active {
                ReplyReturnRoute.clear(); await replyActivity.viewed(conversationID: current.id)
                if let jobID = savedComputerRun?.jobID { Task { await self.markComputerResultViewed(jobID: jobID) } }
            }
            if responseWasBackgrounded, !userRequestedStop, !handingOffToComputer, selection.taskNotifications, UIApplication.shared.applicationState != .active,
               !computerReply || !replyActivity.remoteNotificationsAvailable,
               completedTurn || !computerReply || pausedForInput || responseAwaitingAttention {
                await taskAttention.notify(conversationID: current.id, title: completedTurn ? "Your reply is ready" : "Your task needs attention",
                    explanation: completedTurn ? "Open Personal Assistant to see the answer and saved results." : "Progress is saved. Open the task to review what remains and continue.")
            }
            // Keep the same iOS processing window through the transfer and the
            // PC event subscription. Handoff is not user-task completion.
            // Final UI/notifications are delivered before ending execution time.
            if !handingOffToComputer || completedTurn {
                completionWindow.end(success: completedTurn || pausedForInput || pausedForWorkBudget || responseAwaitingAttention)
            }
            isRunning = false; responseTask = nil; activity = nil; activeToolCall = nil
            if completedTurn, let titleBackend, conversation.needsAutomaticTitle, selection.automaticChatTitles {
                let namedConversation = conversation
                let generationID = UUID(); titleGenerationID = generationID
                titleTask = Task { [weak self] in
                    let timeout = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(25))
                        if !Task.isCancelled, self?.titleGenerationID == generationID { self?.titleTask?.cancel() }
                    }
                    defer { timeout.cancel() }
                    do {
                        guard let title = try await ConversationNamer.generate(for: namedConversation, backend: titleBackend),
                              !Task.isCancelled, let self, let store = self.store else { return }
                        if try await store.saveAutomaticTitle(title, conversationID: namedConversation.id) {
                            if self.conversation.id == namedConversation.id && !self.isRunning {
                                self.conversation = try await store.loadConversation(namedConversation.id)
                            }
                            await self.refresh()
                        }
                    } catch { /* Naming is optional metadata; never replace a successful answer with an error. */ }
                }
            }
            if let requestID = activeWatchRequestID {
                activeWatchRequestID = nil
                let answer = conversation.messages.last(where: { $0.role == .assistant })
                let successful = completedTurn && errorMessage == nil && !Task.isCancelled && answer?.state == .complete && answer.map { !previousIDs.contains($0.id) } == true
                let text = successful ? String((answer?.text ?? "Completed on iPhone.").prefix(1000)) : "The task stopped or needs attention. Continue on your iPhone."
                await publishWatch(WatchReply(requestID: requestID, conversationID: conversation.id,
                    state: successful ? .complete : .needsPhone, message: text, modelName: modelTitle))
            }
            await refresh()
            if responseWasBackgrounded && !userRequestedStop && UIApplication.shared.applicationState == .active {
                Task { [weak self] in await self?.continueInterruptedReplyIfEligible() }
            }
        }
    }
    private func backend(forSavedWork work: WorkTurn, selection: ModelSettings) async throws -> any ModelBackend {
        guard work.backendID.hasPrefix("companion:"), let record = try await store?.companionRun(work.id) else {
            return try await backend(for: selection, onComputer: false)
        }
        let original = try ComputerTaskRecovery.selection(for: work, record: record, current: selection)
        let result = try await backend(for: original, onComputer: true)
        guard result.id == work.backendID else { throw AssistantError.provider("The original task connection could not be restored.") }
        return result
    }
    func backend(for selection: ModelSettings, onComputer: Bool = false) async throws -> any ModelBackend {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-local-isolation") {
            guard selection.choice == .appleOnDevice, !onComputer else { throw AssistantError.provider("The local-routing fixture refused a connected backend.") }
            return UILocalIsolationBackend()
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-interactions") { return UIInteractionBackend() }
        if ProcessInfo.processInfo.arguments.contains("--ui-product117") { return UIProductBackend() }
        if ProcessInfo.processInfo.arguments.contains("--ui-streaming") { return UIStreamingBackend() }
        if ProcessInfo.processInfo.arguments.contains("--ui-continuity") { return UIContinuityBackend() }
        if ProcessInfo.processInfo.arguments.contains("--ui-background") { return UIBackgroundBackend() }
        if ProcessInfo.processInfo.arguments.contains("--ui-long-task") { return UILongTaskBackend() }
        if ProcessInfo.processInfo.arguments.contains("--ui-daily-work") { return UIDailyWorkflowBackend(questionOnly: ProcessInfo.processInfo.arguments.contains("--ui-question-only")) }
        if ProcessInfo.processInfo.arguments.contains("--ui-recovery09") { return UIRecovery09Backend() }
        if ProcessInfo.processInfo.arguments.contains("--ui-coherence") { return UICoherenceBackend() }
        #endif
        switch selection.choice {
        case .localMLX:
            await localBackendTransition?.value
            try Task.checkCancellation()
            guard let localBackend else { throw AccountConnectionError.unavailable }; return localBackend
        case .appleOnDevice: return AppleModelBackend(location: .device)
        case .appleCloud: return AppleModelBackend(location: .privateCloud)
        case .chatGPT:
            if onComputer, selection.useComputer, let connection = selection.companion, let store {
                let token = try CredentialStore.read(account: connection.credentialAccount)
                guard !token.isEmpty else { throw AssistantError.provider("Reconnect your computer in Connections.") }
                let client = try CompanionClient(baseURL: connection.baseURL, fingerprint: connection.certificateSHA256, token: token)
                let wire = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: selection.chatGPTModel, wireProtocol: .responses,
                    chatGPTAccountID: connection.profileID, webSearchEnabled: selection.chatGPTWebSearch, reasoningEffort: selectedReasoningEffort, contextBudget: contextBudget(for: selection))
                return CompanionModelBackend(connection: connection, client: client, wire: wire, store: store, notificationsEnabled: selection.taskNotifications)
            }
            guard let account = selection.chatGPTAccountID, let accountService, !selection.chatGPTModel.isEmpty else { throw AccountConnectionError.signInRequired }
            let access = try await accountService.accessToken(for: account)
            return try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: selection.chatGPTModel,
                                           wireProtocol: .responses, credential: access, chatGPTAccountID: account, webSearchEnabled: selection.chatGPTWebSearch, reasoningEffort: selectedReasoningEffort, contextBudget: contextBudget(for: selection))
        case .openAI, .compatibleServer:
            guard let url = selection.endpoint else { throw AssistantError.invalidEndpoint("Add a valid server address in Connections.") }
            let credential = try selection.credentialAccount.map { try CredentialStore.read(account: $0) } ?? ""
            if selection.choice == .openAI && credential.isEmpty { throw AssistantError.provider("Add an OpenAI API key, or use Continue with ChatGPT in the model picker.") }
            return try NetworkModelBackend(baseURL: url, model: selection.choice == .openAI ? selection.openAIModel : selection.compatibleModel,
                wireProtocol: selection.choice == .openAI ? .responses : .chatCompletions, credential: credential, reasoningEffort: selection.choice == .openAI ? selectedReasoningEffort : nil, contextBudget: contextBudget(for: selection))
        }
    }

    func saveSettings(_ value: ModelSettings, credential: String = "") throws {
        guard !isRunning else { throw AssistantError.busy }
        let previous = settings
        let changedAccountRoute = value.useComputer != settings.useComputer || value.companion != settings.companion || value.localOnly != settings.localOnly
        guard !value.includeInDeviceBackup || !libraryContainsHealthData else { throw AssistantError.provider("A library containing Health-derived information stays excluded from device backups. You can export selected items yourself.") }
        guard credential.isEmpty || !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AssistantError.provider("Enter a connection credential, or leave the field empty to keep the saved credential.") }
        if let endpoint = value.endpoint { try EndpointPolicy.validate(endpoint) }
        guard let settingsURL else { throw AssistantError.provider("App storage is unavailable.") }
        let priorCredential = try (!credential.isEmpty ? value.credentialAccount.map { try CredentialStore.read(account: $0) } : nil)
        let backupChanged = value.includeInDeviceBackup != previous.includeInDeviceBackup
        do {
            if backupChanged, let root { try PrivatePaths.configureBackup(root: root, includeUserData: value.includeInDeviceBackup) }
            if !credential.isEmpty, let account = value.credentialAccount { try CredentialStore.save(credential, account: account) }
            #if DEBUG
            if failPreferenceWritesForTest { throw CocoaError(.fileWriteNoPermission) }
            #endif
            try JSONEncoder().encode(value).write(to: settingsURL, options: .atomic)
        } catch {
            var rollbackFailed = false
            if let account = value.credentialAccount, let priorCredential {
                do { if priorCredential.isEmpty { try CredentialStore.remove(account: account) } else { try CredentialStore.save(priorCredential, account: account) } }
                catch { rollbackFailed = true }
            }
            if backupChanged, let root { do { try PrivatePaths.configureBackup(root: root, includeUserData: previous.includeInDeviceBackup) } catch { rollbackFailed = true } }
            if rollbackFailed { throw AssistantError.provider("The preferences were not committed, and a system-storage change could not be restored. Unlock the iPhone and review the connection and backup settings before retrying.") }
            throw error
        }
        if value.choice != settings.choice || value.networkDestination != settings.networkDestination || value.localRepository != settings.localRepository
            || value.chatGPTModel != settings.chatGPTModel || value.openAIModel != settings.openAIModel || value.localOnly || !value.automaticChatTitles {
            titleTask?.cancel(); activity = nil; activeToolCall = nil; noticeMessage = nil; responseWasBackgrounded = false
        }
        let leavingLocal = settings.choice == .localMLX && value.choice != .localMLX
        let changedLocal = value.localRepository != settings.localRepository || value.localRevision != settings.localRevision || value.localResponseTokens != settings.localResponseTokens
            || value.localContextTokens != settings.localContextTokens || value.localMemoryGiB != settings.localMemoryGiB
        settings = value
        if let computerAccount, value.companion.map({ computerAccount.matches($0) }) != true {
            self.computerAccount = nil
            if let computerAccountURL { try? FileManager.default.removeItem(at: computerAccountURL) }
        }
        if changedAccountRoute {
            computerAccountReachability = .unchecked
            modelCatalog = .init()
            Task { await refreshAccounts() }
        }
        if value.localOnly { cancelConnection(); stopDownload() }
        if changedLocal { rebuildLocalBackend() }
        else if leavingLocal { releaseLocalBackend(localBackend) }
    }
    #if DEBUG
    var failPreferenceWritesForTest = false
    #endif
    func updatePreference<Value>(_ key: WritableKeyPath<ModelSettings, Value>, to value: Value) throws {
        var next = settings; next[keyPath: key] = value; try saveSettings(next)
    }
    func setPlanningAccess(calendars: [String], reminders: [String], connected: Bool) throws {
        guard let settingsURL else { throw AssistantError.provider("App storage is unavailable.") }
        settings.calendarSourceIDs = calendars; settings.reminderSourceIDs = reminders; settings.planningConnectedAccess = connected
        try JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic)
        Task { await planning.refreshHome(settings: settings) }
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
    func chooseSavedChatGPTModel() {
        guard !settings.chatGPTModel.isEmpty else { return }
        var next = settings; next.choice = .chatGPT
        do { try saveSettings(next); showModels = false } catch { errorMessage = error.localizedDescription }
    }
    func clearCredential() throws { if let account = settings.credentialAccount { try CredentialStore.remove(account: account) } }
    var localBackendResidentBytes: Int64 { localBackend?.residentBytes ?? 0 }
    func localRuntimeBudget(memoryGiB: Int, contextTokens: Int?, availableBytes: Int64) -> LocalInferenceBudget? {
        localBackend?.planningBudget(memoryGiB: memoryGiB, contextTokens: contextTokens, availableBytes: availableBytes)
    }
    private func rebuildLocalBackend() {
        guard let modelRoot else { return }
        let previous = localBackend
        localBackend = MLXLocalBackend(repository: settings.localRepository, revision: settings.localRevision, root: modelRoot, responseTokens: settings.localResponseTokens, supportsVision: catalog.first { $0.id == settings.localRepository }?.supportsVision ?? true, weightBytes: catalog.first { $0.id == settings.localRepository }?.weightBytes ?? 0, textWeightBytes: catalog.first { $0.id == settings.localRepository }?.textWeightBytes,
            requestedContextTokens: settings.localContextTokens, requestedMemoryGiB: settings.localMemoryGiB)
        releaseLocalBackend(previous)
    }
    private func releaseLocalBackend(_ backend: MLXLocalBackend?) {
        let pending = localBackendTransition
        localBackendTransition = Task {
            await pending?.value
            try? await backend?.unload()
        }
    }
    func refreshDownloads() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-qwen-memory") {
            downloadedModelIDs = ["mlx-community/Qwen3.5-4B-4bit"]; return
        }
        #endif
        guard let modelRoot else { return }
        var ready = Set<String>()
        for entry in catalog {
            let backend = MLXLocalBackend(repository: entry.id, revision: entry.revision, root: modelRoot, responseTokens: settings.localResponseTokens, supportsVision: entry.supportsVision, weightBytes: entry.weightBytes ?? 0)
            if await backend.isDownloaded() { ready.insert(entry.id) }
        }
        if let localBackend, await localBackend.isDownloaded() { ready.insert(settings.localRepository) }
        downloadedModelIDs = ready
    }
    func downloadModel(_ entry: LocalModelCatalogEntry) {
        guard !settings.localOnly else { noticeMessage = "Turn off on-device-only mode to download model files, then enable it again for offline use."; return }
        guard !isDownloading, !(isRunning && settings.choice == .localMLX), let modelRoot else { return }
        let backend = MLXLocalBackend(repository: entry.id, revision: entry.revision, root: modelRoot, responseTokens: settings.localResponseTokens, supportsVision: entry.supportsVision, weightBytes: entry.weightBytes ?? 0)
        isDownloading = true; downloadingModelID = entry.id; downloadProgress = 0; modelStatus = "Downloading \(entry.name)"
        let allowCellular = settings.allowCellularDownloads
        downloadTask = Task {
            defer { isDownloading = false; downloadingModelID = nil; downloadTask = nil }
            do {
                try await backend.download(allowCellular: allowCellular, expectedFiles: entry.files) { [weak self] value in
                    Task { @MainActor in self?.downloadProgress = value; if value >= 1 { self?.modelStatus = "Verifying model files" } }
                }
                modelStatus = "\(entry.name) downloaded"; await refreshDownloads()
            } catch {
                modelStatus = Task.isCancelled ? "Download stopped" : "Download needs attention"
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }
    func modelStorage(_ entry: LocalModelCatalogEntry, cacheOnly: Bool = false, remove: Bool = false) async throws -> Int64 {
        guard let modelRoot, !isDownloading, !isRunning else { throw AssistantError.busy }
        let backend: MLXLocalBackend
        if entry.id == settings.localRepository, let localBackend { backend = localBackend }
        else { backend = MLXLocalBackend(repository: entry.id, revision: entry.revision, root: modelRoot, responseTokens: settings.localResponseTokens) }
        if remove {
            let bytes = try await backend.removeStoredFiles(cacheOnly: cacheOnly)
            await refreshDownloads(); return bytes
        }
        return try await backend.storageBytes(cacheOnly: cacheOnly)
    }
    func stopDownload() { downloadTask?.cancel() }
    func importModel(_ entry: LocalModelCatalogEntry, folder: URL) {
        guard !isDownloading, !(isRunning && settings.choice == .localMLX), let modelRoot else { return }
        let scoped = folder.startAccessingSecurityScopedResource()
        let backend = MLXLocalBackend(repository: entry.id, revision: entry.revision, root: modelRoot, responseTokens: settings.localResponseTokens, supportsVision: entry.supportsVision, weightBytes: entry.weightBytes ?? 0)
        isDownloading = true; downloadingModelID = entry.id; downloadProgress = 0; modelStatus = "Importing \(entry.name)"
        downloadTask = Task {
            defer { if scoped { folder.stopAccessingSecurityScopedResource() }; isDownloading = false; downloadingModelID = nil; downloadTask = nil }
            do {
                try await backend.importFolder(folder, expectedFiles: entry.files) { [weak self] progress in
                    Task { @MainActor in self?.downloadProgress = progress; if progress >= 1 { self?.modelStatus = "Verifying imported files" } }
                }
                modelStatus = "\(entry.name) imported"; await refreshDownloads()
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
            catch { localRecovery = LocalRecovery(conversationID: nil, category: .connection, title: "ChatGPT connection needs attention", detail: error.localizedDescription, retained: "Your account records, pairing, saved chats and unsent draft are kept."); return }
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
                if !(error is CancellationError) { localRecovery = LocalRecovery(conversationID: nil, category: .connection, title: "ChatGPT connection needs attention", detail: error.localizedDescription, retained: "Your account records, pairing, saved chats and unsent draft are kept.") }
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
        guard isRunning, conversation.id == conversationID else { throw CancellationError() }
        if PlanningTools.names.contains(call.name) { return try await executePlanningTool(call, destination: destination) }
        if call.name == QuestionTools.request.name { return try await executeQuestionTool(call, conversationID: conversationID) }
        if WorkspaceTools.names.contains(call.name) { return try await executeWorkspaceTool(call, conversationID: conversationID, destination: destination) }
        if CommunicationTools.names.contains(call.name) { return try await executeCommunicationTool(call, conversationID: conversationID) }
        if call.name == ComputerScheduleTools.create.name { return try await executeScheduleTool(call) }
        if call.name == ComputerFileTools.transfer.name { return try await transferFileToComputer(call, conversationID: conversationID) }
        if call.name == ComputerActionReview.definition.name { return try await reviewComputerAction(call) }
        if ComputerTools.names.contains(call.name) { return try await executeComputerTool(call, conversationID: conversationID) }
        func nativeResult(_ value: JSONValue) -> ToolResult {
            ToolResult(callID: call.id, name: call.name, succeeded: !["failed", "outcome_unknown", "interrupted"].contains(value["status"]?.stringValue ?? ""), output: value)
        }
        switch call.name {
        case NativeTools.route.name, NativeTools.readRoute.name:
            return nativeResult(try await executeRouteTool(call, conversationID: conversationID))
        case NativeTools.device.name: return nativeResult(DeviceContext.snapshot())
        case NativeTools.context.name:
            var context: [String: JSONValue] = ["model": .string(modelTitle), "processing": .string(modelLocation),
                "current_time": .string(ISO8601DateFormatter().string(from: Date())), "time_zone": .string(TimeZone.current.identifier),
                "selected_calendar_count": .number(Double(settings.calendarSourceIDs.count)), "selected_reminder_list_count": .number(Double(settings.reminderSourceIDs.count)), "planning_connected_access": .bool(settings.planningConnectedAccess),
                "automatic_memory": .bool(settings.automaticMemory), "workspace_history_enabled": .bool(settings.workspaceSearchEnabled),
                "location_context_enabled": .bool(settings.locationContextEnabled), "location_authorization": .string(locationService.authorizationSummary),
                "local_only": .bool(settings.localOnly), "background_tracking": .bool(false), "weather": .null,
                "continued_background_requested": .bool(settings.continueInBackground), "task_notifications_enabled": .bool(TaskPresentationPolicy.isEnabled && settings.taskNotifications)]
            if !settings.localOnly, let weather = try await store?.cachedHomeWeather(), weather.isFresh(),
               (settings.weatherFollowsLocation && settings.locationContextEnabled && weather.place.name == "Nearby") || (!settings.weatherFollowsLocation && settings.weatherPlace == weather.place) {
                context["weather"] = .object(["place": .string(weather.place.name), "celsius": .number(weather.celsius), "conditions": .string(weather.condition),
                    "observed_at": .string(ISO8601DateFormatter().string(from: weather.observedAt)), "source": .string("Open-Meteo cached weather estimate")])
            }
            return nativeResult(.object(context))
        case NativeTools.pdf.name:
            guard let filename = call.arguments["filename"]?.stringValue, filename.lowercased().hasSuffix(".pdf"), let store else { throw AssistantError.invalidTool("Choose a filename ending in .pdf.") }
            try WorkspaceFile.validateFilename(filename)
            let (data, text) = try PDFDocumentWriter.make(title: call.arguments["title"]?.stringValue ?? "", markdown: call.arguments["markdown"]?.stringValue ?? "")
            let file = WorkspaceFile(filename: filename, mediaType: "application/pdf", byteCount: data.count, text: text,
                extractionNote: "PDF generated on this iPhone. Text layout; original Markdown formatting and images are not embedded.",
                conversationID: conversationID, containsHealthData: conversation.containsHealthData)
            guard let verified = PDFDocument(data: data), verified.pageCount > 0, !verified.isLocked else { throw AssistantError.invalidTool("The generated PDF could not be reopened for verification.") }
            try await store.saveWorkspaceFile(file, data: data)
            let output = try await store.publishOutput(id: file.id, filename: filename, data: data, conversationID: conversationID)
            return nativeResult(.object(["file_id": .string(file.id.uuidString), "filename": .string(filename), "bytes": .number(Double(data.count)),
                "page_count": .number(Double(verified.pageCount)), "verification": .string("PDF reopened successfully"),
                "saved_to": .string(output?.status == "saved_local" ? output!.location : "App Library"), "warning": output?.warning.map(JSONValue.string) ?? .null]))
        case NativeTools.location.name:
            let purpose = String((call.arguments["reason"]?.stringValue ?? "").prefix(500))
            if !settings.locationContextEnabled {
                let status = try await reviewNativeAction(NativeActionRequest(kind: .approval, title: "Use your current location?", detail: purpose + "\n\nThis location fix will be available to \(modelTitle) in this conversation. Enable location context on the home screen to remember this permission for future requests.", arguments: call.arguments))
                guard status == "approved" else { return nativeResult(.object(["status": .string(status == "cancelled" ? "cancelled" : "interrupted"), "location_shared": .bool(false)])) }
            }
            return nativeResult(try await locationService.read())
        case NativeTools.calendar.name:
            let formatter = ISO8601DateFormatter()
            guard let start = formatter.date(from: call.arguments["start"]?.stringValue ?? ""), let end = formatter.date(from: call.arguments["end"]?.stringValue ?? ""),
                  end > start, end.timeIntervalSince(start) <= 366 * 86400, let title = call.arguments["title"]?.stringValue, !title.isEmpty, title.count <= 300,
                  (call.arguments["notes"]?.stringValue?.count ?? 0) <= 8000, (call.arguments["location"]?.stringValue?.count ?? 0) <= 500 else { throw AssistantError.invalidTool("Use a short title, valid ISO8601 dates with time zones, and an end after the start.") }
            let status = try await reviewNativeAction(NativeActionRequest(kind: .calendar, title: "Review event", detail: "", arguments: call.arguments))
            guard status == "saved" else { return nativeResult(.object(["status": .string(status == "cancelled" ? "cancelled" : "outcome_unknown"), "completed_action_confirmed": .bool(false)])) }
            return nativeResult(.object(["status": .string("saved_by_user"), "proposed_title": .string(title),
                "note": .string("The user may have edited details in Apple's editor. The app did not query the saved event contents.")]))
        case NativeTools.message.name:
            guard MFMessageComposeViewController.canSendText(), let body = call.arguments["body"]?.stringValue, body.count <= 8000,
                  let recipients = call.arguments["recipients"]?.stringValue, recipients.count <= 300 else { throw AssistantError.invalidTool("Text messaging is unavailable or the proposed message is too long.") }
            let status = try await reviewNativeAction(NativeActionRequest(kind: .message, title: "Review message", detail: "", arguments: call.arguments))
            guard status == "sent" else { return nativeResult(.object(["status": .string(status == "cancelled" ? "cancelled" : status == "failed" ? "failed" : "outcome_unknown"), "delivery_confirmed": .bool(false), "notice": .string("Do not retry sending automatically.")])) }
            return nativeResult(.object(["status": .string("system_reported_sent"), "delivery_confirmed": .bool(false)]))
        case NativeTools.maps.name, NativeTools.phone.name:
            let url: URL, title: String, detail: String
            if call.name == NativeTools.maps.name {
                let query = call.arguments["query"]?.stringValue ?? ""
                guard !query.isEmpty, query.count <= 500 else { throw AssistantError.invalidTool("Provide a short place name or address.") }
                var components = URLComponents(string: "https://maps.apple.com/")!; components.queryItems = [URLQueryItem(name: "q", value: query)]
                url = components.url!; title = "Open in Maps?"; detail = query
            } else {
                let number = call.arguments["number"]?.stringValue ?? ""
                guard (3...25).contains(number.count), number.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "+") }), number.filter({ $0 == "+" }).count <= 1,
                      !number.dropFirst().contains("+"), let phoneURL = URL(string: "tel:" + number) else { throw AssistantError.invalidTool("Use digits with an optional leading plus. Dialer control codes are not supported.") }
                url = phoneURL; title = "Open this number in Phone?"; detail = number + "\n\n" + String((call.arguments["reason"]?.stringValue ?? "").prefix(500))
            }
            let status = try await reviewNativeAction(NativeActionRequest(kind: .approval, title: title, detail: detail, arguments: call.arguments))
            guard status == "approved" else { return nativeResult(.object(["status": .string(status == "cancelled" ? "cancelled" : "interrupted"), "completed_action_confirmed": .bool(false)])) }
            try Task.checkCancellation()
            let opened = await UIApplication.shared.open(url)
            guard opened else { throw AssistantError.invalidTool("iOS could not open the requested app action.") }
            return nativeResult(.object(["status": .string("handed_to_system"), "completed_action_confirmed": .bool(false)]))
        default: break
        }
        guard isRunning, conversation.id == conversationID, settings.healthToolsEnabled,
              [HealthOverviewService.tool.name, "list_health_types", "read_health_data"].contains(call.name) else {
            throw AssistantError.invalidTool("The requested Health context is unavailable.")
        }
        if call.name == "list_health_types" {
            return nativeResult(HealthDataReader.catalog(query: call.arguments["query"]?.stringValue ?? "", selected: settings.healthTypeIDs))
        }
        let query: HealthDataQuery?
        let readDescription: String
        if call.name == "read_health_data" {
            guard let ids = try JSONValue.parse(call.arguments["types_json"]?.stringValue ?? "[]").arrayValue,
                  ids.allSatisfy({ $0.stringValue != nil }) else { throw AssistantError.invalidTool("Use a list of Health type IDs.") }
            let value = try HealthDataQuery(typeIDs: ids.compactMap(\.stringValue), start: call.arguments["start"]?.stringValue ?? "", end: call.arguments["end"]?.stringValue ?? "",
                mode: call.arguments["mode"]?.stringValue ?? "", limit: Int(call.arguments["limit"]?.stringValue ?? "") ?? 0)
            guard Set(value.typeIDs).isSubset(of: settings.healthTypeIDs) else { throw AssistantError.invalidTool("Connect these data types in Connections → Health → Connected data first.") }
            query = value
            let names = HealthDataCatalog.entries.filter { value.typeIDs.contains($0.id) }.map(\.name).joined(separator: ", ")
            readDescription = "Read \(names), from \(value.start.formatted(date: .abbreviated, time: .omitted)) through \(value.end.formatted(date: .abbreviated, time: .omitted))."
        } else {
            guard call.arguments["days"]?.stringValue == "7" else { throw AssistantError.invalidTool("The overview covers seven days.") }
            query = nil; readDescription = "Read the connected steps, sleep and workout data for your seven-day overview."
        }
        if let destination, !conversation.allowedHealthDestinations.contains(destination) {
            let review = try await reviewNativeAction(.init(kind: .approval, title: "Use Health in this conversation?",
                detail: readDescription + " Share the result with \(modelTitle) for this conversation.", arguments: call.arguments))
            guard review == "approved" else { throw AssistantError.networkNotAuthorized }
            conversation.allowedHealthDestinations.insert(destination)
        }
        libraryContainsHealthData = true
        settings.includeInDeviceBackup = false
        if let root { try PrivatePaths.configureBackup(root: root, includeUserData: false) }
        if let settingsURL { try JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic) }
        let healthOutput: JSONValue
        if let query {
            healthOutput = try await HealthDataReader().read(query, selected: settings.healthTypeIDs)
        } else {
            let report = try await healthService.overview(selected: settings.healthTypeIDs)
            healthOutput = .object(["summary": .string(try report.discussionText()), "source": .string("Apple HealthKit"), "read_at": .string(ISO8601DateFormatter().string(from: report.rangeEnd))])
        }
        try Task.checkCancellation()
        var result = ToolResult(callID: call.id, name: call.name, succeeded: true,
            output: healthOutput)
        result.containsHealthData = true; result.authorizedHealthDestination = destination
        return result
    }
    func reviewNativeAction(_ request: NativeActionRequest) async throws -> String {
        guard nativeActionWaiter == nil else { throw AssistantError.invalidTool("Finish the current review before another action.") }
        let identity = ToolExecutionContext.current
        if let identity {
            try await store?.setOperationWaitingForReview(turnID: identity.turnID, callID: identity.callID, waiting: true)
        }
        guard nativeActionWaiter == nil else { throw AssistantError.invalidTool("Another review is already waiting. Finish it before another action.") }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let result: String = try await withCheckedThrowingContinuation { continuation in
                nativeActionWaiter = continuation; nativeActionWaiterID = request.id; activity = "Waiting for your review"
                responseAwaitingAttention = true
                completionWindow.status(request.kind == .question ? "Your answer is needed" : "Ready for your review")
                deferredNativeAction = request; deferredReviewIdentity = identity
                Task {
                    await presentDeferredReview()
                    await notifyReview(request)
                    // Persist and schedule attention before releasing the CPU
                    // grant; otherwise suspension can prevent notification delivery.
                    if isPendingNativeAction(request.id), responseAwaitingAttention {
                        completionWindow.waitingForAttention(question: request.kind == .question)
                    }
                }
            }
            try Task.checkCancellation()
            return result
        } onCancel: { Task { @MainActor [weak self] in
            guard self?.isPendingNativeAction(request.id) == true else { return }
            self?.resolveNativeAction("interrupted", for: request.id)
        } }
    }
    func resolveNativeAction(_ status: String, for requestID: UUID? = nil) {
        if let requestID, nativeActionWaiterID != requestID { return }
        let waiter = nativeActionWaiter; nativeActionWaiter = nil; nativeActionWaiterID = nil; nativeAction = nil; deferredNativeAction = nil; deferredReviewIdentity = nil
        taskAttention.clear(conversation.id)
        if waiter != nil, responseAwaitingAttention, status != "interrupted", !userRequestedStop,
           UIApplication.shared.applicationState == .active {
            responseAwaitingAttention = false
            beginResponseWindow()
        }
        waiter?.resume(returning: status)
    }
    func isPendingNativeAction(_ id: UUID) -> Bool { nativeActionWaiterID == id && nativeActionWaiter != nil }
    private func presentDeferredReview() async {
        guard !nativeReviewVisible, UIApplication.shared.applicationState == .active, let request = deferredNativeAction, isPendingNativeAction(request.id) else { return }
        let identity = deferredReviewIdentity
        do {
            if let identity {
                try await store?.setOperationWaitingForReview(turnID: identity.turnID, callID: identity.callID, waiting: request.kind == .question)
            }
            guard isPendingNativeAction(request.id) else { return }
            guard UIApplication.shared.applicationState == .active else {
                if let identity { try await store?.setOperationWaitingForReview(turnID: identity.turnID, callID: identity.callID, waiting: true) }
                return
            }
            deferredNativeAction = nil; nativeReviewVisible = true; nativeAction = request
            if request.kind == .question { AppFeedback.play(.question) }
        } catch { resolveNativeAction("interrupted", for: request.id); noticeMessage = error.localizedDescription }
    }
    func nativeReviewDidDismiss() {
        nativeReviewVisible = false
        if let work = questionResumeAfterDismiss {
            questionResumeAfterDismiss = nil
            Task { await resumeReply(work) }
        } else { Task { await presentDeferredReview() } }
    }
    private func notifyReview(_ request: NativeActionRequest) async {
        guard !responseOnComputer || !replyActivity.remoteNotificationsAvailable else { return }
        guard settings.taskNotifications, UIApplication.shared.applicationState != .active, isPendingNativeAction(request.id) else { return }
        await taskAttention.notify(conversationID: conversation.id, title: request.kind == .question ? "Your answer is needed" : "Your review is needed",
            explanation: request.kind == .question ? String(request.detail.prefix(200)) : request.kind == .message ? "A message draft is ready. Open the app to review it before sending." : request.kind == .calendar ? "An event is ready. Open the app to review it before saving." : "Your task is waiting for a choice or approval. Open the app to review the next step.")
    }
    func openTaskAttention(_ id: UUID) async {
        attentionDestination = id
        if !isInitialized { isRestoringBackgroundRoute = true }
        defer { if attentionDestination == id { attentionDestination = nil; isRestoringBackgroundRoute = false } }
        do { try await waitUntilReady() } catch { return }
        guard attentionDestination == id else { return }
        await replyActivity.viewed(conversationID: id)
        if isRunning {
            if conversation.id == id { ReplyReturnRoute.clear(); await presentDeferredReview() }
            else { noticeMessage = "Another task is running. Its progress is saved in the sidebar." }
            return
        }
        await refresh()
        guard let summary = histories.first(where: { $0.id == id }) else { return }
        await selectConversation(summary)
        ReplyReturnRoute.clear()
        if let work = unfinishedReplies.first(where: { $0.conversationID == id }),
           let record = try? await store?.companionRun(work.id), !record.stopRequested {
            await resumeReply(work, reconnectOnly: true); return
        }
        if let work = unfinishedReplies.first(where: { $0.conversationID == id }),
           let evidence = try? await store?.workEvidence(work.id, conversationID: id, remote: settings.networkDestination != nil, workspaceEnabled: settings.workspaceSearchEnabled),
           evidence["actions"]?.arrayValue?.contains(where: { $0["status"] == .string("awaiting_review") }) == true {
            await resumeReply(work)
        }
    }
    private func beginResponseWindow() {
        let continued = TaskPresentationPolicy.isEnabled && !responseOnComputer && settings.continueInBackground && [.chatGPT, .openAI, .compatibleServer].contains(settings.choice)
        completionWindow.begin(allowContinued: continued, preservingCurrent: handingOffToComputer) { [weak self] cancelledBySystem in
            guard let self else { return }
            self.systemEndedBackgroundWork = !self.responseOnComputer && cancelledBySystem
            self.pauseResponseForBackground()
        }
        if let activeTurnID { completionWindow.identifyTurn(activeTurnID) }
    }
    private func attachRemoteActivity(jobID: String, client: CompanionClient, provider: String? = nil) {
        replyActivity.attach(jobID: jobID, client: client, notifications: settings.taskNotifications, externalPresentation: provider == "pushward")
    }
    private func handoffResponseToComputer() {
        guard computerHandoff == nil, let connection = settings.companion, let store else { return }
        computerHandoff = Task {
            defer {
                if handingOffToComputer && !isRunning { completionWindow.end(success: false) }
                computerHandoff = nil; handingOffToComputer = false
            }
            do {
                let selection = settings
                let client = try CompanionClient(baseURL: connection.baseURL, fingerprint: connection.certificateSHA256, token: CredentialStore.read(account: connection.credentialAccount))
                // Probe before disturbing a healthy direct response. This makes
                // an unavailable PC irrelevant to ordinary phone conversations.
                let info = try await client.json("/v1/capabilities")
                // A just-sent request may still be obtaining the direct account
                // connection. Wait for its durable turn before handing it over.
                while activeTurnID == nil && isRunning && !userRequestedStop && settings == selection && UIApplication.shared.applicationState != .active {
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard info["profile"]?["status"] == .string("connected"), info["profile"]?["sharing"] == .bool(true),
                      isRunning, !responseOnComputer, !userRequestedStop, !pausedForInput, !responseAwaitingAttention,
                      activeToolCall == nil || ComputerTools.names.contains(activeToolCall?.arguments["name"]?.stringValue ?? activeToolCall?.name ?? ""),
                      UIApplication.shared.applicationState != .active, settings == selection,
                      let turn = activeTurnID, let prior = responseTask else { return }
                let chat = try await store.loadConversation(conversation.id)
                guard !chat.networkDisabled, !chat.messages.contains(where: \.containsLocalOnlyContext),
                      !chat.containsHealthData || chat.allowedHealthDestinations.contains(connection.destination) else { return }
                let owner = try await backend(for: selection, onComputer: true)
                handingOffToComputer = true
                completionWindow.handoff()
                prior.cancel(); await prior.value
                guard !userRequestedStop, settings == selection, var work = try await store.workTurn(turn), work.phase != .completed,
                      let latest = try? await store.loadConversation(chat.id), latest.messages.last(where: \.isRequest)?.id == work.userMessageID else { return }
                var transferred = latest
                transferred.allowedNetworkDestinations.insert(connection.destination)
                try await store.save(transferred)
                work.backendID = owner.id; work.destination = owner.networkDestination; work.phase = .interrupted
                work.reason = "Continuing your saved task"; work.interruptionKind = "computer_handoff"; work.automaticResumes = 0
                var configuration = work.configuration.objectValue ?? [:]
                configuration["handoff_message_count"] = .number(Double(transferred.messages.count))
                work.configuration = .object(configuration)
                try await store.saveWorkTurn(work)
                try Task.checkCancellation()
                guard !userRequestedStop else { try await store.finishWork(turn, phase: .cancelled, reason: "Stopped by the user", kind: "cancelled"); return }
                conversation = transferred
                startResponse("", resuming: work, reconnectOnly: true)
            } catch {
                // Keep the direct request running when the PC cannot accept a
                // handoff. Its existing iOS completion window remains in use.
                if handingOffToComputer { noticeMessage = "Your latest progress is saved. Reopen this chat to continue when the connection is available." }
            }
        }
    }
    func refreshAccounts(force: Bool = false) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-coherence") { return }
        if ProcessInfo.processInfo.arguments.contains("--ui-product117") { return }
        #endif
        let refreshID = UUID(); accountRefreshID = refreshID
        guard !settings.localOnly else { modelCatalog = .init(); return }
        if settings.useComputer, !settings.localOnly, let connection = settings.companion {
            guard let owner = modelCatalogOwner else { return }
            modelCatalog.begin(owner: owner, saved: savedModelCatalogs[owner])
            computerAccountReachability = .checking
            var verifiedAccount = false
            do {
                let client = try CompanionClient(baseURL: connection.baseURL, fingerprint: connection.certificateSHA256,
                    token: CredentialStore.read(account: connection.credentialAccount))
                let capabilities = try await client.json("/v1/capabilities")
                guard accountRefreshID == refreshID, settings.companion == connection, usesComputerChatGPT, !settings.localOnly else { return }
                try applyComputerAccount(capabilities["profile"] ?? .null, connection: connection, activityProvider: capabilities["presentation"]?["provider"]?.stringValue)
                verifiedAccount = true
                guard activeComputerAccount?.isConnected == true else {
                    modelCatalog = .init(); modelCatalog.begin(owner: owner, saved: nil)
                    modelCatalog.failed(owner: owner, message: computerAccountDetail); return
                }
                let catalog = try await client.json(force ? "/v1/models?refresh=1" : "/v1/models")
                guard accountRefreshID == refreshID, settings.companion == connection, usesComputerChatGPT, !settings.localOnly else { return }
                let observation = try ModelCatalogState.computerObservation(catalog, profileID: connection.profileID, owner: owner)
                if observation.phase == .unavailable {
                    modelCatalog.failed(owner: owner, message: observation.issue ?? "Current model availability could not be checked. Your sign-in is saved.")
                } else {
                    keepModelCatalog(AccountModelCatalog(owner: owner, models: observation.models, updatedAt: observation.updatedAt ?? Date()), staleReason: observation.issue)
                }
            } catch {
                guard accountRefreshID == refreshID, settings.companion == connection, usesComputerChatGPT, !settings.localOnly else { return }
                modelCatalog.failed(owner: owner, message: verifiedAccount ? "Your sign-in is saved, but the model list could not refresh. \(error.localizedDescription)" : "The computer could not be reached. Saved model choices remain available.")
                if !verifiedAccount { computerAccountReachability = .unavailable }
            }
            return
        }
        guard let accountService else {
            if let owner = modelCatalogOwner { modelCatalog.failed(owner: owner, message: "The saved account could not be opened. Check your account connection in Settings.") }
            return
        }
        accounts = await accountService.summaries()
        let savedID = await accountService.selectedID()
        guard let id = settings.chatGPTAccountID ?? savedID else { modelCatalog = .init(); return }
        settings.chatGPTAccountID = id
        let owner = "account:" + id
        modelCatalog.begin(owner: owner, saved: savedModelCatalogs[owner])
        do {
            let models = try await accountService.models(for: id)
            guard accountRefreshID == refreshID, modelCatalogOwner == owner else { return }
            keepModelCatalog(AccountModelCatalog(owner: owner, models: models))
            // Initial selection is allowed; never replace an existing choice
            // merely because the service omitted it from a new catalog.
            if !isRunning && settings.chatGPTModel.isEmpty { settings.chatGPTModel = chatGPTModels.first?.id ?? "" }
            if let settingsURL { try JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic) }
        } catch {
            guard accountRefreshID == refreshID, modelCatalogOwner == owner else { return }
            modelCatalog.failed(owner: owner, message: error.localizedDescription)
        }
    }
    private func keepModelCatalog(_ snapshot: AccountModelCatalog, staleReason: String? = nil) {
        guard modelCatalogOwner == snapshot.owner else { return }
        modelCatalog.receive(snapshot, staleReason: staleReason)
        savedModelCatalogs[snapshot.owner] = snapshot
        if savedModelCatalogs.count > 8, let oldest = savedModelCatalogs.values.min(by: { $0.updatedAt < $1.updatedAt }) { savedModelCatalogs.removeValue(forKey: oldest.owner) }
        if let modelCatalogURL { try? JSONEncoder().encode(savedModelCatalogs).write(to: modelCatalogURL, options: .atomic) }
    }
    func applyComputerAccount(_ profile: JSONValue, connection: CompanionConnection, activityProvider: String? = nil) throws {
        guard settings.companion == connection else { return }
        let record = try ComputerAccountRecord(connection: connection, profile: profile, activityProvider: activityProvider)
        computerAccount = record; computerAccountReachability = .reachable
        if let computerAccountURL, let data = try? JSONEncoder().encode(record) { try? data.write(to: computerAccountURL, options: .atomic) }
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
    private func installWorkspaceFixture() async {
        guard let store, let workspaceService else { return }
        do {
            settings.choice = .chatGPT; settings.chatGPTModel = "gpt-6.1-sol"
            chatGPTModels = try ChatGPTModel.catalog(from: Data(#"{"models":[{"slug":"gpt-6.1-sol","display_name":"GPT-6.1-Sol","visibility":"list"}]}"#.utf8))
            if let index = conversation.messages.lastIndex(where: { $0.role == .assistant }) {
                conversation.messages[index].citations = (1...4).compactMap { WebCitation(title: "Reference \($0)", url: "https://example.com/source-\($0)") }
                try await store.save(conversation)
            }
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let selected = documents.appendingPathComponent("Sample workspace")
            try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
            try Data("Project notes\n\nThis is a synthetic folder document. Verified total: 60.5.".utf8).write(to: selected.appendingPathComponent("notes.md"), options: .atomic)
            let folder = try await workspaceService.connect(selected)
            conversation.workspaceIDs.insert(folder.id)
            try await store.save(conversation)
            await refreshWorkspaces()
            let id = UUID(uuidString: "00000000-0000-4000-8000-000000000040")!
            _ = try await store.publishOutput(id: id, filename: "verified-total.csv", data: Data("value\n60.5\n".utf8), conversationID: conversation.id)
        } catch { errorMessage = error.localizedDescription }
    }
    private func installPresentationFixture() async {
        guard let store else { return }
        do {
            // Synthetic provider records exercise restoration of a 0.3 transcript without any network request.
            let items = try JSONValue.parse(#"""
            [
              {"type":"message","id":"plan","phase":"commentary","content":[{"type":"output_text","text":"I’ll check the reference values, then calculate the circumference."}]},
              {"type":"web_search_call","id":"search","status":"completed","action":{"type":"search","query":"planet reference dimensions","sources":[{"type":"url","title":"Example reference","url":"https://example.com/reference"}]}},
              {"type":"message","id":"assumptions","phase":"commentary","content":[{"type":"output_text","text":"No observations were supplied, so I’ll use an illustrative example."}]}
            ]
            """#).arrayValue!
            let call = ToolCall(id: "synthetic-calculation", name: "run_javascript", arguments: .object(["code": .string("return { result: { diameterKm: 143325.46854641213, circumferenceKm: 450270.2390577233 } };")]))
            let parts = ResponsePresentation.parts(from: items)
            let legacy = Message(role: .assistant, text: parts.map(\.text).joined(), toolCalls: [call],
                                 continuation: .init(providerID: "synthetic-ui-fixture", items: items))
            let result = Message(role: .tool, text: #"{"tool_succeeded":true,"execution_location":"on-device","elapsed_ms":2,"result":{"circumferenceKm":450270.2390577233,"diameterKm":143325.46854641213},"artifacts":[]}"#, toolCallID: call.id)
            let answer = #"""
            ## Approximately 450,000 km

            This is an illustrative estimate, using a rounded angular size and distance.

            With angular diameter \(\theta\) and distance \(d\):

            \[D \approx d\theta \qquad C \approx \pi d\theta.\]

            | Quantity | Value |
            | --- | ---: |
            | Diameter | 143,325 km |
            | Circumference | 450,270 km |

            The useful rounded result is **about 450,000 km**. The precision depends on the assumed observations.
            """#
            var sample = Conversation(id: UUID(uuidString: "00000000-0000-4000-8000-000000000031")!, title: "Response presentation")
            sample.messages = [Message(role: .user, text: "Estimate a planet’s circumference from limited observations."), legacy, result,
                               Message(role: .assistant, text: answer, responseParts: [.init(id: "answer", text: answer, phase: "final_answer")])]
            try await store.save(sample); conversation = try await store.loadConversation(sample.id)
        } catch { errorMessage = error.localizedDescription }
    }
    private func installDemoFixture() async {
        guard let store else { return }
        var sample = Conversation(id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!, title: "Burgundy study project")
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
            var disposable = Conversation(id: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!, title: "Disposable test chat")
            disposable.messages = [Message(role: .user, text: "Synthetic chat for exercising delete controls.")]
            try await store.save(disposable)
            if try await store.artifacts(conversationID: sample.id).isEmpty {
                try await store.saveArtifact(ArtifactRecord(conversationID: sample.id, filename: "study-plan.md", content: "# Study plan\n\n- Read and annotate: 25 minutes\n- Practice: 20 minutes\n- Recall: 10 minutes\n"))
            }
            let csvID = UUID(uuidString: "00000000-0000-4000-8000-000000000005")!
            if (try? await store.workspaceFile(csvID)) == nil {
                let csv = "value\n18.5\n27.25\n14.75\n60.5\n", bytes = Data("value\n18.5\n27.25\n14.75\n60.5\n".utf8)
                try await store.saveWorkspaceFile(WorkspaceFile(id: csvID, filename: "sample.csv", mediaType: "text/csv", byteCount: bytes.count, text: csv, extractionNote: "Synthetic UI fixture."), data: bytes)
                let (pdf, text) = try PDFDocumentWriter.make(title: "Study report", markdown: "A sample document for the Library.\n\nThe verified example sum is **60.5**.")
                try await store.saveWorkspaceFile(WorkspaceFile(filename: "study-report.pdf", mediaType: "application/pdf", byteCount: pdf.count, text: text, extractionNote: "Synthetic PDF created by the native writer for interface validation."), data: pdf)
            }
            conversation = sample
        } catch { errorMessage = error.localizedDescription }
    }
    #endif
}
