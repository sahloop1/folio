import SwiftUI
import UIKit
import UniformTypeIdentifiers
import FolioCore

struct LibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var audio: AudioController
    @State private var path: [String] = []
    @State private var search = ""
    @State private var folder = ""
    @State private var filter = "All materials"
    @State private var sort = "Last edited"
    @State private var importVisible = false
    @State private var newVisible = false
    @State private var graphVisible = false
    @State private var profilePrompt = false
    @State private var folderPrompt = false
    @State private var promptText = ""
    @State private var editing: Notebook?
    @State private var deleting: Notebook?
    private var filtered: [Notebook] {
        store.notebooks.filter { notebook in
            notebook.profile == store.profile && notebook.trashed == (filter == "Trash")
                && (filter != "Favorites" || notebook.favorite) && (folder.isEmpty || notebook.folder == folder)
                && notebook.matches(search)
        }.sorted { sort == "Name" ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.updated > $1.updated }
    }
    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let error = store.loadError {
                    ContentUnavailableView {
                        Label("Your library could not open", systemImage: "externaldrive.badge.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Retry") { Task { await store.open() } }
                        Button("Recover previous save") { Task { await store.open(recover: true) } }
                    }
                } else if !store.isLoaded { ProgressView("Opening your library…") }
                else { library }
            }
            .background(FolioStyle.background)
            .navigationTitle("Folio")
            .toolbar { libraryToolbar }
            .searchable(text: $search, prompt: "Search titles, tags, sections, and typed notes")
            .navigationDestination(for: String.self) { id in NotebookDesk(mainID: id) }
            .fileImporter(isPresented: $importVisible, allowedContentTypes: [.folioNotebook, .zip, .pdf, .plainText, .data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { Task { await store.prepareImport(url, folder: folder) } }
                case .failure(let error): store.error = error.localizedDescription
                }
            }
            .sheet(isPresented: $newVisible) { NotebookForm(folder: folder) { id in path.append(id) } }
            .sheet(item: $editing) { notebook in NotebookForm(existing: notebook, folder: notebook.folder) { _ in } }
            .sheet(isPresented: $graphVisible) { KnowledgeMapView { id in graphVisible = false; path.append(id) } }
            .alert("New profile", isPresented: $profilePrompt) {
                TextField("Profile name", text: $promptText)
                Button("Create") { let value = promptText.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty { store.selectProfile(String(value.prefix(60))); folder = "" } }
                Button("Cancel", role: .cancel) {}
            }
            .alert("New folder", isPresented: $folderPrompt) {
                TextField("Folder name", text: $promptText)
                Button("Create") { let value = promptText.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty { folder = String(value.prefix(120)); store.addFolder(folder) } }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Permanently delete this notebook?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete notebook", role: .destructive) { if let notebook = deleting { Task { await store.purge(notebook.id) } }; deleting = nil }
            } message: { Text("Export a backup first if you may need it again.") }
            .onChange(of: store.profile) { _, _ in folder = "" }
            .onOpenURL { url in openLibraryURL(url) }
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                ForEach(store.profiles, id: \.self) { name in
                    let icon = name == store.profile ? "checkmark" : "person"
                    Button {
                        store.selectProfile(name)
                        folder = ""
                    } label: {
                        Label(name, systemImage: icon)
                    }
                }
                Divider(); Button("New profile", systemImage: "person.badge.plus") { promptText = ""; profilePrompt = true }
            } label: { Label(store.profile, systemImage: "person.crop.circle") }
            .disabled(!store.isLoaded)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { graphVisible = true } label: { Image(systemName: "point.3.connected.trianglepath.dotted") }.accessibilityLabel("Knowledge map")
            Menu {
                Button("Import from Files", systemImage: "square.and.arrow.down") { importVisible = true }
                Button("Back up whole library", systemImage: "externaldrive") { Task { await store.export() } }
                Button("New folder", systemImage: "folder.badge.plus") { promptText = ""; folderPrompt = true }
                if store.isSaving { Button("Retry saving", systemImage: "arrow.clockwise") { Task { _ = await store.flush() } } }
            } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Library actions")
            Button { newVisible = true } label: { Label("New notebook", systemImage: "plus") }.accessibilityIdentifier("new-notebook")
        }.disabled(!store.isLoaded)
    }

    private func openLibraryURL(_ url: URL) {
        if url.isFileURL {
            Task { await store.prepareImport(url, folder: folder) }
            return
        }

        guard url.scheme == "folio", url.host == "notebook" else { return }
        let notebookID = String(url.path.dropFirst())
        guard let notebook = store.notebook(notebookID), !notebook.trashed else { return }
        store.selectProfile(notebook.profile)
        path = [notebook.id]
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Room for your thinking.").font(.system(size: 34, weight: .regular, design: .serif))
                    Text("Your notebooks, on your iPad.").foregroundStyle(.secondary)
                }.padding(.top, 18)
                HStack {
                    Picker("Collection", selection: $filter) { ForEach(["All materials", "Favorites", "Trash"], id: \.self) { Text($0) } }.pickerStyle(.segmented).frame(maxWidth: 460)
                    Spacer()
                    Menu { Picker("Sort", selection: $sort) { Text("Last edited").tag("Last edited"); Text("Name").tag("Name") } } label: { Label(sort, systemImage: "arrow.up.arrow.down") }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        folderButton("All folders", value: "")
                        ForEach(store.folders, id: \.self) { folderButton($0, value: $0) }
                    }
                }
                if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "A fresh page starts here" : "No matching materials",
                        systemImage: search.isEmpty ? "book.closed" : "magnifyingglass",
                        description: Text(search.isEmpty ? "Create a notebook or import your Folio library, PDF, or Word file." : "Try a title, tag, or phrase from your typed notes."))
                        .padding(.vertical, 50)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 185, maximum: 250), spacing: 24)], alignment: .leading, spacing: 30) {
                        ForEach(filtered) { notebook in
                            Button { if !notebook.trashed { path.append(notebook.id) } } label: { NotebookCard(notebook: notebook) }
                                .buttonStyle(.plain).accessibilityIdentifier("notebook-" + notebook.title)
                                .contextMenu {
                                    if notebook.trashed {
                                        Button("Restore", systemImage: "arrow.uturn.backward") { store.change(notebook.id) { $0.trashed = false } }
                                        Button("Delete permanently", systemImage: "trash", role: .destructive) { deleting = notebook }
                                    } else {
                                        Button("Open", systemImage: "book") { path.append(notebook.id) }
                                        Button("Edit details", systemImage: "pencil") { editing = notebook }
                                        Button(notebook.favorite ? "Remove favorite" : "Favorite", systemImage: "star") { store.change(notebook.id) { $0.favorite.toggle() } }
                                        Button("Duplicate", systemImage: "doc.on.doc") { store.duplicate(notebook.id) }
                                        Button("Export editable notebook", systemImage: "square.and.arrow.up") { Task { await store.export(notebook) } }
                                        Button("Move to Trash", systemImage: "trash", role: .destructive) { store.change(notebook.id) { $0.trashed = true } }
                                    }
                                }
                        }
                    }
                }
                HStack { SavingIndicator(); Spacer(); Text("Offline · No account required").font(.caption).foregroundStyle(.secondary) }.padding(.top, 20)
            }.padding(.horizontal, 32).padding(.bottom, 36)
        }
    }
    private func folderButton(_ title: String, value: String) -> some View {
        Button { folder = value } label: {
            Label(title, systemImage: "folder").font(.subheadline).padding(.horizontal, 16).padding(.vertical, 10)
                .background(folder == value ? FolioStyle.sage.opacity(0.18) : FolioStyle.panel, in: Capsule())
        }.buttonStyle(.plain)
    }
}

