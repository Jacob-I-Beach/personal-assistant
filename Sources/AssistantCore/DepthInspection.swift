import Foundation

public struct ImagePoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}
public struct DepthReading: Codable, Equatable, Sendable {
    public var point: ImagePoint
    public var axialMeters: Double?
    public var minimumMeters: Double?
    public var maximumMeters: Double?
    public var acceptedSamples: Int
    public var excludedSamples: Int
    public var cameraPoint: [Double]?
}
public struct DepthInspection: Codable, Equatable, Sendable {
    public var captureID: UUID
    public var capturedAt: Date
    public var readings: [DepthReading]
    public var separationMeters: Double?
    public var warnings: [String]
    public let method = "Median of a 3 by 3 neighborhood in the saved native depth grid, excluding missing and low-confidence samples. Points use normalized coordinates in the displayed image."
    public let limitation = "Approximate saved surface measurements, not live readings or a calibrated accuracy guarantee. Two-point separation does not establish an object's dimensions, fit, or hidden geometry."

    public static let tool = ToolDefinition(name: "inspect_depth", description: "Inspect saved LiDAR depth at one or two visible image positions, or estimate their straight-line separation using saved camera calibration. Useful for relative layout and approximate distances between visible surfaces. Coordinates are normalized in the displayed image. Does not capture live depth or guarantee object dimensions.", parameters: .object([
        "type": .string("object"), "properties": .object([
            "capture_id": .object(["type": .string("string"), "description": .string("UUID of an image attached to this conversation.")]),
            "points_json": .object(["type": .string("string"), "description": .string("JSON array of one or two points, each exactly {x: number, y: number}; coordinates 0 to 1, origin at the displayed image's top left.")])
        ]), "required": .array([.string("capture_id"), .string("points_json")]), "additionalProperties": .bool(false)
    ]))
    public static func inspect(_ capture: CaptureObservation, points: [ImagePoint]) throws -> Self {
        try capture.validate()
        guard (1...2).contains(points.count), points.allSatisfy(\.isValid), let grid = capture.depth else {
            throw AssistantError.invalidCapture("Choose one or two points inside an image with saved depth.")
        }
        var warnings: [String] = []
        if grid.confidence == nil { warnings.append("This capture has no sensor-confidence map.") }
        if capture.trackingState != "normal" { warnings.append("Camera tracking was not normal at capture time; separation is unavailable.") }
        var readings: [DepthReading] = []
        for point in points {
            let native: ImagePoint
            switch capture.imageRotationDegrees {
            case 90: native = ImagePoint(x: point.y, y: 1 - point.x)
            case 180: native = ImagePoint(x: 1 - point.x, y: 1 - point.y)
            case 270: native = ImagePoint(x: 1 - point.y, y: point.x)
            default: native = point
            }
            let gx = min(grid.width - 1, Int(native.x * Double(grid.width)))
            let gy = min(grid.height - 1, Int(native.y * Double(grid.height)))
            var samples: [Double] = []; var excluded = 0
            for y in max(0, gy - 1)...min(grid.height - 1, gy + 1) {
                for x in max(0, gx - 1)...min(grid.width - 1, gx + 1) {
                    let i = y * grid.width + x
                    if let z = grid.meters[i], grid.confidence == nil || grid.confidence![i] >= 1 { samples.append(Double(z)) }
                    else { excluded += 1 }
                }
            }
            samples.sort()
            let depth: Double? = samples.count < 3 ? nil : samples.count.isMultiple(of: 2) ? (samples[samples.count / 2 - 1] + samples[samples.count / 2]) / 2 : samples[samples.count / 2]
            var cameraPoint: [Double]?
            if let z = depth, let k = capture.cameraIntrinsics, k[0] > 0, k[4] > 0 {
                let u = (Double(gx) + 0.5) / Double(grid.width) * Double(capture.imageWidth) - 0.5
                let v = (Double(gy) + 0.5) / Double(grid.height) * Double(capture.imageHeight) - 0.5
                cameraPoint = [(u - Double(k[6])) / Double(k[0]) * z, (v - Double(k[7])) / Double(k[4]) * z, z]
            }
            if depth == nil { warnings.append("A selected point has fewer than three usable samples.") }
            if let low = samples.first, let high = samples.last, high - low > max(0.05, (depth ?? low) * 0.1) {
                warnings.append("A selected neighborhood crosses substantially different depths; it may span an edge or a noisy surface.")
                cameraPoint = nil
            }
            readings.append(.init(point: point, axialMeters: depth, minimumMeters: samples.first, maximumMeters: samples.last, acceptedSamples: samples.count, excludedSamples: excluded, cameraPoint: cameraPoint))
        }
        var separation: Double?
        if readings.count == 2, capture.trackingState == "normal", let a = readings[0].cameraPoint, let b = readings[1].cameraPoint {
            separation = sqrt(zip(a, b).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) })
        }
        if points.count == 2 && separation == nil { warnings.append("A usable pair of depth samples and camera calibration is required for separation.") }
        return Self(captureID: capture.id, capturedAt: capture.capturedAt, readings: readings, separationMeters: separation, warnings: warnings)
    }
}
