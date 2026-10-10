import Foundation

/// Adapts the common model-produced \(…\) and \[…\] delimiters to Textual's math syntax.
/// Complete code fences and inline code are left byte-for-byte unchanged.
public enum MathMarkdown {
    public static func normalize(_ source: String) -> String {
        let chars = Array(source)
        var result = "", index = 0
        while index < chars.count {
            let ch = chars[index]
            if ch == "\u{0060}" || (ch == "~" && index + 2 < chars.count && chars[index + 1] == "~" && chars[index + 2] == "~") {
                var end = index
                while end < chars.count && chars[end] == ch { end += 1 }
                let length = end - index
                // Copy a matching fence/span, or the remaining unfinished streamed code.
                var cursor = end, close: Int?
                while cursor < chars.count {
                    if chars[cursor] == ch {
                        var runEnd = cursor
                        while runEnd < chars.count && chars[runEnd] == ch { runEnd += 1 }
                        if runEnd - cursor == length { close = runEnd; break }
                        cursor = runEnd
                    } else { cursor += 1 }
                }
                let upper = close ?? chars.count
                result += String(chars[index..<upper]); index = upper; continue
            }
            if ch == "\\", index + 1 < chars.count, chars[index + 1] == "\\" {
                result += "\\\\"; index += 2; continue
            }
            if ch == "\\", index + 1 < chars.count, chars[index + 1] == "(" || chars[index + 1] == "[" {
                let block = chars[index + 1] == "[", closer: Character = block ? "]" : ")"
                var end = index + 2
                while end + 1 < chars.count && !(chars[end] == "\\" && chars[end + 1] == closer) { end += 1 }
                if end + 1 < chars.count {
                    let latex = String(chars[(index + 2)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    // Markdown parses before math, so protect TeX punctuation from Markdown escapes/emphasis.
                    let escaped = latex.reduce(into: "") { output, character in
                        if "\\*_{}[]".contains(character) { output.append("\\") }
                        output.append(character)
                    }
                    result += block ? "\n\n$$\(escaped)$$\n\n" : "$\(escaped)$"
                    index = end + 2; continue
                }
            }
            result.append(ch); index += 1
        }
        return result
    }
}
