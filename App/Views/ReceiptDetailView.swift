import AssistantCore
import SwiftUI

struct ReceiptDetailView: View {
    let nodes: [ReceiptDetail]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(nodes) { node in
                if !node.children.isEmpty {
                    AssistantDisclosure(nested: true) {
                        ReceiptDetailView(nodes: node.children).padding(.leading, 10).padding(.top, 10)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(node.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                            if let value = node.value { Text(value).font(.caption).foregroundStyle(.secondary) }
                        }
                    }.tint(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.title).font(.caption).foregroundStyle(.secondary)
                        if let value = node.value {
                            if node.isProse { AssistantMarkdown(text: value).font(.subheadline).textSelection(.enabled) }
                            else { Text(value).font(.subheadline).foregroundStyle(.primary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
