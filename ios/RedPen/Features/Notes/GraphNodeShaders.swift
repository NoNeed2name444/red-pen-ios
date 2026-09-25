import SceneKit
import UIKit
import Metal
import simd

// The node styles' shader modifiers (see GraphNodeStyles), and the check
// that they compile and draw on this device.
//
// They follow GraphShaders' rules: surface modifiers that write the final
// colour into `_surface.diffuse` (constant lighting), time from `rpClock`
// (GraphSim's wrapped clock) times `rpMotion` (0 with Reduce Motion, so the
// picture is still but whole), no helper functions, and `rpProbe` added at
// the end so GraphStyleProbe can tell a working modifier from a broken one.
// Each is mirrored statement for statement by the design mock
// (scratchpad mock/styles_lib.py).
//
// Per-note values that change every frame travel in the node's own
// transform, never in per-note materials, so every note of a style (and
// folder) shares one material:
//
// - a plane's z scale is free (a plane has no depth), so a disk, ring,
//   beam or tail carries one number as |z column| / |x column| - 1;
// - a sphere's z scale may differ from its x scale by a fraction of a
//   percent, invisible, carrying 0...1 as (|z| / |x| - 1) * 250;
// - a billboarded glow (inside the stretch that squashes it along the
//   motion) carries |z column| - 2, GraphStyleAnimator dividing out the
//   note's pop scale.
//
// Light: planets, moons, comets and rings are lit by the nearest suns
// (`rpSun0`...`rpSun3`: world position, w = 1 when there is a sun), each
// weighted by the inverse square of its distance, or by the key light
// `rpKey` (a world direction) when there are none - one terminator,
// sliding smoothly as a sun is dragged past.

