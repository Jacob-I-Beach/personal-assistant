import AssistantCore
import Foundation

extension AppModel {
    func executePlanningTool(_ call: ToolCall, destination: String?) async throws -> ToolResult {
        let kind = ["read_reminders", "save_reminder", "complete_reminder"].contains(call.name) ? "reminder" : "calendar"
        func permitted() -> Bool { (kind == "calendar" ? !settings.calendarSourceIDs.isEmpty : !settings.reminderSourceIDs.isEmpty) && (destination == nil || settings.planningConnectedAccess) }
        if !permitted(), call.name != PlanningTools.sources.name {
            let choice = try await reviewNativeAction(.init(kind: .planningConnection, title: "Planning access", detail: "", arguments: .object([:])))
            guard choice == "approved", permitted() else { return .init(callID: call.id, name: call.name, succeeded: false, output: .object(["status": .string("cancelled"), "notice": .string("Planning access was not enabled. No calendar or reminder data was read.")])) }
        }
        guard destination == nil || settings.planningConnectedAccess else { throw AssistantError.invalidTool("Enable connected-model planning access before sharing these sources.") }
        let args = call.arguments, sourceIDs = kind == "calendar" ? settings.calendarSourceIDs : settings.reminderSourceIDs
        let output: JSONValue
        switch call.name {
        case PlanningTools.sources.name:
            planning.refreshSources()
            let ids = Set(settings.calendarSourceIDs + settings.reminderSourceIDs)
            output = .object(["sources": .array(planning.sources.filter { ids.contains($0.id) }.map { .object(["source_id": .string($0.id), "title": .string($0.title), "kind": .string($0.kind), "can_save": .bool($0.writable)]) })])
        case PlanningTools.schedule.name:
            let items = try planning.schedule(from: PlanningService.date(args["start"]!.stringValue!), to: PlanningService.date(args["end"]!.stringValue!), sourceIDs: sourceIDs)
            output = .object(["events": .array(items.prefix(80).map(\.modelValue)), "total_events": .number(Double(items.count)), "coverage_complete": .bool(items.count <= 80), "time_zone": .string(TimeZone.current.identifier)])
        case PlanningTools.available.name:
            guard let minutes = Int(args["minutes"]!.stringValue!), let lower = Int(args["day_start_hour"]!.stringValue!), let upper = Int(args["day_end_hour"]!.stringValue!), let zone = TimeZone(identifier: args["time_zone"]!.stringValue!), ["true", "false"].contains(args["weekdays_only"]!.stringValue!) else { throw AssistantError.invalidTool("Use valid duration, daily hours, time zone and weekday choices.") }
            let slots = try planning.availability(from: PlanningService.date(args["start"]!.stringValue!), to: PlanningService.date(args["end"]!.stringValue!), minutes: minutes, dayStart: lower, dayEnd: upper, timeZone: zone, weekdaysOnly: args["weekdays_only"] == .string("true"), sourceIDs: sourceIDs)
            output = .object(["slots": .array(slots.map { .object(["start": .string(ISO8601DateFormatter().string(from: $0.start)), "end": .string(ISO8601DateFormatter().string(from: $0.end))]) }), "time_zone": .string(zone.identifier), "coverage": .string("Selected calendars only. No other person's availability or travel time is assumed.")])
        case PlanningTools.reminders.name:
            let query = args["query"]!.stringValue!.lowercased()
            let items = try await planning.reminders(sourceIDs: sourceIDs).filter { query.isEmpty || $0.title.lowercased().contains(query) }
            output = .object(["reminders": .array(items.prefix(80).map(\.modelValue)), "total_reminders": .number(Double(items.count)), "coverage_complete": .bool(items.count <= 80)])
        default:
            let existing = try planning.validateChange(args, kind: kind, settings: settings)
            let completing = call.name == PlanningTools.complete.name
            let title = completing ? "Complete reminder?" : existing == nil ? "Save \(kind == "calendar" ? "event" : "reminder")?" : "Update \(kind == "calendar" ? "event" : "reminder")?"
            var lines = [args["title"]?.stringValue ?? existing?.title ?? ""]
            if kind == "calendar" {
                let start = try PlanningService.date(args["start"]!.stringValue!), end = try PlanningService.date(args["end"]!.stringValue!)
                guard start < end else { throw AssistantError.invalidTool("The end must follow the start.") }
                let conflicts = try planning.schedule(from: start, to: end, sourceIDs: sourceIDs).filter { $0.id != existing?.id && $0.blocksTime }
                lines += [start.formatted(date: .abbreviated, time: .shortened) + " – " + end.formatted(date: .abbreviated, time: .shortened), TimeZone.current.identifier]
                if !conflicts.isEmpty { lines.append("Overlaps: " + conflicts.prefix(4).map(\.title).joined(separator: ", ")) }
            } else if let due = args["due"]?.stringValue, !due.isEmpty { lines.append("Due " + (try PlanningService.date(due)).formatted(date: .abbreviated, time: .shortened)) }
            if let old = existing, !completing { lines.append("Currently: " + old.title + (old.start.map { " · " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")) }
            if let notes = args["notes"]?.stringValue, !notes.isEmpty { lines.append(notes) }
            if let source = planning.sources.first(where: { $0.id == (args["source_id"]?.stringValue ?? existing?.sourceID) }) { lines.append("In " + source.title) }
            let approved = try await reviewNativeAction(.init(kind: .approval, title: title, detail: lines.joined(separator: "\n\n"), arguments: args))
            guard approved == "approved" else { return .init(callID: call.id, name: call.name, succeeded: false, output: .object(["status": .string(approved == "cancelled" ? "cancelled" : "interrupted"), "saved": .bool(false)])) }
            guard permitted() else { throw AssistantError.invalidTool("Planning access changed. Review the connection before saving.") }
            let saved: PlanningItem
            do { saved = try planning.save(args, kind: kind, settings: settings, completeOnly: completing) }
            catch let uncertain as PlanningWriteUnverified {
                return .init(callID: call.id, name: call.name, succeeded: false, output: .object(["status": .string("outcome_unknown"), "item_id": .string(uncertain.itemID), "error": .string(uncertain.localizedDescription)]))
            }
            output = .object(["status": .string(completing ? "completed" : "saved"), "verified_in_event_store": .bool(true), "item": saved.modelValue, "notice": .string("Verified in this iPhone's event store. Cloud sync and notification delivery are not confirmed.")])
            await planning.refreshHome(settings: settings)
        }
        return .init(callID: call.id, name: call.name, succeeded: true, output: output)
    }
}
