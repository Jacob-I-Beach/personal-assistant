import AssistantCore
import Foundation
import UIKit

extension AppModel {
    func executeRouteTool(_ call: ToolCall, conversationID: UUID) async throws -> JSONValue {
        guard let store else { throw AssistantError.provider("The workspace is unavailable.") }
        if call.name == NativeTools.readRoute.name {
            guard let id = UUID(uuidString: call.arguments["route_id"]?.stringValue ?? "") else { throw AssistantError.invalidTool("Use the route ID from the prepared route.") }
            let route = try await store.route(id, in: conversationID)
            guard settings.networkDestination == nil || (!route.containsLocalOnlyContext && (!route.containsHealthData || conversation.allowedHealthDestinations.contains(settings.networkDestination!))) else { throw AssistantError.networkNotAuthorized }
            return route.modelSummary()
        }
        guard !settings.localOnly, let source = try await store.loadConversation(conversationID).messages.last(where: { $0.role == .user })?.id else { throw AssistantError.invalidTool("Route preparation needs an active request and a connection to Apple Maps. Local only mode prevents that connection.") }
        let originQuery = call.arguments["origin"]?.stringValue ?? ""
        let destinationQuery = call.arguments["destination"]?.stringValue ?? ""
        let mode = call.arguments["transport"]?.stringValue ?? ""
        guard !originQuery.isEmpty, originQuery.count <= 500, !destinationQuery.isEmpty, destinationQuery.count <= 500,
              ["driving", "walking", "cycling"].contains(mode) else { throw AssistantError.invalidTool("Provide an origin, a destination and driving, walking or cycling.") }
        let currentLocation = originQuery == "current_location"
        if !settings.locationContextEnabled {
            let status = try await reviewNativeAction(NativeActionRequest(kind: .approval, title: "Prepare directions?",
            detail: "\(currentLocation ? "Current location" : originQuery) → \(destinationQuery)\n\nApple Maps will receive these places\(currentLocation ? " and a single foreground location fix" : "") to calculate a \(mode) route. The route summary will be available to \(modelTitle) in this chat. You’ll review the destination and stay in the app.", arguments: call.arguments))
            guard status == "approved" else { return routeCancelled(status) }
        }
        let origin: RoutePlace
        var accuracy: Double?
        if currentLocation {
            let fix = try await locationService.read()
            accuracy = fix["horizontal_accuracy_meters"]?.numberValue
            guard let lat = fix["latitude"]?.numberValue, let lon = fix["longitude"]?.numberValue else { throw AssistantError.invalidTool("A current location was not available.") }
            origin = RoutePlace(name: "Location at preparation", address: "Saved foreground location", point: RoutePoint(latitude: lat, longitude: lon))
        } else {
            let choices = try await routeService.places(originQuery)
            let selection = try await reviewNativeAction(NativeActionRequest(kind: .placeSelection, title: "Starting point", detail: "Choose the intended starting point.", arguments: .object([:]), places: choices))
            guard let selected = choices.first(where: { $0.id.uuidString == selection }) else { return routeCancelled(selection) }
            origin = selected
        }
        try Task.checkCancellation()
        let choices = try await routeService.places(destinationQuery, near: origin.point)
        let selection = try await reviewNativeAction(NativeActionRequest(kind: .placeSelection, title: "Destination", detail: "Choose the place you want directions to. No navigation starts here.", arguments: .object([:]), places: choices))
        guard let destination = choices.first(where: { $0.id.uuidString == selection }) else { return routeCancelled(selection) }
        activity = "Preparing your route"
        var route = try await routeService.prepare(origin: origin, destination: destination, transport: mode, conversationID: conversationID, callID: call.id, sourceMessageID: source)
        route.containsLocalOnlyContext = settings.networkDestination == nil || conversation.networkDisabled || conversation.messages.contains(where: \.containsLocalOnlyContext)
        route.containsHealthData = conversation.containsHealthData
        route.originIsDeviceLocation = currentLocation; route.originAccuracyMeters = accuracy
        try Task.checkCancellation()
        try await store.saveRoute(route)
        return route.modelSummary()
    }
    private func routeCancelled(_ status: String) -> JSONValue {
        .object(["status": .string(status == "cancelled" ? "cancelled" : "interrupted"), "route_prepared": .bool(false), "navigation_started_confirmed": .bool(false)])
    }
    func openPreparedRoute(_ id: UUID, in conversationID: UUID) async throws -> PreparedRoute {
        guard !isRunning, !settings.localOnly, UIApplication.shared.applicationState == .active, let store else { throw AssistantError.invalidTool("Finish the reply and keep the app open before opening Maps. Local only mode must be off.") }
        var route = try await store.route(id, in: conversationID)
        route.handoffStatus = "opening"; route.handoffUpdatedAt = Date()
        try await store.saveRoute(route)
        let window = ResponseCompletionWindow(); window.begin {}
        defer { window.end() }
        let opened = await routeService.open(route)
        route.handoffStatus = opened ? "opened" : "failed"; route.handoffUpdatedAt = Date()
        try await store.saveRoute(route)
        return route
    }
}
