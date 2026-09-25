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
/// one style for every note, or "Star systems", where each note's role
/// picks it; and optionally a style per top-level folder, which wins.
///
/// Stored in UserDefaults (the view reads the same keys with @AppStorage,
/// so a change rebuilds the space). The design preview (`-graphPreview`)
/// always shows star systems and never reads or writes the owner's choice.
@MainActor
enum GraphStyleChoice {
    static let key = "vignette.space.nodeStyle"
    static let foldersKey = "vignette.space.nodeStyleFolders"
    /// The stored value for star systems.
    static let auto = "auto"
    /// Until the owner chooses, every note is a black hole, as before.
    static let standard = GraphNodeStyle.blackHole.rawValue

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

    static func resolve(store: NoteStore, main: String, folderRaw: String) -> [UUID: GraphNodeStyle] {
        let byFolder: [UUID: GraphNodeStyle] = folders(folderRaw)
        var result: [UUID: GraphNodeStyle] = [:]
        if let single = GraphNodeStyle(rawValue: main) {
            for note in store.notes { result[note.id] = single }
        } else {
            result = starSystems(store: store)
        }
        guard !byFolder.isEmpty else { return result }
        for note in store.notes {
            guard let root = store.rootFolder(of: note.folderId),
                  let style = byFolder[root] else { continue }
            result[note.id] = style
        }
        return result
    }

    /// Star systems: a note's role in the vault picks its look.
    ///
    /// - the most-linked note of all is the galaxy's black hole;
    /// - each top-level folder's most-linked remaining note is its sun;
    /// - the most recently edited note is a pulsar, a beacon;
    /// - notes with no links wander as comets;
    /// - pages are gas giants, and the other ideas rocky planets.
    static func starSystems(store: NoteStore) -> [UUID: GraphNodeStyle] {
        var degree: [UUID: Int] = [:]
        for edge in store.allEdges() {
            degree[edge.0, default: 0] += 1
            degree[edge.1, default: 0] += 1
        }
        var result: [UUID: GraphNodeStyle] = [:]
        // the most linked, ties broken by title so it never flickers
        let ranked: [Note] = store.notes.sorted { a, b in
            let da: Int = degree[a.id] ?? 0
            let db: Int = degree[b.id] ?? 0
            if da != db { return da > db }
            return a.title < b.title
        }
        if let core = ranked.first, (degree[core.id] ?? 0) >= 2 {
            result[core.id] = .blackHole
        }
        var litRoots = Set<String>()
        for note in ranked where result[note.id] == nil && (degree[note.id] ?? 0) >= 1 {
            let root: String = store.rootFolder(of: note.folderId)?.uuidString ?? "none"
            if litRoots.insert(root).inserted { result[note.id] = .sun }
        }
        let recent: Note? = store.notes
            .filter { result[$0.id] == nil }
            .max { $0.updatedAt < $1.updatedAt }
        if let recent { result[recent.id] = .pulsar }
        for note in store.notes where result[note.id] == nil {
            let links: Int = degree[note.id] ?? 0
            if links == 0 {
                result[note.id] = .comet
            } else {
                result[note.id] = note.kind == .page ? .gasGiant : .rocky
            }
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
/// one choice for every note, and a submenu with a choice per top-level
/// folder.
struct GraphStyleTool: View {
    @Binding var main: String
    @Binding var folderRaw: String
    let folders: [NoteFolder]

    var body: some View {
        let custom: Bool = main != GraphStyleChoice.standard || !folderRaw.isEmpty
        let ink: Color = custom ? Color.accentColor : Color.secondary
        let glass: Glass = IdeaToolGlass.glass(active: custom)
        Menu {
            Picker("Look", selection: $main) {
                Label("Star systems", systemImage: "sparkles").tag(GraphStyleChoice.auto)
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
        } label: {
            IdeaToolFace(symbol: "sparkles")
        }
        .foregroundStyle(ink)
        .glassEffect(glass, in: .circle)
        .popOut(.floating, in: Circle())
        .hoverEffect(.highlight)
        .accessibilityLabel("Look")
        .accessibilityHint("Choose what notes look like: black holes, suns, planets, pulsars or comets.")
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
