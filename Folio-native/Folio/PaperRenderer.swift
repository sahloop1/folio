import UIKit
import CoreGraphics
import FolioCore

enum PaperRenderer {
    static func draw(_ page: Page, in context: CGContext, assetRoot: URL, labels: Bool = true) {
        let rect = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        context.setFillColor(UIColor(argb: page.color).cgColor); context.fill(rect)
        if !page.pdf.isEmpty,
           let pdf = CGPDFDocument(assetRoot.appendingPathComponent("pdfs/" + page.pdf) as CFURL),
           let source = pdf.page(at: page.pdfPage + 1) {
            context.saveGState(); context.translateBy(x: 0, y: rect.height); context.scaleBy(x: 1, y: -1)
            context.concatenate(source.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(source); context.restoreGState()
        } else if page.pdf.isEmpty {
            let light = UIColor(argb: page.color).cgColor.components?.prefix(3).reduce(0, +) ?? 2
            let line = light < 1.3 ? UIColor.white.withAlphaComponent(0.17) : UIColor(red: 0.37, green: 0.46, blue: 0.55, alpha: 0.23)
            context.setStrokeColor(line.cgColor); context.setFillColor(line.cgColor); context.setLineWidth(0.9)
            let step = page.lineSpacing, bottom = page.height - (page.paper == .cornell ? 250 : 65)
            if page.paper == .dotted {
                for y in stride(from: page.firstLine, through: bottom, by: step) {
                    for x in stride(from: 48.0, through: page.width - 48, by: step) { context.fillEllipse(in: CGRect(x: x, y: y, width: 2, height: 2)) }
                }
            } else if page.paper != .blank {
                for y in stride(from: page.firstLine, through: bottom, by: step) {
                    let left = page.paper == .cornell ? page.width * 0.27 : 50
                    context.move(to: CGPoint(x: left, y: y)); context.addLine(to: CGPoint(x: page.width - 50, y: y))
                }
                if page.paper == .grid {
                    for x in stride(from: 50.0, through: page.width - 50, by: step) { context.move(to: CGPoint(x: x, y: page.firstLine)); context.addLine(to: CGPoint(x: x, y: bottom)) }
                }
                context.strokePath()
            }
            if page.paper == .ruled || page.paper == .cornell {
                context.setStrokeColor(UIColor.systemRed.withAlphaComponent(0.25).cgColor)
                let x = page.paper == .cornell ? page.width * 0.27 : 92
                context.move(to: CGPoint(x: x, y: 65)); context.addLine(to: CGPoint(x: x, y: bottom))
                if page.paper == .cornell { context.move(to: CGPoint(x: 50, y: bottom)); context.addLine(to: CGPoint(x: page.width - 50, y: bottom)) }
                context.strokePath()
            }
        }
        if labels {
            for label in page.labels { drawText(label, page: page) }
            for note in page.recordings {
                let title = "▶  " + note.text("title", "Voice note")
                (title as NSString).draw(at: CGPoint(x: note.number("x", 110), y: note.number("y", 130)),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 24, weight: .medium), .foregroundColor: UIColor.systemBlue])
            }
        }
    }
    static func textRect(_ text: [String: JSONValue], page: Page) -> CGRect {
        let x = text.number("x", 80), y = text.number("y", 100)
        let width = text.number("width") > 0 ? text.number("width") : max(100, page.width - x - 60)
        let height = (text.text("text") as NSString).boundingRect(with: CGSize(width: width, height: 100_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(text), context: nil).height
        return CGRect(x: x, y: y, width: width, height: max(32, ceil(height) + 4))
    }
    static func attributes(_ text: [String: JSONValue]) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle(); paragraph.baseWritingDirection = .natural
        if text.number("lineHeight") > 0 { paragraph.minimumLineHeight = text.number("lineHeight"); paragraph.maximumLineHeight = text.number("lineHeight") }
        return [.font: UIFont.systemFont(ofSize: text.number("size", 24)),
                .foregroundColor: UIColor(argb: text.number("color", -14340028)), .paragraphStyle: paragraph]
    }
    static func drawText(_ text: [String: JSONValue], page: Page) {
        (text.text("text") as NSString).draw(with: textRect(text, page: page), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(text), context: nil)
    }
    static func contentBottom(_ page: Page) -> Double {
        var bottom = Double(InkBridge.drawing(for: page).bounds.maxY)
        if !bottom.isFinite { bottom = 0 }
        for text in page.labels + (page.body.isEmpty ? [] : [page.body]) {
            if !text.text("text").isEmpty { bottom = max(bottom, textRect(text, page: page).maxY) }
        }
        for recording in page.recordings { bottom = max(bottom, recording.number("y", 130) + 50) }
        return bottom
    }
}
