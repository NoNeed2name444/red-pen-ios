import Foundation

/// How every Ward control looks in each of its states (the states gallery,
/// WardStatesGallery): at rest, held under the finger, disabled and chosen,
/// and, for a control that can be chosen, chosen and held, and chosen and
/// disabled. For each state: the colours of its words and glyphs, the face
/// they sit on, the solid mark it carries and how its face stands, as
/// WardControls and PopOut draw them.
///
/// The colours are roles (WardToken), read for a section and a mode through
/// WardGlide at rest: `.primaryInk` is the section's accent and `.primary`
/// its fill (WardSection), the rest are the Ward palette's. No colour here is
/// a hex of its own. Foundation only, so every section and mode is checked
/// on Linux (WardStatesTests).
///
/// The rules the states keep (the owner, 14 Oct: buttons "became too flat";
/// 9 Oct: nothing in the app looks faded):
/// - held, a control sinks into the base; a switch's knob sinks;
/// - disabled, its words and glyphs go Biro Grey (`disabledInk`), solid, and
///   it lies at the lowest lift; a switch's words go Biro Grey, its on-track
///   goes Biro Grey and its knob lies flat;
/// - chosen, it is pressed in, its words take the section's accent (a
///   tile's stay its caller's) and a solid edge in that accent goes round
///   it (a switch: the tint fills its track); chosen and disabled, it stays
///   pressed in and keeps the edge.
enum WardControlStates {
    /// A disabled control's words and glyphs, and a disabled switch's
    /// on-track: Biro Grey, solid, 4.5:1 on every tier, and told apart from
    /// Chart Ink, every section's accent and every colour that means
    /// something. The one place it is named (Color.wardDisabledInk reads it).
    static let disabledInk: WardToken = .inkSecondary

    /// The solid edge round a chosen chip, circle, segment or tile, in
    /// points: the section's accent at full strength, twice the width of a
    /// control's own 1-point edge.
    static let chosenEdgeWidth = 2.0

    /// The edge a disabled switch's flat knob keeps, in the disabled ink: a
    /// flat face on the light well would be 1.2:1, so it would disappear.
    static let knobEdgeWidth = 1.0
}

/// The dock's geometry (CategoryDock): its panel, and the chosen tab's
/// hollow and ring inside it. The ring is concentric with the panel: its
/// corner radius is the panel's less the inset between them, in the same
/// continuous corner style, so the two curves run parallel round every
/// corner (the owner, 21 Oct: "the corner of the part doesn't match the
/// corner around it"). The chosen tab's name sits wholly inside the ring's
/// inner edge, clear of its corners, at every text size the dock is drawn
/// at (past them it is one list button). Foundation only (WardStatesTests).
enum WardDock {
    /// The panel's corner radius (WardRadius.bar).
    static let panelRadius = WardScale.xl
    /// From the panel's edge to the tab's: the bar along the bottom, and
    /// the wide iPad's rail.
    static let barInset = 4.0
    static let railInset = 5.0
    /// The ring round the chosen tab: the accent edge, drawn inside its
    /// hollow's shape (strokeBorder).
    static let ringWidth = WardControlStates.chosenEdgeWidth
    /// The tab's hollow (and its ring's outer edge), concentric with the panel.
    static func tabRadius(inset: Double) -> Double { panelRadius - inset }
    static var barTabRadius: Double { tabRadius(inset: barInset) }
    static var railTabRadius: Double { tabRadius(inset: railInset) }

    /// Round a tab's symbol and name: above and below, and at each side.
    /// With these the name's box keeps `labelClearance` inside the ring's
    /// inner edge, its corners too, whatever the text size makes the tab's
    /// height (labelFits).
    static let labelVertical = 8.0
    static let labelSide = 10.0
    /// The least room between the name and the ring's inner edge.
    static let labelClearance = 1.0
    /// A tab's least height: as tall as before (52 and 2 above and below).
    static let tabMinHeight = 56.0

    // MARK: the row along the bottom, on every phone

    /// The bar: room at its sides, the Ideas pill's width, the gap between
    /// the panel and the pill, and the widest the bar grows.
    static let barSide = 10.0
    static let ideasWidth = 56.0
    static let barSpacing = 6.0
    static let barMaxWidth = 560.0
    /// A tab is never narrower than a finger.
    static let leastTab = 44.0
    /// How small a name may get (all five by the same amount) so the row
    /// still fits: never its side room, so it stays clear of the ring.
    static let leastNameScale = 0.5

    /// Whether the dock folds into its one list button: at the
    /// accessibility text sizes only. At every other size, on every width,
    /// it is the row (owner 22 Oct: the folded "Questions" button on a 17
    /// Pro was wrong).
    static func showsList(accessibilitySize: Bool) -> Bool { accessibilitySize }

