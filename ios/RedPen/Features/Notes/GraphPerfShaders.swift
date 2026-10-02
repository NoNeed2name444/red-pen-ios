// The Performance map's shaders, as Metal source compiled at run time
// (MTLDevice.makeLibrary(source:)): Swift Playgrounds cannot compile .metal
// files. Kept in a Foundation-only file so the tests can hold the names and
// buffer slots the renderer asks for.
//
// Four instanced draws and their rules, the same as GraphPerfLOD's:
//
//   bodies   one quad per body in the draw list, a disc of its radius on
//            screen clamped to 1.25-28 points (hubs 3-48), a note under a
//            point and a quarter fading out; a lit ball once a few pixels
//            across, a flat dot below; opaque, writing depth; the chosen
//            body larger with a white ring
//   lines    one line per link in the list, coloured by each end, faded in
//            from 2 to 12 points long on screen, x0.55 between clusters,
//            fainter with depth, added up; an end inside a collapsed
//            cluster is moved to the cluster's centre; with a focus, its
//            own links x3 and the rest x0.15
//   bundles  one line per bundle between two collapsed clusters, as bright
//            as the log of the links it carries
//   glows    one soft disc per collapsed cluster, the size of its ball on
//            screen (at least 2 points), added up
//
// The frame's numbers are one struct, ten float4s (Frame below):
//   viewProj  world to clip
//   eye       xyz, w time
//   screen    width, height (points), focal length (points), pixels per point
//   lod       note radius min, max; hub radius min, max (points)
//   link      base alpha, fade from, fade to (points), bundle alpha
//   focus     chosen body (-1 none), body whose links stand out (-1), note count, glow floor (points)
//   fog       depth where links start to fade, where they are faintest, 0, link count
import Foundation

