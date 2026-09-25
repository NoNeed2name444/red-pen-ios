import Foundation
import simd

// MARK: - One sky everywhere
//
// The sky the 3D note map flies through (GraphSpace, in GraphLook.swift) and
// the sky behind every other screen (AppBackdrop's star layers) are the SAME
// sky: the same galactic band, the same nebula clouds and the same stars,
// from the same seeds in the same order. The flat screens show it through a
// fixed camera that matches the map's opening one (at +z looking down -z,
// the map's vertical field of view), so opening the map looks like the flat
// sky gaining depth rather than a jump to somewhere else.
//
// Pure values and pure functions, safe on any thread.

/// One star of the shared catalogue.
struct SkyStar: Sendable {
    /// Its direction on the unit sphere.
    var dir: SIMD3<Float>
    /// 0...1, how bright it is beyond the faintest (roll to the fourth).
    var shine: Float
    /// Which of `SkyChart.starTints` it wears.
    var tint: Int
}

/// One nebula cloud along the band.
struct SkyCloud: Sendable {
    var centre: SIMD3<Float>
    /// Angular reach, in radians (roughly).
    var reach: Float
    /// Colour times strength, sRGB.
    var colour: SIMD3<Float>
}

/// One of the few bright glowing stars.
struct SkyGlowStar: Sendable {
    var dir: SIMD3<Float>
    var size: Float
}

nonisolated enum SkyChart {
    /// Bumped whenever anything that is baked from here changes, so cached
    /// bakes are made again.
    static let version: Int = 1

    /// The Milky Way's plane, tilted across the sky.
    static let bandNormal: SIMD3<Float> = simd_normalize(SIMD3<Float>(0.35, 0.9, 0.25))

    /// The nebula's three hues: blue, violet, teal.
    static let nebulaHues: [SIMD3<Float>] = [
        SIMD3<Float>(0.20, 0.30, 0.78),
        SIMD3<Float>(0.36, 0.22, 0.66),
        SIMD3<Float>(0.12, 0.36, 0.58)
    ]

    /// White, blue-white and warm white.
    static let starTints: [SIMD3<Float>] = [
        SIMD3<Float>(1, 1, 1),
        SIMD3<Float>(0.76, 0.85, 1),
        SIMD3<Float>(1, 0.9, 0.76)
    ]

    static let cloudSeed: UInt64 = 0x0B1A
    static let starSeed: UInt64 = 0x57A3
    static let glowSeed: UInt64 = 0x6105
    static let starCount: Int = 14000
    static let glowCount: Int = 36

    /// The map's vertical field of view, in degrees (GraphFraming).
    static let fieldOfView: Float = 55

    /// Every star, in the order the map makes them.
    static let stars: [SkyStar] = makeStars()

    /// The nebula clouds, in the order the map makes them.
    static let clouds: [SkyCloud] = makeClouds()

    /// The bright glowing stars.
    static let glowStars: [SkyGlowStar] = makeGlowStars()

    private static func makeStars() -> [SkyStar] {
        var random = SplitMix64(seed: starSeed)
        var out: [SkyStar] = []
        out.reserveCapacity(starCount)
        for k in 0..<starCount {
            let crowded: Bool = k % 5 < 2
            let dir: SIMD3<Float> = crowded ? onBand(&random, spread: 0.18) : anywhere(&random)
            let roll: Float = random.unit() * 0.5 + 0.5
            let squared: Float = roll * roll
            let shine: Float = squared * squared
            out.append(SkyStar(dir: dir, shine: shine, tint: k % starTints.count))
        }
        return out
    }

    private static func makeClouds() -> [SkyCloud] {
        var random = SplitMix64(seed: cloudSeed)
        var out: [SkyCloud] = []
        for k in 0..<30 {
            let near: SIMD3<Float> = onBand(&random, spread: 0.12)
            let reach: Float = 0.18 + (random.unit() * 0.5 + 0.5) * 0.3
            let strength: Float = 0.07 + (random.unit() * 0.5 + 0.5) * 0.09
            let hue: SIMD3<Float> = nebulaHues[k % nebulaHues.count]
            out.append(SkyCloud(centre: near, reach: reach, colour: hue * strength))
        }
        return out
    }

    private static func makeGlowStars() -> [SkyGlowStar] {
        var random = SplitMix64(seed: glowSeed)
        var out: [SkyGlowStar] = []
        for _ in 0..<glowCount {
            let dir: SIMD3<Float> = anywhere(&random)
            let size: Float = 0.0032 + (random.unit() * 0.5 + 0.5) * 0.0022
            out.append(SkyGlowStar(dir: dir, size: size))
        }
        return out
    }

    /// A random direction, even over the sphere.
    static func anywhere(_ random: inout SplitMix64) -> SIMD3<Float> {
        let y: Float = random.unit()
        let turn: Float = random.unit() * Float.pi
        let flat: Float = max(1 - y * y, 0).squareRoot()
        return SIMD3<Float>(flat * cos(turn), y, flat * sin(turn))
    }

    /// A random direction near the band's plane.
    static func onBand(_ random: inout SplitMix64, spread: Float) -> SIMD3<Float> {
        let dir: SIMD3<Float> = anywhere(&random)
        let off: Float = simd_dot(dir, bandNormal)
        let scatter: Float = random.unit() * random.unit() * spread
        let flat: SIMD3<Float> = dir - bandNormal * off
        let lifted: SIMD3<Float> = flat + bandNormal * scatter
        return simd_normalize(lifted)
    }

    // MARK: The flat view of it

    /// Where a direction lands on a flat screen seen through the map's
    /// opening camera, in "tan space": (0, 0) is the middle, +x right, +y
    /// down, in units of the camera's focal length - multiply by
    /// `scale(height:)` for points. Nil when the direction is behind the
    /// camera.
    static func project(_ dir: SIMD3<Float>) -> SIMD2<Float>? {
        guard dir.z < -0.05 else { return nil }
        let depth: Float = -dir.z
        let u: Float = dir.x / depth
        let v: Float = -dir.y / depth
        return SIMD2<Float>(u, v)
    }

    /// Points per unit of tan space, for a screen `height` points tall.
    static func scale(height: Float) -> Float {
        let half: Float = fieldOfView * Float.pi / 360
        return (height / 2) / tan(half)
    }

    /// The band's centre line in tan space: v = slope * u + offset.
    static var bandSlope: Float { bandNormal.x / bandNormal.y }
    static var bandOffset: Float { -bandNormal.z / bandNormal.y }
}
