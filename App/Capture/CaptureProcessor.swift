import AssistantCore
import CoreImage
import Foundation
import ImageIO
import Vision

actor CaptureProcessor {
    static let shared = CaptureProcessor()
    private let context = CIContext()

    func recognizeText(in jpeg: Data) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(data: jpeg, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    func importPhoto(_ data: Data) throws -> (CaptureObservation, Data) {
        guard let input = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            throw AssistantError.invalidCapture("This image could not be decoded.")
        }
        let maximumDimension: CGFloat = 1600
        let factor = min(1, maximumDimension / max(input.extent.width, input.extent.height))
        let image = input.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let jpeg = context.jpegRepresentation(of: image, colorSpace: colorSpace,
                                                    options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.86]) else {
            throw AssistantError.invalidCapture("The imported image could not be prepared.")
        }
        let text = try recognizeText(in: jpeg)
        let capture = CaptureObservation(source: "Selected photo (no sensor depth)",
                                         imageWidth: Int(image.extent.width), imageHeight: Int(image.extent.height),
                                         recognizedText: text)
        return (capture, jpeg)
    }
}
