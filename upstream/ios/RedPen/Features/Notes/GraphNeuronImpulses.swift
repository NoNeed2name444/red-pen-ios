import Foundation

// MARK: - When each axon fires
//
// Every link in the Neurons theme carries action potentials at its own
// random times: time is cut into slots of the link's own length (0.9 to
// 2.4 s); in each slot it fires or not (the Graphics budget's rate), at a
// random moment in the slot's first half - so two impulses on one axon are
// always at least half a slot apart, its refractory period - and now and
// then as a burst of three, 0.12 s apart. Each impulse runs the axon's whole
// length in its own travel time (0.45 to 0.95 s: a long axon conducts
// faster, as a myelinated one does), then flashes at the synapse.
//
// The axon shader (GraphNeuronShaders.axon) works this out per pixel from
// the link's seed and the shaders' clock; NeuronImpulses works out the same
// arrivals on the render thread, to light the receiving cell's dendrites
// as each impulse lands. Both use this exact integer hash (a PCG step) and
// these float steps, so the flash and the glow land together.
//
// Foundation only: tested on Linux (Tests/NeuronHierarchyTests).

nonisolated enum NeuronImpulse {
    /// Seconds between the impulses of a burst.
    static let burstGap: Float = 0.12
    /// Slots looked back over: an impulse fired up to three slots ago may
    /// still be running or flashing.
    static let slotsBack: Int = 3
    static let pulsesPerBurst: Int = 3

    /// One PCG step, as the shader does it.
    static func hash(_ x: UInt32) -> UInt32 {
        var h: UInt32 = x &* 747_796_405 &+ 2_891_336_453
        let shift: UInt32 = (h >> 28) &+ 4
        h = ((h >> shift) ^ h) &* 277_803_737
        return (h >> 22) ^ h
    }

    /// Eight bits of `h`, from `at`, as 0...1.
    static func byte(_ h: UInt32, _ at: UInt32) -> Float {
        Float((h >> at) & 255) / 255
    }

    /// A link's own rhythm: its slot, its travel time and where its slots
    /// start.
    struct Rhythm: Sendable, Equatable {
        let slot: Float
        let travel: Float
        let phase: Float
    }

    static func rhythm(seed: Int) -> Rhythm {
        let h: UInt32 = hash(UInt32(truncatingIfNeeded: seed))
        let slot: Float = 0.9 + 1.5 * byte(h, 0)
        let travel: Float = 0.45 + 0.5 * byte(h, 8)
        let phase: Float = byte(h, 16) * slot
        return Rhythm(slot: slot, travel: travel, phase: phase)
    }

    /// Slot `k`'s draw for link `seed`.
    static func slotHash(seed: Int, slot k: Float) -> UInt32 {
        let slot: UInt32 = UInt32(max(k, 0))
        let mixed: UInt32 = slot &* 2_654_435_761 &+ UInt32(truncatingIfNeeded: seed) &* 40_503 &+ 17
        return hash(mixed)
    }

    /// The times (on the shaders' clock) at which impulses reach the end of
    /// link `seed` in (`from`, `to`], with `rate` the chance a slot fires
    /// and `bursts` the chance a firing is a burst.
    static func arrivals(seed: Int, from: Float, to: Float, rate: Float, bursts: Float) -> [Float] {
        guard to > from else { return [] }
        let r: Rhythm = rhythm(seed: seed)
        let tt: Float = to + r.phase
        let now: Float = (tt / r.slot).rounded(.down)
        var found: [Float] = []
        for j in 0..<slotsBack {
            let k: Float = now - Float(j)
            let g: UInt32 = slotHash(seed: seed, slot: k)
            guard byte(g, 0) < rate else { continue }
            let fired: Float = k * r.slot + 0.5 * r.slot * byte(g, 8)
            let many: Int = byte(g, 16) < bursts ? pulsesPerBurst : 1
            for b in 0..<many {
                let lands: Float = fired + Float(b) * burstGap + r.travel - r.phase
                if lands > from && lands <= to { found.append(lands) }
            }
        }
        return found
    }

    /// Whether any impulse reaches the end of link `seed` in (`from`,
    /// `to`]: `arrivals` without making an array, for every link every
    /// frame.
    static func lands(seed: Int, from: Float, to: Float, rate: Float, bursts: Float) -> Bool {
        guard to > from else { return false }
        let r: Rhythm = rhythm(seed: seed)
        let tt: Float = to + r.phase
        let now: Float = (tt / r.slot).rounded(.down)
        for j in 0..<slotsBack {
            let k: Float = now - Float(j)
            let g: UInt32 = slotHash(seed: seed, slot: k)
            guard byte(g, 0) < rate else { continue }
            let fired: Float = k * r.slot + 0.5 * r.slot * byte(g, 8)
            let many: Int = byte(g, 16) < bursts ? pulsesPerBurst : 1
            for b in 0..<many {
                let at: Float = fired + Float(b) * burstGap + r.travel - r.phase
                if at > from && at <= to { return true }
            }
        }
        return false
    }

    /// Every firing time of link `seed` in [`from`, `to`) (the first
    /// impulse of each slot that fires), for the tests.
    static func firings(seed: Int, from: Float, to: Float, rate: Float) -> [Float] {
        let r: Rhythm = rhythm(seed: seed)
        var out: [Float] = []
        var k: Float = ((from + r.phase) / r.slot).rounded(.down)
        while k * r.slot - r.phase < to {
            let g: UInt32 = slotHash(seed: seed, slot: k)
            if byte(g, 0) < rate {
                let at: Float = k * r.slot + 0.5 * r.slot * byte(g, 8) - r.phase
                if at >= from && at < to { out.append(at) }
            }
            k += 1
        }
        return out
    }
}
