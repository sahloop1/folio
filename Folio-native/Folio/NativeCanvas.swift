import SwiftUI
import UIKit
import PencilKit
import FolioCore

struct CanvasSettings: Equatable {
    var fingerDrawing = false
    var typing = false
    var showTools = true
}

@MainActor
final class CanvasActions: ObservableObject {
    weak var controller: NativeCanvasController?
    func undo() { controller?.canvas.undoManager?.undo() }
    func redo() { controller?.canvas.undoManager?.redo() }
    func fit() { controller?.fit(animated: true) }
    func commit() { controller?.commitCurrent() }
}

struct NativeCanvas: UIViewControllerRepresentable {
    var page: Page
    var assetRoot: URL
    var settings: CanvasSettings
    var actions: CanvasActions
    var onChange: (Page) -> Void
    var onLink: (String) -> Void
    var onRecording: (String) -> Void
    var onError: (String) -> Void
    func makeUIViewController(context: Context) -> NativeCanvasController {
        let controller = NativeCanvasController(page: page, assetRoot: assetRoot)
        controller.onChange = onChange; controller.onLink = onLink; controller.onRecording = onRecording
        controller.onError = onError
        controller.settings = settings; actions.controller = controller
        return controller
    }
    func updateUIViewController(_ controller: NativeCanvasController, context: Context) {
        controller.onChange = onChange; controller.onLink = onLink; controller.onRecording = onRecording
        controller.onError = onError
        controller.update(page: page, settings: settings)
        actions.controller = controller
    }
    static func dismantleUIViewController(_ controller: NativeCanvasController, coordinator: ()) { controller.commitCurrent(); controller.hideTools() }
}

private final class PencilCanvas: PKCanvasView {
    var acceptsFinger = false
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Route finger taps to links below the ink unless finger drawing is enabled.
        if let touch = event?.allTouches?.first, touch.type != .pencil, !acceptsFinger { return nil }
        return super.hitTest(point, with: event)
    }
}

private final class PaperSurface: UIView {
    var page: Page
    let assetRoot: URL
    init(page: Page, assetRoot: URL) { self.page = page; self.assetRoot = assetRoot; super.init(frame: .zero); isOpaque = true; contentMode = .redraw }
    required init?(coder: NSCoder) { return nil }
    override func draw(_ rect: CGRect) { if let context = UIGraphicsGetCurrentContext() { PaperRenderer.draw(page, in: context, assetRoot: assetRoot) } }
}

final class NativeCanvasController: UIViewController, UIScrollViewDelegate, PKCanvasViewDelegate, UITextViewDelegate {
    let canvas: PKCanvasView = PencilCanvas()
    private let scroll = UIScrollView(), surface = UIView(), textView = UITextView(), toolPicker = PKToolPicker()
    private let paperView: PaperSurface
    private var page: Page
    private var sentInk: Data?
    private var committedDrawing = PKDrawing()
    private var applying = false, fitted = false
    private var pending: DispatchWorkItem?
    private var linkButtons: [UIButton] = []
    private var observers: [NSObjectProtocol] = []
    var settings = CanvasSettings()
    var onChange: ((Page) -> Void)?
    var onLink: ((String) -> Void)?
    var onRecording: ((String) -> Void)?
    var onError: ((String) -> Void)?

