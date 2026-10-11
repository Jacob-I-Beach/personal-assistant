import XCTest
@testable import AssistantCore

final class MaintainedWorkTests: XCTestCase, @unchecked Sendable {
    func testArtifactRevisionsKeepIdentityAndRejectStaleWriters() async throws {
        let store = try makeTestStore(), chat = Conversation()
        try await store.save(chat)
        let artifact = ArtifactRecord(conversationID: chat.id, filename: "report.md", content: "First version")
        try await store.saveArtifact(artifact)
        let revised = try await store.reviseArtifact(id: artifact.id, expectedRevision: 1, content: "Second version")
        XCTAssertEqual(revised.id, artifact.id); XCTAssertEqual(revised.revision, 2)
        let history = try await store.artifactHistory(artifact.id)
        XCTAssertEqual(history.map(\.content), ["First version"])
        do { _ = try await store.reviseArtifact(id: artifact.id, expectedRevision: 1, content: "Stale replacement"); XCTFail("A stale writer changed the document") } catch {}
        let current = try await store.artifacts().first { $0.id == artifact.id }
        XCTAssertEqual(current?.content, "Second version")
    }
    func testSurfaceRevisionPreservesSelectionAndRequiresCurrentVersion() async throws {
        let store = try makeTestStore(); var chat = Conversation()
        chat.messages = [Message(role: .assistant, text: "", toolCalls: [.init(id: "surface", name: "present_surface", arguments: .object([:]))])]
        try await store.save(chat)
        let spec: JSONValue = .object(["kind": .string("checklist"), "title": .string("Packing"), "data": .array([.object(["id": .string("charger"), "label": .string("Charger")])])])
        let original = try WorkSurface(conversationID: chat.id, sourceCallID: "surface", spec: spec, localOnly: false, health: false)
        try await store.saveSurface(original)
        let selected = try await store.interactWithSurface(id: original.id, conversationID: chat.id, expectedRevision: 1, selected: ["charger"], inputs: [:])
        let update = try await store.reviseSurface(id: original.id, conversationID: chat.id, expectedRevision: selected.revision, replacement: original)
        XCTAssertEqual(update.id, original.id); XCTAssertEqual(update.selectedIDs, ["charger"]); XCTAssertEqual(update.revision, 3)
        do { _ = try await store.reviseSurface(id: original.id, conversationID: chat.id, expectedRevision: 1, replacement: original); XCTFail("Stale update was accepted") } catch {}
    }
    func testProjectContextDoesNotExposeAnOnDeviceProjectToConnectedModels() async throws {
        let store = try makeTestStore(), chat = Conversation()
        try await store.save(chat)
        let project = ProjectWorkspace(id: chat.id, sourceConversationID: chat.id, title: "Private project", goal: "A local goal", status: "active", decisions: [], questions: ["Next step?"], outputIDs: [], revision: 1, updatedAt: Date(), containsLocalOnlyContext: true, containsHealthData: false)
        try await store.saveProjectWorkspace(project, expectedRevision: 0)
        let remote = try await store.projectWorkspace(conversationID: chat.id, remote: true), local = try await store.projectWorkspace(conversationID: chat.id, remote: false)
        XCTAssertNil(remote); XCTAssertEqual(local?.questions, ["Next step?"])
    }
}
