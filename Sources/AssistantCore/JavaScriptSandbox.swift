import CQuickJS
import Foundation

public struct ScriptResult: Codable, Equatable, Sendable {
    public var result: JSONValue
    public var files: [String: String]
    public var elapsedMilliseconds: Int
}

public enum ScriptError: Error, LocalizedError, Equatable, Sendable {
    case invalidInput, stopped, memoryLimit, outputLimit, invalidOutput, script(String)
    public var errorDescription: String? {
        switch self {
        case .invalidInput: "The script or its selected input exceeds the execution limits."
        case .stopped: "Script execution stopped because it was cancelled or reached its time limit."
        case .memoryLimit: "The script exceeded the available execution memory."
        case .outputLimit: "The script produced too much output."
        case .invalidOutput: "Return a JSON-compatible value, or {result: value, files: {'name.csv': 'text'}} to save text files. Files need valid filenames and string contents."
        case .script(let message): "Script error: \(message)"
        }
    }
}

/// Each run gets a fresh QuickJS realm. Only JSON enters and leaves; no host capabilities are installed.
public actor JavaScriptSandbox {
    private var busy = false
    public init() {}

    public func run(code: String, input: JSONValue = .null, timeoutMilliseconds: Int = 3_000) async throws -> ScriptResult {
        guard !busy else { throw AssistantError.busy }
        guard code.utf8.count <= 128 * 1024, !code.utf8.contains(0),
              (1...10_000).contains(timeoutMilliseconds) else { throw ScriptError.invalidInput }
        let inputData = try JSONEncoder().encode(input)
        guard inputData.count <= 2 * 1024 * 1024 else { throw ScriptError.invalidInput }
        busy = true
        defer { busy = false }
        let control = try ScriptControl()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let worker = Task.detached(priority: .userInitiated) {
                try Self.execute(code: code, input: inputData, timeout: timeoutMilliseconds, control: control)
            }
            let value = try await worker.value
            try Task.checkCancellation()
            return value
        } onCancel: { control.cancel() }
    }

    private static func execute(code: String, input: Data, timeout: Int, control: ScriptControl) throws -> ScriptResult {
        let source = "(function(){\"use strict\";\n" + code + "\n})()"
        let started = ContinuousClock.now
        var bytes: UnsafeMutablePointer<CChar>?
        var length = 0
        let status = source.withCString { sourcePointer in
            String(decoding: input, as: UTF8.self).withCString { inputPointer in
                pa_js_run(control.raw, sourcePointer, source.utf8.count,
                          inputPointer, input.count,
                          64 * 1024 * 1024, UInt64(timeout), 1024 * 1024, &bytes, &length)
            }
        }
        defer { pa_js_string_free(bytes) }
        let data = bytes.map { Data(bytes: $0, count: length) } ?? Data()
        switch status {
        case 0: break
        case 2: throw ScriptError.stopped
        case 3: throw ScriptError.outputLimit
        case 4: throw ScriptError.memoryLimit
        default: throw ScriptError.script(String(decoding: data, as: UTF8.self))
        }
        let returned = try JSONDecoder().decode(JSONValue.self, from: data)
        // Ordinary JavaScript return values are useful results. Only the explicit
        // result/files envelope opts into the file-output protocol.
        let object = returned.objectValue
        let isEnvelope = object?["result"] != nil && Set(object!.keys).isSubset(of: ["result", "files"])
        let result = isEnvelope ? object!["result"]! : returned
        var files: [String: String] = [:]
        if isEnvelope, let outputFiles = object?["files"] {
            guard let values = outputFiles.objectValue, values.count <= 12 else { throw ScriptError.invalidOutput }
            for (name, value) in values {
                guard validFilename(name), let content = value.stringValue else { throw ScriptError.invalidOutput }
                files[name] = content
            }
        }
        let elapsed = started.duration(to: .now).components
        return ScriptResult(result: result, files: files,
                            elapsedMilliseconds: Int(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000))
    }

    public nonisolated static func validFilename(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 100, name.first != ".",
              name.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil,
              !name.contains("..") else { return false }
        let stem = name.split(separator: ".").first!.uppercased()
        return !(["CON", "PRN", "AUX", "NUL"] + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] }).contains(stem)
    }
}

private final class ScriptControl: @unchecked Sendable {
    let raw: OpaquePointer
    init() throws {
        guard let value = pa_js_control_create() else { throw ScriptError.memoryLimit }
        raw = value
    }
    func cancel() { pa_js_control_cancel(raw) }
    deinit { pa_js_control_free(raw) }
}
