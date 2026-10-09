import AssistantCore
import PhotosUI
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        TabView {
            ChatView().tabItem { Label("Assistant", systemImage: "bubble.left.and.bubble.right") }
            CaptureLibraryView().tabItem { Label("Captures", systemImage: "viewfinder") }
            SettingsView().tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .alert("Could not finish", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""
    @State private var showCapture = false
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Label(model.settings.choice.title, systemImage: model.settings.choice == .localMLX ? "iphone" : "network")
                    Spacer()
                    if model.isRunning { ProgressView().controlSize(.small) }
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.vertical, 8)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            if model.conversation.messages.isEmpty {
                                ContentUnavailableView("A conversation that stays yours", systemImage: "bubble.left",
                                    description: Text("Choose a model in Settings. Capture or import a photo to ask about it and its saved observations."))
                            }
                            ForEach(model.conversation.messages) { message in
                                MessageRow(message: message).id(message.id)
                            }
                            Color.clear.frame(height: 1).id("end")
                        }.padding()
                    }
                    .onChange(of: model.conversation.messages.last?.text) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                }
                if !model.attachedCaptureIDs.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(model.attachedCaptureIDs, id: \.self) { id in
                                HStack {
                                    Label("Capture \(id.uuidString.prefix(6))", systemImage: "photo")
                                    Button { model.attachedCaptureIDs.removeAll { $0 == id } } label: { Image(systemName: "xmark.circle.fill") }
                                        .accessibilityLabel("Remove capture from next message")
                                }.font(.caption).padding(8).background(.quaternary, in: Capsule())
                            }
                        }.padding(.horizontal)
                    }
                }
                Divider()
                HStack(alignment: .bottom, spacing: 12) {
                    Menu {
                        Button("Camera and depth", systemImage: "camera") { showCapture = true }
                        PhotosPicker(selection: $photo, matching: .images) { Label("Choose a photo", systemImage: "photo") }
                    } label: { Image(systemName: "plus.circle").font(.title2) }
                    .disabled(model.isRunning || importing)
                    TextField("Ask or describe a task", text: $draft, axis: .vertical).lineLimit(1...6)
                        .textFieldStyle(.roundedBorder)
                    if model.isRunning {
                        Button { model.stop() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                            .accessibilityLabel("Stop response")
                    } else {
                        Button { model.send(draft) } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                            .accessibilityLabel("Send message")
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isDownloading || importing)
                    }
                }.padding()
            }
            .navigationTitle(model.conversation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("New conversation", systemImage: "square.and.pencil") { model.newConversation() }
                        ForEach(model.histories) { conversation in
                            Button(conversation.title) { model.selectConversation(conversation) }
                        }
                    } label: { Image(systemName: "clock.arrow.circlepath") }
                    .disabled(model.isRunning)
                    .accessibilityLabel("Conversation history")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New", systemImage: "square.and.pencil") { model.newConversation() }.disabled(model.isRunning)
                }
            }
            .sheet(isPresented: $showCapture) { SceneCaptureSheet().environmentObject(model) }
            .alert("Use this network model?", isPresented: $model.needsNetworkConsent) {
                Button("Allow for this conversation") { model.approveNetworkConversation() }
                Button("Cancel", role: .cancel) { model.declineNetworkConversation() }
            } message: {
                Text("Conversation text, attached images, and requested capture results will be sent to \(model.settings.endpoint?.absoluteString ?? "the selected endpoint"). You can revoke this permission in Settings.")
            }
            .onChange(of: model.isRunning) { _, running in if running { draft = "" } }
            .onChange(of: photo) { _, selected in
                guard let selected else { return }
                importing = true
                Task {
                    defer { importing = false; photo = nil }
                    do {
                        guard let data = try await selected.loadTransferable(type: Data.self) else { throw AssistantError.invalidCapture("Could not read the selected photo.") }
                        let (capture, jpeg) = try await CaptureProcessor.shared.importPhoto(data)
                        _ = await model.saveCapture(capture, jpeg: jpeg)
                    } catch { model.errorMessage = error.localizedDescription }
                }
            }
        }
    }
}

private struct MessageRow: View {
    let message: Message
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(message.role == .tool ? "Tool result" : message.role == .user ? "You" : "Assistant").font(.caption.bold())
                if message.state == .interrupted || message.state == .failed { Text(message.state.rawValue).font(.caption).foregroundStyle(.secondary) }
            }
            if message.role == .tool {
                DisclosureGroup("Inspect saved evidence") { Text(message.text).font(.caption.monospaced()).textSelection(.enabled) }
            } else {
                Text(message.text.isEmpty && message.state == .streaming ? "…" : message.text).textSelection(.enabled)
            }
            ForEach(message.captureIDs, id: \.self) { id in
                Text("Capture \(id.uuidString)").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
            ForEach(message.toolCalls) { call in Label(call.name, systemImage: "wrench.and.screwdriver").font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(message.role == .user ? 12 : 0)
        .background(message.role == .user ? Color.secondary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
    }
}
