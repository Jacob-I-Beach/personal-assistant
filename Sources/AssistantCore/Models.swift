import Foundation

public enum MessageRole: String, Codable, Sendable { case user, assistant, tool }
public enum MessageState: String, Codable, Sendable { case complete, streaming, interrupted, failed }

public struct ToolCall: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var arguments: JSONValue
    public init(id: String, name: String, arguments: JSONValue) {
        self.id = id; self.name = name; self.arguments = arguments
    }
}

public struct ProviderContinuation: Codable, Equatable, Sendable {
    public var providerID: String
    public var items: [JSONValue]
    public init(providerID: String, items: [JSONValue]) { self.providerID = providerID; self.items = items }
}

public struct Message: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var role: MessageRole
    public var text: String
    public var createdAt: Date
    public var state: MessageState
    public var captureIDs: [UUID]
    public var toolCalls: [ToolCall]
    public var toolCallID: String?
    public var providerID: String?
    public var continuation: ProviderContinuation?

    public init(id: UUID = UUID(), role: MessageRole, text: String, state: MessageState = .complete,
                captureIDs: [UUID] = [], toolCalls: [ToolCall] = [], toolCallID: String? = nil,
                providerID: String? = nil, continuation: ProviderContinuation? = nil) {
        self.id = id; self.role = role; self.text = text; self.createdAt = Date(); self.state = state
        self.captureIDs = captureIDs; self.toolCalls = toolCalls; self.toolCallID = toolCallID
        self.providerID = providerID; self.continuation = continuation
    }
}

public struct Conversation: Codable, Equatable, Sendable, Identifiable {
    public var schemaVersion = 1
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var messages: [Message]
    public var allowedNetworkDestinations: Set<String>

    public init(id: UUID = UUID(), title: String = "New conversation") {
        self.id = id; self.title = title; self.createdAt = Date(); self.updatedAt = Date()
        self.messages = []; self.allowedNetworkDestinations = []
    }
    public var attachedCaptureIDs: Set<UUID> { Set(messages.flatMap(\.captureIDs)) }
    public mutating func recoverInterruptedMessages() {
        for i in messages.indices where messages[i].state == .streaming { messages[i].state = .interrupted }
    }
}

public struct DepthGrid: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    /// Row-major camera-space depth in meters. Missing/invalid readings are nil.
    public var meters: [Float?]
    /// ARKit qualitative confidence: 0 low, 1 medium, 2 high. Not a probability.
    public var confidence: [UInt8]?
    public init(width: Int, height: Int, meters: [Float?], confidence: [UInt8]? = nil) {
        self.width = width; self.height = height; self.meters = meters; self.confidence = confidence
    }
    public func validate() throws {
        guard width > 0, height > 0, width <= 2048, height <= 2048,
              meters.count == width * height, confidence == nil || confidence?.count == meters.count,
              confidence == nil || confidence!.allSatisfy({ $0 <= 2 }),
              meters.allSatisfy({ $0 == nil || ($0!.isFinite && $0! > 0) }) else {
            throw AssistantError.invalidCapture("Depth dimensions or samples are invalid.")
        }
    }
    public func centerSummary() throws -> DepthSummary {
        try validate()
        let left = width * 2 / 5, right = max(left + 1, width * 3 / 5)
        let top = height * 2 / 5, bottom = max(top + 1, height * 3 / 5)
        var values: [Float] = []
        var rejected = 0
        for y in top..<min(bottom, height) {
            for x in left..<min(right, width) {
                let i = y * width + x
                if let value = meters[i], confidence == nil || confidence![i] >= 1 {
                    values.append(value)
                } else { rejected += 1 }
            }
        }
        values.sort()
        let median: Float? = values.isEmpty ? nil : values.count.isMultiple(of: 2)
            ? (values[values.count / 2 - 1] + values[values.count / 2]) / 2
            : values[values.count / 2]
        return DepthSummary(medianMeters: median, acceptedSamples: values.count, rejectedSamples: rejected,
                            hasSensorConfidence: confidence != nil)
    }
}

public struct DepthSummary: Codable, Equatable, Sendable {
    public var medianMeters: Float?
    public var acceptedSamples: Int
    public var rejectedSamples: Int
    public var hasSensorConfidence: Bool
    public var method = "Median in central 20% of the saved depth grid; low-confidence samples excluded when available."
    public var limitation = "Camera-space depth at capture time; not object dimensions, a calibrated error bound, or a current reading."
}

public struct CaptureObservation: Codable, Equatable, Sendable, Identifiable {
    public var schemaVersion = 1
    public var id: UUID
    public var capturedAt: Date
    public var sensorTimestampSeconds: Double?
    public var source: String
    /// Native sensor-image dimensions; the saved JPEG can be rotated for display.
    public var imageWidth: Int
    public var imageHeight: Int
    /// JPEG is normalized for display; depth/intrinsics remain in the native sensor orientation.
    public var imageRotationDegrees: Int
    public var recognizedText: [String]
    public var depth: DepthGrid?
    public var cameraTransform: [Float]?
    public var cameraIntrinsics: [Float]?
    public var trackingState: String

    public init(id: UUID = UUID(), capturedAt: Date = Date(), sensorTimestampSeconds: Double? = nil, source: String,
                imageWidth: Int, imageHeight: Int, imageRotationDegrees: Int = 0,
                recognizedText: [String] = [], depth: DepthGrid? = nil,
                cameraTransform: [Float]? = nil, cameraIntrinsics: [Float]? = nil,
                trackingState: String = "not available") {
        self.id = id; self.capturedAt = capturedAt; self.sensorTimestampSeconds = sensorTimestampSeconds; self.source = source
        self.imageWidth = imageWidth; self.imageHeight = imageHeight; self.imageRotationDegrees = imageRotationDegrees
        self.recognizedText = recognizedText; self.depth = depth; self.cameraTransform = cameraTransform
        self.cameraIntrinsics = cameraIntrinsics; self.trackingState = trackingState
    }
    public func validate() throws {
        guard schemaVersion == 1, imageWidth > 0, imageHeight > 0,
              sensorTimestampSeconds == nil || sensorTimestampSeconds!.isFinite,
              imageWidth <= 20000, imageHeight <= 20000,
              [0, 90, 180, 270].contains(imageRotationDegrees),
              cameraTransform == nil || cameraTransform?.count == 16,
              cameraIntrinsics == nil || cameraIntrinsics?.count == 9,
              (cameraTransform ?? []).allSatisfy(\.isFinite),
              (cameraIntrinsics ?? []).allSatisfy(\.isFinite) else {
            throw AssistantError.invalidCapture("Capture metadata is invalid.")
        }
        try depth?.validate()
    }
}

public enum AssistantError: Error, LocalizedError, Sendable {
    case invalidCapture(String), invalidEndpoint(String), malformedStream(String), provider(String)
    case incompleteResponse, networkNotAuthorized, invalidTool(String), unsupportedSchema(Int), busy
    public var errorDescription: String? {
        switch self {
        case .invalidCapture(let s), .invalidEndpoint(let s), .malformedStream(let s), .provider(let s), .invalidTool(let s): s
        case .incompleteResponse: "The model stream ended without a completed response. The partial answer was saved."
        case .networkNotAuthorized: "Allow this conversation to use the selected network destination before sending."
        case .unsupportedSchema(let version): "This data uses unsupported schema version \(version). It was not overwritten."
        case .busy: "A response is already running. Stop it before starting another."
        }
    }
}
