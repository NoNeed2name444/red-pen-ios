import Foundation

// The Neurons theme's shader modifiers (GraphNeuronLook builds the materials
// and checks they compile; GraphNeurons plans what they dress).
//
// The look is live-cell fluorescence microscopy: cells glow on a dark tissue
// background, their membranes brightest just inside the edge, a jelly body
// whose glow deepens where there is more of it to look through, a nucleus
// and nucleolus seen through it, faint organelles, a wet highlight, and the
// whole membrane slowly breathing and wobbling. Each link is one axon
// (GraphLinkArbor): a hillock cone out of the sending soma, a thin round
// gel fibre in a faint myelin haze, tapering to one small bouton pressed on
// the target's membrane across a dark cleft; action potentials run along
// it at each axon's own random times (NeuronImpulse, mirrored here
// exactly), and on reaching the bouton send transmitter across the cleft.
//
// They follow the Space's rules (GraphStyleShaders): surface modifiers write
// the final colour into `_surface.diffuse` (constant lighting, added to
// what is behind), designed as it shows on screen and taken into linear
// space at the end; time is `rpClock` times `rpMotion` (0 with Reduce
// Motion); `rpProbe` is added at the end so a modifier that fails to
// compile is caught; no helper functions. The two geometry modifiers
// (the membrane's wobble, the dendrites' sway) read their own clock,
// `rpSway`, set by NeuronImpulses each frame - an argument is never
// declared by two modifiers of one material. `rpDetail` 0 (the Smooth
// budget) drops the organelles, the dendrites' beads, the bursts and the
// synapse's fine marks.
//
// Per-cell variety needs no per-cell material: every cell's soma and arbor
// are turned at random when built, so the nucleus, speckle and wobble fall
// differently on each, and the breathing's phase comes from where it is.

