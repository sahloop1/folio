import SwiftUI
import UIKit
import FolioCore

struct NotebookForm: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let existing: Notebook?
    let onCreated: (String) -> Void
    @State private var title: String
    @State private var folder: String
    @State private var tags: String
    @State private var profile: String
    @State private var paper = Paper.ruled
    @State private var color: Double
    init(existing: Notebook? = nil, folder: String, onCreated: @escaping (String) -> Void) {
        self.existing = existing; self.onCreated = onCreated
        _title = State(initialValue: existing?.title ?? "")
        _folder = State(initialValue: folder); _tags = State(initialValue: existing?.tags.joined(separator: ", ") ?? "")
        _profile = State(initialValue: existing?.profile ?? "")
        _color = State(initialValue: existing?.color ?? FolioStyle.covers[0])
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Notebook") {
                    TextField("Title", text: $title).accessibilityIdentifier("notebook-title")
                    TextField("Folder (optional)", text: $folder)
                    TextField("Tags, separated by commas", text: $tags)
                    if existing != nil { Picker("Profile", selection: $profile) { ForEach(store.profiles, id: \.self) { Text($0) } } }
                }
                if existing == nil { Section("Paper") { Picker("Layout", selection: $paper) { ForEach(Paper.allCases) { Text($0.rawValue).tag($0) } } } }
                Section("Cover") {
                    HStack(spacing: 14) {
                        ForEach(FolioStyle.covers, id: \.self) { value in
                            Button { color = value } label: {
                                Circle().fill(Color(uiColor: UIColor(argb: value))).frame(width: 32, height: 32)
                                    .overlay { if color == value { Image(systemName: "checkmark").foregroundStyle(.black) } }
                            }.buttonStyle(.plain).accessibilityLabel("Cover color \(Int(value))")
                        }
                    }.padding(.vertical, 8)
                }
            }
            .navigationTitle(existing == nil ? "New notebook" : "Notebook details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Create" : "Save") {
                        if let existing {
                            store.change(existing.id) { book in book.title = title.trimmingCharacters(in: .whitespacesAndNewlines); book.folder = folder; book.tags = store.parseTags(tags); book.color = color; book.profile = profile }
                            dismiss()
                        } else {
                            let id = store.create(title: title, folder: folder, paper: paper, tags: tags, color: color)
                            dismiss(); onCreated(id)
                        }
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("save-notebook")
                }
            }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
}

struct ImportSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let preview: ImportPreview
    @State private var preferences = true
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Ready to import", systemImage: "checkmark.shield").font(.title2)
                    Text(preview.title).foregroundStyle(.secondary)
                    LabeledContent("Notebooks", value: "\(preview.prepared.notebooks.count)")
                    LabeledContent("Pages", value: "\(preview.prepared.pageCount)")
                    LabeledContent("Recordings", value: "\(preview.prepared.recordingCount)")
                }
                Section {
                    Text("Your existing notebooks are kept. Conflicting notebooks become separate copies. Handwriting, text, PDFs, recordings, and Trash are included.")
                    if preview.prepared.isLibrary { Toggle("Include imported profiles and folders", isOn: $preferences) }
                }
                Section("Materials") { ForEach(preview.prepared.notebooks) { notebook in Label(notebook.title + (notebook.trashed ? " · Trash" : ""), systemImage: "book.closed") } }
            }
            .navigationTitle("Import into Folio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { store.preview = nil; dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Import") { Task { await store.importConfirmed(preview, usePreferences: preferences) } }.disabled(store.busy != nil) }
            }
        }.presentationDetents([.large])
    }
}
