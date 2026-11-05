import Foundation

/// Where a ring's words may go: the square inside its groove. The review
/// found "67%" and "Readiness" crossing the arc on Vitals (T0211 A5): the
/// words were inset by the line's width alone, a square whose corners
/// reach past the groove's inner edge. The largest square inside a circle
/// of radius r has side r·√2, so the words are given that square inside
/// the groove's hole and shrink to fit it. Android's WardControlSize
/// .ringLabelSide is the same sum. Foundation only, so it is tested on
/// Linux (WardRingFitTests).
enum WardRingFit {
    /// The groove's clearance either side of the arc.
    static func clear(lineWidth: Double) -> Double { min(2, lineWidth / 3) }

    /// The radius of the groove's hole in a ring `diameter` across: the
    /// arc's width and its clearance either side, in from the edge.
    static func holeRadius(diameter: Double, lineWidth: Double) -> Double {
        max(0, diameter / 2 - lineWidth - 2 * clear(lineWidth: lineWidth))
    }

    /// The side of the square the words get: every corner on or inside the
    /// hole's edge.
    static func labelSide(diameter: Double, lineWidth: Double) -> Double {
        holeRadius(diameter: diameter, lineWidth: lineWidth) * 2.0.squareRoot()
    }

    /// The ring's diameter that gives words of `side` their square: the
    /// size a ring takes when nothing sizes it.
    static func diameter(labelSide side: Double, lineWidth: Double) -> Double {
        2 * (max(0, side) / 2.0.squareRoot() + lineWidth + 2 * clear(lineWidth: lineWidth))
    }
}
