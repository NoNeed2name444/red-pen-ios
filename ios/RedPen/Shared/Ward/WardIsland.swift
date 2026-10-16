import Foundation

/// Window geometry shared by the page and the paper frame. No drawing or
/// device queries belong here, so the joins can be checked on Linux.
enum WardIsland {
    struct Sides: Equatable, Sendable {
        var left: Bool
        var right: Bool
        var any: Bool { left || right }
    }

    static func sides(host: CGRect, page: CGRect, covered: Bool) -> Sides {
        guard !covered, host.width > 0, page.width > 0 else {
            return Sides(left: false, right: false)
        }
        return Sides(left: abs(host.minX - page.minX) <= 1,
                     right: abs(host.maxX - page.maxX) <= 1)
    }

    /// Only a translation: the same solved circles are used in both places.
    static func local(_ join: WardEdgeJoin, origin: SIMD2<Double>) -> WardEdgeJoin {
        func corner(_ c: WardEdgeCorner?) -> WardEdgeCorner? {
            c.map { WardEdgeCorner(center: $0.center - origin, radius: $0.radius,
                                  lineX: $0.lineX - origin.x, join: $0.join - origin) }
        }
        return WardEdgeJoin(y: join.y - origin.y, left: corner(join.left), right: corner(join.right),
                            fromX: join.fromX.map { $0 - origin.x }, toX: join.toX.map { $0 - origin.x })
    }

    /// Hard clips divide the ink at the page's actual pixel boundary. These
    /// bands never include the page; the renderer also removes the frame's
    /// stroke from them before filling the arc stroke.
    static func clearance(panel: WardPaperPanel, page: CGRect, sides: Sides) -> [CGRect] {
        var result: [CGRect] = []
        if sides.left, page.minX > panel.x {
            result.append(CGRect(x: panel.x, y: panel.y, width: page.minX - panel.x, height: panel.height))
        }
        let right = panel.x + panel.width
        if sides.right, page.maxX < right {
            result.append(CGRect(x: page.maxX, y: panel.y, width: right - page.maxX, height: panel.height))
        }
        return result
    }

    /// Distance inside a circular top corner and its two tangent straight
    /// edges. Taking the smaller distance from the two corners describes a
    /// slab's entire top, even when only one side joins the frame.
    private static func distance(_ point: SIMD2<Double>, center: SIMD2<Double>,
                                 radius: Double, left: Bool) -> Double {
        let x = left ? center.x - point.x : point.x - center.x
        let y = center.y - point.y
        return radius - hypot(max(0, x), max(0, y)) - min(0, max(x, y))
    }

    /// Near the window's bottom the arc passes its circle's widest point.
    /// Measure the finite arc and its downward continuation, rather than
    /// assuming that every join is a quarter circle on a vertical wall.
    private static func distance(_ point: SIMD2<Double>, corner: WardEdgeCorner, left: Bool) -> Double {
        let sign = left ? -1.0 : 1.0
        let v = point - corner.center
        let end = atan2(corner.join.y - corner.center.y, sign * (corner.join.x - corner.center.x))
        let angle = min(end, max(-Double.pi / 2, atan2(v.y, sign * v.x)))
        let nearest = corner.center + SIMD2(sign * corner.radius * cos(angle), corner.radius * sin(angle))
        let arc = hypot(point.x - nearest.x, point.y - nearest.y)
        let wall = hypot(point.x - corner.join.x, max(0, corner.join.y - point.y))
        let boundary: Double
        if point.y < corner.join.y {
            boundary = corner.center.x + sign * sqrt(max(0, corner.radius * corner.radius - v.y * v.y))
        } else {
            boundary = corner.join.x
        }
        let inside = sign * (point.x - boundary) <= 0
        return (inside ? 1 : -1) * min(arc, wall)
    }

    /// The 44 by 28 pill is the convex hull of two 14-point disks. Including
    /// its five-point rim in both disks bounds every visible part of it.
    /// Its size is fixed at every text size; the band remains the tap target.
    static func foldClearance(slab: CGRect, join: WardEdgeJoin, inset: Double) -> (slab: Double, island: Double) {
        let left = WardEdge.slabTopRadius(join.left, slabSide: slab.minX, leading: true)
        let right = WardEdge.slabTopRadius(join.right, slabSide: slab.maxX, leading: false)
        let top = slab.minY + WardPaper.edgeWidth / 2
        let centers = [SIMD2<Double>(slab.maxX - 36 - inset, slab.minY + 22),
                       SIMD2<Double>(slab.maxX - 20 - inset, slab.minY + 22)]
        let reach = 14 + WardRelief.rimReach
        var slabGap = Double.infinity, islandGap = Double.infinity
        for p in centers {
            slabGap = min(slabGap,
                distance(p, center: SIMD2(slab.minX + left, top + left), radius: left, left: true) - reach,
                distance(p, center: SIMD2(slab.maxX - right, top + right), radius: right, left: false) - reach)
            islandGap = min(islandGap, p.y - join.y - reach)
            if let c = join.left {
                islandGap = min(islandGap, distance(p, corner: c, left: true) - reach)
            }
            if let c = join.right {
                islandGap = min(islandGap, distance(p, corner: c, left: false) - reach)
            }
        }
        return (slabGap, islandGap)
    }

    static func foldInset(slab: CGRect, join: WardEdgeJoin) -> Double {
        func fits(_ inset: Double) -> Bool {
            let gap = foldClearance(slab: slab, join: join, inset: inset)
            return min(gap.slab, gap.island) >= 2.1
        }
        guard !fits(0) else { return 0 }
        var lo = 0.0, hi = slab.width / 2
        for _ in 0..<40 {
            let mid = (lo + hi) / 2
            if fits(mid) { hi = mid } else { lo = mid }
        }
        // Move only sideways: growing the band would move the deck's line
        // while finding its corner. Round inward, with a little room beyond
        // the required two points. The pill's press only makes it smaller.
        return (hi * 2).rounded(.up) / 2
    }
}
