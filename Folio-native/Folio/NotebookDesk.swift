import SwiftUI
import UIKit
import FolioCore

struct NotebookDesk: View {
    @EnvironmentObject var store: LibraryStore
    let mainID: String
    @State private var openIDs: [String] = []
    @State private var focusedID: String?
    @State private var addVisible = false
    @State private var linkedPages: [String: String] = [:]

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(openIDs, id: \.self) { id in
                            if let notebook = store.notebook(id) {
                                HStack(spacing: 8) {
                                    Button { focusedID = id } label: { Label(notebook.title, systemImage: "book.closed").lineLimit(1) }
                                    if openIDs.count > 1 {
                                        Button { openIDs.removeAll { $0 == id }; if focusedID == id { focusedID = openIDs.first } } label: { Image(systemName: "xmark").font(.caption) }.accessibilityLabel("Close " + notebook.title)
                                    }
                                }.padding(12).background(focusedID == id ? FolioStyle.sage.opacity(0.18) : FolioStyle.panel, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 10)
                }
                Divider()
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(openIDs, id: \.self) { id in
                            NotebookEditor(bookID: id, active: focusedID == id, requestedPage: linkedPages[id],
                                onActivate: { focusedID = id }, onLink: openLink)
                                .frame(width: openIDs.count > 1 ? max(450, (geometry.size.width - 16) / 2) : geometry.size.width,
                                       height: max(100, geometry.size.height - 66))
                                .id(id)
                        }
                    }.scrollTargetLayout()
                }.scrollPosition(id: $focusedID, anchor: .leading)
            }
        }
        .background(FolioStyle.background)
        .navigationTitle(store.notebook(focusedID ?? mainID)?.title ?? "Notebook")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addVisible = true } label: { Label("Open alongside", systemImage: "rectangle.split.2x1") }.disabled(openIDs.count >= 6)
            }
        }
        .sheet(isPresented: $addVisible) {
            NotebookChooser(excluding: Set(openIDs)) { id in addVisible = false; openNotebook(id) }
        }
        .onAppear { if openIDs.isEmpty { openIDs = [mainID]; focusedID = mainID } }
    }
    private func openNotebook(_ id: String) {
        guard let notebook = store.notebook(id), !notebook.trashed else { store.error = "That notebook is unavailable or in Trash."; return }
        if !openIDs.contains(id) {
            if openIDs.count >= 6 { openIDs.removeLast() }
            openIDs.append(id)
        }
        focusedID = id
    }
    private func openLink(_ text: String) {
        if let target = NotebookLink.target(text) {
            linkedPages[target.notebook] = target.page
            openNotebook(target.notebook)
        } else if let normalized = try? NotebookLink.normalize(text), let url = URL(string: normalized) {
            UIApplication.shared.open(url)
        } else { store.error = "This link cannot be opened." }
    }
}

