import SwiftUI
import UIKit
import UniformTypeIdentifiers
import FolioCore

@main
@MainActor
struct FolioApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var audio = AudioController()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            LibraryView().environmentObject(store).environmentObject(audio)
                .tint(Color(red: 0.73, green: 0.82, blue: 0.68)).preferredColorScheme(.dark)
                .task { await store.open() }
                .alert("Folio", isPresented: Binding(get: { store.error != nil || audio.error != nil }, set: { if !$0 { store.error = nil; audio.error = nil } })) {
                    Button("OK") { store.error = nil; audio.error = nil }
                } message: { Text(store.error ?? audio.error ?? "") }
                .sheet(item: $store.preview) { preview in ImportSheet(preview: preview).environmentObject(store).interactiveDismissDisabled(store.busy != nil) }
                .sheet(item: $store.sharedFile) { file in NativeShareSheet(url: file.url) }
                .overlay {
                    if let busy = store.busy {
                        ZStack { Color.black.opacity(0.45).ignoresSafeArea(); ProgressView(busy).padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20)) }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { store.flushInBackground(after: audio) }
                }
        }
    }
}

extension UTType {
    static let folioNotebook = UTType(exportedAs: "net.sahlab.folio.notebook", conformingTo: .zip)
}

struct NativeShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

enum FolioStyle {
    static let background = Color(red: 0.055, green: 0.067, blue: 0.075)
    static let panel = Color(red: 0.09, green: 0.105, blue: 0.115)
    static let sage = Color(red: 0.73, green: 0.82, blue: 0.68)
    static let covers: [Double] = [-8413747, -6443631, -3826042, -5663296, -3352703, -8738901, -5077607, -9471855]
}

struct SavingIndicator: View {
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        Label(store.isSaving ? "Saving…" : "Saved on iPad", systemImage: store.isSaving ? "arrow.triangle.2.circlepath" : "checkmark.circle")
            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("save-status")
    }
}
