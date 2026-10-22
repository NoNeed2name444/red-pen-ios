// The million map's shaders, as Metal source compiled at run time
// (MTLDevice.makeLibrary(source:)), like GraphPerfShaders: Swift
// Playgrounds cannot compile .metal files. Foundation only, so the tests and
// tools/shader_check.py hold the names, slots and frame layout.
//
//   mil_layout          the GPU layout, one compute pass a step over every
//                       leaf being prepared (a thread finds its leaf by a
//                       binary search of the jobs): each body moves a little
//                       towards its neighbours and back towards its seed,
//                       never more than a third of a spacing from it nor out
//                       of its leaf's box, and is written back as 16-bit numbers
//   mil_node_vertex     one quad per body of every leaf drawn body by body,
//                       found from the instance by a binary search of the
//                       drawn leaves; placed and sized by its leaf's morph
//                       (it moves out of the leaf's summary point and grows
//                       as the leaf opens) and by its leaf's detail (D1:
//                       smaller and flatter at the back); its colour mixed
//                       towards the ground by its depth fade (plan 4f,
//                       GraphPerfDepthBand), drawn opaque with the depth
//                       test; past the band's end, not drawn at all
//   mil_focus_link_vertex  the chosen note's own links, read straight from
//                       the adjacency (none by default): each grows out from
//                       the chosen note (GraphPerfFocusLook.tip), a smooth
//                       1.3-point band shaded from one note's colour to the other's
//   mil_focus_node_vertex  each neighbour again, over the dimmed map, growing
//                       in as its link reaches it
//   mil_chosen_vertex   the chosen body again, over everything, with a ring
//   mil_bundle_vertex   one faint band per bundle (the strongest 300 at most)
//                       between two cut cells, as wide as the log of the
//                       links it carries times the share of both ends still
//                       closed: it narrows to nothing as the links take
//                       over, and the last few the budget leaves out narrow
//                       away too (never a fade)
//   mil_summary_vertex  one soft disc per summary point: brightness from how
//                       many it stands for, colour their mix, its radius and
//                       its floor both times its morph scale
//
// Bundles and glows are additive light: their share is times 1 - f, so they
// fade to nothing with depth (never towards the ground, which would
// brighten them), and times 1 - dim while a note is chosen.
//
// The frame's numbers are eight float4s after the matrix (Frame below):
//   eye      xyz, w time
//   screen   width, height (points), focal length (points), pixels per point
//   look     body floor (points), summary floor (points), bundle alpha, bundle width (points)
//   pick     chosen slot (-1 none), largest body (points), glow strength, focus links drawn
//   fade     band start depth, end depth, exponent k, most (0: no fade)
//   focus    links' growth (0...1, eased), reach (world: the longest link), dim, link width (points)
//   bundles  limit (eased count: those under it full width), ramp (the next ones narrowing
//            to nothing), width cap (points),
//            reach (points) past which a bundle running off the screen dims
//   sky      the ground's rgb (what the fade mixes towards), w unused
//
// Light (bundles, glows) adds up in an rgba16Float picture at a quarter of
// the pixels; the resolve pass tone-maps it onto the screen (1 - exp(-k x),
// k from the picture's own 97th percentile, GraphPerfExposure) and the
// notes are drawn over it in their own colours, so dense light reads as
// structure, never a white fill, and notes stay shapes.
//   mil_resolve_vertex/_fragment  one triangle over the screen: sky + (1 - sky) x tone
//   mil_measure         a 64 x 64 grid of samples: the light's luminance (for
//                       the exposure) and the screen's (the share at 250+)
import Foundation

