import Foundation

public struct WeatherPlace: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(name):\(latitude):\(longitude)" }
    public var name: String
    public var region: String
    public var latitude: Double
    public var longitude: Double
    public init(name: String, region: String, latitude: Double, longitude: Double) {
        self.name = name; self.region = region; self.latitude = latitude; self.longitude = longitude
    }
    public var isValid: Bool { !name.isEmpty && name.count <= 120 && region.count <= 200 && RoutePoint(latitude: latitude, longitude: longitude).isValid }
}
public struct HomeWeather: Codable, Equatable, Sendable {
    public var place: WeatherPlace
    public var celsius: Double
    public var code: Int
    public var isDay: Bool
    public var observedAt: Date
    public var retrievedAt: Date
    public init(place: WeatherPlace, payload: JSONValue, now: Date = Date()) throws {
        guard place.isValid, let current = payload["current"], let temp = current["temperature_2m"]?.numberValue,
              let time = current["time"]?.numberValue, let code = current["weather_code"]?.numberValue,
              temp.isFinite, (-100...65).contains(temp), time.isFinite, abs(now.timeIntervalSince1970 - time) < 7200,
              code.isFinite, (0...99).contains(code), code.rounded() == code else { throw AssistantError.provider("Current weather is unavailable.") }
        self.place = place; celsius = temp; self.code = Int(code); isDay = current["is_day"]?.numberValue == 1
        observedAt = Date(timeIntervalSince1970: time); retrievedAt = now
    }
    public func isFresh(at now: Date = Date()) -> Bool { (-300...5400).contains(now.timeIntervalSince(observedAt)) }
    public var condition: String {
        switch code {
        case 0: "Clear"
        case 1, 2: "Partly cloudy"
        case 3: "Cloudy"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67, 80...82: "Rain"
        case 71...77, 85, 86: "Snow"
        case 95...99: "Thunderstorms"
        default: "Weather"
        }
    }
    public var symbol: String {
        switch code {
        case 0: isDay ? "sun.max" : "moon"
        case 1, 2: isDay ? "cloud.sun" : "cloud.moon"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51...67, 80...82: "cloud.rain"
        case 71...77, 85, 86: "cloud.snow"
        case 95...99: "cloud.bolt"
        default: "cloud"
        }
    }
}
public enum HomeGreeting {
    public static func name(from memories: [SavedMemory], at date: Date = Date()) -> String? {
        memories.filter { $0.profileKey == "preferred_name" && $0.conversationID == nil && $0.status == .active && $0.isCurrent(at: date) && $0.basis != .inferred && $0.text.count <= 60 && !$0.text.contains("\n") }
            .max(by: { $0.updatedAt < $1.updatedAt })?.text
    }
    public static func title(at date: Date = Date(), calendar: Calendar = .current, name: String?, weather: HomeWeather? = nil,
                             unfinishedCount: Int = 0, needsAttention: Bool = false, nextCommitment: Date? = nil) -> String {
        let hour = calendar.component(.hour, from: date)
        let phrase: String
        if needsAttention { phrase = "One answer, then onward." }
        else if unfinishedCount > 0 { phrase = "Let’s pick up the thread." }
        else if let nextCommitment, (0...7200).contains(nextCommitment.timeIntervalSince(date)) { phrase = "A little room before what’s next." }
        else if let weather, weather.isFresh(at: date), weather.code == 0 { phrase = weather.isDay ? "Clear skies, fresh ideas." : "A clear night for an idea." }
        else if let weather, weather.isFresh(at: date), weather.celsius < 6 { phrase = "Cold air, fresh ideas." }
        else if calendar.isDateInWeekend(date) { phrase = "A little space to explore." }
        else if hour < 5 { phrase = "Something on your mind?" }
        else if hour < 12 { phrase = "Start with something worthwhile." }
        else if hour < 17 { phrase = "Make room for a good idea." }
        else { phrase = "Bring a little clarity." }
        guard let name, !name.isEmpty, name.count <= 24 else { return phrase }
        return String(phrase.dropLast()) + ", " + name + String(phrase.suffix(1))
    }
    public static func subtitle(weather: HomeWeather?, unfinishedCount: Int, at date: Date = Date()) -> String {
        if unfinishedCount > 0 { return "Pick up where you left off, or start something new." }
        if let weather, weather.isFresh(at: date) {
            if weather.celsius < 6 { return "A cold day outside. Room for a new idea here." }
            if weather.code >= 51 { return "A little weather outside. What’s on your mind?" }
        }
        return "Bring an idea, a question, or something in front of you."
    }
}
extension LocalStore {
    public func cachedHomeWeather() throws -> HomeWeather? {
        guard let text = try database.execute("SELECT value FROM metadata WHERE key='home-weather'").first?[0].text,
              let data = text.data(using: .utf8) else { return nil }
        return try Self.decode(HomeWeather.self, data)
    }
    public func cacheHomeWeather(_ weather: HomeWeather?) throws {
        guard let weather else { try database.execute("DELETE FROM metadata WHERE key='home-weather'"); return }
        let text = String(decoding: try Self.encode(weather), as: UTF8.self)
        try database.execute("INSERT INTO metadata(key,value) VALUES('home-weather',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [.text(text)])
    }
}
