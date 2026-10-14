import XCTest
@testable import AssistantCore

final class AuditRegressionTests: XCTestCase, @unchecked Sendable {
    func testUnsafeIntegerArgumentsAreRejectedBeforeActualDispatch() async throws {
        let schema: JSONValue = .object(["type": .string("integer"), "minimum": .number(0)])
        for value in [JSONValue.number(1e30), .string("1e30"), .number(Double(Int.max)), .number(9_007_199_254_740_992), .number(1.5), .number(-1)] {
            XCTAssertThrowsError(try ToolArguments.normalize(value, schema: schema))
        }
        for value in [0.0, 1, 9_007_199_254_740_991] { XCTAssertEqual(try ToolArguments.integer(ToolArguments.normalize(.number(value), schema: schema)), Int(exactly: value)) }
        let store = try makeTestStore(), chat = Conversation()
        try await store.save(chat)
        let tools = AssistantTools(store: store, conversationID: chat.id, captureIDs: [], sandbox: JavaScriptSandbox())
        let call = ToolCall(id: "bad-revision", name: "update_project", arguments: .object([
            "title": .string("Example"), "goal": .string("Example"), "status": .string("active"), "decisions": .array([]), "open_questions": .array([]), "output_ids": .array([]), "expected_revision": .number(1e30)]))
        let result = try await tools.execute(call)
        XCTAssertFalse(result.succeeded)
        let projects = try await store.projectWorkspaces(); XCTAssertTrue(projects.isEmpty)
    }

    func testDerivedPlansRetainProtectionAcrossPersistenceAndStaleCheckpoints() async throws {
        let store = try makeTestStore(); var chat = Conversation()
        let user = Message(role: .user, text: "Make a plan")
        chat.messages = [user]; try await store.save(chat)
        let work = WorkTurn(id: user.id, conversationID: chat.id, userMessageID: user.id, backendID: "local", goal: user.text)
        try await store.saveWorkTurn(work)
        let tools = AssistantTools(store: store, conversationID: chat.id, captureIDs: [], sandbox: JavaScriptSandbox(), artifactLocalOnly: true, operationScope: work.id)
        let steps: JSONValue = .array([.object(["title": .string("private-canary"), "status": .string("pending")])])
        _ = try await tools.execute(.init(id: "plan", name: "update_plan", arguments: .object(["steps_json": .string(try steps.jsonString())])))
        var stale = work; stale.plan = steps.arrayValue!; try await store.saveWorkTurn(stale)
        let reopened = try LocalStore(root: store.root)
        let evidence = try await reopened.workEvidence(work.id, conversationID: chat.id, remote: false, workspaceEnabled: false)
        XCTAssertTrue(try evidence.jsonString().contains("private-canary"))
        do { _ = try await reopened.workEvidence(work.id, conversationID: chat.id, remote: true, workspaceEnabled: false); XCTFail("Protected plan escaped") } catch { }
        let publicWork = WorkTurn(id: UUID(), conversationID: chat.id, userMessageID: user.id, backendID: "connected", goal: "Public")
        try await store.saveWorkTurn(publicWork)
        _ = try await store.workEvidence(publicWork.id, conversationID: chat.id, remote: true, workspaceEnabled: false)
    }