struct NotebookCard: View {
    let notebook: Notebook
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: UIColor(argb: notebook.color)).gradient)
                Rectangle().fill(.black.opacity(0.13)).frame(width: 13).padding(.leading, 13)
                VStack(alignment: .leading) {
                    HStack { Image(systemName: notebook.kind == "PDF" ? "doc.richtext" : "book.closed"); Spacer(); if notebook.favorite { Image(systemName: "star.fill") } }.font(.caption)
                    Spacer()
                    Text(notebook.title).font(.system(size: 23, weight: .medium, design: .serif)).lineLimit(4)
                    Text(notebook.kind.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).padding(.top, 4)
                }.padding(22).padding(.leading, 9).foregroundStyle(Color.black.opacity(0.75))
            }.frame(height: 235).shadow(color: .black.opacity(0.2), radius: 10, y: 6)
            Text(notebook.title).font(.headline).lineLimit(1)
            Text("\(notebook.pages.count) pages · \(notebook.folder.isEmpty ? "Unfiled" : notebook.folder)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if !notebook.tags.isEmpty { Text(notebook.tags.prefix(3).map { "#" + $0 }.joined(separator: "  ")).font(.caption).foregroundStyle(FolioStyle.sage).lineLimit(1) }
        }.contentShape(Rectangle())
    }
}
