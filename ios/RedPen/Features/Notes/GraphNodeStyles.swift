import SwiftUI
import UIKit

/// Which look the notes take, as the owner chose it in the Space's tools:
/// the Universe (GraphUniverse: folders as black holes and stars, notes as
/// planets, moons, pulsars and comets, by size), or one style for every
/// note in today's force layout; and optionally a style per top-level
/// folder, which re-skins that folder's notes.
///
/// Stored in UserDefaults (the view reads the same keys with @AppStorage,
/// so a change rebuilds the space). A stored "auto" (once "Star systems")
/// is the Universe; a stored style keeps that single look. The design
/// preview (`-graphPreview`) shows the Universe unless a style is asked for,
/// and never reads or writes the owner's choice.
@MainActor
enum GraphStyleChoice {
    static let key = "vignette.space.nodeStyle"
    static let foldersKey = "vignette.space.nodeStyleFolders"
    /// The stored value for the Universe.
    static let auto = "auto"
    /// Until the owner chooses, the Universe.
    static let standard = auto

    /// The main choice in force.
    static var main: String {
        if GraphPreview.isOn { return GraphPreview.style?.rawValue ?? auto }
        return UserDefaults.standard.string(forKey: key) ?? standard
    }

    /// The per-folder choices in force.
    static var folderRaw: String {
        if GraphPreview.isOn { return "" }
        return UserDefaults.standard.string(forKey: foldersKey) ?? ""
    }

    /// "uuid=style;uuid=style" to a map; anything unreadable is skipped.
    static func folders(_ raw: String) -> [UUID: GraphNodeStyle] {
        var found: [UUID: GraphNodeStyle] = [:]
        for part in raw.split(separator: ";") {
            let pieces = part.split(separator: "=")
            guard pieces.count == 2,
                  let id = UUID(uuidString: String(pieces[0])),
                  let style = GraphNodeStyle(rawValue: String(pieces[1])) else { continue }
            found[id] = style
        }
        return found
    }

    static func encode(_ map: [UUID: GraphNodeStyle]) -> String {
        let keys: [UUID] = map.keys.sorted { $0.uuidString < $1.uuidString }
        var parts: [String] = []
        for id in keys {
            guard let style = map[id] else { continue }
            parts.append(id.uuidString + "=" + style.rawValue)
        }
        return parts.joined(separator: ";")
    }

    /// Every note's style, from the choice in force.
    static func resolve(store: NoteStore) -> [UUID: GraphNodeStyle] {
        resolve(store: store, main: main, folderRaw: folderRaw)
    }

    /// Every note's style for the single looks. A main that is not a style
    /// (the Universe, drawn by GraphUniverse instead) falls back to pages as
    /// gas giants and ideas as rocky planets - only a safety net. A folder
    /// look wins for the notes in that top-level folder.
    static func resolve(store: NoteStore, main: String, folderRaw: String) -> [UUID: GraphNodeStyle] {
        var result: [UUID: GraphNodeStyle] = [:]
        let single: GraphNodeStyle? = GraphNodeStyle(rawValue: main)
        for note in store.notes {
            let byKind: GraphNodeStyle = note.kind == .page ? .gasGiant : .rocky
            result[note.id] = single ?? byKind
        }
        let byNote: [UUID: GraphNodeStyle] = overrides(store: store, folderRaw: folderRaw)
        for (id, style) in byNote { result[id] = style }
        return result
    }

    /// Each note's folder look in the single looks, from its top-level
    /// folder. (The Universe goes by its planned galaxy instead:
    /// GraphSceneBuilder.buildUniverse.)
    static func overrides(store: NoteStore, folderRaw: String) -> [UUID: GraphNodeStyle] {
        let byFolder: [UUID: GraphNodeStyle] = folders(folderRaw)
        guard !byFolder.isEmpty else { return [:] }
        var result: [UUID: GraphNodeStyle] = [:]
        for note in store.notes {
            guard let root = store.rootFolder(of: note.folderId), let style = byFolder[root] else { continue }
            result[note.id] = style
        }
        return result
    }

    /// Folder palettes, so two folders of planets are not twins: 0 is an
    /// Earth, 1 a desert world, 2 an ice world (rocky); Jupiter, Saturn,
    /// Neptune (gas giants).
    static func palette(for folder: UUID?) -> Int {
        guard let folder else { return 0 }
        var total: Int = 0
        for scalar in folder.uuidString.unicodeScalars { total = (total &* 31) &+ Int(scalar.value) }
        return abs(total) % 3
    }
}

/// The look tool, in the Space's cluster of round tools (under the thumb
/// on a phone, at the trailing edge on a wide iPad - IdeaTools' placement):
/// the map's theme (GraphTheme: Space, Neurons, Performance); in Space, the
/// Universe or one look for every note and a submenu with a look per
/// top-level folder; Lines, Curved or Straight (IdeaLinesPicker, shared
/// with the board); and, in the Universe or any other theme, what its
/// bodies mean.
struct GraphStyleTool: View {
    @Binding var theme: String
    @Binding var main: String
    @Binding var folderRaw: String
    let folders: [NoteFolder]
    /// Opens the legend (GraphLegendSheet).
    var showLegend: () -> Void = {}
    /// The link length in force, and what brings up its bar over the map
    /// (nil where the map is not planned: the single looks).
    var linkLength: Double = GraphLinkLength.standard
    var tuneLinks: (() -> Void)? = nil
    /// The Neurons' cell states (NeuronStateChoice): one for every note's
    /// cell, and one per region, stored as the space's looks are.
    var cellState: Binding<String> = .constant(NeuronStateChoice.naturalValue)
    var cellFolders: Binding<String> = .constant("")

