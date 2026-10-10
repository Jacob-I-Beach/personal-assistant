import XCTest
@testable import AssistantCore

final class SandboxTests: XCTestCase, @unchecked Sendable {
    func testDeviceReportedArrayReturnRetainsTheComputedTotal() async throws {
        // Exact source shown in Jacob's failed 0.2 Apple-model tool request.
        let result = try await JavaScriptSandbox().run(code: """
        function add_array(values) {
          let total = values[0] + values[1] + values[2];
          return [values[0], values[1], values[2], total];
        }
        const result = add_array([18.5, 27.25, 14.75]);
        return result;
        """)
        XCTAssertEqual(result.result, .array([.number(18.5), .number(27.25), .number(14.75), .number(60.5)]))
        XCTAssertTrue(result.files.isEmpty)
    }

    func testOrdinaryJSONReturnsDoNotRequireAProtocolEnvelope() async throws {
        let sandbox = JavaScriptSandbox()
        for (code, expected) in [
            ("return 3 + 4;", JSONValue.number(7)),
            ("return null;", .null),
            ("return 'done';", .string("done")),
            ("return {sum: 7, rows: [3,4]};", .object(["sum": .number(7), "rows": .array([.number(3), .number(4)])]))
        ] {
            let result = try await sandbox.run(code: code)
            XCTAssertEqual(result.result, expected); XCTAssertTrue(result.files.isEmpty)
        }
    }
    func testTransformsSelectedInputAndProducesAnArtifact() async throws {
        let result = try await JavaScriptSandbox().run(code: """
        const rows = input.values.map(x => x * 2);
        return {result: {sum: rows.reduce((a, b) => a + b, 0)}, files: {'result.csv': 'value\\n' + rows.join('\\n')}};
        """, input: .object(["values": .array([.number(2), .number(3), .number(5)])]))
        XCTAssertEqual(result.result["sum"]?.numberValue, 20)
        XCTAssertEqual(result.files["result.csv"], "value\n4\n6\n10")
    }

    func testNoNetworkFilesystemProcessOrBlockingAtomicsBridge() async throws {
        let output = try await JavaScriptSandbox().run(code: """
        return {result: ['fetch','XMLHttpRequest','require','process','std','os','Worker','Atomics','SharedArrayBuffer'].map(k => typeof globalThis[k])};
        """)
        XCTAssertEqual(output.result, .array(Array(repeating: .string("undefined"), count: 9)))
    }

    func testInfiniteLoopTerminatesAndNextRunWorks() async throws {
        let sandbox = JavaScriptSandbox()
        let start = ContinuousClock.now
        do {
            _ = try await sandbox.run(code: "while (true) {}", timeoutMilliseconds: 50)
            XCTFail("Infinite script returned")
        } catch { XCTAssertEqual(error as? ScriptError, .stopped) }
        XCTAssertLessThan(start.duration(to: .now), .seconds(2))
        let next = try await sandbox.run(code: "return {result: 7};")
        XCTAssertEqual(next.result, .number(7))
    }

    func testCancellationActuallyStopsTheInterpreter() async throws {
        let sandbox = JavaScriptSandbox()
        let task = Task { try await sandbox.run(code: "while (true) {}", timeoutMilliseconds: 10_000) }
        try await Task.sleep(for: .milliseconds(50))
        let start = ContinuousClock.now
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled script returned") }
        catch { XCTAssertTrue(error is CancellationError || error as? ScriptError == .stopped) }
        XCTAssertLessThan(start.duration(to: .now), .seconds(2))
    }

    func testMemoryOutputRecursionAndPathLimitsRecover() async throws {
        let sandbox = JavaScriptSandbox()
        for code in [
            "const a = new ArrayBuffer(128 * 1024 * 1024); return {result: a.byteLength};",
            "return {result: 'a'.repeat(1100000)};",
            "function f(){return f()} return {result:f()};",
            "return {result: 1, files: {'../outside.txt':'no'}};",
            "return {result: 1, files: {'CON.txt':'no'}};"
        ] {
            do { _ = try await sandbox.run(code: code); XCTFail("Unsafe or excessive output succeeded") }
            catch { XCTAssertTrue(error is ScriptError) }
        }
        let next = try await sandbox.run(code: "return {result: typeof a};")
        XCTAssertEqual(next.result, .string("undefined"))
    }
    func testInvalidNumericAndUndefinedResultsAreNotSilentlyConvertedToNull() async throws {
        let sandbox = JavaScriptSandbox()
        for code in ["return {result: NaN};", "return {result: Infinity};", "return {result: undefined};", "return {result: () => 1};", "return (async () => ({result: 1}))();", "return {result: Promise.resolve(1)};"] {
            do { _ = try await sandbox.run(code: code); XCTFail("Invalid output was accepted") }
            catch { XCTAssertTrue(error is ScriptError) }
        }
    }
}
