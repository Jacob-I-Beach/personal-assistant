import AssistantCore
import MarkdownUI
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var voice = VoiceController()
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
    @State private var voicePrefix = ""
    @State private var showCapture = false
    @State private var showFiles = false
    @State private var showAttachmentLibrary = false
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var followBottom = true
    @State private var nearBottom = true
    @State private var visibleMessageCount = 100
    @FocusState private var composerFocused: Bool
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if model.conversation.messages.isEmpty { welcome }
                    if model.conversation.messages.count > visibleMessageCount {
                        Button("Show earlier messages") { visibleMessageCount += 100 }.font(.footnote).frame(maxWidth: .infinity)
                    }
                    if let folder = model.folders.first(where: { $0.id == model.conversation.folderID }) {
                        Label(folder.name, systemImage: "folder").font(.caption).foregroundStyle(.secondary)
                    }
                    let actionIDs = model.conversation.responseActionMessageIDs(isRunning: model.isRunning)
                    ForEach(model.conversation.messages.suffix(visibleMessageCount).filter { !$0.text.isEmpty || !$0.displayParts.isEmpty || $0.role == .tool || $0.state == .failed || $0.state == .interrupted }) { message in
                        MessageRow(message: message, showsResponseActions: actionIDs.contains(message.id)).environmentObject(voice).id(message.id)
                    }
                    ForEach(model.artifacts.filter { $0.conversationID == model.conversation.id }.prefix(6)) { artifact in
                        NavigationLink { ArtifactDetailView(artifact: artifact) } label: { ArtifactCard(artifact: artifact) }.buttonStyle(.plain)
                    }
                    ForEach(model.files.filter { $0.conversationID == model.conversation.id }.prefix(6)) { file in
                        NavigationLink { WorkspaceFileView(id: file.id) } label: { WorkspaceFileRow(file: file) }.buttonStyle(.plain)
                    }
                    if let activity = model.activity {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(activity).font(.footnote).foregroundStyle(.secondary) }
                            .accessibilityElement(children: .combine)
                    }
                    Color.clear.frame(height: 10).id("conversation-bottom")
                }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 12)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 100
            } action: { _, value in nearBottom = value }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { followBottom = false }
                else if phase == .idle && nearBottom { followBottom = true }
            }
            .onChange(of: model.conversation.messages.last?.text) { _, _ in
                if followBottom { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
            }
            .onChange(of: model.conversation.messages.last?.responseParts.count) { _, _ in
                if followBottom { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
            }
            .onChange(of: model.conversation.messages.count) { _, _ in
                if followBottom { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
            }
            .onChange(of: model.conversation.id) { _, _ in
                voice.stopAll(); voicePrefix = ""
                followBottom = true; visibleMessageCount = 100; proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
            .overlay(alignment: .bottomTrailing) {
                if !nearBottom && !model.conversation.messages.isEmpty {
                    Button { followBottom = true; withAnimation { proxy.scrollTo("conversation-bottom", anchor: .bottom) } } label: {
                        Image(systemName: "arrow.down").padding(12).background(.regularMaterial, in: Circle())
                    }.padding().accessibilityLabel("Jump to latest message")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $showCapture) { SceneCaptureSheet().environmentObject(model) }
        .sheet(isPresented: $showAttachmentLibrary) { FileAttachmentPicker() }
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
        .onDisappear { voice.stopAll() }
        .onChange(of: photo) { _, selected in
            guard let selected else { return }
            importing = true
            Task {
                defer { importing = false; photo = nil }
                do {
                    guard let data = try await selected.loadTransferable(type: Data.self) else { throw AssistantError.invalidCapture("The photo could not be opened.") }
                    let (capture, jpeg) = try await CaptureProcessor.shared.importPhoto(data)
                    _ = await model.saveCapture(capture, jpeg: jpeg)
                } catch { model.errorMessage = error.localizedDescription }
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
        VStack(spacing: 10) {
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
                                Text("Image").font(.caption)
                                Button { model.attachedCaptureIDs.removeAll { $0 == id } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Remove attached image")
                            }.padding(7).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            HStack(alignment: .bottom, spacing: 12) {
                Menu {
                    Button("Camera and depth", systemImage: "camera") { showCapture = true }
                    PhotosPicker(selection: $photo, matching: .images) { Label("Photo library", systemImage: "photo") }
                    Button("Choose files", systemImage: "doc.badge.plus") { showFiles = true }
                    Button("From Library", systemImage: "square.stack") { showAttachmentLibrary = true }
                } label: { Image(systemName: "plus").font(.title3).frame(width: 32, height: 40) }
                    .accessibilityLabel("Add to message").disabled(importing || model.isImportingFiles || model.isRunning)
                TextField("Ask anything", text: $model.draft, axis: .vertical).lineLimit(1...7)
                    .padding(.vertical, 10).focused($composerFocused).accessibilityIdentifier("message-composer").disabled(voice.isRecording)
                Button {
                    if voice.isRecording { voice.stopRecording() }
                    else {
                        model.stop(); voice.stopSpeaking(); voicePrefix = model.draft.isEmpty ? "" : model.draft + " "
                        Task { await voice.startRecording() }
                    }
                } label: { Image(systemName: voice.isRecording ? "mic.fill" : "mic").font(.title3).frame(width: 28, height: 38) }
                    .accessibilityLabel(voice.isRecording ? "Stop voice input" : "Dictate message").disabled(voice.isPreparing)
                if model.isRunning {
                    Button { model.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 13, weight: .semibold)).frame(width: 38, height: 38).background(Color.primary, in: Circle()).foregroundStyle(Color(uiColor: .systemBackground)) }.accessibilityLabel("Stop response")
                } else {
                    Button { voice.stopRecording(); followBottom = true; model.send() } label: { Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).frame(width: 38, height: 38).background(Color.primary, in: Circle()).foregroundStyle(Color(uiColor: .systemBackground)) }
                        .accessibilityLabel("Send message").disabled((model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.attachedCaptureIDs.isEmpty && model.attachedFileIDs.isEmpty) || importing || model.isImportingFiles)
                }
            }.padding(.horizontal, 12).padding(.vertical, 7).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 27))
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8).background(.bar)
    }
}

