import Foundation

// MARK: - Touching the Ideas map
//
// One model, the same in every theme (Space, Neurons, Circuit):
//
//   Tap a body            select it: its ring lights, a light tick, the
//                         camera eases a little towards it, and a peek card
//                         slides up (a note: its title, what it is, its
//                         first lines, its links; a folder: its counts and
//                         latest notes)
//   Tap it again / Open   read it (the note, or the folder's list); so does
//                         tapping or swiping up the card, and a double tap
//   Hold and move         pick it up (a tick at 0.25 s) and drag it
//   Hold still            its options: Open, Rename, Link to…, Move to
//                         folder…, Add note here (folders), Delete
//   Drag empty space, or  turn the map; pinch to zoom - a quick drag never
//   a quick drag          moves a body
//   Tap empty space       let it go; the card hides
//
// This file is the part that decides, with no UIKit: the touch thresholds
// and what a touch was (GraphTouchRules), the selection's state
// (GraphSelection), and what a peek card says (GraphPeek). Pure Foundation,
// tested on Linux (Tests/GraphTouchTests.swift).

/// The thresholds a touch is judged by.
nonisolated enum GraphTouchRules {
    /// Held this long before moving: a pick-up (drag), not a turn.
    static let holdToDrag: Double = 0.25
    /// Held still this long: the body's options.
    static let holdForMenu: Double = 0.55
    /// Points a finger may wander and still be a tap or a hold.
    static let slop: Double = 10
    /// A second tap within this long and this far is a double tap.
    static let doubleTapGap: Double = 0.30
    static let doubleTapReach: Double = 40
    /// Asking to open the same body again this soon is the same request
    /// (the second tap of a double tap is also a tap on the chosen body).
    static let openRepeat: Double = 0.6
}

/// What a touch turned out to be.
nonisolated enum GraphTouchKind: Equatable, Sendable {
    /// Still deciding.
    case pending
    case tap
    case doubleTap
    /// A quick drag: SceneKit turns the camera.
    case orbit
    /// Held, then moved, on a body: it is picked up.
    case drag
    /// Held still on a body: its options.
    case menu
    /// Held on empty space and nothing more: nothing.
    case nothing
}

/// One touch as the recognisers see it.
nonisolated struct GraphTouch: Equatable, Sendable {
    /// Whether it went down on a body.
    var onBody: Bool
    /// How long it has been (or was) down, in seconds.
    var held: Double
    /// How far it has moved from where it went down, in points.
    var moved: Double
    var lifted: Bool
    /// Taps in a row (2: the second of a double tap).
    var taps: Int = 1
}

extension GraphTouchRules {
    /// What `touch` is, so far.
    nonisolated static func judge(_ touch: GraphTouch) -> GraphTouchKind {
        let still: Bool = touch.moved <= slop
        if !still {
            // moved before it was held long enough: the camera's
            if touch.held < holdToDrag || !touch.onBody { return .orbit }
            return .drag
        }
        if touch.onBody && touch.held >= holdForMenu { return .menu }
        guard touch.lifted else { return .pending }
        if touch.held >= holdToDrag { return touch.onBody ? .tap : .nothing }
        return touch.taps >= 2 && touch.onBody ? .doubleTap : .tap
    }

    /// Whether a second tap, `gap` seconds and `distance` points after the
    /// first, makes a double tap.
    nonisolated static func pairs(gap: Double, distance: Double) -> Bool {
        gap >= 0 && gap <= doubleTapGap && distance <= doubleTapReach
    }
}

// MARK: - The selection

/// What happens to the map and the card.
nonisolated enum GraphSelectionEffect: Equatable, Sendable {
    /// Select this body: light it, tick, show its card; `glide`: the
    /// camera glides to centre it (a link chip), otherwise it eases a
    /// little towards it.
    case select(UUID, glide: Bool)
    /// Nothing chosen: the card goes.
    case clear
    /// Read it: the note, or the folder's list.
    case open(UUID)
    /// Dim all but this body's neighbourhood (nil: everything back).
    case links(UUID?)
    /// Its options, where it is.
    case menu(UUID)
}

nonisolated enum GraphSelectionEvent: Equatable, Sendable {
    case tapBody(UUID)
    case tapEmpty
    case doubleTap(UUID)
    /// Open pressed, the card tapped or swiped up.
    case openCard
    /// A link chip on the card.
    case chip(UUID)
    case showLinks
    case hold(UUID)
    /// The opened note or list closed: back to the map, still selected.
    case closed
    /// A body went (deleted, or filtered away).
    case gone(UUID)
}