    init(page: Page, assetRoot: URL) {
        self.page = page; paperView = PaperSurface(page: page, assetRoot: assetRoot)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { return nil }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.075, green: 0.09, blue: 0.10, alpha: 1)
        scroll.frame = view.bounds; scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.delegate = self; scroll.maximumZoomScale = 8; scroll.minimumZoomScale = 0.05
        scroll.keyboardDismissMode = .interactive; scroll.contentInsetAdjustmentBehavior = .never
        view.addSubview(scroll); scroll.addSubview(surface); surface.addSubview(paperView)
        surface.addSubview(textView); surface.addSubview(canvas)
        canvas.backgroundColor = .clear; canvas.isOpaque = false; canvas.isScrollEnabled = false
        canvas.delegate = self; canvas.drawingPolicy = .pencilOnly
        canvas.accessibilityLabel = "Handwriting canvas"
        textView.backgroundColor = .clear; textView.delegate = self; textView.isScrollEnabled = false
        textView.textContainerInset = .zero; textView.textContainer.lineFragmentPadding = 0
        textView.accessibilityLabel = "Page text"; textView.accessibilityIdentifier = "page-text"
        toolPicker.addObserver(canvas)
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.commitCurrent() })
        observers.append(NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, let rect = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            self.scroll.contentInset.bottom = max(24, self.view.bounds.maxY - self.view.convert(rect, from: nil).minY + 24)
        })
        applyDrawing(); configureSurface(); applySettings()
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); applySettings() }
    override func viewWillDisappear(_ animated: Bool) { commitCurrent(); hideTools(); super.viewWillDisappear(animated) }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); if !fitted && view.bounds.width > 0 { fit(animated: false); fitted = true } }
    func update(page incoming: Page, settings: CanvasSettings) {
        let changed = page.id != incoming.id
        if changed { commitCurrent(); fitted = false; canvas.undoManager?.removeAllActions() }
        let oldSettings = self.settings
        self.settings = settings; self.page = incoming
        guard isViewLoaded else { return }
        if changed || incoming.pencilData != sentInk { applyDrawing() }
        configureSurface()
        if oldSettings != settings || changed { applySettings() }
    }
    private func applyDrawing() {
        applying = true
        canvas.drawing = InkBridge.drawing(for: page)
        committedDrawing = canvas.drawing
        sentInk = page.pencilData
        applying = false
    }
    private func configureSurface() {
        // Reset transform while updating unscaled paper geometry, then restore the shared native zoom.
        let zoom = scroll.zoomScale
        surface.transform = .identity
        surface.frame = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        paperView.frame = surface.bounds; canvas.frame = surface.bounds; canvas.contentSize = surface.bounds.size
        paperView.page = page; paperView.setNeedsDisplay()
        let body = page.body.isEmpty ? page.newBody() : page.body
        if textView.text != body.text("text") {
            let selection = textView.selectedRange
            textView.attributedText = NSAttributedString(string: body.text("text"), attributes: PaperRenderer.attributes(body))
            textView.selectedRange = NSRange(location: min(selection.location, (textView.text as NSString).length), length: 0)
        }
        textView.accessibilityValue = body.text("text")
        textView.typingAttributes = PaperRenderer.attributes(body)
        textView.frame = CGRect(x: body.number("x", 80), y: body.number("y", 100),
                                width: body.number("width", page.width - 160), height: max(100, page.height - body.number("y", 100) - 60))
        surface.transform = CGAffineTransform(scaleX: zoom, y: zoom)
        surface.frame.origin = .zero; scroll.contentSize = surface.frame.size
        rebuildLinks(); centerPaper()
    }
    private func rebuildLinks() {
        for button in linkButtons { button.removeFromSuperview() }; linkButtons.removeAll()
        for label in page.labels where !label.text("link").isEmpty {
            let button = UIButton(type: .custom); button.frame = PaperRenderer.textRect(label, page: page)
            button.accessibilityLabel = label.text("text"); button.accessibilityTraits = .link
            button.addAction(UIAction { [weak self] _ in self?.onLink?(label.text("link")) }, for: .touchUpInside)
            surface.insertSubview(button, belowSubview: canvas); linkButtons.append(button)
        }
        for note in page.recordings {
            let button = UIButton(type: .custom)
            button.frame = CGRect(x: note.number("x", 110), y: note.number("y", 130), width: 400, height: 50)
            button.accessibilityLabel = "Play " + note.text("title", "voice note")
            button.addAction(UIAction { [weak self] _ in self?.onRecording?(note.text("file")) }, for: .touchUpInside)
            surface.insertSubview(button, belowSubview: canvas); linkButtons.append(button)
        }
    }
    private func applySettings() {
        let pencil = canvas as! PencilCanvas
        pencil.acceptsFinger = settings.fingerDrawing && !settings.typing
        canvas.drawingPolicy = pencil.acceptsFinger ? .anyInput : .pencilOnly
        canvas.isUserInteractionEnabled = !settings.typing
        scroll.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scroll.panGestureRecognizer.minimumNumberOfTouches = pencil.acceptsFinger ? 2 : 1
        textView.isEditable = settings.typing; textView.isSelectable = settings.typing; textView.isUserInteractionEnabled = settings.typing
        if settings.typing {
            toolPicker.setVisible(false, forFirstResponder: canvas)
            canvas.resignFirstResponder()
            textView.becomeFirstResponder()
        } else if settings.showTools {
            textView.resignFirstResponder()
            toolPicker.setVisible(true, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
        } else {
            toolPicker.setVisible(false, forFirstResponder: canvas)
            textView.resignFirstResponder()
        }
    }
    func hideTools() { toolPicker.setVisible(false, forFirstResponder: canvas) }
    func fit(animated: Bool) {
        guard isViewLoaded else { return }
        let scale = max(0.05, min(2, (scroll.bounds.width - 40) / page.width))
        scroll.setZoomScale(scale, animated: animated); centerPaper()
    }
    private func centerPaper() {
        scroll.contentInset.left = max(20, (scroll.bounds.width - surface.frame.width) / 2)
        scroll.contentInset.right = scroll.contentInset.left
        scroll.contentInset.top = 24
        scroll.contentInset.bottom = max(24, scroll.contentInset.bottom)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { surface }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPaper() }
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !applying else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commitCurrent() }
        pending = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }
    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) { commitCurrent() }
    func commitCurrent() {
        pending?.cancel(); pending = nil
        guard isViewLoaded, !applying else { return }
        let textChanged = updatePageText()
        let drawing = canvas.drawing
        let inkChanged = drawing != committedDrawing
        if inkChanged {
            InkBridge.save(drawing, to: &page)
            committedDrawing = drawing
            sentInk = page.pencilData
        }
        if textChanged || inkChanged { onChange?(page) }
    }
    func textViewDidChange(_ textView: UITextView) {
        if updatePageText() { onChange?(page) }
    }
    func textViewDidEndEditing(_ textView: UITextView) {
        if updatePageText() { onChange?(page) }
    }
    private func updatePageText() -> Bool {
        let text = textView.text ?? ""
        var body = page.body.isEmpty ? page.newBody() : page.body
        guard text != body.text("text") else { return false }
        body["text"] = .string(text); page.body = body
        textView.accessibilityValue = text
        // Expand plain paper within its supported size; reject an overfull edit without truncating it.
        let bottom = PaperRenderer.textRect(body, page: page).maxY + 70
        if bottom > page.height {
            let maximum = min(10_000, page.baseHeight * 1.5)
            if page.pdf.isEmpty && bottom <= maximum {
                page.raw["baseHeight"] = .number(page.baseHeight); page.height = bottom; configureSurface()
            }
            else {
                // Keep the complete text in the model. The editor scrolls it instead of dropping characters.
                textView.isScrollEnabled = true
            }
        }
        return true
    }
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let current = (textView.text ?? "") as NSString
        guard range.location >= 0, range.location <= current.length,
              range.length >= 0, range.length <= current.length - range.location else { return false }
        var body = page.body.isEmpty ? page.newBody() : page.body
        body["text"] = .string(current.replacingCharacters(in: range, with: text))
        let maximum = page.pdf.isEmpty ? min(10_000, page.baseHeight * 1.5) : page.height
        guard PaperRenderer.textRect(body, page: page).maxY + 70 <= maximum else {
            onError?("This text would extend past the page. Add a new page or shorten the text; the current text has been kept.")
            return false
        }
        return true
    }
}
