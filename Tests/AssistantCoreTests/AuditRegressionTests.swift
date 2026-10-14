import XCTest
@testable import AssistantCore

final class AuditRegressionTests: XCTestCase, @unchecked Sendable {
    func testIdleMeansTheInterruptionCheckpointHasAlreadyFinished() async throws {
        let store = try makeTestStore(), engine = AssistantEngine(store: store)
        var observedRunning = 0
        for _ in 0..<30 {
            let chat = Conversation(), backend = AuditFailureBackend(); try await store.save(chat)
            let consumer = Task { do { for try await _ in engine.respond(conversation: chat, text: "Fail deterministically", captureIDs: [], backend: backend) { } } catch { } }
            await backend.waitForStart()
            let idle = Task { await engine.waitUntilIdle() }
            await backend.fail()
            await idle.value
            let saved = try await store.loadConversation(chat.id)
            let work = try await store.workTurn(saved.messages.first(where: \.isRequest)!.id)
            if work?.phase == .running { observedRunning += 1 }
            await consumer.value
        }
        XCTAssertEqual(observedRunning, 0, "A resumed task must not race the previous run's interruption persistence.")
    }

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

    func testProjectReceiptCarriesProtectionInheritedFromItsOutput() async throws {
        let store = try makeTestStore(), chat = Conversation(); try await store.save(chat)
        var artifact = ArtifactRecord(conversationID: chat.id, filename: "private.txt", content: "private canary")
        artifact.containsLocalOnlyContext = true; artifact.containsHealthData = true
        try await store.saveArtifact(artifact)
        let call = ToolCall(id: "project", name: "update_project", arguments: .object([
            "title": .string("Protected project"), "goal": .string("Maintain selected work"), "status": .string("active"),
            "decisions": .array([]), "open_questions": .array([]), "output_ids": .array([.string(artifact.id.uuidString)]), "expected_revision": .number(0)]))
        let receipt = try await ProjectTools.execute(call, store: store, conversationID: chat.id, workspace: true, remote: false, localOnly: false, health: false)
        XCTAssertTrue(receipt.containsLocalOnlyContext == true); XCTAssertTrue(receipt.containsHealthData == true)
        let remote = try await store.projectWorkspace(conversationID: chat.id, remote: true); XCTAssertNil(remote)
        var guessed = call; guessed.id = "guess"; guessed.arguments = .object([
            "title": .string("Public overwrite"), "goal": .string("Must not replace a private project"), "status": .string("active"),
            "decisions": .array([]), "open_questions": .array([]), "output_ids": .array([]), "expected_revision": .number(1)])
        do { _ = try await ProjectTools.execute(guessed, store: store, conversationID: chat.id, workspace: true, remote: true, localOnly: false, health: false); XCTFail("A model without read access must not overwrite a protected project by guessing its revision") } catch { }
        let retained = try await store.projectWorkspace(conversationID: chat.id, remote: false)
        XCTAssertEqual(retained?.title, "Protected project"); XCTAssertEqual(retained?.revision, 1)
        var staleFlags = retained!; staleFlags.revision = 2; staleFlags.containsLocalOnlyContext = false; staleFlags.containsHealthData = false
        try await store.saveProjectWorkspace(staleFlags, expectedRevision: 1)
        let stillPrivate = try await store.projectWorkspace(conversationID: chat.id, remote: true); XCTAssertNil(stillPrivate)
    }

