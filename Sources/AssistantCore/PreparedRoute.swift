import Foundation

public struct RoutePoint: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
    public var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}
public struct RoutePlace: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var address: String
    public var point: RoutePoint
    public init(name: String, address: String, point: RoutePoint) { self.name = name; self.address = address; self.point = point }
}
public struct PreparedRoute: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var conversationID: UUID
    public var sourceCallID: String
    public var sourceMessageID: UUID
    public var containsLocalOnlyContext = false
    public var containsHealthData = false
    public var originIsDeviceLocation = false
    public var originAccuracyMeters: Double?
    public var origin: RoutePlace
    public var destination: RoutePlace
    public var transport: String
    public var distanceMeters: Double
    public var expectedTravelSeconds: Double
    public var points: [RoutePoint]
    public var steps: [String]
    public var createdAt: Date = Date()
    public var handoffStatus = "not_opened"
    public var handoffUpdatedAt: Date?
    public init(conversationID: UUID, sourceCallID: String, sourceMessageID: UUID, origin: RoutePlace, destination: RoutePlace, transport: String, distanceMeters: Double, expectedTravelSeconds: Double, points: [RoutePoint], steps: [String]) {
        self.conversationID = conversationID; self.sourceCallID = sourceCallID; self.origin = origin; self.destination = destination
        self.sourceMessageID = sourceMessageID
        self.transport = transport; self.distanceMeters = distanceMeters; self.expectedTravelSeconds = expectedTravelSeconds; self.points = points; self.steps = steps
    }
    public func validate() throws {
        guard origin.point.isValid, destination.point.isValid, (2...600).contains(points.count), points.allSatisfy(\.isValid),
              ["driving", "walking", "cycling"].contains(transport), distanceMeters.isFinite, distanceMeters >= 0,
              expectedTravelSeconds.isFinite, expectedTravelSeconds >= 0, steps.count <= 80, steps.allSatisfy({ $0.utf8.count <= 1600 }),
              originAccuracyMeters == nil || (originAccuracyMeters!.isFinite && originAccuracyMeters! >= 0),
              origin.name.count <= 300, destination.name.count <= 300, origin.address.count <= 600, destination.address.count <= 600 else { throw AssistantError.invalidTool("The route response is outside supported bounds.") }
    }
    public func modelSummary() -> JSONValue {
        .object(["route_id": .string(id.uuidString), "status": .string("prepared_in_app"), "origin": .string(origin.name),
            "destination": .string(destination.name), "destination_address": .string(destination.address), "transport": .string(transport),
            "distance_meters": .number(distanceMeters), "expected_travel_seconds": .number(expectedTravelSeconds),
            "origin_accuracy_meters": originAccuracyMeters.map(JSONValue.number) ?? .null,
            "calculated_at": .string(ISO8601DateFormatter().string(from: createdAt)), "maps_handoff": .string(handoffStatus == "opening" ? "outcome_unknown" : handoffStatus),
            "handoff_recorded_at": handoffUpdatedAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
            "navigation_started_confirmed": .bool(false), "source": .string("Apple Maps route estimate"),
            "notice": .string("The route preview is in this conversation. The user can choose Open in Maps. Opening Maps does not confirm that navigation began; travel time is an estimate at the recorded time.")])
    }
}
extension LocalStore {
    private func ensureRoutes() throws { try database.execute("CREATE TABLE IF NOT EXISTS prepared_routes(id TEXT PRIMARY KEY,conversation_id TEXT NOT NULL,payload BLOB NOT NULL)") }
    public func saveRoute(_ route: PreparedRoute) throws {
        try route.validate(); try ensureRoutes()
        try database.execute("INSERT INTO prepared_routes(id,conversation_id,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", [.text(route.id.uuidString), .text(route.conversationID.uuidString), .blob(try Self.encode(route))])
    }
    public func routes(in conversationID: UUID) throws -> [PreparedRoute] {
        try ensureRoutes()
        let activeMessages = Set(try loadConversation(conversationID).messages.map(\.id))
        return try database.execute("SELECT payload FROM prepared_routes WHERE conversation_id=? ORDER BY rowid DESC LIMIT 20", [.text(conversationID.uuidString)])
            .map { try Self.decode(PreparedRoute.self, $0[0].data!) }
            .filter { activeMessages.contains($0.sourceMessageID) }
    }
    public func route(_ id: UUID, in conversationID: UUID) throws -> PreparedRoute {
        try ensureRoutes()
        guard let data = try database.execute("SELECT payload FROM prepared_routes WHERE id=? AND conversation_id=?", [.text(id.uuidString), .text(conversationID.uuidString)]).first?[0].data else { throw AssistantError.invalidTool("That route is outside this conversation.") }
        let route = try Self.decode(PreparedRoute.self, data)
        _ = try message(route.sourceMessageID, in: conversationID)
        return route
    }
}
