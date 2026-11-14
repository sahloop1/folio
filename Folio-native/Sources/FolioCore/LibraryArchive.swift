import Foundation
import CryptoKit

public struct PreparedImport: Sendable {
    public var notebooks: [Notebook]
    public var attachments: [String: Data]
    public var preferences: [String: JSONValue]
    public var isLibrary: Bool
    public init(notebooks: [Notebook], attachments: [String: Data], preferences: [String: JSONValue], isLibrary: Bool) {
        self.notebooks = notebooks; self.attachments = attachments
        self.preferences = PortablePreferences.filtered(preferences); self.isLibrary = isLibrary
    }
    public var pageCount: Int { notebooks.reduce(0) { $0 + $1.pages.count } }
    public var recordingCount: Int { notebooks.reduce(0) { $0 + $1.pages.reduce(0) { $0 + $1.recordings.count } } }
    public func validate() throws {
        try require(notebooks.count <= 1000 && Set(notebooks.map(\.id)).count == notebooks.count, "Invalid or duplicate notebooks.")
        for notebook in notebooks { _ = try notebook.validated() }
        let needed = notebooks.reduce(into: Set<String>()) { $0.formUnion($1.attachments) }
        try require(needed == Set(attachments.keys), "Missing or unexpected attachments.")
        try require(attachments.values.reduce(0, { $0 + $1.count }) <= ZIPArchive.libraryLimit, "Attachments exceed 512 MB.")
        for (name, data) in attachments {
            try require(Identity.asset(name) && !data.isEmpty && data.count <= ZIPArchive.entryLimit, "Invalid attachment.")
        }
    }
}

public enum LibraryArchive {
    public static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    public static func prepare(_ data: Data) throws -> PreparedImport {
        let entries = try ZIPArchive.read(data)
        var notebooks: [Notebook] = [], preferences: [String: JSONValue] = [:]
        let isLibrary = entries["notebook.json"] == nil
        func book(_ bytes: Data?) throws -> Notebook {
            guard let bytes else { throw FolioError.invalid("A notebook is missing from the archive.") }
            try require(bytes.count <= 40 * 1024 * 1024, "Notebook metadata exceeds 40 MB.")
            return try JSONDecoder().decode(Notebook.self, from: bytes).validated()
        }
        if let bytes = entries["notebook.json"] {
            try require(entries.values.reduce(0, { $0 + $1.count }) <= ZIPArchive.entryLimit, "A single editable notebook can contain up to 200 MB.")
            try require(entries.keys.allSatisfy { $0 == "notebook.json" || Identity.asset($0) }, "Unexpected file in the notebook archive.")
            var notebook = try book(bytes); notebook.trashed = false; notebooks = [notebook]
        } else {
            guard let bytes = entries["folio-library.json"], bytes.count <= 16 * 1024 * 1024,
                  let manifest = try JSONValue.decode(bytes).object else { throw FolioError.invalid("Choose an editable .folio notebook or a Folio library ZIP.") }
            try require(["folio-library", "folio-ipad-library", "folio-native-library"].contains(manifest.text("format")) && manifest.number("version") == 1,
                        "This library archive needs a newer version of Folio.")
            guard let inventory = manifest["files"]?.object, let ids = manifest["notebooks"]?.array else {
                throw FolioError.invalid("The library inventory is missing.")
            }
            try require(inventory.count == entries.count - 1 && ids.count <= 1000, "Incomplete library inventory or too many notebooks.")
            var seen = Set<String>(), metadata = 0
            for value in ids {
                guard let id = value.string else { throw FolioError.invalid("Invalid library notebook ID.") }
                try require(Identity.valid(id) && seen.insert(id).inserted, "Invalid or duplicate notebook ID.")
                let notebook = try book(entries["notebooks/" + id + ".folio.json"])
                try require(notebook.id == id, "Notebook ID disagrees with the library inventory.")
                notebooks.append(notebook)
            }
            for (name, content) in entries where name != "folio-library.json" {
                let notebookPath = name.hasPrefix("notebooks/") && name.hasSuffix(".folio.json")
                try require(Identity.asset(name) || notebookPath || ["Folio.apk", "READ-ME.txt", "profile.png"].contains(name), "Unexpected library file.")
                guard let record = inventory[name]?.object else { throw FolioError.invalid("A file is not listed in the library inventory.") }
                try require(record.number("bytes", -1) == Double(content.count) && record.text("sha256") == digest(content), "A library file failed its SHA-256 integrity check.")
                if notebookPath {
                    metadata += content.count
                    let id = String(name.dropFirst(10).dropLast(11))
                    try require(seen.contains(id), "The archive has an unlisted notebook.")
                }
            }
            try require(metadata <= 160 * 1024 * 1024, "Library metadata exceeds 160 MB.")
            preferences = PortablePreferences.filtered(manifest["preferences"]?.object ?? [:])
        }
        let needed = notebooks.reduce(into: Set<String>()) { $0.formUnion($1.attachments) }
        var attachments: [String: Data] = [:]
        for name in needed {
            guard let content = entries[name], !content.isEmpty else { throw FolioError.invalid("A referenced PDF or recording is missing.") }
            if name.hasPrefix("pdfs/") { try require(content.prefix(5) == Data("%PDF-".utf8), "A PDF attachment is damaged.") }
            else { try require(content.count >= 12 && content.subdata(in: 4..<8) == Data("ftyp".utf8), "A recording attachment is damaged.") }
            attachments[name] = content
        }
        try require(entries.keys.filter(Identity.asset).allSatisfy(needed.contains), "The archive has an unreferenced attachment.")
        return PreparedImport(notebooks: notebooks, attachments: attachments, preferences: preferences, isLibrary: isLibrary)
    }

