import AssistantCore
import SwiftUI
import Textual

struct AssistantMarkdown: View {
    let text: String
    var body: some View {
        StructuredText(markdown: MathMarkdown.normalize(text), syntaxExtensions: [.math])
            .font(.body)
            .textual.codeBlockStyle(AssistantCodeBlockStyle())
            .textual.structuredTextStyle(.gitHub)
            .textual.imageAttachmentLoader(ExplicitImageAttachmentLoader())
            .textual.emojiAttachmentLoader(ExplicitImageAttachmentLoader())
            .textual.textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, url.user == nil, url.password == nil else { return .discarded }
                return .systemAction
            })
    }
}

private struct AssistantCodeBlockStyle: StructuredText.CodeBlockStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(configuration.languageHint ?? "Code").font(.caption).foregroundStyle(.secondary)
                Spacer()
                MessageActionButton(title: "Copy code", icon: "doc.on.doc", confirmation: "Copied") { configuration.codeBlock.copyToPasteboard() }
            }.padding(.horizontal, 12).padding(.top, 10)
            ScrollView(.horizontal) {
                configuration.label.textual.fontScale(0.85).monospaced().padding(12)
            }
        }.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .textual.blockSpacing(.init(top: 4, bottom: 14))
    }
}

/// Displaying model-supplied Markdown never fetches remote images or runs HTML.
struct ExplicitImageAttachmentLoader: AttachmentLoader {
    func attachment(for url: URL, text: String, environment: ColorEnvironmentValues) async throws -> LinkedImageAttachment {
        LinkedImageAttachment()
    }
}
struct LinkedImageAttachment: Attachment {
    var description: String { "Linked image" }
    var body: some View { Label("Linked image", systemImage: "photo").font(.caption).foregroundStyle(.secondary) }
    func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
        CGSize(width: min(proposal.width ?? 115, 115), height: 24)
    }
}
