import Foundation
import XCTest
@testable import AssistantCore

final class ReplyBudget131Tests: XCTestCase {
    func testReported855KSelectionKeepsReplyRoomAndSeparateCompactionCapacity() throws {
        let plan = ModelContextBudget(model: "gpt-6.1-sol", advertisedMaximumWindow: 872_000, requestedInputTokens: 855_616)
        XCTAssertEqual(plan.selectedInputTokens, 855_616)
        XCTAssertEqual(plan.activeInputTokens, 598_931)
        XCTAssertEqual(plan.compactionReserveTokens, 256_685)
        XCTAssertEqual(plan.outputReserve, 128_000)
        XCTAssertEqual(plan.compactionInputTokens, 855_616)
        XCTAssertEqual(plan.compactionOutputReserve, 16_384)
        for wire in [NetworkProtocol.responses, .chatCompletions] {
            let backend = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "gpt-6.1-sol", wireProtocol: wire, contextBudget: plan)
            let key = wire == .responses ? "max_output_tokens" : "max_tokens"
            var request = ModelRequest(instructions: "Synthetic", messages: [], tools: [])
            let normal = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(backend.makeRequest(request).httpBody))
            XCTAssertEqual(normal[key], .number(128_000))
            request.isCompaction = true
            let compact = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(backend.makeRequest(request).httpBody))
            XCTAssertEqual(compact[key], .number(16_384))
        }
        let account = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "gpt-6.1-sol", wireProtocol: .responses, credential: "synthetic", chatGPTAccountID: "synthetic-account", contextBudget: plan)
        for compact in [false, true] {
            var request = ModelRequest(instructions: "Synthetic", messages: [], tools: []); request.isCompaction = compact
            let body = try account.responsesBody(request)
            XCTAssertNil(body["max_output_tokens"], "The ChatGPT-plan route does not accept an app-imposed output cap")
        }
    }
    func testBudgetModesRemainWithinCapacityAcrossPresetsAndSmallConnections() throws {
        for model in ["gpt-6.1-sol", "unknown"] {
            for window in [8192, 32768, 200_000, 872_000, 1_050_000] {
                let maximum = ModelContextBudget(model: model, advertisedMaximumWindow: window)
                for choice in maximum.presets {
                    let plan = ModelContextBudget(model: model, advertisedMaximumWindow: window, requestedInputTokens: choice)
                    XCTAssertEqual(plan.activeInputTokens + plan.compactionReserveTokens, plan.selectedInputTokens)
                    XCTAssertLessThanOrEqual(plan.activeInputTokens + plan.outputReserve, window)
                    XCTAssertLessThanOrEqual(plan.compactionInputTokens + plan.compactionOutputReserve, window)
                    XCTAssertGreaterThan(plan.compactionOutputReserve, 0)
                    XCTAssertGreaterThanOrEqual(plan.outputReserve, plan.compactionOutputReserve)
                }
            }
        }
        let large = ModelContextBudget(model: "gpt-6.1-sol", requestedInputTokens: 1_000_000)
        let backend = try NetworkModelBackend(baseURL: URL(string: "https://api.openai.com/v1")!, model: "gpt-6.1-sol", wireProtocol: .responses, contextBudget: large)
        XCTAssertEqual(large.compactionInputTokens, 922_000)
        XCTAssertEqual(backend.checkpointInputByteBudget, 2_766_000)
        XCTAssertLessThan(backend.checkpointInputByteBudget, backend.contextLimits.maximumTextBytes)
    }
}
