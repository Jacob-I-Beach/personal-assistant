import Foundation
import Dispatch

/// A byte-preserving, bounded-memory projection of a verified multimodal
/// checkpoint. The source is never changed. This avoids an eager loader briefly
/// materializing the vision tower even when its model sanitizer discards it.
public enum TextModelWeights {
    public struct Receipt: Codable, Equatable, Sendable {
        public let sourceBytes: Int64
        public let sourceModified: Date
        public let sourceHeader: Data
        public let payloadBytes: Int64
        public let outputBytes: Int64
        public let tensorCount: Int
    }
    public static func prepareAsync(source: URL, destination: URL, expectedPayloadBytes: Int64) async throws -> Receipt {
        let cancellation = WeightPreparationCancellation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let value = try prepare(source: source, destination: destination, expectedPayloadBytes: expectedPayloadBytes,
                            checkCancellation: { try cancellation.check() })
                        continuation.resume(returning: value)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { cancellation.cancel() })
    }
    public static func prepare(source: URL, destination: URL, expectedPayloadBytes: Int64,
                               checkCancellation: @Sendable () throws -> Void = { try Task.checkCancellation() }) throws -> Receipt {
        try checkCancellation()
        let root = destination.deletingLastPathComponent().standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard source.standardizedFileURL != destination.standardizedFileURL,
              destination.resolvingSymlinksInPath().deletingLastPathComponent() == root.resolvingSymlinksInPath() else {
            throw AssistantError.provider("Invalid text-runtime cache location.")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        guard let sourceBytes = (attributes[.size] as? NSNumber)?.int64Value, let modified = attributes[.modificationDate] as? Date else {
            throw AssistantError.provider("The downloaded model's size could not be read.")
        }
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        let lengthData = try read(reader, count: 8)
        let length = lengthData.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian }
        guard length > 0, length <= 2 * 1024 * 1024, Int64(length) + 8 <= sourceBytes else { throw invalid() }
        let headerData = try read(reader, count: Int(length))
        guard let header = try JSONValue.parse(String(decoding: headerData, as: UTF8.self)).objectValue else { throw invalid() }
        let payloadStart = Int64(length) + 8
        var tensors: [(name: String, value: [String: JSONValue], start: Int64, size: Int64)] = []
        for (name, value) in header where name != "__metadata__" {
            guard name.hasPrefix("language_model.") || name.hasPrefix("vision_tower."),
                  var tensor = value.objectValue, let offsets = tensor["data_offsets"]?.arrayValue, offsets.count == 2,
                  let first = offsets[0].numberValue, let last = offsets[1].numberValue,
                  first.isFinite, last.isFinite, first.rounded() == first, last.rounded() == last,
                  first >= 0, last >= first, last <= Double(sourceBytes - payloadStart),
                  tensor["dtype"]?.stringValue != nil, tensor["shape"]?.arrayValue != nil else { throw invalid() }
            if name.hasPrefix("language_model.") {
                tensor.removeValue(forKey: "data_offsets")
                tensors.append((name, tensor, Int64(first), Int64(last - first)))
            }
        }
        tensors.sort { $0.start < $1.start }
        let payloadBytes = tensors.reduce(Int64(0)) { $0 + $1.size }
        guard !tensors.isEmpty, payloadBytes == expectedPayloadBytes,
              zip(tensors, tensors.dropFirst()).allSatisfy({ $0.0.start + $0.0.size <= $0.1.start }) else { throw invalid() }
        let receiptURL = destination.appendingPathExtension("json")
        if let data = try? Data(contentsOf: receiptURL), let saved = try? JSONDecoder().decode(Receipt.self, from: data),
           saved.sourceBytes == sourceBytes, saved.sourceModified == modified, saved.sourceHeader == headerData,
           saved.payloadBytes == payloadBytes,
           (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value == saved.outputBytes {
            return saved
        }
        var outHeader: [String: JSONValue] = [:], offset: Int64 = 0
        if let metadata = header["__metadata__"] { outHeader["__metadata__"] = metadata }
        for tensor in tensors {
            var value = tensor.value
            value["data_offsets"] = .array([.number(Double(offset)), .number(Double(offset + tensor.size))])
            outHeader[tensor.name] = .object(value); offset += tensor.size
        }
        var encoded = Data(try JSONValue.object(outHeader).jsonString().utf8)
        while encoded.count % 8 != 0 { encoded.append(32) }
        if let free = (try? FileManager.default.attributesOfFileSystem(forPath: root.path)[.systemFreeSize] as? NSNumber)?.int64Value,
           free < payloadBytes + Int64(encoded.count) + 64 * 1024 * 1024 {
            throw AssistantError.provider("Preparing the text runtime needs about \(ByteCountFormatter.string(fromByteCount: payloadBytes, countStyle: .file)) of free storage. The original download is kept.")
        }
        let temporary = root.appendingPathComponent(UUID().uuidString + ".partial")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else { throw invalid() }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let writer = try FileHandle(forWritingTo: temporary)
        defer { try? writer.close() }
        var outLength = UInt64(encoded.count).littleEndian
        try writer.write(contentsOf: withUnsafeBytes(of: &outLength) { Data($0) })
        try writer.write(contentsOf: encoded)
        for tensor in tensors {
            try checkCancellation()
            try reader.seek(toOffset: UInt64(payloadStart + tensor.start))
            var remaining = tensor.size
            while remaining > 0 {
                try checkCancellation()
                let count = Int(min(2 * 1024 * 1024, remaining))
                #if canImport(ObjectiveC)
                // FileHandle bridges Foundation objects on Apple platforms.
                // Drain each chunk rather than retaining temporary objects for
                // the full multi-gigabyte copy on this dispatch work item.
                try autoreleasepool { try writer.write(contentsOf: read(reader, count: count)) }
                #else
                try writer.write(contentsOf: read(reader, count: count))
                #endif
                remaining -= Int64(count)
            }
        }
        try writer.synchronize(); try writer.close()
        try checkCancellation()
        let current = try FileManager.default.attributesOfItem(atPath: source.path)
        guard current[.modificationDate] as? Date == modified, (current[.size] as? NSNumber)?.int64Value == sourceBytes else { throw invalid() }
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temporary, to: destination)
        let result = Receipt(sourceBytes: sourceBytes, sourceModified: modified, sourceHeader: headerData,
            payloadBytes: payloadBytes, outputBytes: Int64(encoded.count + 8) + payloadBytes, tensorCount: tensors.count)
        try JSONEncoder().encode(result).write(to: receiptURL, options: .atomic)
        return result
    }
    private static func read(_ file: FileHandle, count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            guard let chunk = try file.read(upToCount: count - data.count), !chunk.isEmpty else { throw invalid() }
            data.append(chunk)
        }
        return data
    }
    private static func invalid() -> AssistantError { .provider("The model's text-runtime cache could not be prepared from its verified checkpoint. The original download is kept.") }
}

private final class WeightPreparationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    func check() throws { if lock.withLock({ cancelled }) { throw CancellationError() } }
}