    func testWorkspaceAuthorityAndAllOptionalReceiptFieldsSurviveReplay() throws {
        let workspace = UUID(), turn = UUID()
        var answer = Message(role: .user, text: "Yes"); answer.replyToTaskID = turn
        var expected = ToolResult(callID: "connect", name: "connect_workspace", succeeded: true, output: .object(["status": .string("connected")]))
        expected.authorizedWorkspaceID = workspace; expected.containsHealthData = true
        expected.containsLocalOnlyContext = true; expected.authorizedHealthDestination = "synthetic"
        expected.userResponse = answer
        let raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(expected))
        var transcript = CompanionTranscript(jobID: UUID(), providerID: "computer", health: false)
        let received = try transcript.apply(.object(["seq": .number(1), "type": .string("executed_tool"), "call": .object(["id": .string("connect"), "name": .string("connect_workspace"), "arguments": .object([:])]), "result": raw]))?.1
        XCTAssertEqual(received?.authorizedWorkspaceID, workspace)
        XCTAssertEqual(received?.containsHealthData, true); XCTAssertEqual(received?.containsLocalOnlyContext, true)
        XCTAssertEqual(received?.authorizedHealthDestination, "synthetic"); XCTAssertEqual(received?.userResponse, answer)
        XCTAssertEqual(received?.completedAt, expected.completedAt)
        XCTAssertTrue(transcript.messages.first(where: { $0.role == .tool })?.containsLocalOnlyContext == true)
    }

    func testLegacyAndNewlyHealthDerivedWorkCannotBeReadAsPublicContext() async throws {
        let store = try makeTestStore(); var chat = Conversation()
        let user = Message(role: .user, text: "Public request"); chat.messages = [user]; try await store.save(chat)
        let work = WorkTurn(id: user.id, conversationID: chat.id, userMessageID: user.id, backendID: "local", goal: user.text)
        try await store.saveWorkTurn(work)
        try await store.classifyWork(work.id, localOnly: false, health: true)
        try await store.finishWork(work.id, phase: .interrupted, reason: "health-canary")
        do { _ = try await store.workEvidence(work.id, conversationID: chat.id, remote: true, workspaceEnabled: false); XCTFail("Health context escaped") } catch { }
        try await store.auditSQL("UPDATE work_turns SET payload=CAST(json_remove(CAST(payload AS TEXT),'$.containsLocalOnlyContext','$.containsHealthData') AS BLOB)")
        let legacy = try await store.workTurn(work.id); XCTAssertNil(legacy?.containsLocalOnlyContext)
        do { _ = try await store.workEvidence(work.id, conversationID: chat.id, remote: true, workspaceEnabled: false); XCTFail("Unclassified legacy context escaped") } catch { }
        let local = try await store.workEvidence(work.id, conversationID: chat.id, remote: false, workspaceEnabled: false)
        XCTAssertEqual(local["reason"], .string("health-canary"))
    }

    func testNativeCallbackCannotExecuteTheTwentyFifthEffectAcrossRollovers() async throws {
        let store = try makeTestStore(), effects = AuditEffectCounter(), backend = AuditNativeBackend()
        let definition = ToolDefinition(name: "audit_effect", description: "Synthetic saved effect", parameters: .object(["type": .string("object"), "properties": .object([:]), "required": .array([]), "additionalProperties": .bool(false)]))
        let chat = Conversation(); try await store.save(chat)
        do {
            for try await _ in AssistantEngine(store: store).respond(conversation: chat, text: "Exercise native callbacks", captureIDs: [], backend: backend,
                additionalTools: [definition], additionalExecutor: { call in await effects.record(); return ToolResult(callID: call.id, name: call.name, succeeded: true, output: .object(["status": .string("saved")])) }) { }
            XCTFail("The per-run admission limit must stop the next effect")
        } catch AssistantError.workBudgetReached { }
        let count = await effects.count; XCTAssertEqual(count, 24)
        let saved = try await store.loadConversation(chat.id)
        XCTAssertEqual(saved.messages.filter { $0.role == .tool }.count, 24)
    }

    func testRecoveryIncludesOperationsBeyondFirstTwentyFourWithoutExecutingAgain() async throws {
        let store = try makeTestStore(); var chat = Conversation()
        let user = Message(role: .user, text: "Recover this work"); chat.messages = [user]
        try await store.save(chat)
        var work = WorkTurn(id: user.id, conversationID: chat.id, userMessageID: user.id, backendID: "audit-recovery", goal: user.text)
        work.phase = .interrupted; try await store.saveWorkTurn(work)
        for index in 0..<31 {
            let call = ToolCall(id: "saved-\(index)", name: "audit_effect", arguments: .object([:]))
            _ = try await store.beginToolOperation(call, conversationID: chat.id, turnID: work.id)
            try await store.finishToolOperation(call, turnID: work.id, result: ToolResult(callID: call.id, name: call.name, succeeded: true, output: .object(["status": .string("saved")])))
        }
        for try await _ in AssistantEngine(store: store).resume(conversation: chat, turnID: work.id, backend: AuditRecoveryBackend()) { }
        let saved = try await store.loadConversation(chat.id)
        XCTAssertEqual(saved.messages.filter { $0.role == .tool }.count, 31)
        XCTAssertEqual(Set(saved.messages.compactMap(\.toolCallID)).count, 31)
    }

    func testSurfaceSaveRollbackAndDeletionDoNotLeaveLiveHistoryPayloads() async throws {
        let store = try makeTestStore(); var chat = Conversation()
        var invocation = Message(role: .assistant, text: "Created")
        invocation.toolCalls = [.init(id: "surface", name: "present_surface", arguments: .object([:]))]
        chat.messages = [invocation]; try await store.save(chat)
        let original = try WorkSurface(conversationID: chat.id, sourceCallID: "surface", spec: surfaceSpec("Original"), localOnly: false, health: false)
        try await store.saveSurface(original)
        let replacement = try WorkSurface(conversationID: chat.id, sourceCallID: "update", spec: surfaceSpec("Updated"), localOnly: false, health: false)
        try await store.auditSQL("CREATE TEMP TRIGGER reject_surface BEFORE UPDATE ON work_surfaces BEGIN SELECT RAISE(FAIL,'synthetic failure'); END")
        do { _ = try await store.reviseSurface(id: original.id, conversationID: chat.id, expectedRevision: 1, replacement: replacement); XCTFail("Injected update failure") } catch { }
        let failedHistory = try await store.auditCount("surface_history"); XCTAssertEqual(failedHistory, 0)
        try await store.auditSQL("DROP TRIGGER reject_surface")
        _ = try await store.reviseSurface(id: original.id, conversationID: chat.id, expectedRevision: 1, replacement: replacement)
        let artifact = ArtifactRecord(conversationID: chat.id, filename: "example.txt", content: "Original")
        try await store.saveArtifact(artifact)
        _ = try await store.reviseArtifact(id: artifact.id, expectedRevision: 1, content: "New revision")
        try await store.removeConversation(chat.id)
        let surfaceCount = try await store.auditCount("surface_history"), artifactCount = try await store.auditCount("artifact_history")
        XCTAssertEqual(surfaceCount, 0); XCTAssertEqual(artifactCount, 0)
    }

    func testEditingAwayLaterRevisionsExcludesDerivedContextAndKeepsActualWork() async throws {
        let store = try makeTestStore(); var chat = Conversation()
        var a = Message(role: .user, text: "Create"), b = Message(role: .user, text: "Removed assumption")
        a.createdAt = Date(timeIntervalSinceNow: -200); b.createdAt = Date(timeIntervalSinceNow: -50)
        var create = Message(role: .assistant, text: "Created"), revise = Message(role: .assistant, text: "Revised")
        create.toolCalls = [.init(id: "create-a", name: "present_surface", arguments: .object([:]))]
        revise.toolCalls = [.init(id: "revise-b", name: "update_artifact", arguments: .object([:]))]
        chat.messages = [a, create, b, revise]; try await store.save(chat)
        var artifact = ArtifactRecord(conversationID: chat.id, filename: "kept.txt", content: "A", sourceCallID: "create-a"); artifact.createdAt = a.createdAt
        try await store.saveArtifact(artifact)
        _ = try await store.reviseArtifact(id: artifact.id, expectedRevision: 1, content: "removed-canary", sourceCallID: "revise-b")
        var surface = try WorkSurface(conversationID: chat.id, sourceCallID: "create-a", spec: surfaceSpec("A"), localOnly: false, health: false)
        surface.createdAt = a.createdAt; surface.updatedAt = a.createdAt; try await store.saveSurface(surface)
        _ = try await store.reviseSurface(id: surface.id, conversationID: chat.id, expectedRevision: 1, replacement: WorkSurface(conversationID: chat.id, sourceCallID: "revise-b", spec: surfaceSpec("removed-canary"), localOnly: false, health: false))
        let project = ProjectWorkspace(id: chat.id, sourceConversationID: chat.id, title: "Project", goal: "removed-canary", status: "active", decisions: ["removed-canary"], questions: [], outputIDs: [], revision: 1, updatedAt: Date(), containsLocalOnlyContext: false, containsHealthData: false)
        try await store.saveProjectWorkspace(project, expectedRevision: 0)
        let branch = try await store.prepareMessageEdit(in: chat, messageID: b.id)
        XCTAssertTrue(branch.excludedArtifactIDs.contains(artifact.id)); XCTAssertTrue(branch.excludedSurfaceIDs.contains(surface.id))
        let visible = try await store.readableArtifacts(conversationID: chat.id, workspace: true, remote: false)
        XCTAssertFalse(visible.contains { $0.id == artifact.id })
        let contextualProject = try await store.projectWorkspace(conversationID: chat.id, remote: false)
        XCTAssertEqual(contextualProject?.needsContextRebuild, true)
        XCTAssertFalse(try contextualProject!.summary.jsonString().contains("removed-canary"))
        let actual = try await store.artifacts(conversationID: chat.id)
        XCTAssertEqual(actual.first?.content, "removed-canary", "Editing chat must not roll back the saved document.")
    }
    private func surfaceSpec(_ title: String) -> JSONValue { .object(["kind": .string("checklist"), "title": .string(title), "data": .array([.object(["id": .string("one"), "label": .string("Example"), "checked": .bool(false)])])]) }
}