    /// The room the five tabs share on a window `width` wide: less the
    /// page's inset, the bar's sides, the pill and its gap, and the panel's
    /// inset round the tabs.
    static func tabsRoom(width: Double) -> Double {
        let bar = min(width - 2 * WardPaper.sideInset - 2 * barSide, barMaxWidth)
        return bar - ideasWidth - barSpacing - 2 * barInset
    }

    /// How much the names shrink so the tabs, each a name with its side
    /// room (`ideals`), fit `room`: 1 when they fit as they are.
    static func nameScale(_ ideals: [Double], room: Double) -> Double {
        let total = ideals.reduce(0, +)
        guard total > room else { return 1 }
        let sides = 2 * labelSide * Double(ideals.count)
        let names = ideals.map { max(0, $0 - 2 * labelSide) }.reduce(0, +)
        guard names > 0 else { return 0 }
        return min(1, max(0, (room - sides) / names))
    }

    /// The tabs' widths in `room`: where there is spare room the narrower
    /// tabs share it equally (water-filling); where there is too little,
    /// every name shrinks by the same amount and each keeps its side room.
    static func tabWidths(_ ideals: [Double], room: Double) -> [Double] {
        let total = ideals.reduce(0, +)
        guard total > 0 else { return ideals }
        let width = max(0, room)
        if width < total {
            let scale = nameScale(ideals, room: width)
            return ideals.map { 2 * labelSide + max(0, $0 - 2 * labelSide) * scale }
        }
        var remaining = width
        var count = ideals.count
        var level = 0.0
        for ideal in ideals.sorted(by: >) {
            level = remaining / Double(count)
            if ideal <= level { break }
            remaining -= ideal
            count -= 1
        }
        return ideals.map { max($0, level) }
    }

    /// What the dock draws along the bottom.
    enum Form: Equatable {
        /// The row of tabs, their widths, and how much the names shrink.
        case row(tabs: [Double], nameScale: Double)
        /// The one list button.
        case list
    }

    /// The dock along the bottom on a window `width` wide, for names
    /// `names` wide at the text size in use.
    static func form(width: Double, names: [Double], accessibilitySize: Bool) -> Form {
        if showsList(accessibilitySize: accessibilitySize) { return .list }
        let ideals = names.map { max(leastTab, $0 + 2 * labelSide) }
        let room = tabsRoom(width: width)
        return .row(tabs: tabWidths(ideals, room: room), nameScale: nameScale(ideals, room: room))
    }

    /// SwiftUI's continuous corner (`.continuous`) for radius 1, from the
    /// edge's straight line into the corner's middle: three cubic curves,
    /// as (along the edge, in from it) from where the curve leaves the
    /// straight edge, 1.52866 radii from the corner.
    static let continuousCorner: [[(Double, Double)]] = [
        [(1.52866, 0), (1.08849, 0), (0.86840, 0), (0.66993, 0.06814)],
        [(0.66993, 0.06814), (0.46213, 0.15429), (0.15429, 0.46213), (0.06814, 0.66993)],
        [(0.06814, 0.66993), (0, 0.86840), (0, 1.08849), (0, 1.52866)],
    ]

    /// Points on a continuous corner of `radius`, as (x, y) from the
    /// corner's two edges, the edges' lines being x = 0 and y = 0.
    static func cornerPoints(radius: Double, steps: Int = 200) -> [(x: Double, y: Double)] {
        var points: [(x: Double, y: Double)] = []
        for curve in continuousCorner {
            for i in 0...steps {
                let t = Double(i) / Double(steps), m = 1 - t
                let w = [m * m * m, 3 * m * m * t, 3 * m * t * t, t * t * t]
                let x = zip(w, curve).map { $0 * $1.0 }.reduce(0, +)
                let y = zip(w, curve).map { $0 * $1.1 }.reduce(0, +)
                points.append((x * radius, y * radius))
            }
        }
        return points
    }

    /// Whether a box's corner at (x, y) from a continuous corner's two
    /// edges lies inside it, at least `clearance` from its curve.
    static func inside(x: Double, y: Double, radius: Double, clearance: Double) -> Bool {
        guard x >= clearance, y >= clearance else { return false }
        let reach = 1.52866 * radius
        if x >= reach + clearance || y >= reach + clearance { return true }
        let curve = cornerPoints(radius: radius)
        // inside is past the curve from the corner: at the box's height
        // above the edge, further along than the curve
        guard x >= depth(curve, at: y) else { return false }
        var nearest = Double.infinity
        for p in curve {
            let dx: Double = x - p.x, dy: Double = y - p.y
            nearest = min(nearest, (dx * dx + dy * dy).squareRoot())
        }
        return nearest >= clearance
    }

