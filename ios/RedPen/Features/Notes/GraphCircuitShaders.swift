import Foundation

// The Circuit theme's shader modifiers (GraphCircuitLook builds the materials
// and checks they compile; GraphCircuit plans what they dress).
//
// The look is calm boards on a dark bench under a desk lamp: plain dark
// green solder mask with a soft vignette and a thin silkscreen outline;
// chips in the style of modern system-on-chip packages - a near-black,
// lightly brushed lid with a bright bevel, an etched outline and a faint
// die layout under it; capacitor cans; LEDs in amber epoxy; gold pads.
// Traces are copper, one per link; now and then a packet of cyan current
// runs along one at its own random time (NeuronImpulse's timing, mirrored
// here exactly, as the Neurons' axons do), flashing on the pad it reaches -
// and the LED there lights (GraphCircuitLook's ticker). No drifting dots:
// between packets the copper is still.
//
// They follow the other themes' rules (GraphStyleShaders): constant
// lighting, the final colour written to `_surface.diffuse`, designed as it
// shows on screen and taken into linear space at the end; the light is the
// shaders' own (a lamp up and to the left, in view space), so nothing
// depends on the scene's lights; time is `rpClock` times `rpMotion` (0 with
// Reduce Motion); `rpProbe` is added at the end so a modifier that fails to
// compile is caught; no helper functions. `rpDetail` 0 (the Smooth budget)
// drops the mask's grain and the die's finest detail.
//
// A part's shader reads where it is drawn in the part's own frame from the
// node's model-view axes (every part node is scaled evenly), so one shader
// dresses every kind of part by `rpPattern`, and no two resistors carry the
// same bands: their colours come from where the part is.

