import Foundation
import XCTest
@testable import AssistantCore

final class HealthTests: XCTestCase, @unchecked Sendable {
    func testOverlappingSleepIsUnionedAndClipped() {
        let start = Date(timeIntervalSince1970: 0), end = Date(timeIntervalSince1970: 10_000)
        let samples = [SleepInterval(start: start.addingTimeInterval(-100), end: start.addingTimeInterval(4000), source: "A"),
                       SleepInterval(start: start.addingTimeInterval(2000), end: start.addingTimeInterval(6000), source: "B"),
                       SleepInterval(start: start.addingTimeInterval(8000), end: start.addingTimeInterval(12_000), source: "A")]
        XCTAssertEqual(HealthOverview.unionDuration(samples, from: start, to: end), 8000)
    }
    func testMissingDataStaysMissingAndDaylightSavingUsesCalendarBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        XCTAssertEqual(end.timeIntervalSince(start), 23 * 3600)
        let report = HealthOverview(rangeStart: start, rangeEnd: end, calendar: calendar, steps: [:], sleep: [], workouts: [])
        XCTAssertEqual(report.days.count, 1)
        XCTAssertNil(report.days[0].steps); XCTAssertNil(report.days[0].sleepHours)
        let sleeping = HealthOverview(rangeStart: start, rangeEnd: end, calendar: calendar, steps: [:], sleep: [.init(start: start, end: end, source: "fixture")], workouts: [])
        XCTAssertEqual(sleeping.days[0].sleepHours, 23)
    }
    func testHealthRequiresItsOwnNetworkPermissionBeforeAnyProviderCall() async throws {
        let store = try makeTestStore()
        let engine = AssistantEngine(store: store)
        var conversation = Conversation()
        conversation.allowedNetworkDestinations = ["fixture"]
        let backend = NeverCalledHealthBackend()
        do {
            for try await _ in engine.respond(conversation: conversation, text: "Selected health summary", captureIDs: [], backend: backend, containsHealthData: true) {}
            XCTFail("Health was shared without specific permission")
        } catch { XCTAssertTrue(error is AssistantError) }
        let saved = try await store.conversations()
        XCTAssertTrue(saved.isEmpty)
    }
}
private struct NeverCalledHealthBackend: ModelBackend {
    let id = "test"
    let networkDestination: String? = "fixture"
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        XCTFail("Unauthorized health request reached the model")
        return AsyncThrowingStream { $0.finish() }
    }
}