    func testConcurrentAdmissionsStopBeforeEffectsAndRejectRepeatedIdentities() async throws {
        let admission = ToolAdmission(previous: []), effects = AuditEffectCounter()
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<60 { group.addTask {
                do { try await admission.admit(.init(id: "concurrent-\(index)", name: "effect", arguments: .object([:]))); await effects.record() } catch { }
            } }
        }
        let count = await effects.count; XCTAssertEqual(count, 24)
        let duplicate = ToolAdmission(previous: ["already-done"])
        do { try await duplicate.admit(.init(id: "already-done", name: "effect", arguments: .object([:]))); XCTFail("Repeated effect admitted") } catch { }
    }

    func testSurfaceInteractionRollbackAndLegacyOrphanCleanupAfterReopen() async throws {
        let store = try makeTestStore(); var chat = Conversation()
        var invocation = Message(role: .assistant, text: "Created")
        invocation.toolCalls = [.init(id: "surface", name: "present_surface", arguments: .object([:]))]
        chat.messages = [invocation]; try await store.save(chat)
        let original = try WorkSurface(conversationID: chat.id, sourceCallID: "surface", spec: surfaceSpec("Original"), localOnly: false, health: false)
        try await store.saveSurface(original)
        try await store.auditSQL("CREATE TEMP TRIGGER reject_interaction BEFORE UPDATE ON work_surfaces BEGIN SELECT RAISE(FAIL,'synthetic failure'); END")
        do { _ = try await store.interactWithSurface(id: original.id, conversationID: chat.id, expectedRevision: 1, selected: ["one"], inputs: [:]); XCTFail("Injected failure") } catch { }
        let before = try await store.auditCount("surface_history"); XCTAssertEqual(before, 0)
        let reopened = try LocalStore(root: store.root)
        let kept = try await reopened.surfaces(conversationID: chat.id); XCTAssertEqual(kept.first?.revision, 1)
        _ = try await reopened.interactWithSurface(id: original.id, conversationID: chat.id, expectedRevision: 1, selected: ["one"], inputs: [:])
        // Emulate the older release leaving a historical payload for a missing
        // parent. Existing live history must survive startup reconciliation.
        try await reopened.auditSQL("INSERT INTO surface_history SELECT 'orphan',revision,payload FROM surface_history LIMIT 1")
        let migrated = try LocalStore(root: store.root)
        let live = try await migrated.auditCount("surface_history"); XCTAssertEqual(live, 1)
        let independent = Conversation(); try await migrated.save(independent)
        let artifact = ArtifactRecord(conversationID: independent.id, filename: "keep.txt", content: "Independent")
        try await migrated.saveArtifact(artifact)
        _ = try await migrated.reviseArtifact(id: artifact.id, expectedRevision: 1, content: "Still independent")
        try await migrated.removeConversation(chat.id)
        let finalStore = try LocalStore(root: store.root)
        let surfaceHistory = try await finalStore.auditCount("surface_history"), artifactHistory = try await finalStore.auditCount("artifact_history")
        XCTAssertEqual(surfaceHistory, 0); XCTAssertEqual(artifactHistory, 1)
        let remaining = try await finalStore.artifacts(conversationID: independent.id); XCTAssertEqual(remaining.first?.content, "Still independent")
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
    func testRemoteReceiptCommitsOnlyAnAnswerForItsOwnTurn() async throws {
        for foreign in [false, true] {
            let store = try makeTestStore(), chat = Conversation(), workspace = UUID()
            try await store.save(chat)
            do {
                for try await _ in AssistantEngine(store: store).respond(conversation: chat, text: "Authorize the synthetic workspace", captureIDs: [], backend: AuditReceiptBackend(workspace: workspace, foreign: foreign)) { }
                XCTAssertFalse(foreign)
            } catch { XCTAssertTrue(foreign) }
            let saved = try await store.loadConversation(chat.id)
            XCTAssertEqual(saved.workspaceIDs.contains(workspace), !foreign)
            XCTAssertEqual(saved.messages.contains { $0.text == "Synthetic answer" }, !foreign)
        }
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
    func testEditedProjectContextCannotReenterThroughASiblingChatAfterReopen() async throws {
        let store = try makeTestStore(), folder = ChatFolder(name: "Synthetic project")
        try await store.saveFolder(folder)
        var source = Conversation(), sibling = Conversation()
        source.folderID = folder.id; sibling.folderID = folder.id
        var a = Message(role: .user, text: "Create A"), b = Message(role: .user, text: "Discard B")
        a.createdAt = Date(timeIntervalSinceNow: -200); b.createdAt = Date(timeIntervalSinceNow: -100)
        var mutation = Message(role: .assistant, text: "Updated")
        mutation.toolCalls = [.init(id: "project-b", name: "update_project", arguments: .object([:]))]
        source.messages = [a, b, mutation]
        try await store.save(source); try await store.save(sibling)
        var project = ProjectWorkspace(id: folder.id, sourceConversationID: source.id, title: "Shared", goal: "discarded-project-canary", status: "active", decisions: ["discarded-project-canary"], questions: [], outputIDs: [], revision: 1, updatedAt: Date(), containsLocalOnlyContext: false, containsHealthData: false)
        project.lastMutationConversationID = source.id; project.lastMutationCallID = "project-b"
        try await store.saveProjectWorkspace(project, expectedRevision: 0)
        _ = try await store.prepareMessageEdit(in: source, messageID: b.id)
        let reopened = try LocalStore(root: store.root)
        for chat in [source, sibling] {
            let visible = try await reopened.projectWorkspace(conversationID: chat.id, remote: true)
            XCTAssertEqual(visible?.needsContextRebuild, true)
            XCTAssertFalse(try visible!.summary.jsonString().contains("discarded-project-canary"))
        }
        let saved = try await reopened.projectWorkspaces(); XCTAssertEqual(saved.first?.goal, "discarded-project-canary", "The original saved record remains available for user review.")
        XCTAssertTrue(saved.first?.needsContextRebuild == true)
        var manual = saved[0]; manual.goal = "User-maintained current decision"; manual.decisions = []
        manual.revision += 1; manual.lastMutationCallID = nil; manual.lastMutationWasUserEdit = true; manual.needsContextRebuild = nil
        try await reopened.saveProjectWorkspace(manual, expectedRevision: 1)
        let editedSource = try await reopened.loadConversation(source.id)
        _ = try await reopened.prepareMessageEdit(in: editedSource, messageID: a.id)
        let independent = try await reopened.projectWorkspace(conversationID: sibling.id, remote: true)
        XCTAssertEqual(independent?.goal, "User-maintained current decision"); XCTAssertNotEqual(independent?.needsContextRebuild, true)
    }
    private func surfaceSpec(_ title: String) -> JSONValue { .object(["kind": .string("checklist"), "title": .string(title), "data": .array([.object(["id": .string("one"), "label": .string("Example"), "checked": .bool(false)])])]) }
}

private actor AuditEffectCounter { var count = 0; func record() { count += 1 } }
private struct AuditReceiptBackend: RemoteTaskBackend {
    let workspace: UUID, foreign: Bool
    let id = "audit-remote-receipt"
    let networkDestination: String? = nil
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> { AsyncThrowingStream { $0.finish() } }
    func runTask(_ request: ModelRequest) -> AsyncThrowingStream<RemoteTaskEvent, any Error> {
        AsyncThrowingStream { output in Task {
            do {
                var answer = Message(role: .user, text: "Synthetic answer")
                answer.replyToTaskID = foreign ? UUID() : request.workIdentity!.turnID
                var receipt = ToolResult(callID: "connect", name: "connect_workspace", succeeded: true, output: .object(["status": .string("connected")]))
                receipt.authorizedWorkspaceID = workspace; receipt.userResponse = answer
                try await request.commitRemoteTranscript!([answer], [receipt])
                output.yield(.transcript([answer])); output.yield(.completed); output.finish()
            } catch { output.finish(throwing: error) }
        } }
    }
}
private actor AuditFailureBackend: ModelBackend {
    nonisolated let id = "audit-idle-checkpoint"
    nonisolated let networkDestination: String? = nil
    private var output: AsyncThrowingStream<ModelEvent, any Error>.Continuation?
    private var started: [CheckedContinuation<Void, Never>] = []
    func waitForStart() async { if output == nil { await withCheckedContinuation { started.append($0) } } }
    func fail() { output?.finish(throwing: AssistantError.incompleteResponse) }
    private func attach(_ value: AsyncThrowingStream<ModelEvent, any Error>.Continuation) { output = value; started.forEach { $0.resume() }; started = [] }
    nonisolated func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { output in Task { await self.attach(output) } }
    }
}
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
