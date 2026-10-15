import Foundation

/// Small deterministic lexical normalization. This does not claim semantic
/// embedding search; source permission and validity filters run before ranking.
public enum RetrievalTerms {
    private static let stop: Set<String> = ["the", "and", "for", "this", "that", "with", "from", "what", "when", "where", "which", "can", "could", "would", "should", "have", "does", "about", "please", "tell", "your", "you", "are", "was", "were", "how", "my", "me", "our", "use"]
    private static let aliases = [["car", "cars", "automobile", "vehicle"], ["food", "diet", "eat", "eating", "meal", "meals"], ["meeting", "meetings", "appointment", "appointments"], ["job", "occupation", "profession"], ["exercise", "workout", "fitness"], ["units", "metric", "imperial", "measurement"]]
    public static func terms(_ text: String) -> Set<String> {
        var result = Set(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 && !stop.contains($0) })
        for group in aliases where !result.isDisjoint(with: group) { result.formUnion(group) }
        return result
    }
    public static func score(_ content: String, query: Set<String>) -> Int { terms(content).intersection(query).count }
}
