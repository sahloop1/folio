import SwiftUI
import UIKit
import FolioCore

struct PageBrowser: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let bookID: String
    let selectedID: String
    let onSelect: (String) -> Void
    @State private var search = "", sectionTitle = "", parentID = ""
    @State private var removing: String?

    var body: some View {
        NavigationStack {
            if let notebook = store.notebook(bookID) {
                List {
                    if !notebook.sections.isEmpty {
                        Section("Contents") {
                            ForEach(notebook.sections) { section in
                                Button { onSelect(section.pageID); dismiss() } label: {
                                    Label(section.title, systemImage: section.parentID.isEmpty ? "bookmark" : "arrow.turn.down.right")
                                }.swipeActions { Button("Remove heading", role: .destructive) { removeSection(section.id) } }
                            }
                        }
                    }
                    Section("Pages · drag to reorder") {
                        ForEach(notebook.pages.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.body.text("text").localizedCaseInsensitiveContains(search) }) { page in
                            Button { onSelect(page.id); dismiss() } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: page.pdf.isEmpty ? "doc.text" : "doc.richtext").font(.title2).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(page.title.isEmpty ? "Page \((notebook.pages.firstIndex { $0.id == page.id } ?? 0) + 1)" : page.title)
                                        Text(page.body.text("text").isEmpty ? page.paper.rawValue : page.body.text("text")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer()
                                    if page.id == selectedID { Image(systemName: "checkmark.circle.fill") }
                                }.padding(.vertical, 5)
                            }.contextMenu {
                                Button("Duplicate page", systemImage: "doc.on.doc") {
                                    var id = ""; store.change(bookID) { id = $0.insertPage(after: page.id, duplicate: true) }; onSelect(id); dismiss()
                                }
                                Button("Delete page", systemImage: "trash", role: .destructive) { removing = page.id }.disabled(notebook.pages.count <= 1)
                            }
                        }.onMove { source, target in
                            guard search.isEmpty else { return }
                            store.change(bookID) { book in var pages = book.pages; pages.move(fromOffsets: source, toOffset: target); book.pages = pages }
                        }.moveDisabled(!search.isEmpty)
                    }
                    Section("New contents heading on the current page") {
                        TextField("Section title", text: $sectionTitle)
                        Picker("Parent", selection: $parentID) {
                            Text("Top level").tag("")
                            ForEach(notebook.sections) { Text($0.title).tag($0.id) }
                        }
                        Button("Add heading") {
                            let section = NotebookSection(title: sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines), pageID: selectedID, parentID: parentID)
                            store.change(bookID) { $0.sections.append(section) }; sectionTitle = ""
                        }.disabled(sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .searchable(text: $search, prompt: "Page title or typed text")
                .navigationTitle("Pages and contents")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
                .confirmationDialog("Delete this page?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                    Button("Delete page", role: .destructive) {
                        guard let id = removing else { return }
                        do {
                            var book = store.notebook(bookID) ?? notebook
                            try book.removePage(id); store.set(book)
                            if id == selectedID { onSelect(book.pages[0].id) }
                        } catch { store.error = error.localizedDescription }
                        removing = nil
                    }
                } message: { Text("The page will be removed from this notebook. Export an editable backup first to keep a separate copy.") }
            }
        }
    }
    private func removeSection(_ id: String) {
        store.change(bookID) { book in
            let parent = book.sections.first { $0.id == id }?.parentID ?? ""
            book.sections = book.sections.filter { $0.id != id }.map { original in
                var section = original
                if section.parentID == id { section.raw["parentId"] = .string(parent) }
                return section
            }
        }
    }
}

