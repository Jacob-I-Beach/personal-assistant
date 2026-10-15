import Foundation

public enum SurfaceKind: String, Codable, CaseIterable, Sendable { case metrics, chart, table, comparison, checklist, timeline, scenario }

/// A bounded declarative document. No HTML, scripts, URLs or native action authority.
public struct WorkSurface: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var conversationID: UUID
    public var sourceCallID: String
    public var lastMutationCallID: String?
    public var spec: JSONValue
    public var createdAt = Date()
    public var updatedAt = Date()
    public var revision = 1
    public var selectedIDs: Set<String> = []
    public var inputValues: [String: Double] = [:]
    public var containsLocalOnlyContext: Bool
    public var containsHealthData: Bool
    public var dataCallID: String?
    public var kind: SurfaceKind { SurfaceKind(rawValue: spec["kind"]!.stringValue!)! }
    public var title: String { spec["title"]!.stringValue! }
    public var rows: [JSONValue] { spec["data"]?.arrayValue ?? [] }
    public var inputs: [JSONValue] { spec["inputs"]?.arrayValue ?? [] }

    public init(conversationID: UUID, sourceCallID: String, spec: JSONValue, localOnly: Bool, health: Bool, dataCallID: String? = nil) throws {
        try Self.validate(spec)
        self.conversationID = conversationID; self.sourceCallID = sourceCallID; self.spec = spec
        self.containsLocalOnlyContext = localOnly; self.containsHealthData = health; self.dataCallID = dataCallID
        for input in inputs { inputValues[input["id"]!.stringValue!] = input["value"]!.numberValue! }
        if kind == .checklist { selectedIDs = Set(rows.filter { $0["checked"] == .bool(true) }.compactMap { $0["id"]?.stringValue }) }
    }
    public static func validate(_ spec: JSONValue) throws {
        func reject() -> AssistantError { .invalidTool("The surface needs a supported kind, a short title, and bounded data matching its schema. Use get_surface_schema for the exact format.") }
        guard try spec.jsonString().utf8.count <= 40_000, let object = spec.objectValue,
              Set(object.keys).isSubset(of: ["kind", "title", "subtitle", "data", "columns", "style", "inputs", "expression", "unit", "result_label"]),
              let kind = spec["kind"]?.stringValue.flatMap(SurfaceKind.init(rawValue:)),
              let title = spec["title"]?.stringValue, (1...120).contains(title.count) else { throw reject() }
        for key in ["subtitle", "unit", "result_label"] {
            if let value = object[key], value.stringValue == nil || value.stringValue!.count > 400 { throw reject() }
        }
        let rows = spec["data"]?.arrayValue ?? []
        guard rows.count <= 200 else { throw reject() }
        if kind != .scenario && rows.isEmpty { throw reject() }
        let columns = spec["columns"]?.arrayValue?.compactMap(\.stringValue) ?? []
        if kind == .table {
            guard (1...8).contains(columns.count), Set(columns).count == columns.count, columns.allSatisfy({ !$0.isEmpty && $0.count <= 60 }),
                  rows.allSatisfy({ row in guard let values = row.arrayValue else { return false }; return values.count == columns.count && values.allSatisfy(Self.validCell) }) else { throw reject() }
        } else if kind == .scenario {
            guard let inputs = spec["inputs"]?.arrayValue, (1...6).contains(inputs.count), let expression = spec["expression"] else { throw reject() }
            var values: [String: Double] = [:]
            for input in inputs {
                guard let value = input.objectValue, Set(value.keys) == ["id", "label", "value", "min", "max", "step"],
                      let id = input["id"]?.stringValue, !id.isEmpty, id.count <= 40, values[id] == nil,
                      let label = input["label"]?.stringValue, !label.isEmpty, label.count <= 80,
                      let initial = input["value"]?.numberValue, let low = input["min"]?.numberValue, let high = input["max"]?.numberValue, let step = input["step"]?.numberValue,
                      [initial, low, high, step].allSatisfy({ $0.isFinite && abs($0) <= 1e12 }), low < high, step > 0, step <= high - low, (high - low) / step <= 10_000, (low...high).contains(initial) else { throw reject() }
                values[id] = initial
            }
            _ = try evaluate(expression, inputs: values)
        } else {
            var ids = Set<String>()
            for row in rows {
                guard let fields = row.objectValue, fields.count <= 5, let label = row["label"]?.stringValue, (1...200).contains(label.count), fields.values.allSatisfy(Self.validCell) else { throw reject() }
                switch kind {
                case .chart:
                    guard Set(fields.keys).isSubset(of: ["label", "value", "series"]), let value = row["value"]?.numberValue, value.isFinite else { throw reject() }
                case .metrics:
                    guard Set(fields.keys).isSubset(of: ["label", "value", "unit", "detail"]), row["value"] != nil else { throw reject() }
                case .comparison, .checklist:
                    guard Set(fields.keys).isSubset(of: ["id", "label", "detail", "checked"]), let id = row["id"]?.stringValue, !id.isEmpty, id.count <= 80, ids.insert(id).inserted else { throw reject() }
                    if let checked = row["checked"], checked != .bool(true) && checked != .bool(false) { throw reject() }
                case .timeline:
                    guard Set(fields.keys).isSubset(of: ["label", "detail", "status"]), row["status"] == nil || ["pending", "in_progress", "completed"].contains(row["status"]!.stringValue ?? "") else { throw reject() }
                default: break
                }
            }
        }
        if let style = spec["style"], !["bar", "line", "area"].contains(style.stringValue ?? "") { throw reject() }
    }
    private static func validCell(_ value: JSONValue) -> Bool {
        switch value { case .string(let text): return text.count <= 600; case .number(let number): return number.isFinite && abs(number) <= 1e15; case .bool, .null: return true; default: return false }
    }
    public static func evaluate(_ expression: JSONValue, inputs: [String: Double]) throws -> Double {
        var nodes = 0
        func visit(_ value: JSONValue, depth: Int) throws -> Double {
            nodes += 1
            guard nodes <= 48, depth <= 8 else { throw AssistantError.invalidTool("This formula is too complex for an interactive surface.") }
            let result: Double
            if let number = value.numberValue { result = number }
            else if let object = value.objectValue, Set(object.keys) == ["input"], let id = value["input"]?.stringValue, let number = inputs[id] { result = number }
            else {
                guard let object = value.objectValue, Set(object.keys) == ["op", "args"], let op = value["op"]?.stringValue,
                      let args = value["args"]?.arrayValue, (2...6).contains(args.count) else { throw AssistantError.invalidTool("Use numbers, {input: id}, or {op: add/subtract/multiply/divide/power/min/max, args: [...]}.") }
                let numbers = try args.map { try visit($0, depth: depth + 1) }
                switch op {
                case "add": result = numbers.reduce(0, +)
                case "multiply": result = numbers.reduce(1, *)
                case "min": result = numbers.min()!
                case "max": result = numbers.max()!
                case "subtract" where numbers.count == 2: result = numbers[0] - numbers[1]
                case "divide" where numbers.count == 2 && numbers[1] != 0: result = numbers[0] / numbers[1]
                case "power" where numbers.count == 2 && abs(numbers[1]) <= 16: result = pow(numbers[0], numbers[1])
                default: throw AssistantError.invalidTool("This formula is undefined for these inputs.")
                }
            }
            guard result.isFinite, abs(result) <= 1e15 else { throw AssistantError.invalidTool("The result exceeds this surface's numeric range.") }
            return result
        }
        return try visit(expression, depth: 0)
    }
    public func summary() throws -> JSONValue {
        var value: [String: JSONValue] = ["surface_id": .string(id.uuidString), "kind": .string(kind.rawValue), "title": .string(title), "revision": .number(Double(revision)), "selected_ids": .array(selectedIDs.sorted().map(JSONValue.string)), "inputs": .object(inputValues.mapValues(JSONValue.number)), "updated_at": .string(ISO8601DateFormatter().string(from: updatedAt))]
        if kind == .scenario, let expression = spec["expression"] {
            do { value["calculated_result"] = .number(try Self.evaluate(expression, inputs: inputValues)) }
            catch { value["calculation_error"] = .string(error.localizedDescription) }
        }
        return .object(value)
    }
}