    private var chosen: GraphTheme { GraphTheme.stored(theme) }

    var body: some View {
        let space: Bool = chosen == .space
        let neurons: Bool = chosen == .neurons
        let cells = NeuronStateChoice(main: cellState.wrappedValue, folderRaw: cellFolders.wrappedValue)
        let custom: Bool = !space || main != GraphStyleChoice.auto || !folderRaw.isEmpty || cells.isCustom
        Menu {
            if GraphTheme.offered.count > 1 {
                Picker("Theme", selection: themeBinding) {
                    ForEach(GraphTheme.offered) { option in
                        Label(option.title, systemImage: option.symbol).tag(option.rawValue)
                    }
                }
                .pickerStyle(.inline)
            }
            if space {
                spaceLooks
            }
            if neurons {
                cellLooks
            }
            // Curved (each theme's own shape) or Straight, in every theme
            IdeaLinesPicker()
            if let tuneLinks {
                Button {
                    tuneLinks()
                } label: {
                    Label("Link length: " + GraphLinkLength.spoken(linkLength), systemImage: "arrow.left.and.right")
                }
                .accessibilityIdentifier("lookLinkLength")
            }
            if !space || GraphNodeStyle(rawValue: main) == nil {
                Button {
                    showLegend()
                } label: {
                    Label(chosen.legendTitle, systemImage: "info.circle")
                }
            }
        } label: {
            IdeaToolFace(symbol: "sparkles")
        }
        .foregroundStyle(IdeaToolFace.ink(active: custom))
        .ideaToolRelief(active: custom)
        .accessibilityLabel("Look")
        .accessibilityHint("Choose the map's theme - space, neurons or performance - how notes look in space, the cells' states in neurons, and curved or straight lines.")
    }

    /// The Space theme's own choices: the Universe or one style for all,
    /// and a style per top-level folder.
    @ViewBuilder
    private var spaceLooks: some View {
        Picker("Look", selection: $main) {
            Label("Universe", systemImage: "sparkles").tag(GraphStyleChoice.auto)
            ForEach(GraphNodeStyle.menuOrder) { style in
                Label(style.name, systemImage: style.symbol).tag(style.rawValue)
            }
        }
        .pickerStyle(.inline)
        if !folders.isEmpty {
            Menu("Folder looks") {
                ForEach(folders) { folder in
                    Picker(folder.name, selection: folderBinding(folder.id)) {
                        Text("Same as all").tag("")
                        ForEach(GraphNodeStyle.menuOrder) { style in
                            Label(style.name, systemImage: style.symbol).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    /// The Neurons' own choices: each cell's state (the space styles'
    /// six, each a process of its own) for all notes, and one per region.
    @ViewBuilder
    private var cellLooks: some View {
        Picker("Cells", selection: cellState) {
            Label("Natural", systemImage: "sparkles").tag(NeuronStateChoice.naturalValue)
            ForEach(NeuronState.menuOrder) { state in
                Label(state.title, systemImage: state.symbol).tag(state.rawValue)
            }
        }
        .pickerStyle(.inline)
        if !folders.isEmpty {
            Menu("Region states") {
                ForEach(folders) { folder in
                    Picker(folder.name, selection: cellFolderBinding(folder.id)) {
                        Text("Same as all").tag("")
                        ForEach(NeuronState.menuOrder) { state in
                            Label(state.title, systemImage: state.symbol).tag(state.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private func cellFolderBinding(_ id: UUID) -> Binding<String> {
        let store: Binding<String> = cellFolders
        return Binding<String>(
            get: { NeuronStateChoice.parse(store.wrappedValue)[id]?.rawValue ?? "" },
            set: { value in
                var map: [UUID: NeuronState] = NeuronStateChoice.parse(store.wrappedValue)
                map[id] = NeuronState(rawValue: value)
                store.wrappedValue = NeuronStateChoice.encode(map)
            }
        )
    }

    /// The stored theme, read back as one the menu offers.
    private var themeBinding: Binding<String> {
        Binding<String>(
            get: { GraphTheme.stored(theme).rawValue },
            set: { theme = $0 }
        )
    }

    private func folderBinding(_ id: UUID) -> Binding<String> {
        Binding<String>(
            get: {
                let map: [UUID: GraphNodeStyle] = GraphStyleChoice.folders(folderRaw)
                return map[id]?.rawValue ?? ""
            },
            set: { value in
                var map: [UUID: GraphNodeStyle] = GraphStyleChoice.folders(folderRaw)
                map[id] = GraphNodeStyle(rawValue: value)
                folderRaw = GraphStyleChoice.encode(map)
            }
        )
    }
}