struct PageSettings: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let bookID: String
    let pageID: String
    @State private var title = "", paper = Paper.ruled
    @State private var lines = 32
    @State private var length: Double = 1
    @State private var paperColor: Double = -329745
    @State private var numbered = true
    @State private var firstNumber = 1
    @State private var localError: String?
    private let colors: [Double] = [-329745, -1, -1249295, -14209733]

    var body: some View {
        NavigationStack {
            Form {
                Section("Page") { TextField("Page title", text: $title) }
                if let page = store.notebook(bookID)?.pages.first(where: { $0.id == pageID }), page.pdf.isEmpty {
                    Section("Paper") {
                        Picker("Layout", selection: $paper) { ForEach(Paper.allCases) { Text($0.rawValue).tag($0) } }
                        Stepper("\(lines) lines / rows", value: $lines, in: 4...100)
                        HStack {
                            Text("Color"); Spacer()
                            ForEach(colors, id: \.self) { color in
                                Button { paperColor = color } label: {
                                    Circle().fill(Color(uiColor: UIColor(argb: color))).frame(width: 32, height: 32)
                                        .overlay { Circle().stroke(paperColor == color ? FolioStyle.sage : .gray, lineWidth: paperColor == color ? 3 : 1) }
                                }.buttonStyle(.plain).accessibilityLabel("Paper color \(Int(color))")
                            }
                        }
                    }
                    Section("Page length") {
                        Slider(value: $length, in: 0.5...1.5, step: 0.05)
                        Text("\(Int((length * 100).rounded()))% of original length").monospacedDigit()
                        Text("Ink and text keep their positions. A shorter page is accepted only when all existing content fits.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Notebook page numbers") {
                    Toggle("Show page numbers in PDF", isOn: $numbered)
                    Stepper("Start at \(firstNumber)", value: $firstNumber, in: 1...999_999)
                }
                if let localError { Section { Text(localError).foregroundStyle(.red) } }
            }.navigationTitle("Paper and page")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Apply") { save() } }
                }
                .onAppear {
                    guard let notebook = store.notebook(bookID), let page = notebook.pages.first(where: { $0.id == pageID }) else { return }
                    title = page.title; paper = page.paper; lines = page.lines == 0 ? 32 : page.lines
                    length = page.height / page.baseHeight; paperColor = page.color
                    numbered = notebook.raw.flag("showPageNumbers", true)
                    firstNumber = Int(exactly: notebook.raw.number("firstPageNumber", 1)) ?? 1
                }
        }
    }
    private func save() {
        guard var book = store.notebook(bookID), let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return }
        var pages = book.pages, page = pages[index]
        do {
            page.title = title
            if page.pdf.isEmpty {
                let bottom = PaperRenderer.contentBottom(page)
                try page.resize(to: page.baseHeight * length, contentBottom: bottom)
                page.paper = paper; page.lines = lines; page.color = paperColor
                page.raw["rulingHeight"] = .number(page.height)
            }
            try page.validate(); pages[index] = page; book.pages = pages
            book.raw["showPageNumbers"] = .bool(numbered); book.raw["firstPageNumber"] = .number(Double(firstNumber))
            book.touch(); store.set(book); dismiss()
        } catch { localError = error.localizedDescription }
    }
}

struct PageLabels: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let bookID: String
    let pageID: String
    @State private var labels: [[String: JSONValue]] = []
    @State private var text = "", link = ""
    @State private var localError: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Labels on this page") {
                    ForEach(labels.indices, id: \.self) { index in
                        VStack(alignment: .leading) {
                            TextField("Label", text: Binding(get: { labels[index].text("text") }, set: { labels[index]["text"] = .string($0) }))
                            if !labels[index].text("link").isEmpty { Text(labels[index].text("link")).font(.caption).foregroundStyle(.secondary) }
                        }
                    }.onDelete { labels.remove(atOffsets: $0) }
                }
                Section("Add label or link") {
                    TextField("Label text", text: $text)
                    TextField("Website or copied Folio page link (optional)", text: $link).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Add to page") {
                        do {
                            let destination = link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : try NotebookLink.normalize(link)
                            labels.append(["text": .string(text), "link": .string(destination), "x": .number(110),
                                "y": .number(min((store.notebook(bookID)?.pages.first { $0.id == pageID }?.height ?? 1414) - 80, 150 + Double(labels.count) * 70)), "size": .number(24), "width": .number(650),
                                "color": .number(destination.isEmpty ? -14340028 : -14120961)])
                            text = ""; link = ""; localError = nil
                        } catch { localError = error.localizedDescription }
                    }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let localError { Text(localError).foregroundStyle(.red) }
            }.navigationTitle("Text labels and links")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { store.changePage(bookID, pageID: pageID) { $0.labels = labels }; dismiss() } }
                }
                .onAppear { labels = store.notebook(bookID)?.pages.first(where: { $0.id == pageID })?.labels ?? [] }
        }
    }
}
