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

    /// Metal: `fbm`, with the octaves from `from` on weighed by `fine` (a
    /// float expression, 0...1) in both the sum and the normalising weight:
    /// at 1 it is fbm(`octaves`) to the bit, at 0 fbm(`from`), and between
    /// the finest octaves morph in and out with no step (SpaceDepth's
    /// detail by size on screen). `octaves` may drop to `from` when `fine`
    /// is 0, so the loop is not run for nothing.
    static func fbm(_ out: String, _ p: String, octaves: String, from: Int, fine: String) -> String {
        """
        float \(out) = 0.0;
        float \(out)_wt = 0.5;
        float \(out)_sum = 0.0;
        float3 \(out)_x = \(p);
        for (int \(out)_o = 0; \(out)_o < \(octaves); \(out)_o++) {

        """ + noise(out + "_v", out + "_x") + """
        float \(out)_k = \(out)_o < \(from) ? 1.0 : \(fine);
        \(out) = \(out) + \(out)_v * \(out)_wt * \(out)_k;
        \(out)_sum = \(out)_sum + \(out)_wt * \(out)_k;
        \(out)_x = \(out)_x * 2.03 + float3(1.7, 9.2, 3.1);
        \(out)_wt = \(out)_wt * 0.5;
        }
        \(out) = \(out) / max(\(out)_sum, 0.0001);

        """
    }

    /// Metal: cellular (Worley) noise of the float3 expression `p`, from
    /// the 2x2x2 cells nearest the point (each cell's feature point kept to
    /// its middle half, so the nearest is almost always among them): into
    /// new floats `out`_f1 and `out`_f2 (the distances to the nearest and
    /// second-nearest points; f2 - f1 is 0 on the borders between cells)
    /// and `out`_id (0...1, the nearest cell's own number). `wobble` (a
    /// float expression) moves each point round its place, so cells boil.
    static func cells(_ out: String, _ p: String, wobble: String) -> String {
        """
        float3 \(out)_p = \(p);
        float3 \(out)_i = floor(\(out)_p);
        float3 \(out)_f = \(out)_p - \(out)_i;
        float3 \(out)_o = step(float3(0.5), \(out)_f) - float3(1.0);
        float \(out)_f1 = 8.0;
        float \(out)_f2 = 8.0;
        float \(out)_id = 0.0;
        for (int \(out)_k = 0; \(out)_k < 8; \(out)_k++) {
        float3 \(out)_c = \(out)_o + float3(float(\(out)_k & 1), float((\(out)_k >> 1) & 1), float((\(out)_k >> 2) & 1));
        float3 \(out)_g = \(out)_i + \(out)_c;
        float \(out)_h = \(out)_g.x + \(out)_g.y * 57.0 + \(out)_g.z * 113.0;
        float3 \(out)_r = fract(sin(float3(\(out)_h, \(out)_h + 31.7, \(out)_h + 67.3)) * 43758.5453);
        float3 \(out)_j = float3(0.5) + (\(out)_r - float3(0.5)) * 0.5 + sin(\(out)_r * 6.2831853 + float3(\(wobble))) * 0.1;
        float3 \(out)_d = \(out)_c + \(out)_j - \(out)_f;
        float \(out)_dd = dot(\(out)_d, \(out)_d);
        if (\(out)_dd < \(out)_f1) {
        \(out)_f2 = \(out)_f1;
        \(out)_f1 = \(out)_dd;
        \(out)_id = \(out)_r.x;
        } else if (\(out)_dd < \(out)_f2) {
        \(out)_f2 = \(out)_dd;
        }
        }
        \(out)_f1 = sqrt(\(out)_f1);
        \(out)_f2 = sqrt(\(out)_f2);

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

    /// The morphing fbm as the shaders sum it: octaves from `from` on
    /// weighed by `fine`.
    static func fbm(_ p: SIMD3<Float>, octaves: Int, from: Int, fine: Float) -> Float {
        var total: Float = 0
        var weight: Float = 0.5
        var sum: Float = 0
        var x: SIMD3<Float> = p
        for o in 0..<max(octaves, 0) {
            let k: Float = o < from ? 1 : fine
            total += value(x) * weight * k
            sum += weight * k
            x = x * 2.03 + SIMD3<Float>(1.7, 9.2, 3.1)
            weight *= 0.5
        }
        return total / max(sum, 0.0001)
    }

    static func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }
}
