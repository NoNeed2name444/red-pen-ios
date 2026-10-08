import Foundation

// The Neurons theme's shader modifiers (GraphNeuronLook builds the materials
// and checks they compile; GraphNeurons plans what they dress).
//
// The look is the close-up neuron the owner circled on the design board:
// a cell is a glass sphere holding a nucleus - a solid violet ball, not a
// light: shaded from the upper left, mottled with chromatin, darker clumps
// under its crisp lavender envelope, a denser nucleolus to one side - in
// dark violet cytoplasm with golden strokes and sparkles, wrapped in uneven
// golden filament light, inside a faint glass envelope with white-blue
// edges and a slowly breathing membrane; glass dendrites taper out of it,
// golden light inside them near the body, and one glass axon swells out
// of it at a hillock and runs, golden-white light inside it, beaded at
// the nodes of Ranvier, to one synapse (GraphLinkArbor): a golden bouton -
// stem, neck, one wide shallow cup - touching the next cell's blue glass
// membrane across a thin cleft, golden sparks round it; action potentials
// run along them at each axon's own random times (NeuronImpulse, mirrored
// here exactly), and on reaching the cup send transmitter across its
// cleft.
//
// They follow the Space's rules (GraphStyleShaders): surface modifiers write
// the final colour into `_surface.diffuse` (constant lighting, added to
// what is behind), designed as it shows on screen and taken into linear
// space at the end; time is `rpClock` times `rpMotion` (0 with Reduce
// Motion, when no impulse runs: the chosen note's axons glow steadily
// and their synapses stay lit instead); `rpProbe` is added at the end so a modifier that fails to
// compile is caught; no helper functions. The two geometry modifiers
// (the membrane's wobble, the dendrites' sway) read their own clock,
// `rpSway`, set by NeuronImpulses each frame - an argument is never
// declared by two modifiers of one material. `rpDetail` 0 (the Smooth
// budget) drops the sparkles, the strands and the bursts. Fine detail
// fades with a cell's size on screen (1 / its radius in pixels), so a far
// cell is a clean violet disc in a gold ring and a glass edge, never
// shimmering noise.
//
// Per-cell variety needs no per-cell material: every cell's soma and arbor
// are turned at random when built, so the sparkles and wobble fall
// differently on each, and the gold's lobes and the breathing's phase
// come from where it is.

