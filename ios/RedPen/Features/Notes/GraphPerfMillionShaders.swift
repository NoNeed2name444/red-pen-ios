// The million map's shaders, as Metal source compiled at run time
// (MTLDevice.makeLibrary(source:)), like GraphPerfShaders: Swift
// Playgrounds cannot compile .metal files. Foundation only, so the tests and
// tools/shader_check.py hold the names, slots and frame layout.
//
//   mil_layout          the GPU layout, a compute pass over the leaves being
//                       prepared: each body moves a little towards its
//                       neighbours and back towards its seed, never more
//                       than a third of a spacing from it nor out of its
//                       leaf's box, and is written back as 16-bit numbers
//   mil_node_vertex     one quad per body of every leaf drawn body by body,
//                       found from the instance by a binary search of the
//                       drawn leaves; placed and sized by its leaf's morph
//                       (it moves out of the leaf's summary point and grows
//                       as the leaf opens); shading and the lit ball grow
//                       with the pixels it covers, a plain dot below two
//   mil_chosen_vertex   the chosen body again, over everything, with a ring
//   mil_link_vertex     the selected note's own links only (none by
//                       default: GraphPerfLinkFocus), read from its leaf's
//                       link pages (1,024 a page); each end where its leaf
//                       shows it, so a link into a closed leaf ends at its
//                       summary point
//   mil_bundle_vertex   one faint band per bundle (the strongest 300 at most)
//                       between two cut cells, as wide as
//                       the log of the links it carries times the share of
//                       both ends still closed: it narrows to nothing as the
//                       links take over, never fades
//   mil_summary_vertex  one soft disc per summary point: brightness from how
//                       many it stands for, colour their mix, its radius and
//                       its floor both times its morph scale
//
// The frame's numbers are six float4s after the matrix (Frame below):
//   eye      xyz, w time
//   screen   width, height (points), focal length (points), pixels per point
//   look     body floor (points), summary floor (points), link alpha, bundle width (points)
//   pick     chosen slot (-1 none), largest body (points), bundle alpha, glow strength
//   fog      depth where links start to fade, where they are faintest, bundle width cap (points),
//            reach (points) past which a link or bundle running off the screen dims
//
// Light (links, bundles, glows) adds up in an rgba16Float picture; the
// resolve pass tone-maps it onto the screen (1 - exp(-k x), k from the
// picture's own 97th percentile, GraphPerfExposure) and the notes are drawn
// over it in their own colours, so dense light reads as structure, never a
// white fill, and notes stay shapes.
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
        static let pool = 7
        static let pages = 8
        static let bundleEnds = 9
        static let bundleWeights = 10
        static let bundleCells = 11
        static let cutColours = 12
        static let summaries = 13
        /// Per bundle cut cell: 1/sqrt(the bundles meeting there).
        static let cutWeights = 14
        /// Per leaf, 1 when its links are drawn one by one (GraphPerfLinkFocus).
        static let linkLeaves = 15
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

    /// The layout kernel's slots.
    enum LayoutSlot {
        static let job = 0
        static let packed = 1
        static let seed = 2
        static let boxes = 3
        static let adjacencyStart = 4
        static let adjacency = 5
        static let params = 6
    }

    /// Links a page holds; an unused entry is `emptyEntry` (folded away).
    static let pageSize = 1024
    static let emptyEntry: UInt32 = 0xFFFF_FFFF
    /// How far a body may move from its seed, in spacings, and per step
    /// towards its neighbours and back to its seed.
    static let layoutReach: Float = 0.3
    static let layoutPull: Float = 0.12
    static let layoutAnchor: Float = 0.1
    /// Steps a leaf is laid out when it is prepared.
    static let layoutSteps = 10
    /// The frame struct's size in floats: the matrix and five float4s.
    static let frameFloats = 36

    static let functions: [String] = [
        "mil_layout", "mil_node_vertex", "mil_chosen_vertex", "mil_node_fragment", "mil_link_vertex",
        "mil_line_fragment", "mil_bundle_vertex", "mil_summary_vertex", "mil_summary_fragment",
        "mil_resolve_vertex", "mil_resolve_fragment", "mil_measure"
    ]

    /// The frame's numbers, in Frame's order.
    /// The widest a bundle is drawn (points, before Bold).
    static let bundleWidthCap: Float = 2.5
    /// At most this many bundles, the strongest: groups, not a web.
    static let bundleCap = 300
    /// The light is drawn at this share of the screen's pixels a side (a
    /// quarter of the pixels), then filtered up by the resolve: glows and
    /// bands are soft anyway, and it is most of the GPU's fill.
    static let lightScale: Float = 0.5
    /// A link or bundle with an end off the screen is drawn at full
    /// strength up to this share of the screen's shorter side long, dimmer
    /// in proportion beyond it (never under `longFloor`): close in, the
    /// neighbourhood shows, not every ray leaving it.
    static let longReach: Float = 0.35
    static let longFloor: Float = 0.12

    static func frame(camera cam: GraphPerfCamera, width: Float, height: Float, near: Float, far: Float,
                      centre: SIMD3<Float>, radius: Float, tier: GraphPerfTier, bold: Bool, chosenSlot: Int?,
                      pixelsPerPoint: Float, time: Float) -> [SIMD4<Float>] {
        let projection = cam.projectionMatrix(aspect: width / max(height, 1), near: near, far: far)
        let viewProj = projection * cam.viewMatrix()
        let eye = cam.eye
        let base: Float = tier.linkBase * (bold ? 1.5 : 1)
        let toCentre = max(((centre - eye) * cam.forward).sum(), 0)
        return [
            viewProj.c0, viewProj.c1, viewProj.c2, viewProj.c3,
            SIMD4(eye.x, eye.y, eye.z, time),
            SIMD4(width, height, cam.focal(viewHeight: height), pixelsPerPoint),
            SIMD4(GraphPerfLOD.noteClamp.lowerBound, 1.6, base, bold ? 3 : 2.2),
            SIMD4(Float(chosenSlot ?? -1), GraphPerfLOD.hubClamp.upperBound, min(base * 0.8, 0.3), tier == .saver ? 0.7 : 1),
            SIMD4(toCentre, toCentre + 2 * radius, bundleWidthCap * (bold ? 1.4 : 1),
                  longReach * min(width, height))
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
        float4 fog;
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

    static float3 shown(float3 p, float4 stand) {
        return mix(stand.xyz, p, leaf_open(stand.w));
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

    static float link_fog(float depth, constant Frame& f) {
        return mix(1.0, 0.35, smoothstep(f.fog.x, f.fog.y, depth));
    }

    static bool off_screen(float4 c) {
        return c.w <= 1e-3 || abs(c.x) > c.w || abs(c.y) > c.w;
    }

    // a line with an end off the screen: full strength up to fog.w points
    // long, then dimmer in proportion (a fixed strength for its length,
    // never a fade over time); behind the eye, the dimmest
    static float long_dim(float4 a, float4 b, constant Frame& f) {
        if (!off_screen(a) && !off_screen(b)) { return 1.0; }
        if (a.w <= 1e-3 || b.w <= 1e-3) { return 0.12; }
        float2 half_screen = f.screen.xy * 0.5;
        float2 sa = a.xy / a.w * half_screen;
        float2 sb = b.xy / b.w * half_screen;
        float len = length(sb - sa);
        return clamp(f.fog.w / max(len, 1e-3), 0.12, 1.0);
    }

    // MARK: the GPU layout

    kernel void mil_layout(uint tid [[thread_position_in_grid]],
                           constant uint4& job [[buffer(0)]],
                           device ushort4* packed [[buffer(1)]],
                           const device ushort4* seed [[buffer(2)]],
                           const device LeafBox* boxes [[buffer(3)]],
                           const device uint* adjacencyStart [[buffer(4)]],
                           const device uint* adjacency [[buffer(5)]],
                           constant float4& params [[buffer(6)]]) {
        if (tid >= job.y) { return; }
        uint s = job.x + tid;
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

    static NodeOut node_out(uint slot, uint vid, float ring, constant Frame& f,
                            const device ushort4* packed, const device uint* looks,
                            const device LeafBox* boxes, const device float4* standIn) {
        NodeOut o;
        ushort4 q = packed[slot];
        uint leaf = uint(q.w);
        float4 stand = standIn[leaf];
        float open = leaf_open(stand.w);
        if (ring > 0.0) { open = max(open, 1.0); }
        float3 p = mix(stand.xyz, unpack_position(q, boxes[leaf]), open);
        float4 look = unpack_unorm4x8_to_float(looks[slot]);
        float radius = look.w * 2.55 * open;
        float4 clip = f.viewProj * float4(p, 1.0);
        float depth = max(clip.w, 1e-3);
        float pixels = radius * f.screen.z / depth;
        pixels = clamp(pixels, f.look.x * open, f.pick.y);
        if (ring > 0.0) { pixels = max(pixels * 1.35, 7.0); }
        float2 c = corner(vid);
        float4 moved = clip;
        moved.xy += c * (pixels * 2.0 / f.screen.xy) * clip.w;
        o.position = moved;
        o.colour = float4(look.rgb, 1.0);
        o.uv = c;
        o.pixels = pixels * f.screen.w;
        o.ring = ring;
        return o;
    }

    vertex NodeOut mil_node_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                   constant Frame& f [[buffer(0)]],
                                   const device ushort4* packed [[buffer(1)]],
                                   const device uint* looks [[buffer(2)]],
                                   const device LeafBox* boxes [[buffer(3)]],
                                   const device float4* standIn [[buffer(4)]],
                                   const device uint2* draw [[buffer(5)]],
                                   constant uint& drawCount [[buffer(6)]]) {
        uint k = find_leaf(draw, drawCount, iid);
        uint leaf = draw[k].x;
        uint first = as_type<uint>(boxes[leaf].lo.w);
        uint slot = first + (iid - draw[k].y);
        return node_out(slot, vid, 0.0, f, packed, looks, boxes, standIn);
    }

    vertex NodeOut mil_chosen_vertex(uint vid [[vertex_id]],
                                     constant Frame& f [[buffer(0)]],
                                     const device ushort4* packed [[buffer(1)]],
                                     const device uint* looks [[buffer(2)]],
                                     const device LeafBox* boxes [[buffer(3)]],
                                     const device float4* standIn [[buffer(4)]]) {
        uint slot = uint(max(f.pick.x, 0.0));
        return node_out(slot, vid, 1.0, f, packed, looks, boxes, standIn);
    }

    fragment float4 mil_node_fragment(NodeOut in [[stage_in]]) {
        float d2 = dot(in.uv, in.uv);
        if (d2 > 1.0) { discard_fragment(); }
        // shading grows with the pixels a body covers: a flat dot under
        // two, a lit ball by eight, a rim of light by twenty
        float lit = smoothstep(2.0, 8.0, in.pixels);
        float rim = smoothstep(8.0, 20.0, in.pixels);
        float3 n = float3(in.uv.x, -in.uv.y, sqrt(max(1.0 - d2, 0.0)));
        float3 l = normalize(float3(-0.45, 0.55, 0.7));
        float diffuse = 0.42 + 0.58 * max(dot(n, l), 0.0);
        float edge = pow(1.0 - n.z, 3.0) * 0.5 * rim;
        float3 colour = in.colour.rgb * mix(1.0, diffuse, lit) + float3(edge);
        if (in.ring > 0.0 && d2 > 0.62) { colour = float3(1.0); }
        return float4(colour, 1.0);
    }

    // MARK: links and bundles

    vertex LineOut mil_link_vertex(uint vid [[vertex_id]],
                                   constant Frame& f [[buffer(0)]],
                                   const device ushort4* packed [[buffer(1)]],
                                   const device uint* looks [[buffer(2)]],
                                   const device LeafBox* boxes [[buffer(3)]],
                                   const device float4* standIn [[buffer(4)]],
                                   const device uint2* pool [[buffer(7)]],
                                   const device uint* pages [[buffer(8)]],
                                   const device uchar* shownLinks [[buffer(15)]]) {
        LineOut o;
        uint e = vid >> 1u;
        uint page = pages[e >> 10u];
        uint2 pair = pool[page * 1024u + (e & 1023u)];
        // off the clip volume: nothing drawn
        o.position = float4(0.0, 0.0, -2.0, 1.0);
        o.colour = float4(0.0);
        if (pair.x == 0xFFFFFFFFu) { return o; }
        // the selected note's own links only: its neighbourhood (a link
        // inside one leaf is kept once, so the note may be either end)
        if (f.pick.x >= 0.0 && pair.x != uint(f.pick.x) && pair.y != uint(f.pick.x)) { return o; }
        ushort4 qh = packed[pair.x];
        ushort4 qo = packed[pair.y];
        float4 sh = standIn[uint(qh.w)];
        float4 so = standIn[uint(qo.w)];
        // both leaves' links drawn: the lower leaf's copy draws it
        if (shownLinks[uint(qo.w)] != 0u && qo.w < qh.w) { return o; }
        bool home = (vid & 1u) == 0u;
        float4 ch = f.viewProj * float4(shown(unpack_position(qh, boxes[uint(qh.w)]), sh), 1.0);
        float4 co = f.viewProj * float4(shown(unpack_position(qo, boxes[uint(qo.w)]), so), 1.0);
        float4 clip = home ? ch : co;
        uint slot = home ? pair.x : pair.y;
        float4 look = unpack_unorm4x8_to_float(looks[slot]);
        o.position = clip;
        o.colour = float4(look.rgb * (f.look.z * link_fog(clip.w, f) * long_dim(ch, co, f)), 0.0);
        return o;
    }

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
        // wider for more links, but never past the cap (fog.z, points): a
        // bundle of thousands is a line, not a band across the screen
        float width = min(f.look.w * (0.5 + 0.3 * log2(1.0 + weights[iid])), f.fog.z) * closed;
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
        // many), and dimmer when it runs off the screen
        float share = min(overlap[e.x], overlap[e.y]);
        o.colour = float4((atB ? kb : ka) * (f.pick.z * share * link_fog(c.w, f) * long_dim(ca, cb, f)), 0.0);
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
        float4 a = sums[2u * iid];
        float4 b = sums[2u * iid + 1u];
        float scale = b.z;
        float4 clip = f.viewProj * float4(a.xyz, 1.0);
        float depth = max(clip.w, 1e-3);
        float pixels = max(a.w * f.screen.z / depth, f.look.y) * scale;
        // never wider than a fifth of the screen: a cluster close by opens
        // into notes, and a huge soft disc is only fill
        pixels = min(pixels, 0.2 * min(f.screen.x, f.screen.y));
        float2 c = corner(vid);
        float4 moved = clip;
        moved.xy += c * (pixels * 2.0 / f.screen.xy) * clip.w;
        float3 colour = unpack_unorm4x8_to_float(as_type<uint>(b.x)).rgb;
        o.position = moved;
        o.colour = float4(colour * (b.y * 0.55 * f.pick.w), 0.0);
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
