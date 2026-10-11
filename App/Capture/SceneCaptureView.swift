import ARKit
import AssistantCore
import AVFoundation
import Combine
import CoreImage
import ImageIO
import RealityKit
import SwiftUI

@MainActor
final class SceneCaptureController: ObservableObject {
    @Published var authorized = false
    @Published var isCapturing = false
    @Published var status = "Preparing camera"
    weak var view: ARView?
    let supportsDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    private let context = CIContext()

    func requestCamera() async {
        guard ARWorldTrackingConfiguration.isSupported else {
            status = "Scene capture requires a physical iPhone. You can import a selected photo instead."
            return
        }
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        authorized = allowed
        status = allowed ? (supportsDepth ? "Camera + LiDAR depth" : "Camera only; depth unavailable") : "Camera access was not granted. Enable it in iOS Settings if desired."
    }
    func attach(_ view: ARView) {
        self.view = view
        let configuration = ARWorldTrackingConfiguration()
        if supportsDepth { configuration.frameSemantics.insert(.sceneDepth) }
        view.session.run(configuration)
    }
    func pause() { view?.session.pause() }

    func snapshot() async throws -> (CaptureObservation, Data) {
        guard !isCapturing else { throw AssistantError.busy }
        guard let frame = view?.session.currentFrame else { throw AssistantError.invalidCapture("No camera frame is ready. Hold the phone steady and try again.") }
        isCapturing = true; defer { isCapturing = false }
        let capturedAt = Date()
        let raw = CIImage(cvPixelBuffer: frame.capturedImage)
        // The app is portrait-only in this first slice. The rear AR sensor image is landscape-native.
        let upright = raw.oriented(.right)
        let factor = min(1, 1600 / max(upright.extent.width, upright.extent.height))
        let image = upright.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        guard let jpeg = context.jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                    options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.86]) else {
            throw AssistantError.invalidCapture("The camera image could not be encoded.")
        }
        let camera = frame.camera
        let pose = [camera.transform.columns.0, camera.transform.columns.1, camera.transform.columns.2, camera.transform.columns.3]
            .flatMap { [$0.x, $0.y, $0.z, $0.w] }
        let intrinsics = [camera.intrinsics.columns.0, camera.intrinsics.columns.1, camera.intrinsics.columns.2]
            .flatMap { [$0.x, $0.y, $0.z] }
        let grid = frame.sceneDepth.flatMap(Self.copyDepth)
        var observation = CaptureObservation(capturedAt: capturedAt, sensorTimestampSeconds: frame.timestamp,
            source: grid == nil ? "Rear AR camera" : "Rear AR camera + LiDAR",
            imageWidth: CVPixelBufferGetWidth(frame.capturedImage), imageHeight: CVPixelBufferGetHeight(frame.capturedImage),
            imageRotationDegrees: 90, depth: grid, cameraTransform: pose, cameraIntrinsics: intrinsics,
            trackingState: String(describing: camera.trackingState))
        observation.recognizedText = try await CaptureProcessor.shared.recognizeText(in: jpeg)
        try observation.validate()
        return (observation, jpeg)
    }

    private static func copyDepth(_ source: ARDepthData) -> DepthGrid? {
        let depth = source.depthMap
        guard CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferLockBaseAddress(depth, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        let confidence = source.confidenceMap
        if let confidence { CVPixelBufferLockBaseAddress(confidence, .readOnly) }
        defer { if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) } }
        let width = CVPixelBufferGetWidth(depth), height = CVPixelBufferGetHeight(depth)
        let outWidth = min(width, 64), outHeight = min(height, 48)
        let stride = CVPixelBufferGetBytesPerRow(depth)
        guard let base = CVPixelBufferGetBaseAddress(depth) else { return nil }
        let confidenceBase = confidence.flatMap { CVPixelBufferGetBaseAddress($0) }
        let confidenceStride = confidence.map { CVPixelBufferGetBytesPerRow($0) } ?? 0
        var meters: [Float?] = []
        var quality: [UInt8] = []
        for y in 0..<outHeight {
            for x in 0..<outWidth {
                let sx = x * width / outWidth, sy = y * height / outHeight
                let value = base.load(fromByteOffset: sy * stride + sx * MemoryLayout<Float>.stride, as: Float.self)
                meters.append(value.isFinite && value > 0 ? value : nil)
                if let confidenceBase { quality.append(confidenceBase.load(fromByteOffset: sy * confidenceStride + sx, as: UInt8.self)) }
            }
        }
        return DepthGrid(width: outWidth, height: outHeight, meters: meters, confidence: confidenceBase == nil ? nil : quality)
    }
}

private struct SceneCameraView: UIViewRepresentable {
    let controller: SceneCaptureController
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        controller.attach(view)
        return view
    }
    func updateUIView(_ uiView: ARView, context: Context) {}
    static func dismantleUIView(_ uiView: ARView, coordinator: ()) { uiView.session.pause() }
}

struct SceneCaptureSheet: View {
    var onCapture: ((CaptureObservation, Data) async throws -> Void)? = nil
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = SceneCaptureController()
    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if controller.authorized {
                    SceneCameraView(controller: controller)
                        .overlay { Image(systemName: "plus").font(.title).foregroundStyle(.white).shadow(radius: 2) }
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else { ContentUnavailableView("Camera", systemImage: "camera", description: Text(controller.status)) }
                Text(controller.status).font(.subheadline)
                Text("Depth describes the saved center region, not an object's dimensions. Capture only what you want included.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    Task {
                        do {
                            let (capture, jpeg) = try await controller.snapshot()
                            if let onCapture { try await onCapture(capture, jpeg); dismiss() }
                            else if await model.saveCapture(capture, jpeg: jpeg) { dismiss() }
                        } catch { model.errorMessage = error.localizedDescription }
                    }
                } label: {
                    Label(controller.isCapturing ? "Reading capture…" : "Capture and attach", systemImage: "camera.shutter.button")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Color(uiColor: .systemBackground))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.authorized || controller.isCapturing)
            }
            .padding()
            .navigationTitle("Observe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await controller.requestCamera() }
            .onDisappear { controller.pause() }
        }
    }
}
