import XCTest
import UIKit
import PencilKit
import FolioCore
@testable import Folio

final class NativeTests: XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("folio-native-test-" + UUID().uuidString) }
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    }
    @MainActor
    func testAndroidInkBecomesEditablePencilKitAndSurvivesReload() async throws {
        let directory = root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try Data(contentsOf: fixture("android-notebook.folio"))
        var imported = try LibraryArchive.prepare(data)
        var notebook = try XCTUnwrap(imported.notebooks.first)
        var page = try XCTUnwrap(notebook.pages.first)
        let drawing = InkBridge.drawing(for: page)
        let originalStroke = try XCTUnwrap(drawing.strokes.first)
        XCTAssertEqual(drawing.strokes.count, 1)
        InkBridge.save(drawing, to: &page)
        let native = try XCTUnwrap(page.pencilData)
        notebook.pages[0] = page
        imported.notebooks[0] = notebook
        let storage = LibraryStorage(root: directory)
        _ = try await storage.load()
        _ = try await storage.add(imported, usePreferences: false)

        let reloaded = try await LibraryStorage(root: directory).load()
        let savedPage = try XCTUnwrap(reloaded.notebooks.first?.pages.first)
        XCTAssertEqual(savedPage.pencilData, native)
        let decoded = try PKDrawing(data: XCTUnwrap(savedPage.pencilData))
        XCTAssertEqual(decoded.strokes.count, 1)
        let restoredDrawing = InkBridge.drawing(for: savedPage)
        XCTAssertEqual(restoredDrawing.strokes.count, 1)
        let restoredStroke = try XCTUnwrap(restoredDrawing.strokes.first)
        XCTAssertEqual(restoredStroke.ink.inkType, originalStroke.ink.inkType)
        XCTAssertEqual(restoredStroke.path.count, originalStroke.path.count)
        for (restored, original) in zip(restoredStroke.path, originalStroke.path) {
            XCTAssertEqual(restored.location.x, original.location.x, accuracy: 0.1)
            XCTAssertEqual(restored.location.y, original.location.y, accuracy: 0.1)
            XCTAssertEqual(restored.force, original.force, accuracy: 0.01)
        }
        let portableStroke = try XCTUnwrap(savedPage.strokes.first)
        XCTAssertFalse(portableStroke.list("points").isEmpty)
    }
    @MainActor
    func testPartialEraserDoesNotResurrectInkInAndroidExport() {
        let points = [PKStrokePoint(location: CGPoint(x: 0, y: 50), timeOffset: 0, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
                      PKStrokePoint(location: CGPoint(x: 100, y: 50), timeOffset: 1, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)]
        var stroke = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        let mask = UIBezierPath(rect: CGRect(x: -10, y: 30, width: 50, height: 40))
        mask.append(UIBezierPath(rect: CGRect(x: 80, y: 30, width: 30, height: 40))); stroke.mask = mask
        var page = Page(); InkBridge.save(PKDrawing(strokes: [stroke]), to: &page)
        XCTAssertGreaterThanOrEqual(page.strokes.count, 2)
        for portable in page.strokes {
            let numbers = portable.list("points").compactMap(\.number)
            for index in stride(from: 0, to: numbers.count, by: 3) { XCTAssertFalse((45...75).contains(numbers[index])) }
        }
    }
    @MainActor
    func testPDFAndPageSnapshotIncludeNativeInkAndKeepPageSize() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var book = Notebook(title: "PDF test"), page = Page()
        page.body = page.newBody(); page.body["text"] = .string("Native paragraph")
        page.strokes = [["tool": .string("pen"), "width": .number(4), "points": .array([.number(100), .number(200), .number(1), .number(300), .number(200), .number(1)])]]
        book.pages = [page]
        let bytes = try NativeDocuments.pdf(book, assetRoot: directory)
        let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
        let pdf = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertEqual(pdf.numberOfPages, 1)
        XCTAssertEqual(pdf.page(at: 1)?.getBoxRect(.mediaBox).size, CGSize(width: 1000, height: 1414))
        let snapshot = try XCTUnwrap(NativeDocuments.snapshot(page, assetRoot: directory))
        XCTAssertNotNil(UIImage(data: snapshot))
    }
    @MainActor
    func testNativeImportValidatesAndroidPDFAndAudio() throws {
        let prepared = try NativeDocuments.prepare(url: fixture("android-library.zip"), profile: "Personal", folder: "")
        XCTAssertEqual(prepared.notebooks.count, 2)
        XCTAssertEqual(prepared.recordingCount, 1)
    }
    @MainActor
    func testNativeStoreSavesAndReopensTypedText() async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(root: directory)
        await store.open()
        let id = store.create(title: "Persistence", folder: "Study", paper: .ruled)
        let pageID = try XCTUnwrap(store.notebook(id)?.pages.first?.id)
        store.changePage(id, pageID: pageID) { page in page.body = page.newBody(); page.body["text"] = .string("Saved offline") }
        let saved = await store.flush(); XCTAssertTrue(saved)
        let reopened = LibraryStore(root: directory); await reopened.open()
        XCTAssertEqual(reopened.notebook(id)?.pages[0].body.text("text"), "Saved offline")
        XCTAssertFalse(reopened.isSaving)
    }
    @MainActor
    func testFirstInsertionOnBlankPageIsAllowed() {
        let controller = NativeCanvasController(page: Page(), assetRoot: root())
        controller.loadViewIfNeeded()
        let textView = UITextView()
        textView.text = nil
        XCTAssertTrue(controller.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementText: "First note"))
    }
    @MainActor
    func testOverfullPasteIsRejectedBeforeReplacingExistingText() {
        let page = Page()
        let controller = NativeCanvasController(page: page, assetRoot: root())
        controller.loadViewIfNeeded()
        let textView = UITextView(); textView.text = "Keep this"
        var message: String?
        controller.onError = { message = $0 }
        XCTAssertFalse(controller.textView(textView, shouldChangeTextIn: NSRange(location: 0, length: 9), replacementText: String(repeating: "Too much text\n", count: 500)))
        XCTAssertEqual(textView.text, "Keep this")
        XCTAssertNotNil(message)
    }
}
