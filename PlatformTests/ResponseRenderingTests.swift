import AssistantCore
import SwiftUI
import Textual
import XCTest
@testable import PersonalAssistant

@MainActor
final class ResponseRenderingTests: XCTestCase {
    func testInlineAndBlockMathReachTheNativeMathRenderer() throws {
        let source = #"With \(\theta\): \[D \approx d\theta \qquad C \approx \pi d\theta.\]"#
        let parsed = try AttributedStringMarkdownParser(baseURL: nil, syntaxExtensions: [.math])
            .attributedString(for: MathMarkdown.normalize(source))
        let math = parsed.runs.compactMap { $0.textual.attachment?.description }
        XCTAssertEqual(math, [#"$\theta$"#, #"$$D \approx d\theta \qquad C \approx \pi d\theta.$$"#])
        XCTAssertFalse(String(parsed.characters).contains(#"\approx"#))
    }
    func testMathAdapterPreservesSubscriptsAndCode() throws {
        let tick = String(UnicodeScalar(96))
        let source = #"Value \(x_{i}^2 + \frac{1}{2}\)."# + "\n\n" + tick + #"\(not_math\)"# + tick
        let parsed = try AttributedStringMarkdownParser(baseURL: nil, syntaxExtensions: [.math])
            .attributedString(for: MathMarkdown.normalize(source))
        let math = parsed.runs.compactMap { $0.textual.attachment?.description }
        XCTAssertEqual(math, [#"$x_{i}^2 + \frac{1}{2}$"#])
        XCTAssertTrue(String(parsed.characters).contains(#"\(not_math\)"#))
    }
}
