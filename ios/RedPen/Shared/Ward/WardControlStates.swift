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
///   it lies at the lowest lift; a switch's on-track goes Biro Grey and its
///   knob lies flat;
/// - chosen, it is pressed in, its words take the section's accent and a
///   solid edge in that accent goes round it (a switch: the tint fills its
///   track); chosen and disabled, it stays pressed in and keeps the edge.
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

    /// What the eye reads first: the words, or else the glyph.
    var label: WardToken? { words ?? glyph }

    /// This look's colours for `section` in light or dark, 0xRRGGBB, read
    /// through the palette and the section's table.
    func colours(_ section: WardSection, dark: Bool) -> WardControlColours {
        let glide = WardGlide.rest(WardLook(dark: dark, section: section))
        func hex(_ token: WardToken) -> UInt32 { glide.hex(token, dark: dark) }
        return WardControlColours(words: words.map(hex), glyph: glyph.map(hex), face: hex(face),
                                  mark: mark.map(hex), knob: knob.map(hex))
    }
}

/// A look's colours for one section and mode, as 0xRRGGBB.
struct WardControlColours: Equatable, Sendable {
    var words: UInt32?
    var glyph: UInt32?
    var face: UInt32
    var mark: UInt32?
    var knob: UInt32?

    var label: UInt32? { words ?? glyph }

    /// Every colour the state draws.
    var all: [UInt32] { [words, glyph, mark, knob].compactMap { $0 } + [face] }
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
    /// PopTileStyle on the raised plane, with a label that takes its
    /// colours from the tile (Chart Ink words, a glyph in the tint).
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
            // edge, when disabled
            let track: WardToken = state.isChosen ? (enabled ? .primaryInk : disabledInk) : .well
            let knobStand: WardStand = !enabled ? .flat : state.isHeld ? .pressedIn(.low) : .raised(.low)
            return WardControlLook(face: track, stand: .pressedIn(.low), mark: enabled ? nil : disabledInk,
                                   knob: .surface, knobStand: knobStand)
        case .tile:
            return WardControlLook(words: enabled ? .ink : disabledInk, glyph: enabled ? .primaryInk : disabledInk,
                                   face: .surface, stand: stand, mark: chosenEdge)
        }
    }
}
