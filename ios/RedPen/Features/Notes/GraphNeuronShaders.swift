import Foundation

// The Neurons theme's shader modifiers (GraphNeuronLook builds the materials
// and checks they compile; GraphNeurons plans what they dress).
//
// The look is live-cell fluorescence microscopy: cells glow on a dark tissue
// background, their membranes brightest just inside the edge, a jelly body
// whose glow deepens where there is more of it to look through, a nucleus
// and nucleolus seen through it, faint organelles, a wet highlight, and the
// whole membrane slowly breathing and wobbling. Axons are soft gel fibres
// with myelin sheaths beaded at the nodes of Ranvier, each ending in one
// synapse (GraphLinkArbor): a gel golf tee - stem, wet neck, one wide
// shallow cup hugging the target's membrane across a thin dark cleft;
// action potentials run along them at each axon's own random times
// (NeuronImpulse, mirrored here exactly), and on reaching the cup send
// transmitter across its cleft.
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
// budget) drops the organelles, the dendrites' beads and the bursts.
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

    /// A link as an axon, on GraphRibbonWriter's strip in its synapse
    /// coding (GraphLinkArbor): u = seed * 64 + 1 + distance from the END
    /// (the target's centre); v = ((length in eighths * 16 + the target's
    /// membrane step) * 2 + the lit bit) plus the position across. The
    /// strip widens over its last stretch (the same ramp as the writer's)
    /// to hold its one synapse: the fibre loses its myelin, narrows into a
    /// thin stem, swells into a wet neck and flares into one wide, shallow
    /// gel cup - a golf tee - whose front follows the membrane across a
    /// thin dark cleft, its rim thicker and softly wobbling on the link's
    /// own phase, vesicle specks inside, a faint bright density on the
    /// membrane facing it. An impulse runs down to the cup's back, landing
    /// at NeuronImpulse's arrival time; the cup brightens, bulges and
    /// settles like jelly, and transmitter glows across the cleft and
    /// spreads along the membrane from the cup's rim. Tint A the fibre, B
    /// the impulse, C its halo; `rpBundle` 1 draws a tract's three fibres,
    /// which gather before the stem; `rpHalf` the strip's base half width;
    /// `rpRate` the chance a slot fires, `rpBurst` the chance a firing is a
    /// burst; `rpDetail` 0 (Smooth) a plain cup, no wobble or bulge.
    static let axon: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;
    float rpDetail;
    float rpRate;
    float rpBurst;
    float rpBundle;
    float rpHalf;
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
    float rp_len = max(rp_q16 * 0.125 + 0.0625, 0.05);
    float rp_along = max(rp_len - rp_dE, 0.0);
    float rp_s = fract(rp_uv.y) * 2.0 - 1.0;
    float rp_t = rpClock * rpMotion;

    float rp_R = 0.05 * exp(rp_lvl * 0.14842);
    float rp_fw = rpHalf * mix(0.3, 0.2, rpBundle);
    float rp_cl = 0.3 * rp_fw;
    float rp_F = rp_R + rp_cl;
    float rp_th0 = 0.55 * rp_fw;
    float rp_Wc = max(min(2.6 * rp_fw, 0.42 * rp_F - 0.75 * rp_th0), 0.25 * rp_fw);
    float rp_Bk = rp_F + rp_th0;
    float rp_Nk = 1.4 * rp_Wc;
    float rp_D1 = rp_Bk + rp_Nk + 0.02;
    float rp_D0 = rp_D1 + 0.5 * rp_R + 4.0 * rp_fw;
    float rp_We = max(rp_Wc + 1.5 * rp_th0 + 3.0 * rp_fw, rpHalf);
    float rp_ramp = clamp((rp_D0 - rp_dE) / max(rp_D0 - rp_D1, 0.0001), 0.0, 1.0);
    float rp_W = rpHalf + (rp_We - rpHalf) * rp_ramp;
    float rp_y = rp_s * rp_W;
    float rp_Lref = max(rp_len - rp_Bk, 0.05);

    float rp_mq = rp_along / 0.55 + rp_seed * 0.37;
    float rp_m = fract(rp_mq) - 0.5;
    float rp_myel = clamp((rp_dE - rp_D1 - rp_Nk) / 0.15, 0.0, 1.0);
    float rp_node = exp(-rp_m * rp_m / 0.0016) * rp_myel;
    float rp_hill = 1.0 + 0.5 * exp(-rp_along / 0.12);
    float rp_conv = clamp((rp_dE - rp_D0) / 0.4, 0.0, 1.0);
    float rp_lane = 0.42 * rpHalf * rpBundle * rp_conv;
    float rp_d0 = abs(rp_y);
    float rp_d1 = abs(rp_y - rp_lane);
    float rp_d2 = abs(rp_y + rp_lane);
    float rp_dm = min(rp_d0, mix(rp_d0, min(rp_d1, rp_d2), rpBundle));

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
    float rp_a1 = 1000.0;
    float rp_a2 = 1000.0;
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
            float rp_dx = rp_along - rp_pos * rp_Lref;
            float rp_fr = rp_dx / 0.08;
            float rp_head = exp(-rp_fr * rp_fr);
            float rp_tail = exp(rp_dx / 0.45);
            float rp_spk = rp_dx > 0.0 ? rp_head : rp_tail;
            float rp_fly = step(0.0, rp_age) * (1.0 - smoothstep(1.0, 1.15, rp_pos));
            rp_pulse = rp_pulse + rp_on * rp_spk * rp_fly;
            if (rp_on > 0.5 && rp_age >= 0.0) {
                if (rp_age < rp_a1) {
                    rp_a2 = rp_a1;
                    rp_a1 = rp_age;
                } else if (rp_age < rp_a2) {
                    rp_a2 = rp_age;
                }
            }
        }
    }

    float rp_tau1 = rp_a1 - rp_D;
    float rp_tau2 = rp_a2 - rp_D;
    float rp_tau = rp_tau1 >= 0.0 ? rp_tau1 : rp_tau2;
    float rp_act = step(0.0, rp_tau) * step(rp_tau, 5.0);
    float rp_tp = max(rp_tau, 0.0);

    float rp_jig = rp_act * rpMotion * rpDetail * exp(-rp_tp / 0.28) * cos(rp_tp * 16.0);
    float rp_sw = 1.0 + 0.3 * rp_jig;
    float rp_Wj = rp_Wc * (1.0 + 0.1 * rp_jig);
    float rp_vc = clamp(rp_y, -rp_Wj, rp_Wj);
    float rp_vr = rp_vc / rp_Wj;
    float rp_lip = rp_vr * rp_vr;
    float rp_th = rp_th0 * rp_sw * (0.8 + (0.3 + 0.3 * rpDetail) * rp_lip);
    float rp_wob = rpMotion * rpDetail * 0.1 * rp_Wc * sin(rp_t * 1.4 + rp_seed * 2.3 + rp_vr * 2.3);
    float rp_fc = sqrt(max(rp_F * rp_F - rp_vc * rp_vc, 0.0)) - 0.25 * rp_th0 * rp_jig - rp_wob * rp_lip;
    float rp_du = rp_dE - (rp_fc + 0.5 * rp_th);
    float rp_dv = rp_y - rp_vc;
    float rp_xc = sqrt(rp_du * rp_du + rp_dv * rp_dv) / (0.5 * rp_th);

    float rp_ns = clamp((rp_Bk + rp_Nk - rp_dE) / rp_Nk, 0.0, 1.0);
    float rp_nb2 = (rp_ns - 0.72) / 0.2;
    float rp_neckw = rp_fw * 0.42 + 0.55 * rp_Wc * rp_ns * rp_ns + 0.12 * rp_Wc * rpDetail * exp(-rp_nb2 * rp_nb2);
    float rp_back = max(rp_dE - (rp_Bk + rp_Nk), 0.0);
    float rp_xn = sqrt(rp_y * rp_y + rp_back * rp_back) / rp_neckw + (1.0 - step(rp_Bk - 0.5 * rp_th0, rp_dE)) * 1000.0;
    float rp_stem = smoothstep(rp_Bk + rp_Nk, rp_Bk + 2.0 * rp_Nk, rp_dE);
    float rp_xt = min(rp_xc, rp_xn);
    float rp_cupIn = sqrt(max(1.0 - rp_xc * rp_xc, 0.0));
    float rp_tee = sqrt(max(1.0 - rp_xt * rp_xt, 0.0));

    float rp_ves = 0.0;
    if (rpDetail > 0.5 && rp_xc < 1.2) {
        for (int rp_v = 0; rp_v < 5; rp_v++) {
            float rp_vs = (float(rp_v) - 2.0) * 0.38 * rp_Wc + 0.05 * rp_Wc * sin(rp_seed * 1.7 + float(rp_v) * 2.1);
            float rp_vu = sqrt(max(rp_F * rp_F - rp_vs * rp_vs, 0.0)) + 0.45 * rp_th0;
            float rp_vx = rp_dE - rp_vu;
            float rp_vy = rp_y - rp_vs;
            float rp_vd = sqrt(rp_vx * rp_vx + rp_vy * rp_vy) / (0.16 * rp_th0 + 0.1 * rp_fw);
            rp_ves = rp_ves + exp(-rp_vd * rp_vd);
        }
    }

    float rp_rr = sqrt(rp_dE * rp_dE + rp_y * rp_y);
    float rp_phi = abs(atan2(rp_y, rp_dE));
    float rp_ang = rp_Wc / rp_F;
    float rp_dp = rp_phi / rp_ang;
    float rp_face = exp(-rp_dp * rp_dp * rp_dp * rp_dp);
    float rp_mb = (rp_rr - (rp_R - 0.4 * rp_cl)) / (0.45 * rp_cl + 0.003);
    float rp_psd = exp(-rp_mb * rp_mb) * rp_face;
    float rp_cleft = step(rp_R, rp_rr) * step(rp_rr, rp_F) * rp_face;
    float rp_ntc = rp_act * exp(-rp_tp / 0.18) * smoothstep(0.0, 0.05, rp_tp);
    float rp_cr = (rp_rr - (rp_R + 0.5 * rp_cl)) / (0.6 * rp_cl + 0.002);
    float rp_nt = rp_ntc * exp(-rp_cr * rp_cr) * rp_face;
    float rp_sig = 0.12 + 1.6 * rp_tp;
    float rp_pd = max(rp_phi - rp_ang, 0.0) / rp_sig;
    float rp_pw = (rp_rr - (rp_R - 0.8 * rp_cl)) / (1.2 * rp_cl + 0.004 + 0.03 * rp_tp);
    float rp_patch = rp_act * smoothstep(0.03, 0.1, rp_tp) * exp(-rp_tp / 0.4);
    rp_nt = max(rp_nt, 1.4 * rp_patch * exp(-rp_pd * rp_pd) * exp(-rp_pw * rp_pw));

    float rp_wm = rp_fw * rp_hill * (1.0 - 0.1 * rp_node) * mix(0.42, 1.0, rp_stem) + 0.00001;
    float rp_xm = rp_dm / rp_wm + (1.0 - step(rp_Bk + rp_Nk, rp_dE)) * 1000.0;
    float rp_x = min(rp_xm, rp_xt);
    float rp_tube = sqrt(max(1.0 - rp_x * rp_x, 0.0));
    float rp_sheath = (rp_x - 0.82) / 0.16;
    float rp_edge = exp(-rp_sheath * rp_sheath) * (1.0 - 0.5 * rp_node);
    float rp_halo = exp(-max(rp_x - 1.0, 0.0) * 1.6) * (1.0 - rp_cleft);
    float rp_bead = 1.0 + 0.12 * rp_node;

    float rp_in = 1.0 - smoothstep(0.92, 1.08, rp_x);
    float rp_imp = min(rp_pulse * (1.0 + 0.7 * rp_node), 1.6) * rp_in;
    float rp_flash = rp_tee * rp_act * exp(-rp_tp / 0.25);
    float rp_fibre = (0.2 * rp_tube + 0.34 * rp_edge) * rp_in * rp_bead;
    float3 rp_col = rpTintA * (rp_fibre + 0.05 * rp_halo);
    rp_col = rp_col + rpTintA * (0.1 * rp_tee + 0.08 * rp_cupIn + 0.18 * rp_psd);
    rp_col = rp_col + (rpTintA * 0.6 + float3(0.25, 0.25, 0.25)) * (0.16 * min(rp_ves, 1.0) * rp_cupIn);
    float rp_core = exp(-rp_x * rp_x * 1.5);
    rp_col = rp_col + rpTintB * (rp_imp * (0.95 * rp_core + 0.12));
    rp_col = rp_col + rpTintC * (rp_imp * rp_halo * 0.35);
    float3 rp_hot = rpTintB + rpTintC * 0.5;
    rp_col = rp_col + rp_hot * (0.4 * rp_flash);
    rp_col = rp_col + (rpTintB * 0.55 + rpTintC * 0.45) * (0.8 * rp_nt);
    rp_col = rp_col * (1.0 + 0.45 * rp_lit);
    rp_col = rp_col * smoothstep(0.0, 0.04, rp_along);

    """ + GraphStyleShaders.glowEnd
}
