import Foundation

public struct LoadedLibrary: Sendable {
    public var notebooks: [Notebook]
    public var preferences: [String: JSONValue]
}

/// Notebook revisions and assets are immutable. The index is the single atomic commit.
/// A failed or interrupted import cannot publish half a library or overwrite old notes.
public actor LibraryStorage {
    public nonisolated let root: URL
    private struct Index: Codable {
        var version = 1
        var notebooks: [String: String] = [:]
        var preferences: [String: JSONValue] = [:]
    }
    private var index: Index?
    private var tickets: [String: Int] = [:]
    private let fm = FileManager.default
    public init(root: URL) { self.root = root }
    private var indexURL: URL { root.appendingPathComponent("library-index.json") }
    private var previousURL: URL { root.appendingPathComponent("previous-index.json") }

    public func load() throws -> LoadedLibrary {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for folder in ["revisions", "pdfs", "audio"] {
            try fm.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        let value: Index
        if fm.fileExists(atPath: indexURL.path) {
            value = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))
        } else {
            let orphaned = try fm.contentsOfDirectory(atPath: root.appendingPathComponent("revisions").path)
            try require(orphaned.isEmpty && !fm.fileExists(atPath: previousURL.path), "The library index is missing. Restore a Files backup; your existing files have been kept.")
            value = Index()
        }
        let loaded = try read(value)
        if !fm.fileExists(atPath: indexURL.path) {
            try JSONEncoder().encode(value).write(to: indexURL, options: .atomic)
        }
        index = value
        return loaded
    }

    private func read(_ value: Index) throws -> LoadedLibrary {
        try require(value.version == 1, "This library needs a newer Folio app.")
        var books: [Notebook] = []
        for (id, revision) in value.notebooks {
            try require(Identity.valid(id) && Identity.valid(revision), "The library index is damaged.")
            let bytes = try Data(contentsOf: root.appendingPathComponent("revisions/" + revision + ".json"))
            let notebook = try JSONDecoder().decode(Notebook.self, from: bytes).validated()
            try require(notebook.id == id, "A notebook disagrees with the library index.")
            for asset in notebook.attachments { try require(fm.fileExists(atPath: root.appendingPathComponent(asset).path), "A saved attachment is missing. Restore a Files backup.") }
            books.append(notebook)
        }
        return LoadedLibrary(notebooks: books, preferences: value.preferences)
    }

    public func recoverPreviousIndex() throws -> LoadedLibrary {
        let previous = try JSONDecoder().decode(Index.self, from: Data(contentsOf: previousURL))
        let loaded = try read(previous)
        // Preserve the damaged/current index for diagnosis; recovery itself is explicit.
        if fm.fileExists(atPath: indexURL.path) {
            try fm.copyItem(at: indexURL, to: root.appendingPathComponent("unreadable-index-" + Identity.new() + ".json"))
        }
        try JSONEncoder().encode(previous).write(to: indexURL, options: .atomic)
        index = previous
        return loaded
    }

    private func commit(_ next: Index) throws {
        let bytes = try JSONEncoder().encode(next)
        if fm.fileExists(atPath: indexURL.path) { try Data(contentsOf: indexURL).write(to: previousURL, options: .atomic) }
        try bytes.write(to: indexURL, options: .atomic)
        index = next
    }
    private func writeRevision(_ notebook: Notebook) throws -> String {
        _ = try notebook.validated()
        let revision = Identity.new()
        try JSONEncoder().encode(notebook).write(to: root.appendingPathComponent("revisions/" + revision + ".json"), options: .atomic)
        return revision
    }
    public func save(_ notebook: Notebook, ticket: Int) throws {
        guard var next = index else { throw FolioError.invalid("Open the library successfully before saving.") }
        if ticket < tickets[notebook.id, default: 0] { return }
        next.notebooks[notebook.id] = try writeRevision(notebook)
        try commit(next)
        tickets[notebook.id] = ticket
    }
    public func savePreferences(_ preferences: [String: JSONValue]) throws {
        guard var next = index else { throw FolioError.invalid("The library is not open.") }
        next.preferences = preferences; try commit(next)
    }
    public func add(_ prepared: PreparedImport, usePreferences: Bool) throws -> PreparedImport {
        guard var next = index else { throw FolioError.invalid("The library is not open.") }
        try prepared.validate()
        let remapped = LibraryArchive.remap(prepared, existingIDs: Set(next.notebooks.keys))
        for (name, data) in remapped.attachments {
            try require(Identity.asset(name), "Invalid attachment name.")
            let target = root.appendingPathComponent(name)
            try require(!fm.fileExists(atPath: target.path), "An attachment name collided. Try the import again.")
            try data.write(to: target, options: .atomic)
        }
        for notebook in remapped.notebooks { next.notebooks[notebook.id] = try writeRevision(notebook) }
        if usePreferences {
            // Merge the imported profile/folder lists; keep all destination settings and profiles.
            for (key, value) in remapped.preferences {
                if let incoming = value.array, let current = next.preferences[key]?.array {
                    next.preferences[key] = .array(current + incoming.filter { !current.contains($0) })
                } else if next.preferences[key] == nil { next.preferences[key] = value }
            }
        }
        try commit(next)
        return remapped
    }
    public func putAsset(_ data: Data, folder: String, extension ext: String) throws -> String {
        let name = Identity.new() + "." + ext, path = folder + "/" + name
        try require(Identity.asset(path) && data.count <= ZIPArchive.entryLimit, "Invalid or oversized attachment.")
        try data.write(to: root.appendingPathComponent(path), options: .atomic)
        return name
    }
    public func export(_ notebooks: [Notebook], preferences: [String: JSONValue], single: Bool) throws -> Data {
        var attachments: [String: Data] = [:]
        for name in notebooks.reduce(into: Set<String>(), { $0.formUnion($1.attachments) }) {
            try require(Identity.asset(name), "Invalid saved attachment name.")
            attachments[name] = try Data(contentsOf: root.appendingPathComponent(name))
        }
        return try LibraryArchive.export(notebooks: notebooks, attachments: attachments, preferences: preferences, single: single)
    }
    public func purge(_ id: String) throws {
        guard var next = index else { throw FolioError.invalid("The library is not open.") }
        next.notebooks.removeValue(forKey: id); try commit(next)
        // Revisions/assets remain recoverable; compaction only removes unreferenced data explicitly.
    }
}
