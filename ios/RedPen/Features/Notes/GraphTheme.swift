import Foundation

// MARK: - The map's themes
//
// The 3D Ideas map can be drawn in one of several themes, each its own
// picture of the same hierarchy (folders, subfolders, pages, ideas, links):
//
//   Space     the Universe (GraphUniverse): black holes, stars, planets,
//             moons, pulsars and comets; the default
//   Neurons   cells (GraphNeurons): a top-level folder is a cell, a folder
//             inside it a part of that cell, deeper a smaller part; pages
//             are neurons, ideas interneurons, joined by axons
//   Circuit   a circuit board (GraphCircuit): a top-level folder is a
//             board, a folder inside it a part of that circuit, deeper a
//             smaller part; capacitors, resistors, LEDs, diodes and
//             headers, joined by routed copper traces carrying current
//   Performance  speed first (GraphPerf*.swift): every note a point and
//             every link a line, drawn by the GPU in a few instanced draws
//             so 100,000 notes and their links fit on screen at once; far
//             away a folder's notes merge into one glow
//
// Space, Neurons and Circuit are planned by a pure Foundation planner into
// a ThemePlan (GraphThemePlan.swift) and built by the shared theme scene
// (GraphThemeScene.swift) with the theme's own look (GraphThemeLook), so a
// new theme adds a planner, a look and its legend - nothing else changes.
// Performance is the exception: its own Metal engine, with no SceneKit and
// no Stethoscore types (GraphPerfTheme.swift is its glue), takes the map's
// place. The Graphics setting (GraphicsQuality.swift) applies to every theme.
//
// Foundation only: the choice and its words are tested on Linux.

nonisolated enum GraphTheme: String, CaseIterable, Sendable, Identifiable {
    case space
    case neurons
    case circuit
    case performance

    var id: String { rawValue }

    /// Stored in UserDefaults (Graph3DView reads it with @AppStorage, so a
    /// change rebuilds the map).
    static let key = "vignette.space.theme"
    static let standard: GraphTheme = .space

    /// Whether it can be chosen (a theme still being built is not).
    var isReady: Bool {
        switch self {
        case .space, .neurons, .circuit, .performance: return true
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
        case .performance: return "Performance"
        }
    }

    var symbol: String {
        switch self {
        case .space: return "sparkles"
        case .neurons: return "brain.head.profile"
        case .circuit: return "cpu"
        case .performance: return "speedometer"
        }
    }

    /// The legend's title (and the Look menu's button for it): how the map
    /// is built, and how to add to it.
    var legendTitle: String {
        switch self {
        case .space: return "How your universe is built"
        case .neurons: return "How your network is built"
        case .circuit: return "How your circuits are built"
        case .performance: return "How the fast map is built"
        }
    }

    /// What VoiceOver calls the map.
    var mapLabel: String {
        switch self {
        case .space: return "Space of ideas"
        case .neurons: return "Network of ideas"
        case .circuit: return "Circuit of ideas"
        case .performance: return "Fast map of ideas"
        }
    }

    /// VoiceOver's hint for the map in this theme.
    var hint: String {
        switch self {
        case .space:
            return "Tap a body to preview it on a card; tap again, or Open, to read it. "
                + "Hold a body to move it, or hold it still for its options. Drag to turn, pinch to zoom."
        case .neurons:
            return "Tap a cell to preview it on a card; tap again, or Open, to read it. "
                + "Hold a cell to move it, or hold it still for its options. Drag to turn, pinch to zoom."
        case .circuit:
            return "Tap a part to preview it on a card; tap again, or Open, to read it. "
                + "Hold a part to move it, or hold it still for its options. Drag to turn, pinch to zoom."
        case .performance:
            return "Tap a point to preview it on a card; tap again, or Open, to read it. "
                + "Hold a point for its options. Drag to turn, two fingers to slide, pinch to zoom."
        }
    }

    /// The first-run card's title and two lines, once per theme.
    var cardTitle: String {
        switch self {
        case .space: return "Your notes as a universe"
        case .neurons: return "Your notes as a nervous system"
        case .circuit: return "Your notes as a circuit"
        case .performance: return "Your notes, built for speed"
        }
    }

    var cardText: String {
        switch self {
        case .space:
            return "Top-level folders are black holes, folders are stars, pages are gas giants "
                + "and ideas are rocky planets. Bigger holds more."
        case .neurons:
            return "A top-level folder is a cell. A folder inside it is a part of that cell, "
                + "and a folder inside that is a smaller part. Pages are large neurons and ideas small ones."
        case .circuit:
            return "A top-level folder is a circuit board. A folder inside it is a part of that circuit, "
                + "and a folder inside that is a smaller part. Pages are capacitors and ideas LEDs."
        case .performance:
            return "Every note is a point and every link a line, drawn so 100,000 fit at once. "
                + "Each top-level folder has its own colour; far away a folder\u{2019}s notes merge into one glow."
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
            return ["Tap + \u{203A} New folder: a new cell.",
                    "Tap + \u{203A} New page for a large neuron, New idea for a small one.",
                    "Type [[ and a note\u{2019}s title in a note: an axon joins them."]
        case .circuit:
            return ["Tap + \u{203A} New folder: a new circuit board.",
                    "Tap + \u{203A} New page for a capacitor, New idea for an LED.",
                    "Type [[ and a note\u{2019}s title in a note: a copper trace joins them."]
        case .performance:
            return ["Tap + \u{203A} New folder: a new cluster round its hub.",
                    "Tap + \u{203A} New page for a larger point, New idea for a smaller one.",
                    "Type [[ and a note\u{2019}s title in a note: a line joins them."]
        }
    }

    /// Where the other themes' "first-run card seen" marks are kept (a
    /// comma list of raw values); the Universe keeps its own old key,
    /// "vignette.space.universeHintSeen", so nobody sees its card twice.
    static let hintsKey = "vignette.space.themeHintsSeen"
}
