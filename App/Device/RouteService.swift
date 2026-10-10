import AssistantCore
import CoreLocation
import MapKit

@MainActor
final class RouteService {
    func places(_ query: String, near point: RoutePoint? = nil) async throws -> [RoutePlace] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, query.count <= 500 else { throw AssistantError.invalidTool("Provide a short place name or address.") }
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        if let point { request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude), span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)) }
        let search = MKLocalSearch(request: request)
        let response = try await search.start()
        try Task.checkCancellation()
        var places: [RoutePlace] = []
        for item in response.mapItems {
            let coordinate = item.placemark.coordinate
            let point = RoutePoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard point.isValid else { continue }
            if places.contains(where: { abs($0.point.latitude - point.latitude) < 0.0001 && abs($0.point.longitude - point.longitude) < 0.0001 }) { continue }
            let address = [item.placemark.subThoroughfare, item.placemark.thoroughfare, item.placemark.locality, item.placemark.administrativeArea, item.placemark.postalCode].compactMap { $0 }.joined(separator: " ")
            places.append(RoutePlace(name: String((item.name ?? query).prefix(300)), address: String(address.prefix(600)), point: point))
            if places.count == 5 { break }
        }
        guard !places.isEmpty else { throw AssistantError.invalidTool("Apple Maps returned no matching place. Include a city or a more complete address.") }
        return places
    }
    func prepare(origin: RoutePlace, destination: RoutePlace, transport: String, conversationID: UUID, callID: String, sourceMessageID: UUID) async throws -> PreparedRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: origin.point.latitude, longitude: origin.point.longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: destination.point.latitude, longitude: destination.point.longitude)))
        switch transport {
        case "driving": request.transportType = .automobile
        case "walking": request.transportType = .walking
        case "cycling": request.transportType = .cycling
        default: throw AssistantError.invalidTool("Choose driving, walking or cycling.")
        }
        request.requestsAlternateRoutes = false
        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        try Task.checkCancellation()
        guard let route = response.routes.first, route.polyline.pointCount >= 2 else { throw AssistantError.invalidTool("Apple Maps did not return a route for that travel mode and region.") }
        let total = route.polyline.pointCount, pointer = route.polyline.points()
        let strideSize = max(1, Int(ceil(Double(total) / 500)))
        var points = stride(from: 0, to: total, by: strideSize).map { index in
            let coordinate = pointer[index].coordinate
            return RoutePoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        let last = pointer[total - 1].coordinate
        points.append(RoutePoint(latitude: last.latitude, longitude: last.longitude))
        let value = PreparedRoute(conversationID: conversationID, sourceCallID: callID, sourceMessageID: sourceMessageID, origin: origin, destination: destination, transport: transport,
            distanceMeters: route.distance, expectedTravelSeconds: route.expectedTravelTime, points: points,
            steps: route.steps.filter { !$0.instructions.isEmpty }.prefix(80).map { String($0.instructions.prefix(350)) })
        try value.validate(); return value
    }
    func open(_ route: PreparedRoute) async -> Bool {
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: route.destination.point.latitude, longitude: route.destination.point.longitude)))
        destination.name = route.destination.name
        let origin = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: route.origin.point.latitude, longitude: route.origin.point.longitude)))
        origin.name = route.origin.name
        let mode = route.transport == "walking" ? MKLaunchOptionsDirectionsModeWalking : route.transport == "cycling" ? MKLaunchOptionsDirectionsModeCycling : MKLaunchOptionsDirectionsModeDriving
        return MKMapItem.openMaps(with: route.originIsDeviceLocation ? [destination] : [origin, destination], launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
    }
}