nonisolated enum NeuronShaders {
    // MARK: the soma

    /// A cell body on a unit sphere (the node scaled to its size): tint A
    /// the membrane dye, B the nucleus, C the organelles; `rpNucleus` the
    /// nucleus's radius as a share of the cell's (0: none).
    static let soma: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;
    float rpDetail;
    float rpNucleus;
    float3 rpTintA;
    float3 rpTintB;
    float3 rpTintC;

    #pragma body
    float3 rp_N = normalize(_surface.normal);
    float3 rp_V = normalize(_surface.view);
    float rp_mu = clamp(dot(rp_N, rp_V), 0.0, 1.0);
    float4x4 rp_mv = scn_node.modelViewTransform;
    float3 rp_ax = rp_mv[0].xyz;
    float3 rp_ay = rp_mv[1].xyz;
    float3 rp_az = rp_mv[2].xyz;
    float3 rp_c = rp_mv[3].xyz;
    float rp_R = max(length(rp_ax), 0.0001);
    float rp_R2 = rp_R * rp_R;
    float3 rp_d = normalize(_surface.position);
    float rp_tc = dot(rp_c, rp_d);
    float3 rp_off = rp_d * rp_tc - rp_c;
    float rp_q = clamp(dot(rp_off, rp_off) / rp_R2, 0.0, 1.0);
    float rp_thick = sqrt(1.0 - rp_q);

    float3 rp_nc = rp_c + rp_ax * 0.18 + rp_ay * 0.07;
    float rp_nt = dot(rp_nc, rp_d);
    float3 rp_no = rp_d * rp_nt - rp_nc;
    float rp_nr = max(rp_R * rpNucleus, 0.0001);
    float rp_nd = length(rp_no) / rp_nr;
    float rp_has = step(0.01, rpNucleus);
    float rp_nuc = (1.0 - smoothstep(0.8, 1.0, rp_nd)) * rp_has;
    float rp_ne = (rp_nd - 0.9) / 0.1;
    float rp_env = exp(-rp_ne * rp_ne) * rp_has;
    float3 rp_lc = rp_nc - rp_ay * 0.12 + rp_az * 0.1;
    float rp_lt = dot(rp_lc, rp_d);
    float3 rp_lo = rp_d * rp_lt - rp_lc;
    float rp_ld = length(rp_lo) / (rp_nr * 0.34);
    float rp_lol = (1.0 - smoothstep(0.55, 1.0, rp_ld)) * rp_nuc;

    float rp_t = rpClock * rpMotion;
    float3 rp_rel = _surface.position - rp_c;
    float3 rp_lp = float3(dot(rp_rel, rp_ax), dot(rp_rel, rp_ay), dot(rp_rel, rp_az));
    rp_lp = rp_lp / rp_R2;
    float3 rp_g = rp_lp * 5.0 + float3(0.0, rp_t * 0.04, 0.0);
    float3 rp_gi = floor(rp_g);
    float3 rp_gf = rp_g - rp_gi;
    float rp_gs = sin(dot(rp_gi, float3(12.9898, 78.233, 37.719)));
    float rp_gh = fract(rp_gs * 43758.5453);
    float3 rp_gp = float3(rp_gh, fract(rp_gh * 7.13), fract(rp_gh * 3.71));
    rp_gp = rp_gp * 0.6 + float3(0.2, 0.2, 0.2);
    float rp_gd = length(rp_gf - rp_gp);
    float rp_dot = 1.0 - smoothstep(0.05, 0.14, rp_gd);
    rp_dot = rp_dot * step(0.45, rp_gh) * rpDetail;

    float rp_rim = pow(1.0 - rp_mu, 2.4) * smoothstep(0.0, 0.18, rp_mu);
    float rp_ph = dot(scn_node.modelTransform[3].xyz, float3(1.7, 2.3, 1.1));
    float rp_br = 1.0 + 0.07 * sin(rp_t * 0.9 + rp_ph);
    float rp_body = 0.14 + 0.2 * rp_thick;
    float3 rp_col = rpTintA * (rp_body + 1.1 * rp_rim);
    float3 rp_nucCol = rpTintB * (0.3 + 0.22 * rp_thick);
    rp_col = mix(rp_col, rp_nucCol, rp_nuc * 0.8);
    rp_col = rp_col + rpTintB * (0.4 * rp_env);
    rp_col = rp_col + rpTintB * (0.35 * rp_lol);
    rp_col = rp_col + rpTintC * (0.45 * rp_dot * rp_thick);
    float3 rp_L = normalize(float3(-0.45, 0.6, 0.66));
    float3 rp_H = normalize(rp_L + rp_V);
    float rp_sp = pow(max(dot(rp_N, rp_H), 0.0), 40.0);
    float3 rp_wet = float3(0.75, 0.95, 1.0) * (0.3 * rp_sp);
    rp_col = rp_col * rp_br + rp_wet;

    """ + GraphStyleShaders.glowEnd

    /// The membrane breathing: every vertex pushed along its normal by a
    /// slow, low wave, `rpWobble` of the radius at most.
    static let wobble: String = """
    #pragma arguments
    float rpSway;
    float rpWobble;

    #pragma body
    float3 rp_p = _geometry.position.xyz;
    float rp_ph = dot(scn_node.modelTransform[3].xyz, float3(1.3, 0.7, 1.9));
    float rp_a = sin(rp_p.x * 3.1 + rpSway * 1.3 + rp_ph);
    float rp_b = sin(rp_p.y * 2.7 - rpSway * 0.9 + rp_ph * 0.5);
    float rp_c = sin(rp_p.z * 3.7 + rpSway * 1.1 + rp_p.x * 1.3);
    float rp_w = (rp_a * rp_b * 0.6 + rp_c * 0.4) * rpWobble;
    _geometry.position.xyz = rp_p + _geometry.normal * rp_w;
    """

    // MARK: the dendrites

    /// The dendritic arbor's tapered tubes (u runs 0 at the soma to 1 at
    /// the tip): thin gel, brightest along its edges, fading out along its
    /// length, beaded with spines.
    static let arbor: String = """
    #pragma arguments
    float rpProbe;
    float rpDetail;
    float3 rpTintA;

    #pragma body
    float3 rp_N = normalize(_surface.normal);
    float3 rp_V = normalize(_surface.view);
    float rp_mu = abs(dot(rp_N, rp_V));
    float rp_s = _surface.diffuseTexcoord.x;
    float rp_core = pow(rp_mu, 0.7);
    float rp_rim = pow(1.0 - rp_mu, 3.0) * smoothstep(0.0, 0.2, rp_mu);
    float rp_fade = 1.0 - 0.65 * rp_s;
    float rp_sw = pow(abs(sin(rp_s * 38.0)), 12.0);
    float rp_bead = 1.0 + 0.3 * rpDetail * rp_sw;
    float rp_lum = (0.16 * rp_core + 0.55 * rp_rim) * rp_fade;
    float3 rp_col = rpTintA * (rp_lum * rp_bead);
    rp_col = rp_col * (1.0 - smoothstep(0.93, 1.0, rp_s));

    """ + GraphStyleShaders.glowEnd

    /// The dendrites swaying in the fluid: more the further out.
    static let sway: String = """
    #pragma arguments
    float rpSway;
    float rpWobble;

    #pragma body
    float3 rp_p = _geometry.position.xyz;
    float rp_r = length(rp_p);
    float rp_ph = dot(scn_node.modelTransform[3].xyz, float3(1.3, 0.7, 1.9));
    float rp_sx = sin(rpSway * 0.8 + rp_p.y * 1.7 + rp_ph);
    float rp_sy = sin(rpSway * 0.6 + rp_p.z * 1.9 + rp_ph * 1.3);
    float rp_sz = sin(rpSway * 0.7 + rp_p.x * 1.5 + rp_ph * 0.7);
    float3 rp_s = float3(rp_sx, rp_sy, rp_sz) * (rpWobble * 2.5 * rp_r);
    _geometry.position.xyz = rp_p + rp_s;
    """

    // MARK: glows

    /// The soft light round a cell, on a billboard 5 cell radii across (the
    /// membrane at 0.4 of its half side): a little inside, a soft falloff
    /// outside; tint C draws the chosen cell's thin ring.
    static let halo: String = """
    #pragma arguments
    float rpProbe;
    float rpGain;
    float3 rpTintA;
    float3 rpTintC;

    #pragma body

    """ + GraphStyleShaders.plane + """
    float rp_e = 0.4;
    float rp_out = max(rp_r - rp_e, 0.0);
    float rp_outside = step(rp_e, rp_r);
    float rp_soft = exp(-rp_out / 0.09) * 0.3;
    float rp_wide = exp(-rp_out / 0.28) * 0.14;
    float rp_in = rp_r / rp_e;
    float rp_inner = rp_in * rp_in * 0.12 * (1.0 - rp_outside);
    float rp_lum = (rp_soft + rp_wide) * rp_outside + rp_inner;
    float rp_fade = clamp((1.0 - rp_r) / 0.25, 0.0, 1.0);
    float3 rp_col = rpTintA * (rp_lum * rp_fade * rpGain);
    float rp_rd = (rp_r - 0.47) / 0.014;
    rp_col = rp_col + rpTintC * (exp(-rp_rd * rp_rd) * rp_fade);

    """ + GraphStyleShaders.glowEnd

    /// An impulse arriving: the receiving cell's dendrites light up, on a
    /// billboard 7 radii across (the membrane at 0.286), in rays like a
    /// dendritic tree, with a brief bright rim. The node's opacity carries
    /// how much (NeuronImpulses).
    static let arrival: String = """
    #pragma arguments
    float rpProbe;
    float3 rpTintA;
    float3 rpTintB;

    #pragma body

    """ + GraphStyleShaders.plane + """
    float rp_e = 0.286;
    float rp_out = max(rp_r - rp_e, 0.0);
    float rp_a = atan2(rp_qy, rp_qx);
    float rp_ray = pow(abs(sin(rp_a * 3.0 + 0.7)), 6.0);
    float rp_glow = exp(-rp_out / 0.16) * (0.45 + 0.55 * rp_ray);
    float rp_fade = clamp((1.0 - rp_r) / 0.3, 0.0, 1.0);
    float3 rp_col = rpTintA * (rp_glow * rp_fade * 0.7);
    rp_col = rp_col + rpTintB * (exp(-rp_out / 0.05) * 0.6);

    """ + GraphStyleShaders.glowEnd

    // MARK: the axon

    /// A link as an axon, on GraphRibbonWriter's strip in its axon coding
    /// (GraphLinkArbor, every measure mirrored exactly): u = seed * 64 + 1
    /// + the distance from the END (the target's centre); v = ((length in
    /// 64ths * 16 + the target's membrane step) * 2 + the lit bit) plus the
    /// position across, the strip `rpHalf` either side all along.
    ///
    /// From the sender: the hillock, a trumpet-shaped cone of the soma's
    /// milky gel; a bare initial segment; the fibre, `rpFibre` round,
    /// shaded as a gel tube with the soma's fresnel rim, inside a soft,
    /// continuous myelin haze, tapering to 0.7 of it; bare again, then ONE
    /// bouton, joined by a smooth fillet and pressed flat on the membrane
    /// across a dark cleft (additive: the cleft is simply unlit), with a
    /// warm active zone facing it and a faint density on the membrane
    /// opposite. Nothing else along it.
    ///
    /// An impulse lights the hillock as the axon fires, runs down as a
    /// white-hot front over an amber wake with a magenta halo bleeding
    /// through the myelin, and reaches the bouton's back at pos 1 - at
    /// NeuronImpulse's arrival time; the bouton flashes and swells a
    /// little, and transmitter glows in the cleft. Tint A the fibre, B the
    /// impulse, C its halo; `rpRate` the chance a slot fires (0: no
    /// impulses, nothing worked out), `rpBurst` the chance a firing is a
    /// burst; `rpPixel` a point's size at unit depth (a hairline stays a
    /// point wide, fainter, however far away); `rpDetail` 0 (Smooth): no
    /// bursts, swell, halo, active zone, density or transmitter.
    static let axon: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;
    float rpDetail;
    float rpRate;
    float rpBurst;
    float rpHalf;
    float rpFibre;
    float rpPixel;
    float3 rpTintA;
    float3 rpTintB;
    float3 rpTintC;

    #pragma body
    float2 rp_uv = _surface.diffuseTexcoord;
    float rp_seed = floor(rp_uv.x / 64.0);
    float rp_dE = rp_uv.x - rp_seed * 64.0 - 1.0;
    float rp_k = floor(rp_uv.y);
    float rp_q2 = floor(rp_k * 0.5);
    float rp_lit = rp_k - 2.0 * rp_q2;
    float rp_q16 = floor(rp_q2 / 16.0);
    float rp_lvl = rp_q2 - 16.0 * rp_q16;
    float rp_len = (rp_q16 + 0.5) / 64.0;
    float rp_a = max(rp_len - rp_dE, 0.0);
    float rp_y = (rp_uv.y - rp_k - 0.5) * (rpHalf / 0.498);
    float rp_ay = abs(rp_y);
    float rp_f = rpFibre;
    float rp_t = rpClock * rpMotion;
    float rp_px = max(-_surface.position.z, 0.001) * rpPixel;

    float rp_R = 0.05 * exp(rp_lvl * 0.14842);
    float rp_Rk = 1.7 * rp_f;
    float rp_cl = 0.55 * rp_f;
    float rp_F = rp_R + rp_cl;
    float rp_ck = rp_F + 0.78 * rp_Rk;
    float rp_kb = rp_ck + rp_Rk;
    float rp_Lref = max(rp_len - rp_kb, 0.05);

    float rp_pulse = 0.0;
    float rp_hot = 0.0;
    float rp_trig = 0.0;
    float rp_tp = 1000.0;
    if (rpRate > 0.0) {
        uint rp_su = uint(rp_seed);
        uint rp_h = rp_su * 747796405u + 2891336453u;
        rp_h = ((rp_h >> ((rp_h >> 28u) + 4u)) ^ rp_h) * 277803737u;
        rp_h = (rp_h >> 22u) ^ rp_h;
        float rp_P = 0.9 + 1.5 * (float(rp_h & 255u) / 255.0);
        float rp_D = 0.45 + 0.5 * (float((rp_h >> 8u) & 255u) / 255.0);
        float rp_ph = (float((rp_h >> 16u) & 255u) / 255.0) * rp_P;
        float rp_tt = rp_t + rp_ph;
        float rp_k0 = floor(rp_tt / rp_P);
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
                float rp_dx = rp_a - rp_pos * rp_Lref;
                float rp_fr = rp_dx / 0.045;
                float rp_head = exp(-rp_fr * rp_fr);
                float rp_tail = exp(rp_dx / 0.16);
                float rp_spk = rp_dx > 0.0 ? rp_head : rp_tail;
                float rp_fly = rp_on * step(0.0, rp_age) * (1.0 - smoothstep(1.0, 1.08, rp_pos));
                rp_pulse = rp_pulse + rp_spk * rp_fly;
                rp_hot = rp_hot + rp_head * rp_fly;
                rp_trig = rp_trig + rp_on * step(0.0, rp_age) * exp(-max(rp_age, 0.0) / 0.09);
                float rp_since = rp_age - rp_D;
                if (rp_on > 0.5 && rp_since >= 0.0 && rp_since < rp_tp) {
                    rp_tp = rp_since;
                }
            }
        }
    }
    float rp_flash = step(rp_tp, 5.0) * exp(-rp_tp / 0.3);
    float rp_jig = rp_flash * rpMotion * rpDetail * smoothstep(0.0, 0.06, rp_tp);
    float rp_Rs = rp_Rk * (1.0 + 0.14 * rp_jig);

    float rp_Lh = 8.0 * rp_f;
    float rp_q = clamp(1.0 - rp_a / rp_Lh, 0.0, 1.0);
    float rp_hk = rp_q * rp_q * rp_q;
    float rp_tq = clamp((rp_a - rp_Lh) / max(rp_Lref - rp_Lh, rp_f), 0.0, 1.0);
    float rp_rf = rp_f * (1.0 - 0.3 * rp_tq);
    float rp_rt = rp_rf + 2.2 * rp_f * rp_hk;
    float rp_my = smoothstep(rp_Lh + 2.0 * rp_f, rp_Lh + 5.0 * rp_f, rp_a);
    rp_my = rp_my * smoothstep(rp_kb + 3.0 * rp_f, rp_kb + 8.0 * rp_f, rp_dE);

    float rp_rr = sqrt(rp_dE * rp_dE + rp_y * rp_y);
    float rp_sd = max(rp_ay - rp_rt, rp_ck - rp_dE);
    float rp_kn = 0.0;
    if (rp_dE < rp_kb + 6.0 * rp_f) {
        float rp_kx = rp_dE - rp_ck;
        float rp_dk = sqrt(rp_kx * rp_kx + rp_y * rp_y) - rp_Rs;
        float rp_sk = max(rp_dk, rp_F - rp_rr);
        float rp_sm = 1.3 * rp_f;
        float rp_hh = clamp(0.5 + 0.5 * (rp_sd - rp_sk) / rp_sm, 0.0, 1.0);
        rp_sd = rp_sd + (rp_sk - rp_sd) * rp_hh - rp_sm * rp_hh * (1.0 - rp_hh);
        rp_kn = 1.0 - smoothstep(rp_ck, rp_kb + 1.5 * rp_f, rp_dE);
    }
    float rp_sc = rp_rt + (0.8 * rp_Rs - rp_rt) * rp_kn;
    float rp_wf = max(rp_sc, 0.6 * rp_px);
    float rp_dim = rp_sc / rp_wf;
    float rp_sw = rp_sd - (rp_wf - rp_sc);
    float rp_aa = max(0.08 * rp_wf, 0.5 * rp_px);
    float rp_in = 1.0 - smoothstep(-rp_aa, rp_aa, rp_sw);
    float rp_dd = clamp(-rp_sw / rp_wf, 0.0, 1.0);
    float rp_mu = sqrt(rp_dd * (2.0 - rp_dd));
    float rp_rim = pow(1.0 - rp_mu, 2.4) * smoothstep(0.0, 0.18, rp_mu) * rp_in;

    float rp_cw = max(0.42 * rp_rf, 0.5 * rp_px);
    float rp_cx = rp_ay / rp_cw;
    float rp_ax = exp(-rp_cx * rp_cx) * (0.42 * rp_rf / rp_cw) * (1.0 - rp_kn);
    float rp_hz = rp_ay / (2.0 * rp_f);
    float rp_haze = exp(-rp_hz * rp_hz) * rp_my;

    float rp_halo = 0.0;
    float rp_az = 0.0;
    float rp_psd = 0.0;
    float rp_nt = 0.0;
    if (rpDetail > 0.5) {
        float rp_out = max(rp_sw, 0.0);
        rp_halo = exp(-rp_out / (0.9 * rp_f)) * (1.0 - rp_kn);
        if (rp_dE < rp_kb + 2.0 * rp_f) {
            float rp_zq = (rp_dE - rp_F - 0.3 * rp_Rs) / (0.32 * rp_Rs);
            float rp_zy = rp_ay / (0.8 * rp_Rs);
            rp_zy = rp_zy * rp_zy;
            rp_az = rp_kn * rp_in * exp(-rp_zq * rp_zq - rp_zy * rp_zy);
            float rp_fa = rp_ay / (0.95 * rp_Rk);
            float rp_face = exp(-rp_fa * rp_fa * rp_fa * rp_fa);
            float rp_mb = (rp_rr - (rp_R - 0.25 * rp_cl)) / (0.35 * rp_cl + 0.002);
            rp_psd = exp(-rp_mb * rp_mb) * rp_face;
            float rp_cr = (rp_rr - (rp_R + 0.5 * rp_cl)) / (0.55 * rp_cl + 0.002);
            rp_nt = rp_flash * smoothstep(0.0, 0.05, rp_tp) * exp(-rp_cr * rp_cr) * rp_face;
        }
    }

    float rp_fill = rp_hk * (1.0 - rp_kn);
    float rp_soma = max(min(rp_hk * 1.6, 1.0), rp_kn);
    float rp_body = mix(0.07 + 0.13 * rp_mu, 0.13 + 0.24 * rp_mu, rp_soma);
    rp_body = rp_body + rp_kn * (0.1 + 0.22 * rp_mu);
    float rp_gel = (rp_body * rp_in + 0.65 * rp_rim) * rp_dim + 0.24 * rp_ax;
    float3 rp_milk = rpTintA * 0.55 + float3(0.3, 0.33, 0.4);
    float3 rp_col = rpTintA * rp_gel + rp_milk * (0.1 * rp_haze);
    rp_col = rp_col + (rpTintA * 0.5 + float3(0.3, 0.26, 0.14)) * (0.45 * rp_az);
    rp_col = rp_col + rpTintA * (0.22 * rp_psd);

    float rp_tube = (0.6 * rp_mu * rp_in + 0.3 * rp_rim) * rp_dim;
    float rp_core = rp_tube * (1.0 - rp_kn) + 0.7 * rp_ax;
    float rp_imp = min(rp_pulse, 1.5);
    float rp_wh = min(rp_hot, 1.0);
    rp_col = rp_col + rpTintB * (rp_imp * (1.1 * rp_core + 0.3 * rp_haze));
    rp_col = rp_col + float3(0.5, 0.48, 0.42) * (rp_wh * rp_core);
    rp_col = rp_col + (rpTintB * 0.5 + rpTintC * 0.5) * (rp_imp * rp_halo * 0.45);
    float3 rp_warm = rpTintB + float3(0.2, 0.2, 0.2);
    float rp_cone = (rp_mu * rp_in + 0.5 * rp_rim) * rp_dim;
    rp_col = rp_col + rp_warm * (0.8 * min(rp_trig, 1.0) * rp_fill * rp_cone);
    float rp_kf = rp_flash * rp_kn * (rp_mu * rp_in + 0.6 * rp_rim) * rp_dim;
    rp_col = rp_col + (rp_warm + rpTintC * 0.2) * (0.3 * rp_kf);
    rp_col = rp_col + rpTintB * (0.8 * rp_flash * rp_az);
    rp_col = rp_col + (rpTintB * 0.6 + rpTintC * 0.5) * (0.9 * rp_nt);
    rp_col = rp_col * (1.0 + 0.45 * rp_lit);
    rp_col = rp_col * smoothstep(0.0, 1.2 * rp_f, rp_a);

    """ + GraphStyleShaders.glowEnd
}
