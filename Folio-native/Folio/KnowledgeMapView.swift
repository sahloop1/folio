import SwiftUI
import UIKit
import FolioCore

/// A local, accessible map of folder neighbors and explicitly linked notebooks.
struct KnowledgeMapView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let onOpen: (String) -> Void
    @State private var search = ""
    @State private var selectedID: String?
    private var books: [Notebook] { store.notebooks.filter { !$0.trashed && $0.profile == store.profile && $0.matches(search) }.sorted { $0.title < $1.title } }
    private var edges: [(String, String)] {
        let values = books, ids = Set(values.map(\.id))
        var result: [(String, String)] = []
        var folderFirst: [String: String] = [:]
        for book in values {
            if !book.folder.isEmpty {
                if let first = folderFirst[book.folder] { result.append((first, book.id)) }
                else { folderFirst[book.folder] = book.id }
            }
            for page in book.pages {
                for label in page.labels + (page.body.isEmpty ? [] : [page.body]) {
                    if let target = NotebookLink.target(label.text("link")), ids.contains(target.notebook), target.notebook != book.id { result.append((book.id, target.notebook)) }
                }
            }
        }
        return result
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    let values = Array(books.prefix(120)), size = geometry.size
                    let positions = Dictionary(uniqueKeysWithValues: values.enumerated().map { index, book in
                        let angle = Double(index) * 2.399963229728653
                        let radius = sqrt(Double(index + 1) / Double(max(1, values.count))) * Double(min(size.width, size.height)) * 0.39
                        return (book.id, CGPoint(x: Double(size.width) / 2 + cos(angle) * radius, y: Double(size.height) / 2 + sin(angle) * radius))
                    })
                    ZStack {
                        Canvas { context, _ in
                            for edge in edges {
                                if let a = positions[edge.0], let b = positions[edge.1] {
                                    var path = Path(); path.move(to: a); path.addLine(to: b)
                                    context.stroke(path, with: .color(FolioStyle.sage.opacity(0.25)), lineWidth: 1)
                                }
                            }
                        }.accessibilityHidden(true)
                        ForEach(values) { book in
                            if let position = positions[book.id] {
                                Button { selectedID = book.id } label: {
                                    VStack(spacing: 4) {
                                        Circle().fill(Color(uiColor: UIColor(argb: book.color))).frame(width: selectedID == book.id ? 26 : 17, height: selectedID == book.id ? 26 : 17)
                                        Text(book.title).font(.caption2).lineLimit(1).frame(width: 90)
                                    }
                                }.buttonStyle(.plain).position(position).accessibilityLabel("Select " + book.title)
                            }
                        }
                    }
                }.frame(minHeight: 160, maxHeight: 380).background(FolioStyle.background)
                if let id = selectedID, let book = store.notebook(id) {
                    HStack { Text(book.title).lineLimit(1); Spacer(); Button("Open notebook") { onOpen(id) } }.padding()
                }
                List(books) { book in
                    Button { onOpen(book.id) } label: {
                        Label { VStack(alignment: .leading) { Text(book.title); Text(book.folder.isEmpty ? book.kind : book.folder).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "book.closed") }
                    }
                }
            }.navigationTitle("Knowledge map").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $search, prompt: "Find a notebook")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
