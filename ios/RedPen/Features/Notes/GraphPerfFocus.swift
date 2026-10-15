// The million map's selection (the design bar: "selection that lights a
// neighbourhood with an obvious focus"; D4: a picked note's neighbourhood
// comes to full detail).
//
// - Links are hidden by default; choosing a note draws its own links,
//   growing out from it to each neighbour (the short ones arrive first),
//   and each neighbour grows in as its link reaches it.
// - The rest of the map steps back (mixed towards the ground by `dim`),
//   so the neighbourhood is the brightest thing on the screen.
// - Choosing another note first draws the old links back in (quickly),
//   then grows the new ones; clearing the choice draws them back and the
//   map comes forward again. Sizes and lengths move, nothing cross-fades.
// - Reduce Motion: every change is at once.
//
// Foundation only, free of Stethoscore types.
import Foundation

/// How the chosen note and its neighbours are drawn.
nonisolated enum GraphPerfFocusLook {
    /// At most this many of a note's links are drawn (a hub of thousands
    /// would be a solid star; its strongest are the first in its adjacency).
    static let most = 4_096
    /// Neighbours are drawn this much bigger than their own size, and never
    /// under `floor` points (radius), so a far neighbour is still a target.
    static let grow: Float = 1.3
    static let floor: Float = 3.5
    /// The rest of the map steps back this far towards the ground.
    static let dimmed: Float = 0.45
    /// A focus link's width (points).
    static let linkWidth: Float = 1.3

    /// A neighbour's (or the chosen note's) size on screen (points, radius).
    static func pixels(radius: Float, focal: Float, depth: Float) -> Float {
        let p = radius * focal / max(depth, 1e-3) * grow
        return min(max(p, floor), GraphPerfLOD.hubClamp.upperBound)
    }

    /// How far a link of `length` has grown when the focus has grown `grow`
    /// (0...1) of the way to `reach`, the longest link's length: every link
    /// grows at the same speed, so the short ones arrive first.
    static func tip(grow: Float, reach: Float, length: Float) -> Float {
        guard length > 1e-6 else { return grow > 0 ? 1 : 0 }
        return min(max(grow * reach / length, 0), 1)
    }

    /// A neighbour's size as its link reaches it: it grows in over the
    /// link's last 15%.
    static func arrival(tip: Float) -> Float {
        GraphPerfDepthLook.smoothstep(0.85, 1, tip)
    }
}

/// The selection's motion: which note's neighbourhood is shown, how far its
/// links have grown, and how far the rest has stepped back.
nonisolated struct GraphPerfFocusMotion: Sendable, Equatable {
    /// Seconds to draw the old links back, to grow the new ones, and for
    /// the rest of the map to step back or forward.
    static let retractSeconds: Float = 0.15
    static let growSeconds: Float = 0.45
    static let dimSeconds: Float = 0.25

    /// The note whose neighbourhood is drawn (its slot), nil for none.
    private(set) var shown: Int?
    /// How far its links have grown, 0...1 (linear; `grow` is eased).
    private(set) var progress: Float = 0
    /// How far the rest has stepped back, 0 ... GraphPerfFocusLook.dimmed.
    private(set) var dim: Float = 0

    init() {}

    /// The links' growth, eased out (fast, then settling).
    var grow: Float {
        let t = min(max(progress, 0), 1)
        let u = 1 - t
        return 1 - u * u * u
    }

    /// Whether anything is still moving towards `target`.
    func isMoving(towards target: Int?) -> Bool {
        let want: Float = target == nil ? 0 : GraphPerfFocusLook.dimmed
        if dim != want { return true }
        if shown != target { return true }
        return target != nil && progress < 1
    }

    /// One frame of `seconds` towards showing `target`'s neighbourhood.
    mutating func step(towards target: Int?, seconds: Float, reduceMotion: Bool = false) {
        let want: Float = target == nil ? 0 : GraphPerfFocusLook.dimmed
        if reduceMotion {
            shown = target
            progress = target == nil ? 0 : 1
            dim = want
            return
        }
        let dt = max(seconds, 0)
        // the rest steps back or forward at its own pace
        let dimStep = GraphPerfFocusLook.dimmed * dt / Self.dimSeconds
        dim = dim < want ? min(dim + dimStep, want) : max(dim - dimStep, want)
        if shown != target {
            // the old links draw back first, then the new note takes over
            if shown != nil && progress > 0 {
                progress = max(progress - dt / Self.retractSeconds, 0)
                if progress > 0 { return }
            }
            shown = target
            progress = 0
            return
        }
        if target != nil && progress < 1 {
            progress = min(progress + dt / Self.growSeconds, 1)
        }
    }
}