nonisolated struct GraphSelection: Equatable, Sendable {
    private(set) var selected: UUID?
    private(set) var linksShown: Bool = false
    /// The body opened on top of the map, if any.
    private(set) var opened: UUID?
    private(set) var selectedAt: Double = -1
    private var lastOpen: UUID?
    private var lastOpenAt: Double = -10

    init() {}

    /// Whether the peek card shows.
    var cardShown: Bool { selected != nil && opened == nil }

    /// Handles `event` at `time` (seconds); the effects, in order.
    mutating func handle(_ event: GraphSelectionEvent, at time: Double) -> [GraphSelectionEffect] {
        switch event {
        case .tapBody(let id):
            if selected == id {
                // the second tap of a double tap: that one opens it
                if time - selectedAt < GraphTouchRules.doubleTapGap { return [] }
                return open(id, at: time)
            }
            return choose(id, glide: false, at: time)
        case .tapEmpty:
            guard selected != nil || linksShown else { return [] }
            var out: [GraphSelectionEffect] = []
            if linksShown { out.append(.links(nil)) }
            selected = nil
            linksShown = false
            out.append(.clear)
            return out
        case .doubleTap(let id):
            var out: [GraphSelectionEffect] = []
            if selected != id { out += choose(id, glide: false, at: time) }
            return out + open(id, at: time)
        case .openCard:
            guard let id = selected else { return [] }
            return open(id, at: time)
        case .chip(let id):
            return choose(id, glide: true, at: time)
        case .showLinks:
            guard let id = selected else { return [] }
            linksShown.toggle()
            return [.links(linksShown ? id : nil)]
        case .hold(let id):
            var out: [GraphSelectionEffect] = []
            if selected != id { out += choose(id, glide: false, at: time) }
            return out + [.menu(id)]
        case .closed:
            opened = nil
            return []
        case .gone(let id):
            if opened == id { opened = nil }
            guard selected == id else { return [] }
            var out: [GraphSelectionEffect] = []
            if linksShown { out.append(.links(nil)) }
            selected = nil
            linksShown = false
            out.append(.clear)
            return out
        }
    }

    private mutating func choose(_ id: UUID, glide: Bool, at time: Double) -> [GraphSelectionEffect] {
        var out: [GraphSelectionEffect] = []
        // links were dimmed round the old one: round the new one now
        if linksShown { out.append(.links(id)) }
        selected = id
        selectedAt = time
        out.insert(.select(id, glide: glide), at: 0)
        return out
    }

    private mutating func open(_ id: UUID, at time: Double) -> [GraphSelectionEffect] {
        if lastOpen == id && time - lastOpenAt < GraphTouchRules.openRepeat { return [] }
        lastOpen = id
        lastOpenAt = time
        opened = id
        return [.open(id)]
    }
}

// MARK: - The peek card

/// What the card is told about a body.
nonisolated struct GraphPeekInput: Sendable {
    /// "space", "neurons" or "circuit".
    var theme: String
    /// The theme's own role (UniverseRole's raw value; NeuronRole's or
    /// CircuitRole's raw value as a number), or "" for a single look.
    var role: String
    /// What a single look calls it ("Black hole", "Sun"...), when `role`
    /// is empty.
    var lookName: String = ""
    var folder: Bool
    /// The one container of a vault with no folders.
    var home: Bool = false
    var title: String
    var page: Bool = false
    var body: String = ""
    /// Its links: id and title.
    var links: [(UUID, String)] = []
    var notes: Int = 0
    var subfolders: Int = 0
    /// Its latest notes' titles, newest first.
    var recent: [String] = []
}

nonisolated struct GraphPeekChip: Equatable, Sendable {
    let id: UUID
    let title: String
}

/// What the card shows.
nonisolated struct GraphPeekContent: Equatable, Sendable {
    let title: String
    /// "Gas giant · Page".
    let kind: String
    /// A note's first lines; a folder's counts and latest notes.
    let lines: [String]
    let chips: [GraphPeekChip]
    /// Links not shown as chips.
    let moreLinks: Int
    /// "Open" or "Open folder".
    let primary: String
    /// "Show links" and "More" for a note, "Fly in" for a folder.
    let secondary: [String]
    /// What VoiceOver reads for the card.
    let spoken: String
}

