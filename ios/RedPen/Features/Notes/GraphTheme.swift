import Foundation

// MARK: - The map's themes
//
// The 3D Ideas map can be drawn in one of several themes, each its own
// picture of the same hierarchy (folders, subfolders, pages, ideas, links):
//
//   Space     the Universe (GraphUniverse): black holes, stars, planets,
//             moons, pulsars and comets; the default
//   Neurons   a nervous system (GraphNeurons): regions, relays down the
//             pathway, neurons, glia and receptors, joined by axons that
//             carry impulses
//   Circuit   a circuit board (GraphCircuit): the vault the motherboard,
//             processors, modules on their sub-boards, capacitors,
//             resistors, LEDs, diodes and headers, joined by routed copper
//             traces carrying current
//
// Every theme other than Space is planned by a pure Foundation planner into
// a ThemePlan (GraphThemePlan.swift) and built by the shared theme scene
// (GraphThemeScene.swift) with the theme's own look (GraphThemeLook), so a
// new theme adds a planner, a look and its legend - nothing else changes.
// The Graphics setting (GraphicsQuality.swift) applies to every theme.
//
// Foundation only: the choice and its words are tested on Linux.

nonisolated enum GraphTheme: String, CaseIterable, Sendable, Identifiable {
    case space
    case neurons
    case circuit

    var id: String { rawValue }

    /// Stored in UserDefaults (Graph3DView reads it with @AppStorage, so a
    /// change rebuilds the map).
    static let key = "vignette.space.theme"
    static let standard: GraphTheme = .space

    /// Whether it can be chosen (a theme still being built is not).
    var isReady: Bool {
        switch self {
        case .space, .neurons, .circuit: return true
        }
    }

    /// The themes the Look menu offers, in its order.
    static var offered: [GraphTheme] {
        allCases.filter { $0.isReady }
    }

    /// A stored value, or the default for anything unknown or not ready.
    static func stored(_ raw: String?) -> GraphTheme {
        guard let raw, let theme = GraphTheme(rawValue: raw), theme.isReady else { return standard }
        return theme
    }

    var title: String {
        switch self {
        case .space: return "Space"
        case .neurons: return "Neurons"
        case .circuit: return "Circuit"
        }
    }

    var symbol: String {
        switch self {
        case .space: return "sparkles"
        case .neurons: return "brain.head.profile"
        case .circuit: return "cpu"
        }
    }

    /// The legend's title (and the Look menu's button for it): how the map
    /// is built, and how to add to it.
    var legendTitle: String {
        switch self {
        case .space: return "How your universe is built"
        case .neurons: return "How your network is built"
        case .circuit: return "How your circuits are built"
        }
    }

    /// What VoiceOver calls the map.
    var mapLabel: String {
        switch self {
        case .space: return "Space of ideas"
        case .neurons: return "Network of ideas"
        case .circuit: return "Circuit of ideas"
        }
    }

    /// VoiceOver's hint for the map in this theme.
    var hint: String {
        switch self {
        case .space:
            return "Drag to turn, pinch to zoom. Press and hold a body to see its name. "
                + "Tap a note twice to open it; tap a star or black hole twice to fly in, "
                + "and twice again to open the folder."
        case .neurons:
            return "Drag to turn, pinch to zoom. Press and hold a cell to see its name. "
                + "Tap a neuron twice to open its note; tap a region or relay twice to fly in, "
                + "and twice again to open the folder."
        case .circuit:
            return "Drag to turn, pinch to zoom. Press and hold a part to see its name. "
                + "Tap a part twice to open its note; tap a processor or module chip twice to fly in, "
                + "and twice again to open the folder."
        }
    }

    /// The first-run card's title and two lines, once per theme.
    var cardTitle: String {
        switch self {
        case .space: return "Your notes as a universe"
        case .neurons: return "Your notes as a nervous system"
        case .circuit: return "Your notes as a circuit"
        }
    }

    var cardText: String {
        switch self {
        case .space:
            return "Top-level folders are black holes, folders are stars, pages are gas giants "
                + "and ideas are rocky planets. Bigger holds more."
        case .neurons:
            return "Top-level folders are brain regions, folders are relays down the pathway, "
                + "pages are large neurons and ideas small ones. Links are axons carrying impulses."
        case .circuit:
            return "Each top-level folder is its own circuit board with its chip; pages are capacitors "
                + "and ideas LEDs. Links are copper traces carrying current."
        }
    }

    /// The first-run card's three ways to add, with the app's own controls
    /// (the + button in the Ideas bar, and [[ ]] in a note).
    var cardSteps: [String] {
        switch self {
        case .space:
            return ["Tap + \u{203A} New folder: a new galaxy round its black hole.",
                    "Tap + \u{203A} New page for a gas giant, New idea for a rocky planet.",
                    "Type [[ and a note\u{2019}s title in a note: a link joins them."]
        case .neurons:
            return ["Tap + \u{203A} New folder: a new brain region.",
                    "Tap + \u{203A} New page for a large neuron, New idea for a small one.",
                    "Type [[ and a note\u{2019}s title in a note: an axon joins them."]
        case .circuit:
            return ["Tap + \u{203A} New folder: a new circuit board with its chip.",
                    "Tap + \u{203A} New page for a capacitor, New idea for an LED.",
                    "Type [[ and a note\u{2019}s title in a note: a copper trace joins them."]
        }
    }

    /// Where the other themes' "first-run card seen" marks are kept (a
    /// comma list of raw values); the Universe keeps its own old key,
    /// "vignette.space.universeHintSeen", so nobody sees its card twice.
    static let hintsKey = "vignette.space.themeHintsSeen"
}
