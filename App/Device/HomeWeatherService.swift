import AssistantCore
import Combine
import Foundation

@MainActor
final class HomeWeatherService: ObservableObject {
    @Published var weather: HomeWeather?
    @Published var status: String?
    private var refreshing = false
    private var requestID = UUID()
    private var lastAttempt = Date.distantPast
    private var lastConfiguration = ""
    var nextRefreshDelay: TimeInterval {
        let latest = max(lastAttempt, weather?.retrievedAt ?? .distantPast)
        guard latest != .distantPast else { return 300 }
        return min(300, max(1, 300 - Date().timeIntervalSince(latest)))
    }
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()
    static func searchCity(_ query: String) async throws -> [WeatherPlace] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...100).contains(query.count) else { throw AssistantError.provider("Enter a city name.") }
        var url = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        url.queryItems = [URLQueryItem(name: "name", value: query), URLQueryItem(name: "count", value: "6"), URLQueryItem(name: "language", value: "en"), URLQueryItem(name: "format", value: "json")]
        let payload = try await json(url.url!)
        return (payload["results"]?.arrayValue ?? []).compactMap { item in
            guard let name = item["name"]?.stringValue, let latitude = item["latitude"]?.numberValue, let longitude = item["longitude"]?.numberValue else { return nil }
            let region = [item["admin1"]?.stringValue, item["country"]?.stringValue].compactMap { $0 }.joined(separator: ", ")
            let place = WeatherPlace(name: name, region: region, latitude: (latitude * 100).rounded() / 100, longitude: (longitude * 100).rounded() / 100)
            return place.isValid ? place : nil
        }
    }
    func refresh(model: AppModel) async {
        let settings = model.settings
        let key = "\(settings.localOnly):\(settings.weatherFollowsLocation):\(settings.locationContextEnabled):\(settings.weatherPlace?.id ?? "")"
        guard !refreshing || key != lastConfiguration else { return }
        if key != lastConfiguration { weather = nil; status = nil; lastAttempt = .distantPast; lastConfiguration = key }
        guard !settings.localOnly, settings.weatherPlace != nil || (settings.weatherFollowsLocation && settings.locationContextEnabled) else { return }
        let currentRequest = UUID(); requestID = currentRequest
        refreshing = true; defer { if requestID == currentRequest { refreshing = false } }
        if weather == nil, let cached = try? await model.store?.cachedHomeWeather(), cached.isFresh(),
           !Task.isCancelled, model.settings == settings,
           (settings.weatherFollowsLocation && cached.place.name == "Nearby") || (!settings.weatherFollowsLocation && cached.place == settings.weatherPlace) { weather = cached }
        guard !Task.isCancelled, model.settings == settings else { return }
        guard Date().timeIntervalSince(lastAttempt) > 300 else { return }
        if let weather, Date().timeIntervalSince(weather.retrievedAt) < 300 { return }
        lastAttempt = Date()
        do {
            let place: WeatherPlace
            if settings.weatherFollowsLocation {
                let fix = try await model.locationService.read()
                guard let lat = fix["latitude"]?.numberValue, let lon = fix["longitude"]?.numberValue else { throw AssistantError.provider("Location is unavailable.") }
                // Forecasts need only an approximate area, never the full device fix.
                place = WeatherPlace(name: "Nearby", region: "Approximate area", latitude: (lat * 10).rounded() / 10, longitude: (lon * 10).rounded() / 10)
            } else if let saved = settings.weatherPlace, saved.isValid { place = saved }
            else { throw AssistantError.provider("Choose a weather location.") }
            try Task.checkCancellation()
            guard model.settings == settings else { return }
            var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            url.queryItems = [URLQueryItem(name: "latitude", value: String(place.latitude)), URLQueryItem(name: "longitude", value: String(place.longitude)),
                URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"), URLQueryItem(name: "timeformat", value: "unixtime"), URLQueryItem(name: "forecast_days", value: "1")]
            let result = try HomeWeather(place: place, payload: await Self.json(url.url!))
            try Task.checkCancellation()
            guard model.settings == settings else { return }
            weather = result; status = nil
            try await model.store?.cacheHomeWeather(result)
        } catch {
            guard !Task.isCancelled, model.settings == settings else { return }
            if weather?.isFresh() != true { weather = nil }
            status = "Weather couldn’t refresh. Your workspace is ready."
        }
    }
    private static func json(_ url: URL) async throws -> JSONValue {
        let (data, response) = try await session.boundedData(for: URLRequest(url: url), maximumBytes: 1048576)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count < 256_000 else { throw AssistantError.provider("The weather service is unavailable.") }
        return try JSONValue.parse(String(decoding: data, as: UTF8.self))
    }
}
