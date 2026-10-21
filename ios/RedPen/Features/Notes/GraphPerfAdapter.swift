import Foundation

// The Performance theme's one tie to the app's notes: the note store's notes,
// folders and links, and the map's filter, turned into the engine's own
// arrays and types (GraphPerfInput, GraphPerfFilter). Everything else in the
// engine (GraphPerf*.swift) knows nothing of Stethoscore, so the standalone
// 3D Knowledge Graph app can take it and write its own adapter.

/// A snapshot of the store for the map, numbered so the map rebuilds only
/// when the notes, folders, links or link length changed.
struct GraphPerfSource: Equatable {
    let version: Int
    let input: GraphPerfInput

    static func == (a: GraphPerfSource, b: GraphPerfSource) -> Bool {
        a.version == b.version
    }
}

@MainActor
enum GraphPerfAdapter {
    /// The store's notes (kind, folder, title), folders (parent, name) and
    /// links as the engine's arrays.
    static func input(store: NoteStore, edges: [(UUID, UUID)], linkScale: Double) -> GraphPerfInput {
        let notes: [Note] = store.notes
        let folders: [NoteFolder] = store.folders
        let isPage: [Bool] = notes.map { $0.kind == .page }
        let noteFolders: [UUID?] = notes.map { $0.folderId }
        let parents: [UUID?] = folders.map { $0.parentId }
        return GraphPerfInput.make(noteIDs: notes.map { $0.id }, isPage: isPage, noteFolders: noteFolders,
                                   folderIDs: folders.map { $0.id }, folderParents: parents, links: edges,
                                   linkScale: Float(linkScale), noteTitles: notes.map { $0.title },
                                   folderNames: folders.map { $0.name })
    }

    /// The map's filter, without the app's types.
    static func filter(_ filter: GraphFilter) -> GraphPerfFilter {
        switch filter {
        case .all: return .all
        case .pages: return .pages
        case .ideas: return .ideas
        case .linked: return .linked
        case .folder(let id): return .folder(id)
        }
    }
}
