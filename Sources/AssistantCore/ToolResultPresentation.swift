import Foundation

/// Deterministic receipt formatting. No model is asked to paraphrase or re-calculate tool output.
public enum ToolResultPresentation {
    public struct Field: Equatable, Sendable, Identifiable {
        public var label: String
        public var value: String
        public var id: String { label }
    }
    public static func fields(_ value: JSONValue) -> [Field] {
        if let object = value.objectValue {
            return object.keys.sorted().prefix(24).map { Field(label: label($0), value: display(object[$0]!)) }
        }
        return [Field(label: "Result", value: display(value))]
    }
    public static func label(_ key: String) -> String {
        let spaced = key.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
        guard let first = spaced.first else { return "Value" }
        return String(first).uppercased() + spaced.dropFirst()
    }
    public static func display(_ value: JSONValue) -> String {
        switch value {
        case .string(let text): return text.isEmpty ? "Empty text" : String(text.prefix(300))
        case .number(let number):
            guard number.isFinite else { return "Non-finite number" }
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.numberStyle = (abs(number) > 0 && abs(number) < 0.000001) || abs(number) >= 1e12 ? .scientific : .decimal
            formatter.usesSignificantDigits = true; formatter.maximumSignificantDigits = 10
            return formatter.string(from: NSNumber(value: number)) ?? String(number)
        case .bool(let flag): return flag ? "Yes" : "No"
        case .null: return "No value"
        case .array(let values):
            guard !values.isEmpty else { return "No items" }
            if values.allSatisfy({ $0.objectValue == nil && $0.arrayValue == nil }) {
                let preview = values.prefix(6).map(display).joined(separator: " · ")
                return preview + (values.count > 6 ? " · +\(values.count - 6) more" : "")
            }
            return "\(values.count) items"
        case .object(let object): return "\(object.count) fields"
        }
    }
    public static func arguments(of call: ToolCall?) -> JSONValue? {
        guard let call else { return nil }
        return call.name == "use_tool" ? (call.arguments["arguments_json"]?.stringValue.flatMap { try? JSONValue.parse($0) }) : call.arguments
    }
}
