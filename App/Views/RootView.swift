import AssistantCore
import MarkdownUI
import PhotosUI
import SwiftUI

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
                        Button("History", systemImage: "sidebar.left") { voice.stopAll(); showHistory = true }.disabled(model.isRunning)
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
        .overlay { if !model.isInitialized { ProgressView("Preparing your workspace").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) } }
        .tint(Color.primary)
        .sheet(isPresented: $model.showModels) { ModelLibraryView() }
        .sheet(isPresented: $showHistory) { HistoryView() }
        .sheet(isPresented: $showLibrary) { LibraryView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showHealth) { HealthOverviewView() }
        .sheet(isPresented: $showWatchRequests) { WatchRequestsView() }
        .alert("Could not finish", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Use \(model.modelTitle) for this conversation?", isPresented: $model.needsNetworkConsent, titleVisibility: .visible) {
            Button("Allow for this conversation") { model.approveNetworkConversation() }
            Button("Keep on this device", role: .cancel) { model.declineNetworkConversation() }
        } message: {
            Text((model.draftContainsHealthData || model.conversation.containsHealthData ? "This conversation includes a selected Health summary. Sharing it sends that Health-derived information to the selected service for this wellness discussion. " : "") + "Relevant conversation text, selected images, and requested tool results will be sent to \(model.modelLocation). You can revoke this permission in Settings.")
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
    @State private var speakReplies = false
    @State private var showCapture = false
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
                    ForEach(model.conversation.messages.suffix(visibleMessageCount)) { message in
                        MessageRow(message: message).environmentObject(voice).id(message.id)
                    }
                    ForEach(model.artifacts.filter { $0.conversationID == model.conversation.id }.prefix(6)) { artifact in
                        NavigationLink { ArtifactDetailView(artifact: artifact) } label: { ArtifactCard(artifact: artifact) }.buttonStyle(.plain)
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
        .onChange(of: model.draft) { _, _ in model.draftChanged() }
        .onChange(of: voice.transcript) { _, text in if !text.isEmpty { model.draft = voicePrefix + text } }
        .onChange(of: voice.errorMessage) { _, value in if let value { model.noticeMessage = value } }
        .onChange(of: model.isRunning) { _, running in
            if !running && speakReplies, let message = model.conversation.messages.last, message.role == .assistant, message.state == .complete { voice.speak(message.text) }
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
        VStack(alignment: .leading, spacing: 25) {
            Image("AssistantMark").resizable().frame(width: 45, height: 45).clipShape(RoundedRectangle(cornerRadius: 13)).accessibilityHidden(true)
            Text("What would you like\nto work on?").font(.system(.largeTitle, design: .rounded, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Text("A place to think, explore, and make things—with the model you choose.").font(.body).foregroundStyle(.secondary)
            VStack(spacing: 10) {
                if model.accounts.allSatisfy({ !$0.isConnected }) {
                    Button { model.connectChatGPT() } label: {
                        HStack { Text(model.isConnecting ? "Connecting…" : "Continue with ChatGPT").fontWeight(.semibold); Spacer(); Image(systemName: "arrow.right") }.padding(8).foregroundStyle(Color(uiColor: .systemBackground))
                    }.buttonStyle(.borderedProminent).tint(Color.primary).disabled(model.isConnecting)
                }
                Button { model.showModels = true } label: {
                    HStack { Label("Explore on-device models", systemImage: "iphone"); Spacer(); Image(systemName: "chevron.right").font(.caption) }.padding(8)
                }.buttonStyle(.bordered).tint(.primary)
            }
            VStack(alignment: .leading, spacing: 12) {
                suggestion("Explore something in front of you", icon: "viewfinder") { showCapture = true }
                suggestion("Turn an idea into a useful file", icon: "doc.badge.plus") { model.draft = "Help me create "; composerFocused = true }
                suggestion("Work through a calculation", icon: "function") { model.draft = "Use code to help me calculate "; composerFocused = true }
            }.padding(.top, 4)
        }.padding(.top, 26).padding(.bottom, 12)
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
                    Toggle("Read responses aloud", isOn: $speakReplies)
                } label: { Image(systemName: "plus").font(.title3).frame(width: 32, height: 40) }
                    .accessibilityLabel("Add to message").disabled(importing || model.isRunning)
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
                        .accessibilityLabel("Send message").disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || importing)
                }
            }.padding(.horizontal, 12).padding(.vertical, 7).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 27))
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8).background(.bar)
    }
}