nonisolated enum CircuitShaders {
    // MARK: the boards

    /// A collection's board (`rpZone` 0) or a sub-folder's sub-board (1), on a box
    /// whose own y is the board's up; `rpSize` is half the box. Tint A the
    /// solder mask (a soft vignette darkens its edges), C its thin outline.
    static let board: String = """
    #pragma arguments
    float rpProbe;
    float rpDetail;
    float rpZone;
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
    float rp_top = step(0.5, dot(rp_N, normalize(rp_ay)));
    float2 rp_q = float2(rp_lp.x, rp_lp.z);

    float rp_gh = fract(sin(dot(floor(rp_q * 60.0), float2(12.9898, 78.233))) * 43758.5453);
    float3 rp_col = rpTintA * (0.93 + 0.07 * rp_gh * rpDetail);
    float rp_ex = rpSize.x - abs(rp_q.x);
    float rp_ez = rpSize.z - abs(rp_q.y);
    float rp_ed = min(rp_ex, rp_ez);
    float rp_vig = smoothstep(0.0, mix(0.9, 0.35, rpZone), rp_ed);
    rp_col = rp_col * (0.62 + 0.38 * rp_vig);
    float rp_inset = mix(0.07, 0.025, rpZone);
    float rp_lw = mix(0.006, 0.005, rpZone);
    float rp_line = 1.0 - smoothstep(rp_lw, rp_lw + 0.005, abs(rp_ed - rp_inset));
    rp_col = mix(rp_col, rpTintC, rp_line * mix(0.45, 0.3, rpZone));
    float rp_hole = 0.0;

    float rp_lay = step(0.5, fract(rp_lp.y * 45.0));
    float3 rp_side = float3(0.30, 0.27, 0.15) * (0.75 + 0.25 * rp_lay);
    rp_col = mix(rp_side, rp_col, rp_top);

    float3 rp_L = normalize(float3(-0.35, 0.65, 0.68));
    float3 rp_H = normalize(rp_L + rp_V);
    float rp_nl = max(dot(rp_N, rp_L), 0.0);
    float rp_sp = pow(max(dot(rp_N, rp_H), 0.0), 60.0) * 0.18 * (1.0 - rp_hole);
    rp_col = rp_col * (0.6 + 0.4 * rp_nl) + float3(0.55, 0.75, 0.62) * rp_sp;

    """ + GraphStyleShaders.glowEnd

    // MARK: the traces

    /// A link as a copper trace, on GraphRibbonWriter's flat strip in the
    /// themes' coding (u = seed * 64 + 1 + distance along; v = length in
    /// sixteenths doubled, plus the lit bit, plus the position across).
    /// Tint A the copper, B the current, C its glow; `rpBundle` 1 draws a
    /// bus of three traces; `rpWidth` is half the strip's width in the
    /// space (so the pads come out round); `rpRate` the chance a slot sends
    /// a packet, `rpBurst` the chance it is a burst.
    ///
    /// Drawn alpha-blended, premultiplied (GraphCircuitLook.traceMaterial):
    /// the copper is opaque where it covers (alpha its coverage), so it lies
    /// on the board as copper rather than glowing on it, and crossing traces
    /// or a bus's lanes meeting at a corner stay copper, never add up to
    /// white; the current's dots, packets, halo and pad flashes are light,
    /// added on top with no alpha of their own.
    static let trace: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;
    float rpDetail;
    float rpRate;
    float rpBurst;
    float rpBundle;
    float rpWidth;
    float3 rpTintA;
    float3 rpTintB;
    float3 rpTintC;

    #pragma body
    float2 rp_uv = _surface.diffuseTexcoord;
    float rp_seed = floor(rp_uv.x / 64.0);
    float rp_along = rp_uv.x - rp_seed * 64.0 - 1.0;
    float rp_k = floor(rp_uv.y);
    float rp_spanQ = floor(rp_k * 0.5);
    float rp_lit = rp_k - 2.0 * rp_spanQ;
    float rp_len = max(rp_spanQ * 0.0625, 0.05);
    float rp_s = fract(rp_uv.y) * 2.0 - 1.0;
    float rp_f = clamp(rp_along / rp_len, 0.0, 1.0);
    float rp_t = rpClock * rpMotion;

    float rp_d0 = abs(rp_s);
    float rp_d1 = abs(rp_d0 - 0.64);
    float rp_dm = mix(rp_d0, min(rp_d0, rp_d1), rpBundle);
    float rp_w = mix(0.56, 0.2, rpBundle);
    float rp_x = rp_dm / rp_w;
    float rp_cu = 1.0 - smoothstep(0.84, 1.0, rp_x);
    float rp_ex = (rp_x - 0.82) / 0.12;
    float rp_edge = exp(-rp_ex * rp_ex);
    float rp_sheen = 0.86 + 0.14 * sin(rp_along * 3.1 + rp_seed * 1.7);
    float3 rp_col = rpTintA * (0.52 * rp_sheen + 0.3 * rp_edge);

    float rp_py = rp_s * rpWidth;
    float rp_pa = length(float2(rp_along, rp_py));
    float rp_pb = length(float2(rp_len - rp_along, rp_py));
    float rp_pn = min(rp_pa, rp_pb);
    float rp_pr = rpWidth * 0.98;
    float rp_pad = 1.0 - smoothstep(rp_pr * 0.82, rp_pr, rp_pn);
    float rp_via = 1.0 - smoothstep(rp_pr * 0.3, rp_pr * 0.4, rp_pn);
    float rp_cov = max(rp_cu, rp_pad);
    rp_col = mix(rp_col, max(rp_col, rpTintA * 0.6), rp_pad);
    rp_col = rp_col * (1.0 - 0.85 * rp_via);
    float3 rp_light = float3(0.0);

    uint rp_su = uint(rp_seed);
    uint rp_h = rp_su * 747796405u + 2891336453u;
    rp_h = ((rp_h >> ((rp_h >> 28u) + 4u)) ^ rp_h) * 277803737u;
    rp_h = (rp_h >> 22u) ^ rp_h;
    float rp_P = 0.9 + 1.5 * (float(rp_h & 255u) / 255.0);
    float rp_D = 0.45 + 0.5 * (float((rp_h >> 8u) & 255u) / 255.0);
    float rp_ph = (float((rp_h >> 16u) & 255u) / 255.0) * rp_P;
    float rp_tt = rp_t + rp_ph;
    float rp_k0 = floor(rp_tt / rp_P);
    float rp_pulse = 0.0;
    float rp_flash = 0.0;
    int rp_nb = rpBurst > 0.0 ? 3 : 1;
    for (int rp_j = 0; rp_j < 3; rp_j++) {
        float rp_ks = rp_k0 - float(rp_j);
        uint rp_g = uint(max(rp_ks, 0.0)) * 2654435761u + rp_su * 40503u + 17u;
        rp_g = rp_g * 747796405u + 2891336453u;
        rp_g = ((rp_g >> ((rp_g >> 28u) + 4u)) ^ rp_g) * 277803737u;
        rp_g = (rp_g >> 22u) ^ rp_g;
        float rp_fire = 1.0 - step(rpRate, float(rp_g & 255u) / 255.0);
        float rp_at = float((rp_g >> 8u) & 255u) / 255.0;
        float rp_tf = rp_ks * rp_P + 0.5 * rp_P * rp_at;
        float rp_many = 1.0 - step(rpBurst, float((rp_g >> 16u) & 255u) / 255.0);
        for (int rp_b = 0; rp_b < rp_nb; rp_b++) {
            float rp_on = rp_b == 0 ? rp_fire : rp_fire * rp_many;
            float rp_age = rp_tt - rp_tf - float(rp_b) * 0.12;
            float rp_pos = rp_age / rp_D;
            float rp_dx = (rp_f - rp_pos) * rp_len;
            float rp_fr = rp_dx / 0.06;
            float rp_head = exp(-rp_fr * rp_fr);
            float rp_tail = exp(rp_dx / 0.3);
            float rp_spk = rp_dx > 0.0 ? rp_head : rp_tail;
            float rp_fly = step(0.0, rp_age) * step(rp_pos, 1.0);
            rp_pulse = rp_pulse + rp_on * rp_spk * rp_fly;
            float rp_after = rp_age - rp_D;
            float rp_fade = exp(-max(rp_after, 0.0) / 0.2);
            rp_flash = rp_flash + rp_on * step(0.0, rp_after) * rp_fade;
        }
    }

    float rp_imp = min(rp_pulse, 1.5);
    float rp_core = 1.0 - smoothstep(0.35, 0.95, rp_x);
    rp_light = rp_light + rpTintB * (rp_imp * (0.9 * rp_core + 0.1) * rp_cu);
    rp_light = rp_light + rpTintC * (rp_imp * 0.22 * (1.0 - smoothstep(1.0, 1.8, rp_x)));
    float rp_endPad = 1.0 - smoothstep(rp_pr * 0.9, rp_pr * 1.9, rp_pb);
    float rp_fl = min(rp_flash, 1.5) * rp_endPad;
    rp_light = rp_light + (rpTintB + rpTintC * 0.4) * (rp_fl * 0.7);
    float rp_in = smoothstep(0.0, 0.02, rp_along);
    rp_col = rp_col * (1.0 + 0.5 * rp_lit);
    rp_light = rp_light * (1.0 + 0.5 * rp_lit) * rp_in;
    rp_cov = rp_cov * rp_in;

    rp_col = pow(max(rp_col, float3(0.0)), float3(2.2));
    rp_light = pow(max(rp_light, float3(0.0)), float3(2.2));
    float rp_a = max(rp_cov, rpProbe);
    _surface.diffuse = float4(rp_col * rp_cov + rp_light + float3(rpProbe), rp_a);
    """

    // MARK: the parts

    /// Every part's body, lit by the lamp, in the part's own frame (y up
    /// from the board). `rpPattern` picks the part: 0 black epoxy (a chip,
    /// its pin-1 dimple on top), 1 a brushed metal lid, 2 a resistor's
    /// colour bands (its axis along y), 3 a diode's cathode band, 4 an
    /// electrolytic can (its sleeve's stripe, its scored vent), 5 an
    /// inductor's copper windings (a ring round y), 6 matte plastic, 7
    /// bright metal, 8 a surface-mount part's tinned ends (along x), 9 an
    /// LED's tinted epoxy (`rpGlow` how lit), 10 gold, 11 a gold pad with a
    /// hole, 12 a processor's green substrate, 13 a system-on-chip lid (tint
    /// A the anodised metal, B its bevel and etched outline, C unused;
    /// `rpGlow` how busy its die: more cores and GPU cells, and a neural
    /// block from a quarter). Tint A the body, B the
    /// second colour (bands, stripe, ends), C the third (the can's top).
    /// `rpShine` scales the highlight.
    static let part: String = """
    #pragma arguments
    float rpProbe;
    float rpDetail;
    float rpPattern;
    float rpShine;
    float rpGlow;
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
    float3 rp_wp = scn_node.modelTransform[3].xyz;
    float rp_id = fract(sin(dot(rp_wp, float3(12.9898, 78.233, 37.719))) * 43758.5453);
    float rp_gr = fract(sin(dot(floor(rp_lp * 90.0), float3(12.9898, 78.233, 37.719))) * 43758.5453);
    float rp_mu = clamp(dot(rp_N, rp_V), 0.0, 1.0);

    float3 rp_base = rpTintA;
    float rp_metal = 0.0;
    float3 rp_emit = float3(0.0, 0.0, 0.0);
    float rp_pat = rpPattern;
    float rp_topF = step(0.9, rp_up);
    float2 rp_tq = float2(rp_lp.x, rp_lp.z);

    if (rp_pat < 0.5) {
        rp_base = rp_base * (0.9 + 0.12 * rp_gr * rpDetail);
        float rp_dd = length(rp_tq - float2(-0.6, 0.6));
        float rp_dim = (1.0 - smoothstep(0.07, 0.09, rp_dd)) * rp_topF;
        rp_base = mix(rp_base, rp_base * 0.35, rp_dim);
    } else if (rp_pat < 1.5) {
        float rp_br = fract(sin(floor(rp_lp.z * 240.0) * 91.7) * 43758.5453);
        rp_base = rp_base * (0.88 + 0.12 * rp_br);
        rp_metal = 1.0;
    } else if (rp_pat < 2.5) {
        for (int rp_j = 0; rp_j < 3; rp_j++) {
            float rp_bp = -0.62 + 0.3 * float(rp_j);
            float rp_code = floor(fract(rp_id * (float(rp_j) + 1.0) * 7.31) * 10.0);
            float3 rp_hue = float3(rp_code * 0.1) + float3(0.0, 0.33, 0.67);
            float3 rp_bc = float3(0.5, 0.5, 0.5) + 0.5 * cos(6.2832 * rp_hue);
            float rp_bm = 1.0 - smoothstep(0.07, 0.09, abs(rp_lp.y - rp_bp));
            rp_base = mix(rp_base, rp_bc * 0.8, rp_bm);
        }
        float rp_gm = 1.0 - smoothstep(0.07, 0.09, abs(rp_lp.y - 0.6));
        rp_base = mix(rp_base, rpTintB, rp_gm);
    } else if (rp_pat < 3.5) {
        float rp_cm = step(0.6, rp_lp.y) * step(rp_lp.y, 0.9);
        rp_base = mix(rp_base, rpTintB, rp_cm);
        rp_metal = rp_cm;
    } else if (rp_pat < 4.5) {
        float rp_a = atan2(rp_lp.z, rp_lp.x);
        float rp_stripe = 1.0 - smoothstep(0.42, 0.5, abs(rp_a));
        float rp_dash = step(0.5, fract(rp_lp.y * 3.0));
        rp_base = mix(rp_base, rpTintB, rp_stripe * (0.35 + 0.65 * rp_dash));
        float rp_groove = 1.0 - smoothstep(0.02, 0.05, abs(rp_lp.y - 0.6));
        rp_base = rp_base * (1.0 - 0.45 * rp_groove);
        float rp_r = length(rp_tq);
        float rp_vent = (1.0 - smoothstep(0.02, 0.04, min(abs(rp_lp.x), abs(rp_lp.z)))) * step(rp_r, 0.52);
        float3 rp_lid = rpTintC * (1.0 - 0.5 * rp_vent);
        float rp_rim = smoothstep(0.66, 0.72, rp_r);
        rp_lid = mix(rp_lid, rpTintA, rp_rim);
        rp_base = mix(rp_base, rp_lid, rp_topF);
        rp_metal = rp_topF * (1.0 - rp_rim);
    } else if (rp_pat < 5.5) {
        float rp_a = atan2(rp_lp.z, rp_lp.x);
        float rp_wd = abs(sin(rp_a * 26.0));
        rp_base = rp_base * (0.55 + 0.45 * sqrt(rp_wd));
        rp_metal = 1.0;
    } else if (rp_pat < 6.5) {
        rp_base = rp_base * (0.9 + 0.1 * rp_gr * rpDetail);
    } else if (rp_pat < 7.5) {
        rp_metal = 1.0;
    } else if (rp_pat < 8.5) {
        float rp_end = step(0.72, abs(rp_lp.x));
        rp_base = mix(rp_base, rpTintB, rp_end);
        rp_metal = rp_end;
    } else if (rp_pat < 9.5) {
        float rp_in = pow(rp_mu, 1.5);
        float rp_edgeL = pow(1.0 - rp_mu, 2.0);
        rp_base = rpTintA * (0.18 + 0.3 * rp_edgeL);
        float rp_die = exp(-dot(rp_lp - float3(0.0, 0.1, 0.0), rp_lp - float3(0.0, 0.1, 0.0)) * 9.0);
        float rp_lum = rpGlow * (0.5 * rp_in + 0.9 * rp_die);
        rp_emit = rpTintA * rp_lum + float3(1.0, 1.0, 1.0) * (rpGlow * 0.4 * rp_die);
    } else if (rp_pat < 10.5) {
        rp_base = rp_base * (0.9 + 0.1 * rp_gr * rpDetail);
        rp_metal = 1.0;
    } else if (rp_pat < 11.5) {
        float rp_r = length(rp_tq);
        float rp_hole = 1.0 - smoothstep(0.3, 0.34, rp_r);
        rp_base = mix(rp_base, float3(0.01, 0.01, 0.01), rp_hole);
        rp_metal = 1.0 - rp_hole;
    } else if (rp_pat > 12.5) {
        float rp_ax2 = abs(rp_lp.x);
        float rp_az2 = abs(rp_lp.z);
        float rp_box = max(rp_ax2, rp_az2);
        float rp_bru = fract(sin(floor(rp_lp.z * 320.0) * 91.7) * 43758.5453);
        rp_base = rpTintA * (0.9 + 0.1 * rp_bru);
        float3 rp_die = float3(0.0, 0.0, 0.0);
        float rp_k = rpGlow;
        float rp_in = step(rp_box, 0.6) * rp_topF;
        float rp_ux = rp_lp.x;
        float rp_uz = rp_lp.z;
        float rp_pc = step(-0.55, rp_ux) * step(rp_ux, -0.08) * step(-0.55, rp_uz) * step(rp_uz, -0.12);
        float rp_pn = 2.0 + floor(2.0 * rp_k);
        float rp_pg = abs(fract((rp_ux + 0.55) / 0.47 * rp_pn) - 0.5);
        float rp_pl = 1.0 - smoothstep(0.42, 0.47, rp_pg);
        rp_die = rp_die + float3(0.9, 0.75, 0.55) * (rp_pc * (0.55 + 0.45 * rp_pl));
        float rp_ec = step(-0.55, rp_ux) * step(rp_ux, -0.2) * step(-0.05, rp_uz) * step(rp_uz, 0.18);
        float rp_eg = abs(fract((rp_ux + 0.55) / 0.35 * 4.0) - 0.5);
        rp_die = rp_die + float3(0.6, 0.8, 0.7) * (rp_ec * (1.0 - smoothstep(0.4, 0.47, rp_eg)) * 0.8);
        float rp_gc = step(0.0, rp_ux) * step(rp_ux, 0.55) * step(-0.55, rp_uz) * step(rp_uz, 0.18);
        float rp_gn = 3.0 + floor(4.0 * rp_k);
        float rp_gx = abs(fract((rp_ux) / 0.55 * rp_gn) - 0.5);
        float rp_gz = abs(fract((rp_uz + 0.55) / 0.73 * rp_gn) - 0.5);
        float rp_gcell = (1.0 - smoothstep(0.38, 0.46, rp_gx)) * (1.0 - smoothstep(0.38, 0.46, rp_gz));
        rp_die = rp_die + float3(0.55, 0.5, 0.95) * (rp_gc * (0.35 + 0.65 * rp_gcell));
        float rp_nc = step(-0.1, rp_ux) * step(rp_ux, 0.55) * step(0.26, rp_uz) * step(rp_uz, 0.55);
        float rp_nq = abs(fract(rp_ux * 16.0) - 0.5) * abs(fract(rp_uz * 16.0) - 0.5);
        rp_die = rp_die + float3(0.35, 0.85, 0.85) * (rp_nc * (0.6 + 0.4 * step(0.05, rp_nq) * rpDetail) * step(0.25, rp_k));
        float rp_cc = step(-0.55, rp_ux) * step(rp_ux, -0.2) * step(0.26, rp_uz) * step(rp_uz, 0.55);
        rp_die = rp_die + float3(0.7, 0.72, 0.78) * (rp_cc * 0.7);
        rp_base = rp_base + rp_die * (0.05 * rp_in);
        float rp_etch = 1.0 - smoothstep(0.004, 0.009, abs(rp_box - 0.66));
        rp_base = mix(rp_base, rpTintB * 0.3, rp_etch * rp_topF * 0.6);
        float rp_bev = smoothstep(0.7, 0.78, rp_box) * rp_topF + (1.0 - rp_topF) * step(0.2, rp_up);
        rp_base = rp_base + rpTintB * (0.35 * rp_bev);
        rp_metal = 1.0;
    } else {
        float2 rp_g = fract(rp_tq * 9.0) - float2(0.5, 0.5);
        float rp_band = step(0.78, max(abs(rp_lp.x), abs(rp_lp.z)));
        float rp_ball = (1.0 - smoothstep(0.16, 0.22, length(rp_g))) * rp_band * rp_topF * rpDetail;
        rp_base = mix(rp_base * (0.9 + 0.1 * rp_gr), rpTintB, rp_ball);
        rp_metal = rp_ball;
    }

    float3 rp_L = normalize(float3(-0.35, 0.65, 0.68));
    float3 rp_H = normalize(rp_L + rp_V);
    float rp_nl = max(dot(rp_N, rp_L), 0.0);
    float rp_nh = max(dot(rp_N, rp_H), 0.0);
    float rp_fr = pow(1.0 - rp_mu, 4.0);
    float rp_power = mix(22.0, 70.0, rp_metal);
    float rp_sp = pow(rp_nh, rp_power) * rpShine;
    float3 rp_spc = mix(float3(0.9, 0.95, 1.0), rp_base * 1.3 + float3(0.12, 0.12, 0.12), rp_metal);
    float rp_sky = 0.5 + 0.5 * rp_N.y;
    float rp_lit = 0.3 + 0.7 * rp_nl;
    float3 rp_col = rp_base * (rp_lit * (1.0 - 0.45 * rp_metal) + rp_metal * 0.35 * rp_sky);
    rp_col = rp_col + rp_spc * rp_sp + rp_base * (rp_fr * 0.3) + rp_emit;

    """ + GraphStyleShaders.glowEnd

    // MARK: glows

    /// A soft round glow on a billboard (the halo round a part, the light
    /// of a lit LED or a busy chip): a bright core and a wide soft falloff
    /// in tint A, times `rpGain`; tint C draws the chosen part's thin ring
    /// (the part's edge at 0.4 of the half side).
    static let glow: String = """
    #pragma arguments
    float rpProbe;
    float rpGain;
    float3 rpTintA;
    float3 rpTintC;

    #pragma body

    """ + GraphStyleShaders.plane + """
    float rp_core = exp(-rp_r * rp_r / 0.02);
    float rp_soft = exp(-rp_r / 0.2);
    float rp_fade = clamp((1.0 - rp_r) / 0.3, 0.0, 1.0);
    float3 rp_col = rpTintA * ((0.5 * rp_soft + 0.7 * rp_core) * rp_fade * rpGain);
    float rp_rd = (rp_r - 0.47) / 0.014;
    rp_col = rp_col + rpTintC * (exp(-rp_rd * rp_rd) * rp_fade);

    """ + GraphStyleShaders.glowEnd
}
