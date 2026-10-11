import AssistantCore
import EventKit
import Foundation

@MainActor enum PlanningRecurrence {
    static func rule(_ value: JSONValue?) throws -> [EKRecurrenceRule]? {
        guard let value, value != .null else { return nil }
        guard let frequency = value["frequency"]?.stringValue else { throw AssistantError.invalidTool("Choose a recurrence frequency.") }
        if frequency == "none" { return [] }
        let frequencies: [String: EKRecurrenceFrequency] = ["daily": .daily, "weekly": .weekly, "monthly": .monthly, "yearly": .yearly]
        guard let frequency = frequencies[frequency], let interval = value["interval"]?.numberValue.flatMap(Int.init(exactly:)), (1...30).contains(interval) else { throw AssistantError.invalidTool("Use daily, weekly, monthly or yearly recurrence and an interval from 1 to 30.") }
        let count = value["count"]?.numberValue.flatMap(Int.init(exactly:))
        let until = value["until"]?.stringValue
        guard count == nil || until == nil else { throw AssistantError.invalidTool("End a recurrence by count or date, not both.") }
        let end: EKRecurrenceEnd?
        if let count { guard (1...366).contains(count) else { throw AssistantError.invalidTool("Use 1–366 occurrences.") }; end = EKRecurrenceEnd(occurrenceCount: count) }
        else if let until { end = EKRecurrenceEnd(end: try PlanningService.date(until)) }
        else { end = nil }
        return [EKRecurrenceRule(recurrenceWith: frequency, interval: interval, end: end)]
    }
    static func description(_ args: JSONValue) -> String? {
        guard let recurrence = args["recurrence"], recurrence != .null, let frequency = recurrence["frequency"]?.stringValue else { return nil }
        if frequency == "none" { return "Does not repeat" }
        let interval = Int(recurrence["interval"]?.numberValue ?? 1)
        let ending = recurrence["count"]?.numberValue.map { " · \(Int($0)) occurrences" } ?? recurrence["until"]?.stringValue.map { " · until \($0)" } ?? " · no end date"
        return "Repeats \(frequency), every \(interval) interval(s)" + ending
    }
    static func span(_ args: JSONValue) -> EKSpan { args["scope"] == .string("this_and_future") ? .futureEvents : .thisEvent }
    nonisolated static func augment(_ tool: ToolDefinition, calendar: Bool) -> ToolDefinition {
        var fields = tool.parameters["properties"]?.objectValue ?? [:]
        let nullableText: JSONValue = .object(["type": .array([.string("string"), .string("null")])])
        fields["time_zone"] = nullableText
        fields["scope"] = .object(["type": .array([.string("string"), .string("null")]), "enum": .array([.null] + (calendar ? ["this_event", "this_and_future"] : ["series"]).map(JSONValue.string)), "description": .string("Required when changing an existing recurring item; null for a new or nonrecurring item.")])
        if calendar {
            fields["all_day"] = .object(["type": .array([.string("boolean"), .string("null")]), "description": .string("True for an all-day event. Start and exclusive end must be midnight in time_zone. Null preserves the existing setting.")])
            fields["occurrence_start"] = .object(["type": .array([.string("string"), .string("null")]), "description": .string("Exact original occurrence start from read_schedule when editing a recurring event; separate from the proposed new start.")])
        }
        fields["recurrence"] = .object(["type": .array([.string("object"), .string("null")]), "description": .string("Null preserves existing recurrence. none removes recurrence. Daily/weekly/monthly/yearly start on the supplied event or due date."), "additionalProperties": .bool(false), "required": .array(["frequency", "interval", "count", "until"].map(JSONValue.string)), "properties": .object([
            "frequency": .object(["type": .string("string"), "enum": .array(["none", "daily", "weekly", "monthly", "yearly"].map(JSONValue.string))]),
            "interval": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(30)]),
            "count": .object(["type": .array([.string("integer"), .string("null")]), "minimum": .number(1), "maximum": .number(366)]),
            "until": nullableText
        ])])
        return ToolDefinition(name: tool.name, description: tool.description, parameters: .object(["type": .string("object"), "properties": .object(fields), "required": .array(fields.keys.sorted().map(JSONValue.string)), "additionalProperties": .bool(false)]))
    }
}
