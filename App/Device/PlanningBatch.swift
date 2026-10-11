import AssistantCore
import Foundation

enum PlanningBatchTools {
    static let apply: ToolDefinition = {
        let tools = [PlanningTools.saveEvent, PlanningTools.saveReminder, PlanningTools.complete, PlanningTools.remove]
        let variants = tools.map { tool in JSONValue.object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("operation"), .string("arguments")]), "properties": .object([
            "operation": .object(["type": .string("string"), "enum": .array([.string(tool.name)])]), "arguments": tool.parameters
        ])]) }
        return .init(name: "apply_planning_changes", description: "Prepare one review for 1–8 independent calendar/reminder saves, completions or deletions. Supply the exact typed arguments for each operation, including source and current version. Execution rechecks each item and records individual outcomes. A partial failure does not roll back successful items. No item may depend on an ID created by another item.", parameters: .object(["type": .string("object"), "additionalProperties": .bool(false), "required": .array([.string("changes")]), "properties": .object([
            "changes": .object(["type": .string("array"), "minItems": .number(1), "maxItems": .number(8), "items": .object(["anyOf": .array(variants)])])
        ])]))
    }()
    static let read = NativeTools.definition("read_planning_batch", "Inspect the saved per-item results of a planning batch in this chat after completion or interruption. started means outcome unknown, not permission to retry.", ["batch_id": "Exact batch identifier returned by apply_planning_changes; the operation ID also appears in task receipts."])
    static let definitions = [apply, read]
    static let names = Set(definitions.map(\.name))
}

