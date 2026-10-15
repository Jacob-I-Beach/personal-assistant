import AssistantCore
import SwiftUI

struct HomeContextSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var city = ""
    @State private var places: [WeatherPlace] = []
    @State private var searching = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Location context") {
                    Toggle("Use location while I’m here", isOn: Binding(get: { model.settings.locationContextEnabled }, set: { enabled in
                        update { $0.locationContextEnabled = enabled; if !enabled { $0.weatherFollowsLocation = false } }
                    }))
                    Text("Remember this permission for location-based requests, so you don’t review the same access each time. iOS still controls access. Requested results can go to the selected model in an authorized chat. No continuous background tracking.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Weather on your home screen") {
                    if model.settings.weatherPlace != nil || model.settings.weatherFollowsLocation {
                        Label(model.settings.weatherFollowsLocation ? "Nearby weather" : model.settings.weatherPlace!.name, systemImage: "cloud.sun")
                        Button("Remove weather", role: .destructive) { update { $0.weatherPlace = nil; $0.weatherFollowsLocation = false }; Task { try? await model.store?.cacheHomeWeather(nil) } }
                    }
                    Text("Weather uses Open-Meteo. Choose a city or allow an approximate area (rounded to about 11 km) to be sent when you open the home screen. Refreshes automatically about every five minutes while Home is open. Your chat and saved memories are not sent to this service.").font(.footnote).foregroundStyle(.secondary)
                    Button("Use my approximate location", systemImage: "location") {
                        update { $0.locationContextEnabled = true; $0.weatherFollowsLocation = true; $0.weatherPlace = nil }
                        if error == nil { dismiss() }
                    }.disabled(model.settings.localOnly)
                    HStack {
                        TextField("City", text: $city).textContentType(.addressCity).submitLabel(.search).onSubmit { search() }
                        Button { search() } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Find weather city").disabled(searching || model.settings.localOnly)
                    }
                    if searching { ProgressView("Finding cities") }
                    ForEach(places) { place in
                        Button {
                            update { $0.weatherPlace = place; $0.weatherFollowsLocation = false }
                            if error == nil { dismiss() }
                        } label: { VStack(alignment: .leading) { Text(place.name).foregroundStyle(.primary); Text(place.region).font(.caption).foregroundStyle(.secondary) } }
                    }
                    Link("Weather data by Open-Meteo · CC BY 4.0", destination: URL(string: "https://open-meteo.com/")!).font(.caption)
                    Link("Open-Meteo privacy and terms", destination: URL(string: "https://open-meteo.com/en/terms")!).font(.caption)
                }
                if model.settings.localOnly { Text("Local only mode pauses weather and online route preparation.").font(.footnote).foregroundStyle(.secondary) }
                if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Home context").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .disabled(model.isRunning)
        }
    }
    private func update(_ change: (inout ModelSettings) -> Void) {
        var settings = model.settings; change(&settings)
        do { try model.saveSettings(settings); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func search() {
        guard !searching, !model.settings.localOnly else { return }
        searching = true
        Task {
            defer { searching = false }
            do { places = try await HomeWeatherService.searchCity(city); error = places.isEmpty ? "No matching cities. Try a nearby city or include the country." : nil }
            catch { self.error = error.localizedDescription }
        }
    }
}
