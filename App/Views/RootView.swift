import AssistantCore
import MarkdownUI
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var voice = VoiceController()
    @StateObject private var chatNavigation = ChatNavigation()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var showHealth = false
    @State private var showWatchRequests = false
    @State private var showTaskActivity = false
    @State private var showActivityPreview = false
    var body: some View {
        NavigationStack {
            ChatView().environmentObject(voice)
                .navigationDestination(item: $chatNavigation.destination) { destination in
                    switch destination {
                    case .file(let id): WorkspaceFileView(id: id)
                    case .artifact(let id):
                        if let artifact = model.artifacts.first(where: { $0.id == id }) { ArtifactDetailView(artifact: artifact) }
                        else { ContentUnavailableView("File unavailable", systemImage: "doc") }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("History", systemImage: "sidebar.left") { voice.stopAll(); withAnimation(.snappy(duration: 0.25)) { showHistory = true } }
                    }
                    ToolbarItem(placement: .principal) {
                        Button { voice.stopAll(); model.showModels = true } label: {
                            VStack(spacing: 2) {
                                HStack(spacing: 5) { Text(model.modelTitle).font(.subheadline.weight(.semibold)).lineLimit(1); Image(systemName: "chevron.down").font(.caption2) }
                                Text(model.modelLocation).font(.caption2).foregroundStyle(Color.secondary)
                            }.foregroundStyle(Color.primary)
                        }.accessibilityLabel("Choose model").disabled(model.isRunning)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            #if DEBUG
                            if ProcessInfo.processInfo.arguments.contains("--ui-activity103") {
                                Button("Activity preview") { showActivityPreview = true }
                                Button("Finish sample reply") { Task { await model.finishActivityFixture() } }
                            }
                            #endif
                            Button("Connections", systemImage: "point.3.connected.trianglepath.dotted") { chatNavigation.showConnections = true }
                            Button("Task activity", systemImage: "list.bullet.rectangle") { showTaskActivity = true }
                            Button("Assistant inbox", systemImage: "tray") { model.showInbox = true }
                        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Assistant menu")
                    }
                }
        }
        .disabled(!model.isInitialized || model.isRestoringBackgroundRoute)
        .allowsHitTesting(!showHistory)
        .accessibilityHidden(showHistory)
        .overlay {
            if model.isRestoringBackgroundRoute {
                ZStack { Color(uiColor: .systemBackground).ignoresSafeArea(); ProgressView("Opening your task…") }
            } else if !model.isInitialized { ProgressView("Preparing your workspace").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) }
        }
        .overlay(alignment: .leading) {
            if showHistory {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Button { withAnimation(.snappy(duration: 0.25)) { showHistory = false } } label: { Color.black.opacity(0.25).ignoresSafeArea() }
                                .frame(width: max(0, geometry.size.width - min(geometry.size.width * 0.9, 390)))
                                .accessibilityLabel("Dismiss sidebar")
                        }
                        HistoryView(close: { withAnimation(.snappy(duration: 0.25)) { showHistory = false } }, open: { destination in
                            switch destination {
                            case "library": chatNavigation.showLibrary = true
                            case "connections": chatNavigation.showConnections = true
                            case "inbox": model.showInbox = true
                            case "activity": showTaskActivity = true
                            case "models": model.showModels = true
                            case "watch": showWatchRequests = true
                            default: showSettings = true
                            }
                        })
                        .frame(width: min(geometry.size.width * 0.9, 390), height: geometry.size.height)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .transition(.move(edge: .leading))
                        .accessibilityAddTraits(.isModal)
                        .gesture(DragGesture(minimumDistance: 30).onEnded { gesture in
                            if gesture.translation.width < -65 { withAnimation(.snappy(duration: 0.25)) { showHistory = false } }
                        })
                    }
                }
            }
        }
        .tint(Color.primary)
        .sheet(isPresented: $model.showModels) { ModelLibraryView() }
        .sheet(isPresented: $chatNavigation.showLibrary) { LibraryView() }
        .sheet(isPresented: $chatNavigation.showConnections) { ConnectionsView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showHealth) { HealthOverviewView() }
        .sheet(isPresented: $showWatchRequests) { WatchRequestsView() }
        .sheet(isPresented: $showTaskActivity) { TaskActivityView() }
        #if DEBUG
        .sheet(isPresented: $showActivityPreview) { ActivityPreviewGallery() }
        #endif
        .sheet(isPresented: $model.showInbox) { AssistantInboxView() }
        .sheet(isPresented: $model.showPlanningAccess) { PlanningAccessView(service: model.planning) }
        .onOpenURL { url in
            guard url.scheme == "personalassistant", url.host == "task", let id = UUID(uuidString: url.lastPathComponent) else { return }
            Task { await model.openTaskAttention(id) }
        }
        .sheet(item: $model.nativeAction, onDismiss: { model.nativeReviewDidDismiss() }) { NativeActionView(request: $0) }
        .alert("Could not finish", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Use \(model.modelTitle) for this conversation?", isPresented: $model.needsNetworkConsent, titleVisibility: .visible) {
            Button("Allow for this conversation") { model.approveNetworkConversation() }
            Button("Keep on this device", role: .cancel) { model.declineNetworkConversation() }
        } message: {
            Text((model.draftContainsHealthData || model.conversation.containsHealthData ? "This conversation includes a selected Health summary. Sharing it sends that Health-derived information to the selected service for this wellness discussion. " : "") + "Relevant conversation text, selected images and files, and requested tool results will be sent to \(model.modelLocation). Workspace search, when enabled in Settings, can include permitted other chats and Library files. You can revoke this conversation's permission in Settings.")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.becameActive() }
            else if phase == .background { model.enteredBackground() }
            else { model.flushDraft() }
        }
        .tint(Color.primary)
        .modifier(TestAppearance(systemTypeSize: systemTypeSize))
        .onChange(of: model.isConnecting) { _, value in if value { voice.stopAll() } }
        .onChange(of: model.showModels) { _, value in if value { voice.stopAll() } }
        .onChange(of: model.settings.hapticsEnabled, initial: true) { _, enabled in AppFeedback.enabled = enabled }
        // Sheets and sidebar overlays share the same router as the transcript.
        // Keep this outside the presentation modifiers so their destinations
        // receive it as well as the NavigationStack's original content.
        .environmentObject(chatNavigation)
    }
}