private struct MessageRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceController
    let message: Message
    let showsResponseActions: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if message.role == .tool {
                WorkReceiptView(message: message)
            } else {
                if !message.text.isEmpty || !message.displayParts.isEmpty { ResponseContentView(message: message) }
                if message.state == .interrupted || message.state == .failed {
                    Label(message.state == .interrupted ? "Stopped · partial response saved" : "Incomplete response", systemImage: "pause.circle").font(.caption).foregroundStyle(.secondary)
                    if let reason = message.failureReason { Text(reason).font(.footnote).foregroundStyle(Color.secondary).textSelection(.enabled) }
                }
                if message.containsLocalOnlyContext { Label("On-device-only context", systemImage: "iphone").font(.caption2).foregroundStyle(Color.secondary) }
                if !message.displayCitations.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sources").font(.caption.weight(.semibold)).foregroundStyle(Color.secondary)
                        ForEach(Array(message.displayCitations.enumerated()), id: \.offset) { index, citation in
                            Link(destination: citation.url) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("[\(index + 1)] \(citation.title)").font(.footnote).multilineTextAlignment(.leading)
                                    Text(citation.url.host ?? "").font(.caption2).foregroundStyle(Color.secondary)
                                }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.padding(.vertical, 6)
                }
                if !message.captureIDs.isEmpty {
                    HStack { ForEach(message.captureIDs, id: \.self) { id in CaptureThumbnail(id: id).frame(width: 80, height: 80).clipShape(RoundedRectangle(cornerRadius: 12)) } }
                }
                ForEach(message.fileIDs, id: \.self) { id in
                    if let file = model.files.first(where: { $0.id == id }) {
                        NavigationLink { WorkspaceFileView(id: id) } label: { Label(file.filename, systemImage: file.icon).font(.footnote).lineLimit(2).padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 10)) }
                    } else { Label("File removed from Library", systemImage: "doc").font(.caption).foregroundStyle(.secondary) }
                }
                if !message.text.isEmpty && (message.role == .user || showsResponseActions) {
                    HStack(spacing: 18) {
                        Button { UIPasteboard.general.string = message.answerText } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("Copy message")
                        ShareLink(item: message.answerText) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share message")
                        if message.role == .assistant { Button { voice.speak(MarkdownContent(message.answerText).renderPlainText()) } label: { Image(systemName: "speaker.wave.2") }.accessibilityLabel("Read response aloud") }
                        if message.role == .user { Button { model.draft = message.text } label: { Image(systemName: "pencil") }.accessibilityLabel("Use message as draft") }
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 3)
                        .accessibilityIdentifier(message.role == .assistant ? "final-response-actions" : "user-message-actions")
                }
            }
        }
        .padding(message.role == .user ? 15 : 0)
        .background(message.role == .user ? Color(uiColor: .secondarySystemBackground) : .clear, in: RoundedRectangle(cornerRadius: 22))
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
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