    /// Every asset gets a fresh name. Notebook collisions become independent copies.
    /// Called at commit time against the latest destination IDs, never during preview.
    public static func remap(_ prepared: PreparedImport, existingIDs: Set<String>) -> PreparedImport {
        var result = prepared, used = existingIDs, ids: [String: String] = [:], assets: [String: String] = [:]
        for notebook in prepared.notebooks {
            var id = notebook.id
            while used.contains(id) { id = Identity.new() }
            used.insert(id); ids[notebook.id] = id
        }
        for name in prepared.attachments.keys {
            assets[name] = String(name.prefix(through: name.firstIndex(of: "/")!)) + Identity.new() + "." + (name as NSString).pathExtension
        }
        result.attachments = Dictionary(uniqueKeysWithValues: prepared.attachments.map { (assets[$0.key]!, $0.value) })
        result.notebooks = prepared.notebooks.map { original in
            var notebook = original; notebook.raw["id"] = .string(ids[original.id]!)
            var pages = notebook.pages
            for i in pages.indices {
                if !pages[i].pdf.isEmpty { pages[i].pdf = (assets["pdfs/" + pages[i].pdf]! as NSString).lastPathComponent }
                pages[i].recordings = pages[i].recordings.map { original in
                    var recording = original
                    recording["file"] = .string((assets["audio/" + original.text("file")]! as NSString).lastPathComponent)
                    return recording
                }
            }
            notebook.pages = pages; notebook.remapLinks(ids)
            return notebook
        }
        return result
    }

    public static func export(notebooks: [Notebook], attachments: [String: Data], preferences: [String: JSONValue] = [:], single: Bool = false) throws -> Data {
        try require(!single || notebooks.count == 1, "Choose one notebook for an editable export.")
        var entries: [String: Data] = [:], inventory: [String: JSONValue] = [:]
        let needed = notebooks.reduce(into: Set<String>()) { $0.formUnion($1.attachments) }
        for name in needed {
            guard let bytes = attachments[name] else { throw FolioError.invalid("A PDF or recording is missing. The backup was not created.") }
            entries[name] = bytes
        }
        for notebook in notebooks {
            _ = try notebook.validated()
            entries[single ? "notebook.json" : "notebooks/" + notebook.id + ".folio.json"] = try JSONEncoder().encode(notebook)
        }
        if !single {
            for (name, data) in entries {
                inventory[name] = .object(["bytes": .number(Double(data.count)), "sha256": .string(digest(data))])
            }
            entries["folio-library.json"] = try JSONValue.object([
                "format": .string("folio-native-library"), "version": .number(1),
                "created": .number(Date().timeIntervalSince1970 * 1000),
                "notebooks": .array(notebooks.map { .string($0.id) }), "files": .object(inventory),
                "preferences": .object(PortablePreferences.filtered(preferences))
            ]).data()
        }
        return try ZIPArchive.write(entries)
    }
}
