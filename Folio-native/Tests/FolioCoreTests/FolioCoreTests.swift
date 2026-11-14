import Foundation
import XCTest
@testable import FolioCore

final class FolioCoreTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
    private func temporaryRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("folio-tests-" + UUID().uuidString) }

    func testSHA256KnownVector() {
        XCTAssertEqual(LibraryArchive.digest(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    func testAndroidStreamingNotebookAndUnknownFields() throws {
        let prepared = try LibraryArchive.prepare(fixture("android-notebook.folio"))
        try prepared.validate()
        XCTAssertEqual(prepared.pageCount, 1)
        XCTAssertEqual(prepared.recordingCount, 1)
        XCTAssertEqual(prepared.attachments.count, 2)
        let book = try XCTUnwrap(prepared.notebooks.first)
        XCTAssertEqual(book.raw.number("futureNotebookSetting"), 42)
        XCTAssertEqual(book.pages[0].raw["futurePageSetting"]?.object?.flag("kept"), true)
        XCTAssertTrue(book.matches("cafe science"))
        XCTAssertTrue(book.matches("ملاحظات"))
        XCTAssertFalse(book.matches("absent phrase"))
    }
    func testAndroidLibraryPreservesTrashAndFiltersCredentials() throws {
        let prepared = try LibraryArchive.prepare(fixture("android-library.zip"))
        XCTAssertTrue(prepared.isLibrary)
        XCTAssertEqual(prepared.notebooks.count, 2)
        XCTAssertTrue(prepared.notebooks[1].trashed)
        XCTAssertEqual(prepared.preferences.text("activeProfile"), "Study")
        XCTAssertNil(prepared.preferences["assistantToken"])
        let data = try LibraryArchive.export(notebooks: prepared.notebooks, attachments: prepared.attachments, preferences: prepared.preferences)
        let restored = try LibraryArchive.prepare(data)
        XCTAssertEqual(prepared.notebooks, restored.notebooks)
        XCTAssertEqual(prepared.attachments, restored.attachments)
    }
    func testCollisionRemapsLinksAndAssetsWithoutOverwriting() throws {
        let prepared = try LibraryArchive.prepare(fixture("android-library.zip"))
        let original = prepared.notebooks
        let remapped = LibraryArchive.remap(prepared, existingIDs: Set(original.map(\.id)))
        XCTAssertTrue(Set(remapped.notebooks.map(\.id)).isDisjoint(with: Set(original.map(\.id))))
        XCTAssertTrue(Set(remapped.attachments.keys).isDisjoint(with: Set(prepared.attachments.keys)))
        let link = remapped.notebooks[0].pages[0].labels[0].text("link")
        XCTAssertEqual(NotebookLink.target(link)?.notebook, remapped.notebooks[1].id)
        XCTAssertEqual(NotebookLink.target(link)?.page, original[1].pages[0].id)
        try remapped.validate()
        XCTAssertEqual(remapped.notebooks[0].sections[0].pageID, original[0].sections[0].pageID)
    }
    func testTamperedLibraryHashRejectedEvenWithValidZIPCRC() throws {
        var entries = try ZIPArchive.read(fixture("android-library.zip"))
        let key = try XCTUnwrap(entries.keys.first { $0.hasPrefix("notebooks/") })
        entries[key]!.append(0x20)
        XCTAssertThrowsError(try LibraryArchive.prepare(ZIPArchive.write(entries)))
    }
    func testMissingAssetRejected() throws {
        var entries = try ZIPArchive.read(fixture("android-notebook.folio"))
        entries.removeValue(forKey: try XCTUnwrap(entries.keys.first { $0.hasPrefix("audio/") }))
        XCTAssertThrowsError(try LibraryArchive.prepare(ZIPArchive.write(entries)))
    }
    func testZIPRoundTripAndCRCFailure() throws {
        let entries = ["notes/ملاحظات.txt": Data("hello".utf8), "empty.txt": Data()]
        let zip = try ZIPArchive.write(entries)
        XCTAssertEqual(try ZIPArchive.read(zip), entries)
        var damaged = zip
        let payload = try XCTUnwrap(damaged.range(of: Data("hello".utf8)))
        damaged[payload.lowerBound] ^= 0xff
        XCTAssertThrowsError(try ZIPArchive.read(damaged))
        XCTAssertThrowsError(try ZIPArchive.read(Data(zip.dropLast())))
    }
    func testUnsafePathsAndZIPLimits() throws {
        for path in ["../notes", "/root", "notes/../x", "x\\y", "C:/x", "./x", "x\u{0000}y"] { XCTAssertFalse(ZIPArchive.safePath(path), path) }
        XCTAssertThrowsError(try ZIPArchive.write(["../bad": Data()]))
        XCTAssertThrowsError(try ZIPArchive.read(ZIPArchive.write(["large": Data(repeating: 0, count: 100)]), limit: 50))
    }
    func testExtremeNumericMetadataRejectedWithoutIntegerTrap() throws {
        for key in ["lineCount", "width", "height", "paperColor", "baseHeight"] {
            var page = Page(); page.raw[key] = .number(1e200)
            XCTAssertThrowsError(try page.validate(), key)
        }
    }
    func testPageResizeProtectsContentAndLegacyZeroBase() throws {
        var page = Page(); page.raw["baseHeight"] = .number(0)
        XCTAssertThrowsError(try page.resize(to: 707, contentBottom: 800))
        XCTAssertEqual(page.height, 1414)
        try page.resize(to: 1800, contentBottom: 800)
        XCTAssertEqual(page.baseHeight, 1414)
        XCTAssertEqual(page.height, 1800)
    }
    func testPageInsertionReorderAndDeletionKeepStableLinks() throws {
        var book = Notebook(title: "Study")
        let first = book.pages[0].id
        book.sections = [NotebookSection(title: "First", pageID: first)]
        let second = book.insertPage(after: first)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(book.pages[1].id, second)
        try book.removePage(first)
        XCTAssertTrue(book.sections.isEmpty)
        XCTAssertEqual(book.pages.count, 1)
        XCTAssertThrowsError(try book.removePage(second))
    }
    func testLinkValidationRejectsExecutableSchemes() throws {
        XCTAssertEqual(try NotebookLink.normalize("example.com"), "https://example.com")
        XCTAssertThrowsError(try NotebookLink.normalize("javascript:alert(1)"))
        XCTAssertThrowsError(try NotebookLink.normalize("https://user:secret@example.com"))
        XCTAssertThrowsError(try NotebookLink.normalize("folio://notebook/not-an-id"))
        let id = Identity.new(), page = Identity.new()
        XCTAssertEqual(NotebookLink.target(NotebookLink.make(notebookID: id, pageID: page))?.page, page)
    }
    func testAtomicImportRepeatedRestoreAndDiskReload() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let storage = LibraryStorage(root: root)
        _ = try await storage.load()
        let existing = Notebook(title: "Keep my notes")
        try await storage.save(existing, ticket: 1)
        let prepared = try LibraryArchive.prepare(fixture("android-library.zip"))
        _ = try await storage.add(prepared, usePreferences: true)
        _ = try await storage.add(prepared, usePreferences: true)
        let reopened = try await LibraryStorage(root: root).load()
        XCTAssertEqual(reopened.notebooks.count, 5)
        XCTAssertTrue(reopened.notebooks.contains { $0 == existing })
        XCTAssertEqual(Set(reopened.notebooks.map(\.id)).count, 5)
        XCTAssertEqual(reopened.preferences.text("activeProfile"), "Study")
    }
    func testStaleSaveTicketDoesNotReplaceNewerRevision() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let storage = LibraryStorage(root: root); _ = try await storage.load()
        let older = Notebook(title: "Older")
        var newer = older; newer.title = "Newer"
        try await storage.save(newer, ticket: 2)
        try await storage.save(older, ticket: 1)
        let loaded = try await storage.load()
        XCTAssertEqual(loaded.notebooks[0].title, "Newer")
    }
    func testFailedImportLeavesIndexAndExistingNotesUntouched() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let storage = LibraryStorage(root: root); _ = try await storage.load()
        let book = Notebook(title: "Keep")
        try await storage.save(book, ticket: 1)
        let before = try Data(contentsOf: root.appendingPathComponent("library-index.json"))
        var bad = book; bad.raw["pages"] = .array([])
        do {
            _ = try await storage.add(PreparedImport(notebooks: [bad], attachments: [:], preferences: [:], isLibrary: true), usePreferences: false)
            XCTFail("An invalid import succeeded")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library-index.json")), before)
        let loaded = try await storage.load()
        XCTAssertEqual(loaded.notebooks, [book])
    }
    func testDamagedIndexRequiresExplicitRecovery() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let storage = LibraryStorage(root: root); _ = try await storage.load()
        let first = Notebook(title: "First save")
        try await storage.save(first, ticket: 1)
        var next = first; next.title = "Second save"
        try await storage.save(next, ticket: 2)
        try Data("broken".utf8).write(to: root.appendingPathComponent("library-index.json"))
        let reopened = LibraryStorage(root: root)
        do { _ = try await reopened.load(); XCTFail("A damaged index was silently reset") } catch { }
        let recovered = try await reopened.recoverPreviousIndex()
        XCTAssertEqual(recovered.notebooks[0].title, "First save")
    }
}