    /// How far along the edge the corner's curve is at `y` in from it (the
    /// curve's y only grows along it, from 0 to the reach).
    static func depth(_ curve: [(x: Double, y: Double)], at y: Double) -> Double {
        guard let last = curve.last, y < last.y else { return 0 }
        for (a, b) in zip(curve, curve.dropFirst()) where a.y <= y && y <= b.y {
            let t = b.y > a.y ? (y - a.y) / (b.y - a.y) : 0
            return a.x + (b.x - a.x) * t
        }
        return curve.first?.x ?? 0
    }

    /// Whether a tab's name, `width` by `height`, centred across a tab
    /// `tabWidth` wide whose bottom edge is `below` under the name, sits
    /// wholly inside a ring of corner `radius`: its box keeps
    /// `labelClearance` from the ring's inner edge (the hollow's shape
    /// inset by the ring's width, its radius less the same), corners too.
    static func labelFits(width: Double, below: Double, tabWidth: Double, radius: Double) -> Bool {
        let inner = radius - ringWidth
        let side = (tabWidth - width) / 2 - ringWidth
        let under = below - ringWidth
        return inside(x: side, y: under, radius: inner, clearance: labelClearance)
    }
}

/// One state of a control: chosen or not, held or not, enabled or not.
struct WardControlState: Hashable, Sendable, CustomStringConvertible {
    var isChosen = false
    var isHeld = false
    var isEnabled = true

    static let rest = WardControlState()
    static let pressed = WardControlState(isHeld: true)
    static let disabled = WardControlState(isEnabled: false)
    static let selected = WardControlState(isChosen: true)
    static let selectedPressed = WardControlState(isChosen: true, isHeld: true)
    static let selectedDisabled = WardControlState(isChosen: true, isEnabled: false)

    /// The same state on an enabled control: what a disabled one is told
    /// apart from.
    var enabledTwin: WardControlState {
        var twin = self
        twin.isEnabled = true
        return twin
    }

    /// The same state, not chosen: what a chosen one is told apart from.
    var unchosenTwin: WardControlState {
        var twin = self
        twin.isChosen = false
        return twin
    }

    var description: String {
        var words: [String] = []
        if isChosen { words.append("chosen") }
        if isHeld { words.append("held") }
        if !isEnabled { words.append("disabled") }
        return words.isEmpty ? "at rest" : words.joined(separator: " and ")
    }
}

/// How a face stands off the base.
enum WardStand: Equatable, Sendable {
    /// Raised by its lights at this lift (a button by its small rim).
    case raised(WardLift)
    /// Pressed into the base, the lift's lights inside it: held or chosen.
    case pressedIn(WardLift)
    /// No lights at all: a disabled switch's knob.
    case flat

    var isPressedIn: Bool {
        if case .pressedIn = self { return true }
        return false
    }
}

/// A control's look in one state, as colour roles.
struct WardControlLook: Equatable, Sendable {
    /// Its words, where it has them.
    var words: WardToken?
    /// Its glyph, where it has one.
    var glyph: WardToken?
    /// The face its words and glyph sit on; for a switch, its track
    /// (`.primaryInk` there is the tint).
    var face: WardToken
    var stand: WardStand
    /// A solid mark that is not words: a chosen control's edge, or a
    /// disabled switch's knob edge.
    var mark: WardToken?
    /// A switch's knob, and how it stands on the track.
    var knob: WardToken?
    var knobStand: WardStand?
    /// Where its words sit when that is not `face`: a switch's words stand
    /// on the row beside its track.
    var wordsFace: WardToken?

    /// What the eye reads first: the words, or else the glyph.
    var label: WardToken? { words ?? glyph }

    /// This look's colours for `section` in light or dark, 0xRRGGBB, read
    /// through the palette and the section's table.
    func colours(_ section: WardSection, dark: Bool) -> WardControlColours {
        let glide = WardGlide.rest(WardLook(dark: dark, section: section))
        func hex(_ token: WardToken) -> UInt32 { glide.hex(token, dark: dark) }
        return WardControlColours(words: words.map(hex), glyph: glyph.map(hex), face: hex(face),
                                  mark: mark.map(hex), knob: knob.map(hex), wordsFace: wordsFace.map(hex))
    }
}

/// A look's colours for one section and mode, as 0xRRGGBB.
struct WardControlColours: Equatable, Sendable {
    var words: UInt32?
    var glyph: UInt32?
    var face: UInt32
    var mark: UInt32?
    var knob: UInt32?
    var wordsFace: UInt32?

