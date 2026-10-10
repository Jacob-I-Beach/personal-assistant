import AssistantCore
import SwiftUI
import UIKit

struct CaptureViewer: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let captureID: UUID
    var initialPoints: [ImagePoint] = []
    @State private var capture: CaptureObservation?
    @State private var image: UIImage?
    @State private var points: [ImagePoint] = []
    @State private var exportURLs: [URL] = []
    @State private var failure: String?
    private var inspection: DepthInspection? { capture.flatMap { try? DepthInspection.inspect($0, points: points) } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let image {
                    ZoomableCapture(image: image, points: points) { point in
                        guard capture?.depth != nil else { return }
                        if points.count == 2 { points = [point] } else { points.append(point) }
                    }.frame(minHeight: 220, idealHeight: 350, maxHeight: 430)
                        .accessibilityLabel(capture?.depth == nil ? "Image. Pinch to zoom." : "Depth image. Pinch to zoom; tap up to two visible surfaces to inspect saved depth.")
                } else if let failure { ContentUnavailableView("Image unavailable", systemImage: "photo", description: Text(failure)) }
                else { ProgressView("Opening image").frame(height: 300) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let capture {
                            HStack { Text(capture.source).font(.subheadline.weight(.medium)); Spacer(); if !points.isEmpty { Button("Clear points") { points = [] }.font(.caption) } }
                            Text("Captured \(capture.capturedAt.formatted())").font(.caption).foregroundStyle(.secondary)
                            if capture.depth != nil {
                                if let inspection {
                                    DepthInspectionView(inspection: inspection)
                                } else {
                                    Label("Tap one point for depth, or two to estimate the separation between visible surfaces.", systemImage: "viewfinder").font(.subheadline)
                                    Text("Use this to explore relative layout or approximate spacing. Measurements come from the saved capture.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if !capture.recognizedText.isEmpty {
                                DisclosureGroup("Recognized text") { Text(capture.recognizedText.joined(separator: "\n")).font(.subheadline).textSelection(.enabled).padding(.top, 8) }
                            }
                            if !points.isEmpty {
                                Button("Use selected points in chat", systemImage: "paperclip") {
                                    model.attach(captureID); model.selectedImagePoints[captureID.uuidString] = points; model.flushDraft(); dismiss()
                                }.disabled(model.isRunning)
                                Text("Attaches the image and selected coordinates. Your message stays unchanged.").font(.caption).foregroundStyle(.secondary)
                            }
                            if !exportURLs.isEmpty { ShareLink(items: exportURLs) { Label("Share image and observation", systemImage: "square.and.arrow.up") }.font(.subheadline) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                }
            }
            .navigationTitle("Image").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task(id: captureID) {
            points = initialPoints
            capture = model.captures.first { $0.id == captureID }
            if capture == nil { capture = try? await model.store?.loadCapture(captureID) }
            image = await model.image(captureID)
            if image == nil { failure = "This image is no longer available in the app's Library." }
            exportURLs = await model.captureExportURLs(captureID)
        }
    }
}

struct DepthInspectionView: View {
    let inspection: DepthInspection
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(inspection.readings.enumerated()), id: \.offset) { index, reading in
                HStack(alignment: .firstTextBaseline) {
                    Text("Point \(index + 1)").foregroundStyle(.secondary)
                    Spacer()
                    if let meters = reading.axialMeters { Text("\(meters, format: .number.precision(.fractionLength(2))) m depth").monospacedDigit() }
                    else { Text("Insufficient depth samples") }
                }.font(.subheadline)
            }
            if let meters = inspection.separationMeters {
                LabeledContent("Approximate separation", value: "\(meters.formatted(.number.precision(.fractionLength(2)))) m").font(.subheadline.weight(.medium))
            }
            ForEach(inspection.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            Text(inspection.limitation).font(.caption).foregroundStyle(.secondary)
        }.textSelection(.enabled)
    }
}

private struct ZoomableCapture: UIViewRepresentable {
    let image: UIImage
    let points: [ImagePoint]
    let tapped: (ImagePoint) -> Void
    func makeUIView(context: Context) -> ZoomCaptureCanvas { ZoomCaptureCanvas() }
    func updateUIView(_ view: ZoomCaptureCanvas, context: Context) { view.configure(image: image, points: points, tapped: tapped) }
}
@MainActor
private final class ZoomCaptureCanvas: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var points: [ImagePoint] = []
    private var pointLabels: [UILabel] = []
    private var tapped: ((ImagePoint) -> Void)?
    private var fittedSize = CGSize.zero
    override init(frame: CGRect) {
        super.init(frame: frame); delegate = self; backgroundColor = .black
        contentInsetAdjustmentBehavior = .never; showsVerticalScrollIndicator = false; showsHorizontalScrollIndicator = false
        imageView.isUserInteractionEnabled = true; addSubview(imageView)
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(selectPoint(_:))))
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    func configure(image: UIImage, points: [ImagePoint], tapped: @escaping (ImagePoint) -> Void) {
        self.tapped = tapped; self.points = points
        if imageView.image !== image {
            zoomScale = 1; imageView.image = image; imageView.frame = CGRect(origin: .zero, size: image.size)
            contentSize = image.size; fittedSize = .zero
        }
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else { return }
        if fittedSize != bounds.size {
            let wasFitted = fittedSize == .zero || abs(zoomScale - minimumZoomScale) < 0.001
            let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
            minimumZoomScale = fit; maximumZoomScale = max(fit * 6, 1)
            if wasFitted { zoomScale = fit }
            fittedSize = bounds.size
        }
        centerImage(); drawPoints()
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage(); drawPoints() }
    private func centerImage() {
        let x = max(0, (bounds.width - contentSize.width) / 2), y = max(0, (bounds.height - contentSize.height) / 2)
        let insets = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        if contentInset != insets { contentInset = insets }
    }
    private func drawPoints() {
        pointLabels.forEach { $0.removeFromSuperview() }; pointLabels = []
        for (index, point) in points.enumerated() {
            let size = 24 / max(zoomScale, 0.001)
            let label = UILabel(frame: CGRect(x: point.x * imageView.bounds.width - size / 2, y: point.y * imageView.bounds.height - size / 2, width: size, height: size))
            label.text = String(index + 1); label.textAlignment = .center; label.font = .systemFont(ofSize: size * 0.55, weight: .semibold)
            label.textColor = .black; label.backgroundColor = .white; label.layer.cornerRadius = size / 2; label.clipsToBounds = true
            label.layer.borderColor = UIColor.black.cgColor; label.layer.borderWidth = 1 / max(zoomScale, 0.001)
            imageView.addSubview(label); pointLabels.append(label)
        }
    }
    @objc private func selectPoint(_ gesture: UITapGestureRecognizer) {
        guard imageView.bounds.width > 0, imageView.bounds.height > 0 else { return }
        let location = gesture.location(in: imageView)
        let point = ImagePoint(x: location.x / imageView.bounds.width, y: location.y / imageView.bounds.height)
        if point.isValid { tapped?(point) }
    }
}