extension AppModel {
    func executePlanningBatch(_ call: ToolCall, destination: String?) async throws -> ToolResult {
        guard let store else { throw AssistantError.provider("Saved task storage is unavailable.") }
        let chatID = conversation.id
        if call.name == PlanningBatchTools.read.name {
            guard let record = try await store.batchAction(call.arguments["batch_id"]?.stringValue ?? "", conversationID: chatID) else { throw AssistantError.invalidTool("That batch was not found in this chat.") }
            return .init(callID: call.id, name: call.name, succeeded: true, output: record)
        }
        guard destination == nil || settings.planningConnectedAccess else { throw AssistantError.invalidTool("Connect planning sources and enable their use with this model before reviewing a batch.") }
        let scope = ToolExecutionContext.current?.turnID.uuidString ?? chatID.uuidString, batchID = scope + ":" + call.id
        if let record = try await store.batchAction(batchID, conversationID: chatID) { return .init(callID: call.id, name: call.name, succeeded: true, output: record) }
        guard let changes = call.arguments["changes"]?.arrayValue, (1...8).contains(changes.count) else { throw AssistantError.invalidTool("Use one to eight changes.") }
        var previews: [String] = [], steps: [JSONValue] = [], prepared: [(String, String, JSONValue)] = []
        var seenItems = Set<String>()
        for (index, change) in changes.enumerated() {
            guard let operation = change["operation"]?.stringValue, let raw = change["arguments"],
                  let definition = [PlanningTools.saveEvent, PlanningTools.saveReminder, PlanningTools.complete, PlanningTools.remove].first(where: { $0.name == operation }) else { throw AssistantError.invalidTool("Choose a supported planning operation.") }
            var fields = try ToolArguments.normalize(raw, schema: definition.parameters).objectValue ?? [:]
            if fields["occurrence_start"] == .string("") { fields["occurrence_start"] = .null }
            let args = JSONValue.object(fields)
            let kind = operation == "delete_planning_item" ? args["kind"]?.stringValue ?? "" : operation == "save_calendar_event" ? "calendar" : "reminder"
            guard ["calendar", "reminder"].contains(kind) else { throw AssistantError.invalidTool("Choose calendar or reminder.") }
            let existing = try planning.validateChange(args, kind: kind, settings: settings)
            if let existing { guard seenItems.insert(kind + ":" + existing.id).inserted else { throw AssistantError.invalidTool("An item can appear only once in a batch; combine its changes first.") } }
            _ = try PlanningRecurrence.rule(args["recurrence"])
            let title = args["title"]?.stringValue ?? existing?.title ?? ""
            var lines = ["\(index + 1). " + operation.replacingOccurrences(of: "_", with: " ").capitalized, title]
            if operation == "save_calendar_event" {
                let start = try PlanningService.date(args["start"]?.stringValue ?? ""), end = try PlanningService.date(args["end"]?.stringValue ?? "")
                guard start < end, end.timeIntervalSince(start) <= 31 * 86400 else { throw AssistantError.invalidTool("Use a valid event range of at most 31 days.") }
                lines.append(start.formatted(date: .abbreviated, time: .shortened) + " – " + end.formatted(date: .abbreviated, time: .shortened))
                if args["all_day"] == .bool(true) { lines.append("All-day · exclusive end date") }
            } else if let due = args["due"]?.stringValue, !due.isEmpty { lines.append("Due " + (try PlanningService.date(due)).formatted(date: .abbreviated, time: .shortened)) }
            if let recurrence = PlanningRecurrence.description(args) { lines.append(recurrence) }
            if let scope = args["scope"]?.stringValue, !scope.isEmpty { lines.append("Scope: " + scope.replacingOccurrences(of: "_", with: " ")) }
            if let source = planning.sources.first(where: { $0.id == (args["source_id"]?.stringValue ?? existing?.sourceID) }) { lines.append("In " + source.title) }
            if let location = args["location"]?.stringValue, !location.isEmpty { lines.append(location) }
            if let notes = args["notes"]?.stringValue, !notes.isEmpty { lines.append(notes) }
            previews.append(lines.joined(separator: "\n")); prepared.append((operation, kind, args))
            steps.append(.object(["index": .number(Double(index + 1)), "operation": .string(operation), "title": .string(title), "status": .string("not_started")]))
        }
        let approval = try await reviewNativeAction(.init(kind: .approval, title: "Review \(changes.count) planning changes", detail: previews.joined(separator: "\n\n") + "\n\nEach change is recorded separately. If one cannot finish, the others may still complete.", arguments: call.arguments))
        guard approval == "approved" else { return .init(callID: call.id, name: call.name, succeeded: false, output: .object(["status": .string("cancelled"), "changed": .bool(false)])) }
        try await store.saveBatchAction(batchID, conversationID: chatID, steps: steps)
        for (index, operation) in prepared.enumerated() {
            try Task.checkCancellation()
            var step = steps[index].objectValue!; step["status"] = .string("started"); steps[index] = .object(step)
            try await store.saveBatchAction(batchID, conversationID: chatID, steps: steps)
            do {
                guard destination == nil || settings.planningConnectedAccess else { throw AssistantError.invalidTool("Planning access was revoked.") }
                let receipt: JSONValue
                if operation.0 == "delete_planning_item" { receipt = try planning.delete(operation.2, kind: operation.1, settings: settings) }
                else {
                    let item = try planning.save(operation.2, kind: operation.1, settings: settings, completeOnly: operation.0 == "complete_reminder")
                    receipt = .object(["status": .string(operation.0 == "complete_reminder" ? "completed" : "saved"), "verified_in_event_store": .bool(true), "item": item.modelValue])
                }
                step["status"] = receipt["status"]; step["receipt"] = receipt
            } catch {
                step["status"] = .string(error is PlanningWriteUnverified ? "outcome_unknown" : "failed")
                step["explanation"] = .string(error.localizedDescription)
            }
            steps[index] = .object(step); try await store.saveBatchAction(batchID, conversationID: chatID, steps: steps)
        }
        await planning.refreshHome(settings: settings)
        let value = try await store.batchAction(batchID, conversationID: chatID)!
        return .init(callID: call.id, name: call.name, succeeded: !steps.contains(where: { ["failed", "outcome_unknown"].contains($0["status"]?.stringValue ?? "") }), output: value)
    }
}
