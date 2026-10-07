import Foundation

// MARK: - How the Circuit's parts are dressed
//
// The owner's Circuit target (docs/design/targets-2026-10-01.md, section 3)
// is a realistic green board: processors and modules with printed markings
// ("CARDIOLOGY RP754-2G"), pages as capacitors and inductors, copper traces
// and gold buses, and the small parts a real board carries - ports, diodes,
// bus headers, blue electrolytic capacitors, colour-banded resistors, LEDs.
//
// The plan (GraphCircuit) keeps its few roles and its tested topology; this
// says what each is drawn as, with no SceneKit, so it is tested on Linux
// (Tests/CircuitHierarchyTests, T10):
//
// - a page is a blue electrolytic capacitor, or a toroidal inductor once it
//   is long (250 words, where the space's gas giants gain rings);
// - the wiring's taps carry parts in series, as on a real board: a
//   colour-banded resistor at each tap on a ground rail (the branch's
//   current-limiting resistor), a diode at each tap on the power rail
//   (reverse protection), a two-pin header at each bus tap, a port's
//   metal shell on each edge connector;
// - a chip's marking: its folder's name in capitals over the app's own part
//   number, "RP" (Red Pen) - never anyone else's name or numbering.
//
// Every fitting stays inside its tap's room, clear of every part (T10).
//
// Since 7 October the Circuit is the owner's translucent glass look, not the
// green board (GraphCircuitLook): it prints only the marking's part number
// under each chip's name. The page parts and fittings are kept, and still
// tested, but not drawn.

/// A page's part.
nonisolated enum CircuitPagePart: Sendable, Equatable {
    case capacitor
    case inductor
}

/// What a tap on the wiring carries.
nonisolated enum CircuitFitting: Int, Sendable, CaseIterable {
    case none
    case resistor
    case diode
    case header
    case port
}

nonisolated enum CircuitDress {
    /// A page this long or longer is an inductor (the gas giants' rings).
    static let inductorWords: Int = 250

    static func pagePart(words: Int) -> CircuitPagePart {
        words >= inductorWords ? .inductor : .capacitor
    }

    static func fitting(_ role: CircuitRole) -> CircuitFitting {
        switch role {
        case .ground: return .resistor
        case .vcc: return .diode
        case .bus: return .header
        case .connector: return .port
        default: return .none
        }
    }

    /// Half a fitting's footprint in its tap's sizes: x across the board,
    /// y along it (a resistor and a diode lie along the branch, in series).
    static func extent(_ fitting: CircuitFitting) -> SIMD2<Double> {
        switch fitting {
        case .none: return SIMD2<Double>(0, 0)
        case .resistor: return SIMD2<Double>(0.36, 1.25)
        case .diode: return SIMD2<Double>(0.32, 1.2)
        case .header: return SIMD2<Double>(0.9, 0.5)
        case .port: return SIMD2<Double>(0.62, 0.7)
        }
    }

    /// A chip's printed marking: its folder's name in capitals (at most 14
    /// characters, an ellipsis past that) and its part number - "RP", a
    /// series (7 a board's controller, 5 a module, 3 deeper), two digits of
    /// its own, then its class by how much it holds (1-9) and a revision
    /// letter: "RP754-2G".
    static func marking(name: String, count: Int, depth: Int, seed: UInt64) -> (name: String, part: String) {
        let upper: String = name.uppercased()
        let shown: String = upper.count > 14 ? String(upper.prefix(13)) + "\u{2026}" : upper
        let series: Int = depth <= 0 ? 7 : (depth == 1 ? 5 : 3)
        let own: Int = 10 + Int(seed % 90)
        var size: Int = 1
        var room: Int = max(count, 0)
        while room >= 3 && size < 9 {
            room /= 2
            size += 1
        }
        let letters: [Character] = Array("ABCDEFGHJK")
        let letter: Character = letters[Int((seed / 90) % UInt64(letters.count))]
        let part: String = "RP" + String(series) + String(own) + "-" + String(size) + String(letter)
        return (shown, part)
    }
}