nonisolated enum GraphPerfShaders {
    /// Buffer slots, the same for every function.
    enum Slot {
        static let frame = 0
        static let positions = 1
        static let colours = 2
        static let list = 3
        static let lineEnds = 4
        static let clusterOfBody = 5
        static let clusterBalls = 6
        static let collapsed = 7
        static let clusterColours = 8
        static let bundleEnds = 9
        static let bundleWeights = 10
    }

    /// The frame struct's size: ten float4s.
    static let frameFloats = 40

    /// The frame's numbers for this viewpoint, in Frame's order.
    static func frame(_ v: GraphPerfViewpoint, scene: GraphPerfScene, tier: GraphPerfTier, bold: Bool,
                      selected: Int?, focus: Int?, pixelsPerPoint: Float, time: Float) -> [SIMD4<Float>] {
        let cam = v.camera
        let projection = cam.projectionMatrix(aspect: v.width / max(v.height, 1), near: v.near, far: v.far)
        let viewProj = projection * cam.viewMatrix()
        let eye = cam.eye
        let base: Float = tier.linkBase * (bold ? 1.5 : 1)
        let toCentre = max(((scene.centre - eye) * cam.forward).sum(), 0)
        let notes = GraphPerfLOD.noteClamp, hubs = GraphPerfLOD.hubClamp
        return [
            viewProj.c0, viewProj.c1, viewProj.c2, viewProj.c3,
            SIMD4(eye.x, eye.y, eye.z, time),
            SIMD4(v.width, v.height, cam.focal(viewHeight: v.height), pixelsPerPoint),
            SIMD4(notes.lowerBound, notes.upperBound, hubs.lowerBound, hubs.upperBound),
            SIMD4(base, 2, 12, min(base * 2, 1)),
            SIMD4(Float(selected ?? -1), Float(focus ?? -1), Float(scene.graph.noteCount), GraphPerfLOD.glowFloor),
            SIMD4(toCentre, toCentre + 2 * scene.radius, 0, Float(scene.graph.linkCount))
        ]
    }

    static let functions: [String] = [
        "perf_body_vertex", "perf_body_fragment", "perf_line_vertex", "perf_line_fragment",
        "perf_bundle_vertex", "perf_glow_vertex", "perf_glow_fragment"
    ]

    static let source: String = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct Frame {
        float4x4 viewProj;
        float4 eye;
        float4 screen;
        float4 lod;
        float4 link;
        float4 focus;
        float4 fog;
    };

    struct BodyOut {
        float4 position [[position]];
        float4 colour;
        float2 uv;
        float pixels;
        float ring;
    };

    struct LineOut {
        float4 position [[position]];
        float4 colour;
    };

    struct GlowOut {
        float4 position [[position]];
        float4 colour;
        float2 uv;
    };

    static float2 corner(uint vid) {
        return float2((vid & 1u) != 0u ? 1.0 : -1.0, (vid & 2u) != 0u ? 1.0 : -1.0);
    }

    // a quad of `radius` points round a clip-space centre
    static float4 spread(float4 clip, float2 c, float radius, constant Frame& f) {
        float4 moved = clip;
        moved.xy += c * (radius * 2.0 / f.screen.xy) * clip.w;
        return moved;
    }

    vertex BodyOut perf_body_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                    constant Frame& f [[buffer(0)]],
                                    const device float4* xyzr [[buffer(1)]],
                                    const device uint* colour [[buffer(2)]],
                                    const device uint* list [[buffer(3)]]) {
        uint i = list[iid];
        float4 p = xyzr[i];
        float4 clip = f.viewProj * float4(p.xyz, 1.0);
        float depth = max(clip.w, 0.0001);
        float rho = p.w * f.screen.z / depth;
        bool note = float(i) < f.focus.z;
        float lo = note ? f.lod.x : f.lod.z;
        float hi = note ? f.lod.y : f.lod.w;
        float drawn = clamp(rho, lo, hi);
        float fade = note ? smoothstep(0.35, 1.25, rho) : 1.0;
        bool chosen = float(i) == f.focus.x;
        if (chosen) {
            drawn = max(drawn * 1.4, 7.0);
            fade = 1.0;
        }
        float2 c = corner(vid);
        BodyOut o;
        o.position = spread(clip, c, drawn, f);
        o.colour = float4(unpack_unorm4x8_to_float(colour[i]).rgb, fade);
        o.uv = c;
        o.pixels = drawn * f.screen.w;
        o.ring = chosen ? 1.0 : 0.0;
        return o;
    }

    fragment float4 perf_body_fragment(BodyOut in [[stage_in]]) {
        float r = length(in.uv);
        float edge = 1.0 / max(in.pixels, 1.0);
        float coverage = 1.0 - smoothstep(1.0 - edge, 1.0, r);
        if (coverage <= 0.02) {
            discard_fragment();
        }
        float z = sqrt(max(1.0 - r * r, 0.0));
        float3 n = float3(in.uv.x, in.uv.y, z);
        float light = max(dot(n, normalize(float3(-0.45, 0.55, 0.7))), 0.0);
        float rim = pow(1.0 - z, 3.0);
        float detail = smoothstep(2.5, 7.0, in.pixels);
        float shade = mix(1.0, 0.38 + 0.8 * light + 0.55 * rim, detail);
        float3 rgb = in.colour.rgb * shade * in.colour.a;
        if (in.ring > 0.5) {
            float band = smoothstep(0.66, 0.74, r) * (1.0 - smoothstep(0.86, 0.94, r));
            rgb = mix(rgb, float3(1.0), band);
        }
        return float4(rgb, coverage);
    }

    static float3 lineEnd(uint body, const device float4* xyzr, const device uint* clusterOf,
                          const device float4* balls, const device uint* collapsed) {
        uint s = clusterOf[body];
        return collapsed[s] != 0u ? balls[s].xyz : xyzr[body].xyz;
    }

    // how long a line is on screen, in points (long when an end is behind the eye)
    static float screenLength(float4 a, float4 b, constant Frame& f) {
        if (a.w <= 0.0001 || b.w <= 0.0001) {
            return 10000.0;
        }
        float2 pa = a.xy / a.w * 0.5 * f.screen.xy;
        float2 pb = b.xy / b.w * 0.5 * f.screen.xy;
        return length(pa - pb);
    }

    static float fogged(float alpha, float depth, constant Frame& f) {
        return alpha * (1.0 - 0.6 * smoothstep(f.fog.x, f.fog.y, depth));
    }

    vertex LineOut perf_line_vertex(uint vid [[vertex_id]],
                                    constant Frame& f [[buffer(0)]],
                                    const device float4* xyzr [[buffer(1)]],
                                    const device uint* colour [[buffer(2)]],
                                    const device uint* list [[buffer(3)]],
                                    const device uint2* ends [[buffer(4)]],
                                    const device uint* clusterOf [[buffer(5)]],
                                    const device float4* balls [[buffer(6)]],
                                    const device uint* collapsed [[buffer(7)]]) {
        uint line = list[vid >> 1];
        uint2 e = ends[line];
        bool second = (vid & 1u) != 0u;
        uint me = second ? e.y : e.x;
        uint other = second ? e.x : e.y;
        float4 cp = f.viewProj * float4(lineEnd(me, xyzr, clusterOf, balls, collapsed), 1.0);
        float4 cq = f.viewProj * float4(lineEnd(other, xyzr, clusterOf, balls, collapsed), 1.0);
        float alpha = f.link.x * smoothstep(f.link.y, f.link.z, screenLength(cp, cq, f));
        bool tree = float(line) >= f.fog.w;
        if (tree) {
            alpha *= 1.2;
        } else if (clusterOf[e.x] != clusterOf[e.y]) {
            alpha *= 0.55;
        }
        if (f.focus.y >= 0.0) {
            bool touches = float(e.x) == f.focus.y || float(e.y) == f.focus.y;
            alpha *= touches ? 3.0 : 0.15;
        }
        alpha = min(fogged(alpha, cp.w, f), 1.0);
        LineOut o;
        o.position = cp;
        o.colour = float4(unpack_unorm4x8_to_float(colour[me]).rgb * alpha, alpha);
        return o;
    }

    fragment float4 perf_line_fragment(LineOut in [[stage_in]]) {
        return in.colour;
    }

    vertex LineOut perf_bundle_vertex(uint vid [[vertex_id]],
                                      constant Frame& f [[buffer(0)]],
                                      const device uint* list [[buffer(3)]],
                                      const device float4* balls [[buffer(6)]],
                                      const device uint* clusterColour [[buffer(8)]],
                                      const device uint2* bundleEnds [[buffer(9)]],
                                      const device float* weights [[buffer(10)]]) {
        uint b = list[vid >> 1];
        uint2 e = bundleEnds[b];
        uint s = (vid & 1u) != 0u ? e.y : e.x;
        float4 cp = f.viewProj * float4(balls[s].xyz, 1.0);
        float alpha = f.link.w * (0.35 + 0.65 * saturate(log2(1.0 + weights[b]) / 6.0));
        if (f.focus.y >= 0.0) {
            alpha *= 0.15;
        }
        alpha = min(fogged(alpha, cp.w, f), 1.0);
        LineOut o;
        o.position = cp;
        o.colour = float4(unpack_unorm4x8_to_float(clusterColour[s]).rgb * alpha, alpha);
        return o;
    }

    vertex GlowOut perf_glow_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                    constant Frame& f [[buffer(0)]],
                                    const device uint* list [[buffer(3)]],
                                    const device float4* balls [[buffer(6)]],
                                    const device uint* clusterColour [[buffer(8)]]) {
        uint s = list[iid];
        float4 b = balls[s];
        float4 clip = f.viewProj * float4(b.xyz, 1.0);
        float depth = max(clip.w, 0.0001);
        float rho = b.w * f.screen.z / depth;
        float drawn = max(rho, f.focus.w) * 1.6;
        float2 c = corner(vid);
        GlowOut o;
        o.position = spread(clip, c, drawn, f);
        o.colour = float4(unpack_unorm4x8_to_float(clusterColour[s]).rgb, 1.0);
        o.uv = c;
        return o;
    }

    fragment float4 perf_glow_fragment(GlowOut in [[stage_in]]) {
        float r2 = dot(in.uv, in.uv);
        if (r2 >= 1.0) {
            discard_fragment();
        }
        float a = exp(-r2 * 5.0) * 0.85;
        return float4(in.colour.rgb * a, a);
    }
    """#
}
