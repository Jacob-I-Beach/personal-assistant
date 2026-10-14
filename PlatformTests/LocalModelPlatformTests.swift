import XCTest
import Network
import AssistantCore
@testable import PersonalAssistant

final class LocalModelPlatformTests: XCTestCase {
    func testQwenTextPlanUsesTheReportedHeadroomAndAutomaticDoesNotReuseOldManualContext() {
        let backend = MLXLocalBackend(repository: "mlx-community/Qwen3.5-4B-4bit", revision: "fixture", root: FileManager.default.temporaryDirectory,
            responseTokens: 2048, supportsVision: true, weightBytes: 3_034_300_695, textWeightBytes: 2_367_118_848, requestedContextTokens: 131_072)
        let reported = backend.planningBudget(memoryGiB: 8, contextTokens: nil, availableBytes: Int64(3.05 * 1_073_741_824))
        XCTAssertFalse(reported.fits); XCTAssertEqual(reported.selectedContextTokens, 65_536)
        let granted = backend.planningBudget(memoryGiB: 8, contextTokens: nil, availableBytes: 6 * 1_073_741_824)
        XCTAssertTrue(granted.fits); XCTAssertNil(granted.attentionCacheBits)
        let automatic = backend.planningBudget(memoryGiB: 8, contextTokens: nil, availableBytes: 10_000_000_000)
        XCTAssertEqual(automatic.selectedContextTokens, 65_536)
        let manual = backend.planningBudget(memoryGiB: 8, contextTokens: 131_072, availableBytes: 10_000_000_000)
        XCTAssertEqual(manual.selectedContextTokens, 131_072)
        XCTAssertEqual(backend.residentBytes, 0, "Planning alone must not initialize Metal or load weights.")
    }
    func testPinnedDownloadReportsBytesAndReusesCompletedFileWithoutAnotherRequest() async throws {
        let bytes = Data(repeating: 42, count: 512 * 1024), server = try ModelFileFixture(bytes: Data(repeating: 42, count: 512 * 1024))
        let address = try await server.start()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { server.stop(); try? FileManager.default.removeItem(at: root) }
        let progress = DownloadProgressFixture()
        let files = [LocalModelCatalogEntry.File(name: "model.safetensors", bytes: Int64(bytes.count), sha256: nil)]
        let directory = try await ModelPackageDownload.download(repository: "fixture/model", revision: String(repeating: "a", count: 40), root: root,
            files: files, allowCellular: false, host: address, progress: { progress.record($0) })
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("model.safetensors")), bytes)
        XCTAssertTrue(progress.values.contains { $0 > 0 })
        XCTAssertEqual(server.requests, 1)
        _ = try await ModelPackageDownload.download(repository: "fixture/model", revision: String(repeating: "a", count: 40), root: root,
            files: files, allowCellular: false, host: address, progress: { _ in })
        XCTAssertEqual(server.requests, 1)
    }
    func testLocalPreferencesPersistAndPersonalBuildDoesNotClaimPushProvisioning() throws {
        var settings = ModelSettings(); settings.localMemoryGiB = 6; settings.localContextTokens = 65_536
        let decoded = try JSONDecoder().decode(ModelSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.localMemoryGiB, 6); XCTAssertEqual(decoded.localContextTokens, 65_536)
        XCTAssertNotEqual(Bundle.main.object(forInfoDictionaryKey: "AssistantPushEnvironment") as? String, "production")
    }
}

private final class DownloadProgressFixture: @unchecked Sendable {
    private let lock = NSLock(); private var recorded: [Double] = []
    var values: [Double] { lock.withLock { recorded } }
    func record(_ value: Double) { lock.withLock { recorded.append(value) } }
}
private final class ModelFileFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "assistant.model-file-fixture")
    private let bytes: Data
    private let lock = NSLock(); private var count = 0
    var requests: Int { lock.withLock { count } }
    init(bytes: Data) throws { self.bytes = bytes; listener = try NWListener(using: .tcp, on: .any) }
    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                if case .ready = state, let port = self.listener.port {
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)")!)
                } else if case .failed(let error) = state { self.listener.stateUpdateHandler = nil; continuation.resume(throwing: error) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }; connection.start(queue: self.queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] _, _, _, _ in
                    guard let self else { return }; self.lock.withLock { self.count += 1 }
                    var response = Data("HTTP/1.1 200 OK\r\nContent-Length: \(self.bytes.count)\r\nContent-Type: application/octet-stream\r\nConnection: close\r\n\r\n".utf8)
                    response.append(self.bytes)
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                }
            }
            listener.start(queue: queue)
        }
    }
    func stop() { listener.cancel() }
}