nonisolated enum GraphPerfMillionShaders {
    /// Render buffer slots, the same for every vertex function.
    enum Slot {
        static let frame = 0
        static let packed = 1
        static let looks = 2
        static let boxes = 3
        static let standIn = 4
        static let drawLeaves = 5
        static let drawCount = 6
        static let adjacencyStart = 7
        static let adjacency = 8
        static let bundleEnds = 9
        static let bundleWeights = 10
        static let bundleCells = 11
        static let cutColours = 12
        static let summaries = 13
        /// Per bundle cut cell: 1/sqrt(the bundles meeting there).
        static let cutWeights = 14
        /// Per leaf: its detail, 0 (back) ... 1 (front) (GraphPerfChunkFrame.leafDetail).
        static let leafDetail = 15
    }

    /// The resolve and measure passes' slots.
    enum ResolveSlot {
        /// fragment bytes: exposure k, then the sky's rgb
        static let tone = 0
        /// texture 0: the light (accumulated, rgba16Float); texture 1: the screen
        static let light = 0
        static let screen = 1
        /// the measure kernel's samples: (light, screen) luminance pairs
        static let samples = 0
    }

    /// The measure kernel samples a grid of this many points a side.
    static let measureGrid = 64

    /// The layout kernel's slots: the jobs (first slot, count, leaf, the
    /// threads before it), then as before, then how many jobs and threads.
    enum LayoutSlot {
        static let jobs = 0
        static let packed = 1
        static let seed = 2
        static let boxes = 3
        static let adjacencyStart = 4
        static let adjacency = 5
        static let params = 6
        static let count = 7
    }

    /// How far a body may move from its seed, in spacings, and per step
    /// towards its neighbours and back to its seed.
    static let layoutReach: Float = 0.3
    static let layoutPull: Float = 0.12
    static let layoutAnchor: Float = 0.1
    /// Steps a leaf is laid out when it is prepared.
    static let layoutSteps = 10
    /// The frame struct's size in floats: the matrix and eight float4s.
    static let frameFloats = 48

    static let functions: [String] = [
        "mil_layout", "mil_node_vertex", "mil_chosen_vertex", "mil_node_fragment", "mil_focus_link_vertex",
        "mil_focus_link_fragment", "mil_focus_node_vertex", "mil_bundle_vertex", "mil_line_fragment",
        "mil_summary_vertex", "mil_summary_fragment", "mil_resolve_vertex", "mil_resolve_fragment", "mil_measure"
    ]

    /// The widest a bundle is drawn (points, before Bold).
    static let bundleWidthCap: Float = 2.5
    /// At most this many bundles, the strongest: groups, not a web.
    static let bundleCap = 300
    /// The light is drawn at this share of the screen's pixels a side (a
    /// quarter of the pixels), then filtered up by the resolve: glows and
    /// bands are soft anyway, and it is most of the GPU's fill.
    static let lightScale: Float = 0.5
    /// A bundle with an end off the screen is drawn at full strength up to
    /// this share of the screen's shorter side long, dimmer in proportion
    /// beyond it (never under `longFloor`).
    static let longReach: Float = 0.35
    static let longFloor: Float = 0.12

    /// The selection as the frame draws it.
    struct Focus: Sendable, Equatable {
        /// The chosen slot (nil: none).
        var slot: Int?
        /// Its links drawn (at most GraphPerfFocusLook.most).
        var links: Int = 0
        /// How far they have grown (eased, 0...1), the longest one's length
        /// (world), and how far the rest has stepped back.
        var grow: Float = 0
        var reach: Float = 1
        var dim: Float = 0
    }

    /// The bundles drawn: the eased count, and how many narrow away at it.
    static func bundleRamp(limit: Float) -> Float { max(8, 0.2 * limit) }

    static func frame(camera cam: GraphPerfCamera, width: Float, height: Float, near: Float, far: Float,
                      tier: GraphPerfTier, bold: Bool, focus: Focus, fade: SIMD4<Float>, bundleLimit: Float,
                      sky: SIMD3<Float>, pixelsPerPoint: Float, time: Float) -> [SIMD4<Float>] {
        let projection = cam.projectionMatrix(aspect: width / max(height, 1), near: near, far: far)
        let viewProj = projection * cam.viewMatrix()
        let eye = cam.eye
        let base: Float = tier.linkBase * (bold ? 1.5 : 1)
        return [
            viewProj.c0, viewProj.c1, viewProj.c2, viewProj.c3,
            SIMD4(eye.x, eye.y, eye.z, time),
            SIMD4(width, height, cam.focal(viewHeight: height), pixelsPerPoint),
            SIMD4(GraphPerfLOD.noteClamp.lowerBound, 1.6, min(base * 0.8, 0.3), bold ? 3 : 2.2),
            SIMD4(Float(focus.slot ?? -1), GraphPerfLOD.hubClamp.upperBound, tier == .saver ? 0.7 : 1,
                  Float(focus.links)),
            fade,
            SIMD4(focus.grow, max(focus.reach, 1e-4), focus.dim, GraphPerfFocusLook.linkWidth * (bold ? 1.4 : 1)),
            SIMD4(bundleLimit, bundleRamp(limit: bundleLimit), bundleWidthCap * (bold ? 1.4 : 1),
                  longReach * min(width, height)),
            SIMD4(sky.x, sky.y, sky.z, 0)
        ]
    }

    static let source: String = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct Frame {
        float4x4 viewProj;
        float4 eye;
        float4 screen;
        float4 look;
        float4 pick;
        float4 fade;
        float4 focus;
        float4 bundles;
        float4 sky;
    };

    // a leaf's box: low corner (w: first slot's bits), extent (w: count's bits)
    struct LeafBox {
        float4 lo;
        float4 extent;
    };

    struct NodeOut {
        float4 position [[position]];
        float4 colour;
        float2 uv;
        float pixels;
        float ring;
        float detail;
        float fade;
        float dim;
    };

    struct LinkOut {
        float4 position [[position]];
        float4 colour;
        float across;
        float half_width;
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

    static float3 unpack_position(ushort4 q, LeafBox b) {
        return b.lo.xyz + float3(q.xyz) * (1.0 / 65535.0) * b.extent.xyz;
    }

    // how far a leaf is open (its stand-in's w carries 2 more when drawn)
    static float leaf_open(float w) {
        return w >= 2.0 ? w - 2.0 : w;
    }

    // the drawn leaf holding instance `i`: the last whose first instance is <= i
    static uint find_leaf(const device uint2* draw, uint count, uint i) {
        uint lo = 0u;
        uint hi = count;
        while (hi - lo > 1u) {
            uint mid = (lo + hi) / 2u;
            if (draw[mid].y <= i) { lo = mid; } else { hi = mid; }
        }
        return lo;
    }

    // the depth fade at view depth `depth`: SceneKit's fog curve,
    // clamp((z - start) / (end - start), 0, 1)^k, times its most
    static float fade_at(float depth, constant Frame& f) {
        if (f.fade.w <= 0.0) { return 0.0; }
        float t = clamp((depth - f.fade.x) / max(f.fade.y - f.fade.x, 1e-6), 0.0, 1.0);
        if (t <= 0.0) { return 0.0; }
        return pow(t, max(f.fade.z, 0.05)) * f.fade.w;
    }

    static bool off_screen(float4 c) {
        return c.w <= 1e-3 || abs(c.x) > c.w || abs(c.y) > c.w;
    }

    // a bundle with an end off the screen: full strength up to bundles.w
    // points long, then dimmer in proportion (a fixed strength for its
    // length, never a fade over time); behind the eye, the dimmest
    static float long_dim(float4 a, float4 b, constant Frame& f) {
        if (!off_screen(a) && !off_screen(b)) { return 1.0; }
        if (a.w <= 1e-3 || b.w <= 1e-3) { return 0.12; }
        float2 half_screen = f.screen.xy * 0.5;
        float2 sa = a.xy / a.w * half_screen;
        float2 sb = b.xy / b.w * half_screen;
        float len = length(sb - sa);
        return clamp(f.bundles.w / max(len, 1e-3), 0.12, 1.0);
    }

    // MARK: the GPU layout

    kernel void mil_layout(uint tid [[thread_position_in_grid]],
                           const device uint4* jobs [[buffer(0)]],
                           device ushort4* packed [[buffer(1)]],
                           const device ushort4* seed [[buffer(2)]],
                           const device LeafBox* boxes [[buffer(3)]],
                           const device uint* adjacencyStart [[buffer(4)]],
                           const device uint* adjacency [[buffer(5)]],
                           constant float4& params [[buffer(6)]],
                           constant uint2& count [[buffer(7)]]) {
        if (tid >= count.y) { return; }
        // the job holding this thread: the last whose first thread is <= tid
        uint lo = 0u;
        uint hi = count.x;
        while (hi - lo > 1u) {
            uint mid = (lo + hi) / 2u;
            if (jobs[mid].w <= tid) { lo = mid; } else { hi = mid; }
        }
        uint4 job = jobs[lo];
        uint at = tid - job.w;
        if (at >= job.y) { return; }
        uint s = job.x + at;
        LeafBox b = boxes[job.z];
        ushort4 q = packed[s];
        float3 p = unpack_position(q, b);
        float3 home = unpack_position(seed[s], b);
        uint a0 = adjacencyStart[s];
        uint a1 = min(adjacencyStart[s + 1u], a0 + 32u);
        float3 sum = float3(0.0);
        float n = 0.0;
        for (uint k = a0; k < a1; k++) {
            ushort4 other = packed[adjacency[k]];
            sum += unpack_position(other, boxes[other.w]);
            n += 1.0;
        }
        float3 next = p;
        if (n > 0.0) { next += (sum / n - p) * params.x; }
        next += (home - p) * params.y;
        float3 off = next - home;
        float reach = length(off);
        if (reach > params.z) { next = home + off * (params.z / reach); }
        float3 top = b.lo.xyz + b.extent.xyz;
        next = clamp(next, b.lo.xyz, top);
        float3 t = (next - b.lo.xyz) / max(b.extent.xyz, float3(1e-9)) * 65535.0;
        t = clamp(rint(t), float3(0.0), float3(65535.0));
        packed[s] = ushort4(ushort(t.x), ushort(t.y), ushort(t.z), q.w);
    }

    // MARK: bodies

    static NodeOut hidden_node() {
        NodeOut o;
        o.position = float4(0.0, 0.0, -2.0, 1.0);
        o.colour = float4(0.0);
        o.uv = float2(0.0);
        o.pixels = 0.0;
        o.ring = 0.0;
        o.detail = 0.0;
        o.fade = 0.0;
        o.dim = 0.0;
        return o;
    }

    static NodeOut quad(float4 clip, float pixels, uint vid, float3 colour, constant Frame& f) {
        NodeOut o = hidden_node();
        float2 c = corner(vid);
        float4 moved = clip;
        moved.xy += c * (pixels * 2.0 / f.screen.xy) * clip.w;
        o.position = moved;
        o.colour = float4(colour, 1.0);
        o.uv = c;
        o.pixels = pixels * f.screen.w;
        return o;
    }

    vertex NodeOut mil_node_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                   constant Frame& f [[buffer(0)]],
                                   const device ushort4* packed [[buffer(1)]],
                                   const device uint* looks [[buffer(2)]],
                                   const device LeafBox* boxes [[buffer(3)]],
                                   const device float4* standIn [[buffer(4)]],
                                   const device uint2* draw [[buffer(5)]],
                                   constant uint& drawCount [[buffer(6)]],
                                   const device float* leafDetail [[buffer(15)]]) {
        uint k = find_leaf(draw, drawCount, iid);
        uint leaf = draw[k].x;
        uint first = as_type<uint>(boxes[leaf].lo.w);
        uint slot = first + (iid - draw[k].y);
        ushort4 q = packed[slot];
        float4 stand = standIn[leaf];
        float open = leaf_open(stand.w);
        float detail = clamp(leafDetail[leaf], 0.0, 1.0);
        float3 p = mix(stand.xyz, unpack_position(q, boxes[leaf]), open);
        float4 look = unpack_unorm4x8_to_float(looks[slot]);
        float4 clip = f.viewProj * float4(p, 1.0);
        float depth = max(clip.w, 1e-3);
        float fade = fade_at(depth, f);
        // past the band's end: gone, so not drawn at all
        if (fade >= 0.999) { return hidden_node(); }
        // smaller as its detail drops (D1), all times the leaf's morph
        float shrink = 0.7 + 0.3 * detail;
        float pixels = look.w * 2.55 * open * shrink * f.screen.z / depth;
        pixels = clamp(pixels, f.look.x * open, f.pick.y);
        NodeOut o = quad(clip, pixels, vid, look.rgb, f);
        o.detail = detail;
        o.fade = fade;
        o.dim = f.focus.z;
        return o;
    }

    // the chosen note: at its own place whatever its leaf shows, unfaded,
    // bigger, with a ring
    vertex NodeOut mil_chosen_vertex(uint vid [[vertex_id]],
                                     constant Frame& f [[buffer(0)]],
                                     const device ushort4* packed [[buffer(1)]],
                                     const device uint* looks [[buffer(2)]],
                                     const device LeafBox* boxes [[buffer(3)]]) {
        uint slot = uint(max(f.pick.x, 0.0));
        ushort4 q = packed[slot];
        float3 p = unpack_position(q, boxes[uint(q.w)]);
        float4 look = unpack_unorm4x8_to_float(looks[slot]);
        float4 clip = f.viewProj * float4(p, 1.0);
        if (clip.w <= 1e-3) { return hidden_node(); }
        float pixels = clamp(look.w * 2.55 * f.screen.z / clip.w * 1.3, 3.5, f.pick.y);
        pixels = max(pixels * 1.35, 7.0);
        NodeOut o = quad(clip, pixels, vid, look.rgb, f);
        o.ring = 1.0;
        o.detail = 1.0;
        return o;
    }

    fragment float4 mil_node_fragment(NodeOut in [[stage_in]], constant Frame& f [[buffer(0)]]) {
        float d2 = dot(in.uv, in.uv);
        if (d2 > 1.0) { discard_fragment(); }
        // shading grows with the pixels a body covers and its detail: a
        // flat dot under two, a lit ball by eight, a rim of light by twenty
        float lit = smoothstep(2.0, 8.0, in.pixels) * smoothstep(0.0, 1.0, in.detail);
        float rim = smoothstep(8.0, 20.0, in.pixels) * smoothstep(0.5, 1.0, in.detail);
        float3 n = float3(in.uv.x, -in.uv.y, sqrt(max(1.0 - d2, 0.0)));
        float3 l = normalize(float3(-0.45, 0.55, 0.7));
        float diffuse = 0.42 + 0.58 * max(dot(n, l), 0.0);
        float edge = pow(1.0 - n.z, 3.0) * 0.5 * rim;
        float3 colour = in.colour.rgb * mix(1.0, diffuse, lit) + float3(edge);
        // the depth fade, then the step back while another note is chosen
        colour = mix(colour, f.sky.rgb, in.fade);
        colour = mix(colour, f.sky.rgb, in.dim);
        if (in.ring > 0.0 && d2 > 0.62) { colour = float3(0.94); }
        return float4(min(colour, float3(0.94)), 1.0);
    }

    // MARK: the chosen note's neighbourhood

    // a neighbour's slot, and its link's growth (0...1) as it reaches it
    static uint neighbour(uint iid, constant Frame& f, const device uint* adjacencyStart,
                          const device uint* adjacency) {
        uint chosen = uint(max(f.pick.x, 0.0));
        return adjacency[adjacencyStart[chosen] + iid];
    }

    static float link_tip(float3 a, float3 b, constant Frame& f) {
        float len = length(b - a);
        if (len <= 1e-6) { return f.focus.x > 0.0 ? 1.0 : 0.0; }
        return clamp(f.focus.x * f.focus.y / len, 0.0, 1.0);
    }

    vertex LinkOut mil_focus_link_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                         constant Frame& f [[buffer(0)]],
                                         const device ushort4* packed [[buffer(1)]],
                                         const device uint* looks [[buffer(2)]],
                                         const device LeafBox* boxes [[buffer(3)]],
                                         const device uint* adjacencyStart [[buffer(7)]],
                                         const device uint* adjacency [[buffer(8)]]) {
        LinkOut o;
        o.position = float4(0.0, 0.0, -2.0, 1.0);
        o.colour = float4(0.0);
        o.across = 0.0;
        o.half_width = 1.0;
        uint chosen = uint(max(f.pick.x, 0.0));
        uint other = neighbour(iid, f, adjacencyStart, adjacency);
        ushort4 qa = packed[chosen];
        ushort4 qb = packed[other];
        float3 a = unpack_position(qa, boxes[uint(qa.w)]);
        float3 b = unpack_position(qb, boxes[uint(qb.w)]);
        float tip = link_tip(a, b, f);
        if (tip <= 0.0) { return o; }
        float3 e = mix(a, b, tip);
        float4 ca = f.viewProj * float4(a, 1.0);
        float4 cb = f.viewProj * float4(e, 1.0);
        if (ca.w <= 1e-3 || cb.w <= 1e-3) { return o; }
        float2 half_screen = f.screen.xy * 0.5;
        float2 sa = ca.xy / ca.w * half_screen;
        float2 sb = cb.xy / cb.w * half_screen;
        float2 along = sb - sa;
        float len = length(along);
        float2 dir = len > 1e-4 ? along / len : float2(1.0, 0.0);
        float2 nrm = float2(-dir.y, dir.x);
        bool atB = (vid & 2u) != 0u;
        float side = (vid & 1u) != 0u ? 1.0 : -1.0;
        // half its width and a pixel more for the smooth edge (points)
        float half_width = f.focus.w * 0.5;
        float reach = half_width + 1.0 / max(f.screen.w, 1.0);
        float4 c = atB ? cb : ca;
        c.xy += nrm * side * (reach / half_screen) * c.w;
        float3 ka = unpack_unorm4x8_to_float(looks[chosen]).rgb;
        float3 kb = unpack_unorm4x8_to_float(looks[other]).rgb;
        o.position = c;
        o.colour = float4(atB ? mix(ka, kb, tip) : ka, 1.0);
        o.across = side * reach;
        o.half_width = half_width;
        return o;
    }

    fragment float4 mil_focus_link_fragment(LinkOut in [[stage_in]], constant Frame& f [[buffer(0)]]) {
        // a smooth edge a pixel wide; premultiplied
        float px = 1.0 / max(f.screen.w, 1.0);
        float a = clamp((in.half_width + px * 0.5 - abs(in.across)) / px, 0.0, 1.0) * 0.9;
        float3 colour = min(in.colour.rgb * 1.1, float3(0.94));
        return float4(colour * a, a);
    }

    vertex NodeOut mil_focus_node_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                         constant Frame& f [[buffer(0)]],
                                         const device ushort4* packed [[buffer(1)]],
                                         const device uint* looks [[buffer(2)]],
                                         const device LeafBox* boxes [[buffer(3)]],
                                         const device uint* adjacencyStart [[buffer(7)]],
                                         const device uint* adjacency [[buffer(8)]]) {
        uint chosen = uint(max(f.pick.x, 0.0));
        uint other = neighbour(iid, f, adjacencyStart, adjacency);
        ushort4 qa = packed[chosen];
        ushort4 qb = packed[other];
        float3 a = unpack_position(qa, boxes[uint(qa.w)]);
        float3 b = unpack_position(qb, boxes[uint(qb.w)]);
        // it grows in as its link arrives (the link's last 15%)
        float arrived = smoothstep(0.85, 1.0, link_tip(a, b, f));
        if (arrived <= 0.0) { return hidden_node(); }
        float4 look = unpack_unorm4x8_to_float(looks[other]);
        float4 clip = f.viewProj * float4(b, 1.0);
        if (clip.w <= 1e-3) { return hidden_node(); }
        float pixels = clamp(look.w * 2.55 * f.screen.z / clip.w * 1.3, 3.5, f.pick.y) * arrived;
        NodeOut o = quad(clip, pixels, vid, look.rgb, f);
        o.detail = 1.0;
        return o;
    }

    // MARK: bundles

    vertex LineOut mil_bundle_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                     constant Frame& f [[buffer(0)]],
                                     const device uint2* ends [[buffer(9)]],
                                     const device float* weights [[buffer(10)]],
                                     const device float4* cells [[buffer(11)]],
                                     const device uint* colours [[buffer(12)]],
                                     const device float* overlap [[buffer(14)]]) {
        LineOut o;
        o.position = float4(0.0, 0.0, -2.0, 1.0);
        o.colour = float4(0.0);
        uint2 e = ends[iid];
        float4 a = cells[e.x];
        float4 b = cells[e.y];
        float closed = min(a.w, b.w);
        float4 ca = f.viewProj * float4(a.xyz, 1.0);
        float4 cb = f.viewProj * float4(b.xyz, 1.0);
        if (closed <= 0.0 || ca.w <= 1e-3 || cb.w <= 1e-3) { return o; }
        // past the budget's count the next few narrow away (never a fade)
        float kept = clamp((f.bundles.x + f.bundles.y - float(iid)) / max(f.bundles.y, 1.0), 0.0, 1.0);
        // wider for more links, but never past the cap (bundles.z, points): a
        // bundle of thousands is a line, not a band across the screen
        float width = min(f.look.w * (0.5 + 0.3 * log2(1.0 + weights[iid])), f.bundles.z) * closed * kept;
        if (width <= 0.0) { return o; }
        float2 half_screen = f.screen.xy * 0.5;
        float2 sa = ca.xy / ca.w * half_screen;
        float2 sb = cb.xy / cb.w * half_screen;
        float2 along = sb - sa;
        float len = length(along);
        float2 dir = len > 1e-4 ? along / len : float2(1.0, 0.0);
        float2 n = float2(-dir.y, dir.x);
        bool atB = (vid & 2u) != 0u;
        float side = (vid & 1u) != 0u ? 1.0 : -1.0;
        float4 c = atB ? cb : ca;
        c.xy += n * side * (width / f.screen.xy) * c.w;
        float3 ka = unpack_unorm4x8_to_float(colours[e.x]).rgb;
        float3 kb = unpack_unorm4x8_to_float(colours[e.y]).rgb;
        o.position = c;
        // each bundle's share of the light where many meet (1/sqrt of how
        // many), dimmer when it runs off the screen, fading to nothing with
        // depth, and stepping back while a note is chosen
        float share = min(overlap[e.x], overlap[e.y]);
        float deep = 1.0 - fade_at(max(c.w, 1e-3), f);
        float strength = f.look.z * share * long_dim(ca, cb, f) * deep * (1.0 - f.focus.z);
        o.colour = float4((atB ? kb : ka) * strength, 0.0);
        return o;
    }

    fragment float4 mil_line_fragment(LineOut in [[stage_in]]) {
        return in.colour;
    }

    // MARK: summary points

    vertex GlowOut mil_summary_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                      constant Frame& f [[buffer(0)]],
                                      const device float4* sums [[buffer(13)]]) {
        GlowOut o;
        o.position = float4(0.0, 0.0, -2.0, 1.0);
        o.colour = float4(0.0);
        o.uv = float2(0.0);
        float4 a = sums[2u * iid];
        float4 b = sums[2u * iid + 1u];
        float scale = b.z;
        float4 clip = f.viewProj * float4(a.xyz, 1.0);
        float depth = max(clip.w, 1e-3);
        // additive light fades to nothing with depth: times 1 - f
        float deep = 1.0 - fade_at(depth, f);
        if (deep <= 0.001) { return o; }
        float pixels = max(a.w * f.screen.z / depth, f.look.y) * scale;
        // never wider than a fifth of the screen: a cluster close by opens
        // into notes, and a huge soft disc is only fill
        pixels = min(pixels, 0.2 * min(f.screen.x, f.screen.y));
        float2 c = corner(vid);
        float4 moved = clip;
        moved.xy += c * (pixels * 2.0 / f.screen.xy) * clip.w;
        float3 colour = unpack_unorm4x8_to_float(as_type<uint>(b.x)).rgb;
        o.position = moved;
        o.colour = float4(colour * (b.y * 0.55 * f.pick.z * deep * (1.0 - f.focus.z)), 0.0);
        o.uv = c;
        return o;
    }

    fragment float4 mil_summary_fragment(GlowOut in [[stage_in]]) {
        float d2 = dot(in.uv, in.uv);
        if (d2 > 1.0) { discard_fragment(); }
        // a bright core in a soft halo: the shape of the point, the same at every size
        float glow = exp(-4.0 * d2) * (1.0 - d2) + 0.6 * exp(-26.0 * d2);
        return float4(in.colour.rgb * glow, 0.0);
    }

    // MARK: tone mapping and measuring

    struct ResolveOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex ResolveOut mil_resolve_vertex(uint vid [[vertex_id]]) {
        ResolveOut o;
        float x = (vid == 1u) ? 3.0 : -1.0;
        float y = (vid == 2u) ? 3.0 : -1.0;
        o.position = float4(x, y, 0.0, 1.0);
        o.uv = float2(x * 0.5 + 0.5, 0.5 - y * 0.5);
        return o;
    }

    fragment float4 mil_resolve_fragment(ResolveOut in [[stage_in]],
                                         texture2d<float> light [[texture(0)]],
                                         constant float4& tone [[buffer(0)]]) {
        // the light is smaller than the screen: filtered up
        constexpr sampler soft(filter::linear, address::clamp_to_edge);
        float3 x = light.sample(soft, in.uv).rgb;
        float3 t = 1.0 - exp(-tone.x * max(x, float3(0.0)));
        return float4(tone.yzw + (1.0 - tone.yzw) * t, 1.0);
    }

    kernel void mil_measure(uint2 gid [[thread_position_in_grid]],
                            texture2d<float, access::read> light [[texture(0)]],
                            texture2d<float, access::read> screen [[texture(1)]],
                            device float2* samples [[buffer(0)]]) {
        if (gid.x >= 64u || gid.y >= 64u) { return; }
        float w = float(light.get_width());
        float h = float(light.get_height());
        uint2 at = uint2(uint((float(gid.x) + 0.5) / 64.0 * w), uint((float(gid.y) + 0.5) / 64.0 * h));
        at = min(at, uint2(light.get_width() - 1u, light.get_height() - 1u));
        float sw = float(screen.get_width());
        float sh = float(screen.get_height());
        uint2 shown_at = uint2(uint((float(gid.x) + 0.5) / 64.0 * sw), uint((float(gid.y) + 0.5) / 64.0 * sh));
        shown_at = min(shown_at, uint2(screen.get_width() - 1u, screen.get_height() - 1u));
        float3 weights = float3(0.2126, 0.7152, 0.0722);
        samples[gid.y * 64u + gid.x] = float2(dot(light.read(at).rgb, weights),
                                              dot(screen.read(shown_at).rgb, weights));
    }
    """#
}
