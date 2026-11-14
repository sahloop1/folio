import UIKit
import PDFKit
import PencilKit
import AVFoundation
import FolioCore
#if canImport(FoundationXML)
import FoundationXML
#endif

enum NativeDocuments {
    static func prepare(url: URL, profile: String, folder: String) throws -> PreparedImport {
        let resource = try url.resourceValues(forKeys: [.fileSizeKey])
        try require((resource.fileSize ?? 0) <= ZIPArchive.libraryLimit + 64 * 1024 * 1024, "This file is too large to import. Split the library into smaller notebooks.")
        let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
        let name = url.deletingPathExtension().lastPathComponent
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let provider = CGDataProvider(data: bytes as CFData), let pdf = CGPDFDocument(provider) else { throw FolioError.invalid("This PDF cannot be opened.") }
            try require(!pdf.isEncrypted && (1...1000).contains(pdf.numberOfPages) && bytes.count <= ZIPArchive.entryLimit, "Choose an unlocked PDF of up to 1,000 pages and 200 MB.")
            let filename = Identity.new() + ".pdf"
            var notebook = Notebook(title: name, profile: profile, folder: folder)
            notebook.raw["sourceFormat"] = .string("pdf")
            notebook.pages = try (1...pdf.numberOfPages).map { index in
                guard let source = pdf.page(at: index) else { throw FolioError.invalid("A PDF page cannot be opened.") }
                let box = source.getBoxRect(.cropBox), rotated = source.rotationAngle % 180 != 0
                let width = rotated ? box.height : box.width, height = rotated ? box.width : box.height
                try require(width > 0 && height > 0 && (100...10_000).contains(1000 * height / width), "A PDF page has unsupported dimensions.")
                var page = Page(paper: .blank)
                page.pdf = filename; page.raw["pdfPage"] = .number(Double(index - 1)); page.height = 1000 * height / width
                page.color = Double(Int32(bitPattern: 0xffffffff))
                return page
            }
            return PreparedImport(notebooks: [notebook], attachments: ["pdfs/" + filename: bytes], preferences: [:], isLibrary: false)
        case "docx", "txt":
            let text: String
            if url.pathExtension.lowercased() == "docx" {
                let entries = try ZIPArchive.read(bytes, limit: 64 * 1024 * 1024)
                guard let document = entries["word/document.xml"], document.count <= 10 * 1024 * 1024 else { throw FolioError.invalid("This Word file has no supported document body.") }
                text = try WordTextParser.read(document)
            } else {
                guard let decoded = String(data: bytes, encoding: .utf8), bytes.count <= 10 * 1024 * 1024 else { throw FolioError.invalid("Choose a UTF-8 text file smaller than 10 MB.") }
                text = decoded
            }
            try require(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "This document has no editable text. Import a PDF to retain images and page appearance.")
            var notebook = Notebook(title: name, profile: profile, folder: folder)
            notebook.raw["sourceFormat"] = .string(url.pathExtension.lowercased())
            notebook.pages = try paginate(text)
            return PreparedImport(notebooks: [notebook], attachments: [:], preferences: [:], isLibrary: false)
        default:
            let prepared = try LibraryArchive.prepare(bytes)
            try validate(prepared)
            return prepared
        }
    }

    static func validate(_ prepared: PreparedImport) throws {
        var counts: [String: Int] = [:]
        for (name, bytes) in prepared.attachments {
            if name.hasPrefix("pdfs/") {
                guard let provider = CGDataProvider(data: bytes as CFData), let pdf = CGPDFDocument(provider), !pdf.isEncrypted else { throw FolioError.invalid("A PDF attachment cannot be opened.") }
                counts[(name as NSString).lastPathComponent] = pdf.numberOfPages
            } else {
                let player = try AVAudioPlayer(data: bytes)
                try require(player.duration > 0 && player.duration <= 86_400, "A recording cannot be played or exceeds 24 hours.")
            }
        }
        for notebook in prepared.notebooks {
            for page in notebook.pages where !page.pdf.isEmpty {
                try require(page.pdfPage < counts[page.pdf, default: 0], "A notebook points to a missing PDF page.")
            }
        }
    }

    static func paginate(_ text: String) throws -> [Page] {
        let paragraph = NSMutableParagraphStyle(); paragraph.minimumLineHeight = 38; paragraph.maximumLineHeight = 38
        let storage = NSTextStorage(string: text, attributes: [.font: UIFont.systemFont(ofSize: 24), .paragraphStyle: paragraph])
        let layout = NSLayoutManager(); storage.addLayoutManager(layout)
        let source = text as NSString
        var pages: [Page] = [], consumed = 0
        while consumed < source.length {
            var page = Page(); var body = page.newBody()
            body["lineHeight"] = .number(38)
            let container = NSTextContainer(size: CGSize(width: body.number("width"), height: page.height - body.number("y") - 80))
            container.lineFragmentPadding = 0; layout.addTextContainer(container)
            let glyphs = layout.glyphRange(for: container), range = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            try require(range.length > 0 && range.location == consumed && pages.count < 5000, "The text cannot fit in the supported notebook size.")
            body["text"] = .string(source.substring(with: range)); page.body = body; pages.append(page)
            consumed = NSMaxRange(range)
        }
        return pages
    }

    @MainActor
    static func pdf(_ notebook: Notebook, assetRoot: URL, indices: [Int]? = nil) throws -> Data {
        let selected = indices ?? Array(notebook.pages.indices)
        try require(!selected.isEmpty && selected.allSatisfy(notebook.pages.indices.contains), "Choose valid notebook pages.")
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: notebook.title, kCGPDFContextCreator as String: "Folio Native"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 1000, height: 1414), format: format)
        return renderer.pdfData { output in
            for index in selected {
                let page = notebook.pages[index], rect = CGRect(x: 0, y: 0, width: page.width, height: page.height)
                output.beginPage(withBounds: rect, pageInfo: [:])
                PaperRenderer.draw(page, in: output.cgContext, assetRoot: assetRoot)
                if !page.body.isEmpty { PaperRenderer.drawText(page.body, page: page) }
                let scale = min(2, 4096 / max(page.width, page.height))
                InkBridge.drawing(for: page).image(from: rect, scale: scale).draw(in: rect)
                if notebook.raw.flag("showPageNumbers", true) {
                    let number = String(Int(notebook.raw.number("firstPageNumber", 1)) + index)
                    (number as NSString).draw(at: CGPoint(x: page.width / 2, y: page.height - 35),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: UIColor.darkGray])
                }
            }
        }
    }
    @MainActor
    static func snapshot(_ page: Page, assetRoot: URL) -> Data? {
        let format = UIGraphicsImageRendererFormat(); format.scale = min(2, 2048 / max(page.width, page.height)); format.opaque = true
        let size = CGSize(width: page.width, height: page.height)
        return UIGraphicsImageRenderer(size: size, format: format).pngData { output in
            PaperRenderer.draw(page, in: output.cgContext, assetRoot: assetRoot)
            if !page.body.isEmpty { PaperRenderer.drawText(page.body, page: page) }
            InkBridge.drawing(for: page).image(from: CGRect(origin: .zero, size: size), scale: format.scale).draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private final class WordTextParser: NSObject, XMLParserDelegate {
    private var text = "", insideText = false, exceeded = false
    static func read(_ bytes: Data) throws -> String {
        let markup = String(decoding: bytes, as: UTF8.self)
        try require(markup.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil && markup.range(of: "<!ENTITY", options: .caseInsensitive) == nil,
                    "Word documents containing entity declarations are unsupported.")
        let delegate = WordTextParser(), parser = XMLParser(data: bytes)
        parser.delegate = delegate; parser.shouldResolveExternalEntities = false
        try require(parser.parse() && !delegate.exceeded, "The Word document is damaged or contains too much text.")
        return delegate.text
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "w:t" { insideText = true }
        if name == "w:tab" { text += "\t" }
        if name == "w:br" || name == "w:cr" { text += "\n" }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "w:t" { insideText = false }
        if name == "w:p" { text += "\n" }
        if name == "w:tc" { text += "\t" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText { text += string }
        if text.utf8.count > 10_000_000 { exceeded = true; parser.abortParsing() }
    }
}
