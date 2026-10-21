import Foundation

// MARK: - Keeping the links welded to their bodies
//
// The links are drawn from Metal buffers that the render thread rewrites
// every frame a body moves (GraphRibbonWriter). The GPU draws a frame some
// time after SceneKit's render thread has encoded it - up to a few frames
// later on a busy ProMotion device - so a buffer written for this frame
// must never be one the GPU is still reading for an earlier one: if it is,
// the GPU draws part of a link from this frame's positions and part from an
// older frame's, and the end at a moving body jumps back and forth (the
// "stutter" at a dragged body's link ends).
//
// So each buffer set carries the frame it was written in, and the render
// loop learns which frames the GPU has finished (GraphFrameFence commits an
// empty marker after each frame's work on SceneKit's own command queue; a
// queue finishes its buffers in order, so when the marker completes every
// earlier frame has been drawn). A set is written again only once the frame
// it last held is finished; when none is free, a new set is made (up to a
// cap) rather than overwriting one in flight.
//
// Also here: where the whole-map framing aims (GraphMapBounds) - the middle
// of the plan's box, not the origin, since a theme's plan need not be
// centred on it.
//
// Pure Foundation: tested on Linux (Tests/GraphDeathTests.swift).

/// Which buffer set a writer may fill this frame.
nonisolated enum GraphBufferRing {
    /// The most sets a writer keeps: beyond this, the least recently used
    /// finished-or-not set is reused (never reached in practice: SceneKit
    /// keeps at most three frames in flight).
    static let most: Int = 8

    /// The set to write in frame `now`, given the frame each set was last
    /// written in (`used`, 0 for never) and the newest frame the GPU has
    /// finished (`finished`): the least recently used set whose frame is
    /// finished; nil when every set is still in flight (make another).
    /// A set is never handed out twice in one frame.
    static func pick(used: [UInt64], finished: UInt64, now: UInt64) -> Int? {
        var best: Int? = nil
        var oldest: UInt64 = UInt64.max
        for (k, frame) in used.enumerated() {
            let free: Bool = frame == 0 || frame <= finished
            guard free, frame != now else { continue }
            if frame < oldest {
                oldest = frame
                best = k
            }
        }
        return best
    }

    /// When no set is free and no more may be made: the least recently
    /// used one (drawn from the oldest frame, so the likeliest finished).
    static func fallback(used: [UInt64], now: UInt64) -> Int {
        var best: Int = 0
        var oldest: UInt64 = UInt64.max
        for (k, frame) in used.enumerated() where frame != now && frame < oldest {
            oldest = frame
            best = k
        }
        return best
    }
}

/// Where the camera aims at the whole map, and how the framing's points are
/// taken relative to it.
nonisolated enum GraphMapBounds {
    /// The middle of the points' box (x, y and z); the origin for none.
    static func centre(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard let first = points.first else { return SIMD3<Float>(0, 0, 0) }
        var low: SIMD3<Float> = first
        var high: SIMD3<Float> = first
        for p in points {
            low = SIMD3<Float>(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
            high = SIMD3<Float>(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
        }
        let sum: SIMD3<Float> = low + high
        return sum * Float(0.5)
    }

    /// The points moved so their box is centred on the origin.
    static func centred(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        let middle: SIMD3<Float> = centre(points)
        return points.map { $0 - middle }
    }
}

/// How far a link is trimmed from a body's centre this frame: its trim
/// radius times its live size (popping in, bouncing when grabbed, shrinking
/// away), so the link's end stays on the body's rim as the body's size
/// springs - never a gap opening under a body that dips, nor the link
/// running into one that swells.
nonisolated enum GraphLinkEnds {
    static func radii(_ radius: [Float], scale: [Float], into out: inout [Float]) {
        let count: Int = radius.count
        if out.count != count { out = [Float](repeating: 0, count: count) }
        for i in 0..<count {
            let s: Float = i < scale.count ? scale[i] : 1
            let live: Float = min(max(s, 0.05), 1.6)
            out[i] = radius[i] * live
        }
    }
}
