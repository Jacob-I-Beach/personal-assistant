import Foundation
import XCTest
@testable import AssistantCore

final class WorkingSurfaceTests: XCTestCase, @unchecked Sendable {
    func testAllSurfaceSchemasValidateBoundedExamples() throws {
        let examples = [
            #"{"kind":"metrics","title":"Result","data":[{"label":"Total","value":60.5}]}"#,
            #"{"kind":"chart","title":"Values","style":"line","data":[{"label":"A","value":18.5},{"label":"B","value":27.25}]}"#,
            #"{"kind":"table","title":"Values","columns":["Item","Amount"],"data":[["A",18.5]]}"#,
            #"{"kind":"comparison","title":"Options","data":[{"id":"a","label":"First","detail":"One option"}]}"#,
            #"{"kind":"checklist","title":"Tasks","data":[{"id":"a","label":"Read","checked":false}]}"#,
            #"{"kind":"timeline","title":"Progress","data":[{"label":"Draft","status":"completed"}]}"#,
            Self.scenario,
        ]
        for example in examples { XCTAssertNoThrow(try WorkSurface.validate(JSONValue.parse(example))) }
    }
    func testSurfaceRejectsCodeBadShapesDuplicatesAndExcessData() throws {
        for raw in [
            #"{"kind":"html","title":"Bad","data":[]}"#,
            #"{"kind":"chart","title":"Bad","script":"fetch('private')","data":[{"label":"A","value":1}]}"#,
            #"{"kind":"chart","title":"Bad","data":[{"label":"A","value":"invented"}]}"#,
            #"{"kind":"checklist","title":"Bad","data":[{"id":"a","label":"A"},{"id":"a","label":"B"}]}"#,
            #"{"kind":"table","title":"Bad","columns":["A"],"data":[[1,2]]}"#,
        ] { XCTAssertThrowsError(try WorkSurface.validate(JSONValue.parse(raw))) }
        var huge = try JSONValue.parse(#"{"kind":"metrics","title":"Too much","data":[]}"#).objectValue!
        huge["data"] = .array(Array(repeating: .object(["label": .string("A"), "value": .number(1)]), count: 201))
        XCTAssertThrowsError(try WorkSurface.validate(.object(huge)))
    }
    func testScenarioEvaluatesInputsWithoutExecutingScripts() throws {
        let spec = try JSONValue.parse(Self.scenario), expression = try XCTUnwrap(spec["expression"])
        XCTAssertEqual(try WorkSurface.evaluate(expression, inputs: ["price": 18.5, "count": 4]), 74)
        XCTAssertEqual(try WorkSurface.evaluate(expression, inputs: ["price": 27.25, "count": 2]), 54.5)
        XCTAssertThrowsError(try WorkSurface.evaluate(try JSONValue.parse(#"{"op":"divide","args":[1,0]}"#), inputs: [:]))
        XCTAssertThrowsError(try WorkSurface.evaluate(.string("run arbitrary code"), inputs: [:]))
        var nested: JSONValue = .number(1)
        for _ in 0..<10 { nested = .object(["op": .string("add"), "args": .array([nested, .number(1)])]) }
        XCTAssertThrowsError(try WorkSurface.evaluate(nested, inputs: [:]))
    }
    func testSelectionsPersistAndRejectStaleOrForeignUpdates() async throws {
        let store = try makeTestStore()
        var conversation = Conversation(); conversation.messages = [Message(role: .assistant, text: "", toolCalls: [.init(id: "board", name: "present_surface", arguments: .object([:]))])]
        try await store.save(conversation)
        let surface = try WorkSurface(conversationID: conversation.id, sourceCallID: "board", spec: JSONValue.parse(#"{"kind":"comparison","title":"Choose","data":[{"id":"a","label":"Option A"},{"id":"b","label":"Option B"}]}"#), localOnly: false, health: false)
        try await store.saveSurface(surface)
        let changed = try await store.interactWithSurface(id: surface.id, conversationID: conversation.id, expectedRevision: 1, selected: ["b"], inputs: [:])
        XCTAssertEqual(changed.revision, 2)
        let reopened = try LocalStore(root: store.root)
        let records = try await reopened.surfaces(conversationID: conversation.id)
        XCTAssertEqual(records.first?.selectedIDs, ["b"])
        do { _ = try await store.interactWithSurface(id: surface.id, conversationID: conversation.id, expectedRevision: 1, selected: ["a"], inputs: [:]); XCTFail("Stale overwrite") } catch { }
        do { _ = try await store.interactWithSurface(id: surface.id, conversationID: conversation.id, expectedRevision: 2, selected: ["outside"], inputs: [:]); XCTFail("Foreign option") } catch { }
    }
    func testComputedSurfaceUsesSavedResultInsteadOfRetypedData() async throws {
        let store = try makeTestStore()
        var conversation = Conversation()
        let calculation = ToolCall(id: "calculation", name: "run_javascript", arguments: .object([:]))
        let presentation = ToolCall(id: "presentation", name: "present_surface", arguments: .object([:]))
        conversation.messages = [Message(role: .user, text: "Calculate"), Message(role: .assistant, text: "", toolCalls: [calculation]), Message(role: .tool, text: #"{"tool_succeeded":true,"result":60.5}"#, toolCallID: calculation.id), Message(role: .assistant, text: "", toolCalls: [presentation])]
        try await store.save(conversation)
        let call = ToolCall(id: presentation.id, name: "present_surface", arguments: .object(["spec_json": .string(#"{"kind":"metrics","title":"Total","data":[{"label":"Wrong","value":61.55}]}"#), "data_call_id": .string(calculation.id)]))
        let result = try await SurfaceTools.execute(call, store: store, conversationID: conversation.id, remote: false, localOnly: false, health: false)
        XCTAssertTrue(result.succeeded)
        let stored = try await store.surfaces(conversationID: conversation.id)
        XCTAssertEqual(stored.first?.rows.first?["value"], .number(60.5))
        let repeated = try await SurfaceTools.execute(call, store: store, conversationID: conversation.id, remote: false, localOnly: false, health: false)
        XCTAssertEqual(result.output["surface_id"], repeated.output["surface_id"])
    }
    func testEditingRemovesFutureSurfacesFromAllActiveContext() async throws {
        let store = try makeTestStore()
        var conversation = Conversation(); let user = Message(role: .user, text: "Old request")
        conversation.messages = [user, Message(role: .assistant, text: "", toolCalls: [.init(id: "future", name: "present_surface", arguments: .object([:]))])]
        try await store.save(conversation)
        try await store.saveSurface(WorkSurface(conversationID: conversation.id, sourceCallID: "future", spec: JSONValue.parse(Self.scenario), localOnly: true, health: false))
        let remote = try await store.surfaces(conversationID: conversation.id, remote: true)
        XCTAssertTrue(remote.isEmpty)
        _ = try await store.prepareMessageEdit(in: conversation, messageID: user.id)
        let active = try await store.surfaces(conversationID: conversation.id)
        XCTAssertTrue(active.isEmpty)
    }
    func testExpiredAndSupersededMemoriesAreInspectableButNotContext() async throws {
        let store = try makeTestStore(), conversationID = UUID()
        var note = SavedMemory(title: "Old decision", text: "Do the obsolete thing", allowsConnectedModels: true)
        note.kind = .decision; note.status = .superseded; try await store.saveMemory(note)
        var expired = SavedMemory(title: "Temporary", text: "Was valid", allowsConnectedModels: true)
        expired.expiresAt = Date().addingTimeInterval(-1); try await store.saveMemory(expired)
        let notes = try await store.memories()
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(MemoryContext.eligible(notes, conversationID: conversationID, remote: true).isEmpty)
        var tentative = SavedMemory(title: "Maybe", text: "Uncertain preference", allowsConnectedModels: true)
        tentative.status = .tentative; tentative.kind = .question; tentative.source = "User hypothesis"
        let context = MemoryContext.instructions([tentative], query: "preference", conversationID: conversationID, remote: true)
        XCTAssertTrue(context.contains("tentative")); XCTAssertTrue(context.contains("User hypothesis")); XCTAssertTrue(context.contains("question"))
    }
    func testOldMemoryMigratesWithoutInventedConfirmation() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        var object = try JSONValue.parse(String(decoding: encoder.encode(SavedMemory(title: "Old", text: "Note")), as: UTF8.self)).objectValue!
        for key in ["kind", "status", "source", "confirmedAt", "expiresAt"] { object.removeValue(forKey: key) }
        let note = try decoder.decode(SavedMemory.self, from: Data(JSONValue.object(object).jsonString().utf8))
        XCTAssertEqual(note.kind, .note); XCTAssertEqual(note.status, .active); XCTAssertNil(note.confirmedAt)
    }
    private static let scenario = #"{"kind":"scenario","title":"Try values","inputs":[{"id":"price","label":"Price","value":18.5,"min":1,"max":100,"step":0.5},{"id":"count","label":"Count","value":4,"min":1,"max":10,"step":1}],"expression":{"op":"multiply","args":[{"input":"price"},{"input":"count"}]},"result_label":"Total"}"#
}
