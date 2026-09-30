import SwiftUI
import UIKit

/// What a note looks like in the Space. Each is physically inspired, with
/// its own look at rest, its own answer to being dragged, and its own
/// effect on the links that reach it (see GraphStyleShaders.link):
///
/// - black hole: a black sphere, a Doppler-bright photon ring, lensed arcs,
///   a Keplerian accretion disk; links bend in and fall into it;
/// - sun: granulation, limb darkening, corona, prominences and flares;
///   links run whiter near it and it throws its pulses out as plasma;
/// - rocky planet: continents, clouds, a terminator towards the nearest
///   sun, air, a moon that lags when dragged; pulses glint on arrival;
/// - gas giant: banded clouds with jets and a storm, a tilted ring with
///   shadows; dragged, the bands smear; links light a bar on the ring;
/// - pulsar: a tiny core and two sweeping beams; its links beat in step;
/// - comet: a nucleus, a coma and two tails pointing away from the
///   nearest sun, stretching when it moves.
///
/// The raw value is stored; `code` is what the link shader reads, and also
/// which end of a link sends: the higher code is the link's A end.
nonisolated enum GraphNodeStyle: String, CaseIterable, Sendable, Identifiable {
    case blackHole
    case rocky
    case gasGiant
    case comet
    case pulsar
    case sun

    var id: String { rawValue }

    /// The link shader's number for this style (0...5), and its send rank.
    var code: Int {
        switch self {
        case .blackHole: return 0
        case .rocky: return 1
        case .gasGiant: return 2
        case .comet: return 3
        case .pulsar: return 4
        case .sun: return 5
        }
    }

    var name: String {
        switch self {
        case .blackHole: return "Black holes"
        case .sun: return "Suns"
        case .rocky: return "Rocky planets"
        case .gasGiant: return "Gas giants"
        case .pulsar: return "Pulsars"
        case .comet: return "Comets"
        }
    }

    var symbol: String {
        switch self {
        case .blackHole: return "circle.circle.fill"
        case .sun: return "sun.max.fill"
        case .rocky: return "globe.europe.africa.fill"
        case .gasGiant: return "circle.lefthalf.filled"
        case .pulsar: return "dot.radiowaves.left.and.right"
        case .comet: return "sparkle"
        }
    }

    /// The order the picker lists them in.
    static let menuOrder: [GraphNodeStyle] = [.blackHole, .sun, .rocky, .gasGiant, .pulsar, .comet]

    /// How long a pulsar takes to turn once, in seconds. The link shader
    /// beats twice a turn (4/3 a second) and GraphShape.clockPeriod (3000 s)
    /// is a whole number of turns, so the clock's wrap never shows.
    static let pulsarPeriod: Float = 1.5
}

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
/// the map's theme (GraphTheme: Space, Neurons, Circuit); in Space, the
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

    private var chosen: GraphTheme { GraphTheme.stored(theme) }

    var body: some View {
        let space: Bool = chosen == .space
        let custom: Bool = !space || main != GraphStyleChoice.auto || !folderRaw.isEmpty
        let ink: Color = custom ? Color.accentColor : Color.secondary
        let glass: Glass = IdeaToolGlass.glass(active: custom)
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
            IdeaToolFace(symbol: space ? "sparkles" : chosen.symbol)
        }
        .foregroundStyle(ink)
        .glassEffect(glass, in: .circle)
        .popOut(.floating, in: Circle())
        .hoverEffect(.highlight)
        .accessibilityLabel("Look")
        .accessibilityHint("Choose the map's theme - space, neurons or circuit - in space how notes look, and curved or straight lines.")
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
