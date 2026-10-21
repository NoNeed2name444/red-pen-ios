import Foundation

// MARK: - Shared pieces of the 3D map's shaders
//
// The shader modifiers follow one rule that makes them hard to share code
// in: no helper functions (GraphShaders' rule, kept by every look). So the
// pieces every theme wants - smooth value noise, and a few octaves of it
// (fBm) - are written here as Metal source, inlined where they are used,
// every variable named after the result so one shader can use them many
// times.
//
// The noise is the classic hashed lattice: the eight corners of the cell
// round a point each get a pseudo-random value, fract(sin(n) * 43758.5453)
// of the corner's number n = x + 57 y + 113 z, blended by a smoothstep fade.
// It is continuous everywhere (the corners are shared by neighbouring cells)
// and stays in 0...1. Arguments are kept small (a few hundred at most) so a
// 32-bit sine is still exact enough to hash with.
//
// The same maths in Swift (`value`, `fbm`) is what the tests check
// (Tests/ShaderSourceTests), and what anything on the CPU that must agree
// with a shader can call. Foundation only.

nonisolated enum GraphShaderKit {
    /// Metal: value noise of the float3 expression `p`, into a new float
    /// named `out` (0...1).
    static func noise(_ out: String, _ p: String) -> String {
        """
        float3 \(out)_p = \(p);
        float3 \(out)_i = floor(\(out)_p);
        float3 \(out)_f = \(out)_p - \(out)_i;
        float3 \(out)_u = \(out)_f * \(out)_f * (3.0 - 2.0 * \(out)_f);
        float \(out)_n = \(out)_i.x + \(out)_i.y * 57.0 + \(out)_i.z * 113.0;
        float \(out)_a = mix(fract(sin(\(out)_n) * 43758.5453), fract(sin(\(out)_n + 1.0) * 43758.5453), \(out)_u.x);
        float \(out)_b = mix(fract(sin(\(out)_n + 57.0) * 43758.5453), fract(sin(\(out)_n + 58.0) * 43758.5453), \(out)_u.x);
        float \(out)_c = mix(fract(sin(\(out)_n + 113.0) * 43758.5453), fract(sin(\(out)_n + 114.0) * 43758.5453), \(out)_u.x);
        float \(out)_d = mix(fract(sin(\(out)_n + 170.0) * 43758.5453), fract(sin(\(out)_n + 171.0) * 43758.5453), \(out)_u.x);
        float \(out) = mix(mix(\(out)_a, \(out)_b, \(out)_u.y), mix(\(out)_c, \(out)_d, \(out)_u.y), \(out)_u.z);

        """
    }

    /// Metal: `octaves` (an int expression) of value noise at `p`, each
    /// twice the frequency and half the weight of the one before, into a
    /// new float `out` (0...1, normalised by the weights).
    static func fbm(_ out: String, _ p: String, octaves: String) -> String {
        """
        float \(out) = 0.0;
        float \(out)_wt = 0.5;
        float \(out)_sum = 0.0;
        float3 \(out)_x = \(p);
        for (int \(out)_o = 0; \(out)_o < \(octaves); \(out)_o++) {

        """ + noise(out + "_v", out + "_x") + """
        \(out) = \(out) + \(out)_v * \(out)_wt;
        \(out)_sum = \(out)_sum + \(out)_wt;
        \(out)_x = \(out)_x * 2.03 + float3(1.7, 9.2, 3.1);
        \(out)_wt = \(out)_wt * 0.5;
        }
        \(out) = \(out) / max(\(out)_sum, 0.0001);

        """
    }

    // MARK: the same maths on the CPU

    /// fract(sin(n) * 43758.5453), in Float as the GPU has it.
    static func hash(_ n: Float) -> Float {
        let v: Float = sin(n) * 43758.5453
        return v - v.rounded(.down)
    }

    /// The value noise at `p` (0...1).
    static func value(_ p: SIMD3<Float>) -> Float {
        let i = SIMD3<Float>(p.x.rounded(.down), p.y.rounded(.down), p.z.rounded(.down))
        let f: SIMD3<Float> = p - i
        let u: SIMD3<Float> = f * f * (SIMD3<Float>(3, 3, 3) - f * 2)
        let n: Float = i.x + i.y * 57 + i.z * 113
        let a: Float = mix(hash(n), hash(n + 1), u.x)
        let b: Float = mix(hash(n + 57), hash(n + 58), u.x)
        let c: Float = mix(hash(n + 113), hash(n + 114), u.x)
        let d: Float = mix(hash(n + 170), hash(n + 171), u.x)
        return mix(mix(a, b, u.y), mix(c, d, u.y), u.z)
    }

    /// `octaves` of value noise at `p`, as the shaders sum them.
    static func fbm(_ p: SIMD3<Float>, octaves: Int) -> Float {
        var total: Float = 0
        var weight: Float = 0.5
        var sum: Float = 0
        var x: SIMD3<Float> = p
        for _ in 0..<max(octaves, 0) {
            total += value(x) * weight
            sum += weight
            x = x * 2.03 + SIMD3<Float>(1.7, 9.2, 3.1)
            weight *= 0.5
        }
        return total / max(sum, 0.0001)
    }

    static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }
}