private struct NotebookChooser: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let excluding: Set<String>
    let onChoose: (String) -> Void
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List(store.notebooks.filter { !$0.trashed && $0.profile == store.profile && !excluding.contains($0.id) && $0.matches(search) }) { notebook in
                Button { onChoose(notebook.id) } label: {
                    Label { VStack(alignment: .leading) { Text(notebook.title); Text(notebook.folder).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "book.closed").foregroundStyle(Color(uiColor: UIColor(argb: notebook.color))) }
                }
            }.searchable(text: $search).navigationTitle("Open alongside")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct NotebookEditor: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var audio: AudioController
    let bookID: String
    let active: Bool
    let requestedPage: String?
    let onActivate: () -> Void
    let onLink: (String) -> Void
    @StateObject private var actions = CanvasActions()
    @State private var pageID = ""
    @State private var settings = CanvasSettings()
    @State private var contentsVisible = false
    @State private var settingsVisible = false
    @State private var labelsVisible = false

    var body: some View {
        if let notebook = store.notebook(bookID), let page = notebook.pages.first(where: { $0.id == pageID }) ?? notebook.pages.first {
            VStack(spacing: 0) {
                HStack {
                    Button { onActivate() } label: { Text(notebook.title).font(.headline).lineLimit(1) }.buttonStyle(.plain)
                    Spacer()
                    Button { actions.commit(); contentsVisible = true } label: { Image(systemName: "list.bullet.rectangle") }.accessibilityLabel("Pages and contents")
                    Menu {
                        Button("Insert page after this", systemImage: "doc.badge.plus") { insertPage(page, duplicate: false) }
                        Button("Duplicate page", systemImage: "doc.on.doc") { insertPage(page, duplicate: true) }
                        Button("Paper and page length", systemImage: "ruler") { actions.commit(); settingsVisible = true }
                        Button("Text labels and links", systemImage: "text.badge.plus") { actions.commit(); labelsVisible = true }
                        Button("Copy page link", systemImage: "link") { UIPasteboard.general.string = NotebookLink.make(notebookID: bookID, pageID: page.id) }
                        Divider()
                        Button("Export PDF", systemImage: "doc.richtext") { actions.commit(); Task { await store.exportPDF(bookID) } }
                        Button("Export editable notebook", systemImage: "square.and.arrow.up") { actions.commit(); Task { await store.export(store.notebook(bookID)) } }
                        Button("Share this page image", systemImage: "photo") { actions.commit(); Task { await store.sharePage(bookID, pageID: page.id) } }
                        Divider()
                        Toggle("Draw with finger", isOn: $settings.fingerDrawing)
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Page options")
                }.padding(.horizontal, 16).padding(.vertical, 12)
                    .background(active ? FolioStyle.sage.opacity(0.08) : FolioStyle.panel)
                HStack(spacing: 16) {
                    Button { actions.undo() } label: { Image(systemName: "arrow.uturn.backward") }.accessibilityLabel("Undo")
                    Button { actions.redo() } label: { Image(systemName: "arrow.uturn.forward") }.accessibilityLabel("Redo")
                    Divider().frame(height: 20)
                    Button { actions.commit(); onActivate(); settings.typing.toggle() } label: { Image(systemName: settings.typing ? "keyboard.chevron.compact.down" : "textformat") }
                        .accessibilityLabel(settings.typing ? "Done typing" : "Type on page").accessibilityIdentifier("toggle-typing")
                    Button { onActivate(); settings.showTools.toggle() } label: { Image(systemName: "pencil.tip.crop.circle") }.accessibilityLabel("Drawing tools")
                    Button { actions.fit() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.accessibilityLabel("Fit page")
                    Spacer()
                    if audio.playing { Button { audio.stopPlayback() } label: { Image(systemName: "stop.circle") }.accessibilityLabel("Stop playback") }
                    Button {
                        actions.commit()
                        if audio.recording { audio.stop() }
                        else {
                            let targetPage = page.id
                            Task { await audio.start { url, duration in await store.attachRecording(url: url, duration: duration, bookID: bookID, pageID: targetPage) } }
                        }
                    } label: { Image(systemName: audio.recording ? "stop.circle.fill" : "mic") }.foregroundStyle(audio.recording ? .red : FolioStyle.sage).accessibilityLabel(audio.recording ? "Stop recording" : "Record voice note")
                }.padding(.horizontal, 16).padding(.vertical, 10)
                Divider()
                NativeCanvas(page: page, assetRoot: store.storage.root,
                    settings: CanvasSettings(fingerDrawing: settings.fingerDrawing, typing: settings.typing && active, showTools: settings.showTools && active), actions: actions,
                    onChange: { changed in store.changePage(bookID, pageID: changed.id) { $0 = changed } },
                    onLink: onLink,
                    onRecording: { filename in audio.play(store.storage.root.appendingPathComponent("audio/" + filename)) },
                    onError: { store.error = $0 })
                    .accessibilityIdentifier("native-canvas")
                Divider()
                HStack {
                    Button { navigate(-1, in: notebook, current: page) } label: { Image(systemName: "chevron.left") }.disabled(notebook.pages.first?.id == page.id).accessibilityLabel("Previous page")
                    Spacer()
                    Text("Page \((notebook.pages.firstIndex { $0.id == page.id } ?? 0) + 1) of \(notebook.pages.count)").font(.caption.monospacedDigit())
                    if !page.title.isEmpty { Text(page.title).font(.caption).lineLimit(1) }
                    Spacer()
                    Button { navigate(1, in: notebook, current: page) } label: { Image(systemName: "chevron.right") }.disabled(notebook.pages.last?.id == page.id).accessibilityLabel("Next page")
                }.padding(14)
                SavingIndicator().padding(.bottom, 8)
            }
            .sheet(isPresented: $contentsVisible) { PageBrowser(bookID: bookID, selectedID: page.id) { id in select(id) } }
            .sheet(isPresented: $settingsVisible) { PageSettings(bookID: bookID, pageID: page.id) }
            .sheet(isPresented: $labelsVisible) { PageLabels(bookID: bookID, pageID: page.id) }
            .onAppear {
                if pageID.isEmpty { pageID = requestedPage ?? notebook.resumePage }
                settings.fingerDrawing = store.preferences.flag("fingerDrawing")
            }
            .onChange(of: requestedPage) { _, value in if let value { select(value) } }
            .onDisappear { actions.commit(); audio.stop(); audio.stopPlayback(); Task { _ = await store.flush() } }
        } else { ContentUnavailableView("Notebook unavailable", systemImage: "book.closed") }
    }
    private func select(_ id: String) {
        guard store.notebook(bookID)?.pages.contains(where: { $0.id == id }) == true else { return }
        actions.commit(); audio.stop(); audio.stopPlayback(); pageID = id
        store.change(bookID) { $0.raw["lastPageId"] = .string(id) }
    }
    private func navigate(_ delta: Int, in notebook: Notebook, current: Page) {
        guard let index = notebook.pages.firstIndex(where: { $0.id == current.id }), notebook.pages.indices.contains(index + delta) else { return }
        select(notebook.pages[index + delta].id)
    }
    private func insertPage(_ page: Page, duplicate: Bool) {
        actions.commit()
        var newID = ""
        store.change(bookID) { newID = $0.insertPage(after: page.id, duplicate: duplicate) }
        select(newID)
    }
}