private struct TestAppearance: ViewModifier {
    let systemTypeSize: DynamicTypeSize
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG
        content.preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--ui-dark") ? .dark : nil)
            .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("--ui-large") ? .accessibility2 : systemTypeSize)
        #else
        content
        #endif
    }
}

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceController
    @EnvironmentObject private var chatNavigation: ChatNavigation
    @State private var voicePrefix = ""
    @State private var showCapture = false
    @State private var showFiles = false
    @State private var showPhotos = false
    @State private var showReasoningEffort = false
    @State private var showAttachmentLibrary = false
    @State private var showCreationBrief = false
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var photoImportTask: Task<Void, Never>?
    @StateObject private var viewport = ChatViewport()
    @State private var visibleMessageCount = 100
    @ScaledMetric(relativeTo: .caption) private var attachmentRowHeight: CGFloat = 52
    @FocusState private var composerFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
        StableChatScrollView(conversationID: model.conversation.id, isStreaming: model.isRunning, hasMessages: !model.conversation.messages.isEmpty, composerFocused: composerFocused, dismissKeyboard: { composerFocused = false }, viewport: viewport) {
                VStack(alignment: .leading, spacing: 18) {
                    if model.conversation.messages.isEmpty { welcome }
                    if model.conversation.messages.count > visibleMessageCount {
                        Button("Show earlier messages") { visibleMessageCount += 100 }.font(.footnote).frame(maxWidth: .infinity)
                    }
                    if let folder = model.folders.first(where: { $0.id == model.conversation.folderID }) {
                        Label(folder.name, systemImage: "folder").font(.caption).foregroundStyle(.secondary)
                    }
                    let actionIDs = model.conversation.responseActionMessageIDs(isRunning: model.isRunning)
                    ForEach(ChatTimeline.items(model.conversation.messages).suffix(visibleMessageCount)) { item in
                        Group {
                            if item.isActivity { ActivityGroupView(messages: item.messages) }
                            else if let message = item.messages.first {
                                MessageRow(message: message, showsResponseActions: actionIDs.contains(message.id)).environmentObject(voice)
                            }
                        }.background(alignment: .topLeading) { ChatScrollAnchor(id: item.id).frame(width: 1, height: 1) }.id(item.id)
                    }
                    ForEach(model.artifacts.filter { $0.conversationID == model.conversation.id && !model.conversation.excludedArtifactIDs.contains($0.id) }.prefix(6)) { artifact in
                        Button { chatNavigation.destination = .artifact(artifact.id) } label: { ArtifactCard(artifact: artifact) }.buttonStyle(.plain)
                    }
                    ForEach(model.files.filter { $0.conversationID == model.conversation.id && !model.conversation.excludedFileIDs.contains($0.id) }.prefix(6)) { file in
                        Button { chatNavigation.destination = .file(file.id) } label: { WorkspaceFileRow(file: file) }.buttonStyle(.plain)
                    }
                    if let call = model.activeToolCall {
                        ActiveWorkRow(title: model.activity ?? ToolResultPresentation.activeTitle(call))
                    } else if let activity = model.activity, activity.hasPrefix("Retrying") || activity == "Reconnecting" || !model.conversation.messages.suffix(2).filter({ $0.state == .streaming }).flatMap(\.displayParts).contains(where: { $0.web?.isRunning == true }) {
                        ActiveWorkRow(title: activity)
                    }
                    if !model.isRunning, !model.conversation.messages.isEmpty,
                       let work = model.unfinishedReplies.first(where: { work in work.conversationID == model.conversation.id && work.userMessageID == model.conversation.messages.last(where: \.isRequest)?.id && !model.pendingQuestions.contains(where: { $0.turnID == work.id }) }) {
                        SavedWorkCard(work: work)
                    }
                    ForEach(model.pendingQuestions.filter { $0.conversationID == model.conversation.id }) { question in
                        Button { model.openQuestion(question) } label: {
                            VStack(alignment: .leading, spacing: 8) { Label("Needs your answer", systemImage: "bubble.left").font(.caption); Text(question.title).font(.subheadline.weight(.medium)); Text("Open question").font(.caption) }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(16).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                    let savedInputs = model.inbox.filter { $0.conversationID == model.conversation.id && $0.handledAt == nil }
                    if !savedInputs.isEmpty {
                        Button { model.showInbox = true } label: { Label("\(savedInputs.count) saved \(savedInputs.count == 1 ? "capture" : "captures") for this chat", systemImage: "tray").font(.footnote) }
                    }
                    Color.clear.frame(height: 10).id("conversation-bottom")
                }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 12)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .environmentObject(model).environmentObject(voice).environmentObject(chatNavigation).environment(\.chatViewport, viewport)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            if !viewport.nearBottom && !model.conversation.messages.isEmpty {
                Button { AppFeedback.play(.selection); viewport.jumpToLatest() } label: {
                    Image(systemName: "arrow.down").padding(12).background(.regularMaterial, in: Circle())
                }.padding().accessibilityLabel("Jump to latest message")
            }
        }
        composer
        }
        .onChange(of: model.conversation.id) { _, _ in
            photoImportTask?.cancel(); voice.stopAll(); voicePrefix = ""; visibleMessageCount = 100
        }
        .onChange(of: model.editingMessageID) { _, value in if value != nil { composerFocused = true } }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $showCapture) { SceneCaptureSheet().environmentObject(model) }
        .sheet(isPresented: $showReasoningEffort) { ReasoningEffortView() }
        .sheet(isPresented: $showCreationBrief) { CreationBriefView(text: model.draft) { model.draft = $0; composerFocused = true } }
        .sheet(isPresented: $model.showConnectedFolders) {
            NavigationStack { ConnectedFoldersView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { model.showConnectedFolders = false } } } }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images, preferredItemEncoding: .compatible)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): model.importFiles(urls)
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .onChange(of: model.draft) { _, _ in model.draftChanged() }
        .onChange(of: voice.transcript) { _, text in if !text.isEmpty { model.draft = voicePrefix + text } }
        .onChange(of: voice.errorMessage) { _, value in if let value { model.noticeMessage = value } }
        .onChange(of: model.isRunning) { _, running in
            if !running && model.settings.speakReplies, let message = model.conversation.messages.last, message.role == .assistant, message.state == .complete { voice.speak(MarkdownContent(message.text).renderPlainText()) }
        }
        .onDisappear { voice.stopAll(); photoImportTask?.cancel() }
        .onChange(of: photo) { _, selected in
            guard let selected else { return }
            importing = true
            let targetConversation = model.conversation.id
            photoImportTask = Task {
                defer { importing = false; photo = nil }
                do {
                    guard let data = try await selected.loadTransferable(type: Data.self) else { throw AssistantError.invalidCapture("The photo could not be opened.") }
                    let (capture, jpeg) = try await CaptureProcessor.shared.importPhoto(data)
                    try Task.checkCancellation()
                    _ = await model.saveCapture(capture, jpeg: jpeg, attachTo: targetConversation)
                } catch { if !Task.isCancelled { model.errorMessage = error.localizedDescription } }
            }
        }
    }
    private var welcome: some View {
        WelcomeWorkspaceView(camera: { showCapture = true }, files: { showFiles = true }, create: { showCreationBrief = true }, voice: {
            voice.stopSpeaking(); voicePrefix = model.draft.isEmpty ? "" : model.draft + " "
            Task { await voice.startRecording() }
        })
    }
    private var composer: some View {
        VStack(spacing: 8) {
            if model.editingMessageID != nil {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Editing message").font(.caption.weight(.semibold))
                        Text("Later replies will be replaced.").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cancel") { model.cancelEditing() }.font(.caption)
                }.padding(.horizontal, 10)
            }
            if voice.isRecording || voice.isSpeaking {
                HStack {
                    Label(voice.isRecording ? "Listening on this iPhone" : "Reading response", systemImage: "waveform").font(.footnote)
                    Spacer()
                    Button("Stop") { voice.stopAll() }.font(.footnote)
                }.padding(.horizontal, 6)
            }
            if let notice = model.noticeMessage {
                HStack(alignment: .top) {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button { model.noticeMessage = nil } label: { Image(systemName: "xmark").font(.caption) }.accessibilityLabel("Dismiss notice")
                }.padding(.horizontal, 6)
            }
            if model.isDownloading {
                HStack { ProgressView(value: model.downloadProgress).frame(width: 50); Text(model.modelStatus).font(.caption).lineLimit(1); Spacer(); Button("View") { model.showModels = true }.font(.caption) }
            }
            if model.isImportingFiles { HStack { ProgressView().controlSize(.small); Text("Adding files to your Library").font(.caption); Spacer() } }
            if importing {
                HStack { ProgressView().controlSize(.small); Text("Preparing image").font(.caption); Spacer(); Button("Cancel") { photoImportTask?.cancel() }.font(.caption) }
            }
            if !model.attachedFileIDs.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(model.attachedFileIDs, id: \.self) { id in
                            HStack(spacing: 8) {
                                Image(systemName: model.files.first { $0.id == id }?.icon ?? "doc")
                                Text(model.files.first { $0.id == id }?.filename ?? "File").font(.caption).lineLimit(1)
                                Button { model.attachedFileIDs.removeAll { $0 == id }; model.flushDraft() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Remove attached file")
                            }.padding(10).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }.scrollIndicators(.hidden).frame(height: attachmentRowHeight)
            }
            if !model.attachedCaptureIDs.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(model.attachedCaptureIDs, id: \.self) { id in
                            HStack(spacing: 8) {
                                CaptureThumbnail(id: id).frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 7))
                                Text(model.selectedImagePoints[id.uuidString].map { "Image · \($0.count) selected points" } ?? "Image").font(.caption)
                                Button { model.attachedCaptureIDs.removeAll { $0 == id } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Remove attached image")
                            }.padding(7).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }.scrollIndicators(.hidden).frame(height: attachmentRowHeight)
            }
            VStack(alignment: .leading, spacing: 2) {
                TextField("Ask anything", text: $model.draft, axis: .vertical).lineLimit(1...7)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
                    .focused($composerFocused).accessibilityIdentifier("message-composer").disabled(voice.isRecording)
                HStack(alignment: .center, spacing: 4) {
                Menu {
                    Button("Camera and depth", systemImage: "camera") { showCapture = true }
                    Button("Photo library", systemImage: "photo") { showPhotos = true }
                    Button("Choose files", systemImage: "doc.badge.plus") { showFiles = true }
                    Button("Library", systemImage: "square.stack") { composerFocused = false; chatNavigation.showLibrary = true }
                    Button("Connected folders", systemImage: "folder") { model.showConnectedFolders = true }
                } label: { Image(systemName: "plus").font(.title3).frame(width: 44, height: 44) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add to message").disabled(importing || model.isImportingFiles || model.isRunning)
                Spacer(minLength: 16)
                Button {
                    if voice.isRecording { voice.stopRecording() }
                    else {
                        model.stop(); voice.stopSpeaking(); voicePrefix = model.draft.isEmpty ? "" : model.draft + " "
                        Task { await voice.startRecording() }
                    }
                } label: { Image(systemName: voice.isRecording ? "mic.fill" : "mic").font(.title3).frame(width: 44, height: 44) }
                    .accessibilityLabel(voice.isRecording ? "Stop voice input" : "Dictate message").disabled(voice.isPreparing)
                if model.selectedReasoningEffort != nil || model.contextBudget(for: model.settings) != nil {
                    ThinkingLevelButton(effort: model.selectedReasoningEffort) { showReasoningEffort = true }.disabled(model.isRunning)
                }
                if model.isRunning {
                    Button { model.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 13, weight: .semibold)).frame(width: 38, height: 38).background(Color.primary, in: Circle()).foregroundStyle(Color(uiColor: .systemBackground)).frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Stop response")
                } else {
                    Button { voice.stopRecording(); composerFocused = false; viewport.jumpToLatest(); model.send() } label: { Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).frame(width: 38, height: 38).background(Color.primary, in: Circle()).foregroundStyle(Color(uiColor: .systemBackground)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .accessibilityLabel("Send message").disabled((model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.attachedCaptureIDs.isEmpty && model.attachedFileIDs.isEmpty) || importing || model.isImportingFiles)
                }
                }.buttonStyle(QuietPressStyle())
            }.padding(.horizontal, 10).padding(.vertical, 6).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 25))
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8).background(.bar)
    }
}

struct CaptureThumbnail: View {
    @EnvironmentObject private var model: AppModel
    let id: UUID
    @State private var image: UIImage?
    var body: some View {
        Group { if let image { Image(uiImage: image).resizable().scaledToFill() } else { Image(systemName: "photo").frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary) } }
            .clipped().task(id: id) { image = await model.image(id) }.accessibilityLabel("Attached image")
    }
}