struct AssistantMarkdown: View {
    let text: String
    var body: some View {
        Markdown(text)
            .markdownBlockStyle(\.codeBlock) { configuration in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(configuration.language ?? "Code").font(.caption).foregroundStyle(Color.secondary)
                        Spacer()
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = configuration.content }.font(.caption).accessibilityLabel("Copy code")
                    }.padding(.horizontal, 12).padding(.top, 10)
                    ScrollView(.horizontal) {
                        configuration.label.markdownTextStyle { FontFamilyVariant(.monospaced); FontSize(.em(0.85)) }.padding(12)
                    }
                }.background(Color(uiColor: .secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 14)).markdownMargin(top: 4, bottom: 14)
            }
            .markdownTheme(.gitHub.text { FontSize(17); ForegroundColor(Color.primary); BackgroundColor(nil) })
            .markdownImageProvider(ExplicitImagePlaceholder())
            .markdownInlineImageProvider(NoRemoteInlineImage())
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
                return .systemAction
            })
    }
}
private struct ExplicitImagePlaceholder: MarkdownUI.ImageProvider {
    func makeImage(url: URL?) -> some View { Label("Linked image", systemImage: "photo").font(.caption).foregroundStyle(.secondary) }
}
private struct NoRemoteInlineImage: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image { Image(systemName: "photo") }
}
private struct MessageRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceController
    let message: Message
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if message.role == .tool {
                DisclosureGroup {
                    Text(message.text).font(.caption.monospaced()).textSelection(.enabled)
                } label: { Label("Saved tool result", systemImage: "doc.text.magnifyingglass").font(.footnote).foregroundStyle(.secondary) }
            } else {
                if message.role == .assistant && !message.text.isEmpty {
                    Text("Assistant").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                if !message.text.isEmpty { AssistantMarkdown(text: message.text) }
                if message.state == .interrupted || message.state == .failed {
                    Label(message.state == .interrupted ? "Stopped · partial response saved" : "Incomplete response", systemImage: "pause.circle").font(.caption).foregroundStyle(.secondary)
                }
                if message.containsLocalOnlyContext { Label("On-device-only context", systemImage: "iphone").font(.caption2).foregroundStyle(Color.secondary) }
                if !message.captureIDs.isEmpty {
                    HStack { ForEach(message.captureIDs, id: \.self) { id in CaptureThumbnail(id: id).frame(width: 80, height: 80).clipShape(RoundedRectangle(cornerRadius: 12)) } }
                }
                ForEach(message.toolCalls) { call in
                    DisclosureGroup {
                        Text(call.arguments["code"]?.stringValue ?? (try? call.arguments.jsonString()) ?? "Arguments unavailable").font(.caption.monospaced()).textSelection(.enabled)
                    } label: {
                        Label(call.name == "run_javascript" ? "Inspect code request" : "Inspect tool request", systemImage: "wrench.and.screwdriver").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !message.text.isEmpty && message.state != .streaming {
                    HStack(spacing: 18) {
                        Button { UIPasteboard.general.string = message.text } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("Copy message")
                        ShareLink(item: message.text) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share message")
                        if message.role == .assistant { Button { voice.speak(message.text) } label: { Image(systemName: "speaker.wave.2") }.accessibilityLabel("Read response aloud") }
                        if message.role == .user { Button { model.draft = message.text } label: { Image(systemName: "pencil") }.accessibilityLabel("Use message as draft") }
                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 3)
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
