import AssistantCore
import Foundation

@main
struct CaptureReplay {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            print("Usage: capture-replay /path/to/observation.json")
            return
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let observation = try decoder.decode(CaptureObservation.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        try observation.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let depth = observation.depth {
            print(String(decoding: try encoder.encode(depth.centerSummary()), as: UTF8.self))
        } else { print("This capture has no depth data.") }
        print("Recognized text (source content):")
        observation.recognizedText.forEach { print($0) }
    }
}
