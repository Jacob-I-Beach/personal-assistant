import XCTest
@testable import AssistantCore

final class TextModelWeightsTests: XCTestCase, @unchecked Sendable {
    func testCancelledPreparationKeepsSourceAndPublishesNoCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), output = root.appendingPathComponent("text/model.safetensors"), original = try fixture()
        try original.write(to: source)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await TextModelWeights.prepareAsync(source: source, destination: output, expectedPayloadBytes: 8)
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
    func testTextProjectionPreservesExactTensorBytesWithoutVisionAndReusesCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.safetensors"), output = root.appendingPathComponent("text/model.safetensors")
        let original = try fixture()
        try original.write(to: source)
        let receipt = try TextModelWeights.prepare(source: source, destination: output, expectedPayloadBytes: 8)
        let saved = try Data(contentsOf: output), length = saved.prefix(8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian }
        let header = try JSONValue.parse(String(decoding: saved[8..<(8 + Int(length))], as: UTF8.self))
        XCTAssertNil(header["vision_tower.weight"])
        XCTAssertEqual(header["language_model.first"]?["data_offsets"], .array([.number(0), .number(4)]))
        XCTAssertEqual(header["language_model.last"]?["data_offsets"], .array([.number(4), .number(8)]))
        XCTAssertEqual(Array(saved.suffix(8)), [1,2,3,4,9,10,11,12])
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try TextModelWeights.prepare(source: source, destination: output, expectedPayloadBytes: 8), receipt)
        XCTAssertEqual(try Data(contentsOf: output), saved)
    }
    func testInvalidOrMismatchedCheckpointDoesNotProduceAUsableCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), output = root.appendingPathComponent("text/weights")
        try fixture().write(to: source)
        XCTAssertThrowsError(try TextModelWeights.prepare(source: source, destination: output, expectedPayloadBytes: 9))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        try Data([1,2]).write(to: source)
        XCTAssertThrowsError(try TextModelWeights.prepare(source: source, destination: output, expectedPayloadBytes: 8))
    }
    private func fixture() throws -> Data {
        func tensor(_ start: Int, _ end: Int) -> JSONValue { .object(["dtype": .string("U32"), "shape": .array([.number(1)]), "data_offsets": .array([.number(Double(start)), .number(Double(end))])]) }
        var header = Data(try JSONValue.object(["language_model.first": tensor(0,4), "vision_tower.weight": tensor(4,8), "language_model.last": tensor(8,12)]).jsonString().utf8)
        while header.count % 8 != 0 { header.append(32) }
        var length = UInt64(header.count).littleEndian
        return withUnsafeBytes(of: &length) { Data($0) } + header + Data(1...12)
    }
}
