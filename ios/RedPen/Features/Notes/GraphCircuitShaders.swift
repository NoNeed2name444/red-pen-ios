import Foundation

// The Circuit theme's shader modifiers (GraphCircuitLook builds the materials
// and checks they compile; GraphCircuit plans what they dress).
//
// The look is a tidy circuit of light: each collection a floating tile of
// dark smoked glass, its rim lit faintly in the collection's own hue; thin
// ice-blue light guides etched into it (the trunk heaviest, branches
// lighter, the return rails thinnest, in indigo); rings of light for
// pages, amber glass capsules for ideas, violet prisms for loose notes;
// chips in dark titanium packages with a smoked-glass lid and a faint die
// under it. The links between notes are etched a layer apart, violet and
// almost invisible until one of their notes is chosen.
//
// Current is one pulse of light a beat (every 6 s): every guide knows how
// far along the circuit from its source the light has come at each point
// (the texture coordinate's distance along, plus the route's phase), and
// every part and glow its own distance (`rpDist`), so one packet - a bright
// head with a short comet tail - runs coherently through every joint, and
// each ring and capsule flashes as it passes, with no ticker on the CPU.
//
// They follow the other themes' rules (GraphStyleShaders): constant
// lighting, the final colour written to `_surface.diffuse`, designed as it
// shows on screen and taken into linear space at the end; the light is the
// shaders' own (a lamp up and to the left, in view space), so nothing
// depends on the scene's lights; time is `rpClock` times `rpMotion` (0 with
// Reduce Motion: no packets, no flashes, the circuit rests fully lit);
// `rpProbe` is added at the end so a modifier that fails to compile is
// caught; no helper functions. `rpDetail` 0 (the Smooth budget) drops the
// glass sheen, the die's grids and the lid's reflection band.
//
// A tile's and a part's shader reads where it is drawn in its own frame
// from the node's model-view axes (every node is scaled evenly), y up out
// of the glass.

