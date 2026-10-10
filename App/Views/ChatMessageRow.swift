import AssistantCore
import MarkdownUI
import SwiftUI

struct MessageRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceController
    let message: Message
    let showsResponseActions: Bool
    @State private var selectedImage: ImageSelection?
    private struct ImageSelection: Identifiable { let id: UUID; let points: [ImagePoint] }
    var body: some View {
        Group {
            if message.role == .user {
                HStack(alignment: .top, spacing: 0) {
                    Spacer(minLength: 30)
                    VStack(alignment: .leading, spacing: 8) {
                        attachments
                        if !message.text.isEmpty {
                            Text(message.text).font(.body).foregroundStyle(.primary).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 14).padding(.vertical, 11)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                                .accessibilityIdentifier("user-message-text")
                        }
                        actions
                    }
                }.frame(maxWidth: .infinity, alignment: .trailing)
            } else if message.role == .tool {
                WorkReceiptView(message: message)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if !message.text.isEmpty || !message.displayParts.isEmpty { ResponseContentView(message: message) }
                    if message.state == .interrupted || message.state == .failed {
                        Label(message.state == .interrupted ? "Stopped · partial response saved" : "Incomplete response", systemImage: "pause.circle")
                            .font(.caption).foregroundStyle(.secondary)
                        if let reason = message.failureReason { Text(reason).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                    if message.containsLocalOnlyContext { Label("On-device-only context", systemImage: "iphone").font(.caption2).foregroundStyle(.secondary) }
                    if !message.displayCitations.isEmpty { SourceListView(citations: message.displayCitations) }
                    attachments
                    if showsResponseActions && !message.answerText.isEmpty { actions }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(item: $selectedImage) { selection in CaptureViewer(captureID: selection.id, initialPoints: selection.points) }
    }
    @ViewBuilder private var attachments: some View {
        if !message.captureIDs.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(message.captureIDs, id: \.self) { id in
                        Button { selectedImage = ImageSelection(id: id, points: message.imageSelections[id.uuidString] ?? []) } label: {
                            CaptureThumbnail(id: id).frame(width: 132, height: 132).clipShape(RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain).accessibilityLabel("Open attached image")
                    }
                }
            }.scrollIndicators(.hidden).frame(maxWidth: 300, alignment: .leading)
        }
        ForEach(message.fileIDs, id: \.self) { id in
            if let file = model.files.first(where: { $0.id == id }) {
                NavigationLink { WorkspaceFileView(id: id) } label: {
                    Label(file.filename, systemImage: file.icon).font(.footnote).lineLimit(2).padding(10)
                        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityLabel("Open attached file \(file.filename)")
            } else { Label("File removed from Library", systemImage: "doc").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var actions: some View {
        HStack(spacing: 8) {
            if !message.text.isEmpty {
                Button { UIPasteboard.general.string = message.role == .user ? message.text : message.answerText } label: { Image(systemName: "doc.on.doc").frame(width: 32, height: 32) }.accessibilityLabel("Copy message")
                ShareLink(item: message.role == .user ? message.text : message.answerText) { Image(systemName: "square.and.arrow.up").frame(width: 32, height: 32) }.accessibilityLabel("Share message")
            }
            if message.role == .assistant {
                Button { voice.speak(MarkdownContent(message.answerText).renderPlainText()) } label: { Image(systemName: "speaker.wave.2").frame(width: 32, height: 32) }.accessibilityLabel("Read response aloud")
            } else {
                Button { model.beginEditing(message) } label: { Image(systemName: "pencil").frame(width: 32, height: 32) }
                    .accessibilityLabel("Edit message").disabled(model.isRunning)
            }
        }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier(message.role == .assistant ? "final-response-actions" : "user-message-actions")
    }
}
