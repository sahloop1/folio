import Foundation

public enum Paper: String, CaseIterable, Identifiable, Sendable {
    case ruled = "Ruled", grid = "Grid", dotted = "Dotted", blank = "Blank", cornell = "Cornell"
    public var id: String { rawValue }
}

public struct Notebook: Identifiable, Codable, Equatable, Sendable {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }
    public init(title: String, profile: String = "Personal", folder: String = "", paper: Paper = .ruled) {
        let now = Date().timeIntervalSince1970 * 1000
        raw = ["id": .string(Identity.new()), "title": .string(title), "profile": .string(profile),
               "folder": .string(folder), "sourceFormat": .string("notebook"), "tags": .array([]),
               "color": .number(-8413747), "favorite": .bool(false), "trashed": .bool(false),
               "created": .number(now), "updated": .number(now), "showPageNumbers": .bool(true),
               "firstPageNumber": .number(1), "sections": .array([]),
               "pages": .array([.object(Page(paper: paper).raw)])]
    }
    public init(from decoder: Decoder) throws { raw = try [String: JSONValue](from: decoder) }
    public func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }
    public var id: String { raw.text("id") }
    public var title: String { get { raw.text("title", "Untitled notebook") } set { raw["title"] = .string(newValue) } }
    public var profile: String { get { raw.text("profile", "Personal") } set { raw["profile"] = .string(newValue) } }
    public var folder: String { get { raw.text("folder") } set { raw["folder"] = .string(newValue) } }
    public var favorite: Bool { get { raw.flag("favorite") } set { raw["favorite"] = .bool(newValue) } }
    public var trashed: Bool { get { raw.flag("trashed") } set { raw["trashed"] = .bool(newValue) } }
    public var color: Double { get { raw.number("color", -8413747) } set { raw["color"] = .number(newValue) } }
    public var updated: Double { raw.number("updated") }
    public var tags: [String] { get { raw.list("tags").compactMap(\.string) } set { raw["tags"] = .array(newValue.map(JSONValue.string)) } }
    public var pages: [Page] {
        get { raw.list("pages").compactMap { $0.object.map(Page.init(raw:)) } }
        set { raw["pages"] = .array(newValue.map { .object($0.raw) }) }
    }
    public var kind: String {
        if raw.text("sourceFormat") == "moc" { return "Map of content" }
        if pages.contains(where: { !$0.pdf.isEmpty }) { return "PDF" }
        if raw.text("sourceFormat") == "docx" { return "Word text" }
        return "Notebook"
    }
    public var resumePage: String { raw.text("lastPageId", pages.first?.id ?? "") }
    public mutating func touch() { raw["updated"] = .number(Date().timeIntervalSince1970 * 1000) }
    public func matches(_ query: String) -> Bool {
        let sections = raw.list("sections").compactMap { $0.object?.text("title") }
        let text = ([title, folder] + tags + sections + pages.flatMap { page in
            [page.title, page.body.text("text")] + page.labels.map { $0.text("text") }
                + page.recordings.map { $0.text("title") }
        }).joined(separator: " ").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace).allSatisfy { text.contains($0) }
    }
    public var attachments: Set<String> { Set(pages.flatMap(\.attachments)) }

    public func validated() throws -> Notebook {
        try require(Identity.valid(id), "A notebook has an invalid ID.")
        try require(raw["title"]?.string != nil && title.count <= 10_000, "A notebook title is invalid.")
        let values = raw.list("pages")
        try require(!values.isEmpty && values.count <= 5_000 && values.count == pages.count, "A notebook needs 1–5,000 valid pages.")
        var seen = Set<String>(), points = 0
        for page in pages {
            try require(seen.insert(page.id).inserted, "A notebook has duplicate page IDs.")
            try page.validate()
            points += page.strokes.reduce(0) { $0 + $1.list("points").count }
            try require(points <= 12_000_000, "This notebook has too much ink for one import. Split it into smaller notebooks.")
        }
        try require(tags.count <= 1_000 && profile.count <= 120 && folder.count <= 1_000, "Notebook metadata is too large.")
        try require((-2_147_483_648...4_294_967_295).contains(color), "Invalid notebook cover color.")
        if raw["firstPageNumber"] != nil { try require((1...999_999).contains(raw.number("firstPageNumber")), "Invalid page numbering.") }
        return self
    }

    public func copy() -> Notebook {
        var copy = self
        copy.raw["id"] = .string(Identity.new())
        copy.title += " copy"
        copy.trashed = false
        copy.touch()
        copy.remapLinks([id: copy.id])
        return copy
    }

    public mutating func remapLinks(_ ids: [String: String]) {
        var updatedPages = pages
        for i in updatedPages.indices {
            updatedPages[i].labels = updatedPages[i].labels.map { label in
                var value = label; value["link"] = .string(Self.remapLink(value.text("link"), ids)); return value
            }
            if !updatedPages[i].body.isEmpty {
                var body = updatedPages[i].body
                body["link"] = .string(Self.remapLink(body.text("link"), ids)); updatedPages[i].body = body
            }
        }
        pages = updatedPages
        // MOC connections are portable text links; retain their other fields.
        if let connections = raw["mocLinks"]?.array {
            raw["mocLinks"] = .array(connections.map { value in
                guard var item = value.object else { return value }
                for key in ["notebookId", "targetId"] { if let id = ids[item.text(key)] { item[key] = .string(id) } }
                return .object(item)
            })
        }
    }
    public static func remapLink(_ text: String, _ ids: [String: String]) -> String {
        guard var url = URLComponents(string: text), url.scheme == "folio", url.host == "notebook",
              let id = ids[String(url.path.dropFirst())] else { return text }
        url.path = "/" + id
        return url.string ?? text
    }
}