nonisolated enum CircuitShaders {
    // MARK: the glass tiles

    /// A collection's tile, on a rounded slab whose own y is up; `rpSize`
    /// is half the slab, `rpCorner` its corner radius in plan. Tint A the
    /// glass, B the rim light (the collection's hue), C the bevel's
    /// highlight.
    static let board: String = """
    #pragma arguments
    float rpProbe;
    float rpDetail;
    float rpCorner;
    float3 rpSize;
    float3 rpTintA;
    float3 rpTintB;
    float3 rpTintC;

    #pragma body
    float3 rp_N = normalize(_surface.normal);
    float3 rp_V = normalize(_surface.view);
    float4x4 rp_mv = scn_node.modelViewTransform;
    float3 rp_ax = rp_mv[0].xyz;
    float3 rp_ay = rp_mv[1].xyz;
    float3 rp_az = rp_mv[2].xyz;
    float rp_s2 = max(dot(rp_ax, rp_ax), 0.000001);
    float3 rp_rel = _surface.position - rp_mv[3].xyz;
    float3 rp_lp = float3(dot(rp_rel, rp_ax), dot(rp_rel, rp_ay), dot(rp_rel, rp_az)) / rp_s2;
    float rp_ny = dot(rp_N, normalize(rp_ay));
    float rp_top = smoothstep(0.93, 0.985, rp_ny);
    float rp_wall = 1.0 - smoothstep(0.25, 0.5, rp_ny);

    float rp_qx = abs(rp_lp.x) - (rpSize.x - rpCorner);
    float rp_qz = abs(rp_lp.z) - (rpSize.z - rpCorner);
    float rp_qo = length(float2(max(rp_qx, 0.0), max(rp_qz, 0.0)));
    float rp_out = rp_qo + min(max(rp_qx, rp_qz), 0.0) - rpCorner;
    float rp_in = max(-rp_out, 0.0);

    float rp_back = clamp(0.5 - 0.5 * rp_lp.z / max(rpSize.z, 0.001), 0.0, 1.0);
    float3 rp_col = rpTintA * (0.8 + 0.45 * rp_back);
    float rp_edge = exp(-rp_in / 0.07);
    rp_col = rp_col + rpTintB * (rp_edge * 0.16);
    float rp_hl = abs(rp_in - 0.045) / 0.004;
    rp_col = rp_col + rpTintC * (exp(-rp_hl * rp_hl) * 0.10);

    float3 rp_L = normalize(float3(-0.35, 0.65, 0.68));
    float3 rp_R = rp_V - rp_N * (2.0 * dot(rp_N, rp_V));
    float rp_sheen = pow(max(dot(-rp_R, rp_L), 0.0), 6.0);
    float rp_mu = clamp(dot(rp_N, rp_V), 0.0, 1.0);
    float rp_fr = pow(1.0 - rp_mu, 5.0);
    float rp_gl = 0.05 * rp_sheen * rpDetail + 0.18 * rp_fr;
    rp_col = rp_col + float3(0.55, 0.62, 0.75) * (rp_gl * rp_top);

    float rp_nl = max(dot(rp_N, rp_L), 0.0);
    float3 rp_bevel = rpTintC * (0.18 + 0.55 * pow(rp_nl, 3.0)) + rpTintB * 0.08;
    float3 rp_side = rpTintA * 0.5 + rpTintB * 0.22;
    float3 rp_rim = mix(rp_bevel, rp_side, rp_wall);
    rp_col = mix(rp_rim, rp_col, rp_top);

    """ + GraphStyleShaders.glowEnd

    // MARK: the light guides

    /// Every wire and link as a light guide on GraphRibbonWriter's flat
    /// strip, in the themes' coding (u = seed * 64 + 1 + the route's phase
    /// + the distance along; v = length in sixteenths doubled, plus the lit
    /// bit, plus the position across). The pulse's phase is u - 1 modulo
    /// `rpSpacing`, a fifth of 64, so the seed drops out and the light
    /// runs on from one guide into the next.
    ///
    /// The guide's class comes from its height above the board (the route
    /// lifts it by `rpStep` a class, above `rpLift`; `rpNormal` is the
    /// board's up in the links node's frame). On the wiring (`rpFar` 0): 0
    /// a branch, 1 the trunk (widest and brightest), 2 a return rail
    /// (thin, dim, indigo). On the links (`rpFar` 1): 0 a link between two
    /// notes (almost invisible at rest, violet with packets when one of its
    /// notes is chosen), 1 a leg to a port, 2 a fibre between two tiles
    /// (always shown). Tint A the guided light, B the packets, C the links,
    /// D the return rails. `rpWidth` is the strip's half width.
    ///
    /// Drawn alpha-blended, premultiplied: the glass under a wiring guide
    /// is darkened a little (its etched channel), the light added on top.
    static let trace: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;
    float rpDetail;
    float rpSpeed;
    float rpSpacing;
    float rpWidth;
    float rpFar;
    float rpLift;
    float rpStep;
    float3 rpNormal;
    float3 rpTintA;
    float3 rpTintB;
    float3 rpTintC;
    float3 rpTintD;

    #pragma body
    float2 rp_uv = _surface.diffuseTexcoord;
    float rp_d = rp_uv.x - 1.0;
    float rp_k = floor(rp_uv.y);
    float rp_lit = rp_k - 2.0 * floor(rp_k * 0.5);
    float rp_s = fract(rp_uv.y) * 2.0 - 1.0;
    float rp_t = rpClock * rpMotion;

    float4x4 rp_mv = scn_node.modelViewTransform;
    float3 rp_ax = rp_mv[0].xyz;
    float3 rp_ay = rp_mv[1].xyz;
    float3 rp_az = rp_mv[2].xyz;
    float rp_s2 = max(dot(rp_ax, rp_ax), 0.000001);
    float3 rp_rel = _surface.position - rp_mv[3].xyz;
    float3 rp_lp = float3(dot(rp_rel, rp_ax), dot(rp_rel, rp_ay), dot(rp_rel, rp_az)) / rp_s2;
    float rp_h = dot(rp_lp, rpNormal) - rpLift;
    float rp_cls = clamp(floor(rp_h / rpStep + 0.5), 0.0, 2.0);
    float rp_c1 = step(0.5, rp_cls) * step(rp_cls, 1.5);
    float rp_c2 = step(1.5, rp_cls);

    float rp_w = 0.30 + 0.20 * rp_c1 - 0.06 * rp_c2;
    float rp_b = 0.85 + 0.35 * rp_c1 - 0.35 * rp_c2;
    float rp_pb = 0.9 + 0.1 * rp_c1 - 0.5 * rp_c2;
    float3 rp_tone = mix(rpTintA, rpTintD, rp_c2);
    rp_b = rp_b * (1.0 + 0.35 * rp_lit);
    float rp_groove = 0.5;
    if (rpFar > 0.5) {
        float rp_rest = 0.07 + 0.07 * rp_c1 + 0.27 * rp_c2;
        rp_w = 0.18 + 0.04 * rp_c2;
        rp_b = mix(rp_rest, 0.95, rp_lit);
        rp_pb = mix(0.3 * rp_c1 + 0.5 * rp_c2, 0.95, rp_lit);
        rp_tone = rpTintC;
        rp_groove = 0.0;
    }

    float rp_x = abs(rp_s) / rp_w;
    float rp_core = exp(-rp_x * rp_x * 1.6);
    float rp_fall = 1.0 - smoothstep(0.8, 1.0, abs(rp_s));
    float rp_halo = exp(-abs(rp_s) * 3.2) * rp_fall;
    float rp_cov = (1.0 - smoothstep(1.3, 1.9, rp_x)) * rp_groove;

    float rp_e = rpSpeed * rp_t - rp_d;
    float rp_m = rp_e - rpSpacing * floor(rp_e / rpSpacing);
    float rp_ahead = (rpSpacing - rp_m) / 0.03;
    float rp_head = 1.3 * exp(-rp_m / 0.10) + 0.45 * exp(-rp_m / 0.9);
    float rp_pk = (rp_head + 1.3 * exp(-rp_ahead * rp_ahead)) * rp_pb * rpMotion;
    float rp_pw = exp(-rp_x * rp_x * 0.7);

    float3 rp_light = rp_tone * (rp_b * (0.62 * rp_core + 0.22 * rp_halo));
    rp_light = rp_light + rpTintB * (rp_pk * (1.1 * rp_pw + 0.35 * rp_halo));

    rp_light = pow(max(rp_light, float3(0.0)), float3(2.2));
    float rp_a = max(rp_cov, rpProbe);
    _surface.diffuse = float4(rp_light + float3(rpProbe), rp_a);
    """

    // MARK: the parts

    /// Every part's body in its own frame (y up from the glass). `rpPattern`:
    /// 0 a chip's titanium package, 1 a chip's smoked-glass lid with the die
    /// glowing faintly under it (`rpGlow` how busy: more cores and GPU
    /// cells; `rpRim` how bright its satin chamfer, brighter on a small
    /// chip so it reads from afar), 2 a page's ring (`rpGlow` its resting
    /// light), 3 an idea's capsule (`rpGlow` 1 lit, low unlit: then smoked
    /// glass with a thin amber rim; a faint chevron points along the
    /// current, its axis y), 4 a loose note's prism, 5 a tile's source
    /// cell, 6 a fibre's port. Tint A the part's light, B the die's accent
    /// (the collection's hue) or second light, C the body. `rpDist` is the
    /// part's distance from its source along the circuit: it flashes as the
    /// packet passes.
    static let part: String = """
    #pragma arguments
    float rpProbe;
    float rpDetail;
    float rpPattern;
    float rpShine;
    float rpGlow;
    float rpRim;
    float rpDist;
    float rpClock;
    float rpMotion;
    float rpSpeed;
    float rpSpacing;
    float3 rpTintA;
    float3 rpTintB;
    float3 rpTintC;

    #pragma body
    float3 rp_N = normalize(_surface.normal);
    float3 rp_V = normalize(_surface.view);
    float4x4 rp_mv = scn_node.modelViewTransform;
    float3 rp_ax = rp_mv[0].xyz;
    float3 rp_ay = rp_mv[1].xyz;
    float3 rp_az = rp_mv[2].xyz;
    float rp_s2 = max(dot(rp_ax, rp_ax), 0.000001);
    float rp_sc = sqrt(rp_s2);
    float3 rp_rel = _surface.position - rp_mv[3].xyz;
    float3 rp_lp = float3(dot(rp_rel, rp_ax), dot(rp_rel, rp_ay), dot(rp_rel, rp_az)) / rp_s2;
    float3 rp_ln = float3(dot(rp_N, rp_ax), dot(rp_N, rp_ay), dot(rp_N, rp_az)) / rp_sc;
    float rp_up = rp_ln.y;
    float rp_topF = smoothstep(0.9, 0.97, rp_up);
    float rp_mu = clamp(dot(rp_N, rp_V), 0.0, 1.0);
    float rp_fr = pow(1.0 - rp_mu, 3.0);
    float rp_t = rpClock * rpMotion;

    float rp_e = rpSpeed * rp_t - rpDist;
    float rp_m = rp_e - rpSpacing * floor(rp_e / rpSpacing);
    float rp_ahead = (rpSpacing - rp_m) / 0.05;
    float rp_flash = (exp(-rp_m / 0.45) + exp(-rp_ahead * rp_ahead)) * rpMotion;

    float3 rp_base = rpTintC;
    float rp_metal = 0.0;
    float rp_gloss = 0.0;
    float3 rp_emit = float3(0.0, 0.0, 0.0);
    float rp_pat = rpPattern;
    float2 rp_tq = float2(rp_lp.x, rp_lp.z);

    if (rp_pat < 0.5) {
        float rp_br = fract(sin(floor(rp_lp.z * 260.0) * 91.7) * 43758.5453);
        rp_base = rpTintC * (0.9 + 0.1 * rp_br * rpDetail);
        rp_metal = 1.0;
    } else if (rp_pat < 1.5) {
        float rp_ux = rp_lp.x;
        float rp_uz = rp_lp.z;
        float rp_k = rpGlow;
        float rp_box = max(abs(rp_ux), abs(rp_uz));
        float rp_inner = (1.0 - smoothstep(0.345, 0.355, rp_box)) * rp_topF;
        float3 rp_die = float3(0.0, 0.0, 0.0);
        float rp_pc = step(-0.30, rp_ux) * step(rp_ux, -0.05);
        rp_pc = rp_pc * step(-0.31, rp_uz) * step(rp_uz, -0.15);
        float rp_pn = 2.0 + floor(3.0 * rp_k);
        float rp_pg = abs(fract((rp_ux + 0.30) / 0.25 * rp_pn) - 0.5);
        float rp_pl = 1.0 - smoothstep(0.30, 0.40, rp_pg);
        rp_die = rp_die + rpTintB * (rp_pc * mix(0.6, rp_pl, rpDetail));
        float rp_gc = step(0.03, rp_ux) * step(rp_ux, 0.30);
        rp_gc = rp_gc * step(-0.31, rp_uz) * step(rp_uz, -0.15);
        float rp_gn = 4.0 + floor(4.0 * rp_k);
        float rp_gx = abs(fract((rp_ux - 0.03) / 0.27 * rp_gn) - 0.5);
        float rp_gz = abs(fract((rp_uz + 0.31) / 0.16 * 2.0) - 0.5);
        float rp_gcx = 1.0 - smoothstep(0.30, 0.40, rp_gx);
        float rp_gcell = rp_gcx * (1.0 - smoothstep(0.30, 0.40, rp_gz));
        rp_die = rp_die + rpTintA * (rp_gc * mix(0.5, rp_gcell, rpDetail) * 0.7);
        float rp_nc = step(-0.30, rp_ux) * step(rp_ux, 0.12);
        rp_nc = rp_nc * step(0.17, rp_uz) * step(rp_uz, 0.31);
        float rp_nq = abs(fract(rp_ux * 20.0) - 0.5);
        float rp_nl = mix(0.45, 0.25 + 0.4 * step(0.22, rp_nq), rpDetail);
        rp_die = rp_die + (rpTintA * 0.5 + rpTintB * 0.5) * (rp_nc * rp_nl);
        float rp_cc = step(0.17, rp_ux) * step(rp_ux, 0.30);
        rp_cc = rp_cc * step(0.17, rp_uz) * step(rp_uz, 0.31);
        rp_die = rp_die + float3(0.45, 0.48, 0.55) * (rp_cc * 0.35);
        float rp_busy = 0.08 + 0.04 * rp_k + 0.10 * rp_flash;
        float rp_bloom = exp(-dot(rp_tq, rp_tq) * 7.0) * rp_topF;
        rp_base = rpTintC * (0.7 + 0.6 * clamp(0.5 - rp_uz, 0.0, 1.0));
        rp_emit = rp_die * (rp_busy * rp_inner);
        rp_emit = rp_emit + rpTintB * (rp_bloom * (0.012 + 0.05 * rp_flash));
        float rp_eg = (rp_box - 0.35) / 0.004;
        float rp_etch = exp(-rp_eg * rp_eg) * rp_topF;
        float rp_ew = 0.26 + 0.5 * rp_flash;
        rp_emit = rp_emit + (rpTintB * 0.8 + float3(0.12, 0.12, 0.14)) * (rp_etch * rp_ew);
        float rp_cf = smoothstep(0.405, 0.44, rp_box) * rp_topF + (1.0 - rp_topF) * step(0.2, rp_up);
        float rp_satin = rpRim * (0.35 + 0.65 * pow(max(dot(rp_N, normalize(float3(-0.35, 0.65, 0.68))), 0.0), 2.0));
        rp_emit = rp_emit + float3(0.62, 0.64, 0.68) * (rp_cf * rp_satin);
        float rp_bd = (rp_ux * 0.6 - rp_uz * 0.8 + 0.12) / 0.2;
        float rp_band = exp(-rp_bd * rp_bd) * rp_topF * rpDetail;
        rp_emit = rp_emit + float3(0.55, 0.6, 0.7) * (rp_band * 0.035);
        rp_gloss = 1.0;
    } else if (rp_pat < 2.5) {
        float rp_lvl = rpGlow + 1.1 * rp_flash;
        float rp_face = clamp(rp_up, 0.0, 1.0);
        rp_base = rpTintC;
        rp_emit = rpTintA * (rp_lvl * (0.25 + 0.75 * pow(rp_face, 1.5)));
        rp_emit = rp_emit + float3(1.0, 1.0, 1.0) * (pow(rp_face, 12.0) * 0.45 * rp_lvl);
        rp_gloss = 0.3;
    } else if (rp_pat < 3.5) {
        float rp_lvl = rpGlow + 1.3 * rp_flash;
        float rp_ay2 = rp_lp.y / 1.3;
        float rp_c = exp(-rp_ay2 * rp_ay2);
        float rp_see = pow(rp_mu, 1.5);
        float rp_cv = abs(rp_lp.y - 0.25 + abs(rp_lp.z) * 1.4);
        float rp_chev = (1.0 - smoothstep(0.05, 0.11, rp_cv)) * (1.0 - smoothstep(0.3, 0.42, abs(rp_lp.z)));
        rp_base = rpTintC;
        rp_emit = rpTintA * (rp_lvl * rp_c * (0.3 + 0.9 * rp_see));
        rp_emit = rp_emit + rpTintA * (rp_fr * (0.35 + 0.25 * rp_lvl));
        rp_emit = rp_emit + float3(1.0, 0.96, 0.9) * (pow(rp_mu, 4.0) * rp_c * rp_lvl * 0.55);
        rp_emit = rp_emit + mix(rpTintA, float3(1.0, 0.97, 0.9), 0.6) * (rp_chev * (0.10 + 0.25 * rp_lvl));
        rp_gloss = 1.0;
    } else if (rp_pat < 4.5) {
        float rp_lvl = rpGlow + 1.1 * rp_flash;
        rp_base = rpTintC;
        rp_emit = rpTintA * (rp_lvl * (0.3 + 0.5 * rp_topF)) + rpTintA * (rp_fr * 0.4);
        rp_gloss = 1.0;
    } else if (rp_pat < 5.5) {
        float rp_r = length(rp_tq);
        float rp_beat = 1.0 + 0.8 * rp_flash;
        float rp_core = exp(-rp_r * rp_r * 14.0) * rp_topF;
        float rp_rd = (rp_r - 0.33) / 0.04;
        float rp_ring = exp(-rp_rd * rp_rd) * rp_topF;
        rp_base = rpTintC * mix(1.0, 0.12, rp_topF);
        rp_metal = 1.0 - rp_topF;
        rp_emit = float3(1.0, 1.0, 1.0) * (rp_core * rp_beat);
        rp_emit = rp_emit + rpTintA * (rp_ring * 1.1 * rp_beat + rp_topF * 0.12 * rp_beat);
        rp_gloss = rp_topF;
    } else {
        float rp_slot = exp(-(rp_lp.x * rp_lp.x) * 30.0) * rp_topF;
        rp_base = rpTintC;
        rp_metal = 1.0 - rp_topF;
        rp_emit = rpTintA * (rp_slot * (0.5 + 0.8 * rp_flash));
    }

    float3 rp_L = normalize(float3(-0.35, 0.65, 0.68));
    float3 rp_H = normalize(rp_L + rp_V);
    float rp_nl = max(dot(rp_N, rp_L), 0.0);
    float rp_nh = max(dot(rp_N, rp_H), 0.0);
    float rp_power = mix(mix(24.0, 60.0, rp_metal), 140.0, rp_gloss);
    float rp_sp = pow(rp_nh, rp_power) * rpShine;
    float3 rp_spc = mix(float3(0.85, 0.9, 1.0), rp_base * 1.4 + float3(0.1, 0.1, 0.1), rp_metal);
    float rp_sky = 0.5 + 0.5 * rp_N.y;
    float rp_lit = 0.3 + 0.7 * rp_nl;
    float3 rp_col = rp_base * (rp_lit * (1.0 - 0.5 * rp_metal) + rp_metal * 0.3 * rp_sky);
    rp_col = rp_col + rp_spc * rp_sp + float3(0.5, 0.56, 0.68) * (rp_fr * 0.12 * rp_gloss) + rp_emit;

    """ + GraphStyleShaders.glowEnd

    // MARK: glows

    /// A soft glow on a unit plane. `rpShape` 0 round (a billboard: the
    /// halo of a lit capsule, the source or a prism; the chosen part's thin
    /// ring in tint C), 1 a rounded rectangle lying under a tile (its light
    /// spilling onto the dark round it; `rpSize` the rectangle's half size
    /// and corner, as fractions of the plane's half side), 2 a folder's
    /// inlay on the glass (a breath of fill, a lighter rim just inside and
    /// a hairline `rpLine` wide, in the same units; open, and fading, on
    /// the plane's +x side, where its lanes run out to the rail), 3 a
    /// tile's joint dots (every quad one dot: u is the dot's kind times 2
    /// plus across it - 0 a trunk's joint in tint A, 1 a rail's in tint
    /// C). Tint A times `rpGain`, plus `rpFlash` more as the packet passes
    /// (`rpDist`, as the parts).
    static let glow: String = """
    #pragma arguments
    float rpProbe;
    float rpGain;
    float rpFlash;
    float rpDist;
    float rpClock;
    float rpMotion;
    float rpSpeed;
    float rpSpacing;
    float rpShape;
    float rpLine;
    float3 rpSize;
    float3 rpTintA;
    float3 rpTintC;

    #pragma body
    float2 rp_uv = _surface.diffuseTexcoord;
    float rp_code = floor(rp_uv.x * 0.5);
    float rp_u = rp_uv.x - rp_code * 2.0;
    float rp_qx = rp_u * 2.0 - 1.0;
    float rp_qy = 1.0 - rp_uv.y * 2.0;
    float rp_t = rpClock * rpMotion;
    float rp_e = rpSpeed * rp_t - rpDist;
    float rp_m = rp_e - rpSpacing * floor(rp_e / rpSpacing);
    float rp_ahead = (rpSpacing - rp_m) / 0.05;
    float rp_flash = (exp(-rp_m / 0.45) + exp(-rp_ahead * rp_ahead)) * rpMotion;
    float rp_gain = rpGain + rpFlash * rp_flash;
    float3 rp_col = float3(0.0, 0.0, 0.0);
    if (rpShape < 0.5) {
        float rp_r = length(float2(rp_qx, rp_qy)) + 0.00001;
        float rp_core = exp(-rp_r * rp_r / 0.02);
        float rp_soft = exp(-rp_r / 0.18);
        float rp_fade = clamp((1.0 - rp_r) / 0.3, 0.0, 1.0);
        rp_col = rpTintA * ((0.5 * rp_soft + 0.6 * rp_core) * rp_fade * rp_gain);
        float rp_rd = (rp_r - 0.47) / 0.014;
        rp_col = rp_col + rpTintC * (exp(-rp_rd * rp_rd) * rp_fade);
    } else if (rpShape > 2.5) {
        float rp_r = length(float2(rp_qx, rp_qy));
        float rp_dot = 1.0 - smoothstep(0.38, 0.5, rp_r);
        float rp_soft = exp(-rp_r * 3.5) * (1.0 - smoothstep(0.8, 1.0, rp_r));
        float3 rp_tone = mix(rpTintA, rpTintC, clamp(rp_code, 0.0, 1.0));
        rp_col = rp_tone * ((0.9 * rp_dot + 0.25 * rp_soft) * rp_gain);
    } else {
        float rp_open = rpShape - 1.0;
        float rp_ox = mix(rp_qx, min(rp_qx, 0.0), clamp(rp_open, 0.0, 1.0));
        float rp_bx = abs(rp_ox) - (rpSize.x - rpSize.z);
        float rp_by = abs(rp_qy) - (rpSize.y - rpSize.z);
        float rp_bo = length(float2(max(rp_bx, 0.0), max(rp_by, 0.0)));
        float rp_d = rp_bo + min(max(rp_bx, rp_by), 0.0) - rpSize.z;
        if (rpShape < 1.5) {
            float rp_ro = max(rp_d, 0.0);
            float rp_edge = min(1.0 - abs(rp_qx), 1.0 - abs(rp_qy));
            float rp_fade = clamp(rp_edge / 0.15, 0.0, 1.0);
            float rp_spill = exp(-rp_ro / 0.05) * 0.6 + exp(-rp_ro / 0.16) * 0.4;
            rp_col = rpTintA * (rp_spill * rp_fade * rp_gain * step(0.0, rp_d));
        } else {
            float rp_fill = 1.0 - smoothstep(-rpLine, rpLine, rp_d);
            float rp_ld = rp_d / rpLine;
            float rp_line = exp(-rp_ld * rp_ld);
            float rp_rim = exp(max(rp_d, -1.0) / (rpLine * 8.0)) * rp_fill;
            float rp_away = 1.0 - smoothstep(0.2, 1.0, rp_qx) * 0.85;
            float rp_mix = 0.05 * rp_fill + 0.08 * rp_rim + 0.32 * rp_line;
            rp_col = rpTintA * (rp_gain * rp_mix * rp_away) + rpTintC * (0.05 * rp_line * rp_gain * rp_away);
        }
    }

    """ + GraphStyleShaders.glowEnd
}