nonisolated enum NeuronShaders {
    // MARK: the soma

    /// A cell body on a unit sphere (the node scaled to its size), drawn by
    /// how far from its middle each pixel looks (0 the middle, 1 the edge),
    /// after the owner's close-up, its glowing heart swapped at the owner's
    /// word for a real nucleus: dark violet glass cytoplasm (NeuronPalette
    /// .interior, a touch of .heart and of tint A, the membrane dye) round
    /// a nucleus - a solid ball, shaded from the upper left (no glow of its
    /// own), its chromatin mottled in .heart and .interior with darker
    /// clumps under the envelope, a thin lavender envelope with pores, and
    /// a nucleolus (tint B) to one side; short strokes swirling round it
    /// (violet near it, gold toward the edge) and a few sparkles in depth,
    /// in the cytoplasm only; at the limb golden filament light in lobes
    /// that blaze in places, white-hot on their crests, with golden glints
    /// (tint C); then a thin white-blue glass rim, a faint violet sheen
    /// inside it and a wet highlight. `rpNucleus` (0: none - a part and a
    /// vesicle are clear) sets the nucleus's size. `rpState` its state
    /// (NeuronState.code): firing flickers hotter, a pacemaker brightens
    /// on each beat (twice a turn of NeuronState.beatPeriod, with its
    /// halo), releasing crowds golden glints round the edge, engulfing
    /// darkens the heart to a phagosome. `rpFill` how much of the violet
    /// shows and how bright the gold is (NeuronCellKind.fill: thin in a
    /// part and a vesicle); `rpOpen` (0 closed, 1 open, eased between)
    /// opens a container so what floats inside shows: the strokes and
    /// sparkles go, the violet thins to a glassy disc and the nucleus
    /// swells to hold the cell's parts (the owner asked for the
    /// subfolders in the nucleus; GraphNeurons.openNucleus, its parts
    /// inside it and its notes in the cytoplasm round it), its chromatin
    /// thinning and its nucleolus fading so the parts show through.
    /// `rpMembrane` 1 (a whole cell, wrapped in its membrane with its
    /// dendrites - NeuronShaders.membrane) leaves the edge to the membrane:
    /// no rim of its own, and its limb gold fading out at the edge, where
    /// the membrane carries the gold on into the dendrites.
    static let soma: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;
    float rpDetail;
    float rpNucleus;
    float rpState;
    float rpOpen;
    float rpFill;
    float rpMembrane;
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

    float rp_r = sqrt(rp_q);
    float rp_t = rpClock * rpMotion;
    float rp_ph = dot(scn_node.modelTransform[3].xyz, float3(1.7, 2.3, 1.1));
    float rp_pz = fract(rp_ph * 0.13) * 40.0;
    float rp_px = 1.0 / max(2000.0 * rp_R / max(-rp_c.z, 0.0001), 1.0);
    float rp_fine = 1.0 - smoothstep(0.025, 0.07, rp_px);
    float rp_tiny = 1.0 - smoothstep(0.016, 0.04, rp_px);
    float2 rp_sd = rp_off.xy / max(length(rp_off.xy), 0.00001);
    float rp_lit = 0.5 + 0.5 * dot(rp_sd, float2(-0.6, 0.8));
    float rp_a = atan2(rp_sd.y, rp_sd.x);
    float rp_gel = rpFill * (1.0 - 0.8 * rpOpen);
    float rp_fire = step(0.5, rpState) * step(rpState, 1.5);
    float rp_vesk = step(1.5, rpState) * step(rpState, 2.5);
    float rp_pace = step(2.5, rpState) * step(rpState, 3.5);
    float rp_eat = step(4.5, rpState);
    float rp_fl = 0.5 + 0.5 * sin(rp_t * 17.0 + rp_ph * 5.0) * sin(rp_t * 7.3 + rp_ph);
    float rp_beat = fract((rp_t / 1.5 + fract(rp_ph * 0.37)) * 2.0);
    float rp_bp = exp(-rp_beat * 6.0) * rpMotion;

    float rp_inV = 1.0 - smoothstep(0.78, 0.99, rp_r);
    float3 rp_vio = mix(float3(0.2, 0.07, 0.46) * 0.6, float3(0.52, 0.24, 0.98) * 0.5, 0.15);
    rp_vio = mix(rp_vio, rpTintA, 0.06);

    """ + GraphShaderKit.noise("rp_mn", "float3(rp_sd * (rp_r * 5.0), rp_pz + rp_t * 0.05)") + """
    float3 rp_col = rp_vio * (0.75 * rp_inV * rp_gel * (0.5 + rp_mn));

    float rp_has = step(0.01, rpNucleus);
    float rp_rn = mix(0.36 + 0.25 * rpNucleus, 0.6, rpOpen);
    float rp_nr = rp_r / rp_rn;
    float rp_aa = max(0.03, 1.5 * rp_px / rp_rn);
    float rp_inN = (1.0 - smoothstep(1.0 - rp_aa, 1.0, rp_nr)) * rp_has;
    float3 rp_nN = float3(rp_sd * rp_nr, sqrt(max(1.0 - rp_nr * rp_nr, 0.0)));
    float3 rp_L = normalize(float3(-0.45, 0.6, 0.66));
    float3 rp_H = normalize(rp_L + rp_V);
    float rp_dif = max(dot(rp_nN, rp_L), 0.0);
    float3 rp_pv = rp_nN * (rp_rn * rp_R);
    float3 rp_lq = float3(dot(rp_pv, rp_ax), dot(rp_pv, rp_ay), dot(rp_pv, rp_az)) / rp_R2;
    """ + GraphShaderKit.noise("rp_c1", "rp_lq * 7.0 + rp_pz")
        + GraphShaderKit.noise("rp_c2", "rp_lq * 16.0 + 3.1 + rp_pz") + """
    float rp_chrom = 0.6 * rp_c1 + 0.4 * rp_c2;
    float rp_dark = clamp(0.8 * smoothstep(0.44, 0.66, rp_chrom) + 0.7 * smoothstep(0.62, 0.97, rp_nr) * smoothstep(0.4, 0.62, rp_c2), 0.0, 1.0);
    float3 rp_ncol = mix(float3(0.52, 0.24, 0.98) * 0.62, float3(0.2, 0.07, 0.46) * 0.75, rp_dark) * ((0.22 + 0.78 * rp_dif) * (0.85 + 0.3 * rp_c2) * (1.0 - 0.62 * rpOpen));
    float2 rp_o = (rp_sd * rp_nr - float2(0.3, 0.2)) / 0.32;
    float rp_or = length(rp_o);
    float rp_inO = 1.0 - smoothstep(1.0 - rp_aa / 0.32, 1.0, rp_or);
    float3 rp_oN = float3(rp_o, sqrt(max(1.0 - rp_or * rp_or, 0.0)));
    float3 rp_ocol = rpTintB * (0.42 * (0.3 + 0.7 * max(dot(rp_oN, rp_L), 0.0)) * (0.8 + 0.4 * rp_c2));
    rp_ncol = mix(rp_ncol, rp_ocol, rp_inO * 0.9 * (1.0 - rpOpen));
    float rp_ew = max(0.035, 1.2 * rp_px / rp_rn);
    float rp_env = 1.0 - smoothstep(0.0, rp_ew, abs(rp_nr - 1.0 + rp_ew));
    float rp_pore = 0.55 + 0.45 * smoothstep(-0.2, 0.4, cos(rp_a * 26.0 + 2.0 * rp_c1));
    rp_col = mix(rp_col, rp_ncol, rp_inN);
    rp_col = rp_col + float3(0.78, 0.66, 1.0) * (0.85 * rp_env * rp_pore * (0.55 + 0.45 * rp_lit) * rp_has);
    rp_col = rp_col + float3(0.85, 0.8, 1.0) * ((0.22 - 0.14 * rpOpen) * pow(max(dot(rp_nN, rp_H), 0.0), 40.0) * rp_inN);
    float rp_cyto = 1.0 - rp_has * (1.0 - smoothstep(rp_rn + 0.01, rp_rn + 0.06, rp_r));

    float rp_warm = smoothstep(0.45, 0.85, rp_r);
    float rp_sa = (rp_a + 3.14159265 + rp_t * 0.02) * 9.549297;
    float rp_sr = rp_r * 26.0;
    float2 rp_sc = floor(float2(rp_sa, rp_sr));
    float rp_sk = fract(sin(dot(rp_sc, float2(12.9898, 78.233)) + rp_pz) * 43758.5453);
    float rp_du = (rp_sa - rp_sc.x - fract(rp_sk * 7.13) * 0.4 - 0.3) * 0.10471976 * rp_r;
    float rp_dv = (rp_sr - rp_sc.y - fract(rp_sk * 3.71) * 0.5 - 0.25) * 0.0384615;
    float rp_sl = length(float2(rp_du / max(0.028, 3.0 * rp_px), rp_dv / max(0.0065, rp_px)));
    float rp_stroke = (1.0 - smoothstep(0.3, 1.0, rp_sl)) * step(0.72 - 0.3 * rp_warm, rp_sk);
    rp_stroke = rp_stroke * smoothstep(0.12, 0.3, rp_r) * (1.0 - smoothstep(0.93, 0.99, rp_r)) * (0.5 + 0.5 * sin(rp_t * 1.3 + rp_sk * 50.0));
    float3 rp_stc = mix(float3(0.7, 0.5, 1.0), float3(1.0, 0.6, 0.22), rp_warm);
    rp_col = rp_col + rp_stc * (1.1 * rp_stroke * rp_cyto * rp_gel * rp_tiny * rpDetail * (1.0 - rpOpen));

    float rp_dots = 0.0;
    for (int rp_k = 0; rp_k < 3; rp_k++) {
        float3 rp_pt = rp_off + rp_d * ((float(rp_k) - 1.0) * 0.5 * rp_thick * rp_R);
        float3 rp_lp = float3(dot(rp_pt, rp_ax), dot(rp_pt, rp_ay), dot(rp_pt, rp_az)) / rp_R2;
        float3 rp_g = rp_lp * 9.0 + float3(float(rp_k) * 3.7, rp_t * 0.06, 0.0);
        float3 rp_gi = floor(rp_g);
        float rp_gh = fract(sin(dot(rp_gi, float3(12.9898, 78.233, 37.719))) * 43758.5453);
        float3 rp_gj = float3(rp_gh, fract(rp_gh * 7.13), fract(rp_gh * 3.71)) * 0.5 + float3(0.25, 0.25, 0.25);
        float rp_gl = length(rp_g - rp_gi - rp_gj);
        float rp_gd = 1.0 - smoothstep(0.0, 0.3, rp_gl);
        rp_gd = rp_gd * rp_gd + 2.0 * (1.0 - smoothstep(0.0, 0.07, rp_gl));
        rp_dots = rp_dots + rp_gd * step(0.68, rp_gh) * (0.6 + 0.4 * sin(rp_t * 1.7 + rp_gh * 40.0));
    }
    float3 rp_spark = mix(float3(0.88, 0.74, 1.0), float3(1.0, 0.8, 0.5), rp_warm);
    rp_col = rp_col + rp_spark * (0.9 * rp_dots * rp_cyto * rp_inV * rp_gel * (1.0 - rpOpen) * rp_tiny * rpDetail);

    """ + GraphShaderKit.noise("rp_gn", "float3(rp_sd * 1.9, rp_pz + rp_t * 0.04)")
        + GraphShaderKit.noise("rp_fn", "float3(rp_sd * 2.6, rp_r * 18.0 - rp_t * 0.12 + rp_pz)")
        + GraphShaderKit.noise("rp_fm", "float3(rp_sd * 6.0 + 7.0, rp_r * 8.0 + rp_t * 0.07 + rp_pz)") + """
    float rp_ridge = 1.0 - abs(2.0 * rp_fn - 1.0);
    rp_ridge = rp_ridge * rp_ridge * rp_ridge;
    float rp_ridge2 = 1.0 - abs(2.0 * rp_fm - 1.0);
    float rp_fib = max(rp_ridge, 0.7 * rp_ridge2 * rp_ridge2);
    float rp_fib2 = rp_fib * rp_fib;
    float rp_band = smoothstep(0.62, 0.97, rp_r) * (1.0 - 0.5 * smoothstep(0.985, 1.0, rp_r)) * (1.0 - rpMembrane * smoothstep(0.88, 1.0, rp_r));
    float rp_lobe = smoothstep(0.25, 0.72, rp_gn);
    float rp_haze = rp_band * rp_lobe;
    float rp_fil = rp_band * (0.2 + 0.8 * rp_lobe) * rp_fib2 * rp_fine;
    float rp_crest = rp_haze * rp_fib2 * rp_fib2 * rp_fine;
    float rp_dim = (1.0 - 0.3 * rpOpen) * mix(0.6, 1.0, rpFill);
    rp_col = rp_col + float3(1.0, 0.42, 0.08) * (0.4 * rp_haze * rp_dim);
    rp_col = rp_col + float3(1.0, 0.62, 0.2) * (rp_fil * rp_dim);
    rp_col = rp_col + float3(1.0, 0.93, 0.75) * (0.75 * rp_crest * rp_dim);

    float rp_pa = (rp_a + 3.14159265) * 15.278875;
    float rp_pr = rp_r * 22.0;
    float2 rp_pc = floor(float2(rp_pa, rp_pr));
    float rp_pk = fract(sin(dot(rp_pc, float2(12.9898, 78.233)) + rp_pz) * 43758.5453);
    float2 rp_pj = float2(fract(rp_pk * 7.13), fract(rp_pk * 3.71)) * 0.5 + float2(0.25, 0.25);
    float rp_pd = 1.0 - smoothstep(0.0, 0.4, length(float2(rp_pa, rp_pr) - rp_pc - rp_pj));
    float rp_glint = rp_pd * rp_pd * step(0.72 - 0.35 * rp_vesk, rp_pk) * (0.55 + 0.45 * sin(rp_t * 2.1 + rp_pk * 60.0));
    rp_col = rp_col + rpTintC * (2.4 * rp_glint * smoothstep(0.5, 0.85, rp_r) * rp_tiny);

    float rp_rim = pow(1.0 - rp_mu, 7.0) * smoothstep(0.0, 0.12, rp_mu);
    rp_col = rp_col + mix(float3(0.66, 0.84, 1.0), rpTintA, 0.08) * (2.4 * rp_rim * (0.6 + 0.4 * rp_lit) * (1.0 - rpMembrane));
    rp_col = rp_col + float3(0.7, 0.45, 0.9) * (0.12 * (1.0 - rp_mu) * (1.0 - rp_mu) * (1.0 - smoothstep(0.9, 1.0, rp_r)));
    rp_col = rp_col + float3(0.8, 0.95, 1.0) * (0.4 * pow(max(dot(rp_N, rp_H), 0.0), 60.0));

    rp_col = rp_col * (1.0 + rp_fire * (0.25 + 0.3 * rp_fl) + rp_pace * 0.6 * rp_bp);
    rp_col = rp_col * (1.0 - rp_eat * 0.75 * rp_inV * smoothstep(0.1, 0.6, 1.0 - rp_r * 1.6));
    rp_col = rp_col * (1.0 + 0.06 * sin(rp_t * 0.9 + rp_ph));

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

    /// The dendritic arbor's glass tubes (u runs 0 at the soma to 1 at the
    /// tip, v round the tube), as in the owner's close-up: an even
    /// white-blue edge the whole way, a faint violet body, golden streaks
    /// running along inside (filament noise stretched along the tube,
    /// drifting out with the clock), gold particles drifting out with them,
    /// the cell's tint A at the base, golden sparkles (on a grid in the
    /// arbor's own space, so they stay put on the tube) when the cell is big
    /// on screen; it fades out over the last part, so a dendrite reads as
    /// running on into the dark, and nothing shows over the nucleus, so the
    /// cell's middle stays clear.
    static let arbor: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;
    float rpDetail;
    float3 rpTintA;

    #pragma body
    float rp_t = rpClock * rpMotion;
    float3 rp_N = normalize(_surface.normal);
    float3 rp_V = normalize(_surface.view);
    float rp_mu = abs(dot(rp_N, rp_V));
    float rp_s = _surface.diffuseTexcoord.x;
    float rp_v = _surface.diffuseTexcoord.y;
    float4x4 rp_mv = scn_node.modelViewTransform;
    float3 rp_c = rp_mv[3].xyz;
    float rp_R = max(length(rp_mv[0].xyz), 0.0001);
    float3 rp_d = normalize(_surface.position);
    float3 rp_off = rp_d * dot(rp_c, rp_d) - rp_c;
    float rp_hide = smoothstep(0.8, 0.97, length(rp_off) / rp_R);
    float rp_px = 1.0 / max(2000.0 * rp_R / max(-rp_c.z, 0.0001), 1.0);
    float rp_tiny = 1.0 - smoothstep(0.016, 0.04, rp_px);
    float rp_rest = 1.0 - rp_mu;
    float rp_edge = rp_rest * rp_rest * smoothstep(0.0, 0.3, rp_mu);
    float3 rp_col = float3(0.62, 0.82, 1.0) * (1.6 * rp_edge);
    rp_col = rp_col + float3(0.24, 0.2, 0.6) * (0.18 * rp_mu);
    float rp_ang = rp_v * 6.2831853;
    """ + GraphShaderKit.noise("rp_fn", "float3(cos(rp_ang) * 2.6, sin(rp_ang) * 2.6, rp_s * 2.5 - rp_t * 0.15)") + """
    float rp_fil = 1.0 - abs(2.0 * rp_fn - 1.0);
    float rp_fil2 = rp_fil * rp_fil;
    rp_fil = rp_fil2 * rp_fil2 * rp_fil;
    float rp_warm = 1.0 - smoothstep(0.05, 0.85, rp_s);
    float3 rp_gold = mix(float3(1.0, 0.5, 0.12), float3(1.0, 0.86, 0.55), rp_fil);
    rp_col = rp_col + rp_gold * (rp_warm * rp_mu * (0.12 + 1.3 * rp_fil * rpDetail));
    float rp_pa = rp_v * 14.0;
    float rp_pr = rp_s * 30.0 - rp_t * 0.6;
    float rp_pcx = floor(rp_pa);
    float rp_pcy = floor(rp_pr);
    float rp_pk = fract(sin(rp_pcx * 12.9898 + rp_pcy * 78.233) * 43758.5453);
    float rp_pjx = fract(rp_pk * 7.13) * 0.5 + 0.25;
    float rp_pjy = fract(rp_pk * 3.71) * 0.5 + 0.25;
    float rp_pd = 1.0 - smoothstep(0.0, 0.35, length(float2(rp_pa - rp_pcx - rp_pjx, rp_pr - rp_pcy - rp_pjy)));
    float rp_part = rp_pd * rp_pd * step(0.7, rp_pk) * rp_mu;
    rp_col = rp_col + float3(1.0, 0.62, 0.2) * (1.6 * rp_part * (1.0 - smoothstep(0.2, 0.95, rp_s)) * rpDetail * rp_tiny);
    float3 rp_rel = _surface.position - rp_c;
    float3 rp_lp = float3(dot(rp_rel, rp_mv[0].xyz), dot(rp_rel, rp_mv[1].xyz), dot(rp_rel, rp_mv[2].xyz)) / (rp_R * rp_R);
    float3 rp_g = rp_lp * 12.0;
    float3 rp_gi = floor(rp_g);
    float rp_gh = fract(sin(dot(rp_gi, float3(12.9898, 78.233, 37.719))) * 43758.5453);
    float3 rp_gj = float3(rp_gh, fract(rp_gh * 7.13), fract(rp_gh * 3.71)) * 0.5 + float3(0.25, 0.25, 0.25);
    float rp_gd = 1.0 - smoothstep(0.0, 0.3, length(rp_g - rp_gi - rp_gj));
    rp_col = rp_col + float3(1.0, 0.9, 0.62) * (1.4 * rp_gd * rp_gd * step(0.86, rp_gh) * (1.0 - 0.6 * rp_s) * rpDetail * rp_tiny);
    rp_col = rp_col + rpTintA * (0.6 * rp_mu * (1.0 - smoothstep(0.0, 0.3, rp_s)));
    rp_col = rp_col * (smoothstep(0.0, 0.12, rp_s) * (1.0 - smoothstep(0.6, 1.0, rp_s)) * rp_hide);

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

    // MARK: the membrane

    /// A whole cell's membrane (GraphNeuronMembrane): its soma and
    /// dendrites one closed glass surface, as the owner asked ("one entity,
    /// not multiple stitched things"). Texture u is the share along a
    /// dendrite (0 on the soma), v how much of it is soma (1 on the soma,
    /// 0 out along a dendrite, between in the webbing where one leaves the
    /// body). One white-blue edge runs unbroken round the body and every
    /// dendrite - the soma's thin crisp rim (lit from the upper left)
    /// where v is 1, easing into the dendrites' wider one; the dendrites'
    /// look grows in as v falls: a faint violet body, golden streaks
    /// running out along them (filament noise round the crown's axis, so
    /// it streams from the body out along each dendrite, drifting out with
    /// the clock), gold particles drifting with them, tint A where they
    /// leave the body, golden sparkles on a grid in the cell's own space
    /// when it is big on screen, a wet highlight. The soma's shader keeps
    /// the body's middle (rpMembrane: no rim of its own), so nothing here
    /// draws over the nucleus; each dendrite fades out over its last
    /// part, running on into the dark.
    static let membrane: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;
    float rpDetail;
    float3 rpTintA;

    #pragma body
    float rp_t = rpClock * rpMotion;
    float3 rp_N = normalize(_surface.normal);
    float3 rp_V = normalize(_surface.view);
    float rp_mu = abs(dot(rp_N, rp_V));
    float rp_s = _surface.diffuseTexcoord.x;
    float rp_w = clamp(_surface.diffuseTexcoord.y, 0.0, 1.0);
    float rp_den = 1.0 - rp_w;
    float4x4 rp_mv = scn_node.modelViewTransform;
    float3 rp_c = rp_mv[3].xyz;
    float rp_R = max(length(rp_mv[0].xyz), 0.0001);
    float rp_px = 1.0 / max(2000.0 * rp_R / max(-rp_c.z, 0.0001), 1.0);
    float rp_tiny = 1.0 - smoothstep(0.016, 0.04, rp_px);
    float3 rp_rel = _surface.position - rp_c;
    float3 rp_lp = float3(dot(rp_rel, rp_mv[0].xyz), dot(rp_rel, rp_mv[1].xyz), dot(rp_rel, rp_mv[2].xyz)) / (rp_R * rp_R);
    float2 rp_sd = rp_rel.xy / max(length(rp_rel.xy), 0.00001);
    float rp_lit = 0.5 + 0.5 * dot(rp_sd, float2(-0.6, 0.8));
    float rp_rest = 1.0 - rp_mu;
    float rp_soft = 1.6 * rp_rest * rp_rest * smoothstep(0.0, 0.3, rp_mu);
    float rp_crisp = 2.4 * pow(rp_rest, 7.0) * smoothstep(0.0, 0.12, rp_mu) * (0.6 + 0.4 * rp_lit);
    float3 rp_col = mix(float3(0.62, 0.82, 1.0), float3(0.66, 0.84, 1.0), rp_w) * mix(rp_soft, rp_crisp, rp_w);
    rp_col = rp_col + float3(0.24, 0.2, 0.6) * (0.18 * rp_mu * rp_den);
    float rp_rho = max(length(rp_lp.xy), 0.0001);
    float2 rp_az = rp_lp.xy / rp_rho;
    """ + GraphShaderKit.noise("rp_fn", "float3(rp_az * 14.0, rp_s * 2.5 - rp_t * 0.15)") + """
    float rp_fil = 1.0 - abs(2.0 * rp_fn - 1.0);
    float rp_fil2 = rp_fil * rp_fil;
    rp_fil = rp_fil2 * rp_fil2 * rp_fil;
    float rp_warm = 1.0 - smoothstep(0.05, 0.85, rp_s);
    float3 rp_gold = mix(float3(1.0, 0.5, 0.12), float3(1.0, 0.86, 0.55), rp_fil);
    rp_col = rp_col + rp_gold * (rp_warm * rp_mu * rp_den * (0.12 + 1.3 * rp_fil * rpDetail));
    float rp_pa = (atan2(rp_az.y, rp_az.x) + 3.14159265) * 15.915494;
    float rp_pr = rp_s * 30.0 - rp_t * 0.6;
    float rp_pcx = floor(rp_pa);
    float rp_pcy = floor(rp_pr);
    float rp_pk = fract(sin(rp_pcx * 12.9898 + rp_pcy * 78.233) * 43758.5453);
    float rp_pjx = fract(rp_pk * 7.13) * 0.5 + 0.25;
    float rp_pjy = fract(rp_pk * 3.71) * 0.5 + 0.25;
    float rp_pd = 1.0 - smoothstep(0.0, 0.35, length(float2(rp_pa - rp_pcx - rp_pjx, rp_pr - rp_pcy - rp_pjy)));
    float rp_part = rp_pd * rp_pd * step(0.7, rp_pk) * rp_mu * rp_den;
    rp_col = rp_col + float3(1.0, 0.62, 0.2) * (1.6 * rp_part * (1.0 - smoothstep(0.2, 0.95, rp_s)) * rpDetail * rp_tiny);
    float3 rp_g = rp_lp * 12.0;
    float3 rp_gi = floor(rp_g);
    float rp_gh = fract(sin(dot(rp_gi, float3(12.9898, 78.233, 37.719))) * 43758.5453);
    float3 rp_gj = float3(rp_gh, fract(rp_gh * 7.13), fract(rp_gh * 3.71)) * 0.5 + float3(0.25, 0.25, 0.25);
    float rp_gd = 1.0 - smoothstep(0.0, 0.3, length(rp_g - rp_gi - rp_gj));
    rp_col = rp_col + float3(1.0, 0.9, 0.62) * (1.4 * rp_gd * rp_gd * step(0.86, rp_gh) * (1.0 - 0.6 * rp_s) * rp_den * rpDetail * rp_tiny);
    rp_col = rp_col + rpTintA * (0.6 * rp_mu * rp_den * (1.0 - smoothstep(0.0, 0.3, rp_s)));
    float3 rp_H = normalize(normalize(float3(-0.45, 0.6, 0.66)) + rp_V);
    rp_col = rp_col + float3(0.8, 0.95, 1.0) * (0.3 * pow(max(dot(rp_N, rp_H), 0.0), 60.0) * rp_den);
    rp_col = rp_col * (1.0 - smoothstep(0.6, 1.0, rp_s));

    """ + GraphStyleShaders.glowEnd

    /// The membrane moving in the fluid, eased by how much of it is soma
    /// (texture v): where it is soma it breathes as the soma's wobble does
    /// (the same wave, along the normal, so the two stay one), where it is
    /// dendrite it sways as the arbor's tubes did, more the further out
    /// from the body.
    static let membraneSway: String = """
    #pragma arguments
    float rpSway;
    float rpWobble;

    #pragma body
    float3 rp_p = _geometry.position.xyz;
    float rp_w = clamp(_geometry.texcoords[0].y, 0.0, 1.0);
    float rp_r = length(rp_p);
    float rp_ph = dot(scn_node.modelTransform[3].xyz, float3(1.3, 0.7, 1.9));
    float rp_a = sin(rp_p.x * 3.1 + rpSway * 1.3 + rp_ph);
    float rp_b = sin(rp_p.y * 2.7 - rpSway * 0.9 + rp_ph * 0.5);
    float rp_c = sin(rp_p.z * 3.7 + rpSway * 1.1 + rp_p.x * 1.3);
    float rp_br = (rp_a * rp_b * 0.6 + rp_c * 0.4) * rpWobble * rp_w;
    float rp_sx = sin(rpSway * 0.8 + rp_p.y * 1.7 + rp_ph);
    float rp_sy = sin(rpSway * 0.6 + rp_p.z * 1.9 + rp_ph * 1.3);
    float rp_sz = sin(rpSway * 0.7 + rp_p.x * 1.5 + rp_ph * 0.7);
    float3 rp_s = float3(rp_sx, rp_sy, rp_sz) * (rpWobble * 4.0 * max(rp_r - 0.9, 0.0) * (1.0 - rp_w));
    _geometry.position.xyz = rp_p + _geometry.normal * rp_br + rp_s;
    """

    // MARK: glows

    /// The light round a cell, on a billboard 5 cell radii across (the
    /// membrane at 0.4 of its half side): one faint, gold-leaning glow with
    /// the cell (tint A), its brightest at the membrane, reaching only a
    /// little way in (so the glass and the nucleus stay clear) and fading
    /// softly out past the edge with no seam; tint C draws the chosen
    /// cell's thin ring. `rpState`
    /// (NeuronState.code) adds the cell's process, each moving on the
    /// shaders' clock, its phase from where the cell is:
    ///
    /// - firing: rays of calcium waves flickering round it, and a ring
    ///   spreading out at each spike;
    /// - releasing: a cloud of transmitter in slow swirling bands, vesicles
    ///   drifting out through it;
    /// - pacemaker: a beat twice a turn (the pulsar's period): the glow
    ///   brightens, a ring wave runs out, two lobes sweep round;
    /// - migrating: the growth cone's filopodia, feeling about;
    /// - engulfing: arms of debris spiralling in to a bright lip at the
    ///   membrane, the phagosome dark inside (the soma's).
    static let halo: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;
    float rpGain;
    float rpState;
    float3 rpTintA;
    float3 rpTintC;

    #pragma body

    """ + GraphStyleShaders.plane + """
    float rp_t = rpClock * rpMotion;
    float rp_e = 0.4;
    float rp_out = max(rp_r - rp_e, 0.0);
    float rp_outside = step(rp_e, rp_r);
    float rp_soft = exp(-rp_out / 0.08) * 0.13;
    float rp_wide = exp(-rp_out / 0.26) * 0.07;
    float rp_within = 0.2 * smoothstep(0.75 * rp_e, rp_e, rp_r);
    float rp_lum = (rp_soft + rp_wide) * rp_outside + rp_within * (1.0 - rp_outside);
    float3 rp_col = rpTintA * (rp_lum * rpGain);
    float rp_ph = dot(scn_node.modelTransform[3].xyz, float3(1.7, 2.3, 1.1));
    float rp_a = atan2(rp_qy, rp_qx);
    if (rpState > 0.5 && rpState < 1.5) {
    float rp_sp = fract(rp_t * 0.9 + fract(rp_ph));
    float rp_rd0 = (rp_r - rp_e - rp_sp * 0.55) / 0.025;
    float rp_ring = exp(-rp_rd0 * rp_rd0) * (1.0 - rp_sp) * rp_outside;
    float rp_rw = 0.5 + 0.5 * sin(rp_a * 11.0 + rp_ph * 3.0 + sin(rp_a * 3.0 + rp_t) * 1.5);
    float rp_rays = rp_rw * rp_rw * rp_rw;
    rp_rays = rp_rays * rp_rays;
    float rp_flick = 0.75 + 0.25 * sin(rp_t * 17.0 + rp_ph * 5.0) * sin(rp_t * 7.3 + rp_ph);
    rp_col = rp_col + rpTintA * (rp_rays * exp(-rp_out / 0.22) * 0.22 * rp_flick * rp_outside);
    rp_col = rp_col + float3(1.0, 0.85, 0.55) * (rp_ring * 0.55);
    } else if (rpState > 1.5 && rpState < 2.5) {

    """ + GraphShaderKit.noise("rp_cn", "float3(cos(rp_a) * 2.0, sin(rp_a) * 2.0, rp_r * 4.0 - rp_t * 0.25)") + """
    float rp_band = 0.5 + 0.5 * sin(rp_r * 24.0 - rp_t * 0.8 + rp_cn * 4.0);
    float rp_cloud = exp(-rp_out / 0.33) * (0.18 + 0.4 * rp_band * rp_cn) * rp_outside;
    float rp_vq = rp_r * 12.0 - rp_t * 0.5;
    float rp_vi = floor(rp_vq);
    float rp_vw = (rp_a + 3.14159) * 3.0;
    float rp_vh = fract(sin(rp_vi * 12.9898 + floor(rp_vw) * 78.233 + rp_ph) * 43758.5453);
    float rp_vf = fract(rp_vq) - 0.5;
    float rp_vg = fract(rp_vw) - 0.5;
    float rp_ves = exp(-(rp_vf * rp_vf + rp_vg * rp_vg) * 60.0) * step(0.62, rp_vh) * rp_outside;
    rp_col = rp_col + mix(rpTintA, float3(1.0, 0.78, 0.45), 0.35) * rp_cloud;
    rp_col = rp_col + float3(1.0, 0.9, 0.72) * (rp_ves * 0.45 * exp(-rp_out / 0.4));
    } else if (rpState > 2.5 && rpState < 3.5) {
    float rp_turn = rp_t / 1.5 + fract(rp_ph * 0.37);
    float rp_bt = fract(rp_turn * 2.0);
    float rp_wd = (rp_r - rp_e - rp_bt * 0.5) / 0.02;
    float rp_wave = exp(-rp_wd * rp_wd) * (1.0 - rp_bt) * rp_outside;
    float rp_lc = cos(rp_a - rp_turn * 6.2831853);
    float rp_lobe = rp_lc * rp_lc;
    rp_lobe = rp_lobe * rp_lobe * rp_lobe;
    rp_lobe = rp_lobe * rp_lobe * exp(-rp_out / 0.3) * rp_outside;
    rp_col = rp_col * (1.0 + 0.8 * exp(-rp_bt * 6.0) * rpMotion);
    rp_col = rp_col + float3(0.75, 0.85, 1.0) * (rp_wave * 0.65 + rp_lobe * 0.5);
    } else if (rpState > 3.5 && rpState < 4.5) {
    float rp_fw = 0.5 + 0.5 * sin(rp_a * 9.0 + sin(rp_t * 0.7 + rp_ph) * 2.0);
    float rp_fil = rp_fw * rp_fw * rp_fw;
    rp_fil = rp_fil * rp_fil;
    rp_col = rp_col + rpTintA * (rp_fil * exp(-rp_out / 0.12) * 0.4 * rp_outside);
    } else if (rpState > 4.5) {
    float rp_lr = log(max(rp_r, 0.05));
    float rp_spin = rp_a + rp_lr * 3.0 + rp_t * 0.9;
    float rp_ac = 0.5 + 0.5 * cos(rp_spin * 2.0);
    float rp_arm = rp_ac * rp_ac * rp_ac;
    rp_arm = rp_arm * rp_arm;
    float rp_fall = exp(-rp_out / 0.3) * rp_outside;
    float rp_dq = rp_lr * 9.0 + rp_t * 1.3;
    float rp_dg = fract(rp_dq) - 0.5;
    float rp_dw = (rp_spin + 3.14159) * 2.5;
    float rp_dh = fract(sin(floor(rp_dq) * 7.13 + floor(rp_dw) * 3.7) * 43758.5453);
    float rp_da = fract(rp_dw) - 0.5;
    float rp_deb = exp(-(rp_dg * rp_dg + rp_da * rp_da) * 40.0) * step(0.55, rp_dh) * rp_fall;
    float rp_rr = (rp_r - rp_e * 1.06) / 0.012;
    float rp_lip = exp(-rp_rr * rp_rr);
    rp_col = rp_col + float3(0.95, 0.6, 1.0) * (rp_arm * rp_fall * 0.3 + rp_deb * 0.6 + rp_lip * 0.45);
    }
    float rp_fade = clamp((1.0 - rp_r) / 0.25, 0.0, 1.0);
    rp_col = rp_col * rp_fade;
    float rp_rd = (rp_r - 0.47) / 0.014;
    rp_col = rp_col + rpTintC * (exp(-rp_rd * rp_rd) * rp_fade);

    """ + GraphStyleShaders.glowEnd

    /// An impulse arriving: the receiving cell lights up from within, on a
    /// billboard 7 radii across (the membrane at 0.286): a hot core at its
    /// middle (tint B) inside a soft glow spreading past the membrane
    /// (tint A). The node's opacity carries how much (NeuronImpulses).
    static let arrival: String = """
    #pragma arguments
    float rpProbe;
    float3 rpTintA;
    float3 rpTintB;

    #pragma body

    """ + GraphStyleShaders.plane + """
    float rp_e = 0.286;
    float rp_out = max(rp_r - rp_e, 0.0);
    float rp_fade = clamp((1.0 - rp_r) / 0.3, 0.0, 1.0);
    float3 rp_col = rpTintA * (exp(-rp_out / 0.12) * rp_fade * 0.4);
    rp_col = rp_col + rpTintB * (exp(-rp_r / 0.18) * 0.5);

    """ + GraphStyleShaders.glowEnd

    // MARK: the axon

    /// A link as an axon, on GraphRibbonWriter's strip in its synapse
    /// coding (GraphLinkArbor): u = (width step * 32 + seed) * 64 + 1 +
    /// distance from the END (the target's centre), the width step
    /// (GraphRibbonWriter.widthStep, 0...7) following the sender's size; v = ((length in eighths * 16 + the target's
    /// membrane step) * 2 + the lit bit) plus the position across. The
    /// strip widens over its last stretch (the same ramp as the writer's)
    /// to hold its one synapse: the fibre loses its myelin, narrows into a
    /// thin stem, swells into a wet neck and flares into one wide, shallow
    /// gel cup - a golf tee - whose front follows the membrane across a
    /// thin dark cleft, its rim thicker and softly wobbling on the link's
    /// own phase, golden-white vesicles inside, a faint blue density on the
    /// membrane facing it. An impulse runs down to the cup's back, landing
    /// at NeuronImpulse's arrival time; the cup brightens, bulges and
    /// settles like jelly, and cyan transmitter glows across the cleft and
    /// spreads along the membrane from the cup's rim. As the owner asked
    /// (a link is one of the cell's own dendrites, prolonged), the fibre
    /// is a thick glass tube drawn as NeuronShaders.arbor draws a
    /// dendrite: a white-blue edge that glints along it and a soft blue
    /// haze outside, a faint violet body, gold filaments crackling inside
    /// and a warm middle (tint A, the cup's gold too) near the sender,
    /// fading to dark glass beyond, golden sparks drifting in it, and
    /// golden sparks spraying round the bouton; tint B the impulse, C its
    /// halo. It flows out of the body: a trumpet three times its width
    /// under the membrane, narrowing over its first stretch, its outline
    /// hidden over the soma and nothing faded beyond it; the myelin barely
    /// beads it. Each axon is a single fibre (`rpBundle` 0;
    /// 1 would draw three, gathered before the stem); `rpHalf` the
    /// strip's base half width, times the width step's
    /// (0.12 * exp(step * 0.300105));
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
    float rp_code = floor(rp_uv.x / 64.0);
    float rp_dE = rp_uv.x - rp_code * 64.0 - 1.0;
    float rp_wk = floor(rp_code / 32.0);
    float rp_seed = rp_code - 32.0 * rp_wk;
    float rp_hw = rpHalf * 0.12 * exp(rp_wk * 0.300105);
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
    float rp_fw = rp_hw * mix(0.3, 0.2, rpBundle);
    float rp_cl = 0.3 * rp_fw;
    float rp_F = rp_R + rp_cl;
    float rp_th0 = 0.55 * rp_fw;
    float rp_Wc = max(min(2.6 * rp_fw, 0.42 * rp_F - 0.75 * rp_th0), 0.25 * rp_fw);
    float rp_Bk = rp_F + rp_th0;
    float rp_Nk = 1.4 * rp_Wc;
    float rp_D1 = rp_Bk + rp_Nk + 0.02;
    float rp_D0 = rp_D1 + 0.5 * rp_R + 4.0 * rp_fw;
    float rp_We = max(rp_Wc + 1.5 * rp_th0 + 3.0 * rp_fw, rp_hw);
    float rp_ramp = clamp((rp_D0 - rp_dE) / max(rp_D0 - rp_D1, 0.0001), 0.0, 1.0);
    float rp_W = rp_hw + (rp_We - rp_hw) * rp_ramp;
    float rp_y = rp_s * rp_W;
    float rp_Lref = max(rp_len - rp_Bk, 0.05);

    float rp_mq = rp_along / max(4.5 * rp_fw, 0.15) + rp_seed * 0.37;
    float rp_m = fract(rp_mq) - 0.5;
    float rp_myel = clamp((rp_dE - rp_D1 - rp_Nk) / 0.15, 0.0, 1.0);
    float rp_node = exp(-rp_m * rp_m / 0.003) * rp_myel;
    float rp_hill = 1.0 + 2.0 * exp(-rp_along / (0.35 * rp_hw));
    float rp_conv = clamp((rp_dE - rp_D0) / 0.4, 0.0, 1.0);
    float rp_lane = 0.42 * rp_hw * rpBundle * rp_conv;
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
    float rp_still = (1.0 - rpMotion) * rp_lit;
    float rp_act = step(0.0, rp_tau) * step(rp_tau, 5.0) * rpMotion;
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

    float rp_cap = 1.0 - 0.05 * rp_myel * (0.5 + 0.5 * cos(rp_m * 6.2831853));
    float rp_wm = rp_fw * rp_hill * (1.0 - 0.15 * rp_node) * rp_cap * mix(0.42, 1.0, rp_stem) + 0.00001;
    float rp_xm = rp_dm / rp_wm + (1.0 - step(rp_Bk + rp_Nk, rp_dE)) * 1000.0;
    float rp_x = min(rp_xm, rp_xt);
    float rp_tube = sqrt(max(1.0 - rp_x * rp_x, 0.0));
    float rp_halo = exp(-max(rp_x - 1.0, 0.0) * 1.6) * (1.0 - rp_cleft);

    float rp_in = 1.0 - smoothstep(0.92, 1.08, rp_x);
    float rp_imp = min(rp_pulse * rpMotion * (1.0 + 0.7 * rp_node), 1.6) * rp_in;
    rp_imp = max(rp_imp, 0.5 * rp_still * rp_in);
    float rp_flash = rp_tee * max(rp_act * exp(-rp_tp / 0.25), 0.6 * rp_still);
    float rp_warm = 1.0 - smoothstep(0.3 * rp_hw, 1.6 * rp_hw, rp_along);
    float rp_ein = smoothstep(0.15 * rp_hw, 0.4 * rp_hw, rp_along);
    float rp_sheath = 1.0 - rp_tube;
    float rp_edge = rp_sheath * rp_sheath * smoothstep(0.0, 0.3, rp_tube) * rp_in * rp_ein;

    """ + GraphShaderKit.noise("rp_en", "float3(rp_along / (1.6 * rp_fw), sign(rp_y) * 3.0 + rp_seed, 0.5 + rp_t * 0.05)") + """
    float3 rp_ecol = mix(float3(0.62, 0.82, 1.0), float3(1.0, 0.86, 0.55), 1.0 - rp_stem);
    float3 rp_col = rp_ecol * (2.0 * rp_edge * (0.65 + 0.7 * rp_en));
    float rp_haze = exp(-max(rp_x - 1.0, 0.0) * 5.0) * (1.0 - rp_in) * rp_ein * rp_stem;
    rp_col = rp_col + float3(0.5, 0.7, 1.0) * (0.22 * rp_haze);
    rp_col = rp_col + float3(0.24, 0.2, 0.6) * (0.18 * rp_tube * rp_in);
    float rp_fa = asin(clamp(rp_y / rp_wm, -1.0, 1.0));

    """ + GraphShaderKit.noise("rp_fn", "float3(cos(rp_fa) * 2.6, sin(rp_fa) * 2.6, rp_along / (2.2 * rp_fw) - rp_t * 0.15)") + """
    float rp_fil = 1.0 - abs(2.0 * rp_fn - 1.0);
    float rp_fil2 = rp_fil * rp_fil;
    rp_fil = rp_fil2 * rp_fil2 * rp_fil;
    float3 rp_gold = mix(float3(1.0, 0.5, 0.12), float3(1.0, 0.86, 0.55), rp_fil);
    rp_col = rp_col + rp_gold * (rp_tube * rp_in * (0.015 + 0.06 * rp_warm + (0.12 + rp_warm) * rp_fil * rpDetail));
    float rp_glow = exp(-rp_x * rp_x * 3.0);
    rp_col = rp_col + rpTintA * ((0.02 + 0.12 * rp_warm) * rp_glow * rp_in);
    float2 rp_kc = float2((rp_along - rp_t * 0.08) / (rp_fw * 0.8), rp_y / rp_wm * 2.0 + 2.0);
    float2 rp_ki = floor(rp_kc);
    float rp_kh = fract(sin(dot(rp_ki, float2(12.9898, 78.233)) + rp_seed * 3.1) * 43758.5453);
    float2 rp_kf = rp_kc - rp_ki - (float2(fract(rp_kh * 7.13), fract(rp_kh * 3.71)) * 0.5 + float2(0.25, 0.25));
    float rp_kd = 1.0 - smoothstep(0.0, 0.3, length(rp_kf));
    rp_col = rp_col + float3(1.0, 0.88, 0.55) * (0.9 * rp_kd * rp_kd * step(0.82, rp_kh) * (0.6 + 0.4 * sin(rp_t * 2.3 + rp_kh * 50.0)) * rpDetail * rp_in);
    rp_col = rp_col + rpTintA * (0.35 * rp_tee + 0.25 * rp_cupIn);
    rp_col = rp_col + float3(1.0, 0.92, 0.7) * (0.3 * min(rp_ves, 1.0) * rp_cupIn);
    rp_col = rp_col + float3(0.35, 0.9, 1.0) * (0.35 * rp_psd + 0.1 * rp_cleft);
    rp_col = rp_col + float3(0.5, 0.95, 1.0) * (0.8 * rp_nt);
    float2 rp_zc = float2(rp_dE, rp_y) / (rp_Wc * 0.35);
    float2 rp_zi = floor(rp_zc);
    float rp_zh = fract(sin(dot(rp_zi, float2(12.9898, 78.233)) + rp_seed * 1.7) * 43758.5453);
    float2 rp_zf = rp_zc - rp_zi - (float2(fract(rp_zh * 7.13), fract(rp_zh * 3.71)) * 0.5 + float2(0.25, 0.25));
    float rp_zd = 1.0 - smoothstep(0.0, 0.3, length(rp_zf));
    float rp_spray = rp_zd * rp_zd * step(0.85, rp_zh) * exp(-max(rp_dE - rp_D1, 0.0) / (rp_Wc * 1.5)) * (1.0 - rp_in) * step(rp_R, rp_rr) * rpDetail;
    rp_col = rp_col + rpTintA * (1.1 * rp_spray * (0.55 + 0.45 * sin(rp_t * 2.9 + rp_zh * 70.0)));
    float rp_core = exp(-rp_x * rp_x * 1.5);
    rp_col = rp_col + rpTintB * (rp_imp * (0.95 * rp_core + 0.12));
    rp_col = rp_col + rpTintC * (rp_imp * rp_halo * 0.35);
    float3 rp_hot = rpTintB + rpTintC * 0.5;
    rp_col = rp_col + rp_hot * (0.4 * rp_flash);
    rp_col = rp_col * (1.0 + 0.45 * rp_lit);
    rp_col = rp_col * smoothstep(0.0, 0.3 * rp_hw, rp_along);

    """ + GraphStyleShaders.glowEnd

    // MARK: the bridge

    /// A link as one dendrite joining two cells (GraphLinkBridge), as the
    /// owner asked ("use dendrites and extend them / make the tube
    /// connected both ways"), on GraphRibbonWriter's strip in its bridge
    /// coding: u = (width step * 32 + seed) * 64 + 1 + distance from the
    /// strip's start, v = (length in sixteenths * 2 + the lit bit) plus
    /// the position across. The strip is the outline itself, flaring out
    /// of each cell's body as the membrane's dendrites do, so across it is
    /// a glass tube whatever its width there: the membrane's white-blue
    /// edge, crisp like the soma's where it leaves a body and softening
    /// into a dendrite's along the flare, a faint violet body, gold
    /// filaments running along it, strong near both cells (as the
    /// membrane's dendrites are near the body) and faint between, golden
    /// sparks drifting in it, tint A where it leaves each body; the body
    /// fades in over its first stretch from each end, where it lies over
    /// the cell's own glass, its edge running on to the cell's. An
    /// impulse runs from the first cell to the second, reaching the
    /// strip's end at NeuronImpulse's arrival time (tint B, tint C its
    /// halo); no myelin, synapse or cup, the same at both ends. `rpHalf`
    /// the strip's base half width, times the width step's
    /// (0.12 * exp(step * 0.300105)); `rpRate` the chance a slot fires,
    /// `rpBurst` the chance a firing is a burst; `rpDetail` 0 (Smooth) no
    /// filaments or sparks.
    static let bridge: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;
    float rpDetail;
    float rpRate;
    float rpBurst;
    float rpHalf;
    float3 rpTintA;
    float3 rpTintB;
    float3 rpTintC;

    #pragma body
    float2 rp_uv = _surface.diffuseTexcoord;
    float rp_code = floor(rp_uv.x / 64.0);
    float rp_along = max(rp_uv.x - rp_code * 64.0 - 1.0, 0.0);
    float rp_wk = floor(rp_code / 32.0);
    float rp_seed = rp_code - 32.0 * rp_wk;
    float rp_hw = rpHalf * 0.12 * exp(rp_wk * 0.300105);
    float rp_k = floor(rp_uv.y);
    float rp_q2 = floor(rp_k * 0.5);
    float rp_lit = rp_k - 2.0 * rp_q2;
    float rp_len = max(rp_q2 / 16.0 + 0.03125, 0.05);
    float rp_s = clamp(fract(rp_uv.y) * 2.0 - 1.0, -1.0, 1.0);
    float rp_t = rpClock * rpMotion;
    float rp_dE = max(rp_len - rp_along, 0.0);
    float rp_end = min(rp_along, rp_dE);

    float rp_mu = sqrt(max(1.0 - rp_s * rp_s, 0.0));
    float rp_rest = 1.0 - rp_mu;
    float rp_w = 1.0 - smoothstep(0.0, 2.0 * rp_hw, rp_end);
    float rp_soft = 1.6 * rp_rest * rp_rest * smoothstep(0.0, 0.3, rp_mu);
    float rp_crisp = 1.9 * pow(rp_rest, 7.0) * smoothstep(0.0, 0.12, rp_mu);
    float3 rp_col = mix(float3(0.62, 0.82, 1.0), float3(0.66, 0.84, 1.0), rp_w) * mix(rp_soft, rp_crisp, rp_w);
    float rp_body = smoothstep(0.0, 1.2 * rp_hw, rp_end);
    rp_col = rp_col + float3(0.24, 0.2, 0.6) * (0.18 * rp_mu * rp_body);
    float rp_warm = 1.0 - smoothstep(0.5 * rp_hw, 5.0 * rp_hw, rp_end);
    float rp_fa = asin(rp_s);

    """ + GraphShaderKit.noise("rp_fn", "float3(cos(rp_fa) * 2.6, sin(rp_fa) * 2.6, rp_along / (1.6 * rp_hw) - rp_t * 0.15)") + """
    float rp_fil = 1.0 - abs(2.0 * rp_fn - 1.0);
    float rp_fil2 = rp_fil * rp_fil;
    rp_fil = rp_fil2 * rp_fil2 * rp_fil;
    float3 rp_gold = mix(float3(1.0, 0.5, 0.12), float3(1.0, 0.86, 0.55), rp_fil);
    float rp_glint = 0.02 + rp_warm * (0.1 + 1.1 * rp_fil * rpDetail) + 0.12 * rp_fil * rpDetail;
    rp_col = rp_col + rp_gold * (rp_glint * rp_mu * rp_body);
    float2 rp_kc = float2((rp_along - rp_t * 0.08) / (rp_hw * 0.8), rp_s * 2.0 + 2.0);
    float2 rp_ki = floor(rp_kc);
    float rp_kh = fract(sin(dot(rp_ki, float2(12.9898, 78.233)) + rp_seed * 3.1) * 43758.5453);
    float2 rp_kf = rp_kc - rp_ki - (float2(fract(rp_kh * 7.13), fract(rp_kh * 3.71)) * 0.5 + float2(0.25, 0.25));
    float rp_kd = 1.0 - smoothstep(0.0, 0.3, length(rp_kf));
    rp_col = rp_col + float3(1.0, 0.88, 0.55) * (0.9 * rp_kd * rp_kd * step(0.82, rp_kh) * (0.6 + 0.4 * sin(rp_t * 2.3 + rp_kh * 50.0)) * rpDetail * rp_body);
    rp_col = rp_col + rpTintA * (0.6 * rp_mu * rp_body * (1.0 - smoothstep(0.0, 3.0 * rp_hw, rp_end)));

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
            float rp_dx = rp_along - rp_pos * rp_len;
            float rp_fr = rp_dx / 0.08;
            float rp_head = exp(-rp_fr * rp_fr);
            float rp_tail = exp(rp_dx / 0.45);
            float rp_spk = rp_dx > 0.0 ? rp_head : rp_tail;
            float rp_fly = step(0.0, rp_age) * (1.0 - smoothstep(1.0, 1.15, rp_pos));
            rp_pulse = rp_pulse + rp_on * rp_spk * rp_fly;
        }
    }
    float rp_still = (1.0 - rpMotion) * rp_lit;
    float rp_imp = max(min(rp_pulse * rpMotion, 1.6), 0.5 * rp_still);
    float rp_core = exp(-rp_s * rp_s * 1.5);
    rp_col = rp_col + rpTintB * (rp_imp * (0.95 * rp_core + 0.12) * rp_body);
    rp_col = rp_col + rpTintC * (rp_imp * 0.35 * rp_body);
    rp_col = rp_col * (1.0 + 0.45 * rp_lit);

    """ + GraphStyleShaders.glowEnd
}