public struct Page: Identifiable, Codable, Equatable, Sendable {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }
    public init(paper: Paper = .ruled) {
        raw = ["id": .string(Identity.new()), "title": .string(""), "paper": .string(paper.rawValue),
               "paperColor": .number(-329745), "width": .number(1000), "height": .number(1414),
               "baseHeight": .number(1414), "rulingHeight": .number(1414), "lineCount": .number(32),
               "pdf": .string(""), "pdfPage": .number(-1), "strokes": .array([]),
               "texts": .array([]), "audio": .array([])]
    }
    public init(from decoder: Decoder) throws { raw = try [String: JSONValue](from: decoder) }
    public func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }
    public var id: String { raw.text("id") }
    public var title: String { get { raw.text("title") } set { raw["title"] = .string(newValue) } }
    public var paper: Paper { get { Paper(rawValue: raw.text("paper")) ?? .ruled } set { raw["paper"] = .string(newValue.rawValue) } }
    public var width: Double { raw.number("width", 1000) }
    public var height: Double { get { raw.number("height", 1414) } set { raw["height"] = .number(newValue) } }
    public var baseHeight: Double { raw.number("baseHeight") > 0 ? raw.number("baseHeight") : height }
    public var color: Double { get { raw.number("paperColor", -329745) } set { raw["paperColor"] = .number(newValue) } }
    public var lines: Int { get { Int(exactly: raw.number("lineCount", 32)) ?? -1 } set { raw["lineCount"] = .number(Double(newValue)) } }
    public var pdf: String { get { raw.text("pdf") } set { raw["pdf"] = .string(newValue) } }
    public var pdfPage: Int { Int(exactly: raw.number("pdfPage", -1)) ?? -1 }
    public var strokes: [[String: JSONValue]] {
        get { raw.list("strokes").compactMap(\.object) }
        set { raw["strokes"] = .array(newValue.map(JSONValue.object)) }
    }
    public var labels: [[String: JSONValue]] {
        get { raw.list("texts").compactMap(\.object) }
        set { raw["texts"] = .array(newValue.map(JSONValue.object)) }
    }
    public var recordings: [[String: JSONValue]] {
        get { raw.list("audio").compactMap(\.object) }
        set { raw["audio"] = .array(newValue.map(JSONValue.object)) }
    }
    public var body: [String: JSONValue] {
        get { raw["documentText"]?.object ?? [:] }
        set { raw["documentText"] = .object(newValue) }
    }
    public var pencilData: Data? {
        get { raw["nativePencilKit"]?.string.flatMap { Data(base64Encoded: $0) } }
        set { raw["nativePencilKit"] = newValue.map { .string($0.base64EncodedString()) } }
    }
    public var attachments: [String] {
        (pdf.isEmpty ? [] : ["pdfs/" + pdf]) + recordings.map { "audio/" + $0.text("file") }
    }
    public var firstLine: Double { paper == .grid ? 40 : paper == .dotted ? 48 : 110 }
    public var lineSpacing: Double {
        guard lines > 0 else { return paper == .grid || paper == .dotted ? 28 : 38 }
        let reference = raw.number("rulingHeight") > 0 ? raw.number("rulingHeight") : height
        return max(1, floor((reference - (paper == .cornell ? 250 : 80) - firstLine - 16) / Double(max(1, lines - 1))))
    }
    public func newBody() -> [String: JSONValue] {
        let x = paper == .cornell ? width * 0.27 + 20 : paper == .ruled ? 110 : 80
        return ["text": .string(""), "x": .number(x), "y": .number(firstLine - 20),
                "size": .number(24), "width": .number(width - x - 65), "color": .number(-14340028),
                "lineHeight": .number(pdf.isEmpty ? lineSpacing : 32), "baseline": .number(20), "link": .string("")]
    }
    public func validate() throws {
        try require(Identity.valid(id), "A page has an invalid ID.")
        try require(width.isFinite && height.isFinite && (100...5000).contains(width) && (100...10_000).contains(height), "A page has invalid dimensions.")
        try require(lines == 0 || (4...100).contains(lines), "Page line count must be between 4 and 100.")
        try require((-2_147_483_648...4_294_967_295).contains(color), "Invalid paper color.")
        for key in ["rulingHeight", "baseHeight"] where raw[key] != nil {
            try require(raw.number(key) == 0 || (100...10_000).contains(raw.number(key)), "Invalid page geometry.")
        }
        try require(pdf.isEmpty || (Identity.asset("pdfs/" + pdf) && pdfPage >= 0 && pdfPage <= 10_000), "A page has an invalid PDF reference.")
        for key in ["strokes", "texts", "audio"] {
            if let content = raw[key] { try require(content.array != nil && content.array!.allSatisfy { $0.object != nil }, "Invalid page content.") }
        }
        try require(strokes.count <= 100_000 && labels.count <= 10_000 && recordings.count <= 10_000, "A page contains too many objects.")
        for stroke in strokes {
            let points = stroke.list("points")
            try require(points.count % 3 == 0 && points.count <= 3_000_000 && points.allSatisfy { $0.number?.isFinite == true }, "Invalid ink coordinates.")
            try require((0.25...80).contains(stroke.number("width", 3)), "Invalid ink width.")
            try require((-2_147_483_648...4_294_967_295).contains(stroke.number("color", -14340028)), "Invalid ink color.")
            try require(points.enumerated().allSatisfy { $0.offset % 3 == 2 || abs($0.element.number ?? .infinity) <= 100_000 }, "Ink coordinates are outside the supported range.")
        }
        for text in labels + (body.isEmpty ? [] : [body]) {
            try require(text["text"]?.string != nil && text.text("text").utf8.count <= 10_000_000, "Invalid typed text.")
            try require((8...120).contains(text.number("size", 24)), "Invalid text size.")
            for key in ["x", "y", "width", "lineHeight", "baseline"] where text[key] != nil {
                try require(abs(text.number(key, .infinity)) <= 10_000, "Invalid text geometry.")
            }
            try require((-2_147_483_648...4_294_967_295).contains(text.number("color", -14340028)), "Invalid text color.")
        }
        for recording in recordings {
            try require(Identity.asset("audio/" + recording.text("file")), "Invalid recording reference.")
            try require((0...86_400_000).contains(recording.number("durationMs")), "Invalid recording duration.")
            try require(abs(recording.number("x", 110)) <= 10_000 && abs(recording.number("y", 130)) <= 10_000, "Invalid recording position.")
        }
        if raw["nativePencilKit"] != nil { try require(pencilData != nil, "The saved native drawing is damaged.") }
    }
    public mutating func resize(to requested: Double, contentBottom: Double) throws {
        try require(pdf.isEmpty, "PDF pages keep their original dimensions.")
        let base = baseHeight
        try require(requested.isFinite && requested >= max(100, base * 0.5) && requested <= min(10_000, base * 1.5), "Page length must be between 50% and 150%.")
        try require(requested >= contentBottom + 40, "That would cut off existing content. Keep a longer page.")
        raw["baseHeight"] = .number(base); height = requested
    }
    public func copy() -> Page {
        var copy = self; copy.raw["id"] = .string(Identity.new()); return copy
    }
}
