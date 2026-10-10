import AssistantCore
import SwiftUI
import UIKit

struct CaptureLibraryView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
            List(model.captures) { capture in
                NavigationLink {
                    CaptureDetailView(capture: capture)
                } label: {
                    VStack(alignment: .leading) {
                        Text(capture.recognizedText.first ?? capture.source).lineLimit(1)
                        Text(capture.capturedAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        Label(capture.depth == nil ? "Image + OCR" : "Image + OCR + depth", systemImage: "viewfinder").font(.caption)
                    }
                }
            }
            .overlay { if model.captures.isEmpty { ContentUnavailableView("No captures", systemImage: "viewfinder", description: Text("Use the + button in Assistant to capture or import an image.")) } }
            .navigationTitle("Captures")
            .refreshable { await model.refresh() }
    }
}

private struct CaptureDetailView: View {
    @EnvironmentObject private var model: AppModel
    let capture: CaptureObservation
    @State private var image: UIImage?
    @State private var exportURLs: [URL] = []
    @State private var showImage = false
    var body: some View {
        List {
            if let image { Button { showImage = true } label: { Image(uiImage: image).resizable().scaledToFit() }.buttonStyle(.plain).accessibilityLabel("Open image") }
            Section("Saved observation") {
                LabeledContent("Captured", value: capture.capturedAt.formatted())
                LabeledContent("Source", value: capture.source)
                Text(capture.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                Text(capture.trackingState).font(.caption)
            }
            if let grid = capture.depth, let summary = try? grid.centerSummary() {
                Section("Center depth") {
                    if let meters = summary.medianMeters { Text("\(meters, format: .number.precision(.fractionLength(2))) m") }
                    else { Text("No usable center-depth samples") }
                    Text("\(summary.acceptedSamples) accepted samples; \(summary.rejectedSamples) excluded.").font(.caption)
                    Text(summary.limitation).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Recognized text") {
                if capture.recognizedText.isEmpty { Text("No text recognized").foregroundStyle(.secondary) }
                ForEach(Array(capture.recognizedText.enumerated()), id: \.offset) { _, text in Text(text).textSelection(.enabled) }
            }
            Section {
                Button("Attach to current conversation", systemImage: "paperclip") { model.attach(capture.id) }.disabled(model.isRunning)
                if !exportURLs.isEmpty { ShareLink(items: exportURLs) { Label("Export image and observation", systemImage: "square.and.arrow.up") } }
            }
        }
        .navigationTitle("Capture")
        .sheet(isPresented: $showImage) { CaptureViewer(captureID: capture.id) }
        .task {
            image = await model.image(capture.id)
            exportURLs = await model.captureExportURLs(capture.id)
        }
    }
}