    var label: UInt32? { words ?? glyph }

    /// What its words and glyph are read against.
    var readOn: UInt32 { wordsFace ?? face }

    /// Every colour the state draws.
    var all: [UInt32] { [words, glyph, mark, knob, wordsFace].compactMap { $0 } + [face] }
}

/// The Ward controls the gallery shows, in its order.
enum WardControl: String, CaseIterable, Sendable {
    /// WardButtonStyle's kinds.
    case primary, secondary, destructive, compact, quiet
    /// WardChipButtonStyle (Sure, Hint, Flag), with no tone of its own.
    case chip
    /// WardCircleButtonStyle (a stepper's minus and plus), at its own lift.
    case circle
    /// WardToggleStyle: chosen is on.
    case toggle
    /// One segment of WardSegmented: chosen is the selected one.
    case segment
    /// PopTileStyle on the raised plane. The tile leaves its label's colours
    /// to the caller; these are the gallery's label, which colours itself
    /// as a careful caller does: Chart Ink words and a glyph in the accent,
    /// Biro Grey when disabled.
    case tile

    var isButton: Bool {
        switch self {
        case .primary, .secondary, .destructive, .compact, .quiet: return true
        case .chip, .circle, .toggle, .segment, .tile: return false
        }
    }

    /// Its states. A button has no chosen ones.
    var states: [WardControlState] {
        isButton ? [.rest, .pressed, .disabled]
                 : [.rest, .pressed, .disabled, .selected, .selectedPressed, .selectedDisabled]
    }

    /// How high it stands at rest: the main button a step above the rest.
    var lift: WardLift {
        switch self {
        case .primary: return .high
        case .secondary, .destructive, .tile: return .mid
        case .compact, .quiet, .chip, .circle, .toggle, .segment: return .low
        }
    }

    /// An enabled button's words: the kind shows in the label's colour.
    private var buttonWords: WardToken {
        switch self {
        case .primary, .compact: return .primaryInk
        case .destructive: return .danger
        default: return .ink
        }
    }

    /// Its look in `state`, as WardControls (and PopOut, for the tile)
    /// draw it.
    func look(_ state: WardControlState) -> WardControlLook {
        let enabled: Bool = state.isEnabled
        let disabledInk: WardToken = WardControlStates.disabledInk
        // disabled, it lies at the lowest lift; held (only while enabled)
        // or chosen, it is pressed in
        let lift: WardLift = enabled ? self.lift : .low
        let down: Bool = state.isChosen || (enabled && state.isHeld)
        let stand: WardStand = down ? .pressedIn(lift) : .raised(lift)
        let chosenEdge: WardToken? = state.isChosen ? .primaryInk : nil
        let chosenInk: WardToken = state.isChosen ? .primaryInk : .ink
        switch self {
        case .primary, .secondary, .destructive, .compact, .quiet:
            // the main button's face is a sheet's, a tier up, while enabled
            return WardControlLook(words: enabled ? buttonWords : disabledInk,
                                   face: self == .primary && enabled ? .raised : .surface, stand: stand)
        case .chip:
            return WardControlLook(words: enabled ? chosenInk : disabledInk, face: .surface, stand: stand,
                                   mark: chosenEdge)
        case .circle:
            return WardControlLook(glyph: enabled ? chosenInk : disabledInk, face: .surface, stand: stand,
                                   mark: chosenEdge)
        case .segment:
            // a segment sits on the control's raised capsule; held or
            // chosen, it is a well pressed into it
            return WardControlLook(words: enabled ? chosenInk : disabledInk, face: down ? .well : .surface,
                                   stand: down ? .pressedIn(.low) : .raised(.low), mark: chosenEdge)
        case .toggle:
            // the track is a well; on, the tint fills it, Biro Grey when
            // disabled; the knob sinks while held and lies flat, with an
            // edge, when disabled; its words, on the row beside it, go
            // Biro Grey too
            let track: WardToken = state.isChosen ? (enabled ? .primaryInk : disabledInk) : .well
            let knobStand: WardStand = !enabled ? .flat : state.isHeld ? .pressedIn(.low) : .raised(.low)
            return WardControlLook(words: enabled ? .ink : disabledInk, face: track, stand: .pressedIn(.low),
                                   mark: enabled ? nil : disabledInk, knob: .surface, knobStand: knobStand,
                                   wordsFace: .surface)
        case .tile:
            return WardControlLook(words: enabled ? .ink : disabledInk, glyph: enabled ? .primaryInk : disabledInk,
                                   face: .surface, stand: stand, mark: chosenEdge)
        }
    }
}
