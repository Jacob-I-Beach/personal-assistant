import AssistantCore
import MapKit
import SwiftUI

struct RouteCard: View {
    @EnvironmentObject private var model: AppModel
    let id: UUID
    @State private var route: PreparedRoute?
    @State private var error: String?
    @State private var opening = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let route {
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.destination.name).font(.headline)
                    Text(route.destination.address).font(.footnote).foregroundStyle(.secondary)
                }
                if model.settings.localOnly {
                    Label("Saved route · online map paused", systemImage: "map").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 70)
                } else {
                    Map(interactionModes: []) {
                        MapPolyline(coordinates: route.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }).stroke(.blue, lineWidth: 4)
                        Marker(route.destination.name, coordinate: CLLocationCoordinate2D(latitude: route.destination.point.latitude, longitude: route.destination.point.longitude))
                    }.frame(height: 185).clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Route preview to \(route.destination.name)")
                }
                HStack(spacing: 18) {
                    Label(Duration.seconds(route.expectedTravelSeconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)), systemImage: "clock")
                    Text(Measurement(value: route.distanceMeters, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))
                    Spacer(minLength: 0)
                    Image(systemName: route.transport == "walking" ? "figure.walk" : route.transport == "cycling" ? "bicycle" : "car")
                }.font(.subheadline).monospacedDigit()
                Text("From \(route.origin.name) · Estimated \(route.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                if let accuracy = route.originAccuracyMeters, accuracy > 100 { Text("The starting fix was approximate (±\(accuracy.formatted(.number.precision(.fractionLength(0)))) m). Maps can refresh your location when opened.").font(.caption).foregroundStyle(.secondary) }
                DisclosureGroup("Route details") {
                    VStack(alignment: .leading, spacing: 10) { ForEach(Array(route.steps.enumerated()), id: \.offset) { i, text in Text("\(i + 1). \(text)").font(.footnote).frame(maxWidth: .infinity, alignment: .leading) } }.padding(.top, 8)
                }.font(.footnote).tint(.secondary)
                Button {
                    opening = true
                    Task {
                        defer { opening = false }
                        do { self.route = try await model.openPreparedRoute(id, in: route.conversationID); error = nil }
                        catch { self.error = error.localizedDescription }
                    }
                } label: { Label(opening ? "Opening…" : "Open in Maps", systemImage: "arrow.up.right").frame(maxWidth: .infinity).padding(.vertical, 4) }
                    .buttonStyle(.bordered).disabled(model.isRunning || opening || model.settings.localOnly)
                    .accessibilityLabel(opening ? "Opening Maps" : "Open in Maps").accessibilityIdentifier("open-prepared-route")
                if model.isRunning { Text("Available when the reply finishes.").font(.caption).foregroundStyle(.secondary) }
                else if route.handoffStatus == "opened" { Text("Opened in Maps. Navigation status isn’t available here.").font(.caption).foregroundStyle(.secondary) }
                else if route.handoffStatus == "opening" { Text("The last handoff was interrupted. Check Maps before opening again.").font(.caption).foregroundStyle(.secondary) }
                else if route.handoffStatus == "failed" { Text("Maps could not open this route.").font(.caption).foregroundStyle(.secondary) }
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
        }.padding(16).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain)
            .task(id: id) {
                do { route = try await model.store?.route(id, in: model.conversation.id) }
                catch { self.error = error.localizedDescription }
            }
    }
}
