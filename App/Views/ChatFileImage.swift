import AssistantCore
import ImageIO
import QuickLook
import SwiftUI

struct ChatFileImage: View {
    @EnvironmentObject private var model: AppModel
    let file: WorkspaceFile
    @State private var thumbnail: UIImage?
    @State private var url: URL?
    @State private var preview: URL?
    @State private var loading = true
    var body: some View {
        Button { preview = url } label: {
            VStack(alignment: .leading, spacing: 6) {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFit()
                        .frame(maxWidth: 400, maxHeight: 440)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else if loading { ProgressView("Loading image").frame(minHeight: 100) }
                else { Label("Preview image", systemImage: "photo").padding(16) }
                Text(file.filename).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }.buttonStyle(.plain).disabled(url == nil).accessibilityLabel("Open image \(file.filename)")
            .quickLookPreview($preview)
            .task(id: file.id) {
                loading = true
                guard let source = await model.fileURL(file.id) else { loading = false; return }
                url = source
                let data = await Task.detached(priority: .utility) { Self.thumbnailData(source) }.value
                if !Task.isCancelled { thumbnail = data.flatMap { UIImage(data: $0) }; loading = false }
            }
    }
    nonisolated private static func thumbnailData(_ url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1200] as CFDictionary) else { return nil }
        return UIImage(cgImage: image).pngData()
    }
}
