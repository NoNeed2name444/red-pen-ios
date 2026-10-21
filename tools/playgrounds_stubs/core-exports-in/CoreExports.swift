import SwiftUI

// Only in the Swift Playgrounds core2 build (make_swiftpm.py --without core2):
// the core plus steps 1 and 2 of the add-back order
// (tools/playgrounds_stubs/README.md), so Anki packages, PDF and set-file
// export, backups, picture cards from photos, occlusion covers and the figure
// finder are the app's own. This file gives the core shell its ways in, and
// stands in for the three names those screens use from the full library.

/// Nothing of step 2 is left out of this build.
enum CoreExportsPart {
    static let missing: [String] = []
}

/// Picture cards from photos, which the full app opens from its Pictures shelf.
struct CoreLibraryExports: View {
    var body: some View {
        Section("Pictures") {
            NavigationLink {
                PictureFromPhotoView()
            } label: {
                Label("Picture cards from photos", systemImage: "photo.on.rectangle.angled")
            }
        }
    }
}

/// Backups and restoring, with the library's other data settings. The full
/// app keeps the Ideas store for the whole app; here it is made for this
/// section, which only reads and restores it.
struct CoreDataSection: View {
    @StateObject private var notes = NoteStore()

    var body: some View {
        LibraryDataSettingsSection()
            .environmentObject(notes)
    }
}

extension View {
    /// A set row's export menu: an Anki deck as .apkg (its schedule and masks
    /// kept), any other set as a printable PDF, or as a set file another copy
    /// of the app can import.
    func coreRowActions(_ set: StudySet) -> some View {
        modifier(CoreRowActions(set: set))
    }
}

private struct CoreRowActions: ViewModifier {
    let set: StudySet
    @State private var shared: SharedFile?
    @State private var failed = false

    private struct SharedFile: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    export()
                } label: {
                    Label(set.kind == .anki ? "Export as Anki deck" : "Export as PDF", systemImage: "square.and.arrow.up")
                }
                Button {
                    if let url = JSONExporter.export(set) { shared = SharedFile(url: url) } else { failed = true }
                } label: {
                    Label("Export as a set file", systemImage: "doc.badge.arrow.up")
                }
            }
            .sheet(item: $shared) { file in
                ShareSheet(items: [file.url])
            }
            .alert("Couldn\u{2019}t export \u{201C}\(set.name)\u{201D}", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            }
    }

    private func export() {
        guard set.kind == .anki else {
            if let url = DeckPDF.export(set) { shared = SharedFile(url: url) } else { failed = true }
            return
        }
        let restored: StudySet = BlobCache().restore(set)
        Task {
            do {
                let url: URL = try await ApkgExporter.exportInBackground(restored)
                shared = SharedFile(url: url)
            } catch {
                failed = true
            }
        }
    }
}

// MARK: - Names the picture screen uses from the full library

/// The library's shelves (Features/Library/StudyCategory.swift): only the
/// Pictures shelf, which the picture screen offers to save into.
enum CategoryFeature {
    case pictures

    @MainActor func shelfSets(_ store: Store) -> [StudySet] {
        store.library
            .filter { set in set.kind == .anki && set.cards.contains { $0.type == .occlusion } }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

/// A shelf's heading (StudyCategory.swift).
struct CategoryHeading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A set opened in its mode (CategoryPages.swift): the core's own screen.
struct StudySetScreen: View {
    let set: StudySet

    var body: some View { CoreSetScreen(set: set) }
}
