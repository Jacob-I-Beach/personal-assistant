import XCTest
@testable import AssistantCore

final class ModelCatalogStateTests: XCTestCase {
    func testSavedModelNamesAreReadableWithoutInventingModelAvailability() {
        XCTAssertEqual(ChatGPTModel.displayTitle(for: "gpt-6.1-sol", catalog: []), "GPT-6.1-Sol")
        XCTAssertEqual(ChatGPTModel.displayTitle(for: "custom-model-id", catalog: []), "custom-model-id")
        XCTAssertEqual(ChatGPTModel.displayTitle(for: "", catalog: []), "ChatGPT")
    }
    func testSameAccountChoicesSurviveFailureAndPersistence() throws {
        let models = try ChatGPTModel.catalog(from: Data(#"{"models":[{"slug":"fixture","display_name":"Fixture","visibility":"list","max_context_window":1000000}]}"#.utf8))
        let saved = AccountModelCatalog(owner: "one", models: models)
        let restored = try JSONDecoder().decode(AccountModelCatalog.self, from: JSONEncoder().encode(saved))
        var state = ModelCatalogState(); state.begin(owner: "one", saved: restored)
        state.failed(owner: "one", message: "HTTP 520")
        XCTAssertEqual(state.phase, .stale); XCTAssertEqual(state.models, models)
        XCTAssertEqual(state.models.first?.maximumContextWindow, 1_000_000)
        state.receive(saved); XCTAssertEqual(state.phase, .ready); XCTAssertNil(state.issue)
    }
    func testAccountSwitchRejectsSavedChoicesAndLateResponsesFromOtherAccount() throws {
        let saved = AccountModelCatalog(owner: "old", models: [])
        var state = ModelCatalogState(); state.begin(owner: "new", saved: saved)
        state.receive(saved); state.failed(owner: "old", message: "Old error")
        XCTAssertEqual(state.owner, "new"); XCTAssertEqual(state.phase, .refreshing); XCTAssertNil(state.updatedAt); XCTAssertNil(state.issue)
        state.failed(owner: "new", message: "Unavailable")
        XCTAssertEqual(state.phase, .unavailable)
    }
}
