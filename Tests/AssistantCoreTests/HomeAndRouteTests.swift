import XCTest
@testable import AssistantCore

final class HomeAndRouteTests: XCTestCase, @unchecked Sendable {
    func testGreetingUsesOnlyCurrentExplicitGlobalNameAndLocalTime() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var stated = SavedMemory(title: "Name", text: "Sam"); stated.profileKey = "preferred_name"; stated.basis = .stated
        var inferred = stated; inferred.id = UUID(); inferred.text = "An inferred name"; inferred.basis = .inferred
        var scoped = stated; scoped.id = UUID(); scoped.text = "Project name"; scoped.conversationID = UUID()
        XCTAssertEqual(HomeGreeting.name(from: [stated, inferred, scoped], at: date), "Sam")
        stated.status = .forgotten
        XCTAssertNil(HomeGreeting.name(from: [stated, inferred, scoped], at: date))
        XCTAssertEqual(HomeGreeting.title(at: date, calendar: calendar, name: "Sam"), "Good evening, Sam.")
    }
    func testWeatherRejectsStaleMalformedDataAndCachesOnlyRecordedConditions() async throws {
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)), place = WeatherPlace(name: "Example city", region: "Test", latitude: 40, longitude: -75)
        let payload: JSONValue = .object(["current": .object(["temperature_2m": .number(3), "time": .number(now.timeIntervalSince1970), "weather_code": .number(3), "is_day": .number(1)])])
        let weather = try HomeWeather(place: place, payload: payload, now: now)
        XCTAssertTrue(weather.isFresh(at: now)); XCTAssertFalse(weather.isFresh(at: now.addingTimeInterval(7200)))
        XCTAssertTrue(HomeGreeting.subtitle(weather: weather, unfinishedCount: 0, at: now).contains("cold"))
        XCTAssertFalse(HomeGreeting.subtitle(weather: weather, unfinishedCount: 0, at: now.addingTimeInterval(7200)).contains("cold"))
        XCTAssertThrowsError(try HomeWeather(place: place, payload: payload, now: now.addingTimeInterval(20_000)))
        let store = try makeTestStore(); try await store.cacheHomeWeather(weather)
        let saved = try await store.cachedHomeWeather(); XCTAssertEqual(saved, weather)
        try await store.cacheHomeWeather(nil); let cleared = try await store.cachedHomeWeather(); XCTAssertNil(cleared)
    }
    func testRouteRequiresValidCoordinatesAndCannotSurviveAnEditedAwaySource() async throws {
        let store = try makeTestStore()
        var chat = Conversation(); let source = Message(role: .user, text: "Prepare an example route")
        chat.messages = [source]; try await store.save(chat)
        let a = RoutePlace(name: "A", address: "Example origin", point: .init(latitude: 40, longitude: -75))
        let b = RoutePlace(name: "B", address: "Example destination", point: .init(latitude: 40.01, longitude: -75.01))
        var route = PreparedRoute(conversationID: chat.id, sourceCallID: "route", sourceMessageID: source.id, origin: a, destination: b, transport: "walking", distanceMeters: 1500, expectedTravelSeconds: 1200, points: [a.point, b.point], steps: ["Example step"])
        try await store.saveRoute(route)
        XCTAssertEqual(route.modelSummary()["navigation_started_confirmed"], .bool(false))
        route.handoffStatus = "opening"; XCTAssertEqual(route.modelSummary()["maps_handoff"], .string("outcome_unknown"))
        route.points[0].latitude = 91; XCTAssertThrowsError(try route.validate())
        _ = try await store.prepareMessageEdit(in: chat, messageID: source.id)
        let visible = try await store.routes(in: chat.id); XCTAssertTrue(visible.isEmpty)
        do { _ = try await store.route(route.id, in: chat.id); XCTFail("Edited-away route was readable") } catch {}
    }
}