nonisolated enum GraphStyleShaders {
    // MARK: shared pieces

    /// The light for a lit body: `rp_Lw` in the world, `rp_Lo` in the
    /// node's own frame, `rp_Lv` in view space; and `rp_v0`...`rp_v2`, the
    /// node's axes in view space.
    static let light: String = """
    float3 rp_wp = scn_node.modelTransform[3].xyz;
    float3 rp_L = rpKey * 0.0001;
    float3 rp_d0 = rpSun0.xyz - rp_wp;
    float rp_e0 = max(dot(rp_d0, rp_d0), 0.0001);
    rp_L = rp_L + rp_d0 * (rpSun0.w / (rp_e0 * sqrt(rp_e0)));
    float3 rp_d1 = rpSun1.xyz - rp_wp;
    float rp_e1 = max(dot(rp_d1, rp_d1), 0.0001);
    rp_L = rp_L + rp_d1 * (rpSun1.w / (rp_e1 * sqrt(rp_e1)));
    float3 rp_d2 = rpSun2.xyz - rp_wp;
    float rp_e2 = max(dot(rp_d2, rp_d2), 0.0001);
    rp_L = rp_L + rp_d2 * (rpSun2.w / (rp_e2 * sqrt(rp_e2)));
    float3 rp_d3 = rpSun3.xyz - rp_wp;
    float rp_e3 = max(dot(rp_d3, rp_d3), 0.0001);
    rp_L = rp_L + rp_d3 * (rpSun3.w / (rp_e3 * sqrt(rp_e3)));
    float3 rp_Lw = normalize(rp_L);
    float3 rp_m0 = normalize(scn_node.modelTransform[0].xyz);
    float3 rp_m1 = normalize(scn_node.modelTransform[1].xyz);
    float3 rp_m2 = normalize(scn_node.modelTransform[2].xyz);
    float3 rp_v0 = normalize(scn_node.modelViewTransform[0].xyz);
    float3 rp_v1 = normalize(scn_node.modelViewTransform[1].xyz);
    float3 rp_v2 = normalize(scn_node.modelViewTransform[2].xyz);
    float3 rp_Lo = float3(dot(rp_m0, rp_Lw), dot(rp_m1, rp_Lw), dot(rp_m2, rp_Lw));
    float3 rp_Lv = rp_v0 * rp_Lo.x + rp_v1 * rp_Lo.y;
    rp_Lv = normalize(rp_Lv + rp_v2 * rp_Lo.z);

    """

    static let lightArguments: String = """
    float4 rpSun0;
    float4 rpSun1;
    float4 rpSun2;
    float4 rpSun3;
    float3 rpKey;

    """

    /// A sphere's surface in its own frame (`rp_p`), its normal and view in
    /// view space, and mu = cos(angle to the eye). Needs `rp_v0`...`rp_v2`.
    static let sphere: String = """
    float3 rp_N = _surface.normal;
    float3 rp_V = _surface.view;
    float rp_mu = max(dot(rp_N, rp_V), 0.0);
    float3 rp_p = float3(dot(rp_v0, rp_N), dot(rp_v1, rp_N), dot(rp_v2, rp_N));
    rp_p = normalize(rp_p);

    """

    /// The axes alone, for a sphere that is not lit.
    static let axes: String = """
    float3 rp_v0 = normalize(scn_node.modelViewTransform[0].xyz);
    float3 rp_v1 = normalize(scn_node.modelViewTransform[1].xyz);
    float3 rp_v2 = normalize(scn_node.modelViewTransform[2].xyz);

    """

    /// A plane's coordinates, -1 to 1, y up.
    static let plane: String = """
    float2 rp_uv = _surface.diffuseTexcoord;
    float rp_qx = rp_uv.x * 2.0 - 1.0;
    float rp_qy = 1.0 - rp_uv.y * 2.0;
    float rp_r = length(float2(rp_qx, rp_qy)) + 0.00001;

    """

    /// A sphere's motion, 0 to 1, from its z scale.
    static let sphereMotion: String = """
    float rp_sx = length(scn_node.modelTransform[0].xyz);
    float rp_sz = length(scn_node.modelTransform[2].xyz);
    float rp_m = clamp((rp_sz / rp_sx - 1.0) * 250.0, 0.0, 1.0);

    """

    /// A plane's number, from its z scale.
    static let planeCode: String = """
    float rp_zx = length(scn_node.modelTransform[0].xyz);
    float rp_zz = length(scn_node.modelTransform[2].xyz);
    float rp_m = clamp(rp_zz / rp_zx - 1.0, 0.0, 1.0);

    """

    /// Ends a body's modifier: the colour, designed as it shows on screen
    /// (the mock), is taken into SceneKit's linear space; and the probe only
    /// paints white when the normal is really there.
    static let bodyEnd: String = """
    rp_col = pow(clamp(rp_col, float3(0.0), float3(1.0)), float3(2.2));
    float rp_ok = step(0.5, length(_surface.normal));
    _surface.diffuse = float4(rp_col + float3(rpProbe * rp_ok), 1.0);
    """

    /// Ends a glow's modifier, taking its colour into linear space too, so
    /// the screen shows what the mock shows.
    static let glowEnd: String = """
    rp_col = pow(max(rp_col, float3(0.0)), float3(2.2));
    _surface.diffuse = float4(rp_col + float3(rpProbe), 1.0);
    """

    // MARK: the link

    /// A link: GraphShaders.link's calm beam, plus what each end's style does
    /// to it. u = ((styleA * 8 + styleB) * 16 + seed) * 64 + 1 + distance
    /// along; v as before (length in sixteenths doubled, plus the lit bit,
    /// plus the position across). The A end is always the higher style
    /// code: suns and pulsars send, black holes swallow (GraphRibbons).
    ///
    /// - black hole: the beam narrows, reddens and fades into the horizon;
    ///   at a B end its core spirals in, its pulses speed up as they fall,
    ///   and each one flashes on arrival where the photon ring is;
    /// - sun: hotter and whiter near it; at an A end pulses leave it fast
    ///   and swollen, like ejected plasma, then slow;
    /// - rocky planet: bluer near it, and each arriving pulse glints;
    /// - gas giant: a wider haze, and a bar of light on its ring where the
    ///   beam meets it, brightening as pulses arrive;
    /// - pulsar: rings of blue-white run out along it, two per turn of its
    ///   beams (period GraphNodeStyle.pulsarPeriod);
    /// - comet: icy, with twinkling dust.
    static let link: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpEnergy;
    float rpSolid;
    float rpReach;
    float rpProbe;

    #pragma body
    float2 rp_uv = _surface.diffuseTexcoord;
    float rp_code = floor(rp_uv.x / 64.0);
    float rp_along = rp_uv.x - rp_code * 64.0 - 1.0;
    float rp_pair = floor(rp_code / 16.0);
    float rp_seed = rp_code - rp_pair * 16.0;
    float rp_sA = floor(rp_pair / 8.0);
    float rp_sB = rp_pair - rp_sA * 8.0;
    float rp_k = floor(rp_uv.y);
    float rp_spanQ = floor(rp_k * 0.5);
    float rp_lit = rp_k - 2.0 * rp_spanQ;
    float rp_len = rp_spanQ * 0.0625;
    float rp_toEnd = max(rp_len - rp_along, 0.0);
    float rp_s0 = fract(rp_uv.y) * 2.0 - 1.0;
    float rp_x = rp_along + rp_seed * 1.37;
    float rp_m = rpMotion;
    float rp_t = rpClock * rp_m;
    float rp_bhA = 1.0 - step(0.5, rp_sA);
    float rp_bhB = 1.0 - step(0.5, rp_sB);
    float rp_rkB = step(0.5, rp_sB) - step(1.5, rp_sB);
    float rp_gsB = step(1.5, rp_sB) - step(2.5, rp_sB);
    float rp_cmA = step(2.5, rp_sA) - step(3.5, rp_sA);
    float rp_cmB = step(2.5, rp_sB) - step(3.5, rp_sB);
    float rp_psA = step(3.5, rp_sA) - step(4.5, rp_sA);
    float rp_psB = step(3.5, rp_sB) - step(4.5, rp_sB);
    float rp_sunA = step(4.5, rp_sA);
    float rp_sunB = step(4.5, rp_sB);
    float rp_reach = max(rpReach, 0.05);
    float rp_nA = exp(-rp_along / rp_reach);
    float rp_nB = exp(-rp_toEnd / rp_reach);
    float rp_bhW = rp_bhA * rp_nA + rp_bhB * rp_nB;
    float rp_sunW = rp_sunA * rp_nA + rp_sunB * rp_nB;
    float rp_ejW = rp_sunA * rp_nA;
    float rp_cmW = rp_cmA * rp_nA + rp_cmB * rp_nB;
    float rp_rkW = rp_rkB * rp_nB;
    float rp_gsW = rp_gsB * rp_nB;

    float rp_dS = max(rp_toEnd, 0.02);
    float rp_turn = log(rp_dS / rp_reach) * 5.0 + rp_t * 4.0;
    float rp_amp = 0.42 * rp_bhB * rp_nB;
    rp_amp = rp_amp * smoothstep(0.0, 0.5 * rp_reach, rp_toEnd);
    float rp_s = rp_s0 - rp_amp * sin(rp_turn);
    float rp_a = abs(rp_s);
    float rp_a2 = rp_a * rp_a * (1.0 + 2.5 * rp_bhW);
    float rp_e = abs(rp_s0);
    float rp_w = clamp(1.0 - rp_e * rp_e, 0.0, 1.0);
    float rp_w2 = rp_w * rp_w;
    float rp_w3 = rp_w2 * rp_w;

    float rp_qD = rp_x * 0.35 - rp_t * 0.12 + rp_seed * 7.1;
    float rp_iD = floor(rp_qD);
    float rp_fD = fract(rp_qD);
    rp_fD = rp_fD * rp_fD * (3.0 - 2.0 * rp_fD);
    float rp_aD = fract(sin(rp_iD * 12.9898 + rp_seed * 3.7) * 43758.5453);
    float rp_bD = fract(sin((rp_iD + 1.0) * 12.9898 + rp_seed * 3.7) * 43758.5453);
    float rp_nD = mix(rp_aD, rp_bD, rp_fD);
    float rp_qV = rp_x * 0.5 + rp_t * 0.05 + rp_seed * 3.3;
    float rp_iV = floor(rp_qV);
    float rp_fV = fract(rp_qV);
    rp_fV = rp_fV * rp_fV * (3.0 - 2.0 * rp_fV);
    float rp_aV = fract(sin(rp_iV * 12.9898 + rp_seed * 5.1 + 17.0) * 43758.5453);
    float rp_bV = fract(sin((rp_iV + 1.0) * 12.9898 + rp_seed * 5.1 + 17.0) * 43758.5453);
    float rp_nV = mix(rp_aV, rp_bV, rp_fV);
    float rp_qH = rp_x * 0.45 - rp_t * 0.15 + rp_seed * 5.7;
    float rp_iH = floor(rp_qH);
    float rp_fH = fract(rp_qH);
    rp_fH = rp_fH * rp_fH * (3.0 - 2.0 * rp_fH);
    float rp_aH = fract(sin(rp_iH * 12.9898 + rp_seed * 1.9 + 31.0) * 43758.5453);
    float rp_bH = fract(sin((rp_iH + 1.0) * 12.9898 + rp_seed * 1.9 + 31.0) * 43758.5453);
    float rp_nH = mix(rp_aH, rp_bH, rp_fH);

    float rp_core = exp(-rp_a2 * 300.0) * rp_w;
    rp_core = max(rp_core, exp(-rp_a2 * 40.0) * rp_w * rpSolid);
    float rp_inner = exp(-rp_a2 * 14.0) * rp_w2;
    float rp_breath = 1.0 + 0.1 * rp_m * sin(rp_t * 1.0471976 + rp_seed * 2.3);
    float rp_thick = (0.7 + 0.5 * rp_nH) * rp_breath * (1.0 + 0.8 * rp_gsW);
    float rp_haze = exp(-rp_a2 * 3.0 / (rp_thick * rp_thick)) * rp_w3;
    rp_haze = rp_haze * (0.16 + 0.22 * rp_nD);
    rp_haze = rp_haze * (1.0 + 1.5 * rp_sunW + 1.5 * rp_gsW);

    float rp_fall = 0.75 * rp_bhB * rp_reach;
    float rp_throw = 0.6 * rp_sunA * rp_reach;
    float rp_gone = exp(-rp_len / rp_reach);
    float rp_X = rp_x - rp_fall * (rp_nB - rp_gone);
    rp_X = rp_X - rp_throw * (1.0 - rp_nA);
    float rp_pp = rp_X * 0.3 - rp_t * 0.42 + rp_seed * 0.618;
    float rp_pi = floor(rp_pp);
    float rp_dw = (fract(rp_pp) - 0.5) / 0.3;
    float rp_sig = mix(0.7, 0.4, smoothstep(-0.2, 0.2, rp_dw));
    float rp_pz = rp_dw / rp_sig;
    float rp_ph = fract(sin(rp_pi * 7.13 + rp_seed) * 43758.5453);
    float rp_pulse = exp(-rp_pz * rp_pz) * (0.45 + 0.55 * rp_ph) * rp_m;
    rp_pulse = rp_pulse * (1.0 + 1.2 * rp_ejW);
    float rp_sp = rp_X * 0.13 - rp_t * 0.31 + rp_seed * 0.37;
    float rp_si = floor(rp_sp);
    float rp_sw = (fract(rp_sp) - 0.5) / 0.13;
    float rp_ssig = mix(1.0, 0.5, smoothstep(-0.3, 0.3, rp_sw));
    float rp_sz = rp_sw / rp_ssig;
    float rp_sh = fract(sin(rp_si * 3.31 + rp_seed * 1.7) * 43758.5453);
    float rp_surge = exp(-rp_sz * rp_sz) * smoothstep(0.55, 0.9, rp_sh) * rp_m;
    float rp_mid = exp(-rp_a2 * (20.0 - 14.0 * rp_ejW));
    float rp_kick = (rp_pulse * 1.2 + rp_surge * 2.2) * rp_mid;

    float rp_xEnd = rp_len + rp_seed * 1.37;
    float rp_XEnd = rp_xEnd - rp_fall * (1.0 - rp_gone);
    rp_XEnd = rp_XEnd - rp_throw * (1.0 - rp_gone);
    float rp_qe = rp_XEnd * 0.3 - rp_t * 0.42 + rp_seed * 0.618;
    float rp_de = (fract(rp_qe) - 0.5) / 0.3;
    float rp_ze = rp_de / mix(0.7, 0.4, smoothstep(-0.2, 0.2, rp_de));
    float rp_he = fract(sin(floor(rp_qe) * 7.13 + rp_seed) * 43758.5453);
    float rp_arrive = exp(-rp_ze * rp_ze) * (0.45 + 0.55 * rp_he) * rp_m;

    float3 rp_gold = float3(1.0, 0.753, 0.302);
    float3 rp_white = float3(1.0, 0.95, 0.84);
    float3 rp_orange = float3(1.0, 0.416, 0.0);
    float3 rp_amber = float3(1.0, 0.30, 0.02);
    float3 rp_violet = float3(0.45, 0.28, 1.0);
    float3 rp_ember = float3(0.62, 0.08, 0.0);
    float rp_heat = rp_core * 0.9 + rp_inner * 0.3;
    rp_heat = clamp(rp_heat + rp_kick * 0.5 + rp_sunW * 0.5, 0.0, 1.0);
    float rp_rim = smoothstep(0.5, 1.0, rp_a) * 0.55;
    float3 rp_base = mix(rp_orange, rp_violet, rp_rim);
    float3 rp_hot = mix(rp_gold, rp_white, clamp(rp_heat * 2.0 - 1.0, 0.0, 1.0));
    float3 rp_hue = mix(rp_base, rp_hot, rp_heat);
    rp_hue = mix(rp_hue, rp_white, clamp(rp_sunW * 0.7, 0.0, 1.0));
    rp_hue = mix(rp_hue, rp_ember, clamp(rp_bhW * rp_bhW * 0.8, 0.0, 1.0));
    rp_hue = mix(rp_hue, float3(0.55, 0.95, 1.0), clamp(rp_cmW * 0.55, 0.0, 1.0));
    rp_hue = mix(rp_hue, float3(0.7, 0.85, 1.0), clamp(rp_rkW * 0.3, 0.0, 1.0));
    rp_hue = mix(rp_hue, float3(1.0, 0.85, 0.6), clamp(rp_gsW * 0.45, 0.0, 1.0));
    float rp_glow = rp_core * 0.8 + rp_inner * 0.4 + rp_haze;
    rp_glow = rp_glow + (rp_core * 1.6 + rp_inner * 0.4) * rp_kick;
    rp_glow = rp_glow * (1.0 + 0.9 * rp_sunW) * (1.0 - 0.45 * rp_bhW);
    float3 rp_col = rp_hue * rp_glow;

    float3 rp_fl = float3(0.0);
    float rp_qA = rp_s * 26.0 + rp_seed * 3.0 + 0.0;
    float rp_iA = floor(rp_qA);
    float rp_fA = fract(rp_qA) - 0.5;
    float rp_haA = fract(sin(rp_iA * 12.9898 + rp_seed * 78.233 + 0.0) * 43758.5453);
    float rp_hbA = fract(sin(rp_iA * 39.346 + rp_seed * 11.135 + 0.0) * 43758.5453);
    float rp_profA = exp(-rp_fA * rp_fA * 38.0);
    float rp_phA = rp_x * (0.35 + rp_haA * 0.9) + rp_haA * 6.2831;
    float rp_runA = rp_t * 5.0 * (0.6 + rp_hbA);
    float rp_slowA = 0.5 + 0.5 * sin(rp_phA - rp_runA * 0.6);
    float rp_fastA = 0.5 + 0.5 * sin(rp_phA - rp_runA * 1.5);
    float rp_flowA = mix(rp_slowA, rp_fastA, rp_nV);
    rp_flowA = rp_flowA * rp_flowA * rp_flowA;
    rp_flowA = rp_flowA * rp_flowA;
    float rp_glA = (0.12 + 1.1 * rp_flowA) * (0.3 + 0.7 * rp_hbA);
    rp_glA = rp_glA * (0.3 + rp_nD);
    float3 rp_warmA = mix(rp_amber, rp_orange, clamp(rp_haA * 2.0, 0.0, 1.0));
    float3 rp_hotA = mix(rp_gold, rp_white, clamp(rp_haA * 2.0 - 1.0, 0.0, 1.0));
    float3 rp_hueA = mix(rp_warmA, rp_hotA, rp_haA);
    rp_fl = rp_fl + rp_hueA * (rp_profA * rp_glA * 0.9);
    float rp_qB = rp_s * 11.0 + rp_seed * 3.0 + 17.0;
    float rp_iB = floor(rp_qB);
    float rp_fB = fract(rp_qB) - 0.5;
    float rp_haB = fract(sin(rp_iB * 12.9898 + rp_seed * 78.233 + 17.0) * 43758.5453);
    float rp_hbB = fract(sin(rp_iB * 39.346 + rp_seed * 11.135 + 17.0) * 43758.5453);
    float rp_profB = exp(-rp_fB * rp_fB * 38.0);
    float rp_phB = rp_x * (0.35 + rp_haB * 0.9) + rp_haB * 6.2831;
    float rp_runB = rp_t * 3.0 * (0.6 + rp_hbB);
    float rp_slowB = 0.5 + 0.5 * sin(rp_phB - rp_runB * 0.6);
    float rp_fastB = 0.5 + 0.5 * sin(rp_phB - rp_runB * 1.5);
    float rp_flowB = mix(rp_slowB, rp_fastB, rp_nV);
    rp_flowB = rp_flowB * rp_flowB * rp_flowB;
    rp_flowB = rp_flowB * rp_flowB;
    float rp_glB = (0.12 + 1.1 * rp_flowB) * (0.3 + 0.7 * rp_hbB);
    rp_glB = rp_glB * (0.3 + rp_nD);
    float3 rp_warmB = mix(rp_amber, rp_orange, clamp(rp_haB * 2.0, 0.0, 1.0));
    float3 rp_hotB = mix(rp_gold, rp_white, clamp(rp_haB * 2.0 - 1.0, 0.0, 1.0));
    float3 rp_hueB = mix(rp_warmB, rp_hotB, rp_haB);
    rp_fl = rp_fl + rp_hueB * (rp_profB * rp_glB * 0.7);
    float rp_qC = rp_s * 53.0 + rp_seed * 3.0 + 31.0;
    float rp_iC = floor(rp_qC);
    float rp_fC = fract(rp_qC) - 0.5;
    float rp_haC = fract(sin(rp_iC * 12.9898 + rp_seed * 78.233 + 31.0) * 43758.5453);
    float rp_hbC = fract(sin(rp_iC * 39.346 + rp_seed * 11.135 + 31.0) * 43758.5453);
    float rp_profC = exp(-rp_fC * rp_fC * 38.0);
    float rp_phC = rp_x * (0.35 + rp_haC * 0.9) + rp_haC * 6.2831;
    float rp_runC = rp_t * 7.5 * (0.6 + rp_hbC);
    float rp_slowC = 0.5 + 0.5 * sin(rp_phC - rp_runC * 0.6);
    float rp_fastC = 0.5 + 0.5 * sin(rp_phC - rp_runC * 1.5);
    float rp_flowC = mix(rp_slowC, rp_fastC, rp_nV);
    rp_flowC = rp_flowC * rp_flowC * rp_flowC;
    rp_flowC = rp_flowC * rp_flowC;
    float rp_glC = (0.12 + 1.1 * rp_flowC) * (0.3 + 0.7 * rp_hbC);
    rp_glC = rp_glC * (0.3 + rp_nD);
    float3 rp_warmC = mix(rp_amber, rp_orange, clamp(rp_haC * 2.0, 0.0, 1.0));
    float3 rp_hotC = mix(rp_gold, rp_white, clamp(rp_haC * 2.0 - 1.0, 0.0, 1.0));
    float3 rp_hueC = mix(rp_warmC, rp_hotC, rp_haC);
    rp_fl = rp_fl + rp_hueC * (rp_profC * rp_glC * 0.45);
    rp_col = rp_col + rp_fl * (rp_w2 * 0.4 * (1.0 + rp_sunW));

    float rp_ph1 = rp_x * 3.1 - rp_t * 2.3 + rp_seed * 1.3;
    rp_ph1 = rp_ph1 + rp_nH * 2.0;
    float rp_y1 = 0.32 * (0.6 + 0.8 * rp_nH) * sin(rp_ph1);
    float rp_e1 = rp_s - rp_y1;
    float rp_h1 = exp(-rp_e1 * rp_e1 * 900.0) * (0.55 + 0.45 * cos(rp_ph1));
    float rp_ph2 = rp_x * 2.3 + rp_t * 1.4 + rp_seed * 2.9;
    rp_ph2 = rp_ph2 - rp_nH * 1.5;
    float rp_y2 = 0.26 * (1.3 - 0.6 * rp_nH) * sin(rp_ph2);
    float rp_e2 = rp_s - rp_y2;
    float rp_h2 = exp(-rp_e2 * rp_e2 * 900.0) * (0.55 + 0.45 * cos(rp_ph2));
    float rp_helix = (rp_h1 + rp_h2) * rp_w * 0.5 * rp_m;
    rp_col = rp_col + mix(rp_gold, rp_white, 0.5) * rp_helix;

    float rp_dP = rp_psA * rp_along + rp_psB * rp_toEnd;
    float rp_isP = clamp(rp_psA + rp_psB, 0.0, 1.0);
    float rp_beat = rp_t * 1.3333333 - rp_dP * 0.8;
    float rp_tick = 0.5 + 0.5 * cos(rp_beat * 6.2831853);
    rp_tick = rp_tick * rp_tick;
    rp_tick = rp_tick * rp_tick;
    rp_tick = rp_tick * rp_tick;
    float rp_sync = (rp_tick + 0.15) * rp_isP;
    rp_sync = rp_sync * exp(-rp_dP / (6.0 * rp_reach));
    float rp_syncGlow = rp_core * 1.4 + rp_inner * 0.5;
    rp_col = rp_col + float3(0.72, 0.8, 1.0) * (rp_syncGlow * rp_sync);

    float rp_cx = floor(rp_x * 16.0);
    float rp_cy = floor(rp_s0 * 4.0);
    float rp_ch = fract(sin(rp_cx * 17.13 + rp_cy * 5.71 + rp_seed) * 43758.5453);
    float rp_cf = fract(rp_x * 16.0) - 0.5;
    float rp_cg = fract(rp_s0 * 4.0) - 0.5;
    float rp_speck = exp(-(rp_cf * rp_cf + rp_cg * rp_cg) * 60.0);
    rp_speck = rp_speck * step(0.72, rp_ch);
    float rp_twk = 0.5 + 0.5 * sin(rp_t * 5.0 + rp_ch * 40.0);
    rp_col = rp_col + float3(0.8, 1.0, 1.0) * (rp_speck * rp_twk * rp_cmW * 0.9 * rp_w);

    float rp_f = sin(rp_t * 4.1 + rp_seed * 3.1);
    rp_f = rp_f * sin(rp_t * 2.3 + rp_seed * 7.7);
    float rp_flicker = 1.0 - 0.08 * rp_m * (0.5 + 0.5 * rp_f);
    float rp_boost = 1.0 + 0.5 * rp_lit;
    float rp_fadeA = 0.28 + rp_bhA * 0.5 * rp_reach;
    float rp_fadeB = 0.28 + rp_bhB * 0.5 * rp_reach;
    float rp_ends = smoothstep(0.0, rp_fadeA, rp_along);
    rp_ends = rp_ends * smoothstep(0.0, rp_fadeB, rp_toEnd);
    rp_col = rp_col * (rp_flicker * rp_boost * rp_ends);

    float rp_dEnd = rp_toEnd / (0.3 * rp_reach);
    float rp_flash = exp(-rp_dEnd * rp_dEnd) * rp_arrive * rp_w * rp_bhB;
    rp_col = rp_col + rp_white * (rp_flash * 1.4);
    float rp_gd = (rp_toEnd - 0.12) / (0.2 * rp_reach);
    float rp_gs = rp_s0 * 1.3;
    float rp_star = exp(-(rp_gd * rp_gd + rp_gs * rp_gs) * 3.0);
    float rp_arms = exp(-rp_gd * rp_gd * 40.0) * exp(-rp_gs * rp_gs * 0.8);
    float rp_arm2 = exp(-rp_gs * rp_gs * 60.0);
    rp_arms = rp_arms + rp_arm2 * exp(-rp_gd * rp_gd * 0.6);
    float rp_glint = (rp_star + rp_arms * 0.6) * rp_arrive * rp_rkB * rp_w;
    rp_col = rp_col + float3(0.8, 0.92, 1.0) * (rp_glint * 1.5);
    float rp_bd = (rp_toEnd - 0.1 * rp_reach) / (0.05 * rp_reach);
    float rp_bar = exp(-rp_bd * rp_bd - rp_s0 * rp_s0 * 2.5) * rp_gsB;
    rp_col = rp_col + float3(1.0, 0.86, 0.62) * (rp_bar * (0.35 + 0.8 * rp_arrive));
    rp_col = rp_col * rpEnergy;
    _surface.diffuse = float4(rp_col + float3(rpProbe), 1.0);
    """

    // MARK: the black hole

    /// The accretion disk, face on in its own plane (GraphSim turns the
    /// plane): streaky orbits whose inner lanes run ahead (Keplerian shear,
    /// two cross-faded eight-second phases so the pattern never winds up),
    /// three hot spots each at its own orbital pace, Doppler beaming from
    /// the real direction each point moves relative to the eye, and a thin
    /// line on the innermost stable orbit. The plane's z scale carries how
    /// hard the note is moving: the disk runs hotter. Below full quality
    /// (rpDetail 0) only one phase is drawn: the pattern then re-seeds
    /// every eight seconds with a soft step instead of a cross-fade.
    static let bhDisk: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpDetail;
    float rpProbe;

    #pragma body

    """ + plane + planeCode + """
    float rp_in = 0.43;
    float rp_u = (rp_r - rp_in) / (1.0 - rp_in);
    float rp_a = atan2(rp_qy, rp_qx);
    float rp_t = rpClock * rpMotion;
    float rp_kep = pow(rp_in / max(rp_r, rp_in), 1.5);
    float rp_om = 1.4 * (rp_kep - 0.28);
    float rp_f1 = fract(rp_t * 0.125);
    float rp_f2 = fract(rp_t * 0.125 + 0.5);
    float rp_w1 = 1.0 - abs(2.0 * rp_f1 - 1.0);
    float rp_n1 = floor(rp_t * 0.125);
    float rp_n2 = floor(rp_t * 0.125 + 0.5) + 7.0;
    float rp_rb = floor(rp_r * 34.0);
    float rp_a1 = rp_a - rp_om * rp_f1 * 8.0;
    float rp_h1 = fract(sin(rp_rb * 7.13 + rp_n1 * 1.618) * 43758.5453);
    float rp_k1 = 1.0 + floor(rp_h1 * 4.0);
    float rp_v1 = sin(rp_a1 * 3.0 + rp_r * 20.0) * 0.6;
    float rp_arc1 = 0.5 + 0.5 * sin(rp_a1 * rp_k1 + rp_h1 * 6.2831 + rp_v1);
    rp_arc1 = rp_arc1 * rp_arc1 * rp_arc1;
    float rp_fw1 = sin(rp_a1 * 5.0 + rp_h1 * 3.0) * 1.4;
    float rp_fn1 = 0.5 + 0.5 * sin(rp_r * 170.0 + rp_fw1);
    float rp_p1 = 0.3 + 0.45 * rp_arc1 * (0.4 + 0.6 * rp_h1);
    rp_p1 = rp_p1 + 0.25 * rp_fn1;
    float rp_pat = rp_p1;
    if (rpDetail > 0.5) {
    float rp_a2 = rp_a - rp_om * rp_f2 * 8.0;
    float rp_h2 = fract(sin(rp_rb * 7.13 + rp_n2 * 1.618) * 43758.5453);
    float rp_k2 = 1.0 + floor(rp_h2 * 4.0);
    float rp_v2 = sin(rp_a2 * 3.0 + rp_r * 20.0) * 0.6;
    float rp_arc2 = 0.5 + 0.5 * sin(rp_a2 * rp_k2 + rp_h2 * 6.2831 + rp_v2);
    rp_arc2 = rp_arc2 * rp_arc2 * rp_arc2;
    float rp_fw2 = sin(rp_a2 * 5.0 + rp_h2 * 3.0) * 1.4;
    float rp_fn2 = 0.5 + 0.5 * sin(rp_r * 170.0 + rp_fw2);
    float rp_p2 = 0.3 + 0.45 * rp_arc2 * (0.4 + 0.6 * rp_h2);
    rp_p2 = rp_p2 + 0.25 * rp_fn2;
    rp_pat = mix(rp_p2, rp_p1, rp_w1);
    }
    float rp_rise = smoothstep(0.0, 0.05, rp_u);
    float rp_fall = pow(max(1.0 - rp_u, 0.0), 1.6);
    float rp_heat = rp_rise * rp_fall * rp_pat * (1.0 + 0.45 * rp_m);

    float rp_oA = 1.4 * pow(rp_in / 0.50, 1.5);
    float rp_dA = rp_a - 0.7 - rp_oA * rp_t;
    rp_dA = rp_dA - 6.2831853 * floor(rp_dA / 6.2831853 + 0.5);
    float rp_rA = (rp_r - 0.50) / 0.025;
    float rp_lA = rp_dA * 0.50 / 0.09;
    rp_heat = rp_heat + exp(-rp_rA * rp_rA - rp_lA * rp_lA) * 0.55;
    float rp_oB = 1.4 * pow(rp_in / 0.63, 1.5);
    float rp_dB = rp_a - 2.9 - rp_oB * rp_t;
    rp_dB = rp_dB - 6.2831853 * floor(rp_dB / 6.2831853 + 0.5);
    float rp_rB = (rp_r - 0.63) / 0.025;
    float rp_lB = rp_dB * 0.63 / 0.09;
    rp_heat = rp_heat + exp(-rp_rB * rp_rB - rp_lB * rp_lB) * 0.44;
    float rp_oC = 1.4 * pow(rp_in / 0.80, 1.5);
    float rp_dC = rp_a - 4.6 - rp_oC * rp_t;
    rp_dC = rp_dC - 6.2831853 * floor(rp_dC / 6.2831853 + 0.5);
    float rp_rC = (rp_r - 0.80) / 0.025;
    float rp_lC = rp_dC * 0.80 / 0.09;
    rp_heat = rp_heat + exp(-rp_rC * rp_rC - rp_lC * rp_lC) * 0.33;

    float3 rp_c0 = normalize(scn_node.modelViewTransform[0].xyz);
    float3 rp_c1 = normalize(scn_node.modelViewTransform[1].xyz);
    float3 rp_vel = (rp_c1 * rp_qx - rp_c0 * rp_qy) / rp_r;
    float rp_beta = 0.5 * sqrt(rp_in / max(rp_r, rp_in));
    float rp_los = dot(rp_vel, _surface.view);
    float rp_D = 1.0 / (1.0 - rp_beta * rp_los);
    float rp_boost = clamp(rp_D * rp_D * rp_D, 0.3, 3.5);
    float rp_h = rp_heat * 1.1 * (0.55 + 0.45 * rp_boost);
    float3 rp_col = mix(float3(0.0), float3(0.62, 0.08, 0.0), clamp(rp_h / 0.25, 0.0, 1.0));
    rp_col = mix(rp_col, float3(0.9, 0.22, 0.0), clamp((rp_h - 0.25) / 0.25, 0.0, 1.0));
    rp_col = mix(rp_col, float3(1.0, 0.416, 0.0), clamp((rp_h - 0.5) / 0.2, 0.0, 1.0));
    rp_col = mix(rp_col, float3(1.0, 0.753, 0.302), clamp((rp_h - 0.7) / 0.18, 0.0, 1.0));
    rp_col = mix(rp_col, float3(1.0, 0.95, 0.84), clamp((rp_h - 0.88) / 0.12, 0.0, 1.0));
    float rp_id = (rp_r - rp_in) / 0.012;
    float rp_isco = exp(-rp_id * rp_id) * (0.5 + 0.5 * rp_boost);
    rp_col = rp_col + float3(1.0, 0.87, 0.64) * (rp_isco * 0.8);
    float rp_keep = step(rp_in - 0.03, rp_r) * (1.0 - step(1.0, rp_r));
    rp_col = rp_col * rp_keep;

    """ + glowEnd

    /// The photon ring and what the hole's gravity does round it, on the
    /// billboarded plane in front of the sphere. GraphStyleAnimator turns
    /// the plane so +x is the side of the disk coming towards the eye (the
    /// ring's Doppler-bright side, which moves as the disk precesses and
    /// tilts), and its z scale carries the disk's inclination with a sign:
    /// which side the broad lensed arc is on. Also: a hot spot running
    /// round the ring, a breathing glow, and (rpDetail) the stars behind
    /// sheared into short arcs round the Einstein radius - a cheap stand-in
    /// for lensing.
    static let bhRing: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpDetail;
    float rpProbe;

    #pragma body

    """ + plane + """
    float rp_code = length(scn_node.modelTransform[2].xyz) - 2.0;
    float rp_k = clamp(abs(rp_code), 0.0, 1.0);
    float rp_flip = rp_code < 0.0 ? 1.0 : -1.0;
    float rp_t = rpClock * rpMotion;
    float3 rp_pos = scn_node.modelTransform[3].xyz;
    float rp_seed = dot(rp_pos, float3(0.37, 0.51, 0.29));
    float rp_ca = rp_qx / rp_r;
    float rp_sa = rp_flip * rp_qy / rp_r;
    float rp_a = atan2(rp_qy, rp_qx);
    float rp_side = 0.5 + 0.5 * rp_ca * rp_k;
    float rp_bright = 0.3 + 1.2 * rp_side * rp_side;
    float rp_d = rp_r - 0.495;
    float rp_sg = rp_d < 0.0 ? 0.010 : 0.022;
    float rp_q = rp_d / rp_sg;
    float rp_ph = exp(-rp_q * rp_q);
    float rp_c = max(cos(rp_a - rp_t * 0.6283185 - rp_seed), 0.0);
    rp_c = rp_c * rp_c;
    rp_c = rp_c * rp_c;
    rp_c = rp_c * rp_c;
    float3 rp_gold = float3(1.0, 0.753, 0.302);
    float3 rp_white = float3(1.0, 0.95, 0.84);
    float3 rp_orange = float3(1.0, 0.416, 0.0);
    float3 rp_hue = mix(rp_gold, rp_white, rp_side * rp_side);
    float3 rp_col = rp_hue * (rp_ph * rp_bright * 1.25);
    rp_col = rp_col + rp_white * (rp_ph * rp_c * 0.6 * rpMotion);
    float rp_fw = sin(rp_a * 4.0 + rp_t * 0.4) * 1.5;
    float rp_flow = 0.6 + 0.4 * sin(rp_a * 9.0 - rp_t * 1.3 + rp_fw);
    float rp_td = (rp_r - 0.6) / 0.05;
    float rp_tw = mix(1.0, pow(max(rp_sa, 0.0), 1.2), rp_k);
    float rp_top = exp(-rp_td * rp_td) * rp_tw;
    float rp_bd = (rp_r - 0.535) / 0.02;
    float rp_bw = mix(0.6, pow(max(-rp_sa, 0.0), 1.5), rp_k);
    float rp_bot = exp(-rp_bd * rp_bd) * rp_bw * 0.7;
    float rp_lens = (rp_top + rp_bot) * rp_flow * (0.45 + 0.8 * rp_side);
    float3 rp_lensHue = mix(rp_orange, rp_gold, 0.45 + 0.4 * rp_side);
    rp_col = rp_col + rp_lensHue * (rp_lens * 0.85);
    float rp_out = max(rp_d, 0.0);
    float rp_inner = rp_d > 0.0 ? 1.0 : rp_ph;
    float rp_breath = 1.0 + 0.1 * sin(rp_t * 0.9 + rp_seed * 2.0);
    float rp_halo = exp(-rp_out / 0.15) * 0.26 * rp_inner * rp_breath;
    rp_col = rp_col + mix(rp_orange, rp_gold, 0.3) * (rp_halo * rp_bright);
    if (rpDetail > 0.5) {
    float rp_lr = floor(rp_r * 16.0);
    float rp_la = floor(rp_a * 3.0 + rp_lr * 0.37);
    float rp_lh = fract(sin(rp_la * 12.9898 + rp_lr * 78.233) * 43758.5453);
    float rp_cr = (rp_lr + 0.5) / 16.0;
    float rp_ang = (rp_la + 0.5 - rp_lr * 0.37) / 3.0;
    float rp_dA = (rp_a - rp_ang) * rp_r;
    float rp_ez = (rp_r - 0.66) / 0.12;
    float rp_ein = exp(-rp_ez * rp_ez);
    float rp_sx = rp_dA / (0.012 + 0.09 * rp_ein);
    float rp_sy = (rp_r - rp_cr) / 0.006;
    float rp_star = exp(-rp_sx * rp_sx - rp_sy * rp_sy);
    rp_star = rp_star * step(0.82, rp_lh) * step(0.53, rp_r);
    rp_col = rp_col + float3(0.75, 0.85, 1.0) * (rp_star * 0.45);
    }
    float rp_e = clamp((1.0 - rp_r) / 0.18, 0.0, 1.0);
    rp_col = rp_col * (rp_e * rp_e * (3.0 - 2.0 * rp_e));
    rp_col = rp_col * step(0.3, rp_r);

    """ + glowEnd

    // MARK: the sun

    /// The sun's face: granulation (three crossed waves, warped so the
    /// cells are not a grid, boiling slowly), a spot group, limb darkening
    /// that also reddens the edge. Moving (z scale), it runs hotter.
    static let sunBody: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;

    #pragma body

    """ + axes + sphere + sphereMotion + """
    float rp_t = rpClock * rpMotion;
    float rp_lm = 1.0 - rp_mu;
    float rp_limb = 1.0 - 0.55 * rp_lm - 0.25 * rp_lm * rp_lm;
    float3 rp_p0 = rp_p;
    float rp_wp = sin(dot(rp_p, float3(0.2, 0.9, 0.4)) * 9.0 + rp_t * 0.2) * 0.9;
    rp_p = rp_p + sin(rp_p.yzx * 13.0 + rp_wp) * 0.06;
    float rp_g1 = sin(dot(rp_p, float3(0.8, 0.5, 0.33)) * 23.0 + rp_t * 0.6);
    rp_g1 = rp_g1 * sin(dot(rp_p, float3(-0.3, 0.85, 0.42)) * 23.0 - rp_t * 0.5);
    rp_g1 = rp_g1 * sin(dot(rp_p, float3(0.45, -0.2, 0.87)) * 23.0 + rp_t * 0.45);
    float rp_g2 = sin(dot(rp_p, float3(0.6, -0.7, 0.38)) * 47.0 - rp_t * 0.9);
    rp_g2 = rp_g2 * sin(dot(rp_p, float3(0.1, 0.4, -0.91)) * 47.0 + rp_t * 0.8);
    rp_g2 = rp_g2 * sin(dot(rp_p, float3(-0.9, -0.1, 0.42)) * 47.0 + rp_t * 0.7);
    float rp_cell = 0.5 + 0.5 * (rp_g1 * 0.75 + rp_g2 * 0.45);
    float rp_gran = smoothstep(0.1, 0.9, rp_cell);
    float rp_sd = dot(rp_p0, float3(0.35, 0.28, 0.894));
    float rp_um = smoothstep(0.988, 0.994, rp_sd);
    float rp_pen = smoothstep(0.972, 0.988, rp_sd);
    float rp_temp = 0.8 + 0.2 * rp_gran - 0.35 * rp_pen - 0.35 * rp_um;
    float rp_heat = rp_temp * rp_limb * (1.0 + 0.12 * rp_m);
    float rp_w = clamp(rp_heat * 1.15 - 0.1, 0.0, 1.0);
    float3 rp_hue = mix(float3(1.0, 0.36, 0.04), float3(1.0, 0.95, 0.78), rp_w);
    float3 rp_col = rp_hue * (0.35 + 0.9 * rp_heat);

    """ + bodyEnd

    /// The corona round the sun, on the lifted billboard (the limb at a
    /// quarter of the half side): a glow in streamers with fine rays, a
    /// rosy chromosphere rim, three prominences rising off the limb and
    /// fading, each on its own clock, and now and then a flare thrown off.
    /// The plane's z scale carries the note's own seed (|z| - 2), so no two
    /// suns flare in step and nothing jumps while one is dragged.
    static let sunCorona: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpDetail;
    float rpProbe;

    #pragma body

    """ + plane + """
    float rp_seed = clamp(length(scn_node.modelTransform[2].xyz) - 2.0, 0.0, 1.0) * 6.2831853;
    float rp_t = rpClock * rpMotion;
    float rp_rl = 0.25;
    float rp_a = atan2(rp_qy, rp_qx);
    float rp_x = rp_r / rp_rl;
    float rp_out = max(rp_x - 1.0, 0.0);
    float rp_sw = sin(rp_a * 5.0 + rp_t * 0.07) * 1.2;
    float rp_st = 0.55 + 0.45 * sin(rp_a * 3.0 + rp_sw + rp_seed);
    float rp_rw = sin(rp_a * 9.0 + rp_seed) * 2.5;
    float rp_ray = 0.5 + 0.5 * sin(rp_a * 38.0 + rp_rw);
    rp_ray = rp_ray * rp_ray;
    rp_ray = rp_ray * rp_ray;
    float rp_cor = exp(-rp_out / 0.3) * 0.55;
    rp_cor = rp_cor + exp(-rp_out / 1.2) * 0.22;
    rp_cor = rp_cor * (0.55 + 0.6 * rp_st);
    rp_cor = rp_cor * (0.75 + 0.6 * rp_ray * smoothstep(1.0, 1.5, rp_x));
    rp_cor = rp_cor * step(1.0, rp_x);
    float3 rp_hue = mix(float3(1.0, 0.93, 0.75), float3(1.0, 0.416, 0.0), clamp(rp_out * 0.6, 0.0, 1.0));
    float3 rp_col = rp_hue * rp_cor;
    float rp_ch = (rp_x - 1.015) / 0.018;
    rp_col = rp_col + float3(1.0, 0.42, 0.32) * (exp(-rp_ch * rp_ch) * 0.7);
    float3 rp_prom = mix(float3(1.0, 0.3, 0.22), float3(1.0, 0.75, 0.45), 0.3);
    float rp_lift = smoothstep(1.0, 1.06, rp_x) * (0.8 + 0.2 * rpDetail);

    float rp_cA = rp_t / 9.0 + rp_seed * 0.1;
    float rp_fA = fract(rp_cA);
    float rp_hA = fract(sin(floor(rp_cA) * 3.7 + rp_seed) * 43758.5453);
    float rp_tA = (0.0 + rp_hA * 0.25) * 6.2831853 + rp_seed;
    float rp_xA = rp_qx - cos(rp_tA) * rp_rl;
    float rp_yA = rp_qy - sin(rp_tA) * rp_rl;
    float rp_gA = rp_rl * (0.10 + 0.28 * rp_fA);
    float rp_lA = (length(float2(rp_xA, rp_yA)) - rp_gA) / (0.009 + 0.006 * rp_fA);
    float rp_pA = exp(-rp_lA * rp_lA) * sin(rp_fA * 3.14159);
    float rp_cB = rp_t / 12.0 + 0.37 + rp_seed * 0.1;
    float rp_fB = fract(rp_cB);
    float rp_hB = fract(sin(floor(rp_cB) * 3.7 + 11.0 + rp_seed) * 43758.5453);
    float rp_tB = (0.333 + rp_hB * 0.25) * 6.2831853 + rp_seed;
    float rp_xB = rp_qx - cos(rp_tB) * rp_rl;
    float rp_yB = rp_qy - sin(rp_tB) * rp_rl;
    float rp_gB = rp_rl * (0.10 + 0.28 * rp_fB);
    float rp_lB = (length(float2(rp_xB, rp_yB)) - rp_gB) / (0.009 + 0.006 * rp_fB);
    float rp_pB = exp(-rp_lB * rp_lB) * sin(rp_fB * 3.14159);
    float rp_cC = rp_t / 15.0 + 0.74 + rp_seed * 0.1;
    float rp_fC = fract(rp_cC);
    float rp_hC = fract(sin(floor(rp_cC) * 3.7 + 22.0 + rp_seed) * 43758.5453);
    float rp_tC = (0.666 + rp_hC * 0.25) * 6.2831853 + rp_seed;
    float rp_xC = rp_qx - cos(rp_tC) * rp_rl;
    float rp_yC = rp_qy - sin(rp_tC) * rp_rl;
    float rp_gC = rp_rl * (0.10 + 0.28 * rp_fC);
    float rp_lC = (length(float2(rp_xC, rp_yC)) - rp_gC) / (0.009 + 0.006 * rp_fC);
    float rp_pC = exp(-rp_lC * rp_lC) * sin(rp_fC * 3.14159);
    rp_col = rp_col + rp_prom * ((rp_pA + rp_pB + rp_pC) * rp_lift * 0.9);

    float rp_cF = rp_t / 13.0 + rp_seed * 0.3;
    float rp_fl = fract(rp_cF);
    float rp_ft = fract(sin(floor(rp_cF) * 5.3 + rp_seed) * 43758.5453) * 6.2831853;
    float rp_fr = rp_rl * (1.02 + rp_fl * 1.6);
    float rp_fx = rp_qx - cos(rp_ft) * rp_fr;
    float rp_fy = rp_qy - sin(rp_ft) * rp_fr;
    float rp_fs = 0.02 + 0.05 * rp_fl;
    float rp_fb = exp(-(rp_fx * rp_fx + rp_fy * rp_fy) / (rp_fs * rp_fs));
    rp_fb = rp_fb * (1.0 - rp_fl) * (1.0 - rp_fl) * rpMotion;
    float3 rp_fh = mix(float3(1.0, 0.95, 0.84), float3(1.0, 0.416, 0.0), rp_fl);
    rp_col = rp_col + rp_fh * (rp_fb * 1.3);
    float rp_e = clamp((1.0 - rp_r) / 0.25, 0.0, 1.0);
    rp_col = rp_col * (rp_e * rp_e * (3.0 - 2.0 * rp_e));

    """ + glowEnd

    // MARK: the rocky planet

    /// A rocky world: continents from warped waves over its own sphere
    /// (turned by GraphStyleAnimator, so the land rotates), shallows, ice
    /// caps, clouds drifting a little faster than the ground, a soft
    /// terminator towards the nearest sun, sunglint on open water, city
    /// lights on the night side, and a Fresnel rim of air lit where the
    /// sun is. Palette per folder: rpTintA sea, B shallows, C land, D high
    /// ground.
    static let rockBody: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;
    float3 rpTintA;
    float3 rpTintB;
    float3 rpTintC;
    float3 rpTintD;

    """ + lightArguments + """
    #pragma body

    """ + light + sphere + """
    float rp_t = rpClock * rpMotion;
    float rp_w = sin(dot(rp_p, float3(0.3, 0.9, 0.3)) * 4.0 + 1.7) * 0.35;
    float rp_h = 0.5 * sin(dot(rp_p, float3(0.82, 0.31, 0.48)) * 3.1 + 1.3 + rp_w);
    rp_h = rp_h + 0.33 * sin(dot(rp_p, float3(-0.44, 0.72, 0.53)) * 5.3 + 0.4);
    float rp_h3 = dot(rp_p, float3(0.21, -0.63, 0.75)) * 9.7;
    rp_h = rp_h + 0.22 * sin(rp_h3 + 2.1 + rp_w);
    float rp_h4 = dot(rp_p, float3(-0.8, -0.35, 0.49)) * 19.0;
    rp_h = rp_h + 0.12 * sin(rp_h4 + 0.9);
    float rp_land = smoothstep(0.04, 0.1, rp_h);
    float rp_ice = smoothstep(0.8, 0.88, abs(rp_p.y) + 0.06 * rp_h);
    float3 rp_ground = mix(rpTintC, rpTintD, smoothstep(0.15, 0.55, rp_h));
    float3 rp_water = mix(rpTintA, rpTintB, smoothstep(-0.3, 0.06, rp_h));
    float3 rp_alb = mix(rp_water, rp_ground, rp_land);
    rp_alb = mix(rp_alb, float3(0.9, 0.93, 0.97), rp_ice);
    float rp_cc = cos(rp_t * 0.03);
    float rp_cs = sin(rp_t * 0.03);
    float3 rp_pc = float3(rp_p.x * rp_cc - rp_p.z * rp_cs, rp_p.y, rp_p.x * rp_cs + rp_p.z * rp_cc);
    float rp_cw = sin(dot(rp_pc, float3(-0.5, 0.8, 0.3)) * 5.0) * 1.6;
    float rp_c1 = 0.5 + 0.5 * sin(dot(rp_pc, float3(0.6, 0.55, 0.58)) * 7.0 + rp_cw);
    float rp_cd = dot(rp_pc, float3(-0.7, 0.2, 0.68)) * 11.0;
    float rp_c2 = 0.5 + 0.5 * sin(rp_cd + rp_t * 0.02);
    float rp_cloud = smoothstep(0.5, 0.85, rp_c1 * (0.6 + 0.6 * rp_c2));
    rp_alb = mix(rp_alb, float3(0.95, 0.96, 1.0), rp_cloud * 0.8);
    float rp_ndl = dot(rp_N, rp_Lv);
    float rp_day = smoothstep(-0.12, 0.3, rp_ndl);
    float rp_sun = 1.15 * rp_day * pow(max(rp_ndl, 0.05), 0.7);
    float3 rp_col = rp_alb * (0.02 + rp_sun);
    float3 rp_hv = normalize(rp_Lv + rp_V);
    float rp_sp = pow(max(dot(rp_N, rp_hv), 0.0), 60.0);
    rp_sp = rp_sp * (1.0 - rp_land) * (1.0 - rp_cloud) * rp_day;
    rp_col = rp_col + float3(1.0, 0.95, 0.85) * (rp_sp * 0.8);
    float3 rp_cq = floor(rp_p * 60.0);
    float rp_ct = fract(sin(dot(rp_cq, float3(3.1, 7.7, 1.3))) * 43758.5453);
    float rp_city = step(0.9, rp_ct) * rp_land * (1.0 - rp_ice);
    rp_city = rp_city * (1.0 - rp_day) * (1.0 - rp_cloud);
    rp_col = rp_col + float3(1.0, 0.7, 0.35) * (rp_city * 0.5);
    float rp_lm = 1.0 - rp_mu;
    float rp_fr = rp_lm * rp_lm * rp_lm;
    float rp_air = rp_fr * (0.1 + 1.3 * smoothstep(-0.35, 0.5, rp_ndl));
    rp_col = rp_col + float3(0.35, 0.62, 1.0) * rp_air;

    """ + bodyEnd

    /// A moon: grey, faintly mottled, lit by the same suns.
    static let moonBody: String = """
    #pragma arguments
    float rpProbe;

    """ + lightArguments + """
    #pragma body

    """ + light + sphere + """
    float rp_c = sin(dot(rp_p, float3(0.7, 0.5, 0.5)) * 9.0);
    rp_c = 0.5 + 0.5 * rp_c * sin(dot(rp_p, float3(-0.4, 0.8, 0.44)) * 13.0);
    float rp_alb = 0.42 + 0.22 * smoothstep(0.3, 0.7, rp_c);
    float rp_ndl = dot(rp_N, rp_Lv);
    float rp_k = 1.1 * smoothstep(-0.05, 0.25, rp_ndl) * pow(max(rp_ndl, 0.03), 0.8);
    float3 rp_col = float3(0.93, 0.9, 0.86) * (rp_alb * (0.02 + rp_k));

    """ + bodyEnd

    /// The thin air round a planet (and, tinted by rpTintA, a gas giant's
    /// glow), on the lifted billboard: brightest on the sun's side, and a
    /// whole glowing ring when the sun is behind it.
    static let halo: String = """
    #pragma arguments
    float rpProbe;
    float3 rpTintA;

    """ + lightArguments + """
    #pragma body

    """ + plane + light + """
    float rp_rl = 0.667;
    float rp_lx = dot(rp_Lv, rp_v0);
    float rp_ly = dot(rp_Lv, rp_v1);
    float rp_dd = (rp_r - rp_rl) / 0.03;
    float rp_thin = exp(-rp_dd * rp_dd) * step(0.0, rp_r - rp_rl + 0.02);
    float rp_soft = exp(-max(rp_r - rp_rl, 0.0) / 0.07) * step(rp_rl, rp_r);
    float rp_dir = (rp_qx * rp_lx + rp_qy * rp_ly) / rp_r;
    float rp_back = max(-rp_Lv.z, 0.0);
    float rp_face = clamp(rp_dir * 0.8 + 0.35, 0.0, 1.0);
    float rp_lit = 0.12 + 1.1 * rp_face + 0.9 * rp_back;
    float3 rp_col = rpTintA * ((rp_thin * 0.5 + rp_soft * 0.35) * rp_lit);
    rp_col = rp_col * clamp((1.0 - rp_r) / 0.2, 0.0, 1.0);

    """ + glowEnd

    // MARK: the gas giant

    /// Ring density at `rp_rho` planet radii, into `rp_den`: the C ring
    /// faint, the Cassini division dark, fine ringlets. `pre` names the
    /// variables so it can be used twice.
    static func ringDensity(_ pre: String) -> String {
        """
        float \(pre)_body = smoothstep(1.3, 1.36, \(pre)_rho) * (1.0 - smoothstep(2.2, 2.3, \(pre)_rho));
        float \(pre)_gd = (\(pre)_rho - 1.95) / 0.03;
        float \(pre)_gap = 1.0 - 0.85 * exp(-\(pre)_gd * \(pre)_gd);
        float \(pre)_lets = 0.78 + 0.22 * sin(\(pre)_rho * 140.0) * sin(\(pre)_rho * 37.0);
        float \(pre)_cring = mix(0.35, 1.0, smoothstep(1.42, 1.52, \(pre)_rho));
        float \(pre)_den = \(pre)_body * \(pre)_gap * \(pre)_lets * \(pre)_cring;

        """
    }

    /// A gas giant: bands whose edges churn, each band's jet running at its
    /// own speed; a storm drifting with its band; paler poles; lit towards
    /// the nearest sun; and the ring's shadow on the clouds. Dragged (its
    /// z scale) the churn stretches out along the bands - they smear - and
    /// fine streaks show. y is its spin axis; the ring lies in y = 0.
    /// Palette per folder: rpTintA cream, B tan, C rust, D the poles.
    static let gasBody: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;
    float3 rpTintA;
    float3 rpTintB;
    float3 rpTintC;
    float3 rpTintD;

    """ + lightArguments + """
    #pragma body

    """ + light + sphere + sphereMotion + """
    float rp_t = rpClock * rpMotion;
    float rp_lat = rp_p.y;
    float rp_lon = atan2(rp_p.z, rp_p.x);
    float rp_bi = floor(rp_lat * 7.0 + 3.5);
    float rp_om = (fract(sin(rp_bi * 3.7) * 43758.5453) - 0.5) * 0.3;
    float rp_lb = rp_lon + rp_t * rp_om;
    float rp_fq = 1.0 - 0.75 * rp_m;
    float rp_tw = sin(rp_lb * 5.0 * rp_fq - rp_lat * 9.0) * 0.8;
    float rp_turb = sin(rp_lb * 3.0 * rp_fq + rp_lat * 14.0 + rp_tw);
    float rp_lw = rp_lat + 0.035 * rp_turb * (1.0 - 0.5 * rp_m);
    float rp_tone = 0.5 + 0.3 * sin(rp_lw * 18.0 + 0.5);
    rp_tone = rp_tone + 0.12 * sin(rp_lw * 41.0 + 2.0);
    rp_tone = rp_tone + 0.2 * sin(rp_lw * 7.0 + 1.1);
    rp_tone = rp_tone + rp_m * 0.1 * sin(rp_lw * 90.0 + rp_lb * 0.5);
    float3 rp_cloud = mix(rpTintC, rpTintB, smoothstep(0.1, 0.5, rp_tone));
    rp_cloud = mix(rp_cloud, rpTintA, smoothstep(0.5, 0.85, rp_tone));
    rp_cloud = mix(rp_cloud, rpTintD, smoothstep(0.72, 0.92, abs(rp_lat)));
    float rp_so = rp_lb - rp_t * 0.02 - 1.0;
    rp_so = rp_so - 6.2831853 * floor(rp_so / 6.2831853 + 0.5);
    float rp_cl = sqrt(max(1.0 - rp_lat * rp_lat, 0.0));
    float rp_stx = rp_so * rp_cl / (0.26 * (1.0 + 0.8 * rp_m));
    float rp_sty = (rp_lat + 0.34) / 0.09;
    float rp_s2 = rp_stx * rp_stx + rp_sty * rp_sty;
    float rp_storm = exp(-rp_s2 * 1.4);
    float rp_sr = (sqrt(rp_s2) - 1.1) / 0.3;
    float rp_srim = exp(-rp_sr * rp_sr) * 0.35;
    rp_cloud = mix(rp_cloud, float3(0.72, 0.28, 0.15), rp_storm * 0.85);
    rp_cloud = rp_cloud + float3(0.9, 0.8, 0.65) * (rp_srim * 0.3);
    float rp_ly = abs(rp_Lo.y) < 0.001 ? 0.001 : rp_Lo.y;
    float rp_tt = -rp_lat / rp_ly;
    float rp_hx = rp_p.x + rp_Lo.x * rp_tt;
    float rp_hz = rp_p.z + rp_Lo.z * rp_tt;
    float rp_rho = sqrt(rp_hx * rp_hx + rp_hz * rp_hz);
    """ + ringDensity("rp") + """
    float rp_shade = 1.0 - 0.6 * rp_den * step(0.0, rp_tt);
    float rp_ndl = dot(rp_N, rp_Lv);
    float rp_day = smoothstep(-0.1, 0.3, rp_ndl) * pow(max(rp_ndl, 0.04), 0.6);
    float rp_k = (0.02 + 1.1 * rp_day * rp_shade) * (0.8 + 0.2 * rp_mu);
    float3 rp_col = rp_cloud * rp_k;
    float rp_lm = 1.0 - rp_mu;
    float rp_fr = rp_lm * rp_lm * rp_lm;
    rp_col = rp_col + float3(0.9, 0.78, 0.55) * (rp_fr * 0.35 * smoothstep(-0.3, 0.5, rp_ndl));

    """ + bodyEnd

    /// A gas giant's ring, in the disk's plane (its half side 2.4 planet
    /// radii): the rings lit from either face, and the planet's shadow
    /// across them on the far side from the sun. Its z scale carries the
    /// planet's motion: it shimmers brighter.
    static let gasRing: String = """
    #pragma arguments
    float rpProbe;

    """ + lightArguments + """
    #pragma body

    """ + plane + planeCode + light + """
    float rp_px = rp_qx * 2.4;
    float rp_py = rp_qy * 2.4;
    float rp_rho = sqrt(rp_px * rp_px + rp_py * rp_py);
    """ + ringDensity("rp") + """
    float rp_tone = 0.5 + 0.5 * sin(rp_rho * 23.0 + 1.0);
    float3 rp_hue = mix(float3(0.62, 0.5, 0.36), float3(0.98, 0.9, 0.74), rp_tone);
    float rp_lit = 0.3 + 0.7 * abs(rp_Lo.z);
    float rp_al = rp_px * rp_Lo.x + rp_py * rp_Lo.y;
    float rp_perp = rp_rho * rp_rho - rp_al * rp_al;
    float rp_sh = (1.0 - step(0.0, rp_al)) * (1.0 - smoothstep(0.85, 1.05, rp_perp));
    float rp_k = rp_den * rp_lit * (1.0 - 0.88 * rp_sh);
    rp_k = rp_k * (0.85 + 0.3 * rp_m);
    float3 rp_col = rp_hue * (rp_k * 0.8);

    """ + glowEnd

    // MARK: the pulsar

    /// The pulsar's tiny core: white-blue, brighter at the edge, flaring
    /// as a beam sweeps by (two beats a turn).
    static let pulsarCore: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;

    #pragma body
    float rp_mu = max(dot(_surface.normal, _surface.view), 0.0);
    float rp_t = rpClock * rpMotion;
    float rp_b = 0.5 + 0.5 * cos(rp_t * 1.3333333 * 6.2831853);
    rp_b = rp_b * rp_b;
    rp_b = rp_b * rp_b;
    rp_b = rp_b * rp_b;
    float rp_k = 1.0 + 0.6 * (1.0 - rp_mu) + 0.5 * rp_b;
    float3 rp_col = float3(0.82, 0.9, 1.0) * rp_k;

    """ + bodyEnd

    /// The glow round it and a faint wind nebula (a wispy torus), beating
    /// with the beams.
    static let pulsarGlow: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;

    #pragma body

    """ + plane + """
    float rp_t = rpClock * rpMotion;
    float rp_rl = 0.12;
    float rp_a = atan2(rp_qy, rp_qx);
    float rp_b = 0.5 + 0.5 * cos(rp_t * 1.3333333 * 6.2831853);
    rp_b = rp_b * rp_b;
    rp_b = rp_b * rp_b;
    rp_b = rp_b * rp_b;
    float rp_x = max(rp_r / rp_rl - 1.0, 0.0);
    float rp_h = 1.0 / (1.0 + rp_x * rp_x * 5.0);
    rp_h = rp_h * (0.55 + 0.9 * rp_b) * step(rp_rl * 0.95, rp_r);
    float3 rp_col = float3(0.6, 0.72, 1.0) * (rp_h * 0.8);
    float rp_ex = rp_qx / 0.62;
    float rp_ey = rp_qy / 0.2;
    float rp_el = (sqrt(rp_ex * rp_ex + rp_ey * rp_ey) - 1.0) / 0.16;
    float rp_wisp = 0.6 + 0.4 * sin(rp_a * 9.0 + rp_t * 0.4);
    float rp_to = exp(-rp_el * rp_el) * rp_wisp;
    rp_col = rp_col + float3(0.5, 0.52, 1.0) * (rp_to * 0.22);
    rp_col = rp_col * clamp((1.0 - rp_r) / 0.3, 0.0, 1.0);

    """ + glowEnd

    /// Both beams in one long plane along the magnetic axis (turned each
    /// frame by GraphStyleAnimator to face the eye): cones widening
    /// outwards, streaming, brightest and widest as the beam sweeps
    /// towards the eye (its z scale).
    static let pulsarBeam: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;

    #pragma body

    """ + plane + planeCode + """
    float rp_t = rpClock * rpMotion;
    float rp_face = rp_m;
    float rp_ay = abs(rp_qy);
    float rp_wd = 0.07 + 0.5 * rp_ay * (1.0 + 0.6 * rp_face);
    float rp_ac = rp_qx / rp_wd;
    float rp_prof = exp(-rp_ac * rp_ac * 3.0);
    float rp_fade = smoothstep(0.03, 0.12, rp_ay) * pow(max(1.0 - rp_ay, 0.0), 1.5);
    float rp_fph = rp_ay * 30.0 - rp_t * 18.0 + rp_qx * 4.0;
    float rp_flow = 0.7 + 0.3 * sin(rp_fph);
    float rp_f2 = rp_face * rp_face;
    float rp_k = rp_prof * rp_fade * rp_flow * (0.7 + 1.8 * rp_f2 * rp_f2);
    float3 rp_hue = mix(float3(0.88, 0.94, 1.0), float3(0.5, 0.45, 1.0), clamp(abs(rp_ac) * 0.8, 0.0, 1.0));
    float3 rp_col = rp_hue * rp_k;

    """ + glowEnd

    // MARK: the comet

    /// The nucleus: small, dark, its sunward side lit.
    static let cometNucleus: String = """
    #pragma arguments
    float rpProbe;

    """ + lightArguments + """
    #pragma body

    """ + light + sphere + """
    float rp_ndl = dot(rp_N, rp_Lv);
    float rp_k = 0.04 + 0.3 * smoothstep(-0.1, 0.4, rp_ndl);
    float3 rp_col = float3(0.62, 0.66, 0.7) * rp_k;

    """ + bodyEnd

    /// The coma: a cyan-green glow, pushed a little towards the sun.
    static let cometComa: String = """
    #pragma arguments
    float rpProbe;

    """ + lightArguments + """
    #pragma body

    """ + plane + light + """
    float rp_rl = 0.1875;
    float rp_cx = rp_qx - dot(rp_Lv, rp_v0) * 0.06;
    float rp_cy = rp_qy - dot(rp_Lv, rp_v1) * 0.06;
    float rp_cr = length(float2(rp_cx, rp_cy)) + 0.00001;
    float rp_g = exp(-max(rp_cr - rp_rl * 0.8, 0.0) / 0.1) * 0.7;
    rp_g = rp_g + exp(-rp_cr / 0.33) * 0.3;
    float3 rp_hue = mix(float3(0.85, 1.0, 0.95), float3(0.3, 0.95, 0.75), clamp(rp_cr / 0.6, 0.0, 1.0));
    float3 rp_col = rp_hue * (rp_g * clamp((1.0 - rp_cr) / 0.3, 0.0, 1.0));

    """ + glowEnd

    /// The tails, in one plane from the head (bottom) to the tip (top): a
    /// straight, streaming blue ion tail and a broader, curving dust tail.
    /// Its z scale carries how fast the comet is moving: brighter.
    static let cometTail: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;

    #pragma body

    """ + plane + planeCode + """
    float rp_t = rpClock * rpMotion;
    float rp_ty = rp_qy * 0.5 + 0.5;
    float rp_tx = rp_qx;
    float rp_wi = 0.04 + 0.16 * rp_ty;
    float rp_ix = rp_tx / rp_wi;
    float rp_sa = sin(rp_tx * 40.0 + rp_ty * 3.0);
    float rp_sp = rp_ty * 12.0 - rp_t * 3.0 + rp_tx * 9.0;
    float rp_st = 0.6 + 0.4 * rp_sa * sin(rp_sp);
    float rp_ion = exp(-rp_ix * rp_ix) * pow(max(1.0 - rp_ty, 0.0), 1.2) * rp_st;
    float rp_xc = 0.32 * rp_ty * rp_ty;
    float rp_wd = 0.07 + 0.38 * rp_ty;
    float rp_dx = (rp_tx - rp_xc) / rp_wd;
    float rp_dust = exp(-rp_dx * rp_dx) * pow(max(1.0 - rp_ty, 0.0), 1.8);
    float rp_head = exp(-rp_ty * 9.0) * exp(-rp_tx * rp_tx * 30.0);
    float3 rp_col = float3(0.45, 0.66, 1.0) * (rp_ion * 1.3);
    rp_col = rp_col + float3(1.0, 0.93, 0.76) * (rp_dust * 0.8);
    rp_col = rp_col + float3(0.9, 1.0, 0.97) * (rp_head * 0.6);
    rp_col = rp_col * (0.8 + 0.6 * rp_m);

    """ + glowEnd

    // MARK: selection and folders

    /// The chosen note's orbit: a thin gold ring round it with a spark
    /// running along it, trailing light.
    static let orbit: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;

    #pragma body

    """ + plane + """
    float rp_t = rpClock * rpMotion;
    float rp_a = atan2(rp_qy, rp_qx);
    float rp_d = (rp_r - 0.9) / 0.012;
    float rp_line = exp(-rp_d * rp_d);
    float rp_da = rp_a - rp_t * 1.4 - 0.8;
    rp_da = rp_da - 6.2831853 * floor(rp_da / 6.2831853);
    float rp_tail = exp(-rp_da * 1.6) + exp(-(6.2831853 - rp_da) * 30.0);
    float3 rp_hue = mix(float3(1.0, 0.753, 0.302), float3(1.0, 0.95, 0.84), clamp(rp_tail, 0.0, 1.0));
    float3 rp_col = rp_hue * (rp_line * (0.28 + 1.1 * rp_tail));

    """ + glowEnd

    /// A folder's gravity well, on a billboard round its notes: faint
    /// rings crowding towards the middle, as a funnel does seen from above,
    /// drifting slowly inwards, tinted by the folder (rpTintA).
    static let well: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;
    float3 rpTintA;

    #pragma body

    """ + plane + """
    float rp_t = rpClock * rpMotion;
    float rp_rr = sqrt(rp_r);
    float rp_c = 0.5 + 0.5 * cos((rp_rr * 6.0 + rp_t * 0.04) * 6.2831853);
    rp_c = rp_c * rp_c;
    rp_c = rp_c * rp_c;
    rp_c = rp_c * rp_c;
    rp_c = rp_c * rp_c;
    float rp_fade = max(1.0 - rp_r, 0.0);
    float rp_k = rp_c * rp_fade * rp_fade * 0.1;
    rp_k = rp_k + exp(-rp_r * rp_r * 6.0) * 0.035;
    float3 rp_col = rpTintA * (rp_k * smoothstep(0.02, 0.2, rp_r));

    """ + glowEnd
}

// MARK: - checking they work

/// Which of the style shaders compiled and drew on this device. A style
/// whose shaders failed falls back to plain baked pieces (GraphStyleArt);
/// the new link falls back to GraphShaders.link, which reads the same
/// texture coordinates.
nonisolated struct GraphStyleSupport: Sendable {
    let passed: Set<String>

    func has(_ name: String) -> Bool { passed.contains(name) }

    static let none = GraphStyleSupport(passed: [])
}

/// Tries each style shader once, off the main thread, in the same tiny
/// offscreen render GraphShaderProbe uses. Bodies must also see a real
/// normal to pass.
nonisolated enum GraphStyleProbe {
    static let all: [(String, String)] = [
        ("link", GraphStyleShaders.link),
        ("bhDisk", GraphStyleShaders.bhDisk),
        ("bhRing", GraphStyleShaders.bhRing),
        ("sunBody", GraphStyleShaders.sunBody),
        ("sunCorona", GraphStyleShaders.sunCorona),
        ("rockBody", GraphStyleShaders.rockBody),
        ("moonBody", GraphStyleShaders.moonBody),
        ("halo", GraphStyleShaders.halo),
        ("gasBody", GraphStyleShaders.gasBody),
        ("gasRing", GraphStyleShaders.gasRing),
        ("pulsarCore", GraphStyleShaders.pulsarCore),
        ("pulsarGlow", GraphStyleShaders.pulsarGlow),
        ("pulsarBeam", GraphStyleShaders.pulsarBeam),
        ("cometNucleus", GraphStyleShaders.cometNucleus),
        ("cometComa", GraphStyleShaders.cometComa),
        ("cometTail", GraphStyleShaders.cometTail),
        ("orbit", GraphStyleShaders.orbit),
        ("well", GraphStyleShaders.well)
    ]

    /// Worked out once per launch (Graph3DView asks for it off the main
    /// thread, before building).
    static let support: GraphStyleSupport = run()

    private static func run() -> GraphStyleSupport {
        guard let device = MTLCreateSystemDefaultDevice() else { return .none }
        var passed = Set<String>()
        for (name, source) in all where passes(source, device: device) {
            passed.insert(name)
        }
        return GraphStyleSupport(passed: passed)
    }

    private static func passes(_ source: String, device: MTLDevice) -> Bool {
        let scene = SCNScene()
        scene.background.contents = UIColor.black
        let material = SCNMaterial()
        material.lightingModel = .constant
        guard let black = blackTexture() else { return false }
        material.diffuse.contents = black
        material.isDoubleSided = true
        material.shaderModifiers = [.surface: source]
        GraphStyleUniforms.defaults(material)
        material.setValue(NSNumber(value: 1.0), forKey: "rpProbe")
        let plane = SCNPlane(width: 4, height: 4)
        plane.materials = [material]
        scene.rootNode.addChildNode(SCNNode(geometry: plane))
        let camera = SCNCamera()
        camera.fieldOfView = 40
        let eye = SCNNode()
        eye.camera = camera
        eye.simdPosition = SIMD3<Float>(0, 0, 3)
        scene.rootNode.addChildNode(eye)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = eye
        let size = CGSize(width: 8, height: 8)
        let shot: UIImage = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .none)
        return centreBrightness(shot) > 0.5
    }

    private static func blackTexture() -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        let info: UInt32 = CGImageAlphaInfo.noneSkipLast.rawValue
        guard let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                                      bytesPerRow: 16, space: space, bitmapInfo: info)
        else { return nil }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return context.makeImage()
    }

    private static func centreBrightness(_ image: UIImage) -> Float {
        guard let cg = image.cgImage else { return 0 }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let space = CGColorSpaceCreateDeviceRGB()
        let info: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn: Bool = pixel.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4,
                                          space: space, bitmapInfo: info) else { return false }
            let middleX: CGFloat = CGFloat(cg.width) / 2
            let middleY: CGFloat = CGFloat(cg.height) / 2
            let rect = CGRect(x: -middleX, y: -middleY,
                              width: CGFloat(cg.width), height: CGFloat(cg.height))
            context.draw(cg, in: rect)
            return true
        }
        guard drawn else { return 0 }
        let top: UInt8 = max(pixel[0], max(pixel[1], pixel[2]))
        return Float(top) / 255
    }
}

/// Sets every argument the style shaders read to a safe value, so a
/// material never draws with one missing (rpKey especially: the light is
/// normalised from it).
nonisolated enum GraphStyleUniforms {
    static let key = SIMD3<Float>(-0.55, 0.45, 0.70)

    static func defaults(_ material: SCNMaterial) {
        let zero = NSNumber(value: 0.0)
        for name in ["rpClock", "rpMotion", "rpProbe", "rpSolid"] {
            material.setValue(zero, forKey: name)
        }
        for name in ["rpDetail", "rpEnergy"] {
            material.setValue(NSNumber(value: 1.0), forKey: name)
        }
        material.setValue(NSNumber(value: 0.75), forKey: "rpReach")
        let off = SCNVector4(x: 0, y: 0, z: 0, w: 0)
        for k in 0..<4 {
            material.setValue(NSValue(scnVector4: off), forKey: "rpSun\(k)")
        }
        let light: SIMD3<Float> = simd_normalize(key)
        let keyVector = SCNVector3(x: light.x, y: light.y, z: light.z)
        material.setValue(NSValue(scnVector3: keyVector), forKey: "rpKey")
        let grey = SCNVector3(x: 0.6, y: 0.6, z: 0.6)
        for name in ["rpTintA", "rpTintB", "rpTintC", "rpTintD"] {
            material.setValue(NSValue(scnVector3: grey), forKey: name)
        }
    }
}