extension LocalStore {
    private func rememberSurface(_ surface: WorkSurface) throws {
        try database.execute("CREATE TABLE IF NOT EXISTS surface_history(id TEXT NOT NULL,revision INTEGER NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(id,revision))")
        if let data = try database.execute("SELECT payload FROM surface_history WHERE id=? AND revision=?", [.text(surface.id.uuidString), .integer(Int64(surface.revision))]).first?[0].data {
            // Recover only the identical orphaned current revision left by an
            // older nontransactional save. A conflicting history stays intact.
            guard try Self.decode(WorkSurface.self, data) == surface else { throw AssistantError.invalidTool("This surface's saved history conflicts with its current revision.") }
            return
        }
        try database.execute("INSERT INTO surface_history(id,revision,payload) VALUES(?,?,?)", [.text(surface.id.uuidString), .integer(Int64(surface.revision)), .blob(try Self.encode(surface))])
    }
    public func reviseSurface(id: UUID, conversationID: UUID, expectedRevision: Int, replacement: WorkSurface) throws -> WorkSurface {
        guard let original = try surfaces(conversationID: conversationID).first(where: { $0.id == id }), original.revision == expectedRevision,
              replacement.conversationID == conversationID else { throw AssistantError.invalidTool("This working object changed. Read the current revision before updating it.") }
        try WorkSurface.validate(replacement.spec)
        var updated = replacement
        updated.id = original.id; updated.createdAt = original.createdAt; updated.sourceCallID = original.sourceCallID
        updated.lastMutationCallID = replacement.sourceCallID
        updated.revision = original.revision + 1; updated.updatedAt = Date()
        updated.containsLocalOnlyContext = original.containsLocalOnlyContext || replacement.containsLocalOnlyContext
        updated.containsHealthData = original.containsHealthData || replacement.containsHealthData
        if updated.kind == original.kind {
            updated.selectedIDs = original.selectedIDs.intersection(Set(updated.rows.compactMap { $0["id"]?.stringValue }))
            for input in updated.inputs {
                let key = input["id"]!.stringValue!
                if let value = original.inputValues[key], let low = input["min"]?.numberValue, let high = input["max"]?.numberValue, (low...high).contains(value) { updated.inputValues[key] = value }
            }
        }
        try database.transaction {
            try rememberSurface(original)
            try database.execute("UPDATE work_surfaces SET payload=? WHERE id=?", [.blob(try Self.encode(updated)), .text(id.uuidString)])
        }
        return updated
    }
    private func prepareSurfaces() throws { try database.execute("CREATE TABLE IF NOT EXISTS work_surfaces(id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE, payload BLOB NOT NULL)") }
    public func surfaces(conversationID: UUID, remote: Bool = false) throws -> [WorkSurface] {
        try prepareSurfaces()
        let conversation = try loadConversation(conversationID)
        let activeCalls = Set(conversation.messages.flatMap(\.toolCalls).map(\.id))
        return try database.execute("SELECT payload FROM work_surfaces WHERE conversation_id = ?", [.text(conversationID.uuidString)])
            .map { row in let surface = try Self.decode(WorkSurface.self, row[0].data!); try WorkSurface.validate(surface.spec); return surface }
            .filter { activeCalls.contains($0.sourceCallID) && !conversation.excludedSurfaceIDs.contains($0.id) && (!remote || (!$0.containsLocalOnlyContext && (!$0.containsHealthData || conversation.containsHealthData))) }
            .sorted { $0.createdAt < $1.createdAt }
    }
    public func saveSurface(_ surface: WorkSurface) throws {
        try prepareSurfaces(); try WorkSurface.validate(surface.spec)
        guard try database.execute("SELECT id FROM work_surfaces WHERE id = ?", [.text(surface.id.uuidString)]).isEmpty else { throw AssistantError.invalidTool("This surface already exists.") }
        try database.execute("INSERT INTO work_surfaces(id,conversation_id,payload) VALUES(?,?,?)", [.text(surface.id.uuidString), .text(surface.conversationID.uuidString), .blob(try Self.encode(surface))])
    }
    public func interactWithSurface(id: UUID, conversationID: UUID, expectedRevision: Int, selected: Set<String>, inputs: [String: Double]) throws -> WorkSurface {
        guard var surface = try surfaces(conversationID: conversationID).first(where: { $0.id == id }), surface.revision == expectedRevision else { throw AssistantError.provider("This working surface changed. Reopen it before editing.") }
        let allowed = Set(surface.rows.compactMap { $0["id"]?.stringValue })
        guard selected.isSubset(of: allowed), (surface.kind == .checklist || selected.count <= 1), Set(inputs.keys) == Set(surface.inputValues.keys) else { throw AssistantError.invalidTool("The selection is outside this surface.") }
        for input in surface.inputs {
            guard let number = inputs[input["id"]!.stringValue!], SurfaceInput.accepts(number, specification: input) else { throw AssistantError.invalidTool("A parameter is outside its allowed range.") }
        }
        let previous = surface
        surface.selectedIDs = selected; surface.inputValues = inputs; surface.updatedAt = Date(); surface.revision += 1
        try database.transaction {
            try rememberSurface(previous)
            try database.execute("UPDATE work_surfaces SET payload = ? WHERE id = ?", [.blob(try Self.encode(surface)), .text(id.uuidString)])
        }
        return surface
    }
}
