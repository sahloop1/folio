import Foundation

public struct NotebookSection: Identifiable, Equatable, Sendable {
    public var raw: [String: JSONValue]
    public init(raw: [String: JSONValue]) { self.raw = raw }
    public init(title: String, pageID: String, parentID: String = "") {
        raw = ["id": .string(Identity.new()), "title": .string(title), "pageId": .string(pageID), "parentId": .string(parentID)]
    }
    public var id: String { raw.text("id") }
    public var title: String { get { raw.text("title") } set { raw["title"] = .string(newValue) } }
    public var pageID: String { raw.text("pageId") }
    public var parentID: String { raw.text("parentId") }
}

public extension Notebook {
    var sections: [NotebookSection] {
        get { raw.list("sections").compactMap { $0.object.map(NotebookSection.init(raw:)) } }
        set { raw["sections"] = .array(newValue.map { .object($0.raw) }) }
    }
    mutating func insertPage(after pageID: String, duplicate: Bool = false) -> String {
        let source = pages.first { $0.id == pageID } ?? pages[0]
        var page = duplicate ? source.copy() : Page(paper: source.paper)
        if !duplicate && source.pdf.isEmpty {
            page.color = source.color; page.lines = source.lines
            page.raw["width"] = .number(source.width); page.height = source.height
            page.raw["baseHeight"] = .number(source.baseHeight)
            page.raw["rulingHeight"] = source.raw["rulingHeight"]
        }
        var values = pages
        let at = values.firstIndex { $0.id == pageID } ?? (values.count - 1)
        values.insert(page, at: at + 1); pages = values; touch()
        return page.id
    }
    mutating func removePage(_ pageID: String) throws {
        try require(pages.count > 1, "A notebook must keep at least one page.")
        try require(pages.contains { $0.id == pageID }, "The page no longer exists.")
        pages = pages.filter { $0.id != pageID }
        var retained = sections.filter { $0.pageID != pageID }
        let ids = Set(retained.map(\.id))
        for i in retained.indices where !ids.contains(retained[i].parentID) { retained[i].raw["parentId"] = .string("") }
        sections = retained
        if resumePage == pageID { raw["lastPageId"] = .string(pages[0].id) }
        touch()
    }
}

public enum NotebookLink {
    public static func make(notebookID: String, pageID: String? = nil) -> String {
        var components = URLComponents()
        components.scheme = "folio"; components.host = "notebook"; components.path = "/" + notebookID
        if let pageID { components.queryItems = [URLQueryItem(name: "page", value: pageID)] }
        return components.string ?? ""
    }
    public static func target(_ text: String) -> (notebook: String, page: String?)? {
        guard let url = URLComponents(string: text), url.scheme == "folio", url.host == "notebook",
              url.path.split(separator: "/").count == 1 else { return nil }
        let id = String(url.path.dropFirst()), page = url.queryItems?.first { $0.name == "page" }?.value
        guard Identity.valid(id), page == nil || Identity.valid(page!) else { return nil }
        return (id, page)
    }
    public static func normalize(_ value: String) throws -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try require(!text.isEmpty && text.utf8.count <= 4096 && !text.contains(where: \.isWhitespace), "Enter a complete link without spaces.")
        if URLComponents(string: text)?.scheme == nil { text = "https://" + text }
        guard let url = URLComponents(string: text), let scheme = url.scheme?.lowercased() else { throw FolioError.invalid("Enter a valid link.") }
        if scheme == "folio" { try require(target(text) != nil, "Invalid Folio notebook link.") }
        else if ["https", "http"].contains(scheme) { try require(!(url.host ?? "").isEmpty && url.user == nil && url.password == nil, "Enter a website address without a username or password.") }
        else { try require(["mailto", "tel", "geo"].contains(scheme) && !url.path.isEmpty, "Use a website, email, phone, map, or Folio notebook link.") }
        return text
    }
}