nonisolated enum GraphPeek {
    static let chipLimit: Int = 6
    static let lineLimit: Int = 3

    /// The theme's own word for a body.
    static func roleWord(theme: String, role: String, folder: Bool, home: Bool) -> String? {
        switch theme {
        case "neurons":
            let words: [String: String] = [
                "0": "Brain region", "1": "Relay neuron", "2": "Brainstem", "3": "Neuron", "4": "Interneuron",
                "5": "Glial cell", "6": "Commissural neuron", "7": "Receptor", "8": "Microglia"
            ]
            return words[role]
        case "circuit":
            let words: [String: String] = [
                "0": "Processor", "1": "Module chip", "2": "System chip", "3": "Capacitor", "6": "LED",
                "11": "Gold pad"
            ]
            return words[role]
        default:
            let words: [String: String] = [
                "galaxy": "Black hole", "star": "Star", "home": "Home star", "gasGiant": "Gas giant",
                "rocky": "Rocky planet", "moon": "Moon", "pulsar": "Pulsar", "comet": "Comet", "oort": "Oort comet"
            ]
            return words[role]
        }
    }

    /// The plain type.
    static func plainType(folder: Bool, home: Bool, page: Bool) -> String {
        if home { return "All notes" }
        if folder { return "Folder" }
        return page ? "Page" : "Idea"
    }

    /// Up to `lineLimit` lines of a note's text, without its markup.
    static func firstLines(_ text: String) -> [String] {
        var out: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            var line: String = raw.trimmingCharacters(in: .whitespaces)
            while let first = line.first, first == "#" || first == "-" || first == "*" || first == ">" {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            line = line.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
            line = line.replacingOccurrences(of: "**", with: "")
            if line.isEmpty { continue }
            if line.count > 140 { line = String(line.prefix(139)) + "\u{2026}" }
            out.append(line)
            if out.count == lineLimit { break }
        }
        return out
    }

    static func plural(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) " + (n == 1 ? one : many)
    }

    /// The card for `input`.
    static func content(_ input: GraphPeekInput) -> GraphPeekContent {
        let plain: String = plainType(folder: input.folder, home: input.home, page: input.page)
        let theme: String? = roleWord(theme: input.theme, role: input.role, folder: input.folder, home: input.home)
        let own: String = theme ?? (input.lookName.isEmpty ? plain : input.lookName)
        let kind: String = own == plain ? plain : own + " \u{00B7} " + plain
        let title: String = input.title.isEmpty ? "Untitled" : input.title
        if input.folder || input.home {
            var lines: [String] = [plural(input.notes, "note", "notes") + " \u{00B7} "
                                   + plural(input.subfolders, "subfolder", "subfolders")]
            let recent: [String] = Array(input.recent.prefix(3)).map { $0.isEmpty ? "Untitled" : $0 }
            if !recent.isEmpty { lines.append("Latest: " + recent.joined(separator: ", ")) }
            let spoken: String = title + ", " + kind + ". " + lines.joined(separator: ". ")
            return GraphPeekContent(title: title, kind: kind, lines: lines, chips: [], moreLinks: 0,
                                    primary: "Open folder", secondary: ["Fly in"], spoken: spoken)
        }
        let sorted: [(UUID, String)] = input.links.sorted { a, b in
            let ka: String = a.1.lowercased()
            let kb: String = b.1.lowercased()
            return ka != kb ? ka < kb : a.0.uuidString < b.0.uuidString
        }
        let chips: [GraphPeekChip] = sorted.prefix(chipLimit).map {
            GraphPeekChip(id: $0.0, title: $0.1.isEmpty ? "Untitled" : $0.1)
        }
        let more: Int = max(sorted.count - chips.count, 0)
        var lines: [String] = firstLines(input.body)
        if lines.isEmpty { lines = ["Nothing written yet."] }
        let links: String = plural(input.links.count, "link", "links")
        let spoken: String = title + ", " + kind + ", " + links + ". " + lines.joined(separator: " ")
        return GraphPeekContent(title: title, kind: kind, lines: lines, chips: chips, moreLinks: more,
                                primary: "Open", secondary: ["Show links", "More"], spoken: spoken)
    }

    /// The first-run card's three lines (merged into each theme's card).
    static let coachLines: [String] = ["Tap to preview", "Tap again or Open to read", "Hold to move or for options"]

    /// VoiceOver's custom actions on a body.
    static func actions(folder: Bool) -> [String] {
        folder ? ["Open folder", "Fly in", "Delete"] : ["Open", "Show links", "Delete"]
    }

    /// The options held on a body, in order; `canAddNote` for folders.
    static func menu(folder: Bool, home: Bool) -> [String] {
        if home { return ["Open", "Add note here"] }
        if folder { return ["Open", "Rename", "Add note here", "Delete"] }
        return ["Open", "Rename", "Link to\u{2026}", "Move to folder\u{2026}", "Delete"]
    }
}
