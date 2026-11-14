import SwiftUI
import UIKit
import FolioCore

struct ImportPreview: Identifiable {
    let id = UUID()
    let title: String
    let prepared: PreparedImport
}

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var notebooks: [Notebook] = []
    @Published private(set) var preferences: [String: JSONValue] = [:]
    @Published var profile = "Personal"
    @Published var isLoaded = false
    @Published var loadError: String?
    @Published var error: String?
    @Published var busy: String?
    @Published var preview: ImportPreview?
    @Published var sharedFile: SharedFile?
    @Published private(set) var unsaved = Set<String>()
    let storage: LibraryStorage
    private var tickets: [String: Int] = [:]
    private var pending: [String: Task<Void, Never>] = [:]

    init(root: URL? = nil) {
        var base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FolioLibrary", isDirectory: true)
        #if DEBUG
        if root == nil && ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            base = base.deletingLastPathComponent().appendingPathComponent("FolioUITestLibrary", isDirectory: true)
            if ProcessInfo.processInfo.arguments.contains("--reset-test-library") { try? FileManager.default.removeItem(at: base) }
        }
        #endif
        storage = LibraryStorage(root: base)
    }
    var profiles: [String] {
        let saved = preferences.list("libraryProfiles").compactMap(\.string) + preferences.list("profiles").compactMap(\.string)
        return Set(["Personal", profile] + saved + notebooks.map(\.profile)).sorted()
    }
    var folders: [String] {
        let saved = preferences.list("profileFolders." + profile).compactMap(\.string)
        return Set(saved + notebooks.filter { $0.profile == profile }.map(\.folder)).filter { !$0.isEmpty }.sorted()
    }
    var isSaving: Bool { !unsaved.isEmpty }
    func notebook(_ id: String) -> Notebook? { notebooks.first { $0.id == id } }

    func open(recover: Bool = false) async {
        do {
            let loaded = try await (recover ? storage.recoverPreviousIndex() : storage.load())
            notebooks = loaded.notebooks; preferences = loaded.preferences
            profile = preferences.text("activeProfile", "Personal")
            loadError = nil; isLoaded = true
        } catch { loadError = error.localizedDescription; isLoaded = false }
    }
    func selectProfile(_ name: String) {
        profile = name
        preferences["activeProfile"] = .string(name)
        let names = Set(profiles + [name]).sorted()
        preferences["libraryProfiles"] = .array(names.map(JSONValue.string))
        let value = preferences
        Task { do { try await storage.savePreferences(value) } catch { self.error = error.localizedDescription } }
    }
    func addFolder(_ name: String) {
        let values = Set(folders + [name]).sorted()
        preferences["profileFolders." + profile] = .array(values.map(JSONValue.string))
        let value = preferences
        Task { do { try await storage.savePreferences(value) } catch { self.error = error.localizedDescription } }
    }
    @discardableResult
    func create(title: String, folder: String, paper: Paper, tags: String = "", color: Double = -8413747) -> String {
        var notebook = Notebook(title: title.trimmingCharacters(in: .whitespacesAndNewlines), profile: profile, folder: folder, paper: paper)
        if notebook.title.isEmpty { notebook.title = "Untitled notebook" }
        notebook.tags = parseTags(tags); notebook.color = color
        set(notebook)
        return notebook.id
    }
    func parseTags(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.prefix(30).map { $0 }
    }
    func change(_ id: String, _ mutation: (inout Notebook) -> Void) {
        guard var notebook = notebook(id) else { return }
        mutation(&notebook); notebook.touch(); set(notebook)
    }
    func changePage(_ bookID: String, pageID: String, _ mutation: (inout Page) -> Void) {
        change(bookID) { book in
            guard let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
            var pages = book.pages; mutation(&pages[index]); book.pages = pages
        }
    }
    func set(_ notebook: Notebook) {
        if let index = notebooks.firstIndex(where: { $0.id == notebook.id }) { notebooks[index] = notebook }
        else { notebooks.append(notebook) }
        let id = notebook.id
        tickets[id, default: 0] += 1
        let ticket = tickets[id]!
        unsaved.insert(id); pending[id]?.cancel()
        pending[id] = Task {
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                try Task.checkCancellation()
                try await storage.save(notebook, ticket: ticket)
                if tickets[id] == ticket { unsaved.remove(id); pending.removeValue(forKey: id) }
            } catch is CancellationError { }
            catch { self.error = "Your latest changes are not saved: " + error.localizedDescription }
        }
    }
    @discardableResult
    func flush() async -> Bool {
        for task in pending.values { task.cancel() }
        pending.removeAll()
        let ids = unsaved
        do {
            for id in ids {
                guard let notebook = notebook(id), let ticket = tickets[id] else { continue }
                try await storage.save(notebook, ticket: ticket)
                if tickets[id] == ticket { unsaved.remove(id) }
            }
            return true
        } catch { self.error = "Changes remain unsaved: " + error.localizedDescription; return false }
    }
    func flushInBackground(after audio: AudioController) {
        var identifier: UIBackgroundTaskIdentifier = .invalid
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Save Folio notebooks") {
            if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier); identifier = .invalid }
        }
        Task {
            await audio.finishRecording()
            _ = await flush()
            if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier) }
        }
    }
    func duplicate(_ id: String) { if let notebook = notebook(id) { set(notebook.copy()) } }
    func purge(_ id: String) async {
        guard await flush() else { return }
        do { try await storage.purge(id); notebooks.removeAll { $0.id == id } }
        catch { self.error = error.localizedDescription }
    }
    func prepareImport(_ url: URL, folder: String) async {
        busy = "Checking import…"
        defer { busy = nil }
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let targetProfile = profile
            let prepared = try await Task.detached(priority: .userInitiated) {
                try NativeDocuments.prepare(url: url, profile: targetProfile, folder: folder)
            }.value
            preview = ImportPreview(title: url.lastPathComponent, prepared: prepared)
        } catch { self.error = error.localizedDescription }
    }
    func importConfirmed(_ preview: ImportPreview, usePreferences: Bool) async {
        guard await flush() else { return }
        busy = "Importing notebooks…"
        defer { busy = nil }
        do {
            _ = try await storage.add(preview.prepared, usePreferences: usePreferences)
            let loaded = try await storage.load()
            notebooks = loaded.notebooks; preferences = loaded.preferences
            self.preview = nil
        } catch { self.error = error.localizedDescription }
    }
    func export(_ notebook: Notebook? = nil) async {
        guard await flush() else { return }
        busy = "Preparing backup…"
        defer { busy = nil }
        do {
            let books = notebook.map { [self.notebook($0.id) ?? $0] } ?? notebooks
            let data = try await storage.export(books, preferences: preferences, single: notebook != nil)
            let name = notebook.map { safeFilename($0.title) + ".folio" } ?? "Folio-library-" + Date.now.formatted(.iso8601.year().month().day()) + ".zip"
            try share(data: data, name: name)
        } catch { self.error = error.localizedDescription }
    }
    func exportPDF(_ id: String) async {
        guard await flush(), let notebook = notebook(id) else { return }
        busy = "Preparing PDF…"
        defer { busy = nil }
        await Task.yield()
        do { try share(data: NativeDocuments.pdf(notebook, assetRoot: storage.root), name: safeFilename(notebook.title) + ".pdf") }
        catch { self.error = error.localizedDescription }
    }
    func sharePage(_ id: String, pageID: String) async {
        guard await flush(), let page = notebook(id)?.pages.first(where: { $0.id == pageID }) else { return }
        busy = "Preparing page image…"
        defer { busy = nil }
        await Task.yield()
        do {
            guard let data = NativeDocuments.snapshot(page, assetRoot: storage.root) else { throw FolioError.invalid("The page image could not be created.") }
            try share(data: data, name: "Folio-page.png")
        } catch { self.error = error.localizedDescription }
    }
    func share(data: Data, name: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Folio-share-" + Identity.new())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        sharedFile = SharedFile(url: url)
    }
    func safeFilename(_ value: String) -> String {
        let name = value.components(separatedBy: CharacterSet(charactersIn: "/\\:\n\r")).joined(separator: "-")
        return String(name.prefix(120)).isEmpty ? "Notebook" : String(name.prefix(120))
    }
    func attachRecording(url: URL, duration: TimeInterval, bookID: String, pageID: String) async {
        do {
            guard notebook(bookID)?.pages.contains(where: { $0.id == pageID }) == true else {
                throw FolioError.invalid("The recording's page was removed. The original recording has been retained.")
            }
            let bytes = try Data(contentsOf: url)
            let file = try await storage.putAsset(bytes, folder: "audio", extension: "m4a")
            changePage(bookID, pageID: pageID) { page in
                var recordings = page.recordings
                recordings.append(["id": .string(Identity.new()), "file": .string(file), "title": .string("Voice note"),
                                   "durationMs": .number(duration * 1000), "x": .number(110),
                                   "y": .number(min(page.height - 100, 150 + Double(recordings.count) * 70)), "scale": .number(1)])
                page.recordings = recordings
            }
            _ = await flush()
            try? FileManager.default.removeItem(at: url)
        } catch { self.error = "The recording is still in temporary storage: " + error.localizedDescription }
    }
}
