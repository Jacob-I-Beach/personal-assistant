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
    @State private var showLibrary = false
    @State private var showSettings = false
    @State private var showHealth = false
    @State private var showWatchRequests = false
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
                        Button("New chat", systemImage: "square.and.pencil") { model.newConversation() }.disabled(model.isRunning)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("New conversation", systemImage: "square.and.pencil") { model.newConversation() }.disabled(model.isRunning)
                            Button("Library", systemImage: "square.stack") { voice.stopAll(); showLibrary = true }
                            Button("Health overview", systemImage: "heart.text.square") { voice.stopAll(); showHealth = true }
                            Button("Watch requests", systemImage: "applewatch") { voice.stopAll(); showWatchRequests = true }
                            Button("Settings", systemImage: "slider.horizontal.3") { voice.stopAll(); showSettings = true }
                        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Assistant menu")
                    }
                }
        }
        .environmentObject(chatNavigation)
        .disabled(!model.isInitialized)
        .allowsHitTesting(!showHistory)
        .accessibilityHidden(showHistory)
        .overlay { if !model.isInitialized { ProgressView("Preparing your workspace").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) } }
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
                            case "library": showLibrary = true
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
        .sheet(isPresented: $showLibrary) { LibraryView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showHealth) { HealthOverviewView() }
        .sheet(isPresented: $showWatchRequests) { WatchRequestsView() }
        .sheet(item: $model.nativeAction) { NativeActionView(request: $0) }
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
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var photoImportTask: Task<Void, Never>?
    @StateObject private var viewport = ChatViewport()
    @State private var visibleMessageCount = 100
    @FocusState private var composerFocused: Bool
    var body: some View {
        StableChatScrollView(conversationID: model.conversation.id, isStreaming: model.isRunning, composerFocused: composerFocused, dismissKeyboard: { composerFocused = false }, viewport: viewport) {
                VStack(alignment: .leading, spacing: 18) {
                    if model.conversation.messages.isEmpty { welcome }
                    if model.conversation.messages.count > visibleMessageCount {
                        Button("Show earlier messages") { visibleMessageCount += 100 }.font(.footnote).frame(maxWidth: .infinity)
                    }
                    if let folder = model.folders.first(where: { $0.id == model.conversation.folderID }) {
                        Label(folder.name, systemImage: "folder").font(.caption).foregroundStyle(.secondary)
                    }
                    let actionIDs = model.conversation.responseActionMessageIDs(isRunning: model.isRunning)
                    ForEach(model.conversation.messages.suffix(visibleMessageCount).filter { !$0.text.isEmpty || !$0.captureIDs.isEmpty || !$0.fileIDs.isEmpty || !$0.displayParts.isEmpty || $0.role == .tool || $0.state == .failed || $0.state == .interrupted }) { message in
                        MessageRow(message: message, showsResponseActions: actionIDs.contains(message.id)).environmentObject(voice)
                            .background(ChatScrollAnchor(id: message.id)).id(message.id)
                    }
                    ForEach(model.artifacts.filter { $0.conversationID == model.conversation.id && !model.conversation.excludedArtifactIDs.contains($0.id) }.prefix(6)) { artifact in
                        Button { chatNavigation.destination = .artifact(artifact.id) } label: { ArtifactCard(artifact: artifact) }.buttonStyle(.plain)
                    }
                    ForEach(model.files.filter { $0.conversationID == model.conversation.id && !model.conversation.excludedFileIDs.contains($0.id) }.prefix(6)) { file in
                        Button { chatNavigation.destination = .file(file.id) } label: { WorkspaceFileRow(file: file) }.buttonStyle(.plain)
                    }
                    if let activity = model.activity {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(activity).font(.footnote).foregroundStyle(.secondary) }
                            .accessibilityElement(children: .combine)
                    }
                    Color.clear.frame(height: 10).id("conversation-bottom")
                }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 12)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .environmentObject(model).environmentObject(voice).environmentObject(chatNavigation)
        }
        .overlay(alignment: .bottomTrailing) {
            if !viewport.nearBottom && !model.conversation.messages.isEmpty {
                Button { viewport.jumpToLatest() } label: {
                    Image(systemName: "arrow.down").padding(12).background(.regularMaterial, in: Circle())
                }.padding().accessibilityLabel("Jump to latest message")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { composerFocused = false } label: { Image(systemName: "keyboard.chevron.compact.down") }
                    .accessibilityLabel("Dismiss keyboard")
            }
        }
        .onChange(of: model.conversation.id) { _, _ in
            photoImportTask?.cancel(); voice.stopAll(); voicePrefix = ""; visibleMessageCount = 100
        }
        .onChange(of: model.editingMessageID) { _, value in if value != nil { composerFocused = true } }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $showCapture) { SceneCaptureSheet().environmentObject(model) }
        .sheet(isPresented: $showAttachmentLibrary) { FileAttachmentPicker() }
        .sheet(isPresented: $showReasoningEffort) { ReasoningEffortView() }
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
        VStack(alignment: .leading, spacing: 24) {
            Text("What are we working on?").font(.system(.title, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Text("Think it through. Make something useful.").font(.subheadline).foregroundStyle(.secondary)
            VStack(spacing: 10) {
                if model.accounts.allSatisfy({ !$0.isConnected }) {
                    Button { model.connectChatGPT() } label: {
                        HStack { Text(model.isConnecting ? "Connecting…" : "Continue with ChatGPT").fontWeight(.semibold); Spacer(); Image(systemName: "arrow.right") }.padding(8).foregroundStyle(Color(uiColor: .systemBackground))
                    }.buttonStyle(.borderedProminent).tint(Color.primary).disabled(model.isConnecting)
                }
                if model.accounts.allSatisfy({ !$0.isConnected }) {
                    Button("Choose an on-device model") { model.showModels = true }.font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 6)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                suggestion("Explore something in front of you", icon: "viewfinder") { showCapture = true }
                suggestion("Turn an idea into a useful file", icon: "doc.badge.plus") { model.draft = "Help me create "; composerFocused = true }
                suggestion("Work through a calculation", icon: "function") { model.draft = "Use code to help me calculate "; composerFocused = true }
                suggestion("Read a document with me", icon: "doc.text") { showFiles = true }
            }.padding(.top, 4)
        }.padding(.top, 70).padding(.bottom, 32)
    }
    private func suggestion(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).font(.subheadline).foregroundStyle(Color.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6) }
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
                }.scrollIndicators(.hidden)
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
                }.scrollIndicators(.hidden)
            }
            HStack(alignment: .bottom, spacing: 4) {
                Menu {
                    Button("Camera and depth", systemImage: "camera") { showCapture = true }
                    Button("Photo library", systemImage: "photo") { showPhotos = true }
                    Button("Choose files", systemImage: "doc.badge.plus") { showFiles = true }
                    Button("From Library", systemImage: "square.stack") { showAttachmentLibrary = true }
                    Button("Connected folders", systemImage: "folder") { model.showConnectedFolders = true }
                } label: { Image(systemName: "plus").font(.title3).frame(width: 44, height: 44) }
                    .accessibilityLabel("Add to message").disabled(importing || model.isImportingFiles || model.isRunning)
                TextField("Ask anything", text: $model.draft, axis: .vertical).lineLimit(1...7)
                    .padding(.vertical, 10).focused($composerFocused).accessibilityIdentifier("message-composer").disabled(voice.isRecording)
                Button {
                    if voice.isRecording { voice.stopRecording() }
                    else {
                        model.stop(); voice.stopSpeaking(); voicePrefix = model.draft.isEmpty ? "" : model.draft + " "
                        Task { await voice.startRecording() }
                    }
                } label: { Image(systemName: voice.isRecording ? "mic.fill" : "mic").font(.title3).frame(width: 44, height: 44) }
                    .accessibilityLabel(voice.isRecording ? "Stop voice input" : "Dictate message").disabled(voice.isPreparing)
                if let effort = model.selectedReasoningEffort {
                    ThinkingLevelButton(effort: effort) { showReasoningEffort = true }.disabled(model.isRunning)
                }
                if model.isRunning {
                    Button { model.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 13, weight: .semibold)).frame(width: 38, height: 38).background(Color.primary, in: Circle()).foregroundStyle(Color(uiColor: .systemBackground)).frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Stop response")
                } else {
                    Button { voice.stopRecording(); composerFocused = false; viewport.jumpToLatest(); model.send() } label: { Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).frame(width: 38, height: 38).background(Color.primary, in: Circle()).foregroundStyle(Color(uiColor: .systemBackground)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .accessibilityLabel("Send message").disabled((model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.attachedCaptureIDs.isEmpty && model.attachedFileIDs.isEmpty) || importing || model.isImportingFiles)
                }
            }.padding(.horizontal, 12).padding(.vertical, 7).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 27))
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