private actor AuditEffectCounter { var count = 0; func record() { count += 1 } }
private actor AuditNativeBackend: ModelBackend {
    nonisolated let id = "audit-native"
    nonisolated let networkDestination: String? = nil
    private var round = 0
    nonisolated func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in
            let task = Task {
                do {
                    let start = await self.nextRound()
                    for index in start..<(start + 12) {
                        let call = ToolCall(id: "effect-\(index)", name: "audit_effect", arguments: .object([:]))
                        let result = try await request.toolExecutor!(call)
                        output.yield(.executedTool(call, result))
                    }
                    output.yield(.contextWindowRollover); output.finish()
                } catch { output.finish(throwing: error) }
            }
            output.onTermination = { @Sendable _ in task.cancel() }
        }
    }
    private func nextRound() -> Int { defer { round += 1 }; return round * 12 }
}
private struct AuditRecoveryBackend: ModelBackend {
    let id = "audit-recovery"
    var networkDestination: String? { nil }
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { $0.yield(.textDelta("Recovered the saved receipts.")); $0.yield(.completed); $0.finish() }
    }
}
private extension LocalStore {
    func auditSQL(_ sql: String) throws { try database.execute(sql) }
    func auditCount(_ table: String) throws -> Int { guard !(try database.execute("SELECT name FROM sqlite_master WHERE name=?", [.text(table)])).isEmpty else { return 0 }; return Int(try database.execute("SELECT COUNT(*) FROM \(table)").first![0].number!) }
}
