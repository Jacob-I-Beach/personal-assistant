import AssistantCore
import CoreText
import MarkdownUI
import UIKit

@MainActor
enum PDFDocumentWriter {
    static func make(title: String, markdown: String) throws -> (Data, String) {
        guard title.count <= 200, markdown.utf8.count <= 100_000 else { throw AssistantError.invalidTool("Use a title up to 200 characters and a PDF body up to 100 KB.") }
        let body = MarkdownContent(markdown).renderPlainText()
        let text = title.isEmpty ? body : title + "\n\n" + body
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4; paragraph.paragraphSpacing = 10
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.black, .paragraphStyle: paragraph])
        if !title.isEmpty { attributed.addAttribute(.font, value: UIFont.systemFont(ofSize: 23, weight: .semibold), range: NSRange(location: 0, length: (title as NSString).length)) }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        var offset = 0, page = 0, truncated = false
        let data = renderer.pdfData { context in
            repeat {
                context.beginPage(); page += 1
                let cg = context.cgContext; cg.saveGState()
                cg.translateBy(x: 0, y: 792); cg.scaleBy(x: 1, y: -1)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), CGPath(rect: CGRect(x: 48, y: 54, width: 516, height: 684), transform: nil), nil)
                CTFrameDraw(frame, cg); cg.restoreGState()
                let count = CTFrameGetVisibleStringRange(frame).length
                offset += count
                ("\(page)" as NSString).draw(at: CGPoint(x: 298, y: 756), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.gray])
                if count == 0 && offset < attributed.length { truncated = true; break }
                if page >= 100 && offset < attributed.length { truncated = true; break }
            } while offset < attributed.length
        }
        guard !truncated else { throw AssistantError.invalidTool("The PDF exceeded the 100-page layout limit. Split the document into smaller parts.") }
        return (data, text)
    }
}
