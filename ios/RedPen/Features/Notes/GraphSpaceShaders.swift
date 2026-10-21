import Foundation

// The node styles' shader modifiers (see GraphNodeStyles). The check that
// they compile and draw on this device is GraphStyleProbe
// (GraphNodeShaders.swift); this file is Foundation only, so they are also
// read on Linux (Tests/ShaderSourceTests, through GraphShaderCatalog) and
// compiled against a stand-in for Metal (tools/shader_check.py).
//
// They follow GraphShaders' rules: surface modifiers that write the final
// colour into `_surface.diffuse` (constant lighting), time from `rpClock`
// (GraphSim's wrapped clock) times `rpMotion` (0 with Reduce Motion, so the
// picture is still but whole), no helper functions, and `rpProbe` added at
// the end so GraphStyleProbe can tell a working modifier from a broken one.
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

    // MARK: the depth fade and detail by size

    // docs/design/depth-fade.md and plan 4e, for the Space theme. Every
    // Space shader takes `rpFade` (start, end, exponent, cap: SpaceDepthBand,
    // set by GraphSim each frame as the camera moves) and fades by the view
    // depth of its node's centre (a link by each fragment's):
    // f = clamp((z - start) / (end - start), 0, 1)^k * cap, SceneKit's fog
    // formula. A body's colour goes towards the sky's near-black by f; a
    // glow's light goes towards nothing, times (1 - f), never towards a
    // colour that would brighten it. All four 0 (a material GraphSim never
    // set) is no fade at all, so nothing changes where it is not wired.
    //
    // The bodies with noise loops also take `rpFocal` (the camera's focal
    // length in points) and weigh their fine detail by the node's radius on
    // screen, smoothly from none at `detailLow` points to all of it at
    // `detailHigh` (rp_dl = rpDetail times that): a morph between the
    // simple path and the full one, never a switch. 0 (not set) is full
    // detail. SpaceDepth (GraphSpaceDepth.swift) is the same maths in Swift.

    /// The sky's near-black a far body dissolves into (sRGB): between the
    /// sky's darkest (its poles) and its band (GraphSpace.skyColour).
    static let fadeSRGB = SIMD3<Float>(0.011, 0.019, 0.058)
    /// The same in linear light, as the endings mix it.
    static var fadeLinear: SIMD3<Float> {
        SIMD3<Float>(pow(fadeSRGB.x, 2.2), pow(fadeSRGB.y, 2.2), pow(fadeSRGB.z, 2.2))
    }
    /// A body's radius on screen (points) where its fine detail starts to
    /// come in, and where all of it is there.
    static let detailLow: Float = 8
    static let detailHigh: Float = 32

    static func literal(_ v: Float) -> String { String(format: "%.6f", Double(v)) }

    /// The fade factor `rp_dfF` for the view depth `z` (a float expression,
    /// in front of the eye positive).
    static func depthFade(_ z: String) -> String {
        """
        float rp_dfZ = \(z);
        float rp_dfW = rpFade.y - rpFade.x;
        float rp_dfF = 0.0;
        if (rp_dfW > 0.0001) {
        rp_dfF = pow(clamp((rp_dfZ - rpFade.x) / rp_dfW, 0.0, 1.0), max(rpFade.z, 0.0001)) * rpFade.w;
        }

        """
    }

    /// `rp_dl`: rpDetail weighed by the node's size on screen. Needs
    /// `rpDetail` and `rpFocal` declared.
    static var detail: String {
        """
        float rp_lodZ = max(-scn_node.modelViewTransform[3].z, 0.001);
        float rp_lodPx = length(scn_node.modelTransform[0].xyz) * rpFocal / rp_lodZ;
        float rp_lod = 1.0;
        if (rpFocal > 0.0) {
        rp_lod = smoothstep(\(literal(detailLow)), \(literal(detailHigh)), rp_lodPx);
        }
        float rp_dl = rpDetail * rp_lod;

        """
    }

    /// bodyEnd, faded towards the sky by the node's depth.
    static var fadedBodyEnd: String {
        let c: SIMD3<Float> = fadeLinear
        return """
        rp_col = pow(clamp(rp_col, float3(0.0), float3(1.0)), float3(2.2));

        """ + depthFade("-scn_node.modelViewTransform[3].z") + """
        rp_col = mix(rp_col, float3(\(literal(c.x)), \(literal(c.y)), \(literal(c.z))), rp_dfF);
        float rp_ok = step(0.5, length(_surface.normal));
        _surface.diffuse = float4(rp_col + float3(rpProbe * rp_ok), 1.0);
        """
    }

    /// glowEnd, its light faded to nothing by the node's depth.
    static var fadedGlowEnd: String {
        """
        rp_col = pow(max(rp_col, float3(0.0)), float3(2.2));

        """ + depthFade("-scn_node.modelViewTransform[3].z") + """
        rp_col = rp_col * (1.0 - rp_dfF);
        _surface.diffuse = float4(rp_col + float3(rpProbe), 1.0);
        """
    }

    // MARK: the link

    /// A link: GraphShaders.link's calm beam, plus what each end's style does
    /// to it. u = ((styleA * 8 + styleB) * 16 + seed) * 64 + 1 + distance
    /// along; v as before (length in sixteenths doubled, plus the lit bit,
    /// plus the position across). The A end is always the higher style
    /// code: suns and pulsars send, black holes swallow (GraphRibbons).
    ///
    /// - black hole: the beam narrows, reddens and fades into the horizon;
    ///   at a B end its core spirals in and its pulses speed up as they
    ///   fall, and simply go into the dark (a flash on arrival read on
    ///   screen as a grey smudge on the photon ring);
    /// - sun: hotter and whiter near it; at an A end pulses leave it fast
    ///   and swollen, like ejected plasma, then slow;
    /// - rocky planet: bluer near it, and each arriving pulse glints;
    /// - gas giant: a wider haze, and a bar of light across the beam where
    ///   it crosses the ring, brighter as pulses arrive;
    /// - pulsar: rings of blue-white run out along it, two per turn of its
    ///   beams (period GraphNodeStyle.pulsarPeriod);
    /// - comet: icy, with twinkling dust.
    ///
    /// Near each end the beam narrows (to a third of its width at the end),
    /// and the strip itself ends in a rounded cap (an eighth of the reach
    /// long), so its glow meets the body as a point of light, never a
    /// square cut. Near each body the whole beam is dimmed (to a quarter at
    /// the limb, full strength from 0.9 of the reach out), so the body is
    /// the brightest thing there, and the colour saturates softly
    /// (1 - e^-x) so no beam or overlap of beams clips to white. A small
    /// body (a pulsar, a comet: a few pixels where a planet is a disc)
    /// dims and narrows its links further and for longer - to 4% and a
    /// sixth of the width at the end, full only from 2.2 reaches out - so
    /// the many beams meeting there never outshine it or cover its coma.
    ///
    /// Every end but a black hole's flares where the beam leaves the body's
    /// limb (the strip starts inside the body, which hides the rest), the
    /// sending end the brighter, both brighter as pulses arrive.
    ///
    /// Everywhere: fine filament particles - small warm motes drifting along
    /// the beam, two layers at their own speeds, twinkling - and when the
    /// link touches a chosen or dragged sun at its sending end, plasma
    /// streaming out along it in quick bright blobs.
    static let link: String = """
    #pragma arguments
    float4 rpFade;
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
    float rp_smA = rp_cmA + rp_psA;
    float rp_smB = rp_cmB + rp_psB;
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
    float rp_tpA = smoothstep(0.0, (0.6 + 1.8 * rp_smA) * rp_reach, rp_along);
    float rp_tpB = smoothstep(0.0, (0.6 + 1.8 * rp_smB) * rp_reach, rp_toEnd);
    float rp_wlo = 0.3 - 0.14 * clamp(rp_smA + rp_smB, 0.0, 1.0);
    float rp_wf = rp_wlo + (1.0 - rp_wlo) * rp_tpA * rp_tpB;
    rp_a2 = rp_a2 / (rp_wf * rp_wf);
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
    float rp_inner = exp(-rp_a2 * 22.0) * rp_w2;
    float rp_breath = 1.0 + 0.1 * rp_m * sin(rp_t * 1.0471976 + rp_seed * 2.3);
    float rp_thick = (0.7 + 0.5 * rp_nH) * rp_breath * (1.0 + 0.8 * rp_gsW);
    float rp_haze = exp(-rp_a2 * 6.0 / (rp_thick * rp_thick)) * rp_w3;
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
    float rp_still = (1.0 - rp_m) * rp_lit;
    rp_arrive = rp_arrive + 0.55 * rp_still;

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
    rp_col = rp_col + rp_fl * (rp_w2 * 0.4 * (1.0 + rp_sunW) * exp(-rp_a2 * 3.0));

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

    float rp_mq = rp_x * 5.0 - rp_t * 1.15 + rp_seed * 0.71;
    float rp_mi = floor(rp_mq);
    float rp_mh = fract(sin(rp_mi * 17.31 + rp_seed * 5.13) * 43758.5453);
    float rp_my = (fract(rp_mh * 13.7) - 0.5) * 1.1;
    float rp_md = (fract(rp_mq) - 0.5) * 5.7;
    float rp_mc = (rp_s - rp_my) / 0.09;
    float rp_mote = exp(-rp_md * rp_md - rp_mc * rp_mc) * step(0.5, rp_mh);
    float rp_oq = rp_x * 3.0 + rp_t * 0.55 + rp_seed * 1.9;
    float rp_oi = floor(rp_oq);
    float rp_oh = fract(sin(rp_oi * 29.17 + rp_seed * 3.71) * 43758.5453);
    float rp_oy = (fract(rp_oh * 7.3) - 0.5) * 1.3;
    float rp_od = (fract(rp_oq) - 0.5) * 4.2;
    float rp_oc = (rp_s - rp_oy) / 0.07;
    rp_mote = rp_mote + 0.6 * exp(-rp_od * rp_od - rp_oc * rp_oc) * step(0.62, rp_oh);
    float rp_mtw = 0.55 + 0.45 * sin(rp_t * 5.0 + rp_mh * 40.0);
    rp_col = rp_col + mix(rp_gold, rp_white, 0.6) * (rp_mote * rp_mtw * 0.55 * rp_w * rp_m);

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

    float rp_drag = rp_lit * rp_sunA * rp_m;
    float rp_jq = rp_x * 1.4 - rp_t * 2.6 + rp_seed * 0.9;
    float rp_jf = fract(rp_jq) - 0.5;
    float rp_jh = fract(sin(floor(rp_jq) * 11.3 + rp_seed) * 43758.5453);
    float rp_jet = exp(-rp_jf * rp_jf * 70.0) * exp(-rp_a2 * 9.0) * (0.5 + 0.5 * rp_jh);
    rp_jet = rp_jet * (0.35 + 0.65 * exp(-rp_along / (3.0 * rp_reach)));
    rp_col = rp_col + float3(1.0, 0.9, 0.66) * (rp_jet * rp_drag * 1.3);

    float rp_cx = floor(rp_x * 16.0);
    float rp_cy = floor(rp_s0 * 4.0);
    float rp_ch = fract(sin(rp_cx * 17.13 + rp_cy * 5.71 + rp_seed) * 43758.5453);
    float rp_cf = fract(rp_x * 16.0) - 0.5;
    float rp_cg = fract(rp_s0 * 4.0) - 0.5;
    float rp_speck = exp(-(rp_cf * rp_cf + rp_cg * rp_cg) * 60.0);
    rp_speck = rp_speck * step(0.72, rp_ch);
    float rp_twk = 0.5 + 0.5 * sin(rp_t * 5.0 + rp_ch * 40.0);
    rp_col = rp_col + float3(0.8, 1.0, 1.0) * (rp_speck * rp_twk * rp_cmW * 0.9 * rp_w);

    rp_col = rp_col + mix(rp_gold, rp_white, 0.5) * (rp_still * (rp_core * 1.1 + rp_inner * 0.3));

    float rp_f = sin(rp_t * 4.1 + rp_seed * 3.1);
    rp_f = rp_f * sin(rp_t * 2.3 + rp_seed * 7.7);
    float rp_flicker = 1.0 - 0.08 * rp_m * (0.5 + 0.5 * rp_f);
    float rp_boost = 1.0 + 0.5 * rp_lit;
    float rp_fadeA = 0.05 + rp_bhA * 0.5 * rp_reach;
    float rp_fadeB = 0.05 + rp_bhB * 0.5 * rp_reach;
    float rp_ends = smoothstep(0.0, rp_fadeA, rp_along);
    rp_ends = rp_ends * smoothstep(0.0, rp_fadeB, rp_toEnd);
    rp_col = rp_col * (rp_flicker * rp_boost * rp_ends);

    float rp_gd = (rp_toEnd - 0.12) / (0.2 * rp_reach);
    float rp_gs = rp_s0 * 1.3;
    float rp_star = exp(-(rp_gd * rp_gd + rp_gs * rp_gs) * 3.0);
    float rp_arms = exp(-rp_gd * rp_gd * 40.0) * exp(-rp_gs * rp_gs * 0.8);
    float rp_arm2 = exp(-rp_gs * rp_gs * 60.0);
    rp_arms = rp_arms + rp_arm2 * exp(-rp_gd * rp_gd * 0.6);
    float rp_glint = (rp_star + rp_arms * 0.6) * rp_arrive * rp_rkB * rp_w;
    rp_col = rp_col + float3(0.8, 0.92, 1.0) * (rp_glint * 1.5);
    float rp_gsA = step(1.5, rp_sA) - step(2.5, rp_sA);
    float rp_gbA = (rp_along - 1.2 * rp_reach) / (0.1 * rp_reach);
    float rp_gbB = (rp_toEnd - 1.2 * rp_reach) / (0.1 * rp_reach);
    float rp_bar = exp(-rp_gbA * rp_gbA) * rp_gsA + exp(-rp_gbB * rp_gbB) * rp_gsB;
    rp_bar = rp_bar * rp_w * (0.45 + 0.4 * rp_lit + 0.9 * rp_arrive);
    rp_col = rp_col + float3(1.0, 0.9, 0.7) * (rp_bar * 0.7);
    float rp_lA = rp_along / 0.07;
    float rp_lB = rp_toEnd / 0.07;
    float rp_touch = exp(-rp_lA * rp_lA) * (1.0 - rp_bhA);
    rp_touch = rp_touch + 0.6 * exp(-rp_lB * rp_lB) * (1.0 - rp_bhB);
    rp_touch = rp_touch * exp(-rp_s0 * rp_s0 * 5.0) * (0.9 + 0.6 * rp_lit + 0.5 * rp_arrive);
    rp_col = rp_col + mix(rp_gold, rp_white, 0.6) * rp_touch;
    float rp_capL = 0.12 * rp_reach;
    float rp_cA = 1.0 - clamp(rp_along / rp_capL, 0.0, 1.0);
    float rp_cB = 1.0 - clamp(rp_toEnd / rp_capL, 0.0, 1.0);
    float rp_cw = sqrt(max(1.0 - max(rp_cA * rp_cA, rp_cB * rp_cB), 0.0));
    float rp_cap = 1.0 - smoothstep(0.55, 1.0, rp_e / max(rp_cw, 0.001));
    float rp_dimA = smoothstep(0.1 * rp_reach, (0.9 + 1.3 * rp_smA) * rp_reach, rp_along);
    float rp_dimB = smoothstep(0.1 * rp_reach, (0.9 + 1.3 * rp_smB) * rp_reach, rp_toEnd);
    float rp_dim = mix(0.25 - 0.21 * rp_smA, 1.0, mix(rp_dimA, rp_dimA * rp_dimA, rp_smA));
    rp_dim = rp_dim * mix(0.25 - 0.21 * rp_smB, 1.0, mix(rp_dimB, rp_dimB * rp_dimB, rp_smB));
    rp_col = rp_col * rp_cap * rp_dim * rpEnergy;
    rp_col = (float3(1.0) - exp(-rp_col * 1.3)) * 0.92;

    """ + depthFade("-_surface.position.z") + """
    rp_col = rp_col * (1.0 - rp_dfF);
    _surface.diffuse = float4(rp_col + float3(rpProbe), 1.0);
    """

    // MARK: the black hole

    /// The accretion disk, face on in its own plane (GraphSim turns the
    /// plane), where the ray-traced ring (bhRing) is not used: streaky
    /// orbits in 34 lanes, each lane turning rigidly at Kepler's pace for
    /// its radius, so inner lanes run ahead and the pattern shears without
    /// ever winding up or being redrawn (no cross-fade); three hot spots
    /// each at its own orbital pace; Doppler beaming from the real direction
    /// each point moves relative to the eye; and a thin line on the
    /// innermost stable orbit. At full quality the lanes also carry
    /// turbulent streaks (value noise drawn long along the orbit). The
    /// plane's z scale carries how hard the note is moving: the disk runs
    /// hotter (flares when dragged).
    static let bhDisk: String = """
    #pragma arguments
    float4 rpFade;
    float rpClock;
    float rpMotion;
    float rpDetail;
    float rpFocal;
    float rpProbe;

    #pragma body

    """ + plane + planeCode + detail + """
    float rp_in = 0.43;
    float rp_u = (rp_r - rp_in) / (1.0 - rp_in);
    float rp_a = atan2(rp_qy, rp_qx);
    float rp_t = rpClock * rpMotion;
    float rp_kep = pow(rp_in / max(rp_r, rp_in), 1.5);
    float rp_rb = floor(rp_r * 34.0);
    float rp_lane = pow(rp_in / max((rp_rb + 0.5) / 34.0, rp_in), 1.5);
    float rp_a1 = rp_a - 1.4 * rp_lane * rp_t;
    float rp_h1 = fract(sin(rp_rb * 7.13) * 43758.5453);
    float rp_k1 = 1.0 + floor(rp_h1 * 4.0);
    float rp_v1 = sin(rp_a1 * 3.0 + rp_r * 20.0) * 0.6;
    float rp_arc1 = 0.5 + 0.5 * sin(rp_a1 * rp_k1 + rp_h1 * 6.2831 + rp_v1);
    rp_arc1 = rp_arc1 * rp_arc1 * rp_arc1;
    float rp_fw1 = sin(rp_a1 * 5.0 + rp_h1 * 3.0) * 1.4;
    float rp_fn1 = 0.5 + 0.5 * sin(rp_r * 170.0 + rp_fw1);
    float rp_pat = 0.3 + 0.45 * rp_arc1 * (0.4 + 0.6 * rp_h1);
    rp_pat = (rp_pat + 0.25 * rp_fn1) * (0.85 + 0.15 * rp_kep);
    if (rp_dl > 0.0) {

    """ + GraphShaderKit.noise("rp_dn1", "float3(cos(rp_a1) * 2.6, sin(rp_a1) * 2.6, rp_r * 30.0)") + """
    rp_pat = rp_pat * mix(1.0, 0.68 + 0.64 * rp_dn1, rp_dl);
    }
    float rp_rise = smoothstep(0.0, 0.05, rp_u);
    float rp_fall = pow(max(1.0 - rp_u, 0.0), 1.2);
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
    float rp_h = rp_heat * 1.9 * (0.55 + 0.45 * rp_boost);
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

    """ + fadedGlowEnd

    /// The black hole as the eye sees it, ray-traced on the billboard in
    /// front of the black sphere (the shadow): every pixel is a light ray
    /// arriving with impact parameter b (the shadow's edge, b = 1, is the
    /// sphere's limb; rs = 1 / 2.6). The ray's plane holds the eye and the
    /// pixel's direction; where that plane cuts the disk, and Beloborodov's
    /// bending (1 - cos a = (1 - cos psi)(1 - rs/r), b = r sin a /
    /// sqrt(1 - rs/r), four fixed-point steps), say which radius of the disk
    /// the ray left. So the near side of the disk crosses in front of the
    /// shadow, and its far side is seen bent up over the top and under the
    /// bottom (the lensed arcs), without a second plane.
    ///
    /// The disk: a Novikov-Thorne-like glow (T^4 ~ r^-3 (1 - sqrt(r_in/r)))
    /// from the innermost stable orbit (3 rs, drawn as a thin line), in
    /// thin lanes that each turn at their own Kepler rate (so the pattern
    /// shears into streaks and never winds up), with turbulent streaks and
    /// two hot spots; Doppler beaming and gravitational redshift from the
    /// gas's real motion against the photon's direction (g^4, and colour
    /// from the shifted temperature). Round the shadow: the photon ring and,
    /// just outside it, the thin second image of the disk; stars behind
    /// sheared into arcs near the Einstein radius.
    ///
    /// GraphStyleAnimator turns the plane so +x is the side of the disk
    /// coming towards the eye, and its z scale carries sin i, the side the
    /// eye is on and the motion (SpaceOptics.holeCode). Dragged, the disk
    /// runs hotter, puffs out and sheds matter in spiral streamers.
    /// `rpDisk` 0 is a dormant hole: the shadow and its ring alone.
    static let bhRing: String = """
    #pragma arguments
    float4 rpFade;
    float rpClock;
    float rpMotion;
    float rpDetail;
    float rpFocal;
    float rpProbe;
    float rpDisk;

    #pragma body

    """ + plane + detail + """
    float rp_code = length(scn_node.modelTransform[2].xyz) - 2.0;
    float rp_above = rp_code < 0.0 ? -1.0 : 1.0;
    float rp_v = min(abs(rp_code), 0.99999);
    float rp_kq = floor(rp_v * 256.0);
    float rp_k = rp_kq / 255.0;
    float rp_m = clamp((rp_v * 256.0 - rp_kq - 0.02) / 0.96, 0.0, 1.0) * rpMotion;
    float rp_t = rpClock * rpMotion;
    float3 rp_pos = scn_node.modelTransform[3].xyz;
    float rp_seed = fract(dot(rp_pos, float3(0.37, 0.51, 0.29)));
    float rp_ci = rp_above * sqrt(max(1.0 - rp_k * rp_k, 0.0));
    float3 rp_n = float3(0.0, -rp_k, rp_ci);
    float rp_H = 3.0;
    float rp_X = rp_qx * rp_H;
    float rp_Y = rp_qy * rp_H;
    float rp_b = sqrt(rp_X * rp_X + rp_Y * rp_Y) + 0.00001;
    float3 rp_e = float3(rp_X / rp_b, rp_Y / rp_b, 0.0);
    float rp_en = dot(rp_e, rp_n);
    float rp_cs = rp_n.z < 0.0 ? rp_en : -rp_en;
    float rp_psi0 = atan2(abs(rp_n.z) + 0.0001, rp_cs);
    float rp_rs = 0.385;
    float rp_rin = 1.155;
    float rp_rout = 2.5 * (1.0 + 0.18 * rp_m);
    float3 rp_d2 = float3(0.0, rp_n.z, rp_k);
    float3 rp_col = float3(0.0);
    float rp_lit = 0.0;
    float rp_s1 = 0.5;
    float rp_om = 0.9;
    int rp_images = rp_dl > 0.0 ? 2 : 1;
    for (int rp_img = 0; rp_img < rp_images; rp_img++) {
    float rp_two = float(rp_img);
    float rp_psi = rp_psi0 + 3.14159265 * rp_two;
    float rp_bi = mix(rp_b, 1.0 + (rp_b - 1.0) * 3.5, rp_two);
    float rp_sp = sin(rp_psi);
    float rp_cp = cos(rp_psi);
    float rp_x = 1.0 - rp_cp;
    float rp_rr = max(rp_bi, 0.5);
    for (int rp_i = 0; rp_i < 4; rp_i++) {
    float rp_ui = min(rp_rs / rp_rr, 0.95);
    float rp_cai = 1.0 - rp_x * (1.0 - rp_ui);
    float rp_sai = sqrt(max(1.0 - rp_cai * rp_cai, 0.0001));
    rp_rr = max(rp_bi, 0.0) * sqrt(1.0 - rp_ui) / rp_sai;
    }
    float rp_u = min(rp_rs / rp_rr, 0.95);
    float rp_ca = 1.0 - rp_x * (1.0 - rp_u);
    float rp_sa = sqrt(max(1.0 - rp_ca * rp_ca, 0.0001));
    float3 rp_P = float3(rp_e.x * rp_sp, rp_e.y * rp_sp, rp_cp);
    float rp_phi = atan2(dot(rp_P, rp_d2), rp_P.x);
    float rp_front = rp_b < 1.0 ? 1.0 - smoothstep(1.2, 1.6, rp_psi) : 1.0;
    float rp_seen = mix(rp_front, step(1.0, rp_b) * 0.55 * rp_dl, rp_two);
    float rp_on = rp_seen * smoothstep(rp_rin - 0.04, rp_rin + 0.02, rp_rr) * (1.0 - smoothstep(rp_rout * 0.72, rp_rout, rp_rr));
    float rp_rn = max(rp_rr / rp_rin, 1.0);
    float rp_prof = 17.6 * (1.0 - 1.0 / sqrt(rp_rn)) / (rp_rn * rp_rn * rp_rn);
    rp_prof = rp_prof + 0.18 * exp(-(rp_rn - 1.0) * 6.0);

    float rp_lanes = 26.0;
    float rp_ln = floor(rp_rr * rp_lanes);
    float rp_lc = max((rp_ln + 0.5) / rp_lanes, rp_rin);
    rp_om = 0.9 * pow(rp_rin / rp_lc, 1.5);
    float rp_ph = rp_phi - rp_om * rp_t + rp_ln * 1.7 + rp_seed * 6.2831853;
    float rp_lh = fract(sin(rp_ln * 12.9898 + rp_seed * 7.0) * 43758.5453);

    """ + GraphShaderKit.noise("rp_n1", "float3(cos(rp_ph) * 2.4, sin(rp_ph) * 2.4, rp_ln * 0.61)") + """
    rp_s1 = mix(rp_n1, rp_s1, rp_two);
    float rp_streak = 0.45 + 0.9 * rp_n1 * (0.6 + 0.4 * rp_lh);
    if (rp_dl > 0.0) {

    """ + GraphShaderKit.noise("rp_n2", "float3(cos(rp_ph) * 7.0, sin(rp_ph) * 7.0, rp_rr * 40.0)") + """
    rp_streak = rp_streak * mix(1.0, 0.62 + 0.76 * rp_n2, rp_dl);
    }
    float rp_fine = 0.82 + 0.18 * sin(rp_rr * 150.0 + rp_n1 * 5.0);
    float rp_hA = rp_phi - 0.9 * pow(rp_rin / 1.45, 1.5) * rp_t - 0.7;
    rp_hA = rp_hA - 6.2831853 * floor(rp_hA / 6.2831853 + 0.5);
    float rp_hB = rp_phi - 0.9 * pow(rp_rin / 1.9, 1.5) * rp_t - 3.4;
    rp_hB = rp_hB - 6.2831853 * floor(rp_hB / 6.2831853 + 0.5);
    float rp_dA = (rp_rr - 1.45) / 0.06;
    float rp_dB = (rp_rr - 1.9) / 0.07;
    float rp_hot = exp(-rp_dA * rp_dA - rp_hA * rp_hA * 9.0) * 0.9 + exp(-rp_dB * rp_dB - rp_hB * rp_hB * 7.0) * 0.6;
    float rp_mat = rp_streak * rp_fine + rp_hot;

    float rp_beta = min(sqrt(rp_rs / (2.0 * max(rp_rr - rp_rs, 0.3))), 0.6);
    float3 rp_vel = cross(rp_n, rp_P);
    float3 rp_T = float3(-rp_e.x * rp_cp, -rp_e.y * rp_cp, rp_sp);
    float3 rp_kd = rp_P * rp_ca + rp_T * rp_sa;
    float rp_cth = dot(rp_vel, rp_kd);
    float rp_gam = 1.0 / sqrt(1.0 - rp_beta * rp_beta);
    float rp_g = sqrt(max(1.0 - 1.5 * rp_rs / rp_rr, 0.05)) / (rp_gam * (1.0 - rp_beta * rp_cth));
    rp_g = mix(1.0, rp_g, 0.8);
    float rp_boost = clamp(rp_g * rp_g * rp_g, 0.04, 6.0);
    float rp_heat = pow(max(rp_prof, 0.0), 0.25) * rp_g * (1.0 + 0.3 * rp_m);
    float3 rp_hue = mix(float3(0.45, 0.04, 0.0), float3(1.0, 0.3, 0.03), clamp(rp_heat / 0.45, 0.0, 1.0));
    rp_hue = mix(rp_hue, float3(1.0, 0.62, 0.24), clamp((rp_heat - 0.45) / 0.3, 0.0, 1.0));
    rp_hue = mix(rp_hue, float3(1.0, 0.9, 0.72), clamp((rp_heat - 0.75) / 0.3, 0.0, 1.0));
    rp_hue = mix(rp_hue, float3(0.86, 0.92, 1.0), clamp((rp_heat - 1.1) / 0.4, 0.0, 1.0));
    float rp_lum = rp_prof * rp_mat * rp_boost * (1.0 + 0.7 * rp_m);
    rp_lum = rp_lum / (1.0 + 0.45 * rp_lum);
    rp_col = rp_col + rp_hue * (rp_lum * 1.3 * rp_on * rpDisk);
    rp_lit = max(rp_lit, rp_lum * rp_on);
    float rp_id = (rp_rr - rp_rin) / 0.018;
    float rp_isco = exp(-rp_id * rp_id) * rp_seen * clamp(rp_boost, 0.3, 2.5) * rpDisk;
    rp_col = rp_col + float3(1.0, 0.86, 0.6) * (rp_isco * 0.55);
    float rp_sr = rp_rr / rp_rout;
    float rp_arm = rp_phi + 2.6 * log(max(rp_sr, 0.5)) - rp_t * 0.5;

    """ + GraphShaderKit.noise("rp_sh", "float3(cos(rp_arm) * 2.0, sin(rp_arm) * 2.0, rp_rr * 3.0 - rp_t * 0.4)") + """
    float rp_shed = smoothstep(0.85, 1.0, rp_sr) * exp(-max(rp_sr - 1.0, 0.0) * 2.6) * smoothstep(0.5, 0.8, rp_sh);
    rp_col = rp_col + float3(1.0, 0.42, 0.08) * (rp_shed * rp_m * rp_seen * clamp(rp_boost, 0.2, 3.0) * 0.5 * rpDisk);
    }

    float rp_side = 0.5 + 0.5 * rp_e.x * rp_k;
    float rp_pd = (rp_b - 1.012) / 0.011;
    float rp_ring = exp(-rp_pd * rp_pd) * (0.35 + 1.4 * rp_side * rp_side);
    float rp_ld = (rp_b - 1.05) / 0.016;
    float rp_echo = exp(-rp_ld * rp_ld) * (0.3 + 0.8 * rp_side) * (0.6 + 0.6 * rp_s1) * rpDisk * (1.0 - rp_dl);
    float3 rp_ringHue = mix(float3(1.0, 0.7, 0.35), float3(1.0, 0.95, 0.86), rp_side);
    rp_col = rp_col + rp_ringHue * (rp_ring * (1.1 + 0.6 * rp_m) + rp_echo * 0.5);
    float rp_out = max(rp_b - 1.0, 0.0);
    rp_col = rp_col + float3(1.0, 0.5, 0.15) * (exp(-rp_out / 0.35) * 0.05 * step(1.0, rp_b) * (0.5 + rp_side));
    if (rp_dl > 0.0) {
    float rp_sa2 = atan2(rp_Y, rp_X);
    float rp_lr = floor(rp_b * 9.0);
    float rp_la = floor(rp_sa2 * 4.0 + rp_lr * 0.37);
    float rp_lsh = fract(sin(rp_la * 12.9898 + rp_lr * 78.233) * 43758.5453);
    float rp_cr = (rp_lr + 0.5) / 9.0;
    float rp_ang = (rp_la + 0.5 - rp_lr * 0.37) / 4.0;
    float rp_dAng = (rp_sa2 - rp_ang) * rp_b;
    float rp_ez = (rp_b - 1.35) / 0.25;
    float rp_ein = exp(-rp_ez * rp_ez);
    float rp_stx = rp_dAng / (0.02 + 0.2 * rp_ein);
    float rp_sty = (rp_b - rp_cr) / 0.012;
    float rp_star = exp(-rp_stx * rp_stx - rp_sty * rp_sty) * step(0.8, rp_lsh) * step(1.06, rp_b);
    rp_col = rp_col + float3(0.75, 0.85, 1.0) * (rp_star * 0.35 * (1.0 - min(rp_lit, 1.0)) * rp_dl);
    }
    float rp_edge = clamp((1.0 - rp_r) / 0.1, 0.0, 1.0);
    rp_col = rp_col * (rp_edge * rp_edge * (3.0 - 2.0 * rp_edge));

    """ + fadedGlowEnd

    // MARK: the sun

    /// The sun's face. Granulation: cellular noise (GraphShaderKit.cells) -
    /// bright convection cells, each its own brightness, parted by narrow
    /// dark lanes, every cell's centre wandering so the surface boils; under
    /// a slower supergranular mottling (value noise), with finer cells at
    /// full quality. A sunspot group: dark umbrae in penumbrae of radial
    /// filaments, shallower towards the limb, to a seventh of their depth
    /// at the edge (foreshortened there, a full-depth umbra read as a hole
    /// in the sun). Faculae: bright patches towards the limb, and a bright
    /// network round each spot there, so a spot near the edge sits in its
    /// active region as on the real sun. Limb darkening
    /// that also reddens the edge (I = 1 - 0.56 (1 - mu) - 0.22 (1 - mu)^2,
    /// the colour from the temperature it leaves). A flare beside the spots
    /// brightens and dies back on its own clock. Moving (its z scale), it
    /// runs hotter.
    static let sunBody: String = """
    #pragma arguments
    float4 rpFade;
    float rpClock;
    float rpMotion;
    float rpDetail;
    float rpFocal;
    float rpProbe;

    #pragma body

    """ + axes + sphere + sphereMotion + detail + """
    float rp_t = rpClock * rpMotion;
    float rp_lm = 1.0 - rp_mu;
    float rp_limb = 1.0 - 0.56 * rp_lm - 0.22 * rp_lm * rp_lm;

    """ + GraphShaderKit.noise("rp_sg", "rp_p * 4.0 + float3(0.0, rp_t * 0.015, 0.0)") + """
    float3 rp_cv = scn_node.modelViewTransform[3].xyz;
    float rp_depth = max(length(rp_cv), 0.001);
    float3 rp_eye = -rp_cv / rp_depth;
    float rp_px = 2600.0 * length(scn_node.modelTransform[0].xyz) / rp_depth;
    float rp_near = smoothstep(120.0, 420.0, rp_px);
    float3 rp_gp = rp_p * 46.0 + float3(rp_sg * 1.2, 0.0, rp_sg * 0.8);
    float rp_gran = 0.86 + 0.28 * (rp_sg - 0.5);
    if (rp_near > 0.001) {

    """ + GraphShaderKit.cells("rp_c1", "rp_gp", wobble: "rp_t * 0.35") + """
    float rp_lane = rp_c1_f2 - rp_c1_f1;
    float rp_cell = 0.8 + 0.2 * smoothstep(0.0, 0.22, rp_lane);
    rp_cell = rp_cell * (0.93 + 0.14 * rp_c1_id) * (1.0 - 0.12 * smoothstep(0.25, 0.8, rp_c1_f1));
    rp_gran = mix(rp_gran, rp_gran * rp_cell * 1.08, rp_near);
    }
    if (rp_dl > 0.0) {

    """ + GraphShaderKit.noise("rp_g2", "rp_p * 18.0 + float3(5.0, 1.0, rp_t * 0.05)") + """
    rp_gran = rp_gran * mix(1.0, 0.94 + 0.12 * rp_g2, rp_dl);
    }
    float rp_sd = dot(rp_p, float3(0.35, 0.28, 0.894));
    float rp_um = smoothstep(0.9935, 0.9965, rp_sd);
    float rp_pen = smoothstep(0.981, 0.9925, rp_sd);
    float rp_fa = atan2(dot(rp_p, float3(0.1021, -0.9599, 0.2607)), dot(rp_p, float3(-0.931, 0.0, 0.3646)));
    float rp_fil = 0.65 + 0.35 * sin(rp_fa * 60.0 + rp_sg * 6.0);
    float rp_sd2 = dot(rp_p, float3(0.47, 0.2, 0.86));
    float rp_um2 = smoothstep(0.9978, 0.9991, rp_sd2);
    float rp_pen2 = smoothstep(0.9935, 0.9975, rp_sd2);
    float rp_sd3 = dot(rp_p, float3(0.29, 0.36, 0.887));
    float rp_um3 = smoothstep(0.9985, 0.9994, rp_sd3);
    float rp_pen3 = smoothstep(0.9958, 0.9984, rp_sd3);
    float rp_spot = (rp_pen - rp_um) * rp_fil * 0.45 + rp_um * 0.78;
    rp_spot = rp_spot + (rp_pen2 - rp_um2) * 0.4 + rp_um2 * 0.72;
    rp_spot = rp_spot + (rp_pen3 - rp_um3) * 0.38 + rp_um3 * 0.7;
    rp_spot = rp_spot * (0.12 + 0.73 * smoothstep(0.2, 0.8, rp_mu));
    float rp_act = smoothstep(0.955, 0.985, rp_sd) * (1.0 - rp_pen) + smoothstep(0.984, 0.993, rp_sd2) * (1.0 - rp_pen2);
    rp_act = min(rp_act + smoothstep(0.989, 0.9955, rp_sd3) * (1.0 - rp_pen3), 1.0);
    float rp_fac = (smoothstep(0.62, 0.8, rp_sg) * 0.3 + rp_act * (0.12 + 0.14 * rp_sg)) * smoothstep(0.35, 0.85, rp_lm);
    float rp_fc = rp_t / 11.0;
    float rp_fl = fract(rp_fc);
    float rp_fd = dot(rp_p, normalize(float3(0.41, 0.17, 0.9)));
    float rp_fz = (1.0 - rp_fd) / 0.0012;
    float rp_flare = exp(-rp_fz * rp_fz) * exp(-rp_fl * 6.0) * smoothstep(0.0, 0.03, rp_fl) * 1.4 * rpMotion;
    float rp_temp = rp_gran - rp_spot * (1.0 - rp_flare) + rp_fac;
    float rp_heat = rp_temp * (0.12 + 0.88 * rp_limb) * 1.15 * (1.0 + 0.16 * rp_m) + rp_flare;
    float3 rp_col = mix(float3(0.55, 0.08, 0.0), float3(0.98, 0.36, 0.03), clamp(rp_heat / 0.42, 0.0, 1.0));
    rp_col = mix(rp_col, float3(1.0, 0.7, 0.22), clamp((rp_heat - 0.42) / 0.25, 0.0, 1.0));
    rp_col = mix(rp_col, float3(1.0, 0.9, 0.62), clamp((rp_heat - 0.67) / 0.22, 0.0, 1.0));
    rp_col = mix(rp_col, float3(1.0, 0.98, 0.9), clamp((rp_heat - 0.89) / 0.2, 0.0, 1.0));
    rp_col = rp_col * (0.25 + 0.85 * clamp(rp_heat, 0.0, 1.3));

    """ + fadedBodyEnd

    /// The corona round the sun, on the lifted billboard (the limb at a
    /// quarter of the half side): a soft inner corona falling off gently
    /// out to the billboard's edge,
    /// helmet streamers whose strength wanders round the limb (value noise
    /// of the angle, drifting), fine polar plumes, and a thin rosy
    /// chromosphere on the limb with spicules. Three prominences: arches of
    /// glowing plasma standing on the limb, threaded with filaments, each
    /// rising out of the limb on its own clock and sinking back into it, a
    /// new one rising elsewhere after it. Now and then a flare blows a loop
    /// of plasma up off the limb, white cooling to orange, its feet always
    /// on the sun (nothing comes loose to float away).
    /// The plane's z scale carries the note's own seed and how hard it is
    /// moving (SpaceOptics.coronaCode: 2 + seed + motion * 0.03), so no two
    /// suns flare in step, and dragged, its streamers stream outward, longer
    /// and brighter, and the plasma runs out along them.
    static let sunCorona: String = """
    #pragma arguments
    float4 rpFade;
    float rpClock;
    float rpMotion;
    float rpDetail;
    float rpProbe;

    #pragma body

    """ + plane + """
    float rp_code = clamp(length(scn_node.modelTransform[2].xyz) - 2.0, 0.0, 0.9999);
    float rp_sq = floor(rp_code * 32.0) / 32.0;
    float rp_seed = rp_sq * 6.2831853;
    float rp_mv = clamp((rp_code - rp_sq) * 32.0 / 0.96, 0.0, 1.0) * rpMotion;
    float rp_t = rpClock * rpMotion;
    float rp_rl = 0.25;
    float rp_a = atan2(rp_qy, rp_qx);
    float rp_x = rp_r / rp_rl;
    float rp_out = max(rp_x - 1.0, 0.0);

    """ + GraphShaderKit.noise("rp_sn", "float3(cos(rp_a) * 1.8, sin(rp_a) * 1.8, rp_t * 0.02 + rp_seed)") + """
    float rp_helm = 0.25 + 1.1 * rp_sn * rp_sn;
    float rp_rw = sin(rp_a * 5.0 + rp_seed) * 1.5;
    float rp_ray = 0.5 + 0.5 * sin(rp_a * 23.0 + rp_rw + rp_out * 0.8);
    rp_ray = rp_ray * rp_ray;
    float rp_flow = 0.8 + 0.2 * sin(rp_out * 9.0 - rp_t * (0.8 + 4.0 * rp_mv) + rp_a * 2.0);
    float rp_inner = exp(-rp_out / (0.15 * (1.0 + 0.5 * rp_mv))) * 0.62;
    float rp_k = exp(-rp_out / (0.6 * (1.0 + 0.8 * rp_mv))) * 0.36 * rp_helm;
    float rp_far = exp(-rp_out / (1.8 * (1.0 + 1.2 * rp_mv))) * 0.2 * rp_helm * (0.65 + 0.7 * rp_ray) * rp_flow;
    float rp_cor = (rp_inner + rp_k + rp_far) * step(1.0, rp_x);
    float3 rp_hue = mix(float3(1.0, 0.86, 0.6), float3(1.0, 0.55, 0.2), clamp(rp_out * 0.8, 0.0, 1.0));
    float3 rp_col = rp_hue * rp_cor;
    float rp_ch = (rp_x - 1.004) / 0.012;
    float rp_spic = 0.7 + 0.3 * sin(rp_a * 160.0 + rp_t * 0.7);
    rp_col = rp_col + float3(1.0, 0.32, 0.2) * (exp(-rp_ch * rp_ch) * 0.9 * rp_spic);
    float3 rp_prom = float3(1.0, 0.36, 0.22);

    """ + GraphShaderKit.noise("rp_pf", "float3(rp_qx * 34.0, rp_qy * 34.0, rp_t * 0.15)") + """
    float rp_thread = 0.55 + 0.9 * rp_pf;
    float rp_cA = rp_t / 14.0 + rp_seed * 0.1;
    float rp_fA = fract(rp_cA);
    float rp_tA = fract(sin(floor(rp_cA) * 3.7 + rp_seed) * 43758.5453) * 1.4 + 0.3 + rp_seed;
    float rp_lA = rp_rl;
    float rp_xA = rp_qx * cos(rp_tA) + rp_qy * sin(rp_tA);
    float rp_yA = rp_qy * cos(rp_tA) - rp_qx * sin(rp_tA);
    float rp_hA = rp_rl * (0.005 + 0.32 * sin(3.1415927 * rp_fA));
    float rp_wA = rp_rl * (0.01 + 0.12 * sqrt(sin(3.1415927 * rp_fA)));
    float rp_sA = rp_yA / rp_wA;
    float rp_uA = (rp_xA - rp_lA) / rp_hA;
    float rp_eA = sqrt(rp_sA * rp_sA + rp_uA * rp_uA);
    float rp_bA = (rp_eA - 1.0 + (rp_pf - 0.5) * 0.35) / (0.16 + 0.08 * rp_fA);
    float rp_pA = exp(-rp_bA * rp_bA) * step(0.0, rp_xA - rp_rl * 0.995) * (0.7 + 0.5 * exp(-clamp(rp_uA, 0.0, 2.0) * 3.0));
    float rp_cB = rp_t / 19.0 + 0.41 + rp_seed * 0.1;
    float rp_fB = fract(rp_cB);
    float rp_tB = fract(sin(floor(rp_cB) * 3.7 + 11.0 + rp_seed) * 43758.5453) * 1.6 + 2.6 + rp_seed;
    float rp_lB = rp_rl;
    float rp_xB = rp_qx * cos(rp_tB) + rp_qy * sin(rp_tB);
    float rp_yB = rp_qy * cos(rp_tB) - rp_qx * sin(rp_tB);
    float rp_hB = rp_rl * (0.005 + 0.24 * sin(3.1415927 * rp_fB));
    float rp_wB = rp_rl * (0.01 + 0.09 * sqrt(sin(3.1415927 * rp_fB)));
    float rp_sB = rp_yB / rp_wB;
    float rp_uB = (rp_xB - rp_lB) / rp_hB;
    float rp_eB = sqrt(rp_sB * rp_sB + rp_uB * rp_uB);
    float rp_bB = (rp_eB - 1.0 + (rp_pf - 0.5) * 0.35) / (0.18 + 0.08 * rp_fB);
    float rp_pB = exp(-rp_bB * rp_bB) * step(0.0, rp_xB - rp_rl * 0.995) * (0.7 + 0.5 * exp(-clamp(rp_uB, 0.0, 2.0) * 3.0));
    float rp_cC = rp_t / 23.0 + 0.77 + rp_seed * 0.1;
    float rp_fC = fract(rp_cC);
    float rp_tC = fract(sin(floor(rp_cC) * 3.7 + 22.0 + rp_seed) * 43758.5453) * 1.6 + 4.6 + rp_seed;
    float rp_lC = rp_rl;
    float rp_xC = rp_qx * cos(rp_tC) + rp_qy * sin(rp_tC);
    float rp_yC = rp_qy * cos(rp_tC) - rp_qx * sin(rp_tC);
    float rp_hC = rp_rl * (0.005 + 0.19 * sin(3.1415927 * rp_fC));
    float rp_wC = rp_rl * (0.01 + 0.07 * sqrt(sin(3.1415927 * rp_fC)));
    float rp_sC = rp_yC / rp_wC;
    float rp_uC = (rp_xC - rp_lC) / rp_hC;
    float rp_eC = sqrt(rp_sC * rp_sC + rp_uC * rp_uC);
    float rp_bC = (rp_eC - 1.0 + (rp_pf - 0.5) * 0.35) / (0.2 + 0.08 * rp_fC);
    float rp_pC = exp(-rp_bC * rp_bC) * step(0.0, rp_xC - rp_rl * 0.995) * (0.7 + 0.5 * exp(-clamp(rp_uC, 0.0, 2.0) * 3.0));
    float rp_proms = (rp_pA + rp_pB + rp_pC) * rp_thread;
    rp_col = rp_col + rp_prom * (rp_proms * 1.1);
    rp_col = rp_col + float3(1.0, 0.75, 0.6) * (rp_proms * rp_proms * 0.25);

    float rp_cF = rp_t / 17.0 + rp_seed * 0.3;
    float rp_fl = fract(rp_cF);
    float rp_ft = fract(sin(floor(rp_cF) * 5.3 + rp_seed) * 43758.5453) * 6.2831853;
    float rp_xF = rp_qx * cos(rp_ft) + rp_qy * sin(rp_ft);
    float rp_yF = rp_qy * cos(rp_ft) - rp_qx * sin(rp_ft);
    float rp_sz = rp_rl * (0.03 + 0.42 * sin(3.1415927 * rp_fl));
    float rp_go = rp_rl + rp_sz * 0.45;
    float rp_dF = length(float2((rp_xF - rp_go) / (rp_sz * 0.7), rp_yF / rp_sz));
    float rp_shell = exp(-(rp_dF - 1.0) * (rp_dF - 1.0) * 30.0) * step(rp_rl, rp_r) * step(rp_go - rp_sz * 0.2, rp_xF + rp_sz * 0.7);
    float3 rp_fh = mix(float3(1.0, 0.95, 0.84), float3(1.0, 0.45, 0.12), rp_fl);
    rp_col = rp_col + rp_fh * (rp_shell * 0.45 * rpMotion * (0.6 + 0.6 * rp_pf));
    float rp_e = clamp((1.0 - rp_r) / 0.5, 0.0, 1.0);
    rp_col = rp_col * (rp_e * rp_e * (3.0 - 2.0 * rp_e));

    """ + fadedGlowEnd

    // MARK: the rocky planet

    /// The Earth, from NASA's maps (Resources/Earth; where each comes from,
    /// its credit and licence: SOURCES.md), bound by GraphEarth: Blue
    /// Marble: Next Generation's ground with The Blue Marble's clouds in its
    /// alpha (rpEarthDay, sRGB), Black Marble's city lights and the GPM
    /// land-sea mask (rpEarthAux). Equirectangular over the planet's own
    /// sphere, which GraphStyleAnimator turns (y the spin axis, north up,
    /// east to the right seen from outside), sampled with the footprint's
    /// gradients taken before the seam's wrap (so the seam meridian never
    /// drops to a blurred mip) and up to 8x anisotropy towards the limb.
    /// Shaded in linear light by its own star (the terminator faces the
    /// light, SpaceOptics.day): sunlight on the ground reddened by its path
    /// through the air (Rayleigh's optical depths), so the soft terminator
    /// burns orange; the sun's glint on open water only (GGX, Schlick's
    /// Fresnel; never on land, ice or cloud); clouds drifting slowly
    /// eastwards over the ground (one turn in the clock's period, so its
    /// wrap never jumps), lit on past the ground's terminator (they stand
    /// higher) and, at High, casting their shadows away from the sun; the
    /// air's own light (single scattering, Rayleigh's phase), blue,
    /// thickening towards the limb, where the halo's rim takes it on, and
    /// glowing into twilight past the terminator; and on the night side the
    /// city lights, warm, dimmed under cloud. The sum rolls off softly above
    /// 0.75, so no cloud or glint clips flat. Three texture reads (four with
    /// the cloud shadows).
    static let rockBody: String = """
    #pragma arguments
    float4 rpFade;
    float rpClock;
    float rpMotion;
    float rpProbe;
    float rpDetail;
    float rpFocal;
    texture2d<float> rpEarthDay;
    texture2d<float> rpEarthAux;

    """ + lightArguments + """
    #pragma body

    """ + light + sphere + detail + """
    float rp_t = rpClock * rpMotion;
    float rp_ce = max(sqrt(rp_p.x * rp_p.x + rp_p.z * rp_p.z), 0.02);
    float2 rp_uv = float2(0.5 + atan2(rp_p.x, rp_p.z) * 0.15915494, 0.5 - asin(clamp(rp_p.y, -1.0, 1.0)) * 0.31830989);
    float2 rp_gx = dfdx(rp_uv);
    float2 rp_gy = dfdy(rp_uv);
    rp_gx.x = rp_gx.x - round(rp_gx.x);
    rp_gy.x = rp_gy.x - round(rp_gy.x);
    constexpr sampler rp_smp(coord::normalized, filter::linear, mip_filter::linear, s_address::repeat, t_address::clamp_to_edge, max_anisotropy(8));
    float3 rp_alb = rpEarthDay.sample(rp_smp, rp_uv, gradient2d(rp_gx, rp_gy)).xyz;
    float4 rp_aux = rpEarthAux.sample(rp_smp, rp_uv, gradient2d(rp_gx, rp_gy));
    float2 rp_cuv = float2(rp_uv.x - rp_t / 3000.0, rp_uv.y);
    float rp_cloud = smoothstep(0.1, 0.82, rpEarthDay.sample(rp_smp, rp_cuv, gradient2d(rp_gx, rp_gy)).w);
    float rp_ndl = dot(rp_N, rp_Lv);
    float rp_day = smoothstep(-0.08, 0.22, rp_ndl);
    float rp_shade = 1.0;
    if (rp_dl > 0.0) {
    float3 rp_off = (rp_Lo - rp_p * dot(rp_Lo, rp_p)) * (0.006 / max(dot(rp_Lo, rp_p), 0.2));
    float2 rp_suv = rp_cuv + float2(dot(rp_off, float3(rp_p.z, 0.0, -rp_p.x)) / (6.2831853 * rp_ce * rp_ce), -rp_off.y / (3.1415927 * rp_ce));
    rp_shade = 1.0 - 0.55 * rp_dl * smoothstep(0.1, 0.82, rpEarthDay.sample(rp_smp, rp_suv, gradient2d(rp_gx, rp_gy)).w);
    }
    float3 rp_tau = float3(0.05, 0.12, 0.33);
    float rp_mv = 1.0 / (rp_mu + 0.035);
    float rp_ms = 1.0 / (max(rp_ndl, 0.0) + 0.035);
    float3 rp_Ts = exp(-rp_tau * (rp_ms * 0.5));
    float3 rp_Tv = exp(-rp_tau * (rp_mv * 0.5));
    float rp_sunE = rp_day * max(rp_ndl + 0.04, 0.0) * 0.96;
    float rp_lum = dot(rp_alb, float3(0.2126, 0.7152, 0.0722));
    float rp_sea = rp_aux.y * (1.0 - smoothstep(0.05, 0.2, rp_lum));
    float3 rp_H = normalize(rp_Lv + rp_V);
    float rp_nh = max(dot(rp_N, rp_H), 0.0);
    float rp_dd = rp_nh * rp_nh * (0.06 - 1.0) + 1.0;
    float rp_ggx = 0.06 / (3.1415927 * rp_dd * rp_dd);
    float rp_vh = 1.0 - max(dot(rp_V, rp_H), 0.0);
    float rp_fr = 0.02 + 0.98 * rp_vh * rp_vh * rp_vh * rp_vh * rp_vh;
    float rp_glint = 3.1415927 * rp_ggx * rp_fr * max(rp_ndl, 0.0) / (4.0 * max(max(rp_ndl, rp_mu), 0.05));
    rp_glint = rp_glint * rp_sea * (1.0 - rp_cloud) * 1.6;
    float rp_night = 1.0 - smoothstep(-0.16, 0.04, rp_ndl);
    float rp_city = rp_aux.x * rp_aux.x * rp_night * (1.0 - 0.85 * rp_cloud) * rp_lod;
    float3 rp_surf = (rp_alb * (rp_sunE * rp_shade) + float3(rp_glint)) * rp_Ts + float3(1.0, 0.62, 0.3) * (rp_city * 0.9);
    rp_surf = rp_surf * rp_Tv;
    float rp_cE = smoothstep(-0.14, 0.24, rp_ndl) * (max(rp_ndl, 0.0) * 0.85 + 0.15);
    float3 rp_cl = float3(0.82, 0.82, 0.82) * rp_cE * exp(-rp_tau * ((rp_ms + rp_mv) * 0.2));
    float rp_cosT = dot(rp_Lv, rp_V);
    float rp_msa = 1.0 / (max(rp_ndl + 0.1, 0.0) * 0.91 + 0.035);
    float3 rp_air = float3(1.0) - exp(-rp_tau * (rp_msa + rp_mv));
    rp_air = rp_air * (0.1875 * (1.0 + rp_cosT * rp_cosT) * rp_mv / (rp_msa + rp_mv) * smoothstep(-0.12, 0.08, rp_ndl));
    float3 rp_col = mix(rp_surf, rp_cl, rp_cloud) + rp_air * (1.0 - 0.55 * rp_cloud);
    rp_col = max(rp_col, float3(0.0));
    float3 rp_over = max(rp_col - float3(0.75), float3(0.0));
    rp_col = min(rp_col, float3(0.75)) + (float3(1.0) - exp(-rp_over * 4.0)) * 0.25;
    rp_col = pow(rp_col, float3(0.45454545));

    """ + fadedBodyEnd

    /// A moon: grey regolith with darker seas (a low noise) and craters -
    /// a bright ring of ejecta round a darker floor - lit by the same suns,
    /// with the hard terminator of a world without air.
    static let moonBody: String = """
    #pragma arguments
    float4 rpFade;
    float rpProbe;
    float rpDetail;
    float rpFocal;

    """ + lightArguments + """
    #pragma body

    """ + light + sphere + detail + """
    int rp_oct = rp_dl > 0.0 ? 3 : 2;

    """ + GraphShaderKit.fbm("rp_mh", "rp_p * 2.4 + float3(5.0, 3.0, 1.0)", octaves: "rp_oct", from: 2,
                             fine: "rp_dl") + """
    float rp_mare = 1.0 - smoothstep(0.4, 0.47, rp_mh);

    """ + GraphShaderKit.noise("rp_cr", "rp_p * 8.5 + float3(1.0, 2.0, 3.0)") + """
    float rp_rim = smoothstep(0.6, 0.68, rp_cr) * (1.0 - smoothstep(0.7, 0.8, rp_cr));
    float rp_pit = smoothstep(0.74, 0.88, rp_cr);
    float rp_alb = 0.56 - 0.2 * rp_mare + 0.14 * rp_rim - 0.1 * rp_pit + 0.1 * (rp_mh - 0.5);
    float rp_ndl = dot(rp_N, rp_Lv);
    float rp_k = 1.15 * smoothstep(-0.03, 0.14, rp_ndl) * pow(max(rp_ndl, 0.02), 0.85);
    float3 rp_col = float3(0.93, 0.9, 0.86) * (rp_alb * (0.012 + rp_k));

    """ + fadedBodyEnd

    /// The thin air round a planet (and, tinted by rpTintA, a gas giant's
    /// glow), on the lifted billboard: brightest on the sun's side, and a
    /// whole glowing ring when the sun is behind it; warmer where the
    /// terminator meets the limb (light through more air at sunset).
    /// rpThin weighs the thin bright line on the limb: a planet's, not a
    /// gas giant's (an oblate limb would leave a gap under a round line).
    static let halo: String = """
    #pragma arguments
    float4 rpFade;
    float rpProbe;
    float rpThin;
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
    float3 rp_col = rpTintA * ((rp_thin * 0.5 * rpThin + rp_soft * 0.35) * rp_lit);
    float rp_edge = exp(-rp_dir * rp_dir * 8.0) * (1.0 - rp_back);
    rp_col = rp_col * mix(float3(1.0, 1.0, 1.0), float3(1.35, 0.75, 0.55), rp_edge * 0.6);
    rp_col = rp_col * clamp((1.0 - rp_r) / 0.2, 0.0, 1.0);

    """ + fadedGlowEnd

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

    /// A gas giant, after Jupiter and Saturn: alternating pale zones and
    /// darker belts of uneven width, each band's jet running its own way at
    /// its own speed (so the bands shear past each other), their edges
    /// churned into eddies by turbulence stretched along the latitudes,
    /// fine streaks inside each band; a string of small white ovals in the
    /// north; a great storm drifting with its band, its clouds spiralling
    /// round its eye inside a pale collar, the bands bowing round it;
    /// mottled paler poles; lit towards the nearest sun with a gas giant's
    /// soft limb darkening. With a ring (`rpRinged`): the ring's shadow on
    /// the clouds (SpaceOptics.ringShadowRadius), and the ring's near arc
    /// dimming the clouds behind it (the same density, along the line to
    /// the eye), so it crosses the disc as a real ring does. Dragged (its z
    /// scale) the jets quicken and the churn smears out along the bands. y
    /// is its spin axis; the ring lies in y = 0. Palette per folder:
    /// rpTintA cream, B tan, C rust, D the poles.
    static let gasBody: String = """
    #pragma arguments
    float4 rpFade;
    float rpClock;
    float rpMotion;
    float rpProbe;
    float rpDetail;
    float rpFocal;
    float rpRinged;
    float3 rpTintA;
    float3 rpTintB;
    float3 rpTintC;
    float3 rpTintD;

    """ + lightArguments + """
    #pragma body

    """ + light + sphere + sphereMotion + detail + """
    float rp_t = rpClock * rpMotion;
    float rp_lat = rp_p.y;
    float rp_lon = atan2(rp_p.z, rp_p.x);
    float rp_cl = sqrt(max(1.0 - rp_lat * rp_lat, 0.0));
    float rp_so = rp_lon + rp_t * 0.02 - 3.9;
    rp_so = rp_so - 6.2831853 * floor(rp_so / 6.2831853 + 0.5);
    float rp_stx = rp_so * rp_cl / 0.27;
    float rp_sty = (rp_lat - 0.3) / 0.1;
    float rp_s2 = rp_stx * rp_stx + rp_sty * rp_sty;
    float rp_sr = sqrt(rp_s2);
    float rp_bq0 = rp_lat * 6.5 + 0.13 * sin(rp_lat * 9.0);
    rp_bq0 = rp_bq0 + 0.35 * exp(-rp_s2 * 0.3) * rp_sty / (1.0 + abs(rp_sty));
    float rp_bi = floor(rp_bq0 + 0.5);
    float rp_way = 1.0 - 2.0 * (rp_bi - 2.0 * floor(rp_bi * 0.5));
    float rp_om = (0.04 + 0.12 * fract(sin(rp_bi * 3.7) * 43758.5453)) * rp_way * (1.0 + 0.8 * rp_m);
    float rp_lb = rp_lon + rp_t * rp_om;
    float rp_R = 1.6 * (1.0 - 0.6 * rp_m);
    float3 rp_ring3 = float3(cos(rp_lb) * rp_R, rp_lat * 9.0, sin(rp_lb) * rp_R);
    int rp_oct = rp_dl > 0.0 ? 5 : 3;

    """ + GraphShaderKit.fbm("rp_tb", "rp_ring3 + float3(0.0, 0.0, rp_t * 0.01)", octaves: "rp_oct", from: 3,
                             fine: "rp_dl")
        + GraphShaderKit.noise("rp_ed", "float3(rp_ring3.x * 4.0, rp_lat * 34.0, rp_ring3.z * 4.0)") + """
    float rp_bq = rp_bq0 + (rp_tb - 0.5) * 0.6 + (rp_ed - 0.5) * 0.2 * (1.0 - 0.6 * rp_m);
    float rp_bj = floor(rp_bq);
    float rp_bf = rp_bq - rp_bj;
    float rp_par = rp_bj - 2.0 * floor(rp_bj * 0.5);
    float rp_h1 = fract(sin(rp_bj * 12.9898) * 43758.5453);
    float rp_h2 = fract(sin((rp_bj + 1.0) * 12.9898) * 43758.5453);
    float rp_t1 = mix(0.74 + 0.24 * rp_h1, 0.14 + 0.3 * rp_h1, rp_par);
    float rp_t2 = mix(0.74 + 0.24 * rp_h2, 0.14 + 0.3 * rp_h2, 1.0 - rp_par);
    float rp_tone = mix(rp_t1, rp_t2, smoothstep(0.72, 1.0, rp_bf));

    """ + GraphShaderKit.noise("rp_zs", "float3(rp_ring3.x * 2.2, rp_bq * 16.0, rp_ring3.z * 2.2)") + """
    rp_tone = rp_tone + (rp_zs - 0.5) * 0.24 + rp_m * 0.07 * sin(rp_bq * 70.0);
    float3 rp_cloud = mix(rpTintC * (0.8 + 0.3 * rp_h1), rpTintB, smoothstep(0.1, 0.5, rp_tone));
    rp_cloud = mix(rp_cloud, rpTintA, smoothstep(0.5, 0.88, rp_tone));
    float rp_oq = rp_lb * 1.9098593 + 0.3;
    float rp_ox = (fract(rp_oq) - 0.5) / 0.16;
    float rp_oy = (rp_lat - 0.56 + 0.02 * (rp_tb - 0.5)) / 0.032;
    float rp_ov = exp(-rp_ox * rp_ox - rp_oy * rp_oy) * step(0.45, fract(sin(floor(rp_oq) * 7.31) * 43758.5453));
    rp_cloud = mix(rp_cloud, float3(0.97, 0.95, 0.9), rp_ov * 0.85);
    float rp_pole = smoothstep(0.6, 0.97, abs(rp_lat) + 0.06 * (rp_tb - 0.5));
    rp_cloud = mix(rp_cloud, mix(rp_cloud, rpTintD, 0.6) * (0.8 + 0.4 * rp_tb), rp_pole);
    float rp_sa = atan2(rp_sty, rp_stx) + 2.6 * exp(-rp_sr * 1.2) - rp_t * 0.35;

    """ + GraphShaderKit.noise("rp_sn", "float3(cos(rp_sa) * 2.2, sin(rp_sa) * 2.2, rp_sr * 2.5)") + """
    float rp_sw = rp_sr * (1.0 + 0.16 * (rp_sn - 0.5));
    float rp_storm = 1.0 - smoothstep(0.82, 1.08, rp_sw);
    float3 rp_red = mix(float3(0.66, 0.27, 0.15), float3(0.86, 0.5, 0.34), rp_sn);
    rp_red = rp_red * (0.85 + 0.25 * smoothstep(0.0, 0.7, rp_sr));
    float rp_cd = (rp_sw - 1.2) / 0.16;
    float rp_collar = exp(-rp_cd * rp_cd);
    rp_cloud = mix(rp_cloud, rp_red, rp_storm * 0.92);
    rp_cloud = mix(rp_cloud, float3(0.95, 0.9, 0.82), rp_collar * 0.45);
    float rp_ly = abs(rp_Lo.y) < 0.001 ? 0.001 : rp_Lo.y;
    float rp_tt = -rp_lat / rp_ly;
    float rp_hx = rp_p.x + rp_Lo.x * rp_tt;
    float rp_hz = rp_p.z + rp_Lo.z * rp_tt;
    float rp_rho = sqrt(rp_hx * rp_hx + rp_hz * rp_hz);
    """ + ringDensity("rp") + """
    float rp_shade = 1.0 - 0.6 * rp_den * step(0.0, rp_tt) * rpRinged * rp_lod;
    float3 rp_Vo = float3(dot(rp_v0, rp_V), dot(rp_v1, rp_V), dot(rp_v2, rp_V));
    float rp_vy = abs(rp_Vo.y) < 0.001 ? 0.001 : rp_Vo.y;
    float rp_tv = -rp_lat / rp_vy;
    float rp_vx = rp_p.x + rp_Vo.x * rp_tv;
    float rp_vz = rp_p.z + rp_Vo.z * rp_tv;
    float rq_rho = sqrt(rp_vx * rp_vx + rp_vz * rp_vz);
    """ + ringDensity("rq") + """
    float rp_veil = 1.0 - 0.8 * rq_den * step(0.0, rp_tv) * rpRinged;
    float rp_ndl = dot(rp_N, rp_Lv);
    float rp_day = smoothstep(-0.1, 0.3, rp_ndl) * pow(max(rp_ndl, 0.04), 0.6);
    float rp_k = (0.015 + 1.1 * rp_day * rp_shade) * (0.6 + 0.4 * pow(max(rp_mu, 0.001), 0.45));
    float3 rp_col = rp_cloud * rp_k;
    float rp_lm = 1.0 - rp_mu;
    float rp_fr = rp_lm * rp_lm * rp_lm;
    rp_col = rp_col + float3(0.9, 0.78, 0.55) * (rp_fr * 0.18 * smoothstep(-0.3, 0.5, rp_ndl));
    rp_col = rp_col * rp_veil;

    """ + fadedBodyEnd

    /// A gas giant's ring, in the disk's plane (its half side 2.4 planet
    /// radii): the faint grey C ring, the bright cream B ring, the dark
    /// Cassini division, the greyer A ring with its thin Encke gap; ringlets
    /// at two scales across all of it (the finest only when the ring is big
    /// enough on screen to show them without shimmering). Lit on the face
    /// the sun shines on, dim on the other unless the sun is behind it
    /// (dusty rings glow forward); the planet's shadow across it on the far
    /// side from the sun (SpaceOptics.planetShadowsRing). The planet dims
    /// what the ring hides of it (gasBody), so here the ring only adds its
    /// own light. Its z scale carries the planet's motion: it shimmers
    /// brighter. Which face the eye sees, and how far it is, come from the
    /// ring's centre in view space, never `_surface.view` or
    /// `_surface.position`: on a constant-lit plane those are not filled
    /// in on the device, so the face test flickered in blocks and the ring
    /// drew as its dim back face, crushed to nothing (found by drawing its
    /// terms as colours in a preview).
    static let gasRing: String = """
    #pragma arguments
    float4 rpFade;
    float rpProbe;

    """ + lightArguments + """
    #pragma body

    """ + plane + planeCode + light + """
    float rp_px = rp_qx * 2.4;
    float rp_py = rp_qy * 2.4;
    float rp_rho = sqrt(rp_px * rp_px + rp_py * rp_py);
    """ + ringDensity("rp") + """
    float3 rp_cv = scn_node.modelViewTransform[3].xyz;
    float rp_depth = max(length(rp_cv), 0.001);
    float3 rp_eye = -rp_cv / rp_depth;
    float rp_near = smoothstep(150.0, 600.0, 2600.0 * rp_zx / 4.8 / rp_depth);
    float rp_q1 = rp_rho * 46.0;
    float rp_i1 = floor(rp_q1);
    float rp_f1 = fract(rp_q1);
    rp_f1 = rp_f1 * rp_f1 * (3.0 - 2.0 * rp_f1);
    float rp_mid = mix(fract(sin(rp_i1 * 12.9898) * 43758.5453), fract(sin((rp_i1 + 1.0) * 12.9898) * 43758.5453), rp_f1);
    float rp_q2 = rp_rho * 240.0;
    float rp_i2 = floor(rp_q2);
    float rp_f2 = fract(rp_q2);
    rp_f2 = rp_f2 * rp_f2 * (3.0 - 2.0 * rp_f2);
    float rp_fine = mix(fract(sin(rp_i2 * 7.137) * 43758.5453), fract(sin((rp_i2 + 1.0) * 7.137) * 43758.5453), rp_f2);
    float rp_band = (0.72 + 0.4 * rp_mid) * (1.0 + (rp_fine - 0.5) * 0.36 * rp_near);
    float rp_ek = (rp_rho - 2.14) / 0.008;
    float rp_encke = 1.0 - 0.8 * exp(-rp_ek * rp_ek);
    float rp_d = rp_den * rp_band * rp_encke;
    float3 rp_hue = mix(float3(0.46, 0.41, 0.36), float3(0.96, 0.87, 0.7), smoothstep(1.44, 1.6, rp_rho));
    rp_hue = mix(rp_hue, float3(0.8, 0.76, 0.69), smoothstep(1.98, 2.06, rp_rho));
    float3 rp_Vo = float3(dot(rp_v0, rp_eye), dot(rp_v1, rp_eye), dot(rp_v2, rp_eye));
    float rp_face = rp_Lo.z * rp_Vo.z >= 0.0 ? 1.0 : 0.0;
    float rp_lit = (0.3 + 0.7 * abs(rp_Lo.z)) * mix(0.3, 1.0, rp_face);
    float rp_fw = pow(max(-dot(rp_Lo, rp_Vo), 0.0), 6.0) * (1.0 - rp_face) * rp_d * (1.0 - min(rp_d, 1.0)) * 1.6;
    float rp_al = rp_px * rp_Lo.x + rp_py * rp_Lo.y;
    float rp_perp = rp_rho * rp_rho - rp_al * rp_al;
    float rp_sh = (1.0 - step(0.0, rp_al)) * (1.0 - smoothstep(0.85, 1.05, rp_perp));
    float rp_k = rp_d * rp_lit * (1.0 - 0.9 * rp_sh);
    rp_k = rp_k * (0.85 + 0.3 * rp_m);
    float3 rp_col = rp_hue * (rp_k * 0.95) + float3(1.0, 0.95, 0.85) * (rp_fw * (1.0 - rp_sh));

    """ + fadedGlowEnd

    // MARK: the pulsar

    /// The pulsar's tiny core: white-blue, brighter at the edge, flaring
    /// a little as a beam sweeps by (two beats a turn) - never to white,
    /// so its edge holds against the glare.
    static let pulsarCore: String = """
    #pragma arguments
    float4 rpFade;
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
    float rp_k = 0.72 + 0.2 * (1.0 - rp_mu) + 0.1 * rp_b;
    float3 rp_col = float3(0.82, 0.9, 1.0) * rp_k;

    """ + fadedBodyEnd

    /// The glow round the core and its wind nebula, after the Crab's: a
    /// small, tight blue-white glare beating gently with the beams, never
    /// near the core's own brightness even at a beat's peak, so the core's
    /// edge holds in every frame (the nebula, not the glare, carries the
    /// look); in the equator, a
    /// thin bright inner ring and the broader torus outside it, both broken
    /// into wisps that drift slowly outwards, the side coming towards the
    /// eye brighter; two jets along the spin axis; and round it all a
    /// synchrotron haze, blue, threaded with warm filaments. The nebula is
    /// the pulsar's own: GraphStyleAnimator turns the plane so +y runs
    /// along the spin axis as seen (SpaceOptics.nebula), and its z scale
    /// carries how edge-on the axis is (|z| - 2: 0 the axis at the eye, 1
    /// across the sky). So the rings are circles flattening into ellipses
    /// as the axis turns across the sky, and the jets shorten as it turns
    /// towards the eye.
    static let pulsarGlow: String = """
    #pragma arguments
    float4 rpFade;
    float rpClock;
    float rpMotion;
    float rpProbe;

    #pragma body

    """ + plane + """
    float rp_k = clamp(length(scn_node.modelTransform[2].xyz) - 2.0, 0.0, 1.0);
    float rp_t = rpClock * rpMotion;
    float rp_rl = 0.12;
    float rp_b = 0.5 + 0.5 * cos(rp_t * 1.3333333 * 6.2831853);
    rp_b = rp_b * rp_b;
    rp_b = rp_b * rp_b;
    rp_b = rp_b * rp_b;
    float rp_x = max(rp_r / rp_rl - 1.0, 0.0);
    float rp_h = 1.0 / (1.0 + rp_x * rp_x * 40.0) + 0.025 / (1.0 + rp_x * 1.5);
    rp_h = rp_h * (0.6 + 0.4 * rp_b) * step(rp_rl * 0.95, rp_r);
    float3 rp_col = float3(0.68, 0.8, 1.0) * (rp_h * 0.42);
    float rp_ratio = sqrt(max(1.0 - rp_k * rp_k, 0.0));
    float rp_B = max(rp_ratio, 0.08);
    float rp_ex = rp_qx;
    float rp_ey = rp_qy / rp_B;
    float rp_er = sqrt(rp_ex * rp_ex + rp_ey * rp_ey) + 0.00001;
    float rp_ang = atan2(rp_ey, rp_ex);

    """ + GraphShaderKit.noise("rp_wn", "float3(cos(rp_ang) * 3.0, sin(rp_ang) * 3.0, rp_er * 7.0 - rp_t * 0.15)") + """
    float rp_near = 1.0 + 0.45 * rp_k * (-rp_ey / rp_er);
    float rp_d1 = (rp_er - 0.21) / 0.022;
    float rp_d2 = (rp_er - 0.4) / 0.085;
    float rp_ring = exp(-rp_d1 * rp_d1) * (0.4 + 0.9 * rp_wn) * 0.8;
    float rp_torus = exp(-rp_d2 * rp_d2) * (0.3 + 0.9 * rp_wn) * 0.6;
    float rp_ay = abs(rp_qy);
    float rp_jet = exp(-rp_qx * rp_qx / (0.0012 + 0.008 * rp_ay)) * smoothstep(0.08, 0.2, rp_ay);
    rp_jet = rp_jet * exp(-rp_ay / (0.1 + 0.45 * rp_k)) * (0.6 + 0.4 * rp_wn) * 0.7;
    float rp_ne = length(float2(rp_qx / 0.72, rp_qy / 0.6));

    """ + GraphShaderKit.noise("rp_fm", "float3(rp_qx * 2.4 + 3.0, rp_qy * 2.4, rp_t * 0.01)")
        + GraphShaderKit.noise("rp_fa", "float3(rp_qx * 5.0 + rp_fm * 1.5, rp_qy * 5.0 - rp_fm * 1.2, 2.0 + rp_t * 0.012)")
        + GraphShaderKit.noise("rp_fb", "float3(rp_qx * 13.0, rp_qy * 13.0, 5.0)") + """
    float rp_ra = 1.0 - abs(rp_fa * 2.0 - 1.0);
    float rp_rb = 1.0 - abs(rp_fb * 2.0 - 1.0);
    float rp_fil = pow(rp_ra, 5.0) * (0.6 + 0.6 * rp_rb);
    float rp_env = exp(-rp_ne * rp_ne * 2.2) * (0.5 + 0.9 * rp_fm);
    float3 rp_syn = mix(float3(0.32, 0.42, 1.0), float3(0.55, 0.75, 1.0), rp_fm) * (rp_env * 0.46);
    float3 rp_warm = float3(1.0, 0.5, 0.32) * (rp_fil * rp_env * 0.4);
    float3 rp_wind = float3(0.62, 0.78, 1.0) * ((rp_ring + rp_torus) * rp_near + rp_jet);
    rp_col = rp_col + (rp_wind + rp_syn + rp_warm) * (0.92 + 0.12 * rp_b);
    rp_col = rp_col * clamp((1.0 - rp_r) / 0.3, 0.0, 1.0);

    """ + fadedGlowEnd

    /// Both beams in one long plane along the magnetic axis (turned each
    /// frame by GraphStyleAnimator to face the eye): narrow cones widening
    /// outwards with a bright spine, plasma streaming out along them in
    /// fine striations, blue-white at the core and violet at the edges,
    /// brightest and widest as the beam sweeps towards the eye (its z
    /// scale), but no more than 1.6 times, and starting at the core's limb,
    /// never across it; and the more it faces the eye, the dimmer its root
    /// (seen end on, the whole beam's light piles on the core), so a beam
    /// facing the eye never blanks the core. Nor is any of it drawn over the
    /// core's disc as seen (its radius a sixth of the plane's width: the
    /// core is 0.3 of the note's radius, the plane 1.8), clearing over a
    /// third of a radius past the limb: a beam pointing nearly at the eye
    /// cannot whiten the core, whose edge holds in every frame.
    static let pulsarBeam: String = """
    #pragma arguments
    float4 rpFade;
    float rpClock;
    float rpMotion;
    float rpProbe;

    #pragma body

    """ + plane + planeCode + """
    float rp_t = rpClock * rpMotion;
    float rp_face = rp_m;
    float rp_ay = abs(rp_qy);
    float rp_wd = 0.1 + 0.34 * rp_ay * (1.0 + 0.5 * rp_face);
    float rp_ac = rp_qx / rp_wd;
    float rp_prof = exp(-rp_ac * rp_ac * 2.5);
    float rp_spine = exp(-rp_ac * rp_ac * 28.0);
    float rp_fade = smoothstep(0.05, 0.14, rp_ay) * pow(max(1.0 - rp_ay, 0.0), 1.6);

    """ + GraphShaderKit.noise("rp_st", "float3(rp_ac * 2.5, rp_ay * 16.0 - rp_t * 7.0, step(0.0, rp_qy) * 7.0)") + """
    float rp_flow = 0.65 + 0.6 * rp_st;
    float rp_f2 = rp_face * rp_face;
    float rp_k = (rp_prof * 0.85 + rp_spine * 0.9) * rp_fade * rp_flow * (0.6 + 1.0 * rp_f2 * rp_f2);
    rp_k = rp_k * (1.0 - 0.8 * rp_f2 * exp(-rp_ay / 0.25));
    float3 rp_cc = scn_node.modelViewTransform[3].xyz;
    float3 rp_ray = normalize(_surface.position);
    float rp_off = length(rp_cc - rp_ray * dot(rp_ray, rp_cc)) * 6.0 / length(scn_node.modelViewTransform[0].xyz);
    rp_k = rp_k * smoothstep(1.0, 1.35, rp_off);
    float3 rp_hue = mix(float3(0.9, 0.95, 1.0), float3(0.52, 0.45, 1.0), clamp(abs(rp_ac) * 0.7, 0.0, 1.0));
    float3 rp_col = rp_hue * rp_k;

    """ + fadedGlowEnd

    // MARK: the comet

    /// The nucleus: three fifths of the head (GraphStyleKit), dark and
    /// lumpy - its shading broken up by two noises, as an irregular body's
    /// would be - its sunward side lit. The coma's glow (cometComa) is
    /// added over it, so it sits inside a bright head.
    static let cometNucleus: String = """
    #pragma arguments
    float4 rpFade;
    float rpProbe;

    """ + lightArguments + """
    #pragma body

    """ + light + sphere + GraphShaderKit.noise("rp_nn", "rp_p * 2.6 + float3(2.0, 7.0, 1.0)")
        + GraphShaderKit.noise("rp_nf", "rp_p * 7.0") + """
    float rp_ndl = dot(rp_N, rp_Lv) + (rp_nn - 0.5) * 0.7 + (rp_nf - 0.5) * 0.3;
    float rp_k = 0.02 + 0.55 * smoothstep(-0.1, 0.5, rp_ndl);
    float3 rp_col = float3(0.56, 0.54, 0.5) * (rp_k * (0.7 + 0.4 * rp_nf));

    """ + fadedBodyEnd

    /// The coma, round the head: thin over the nucleus itself, so the small
    /// dark body shows through, brightest in a white ring just off it,
    /// falling off as gas does (about one over the distance) through pale
    /// yellow into a wide green glow, mottled, squashed on the sunward side
    /// and drawn out away from it, with jets - narrow, gently curving,
    /// mostly sunward - turning slowly as the nucleus spins. Measured in body radii from the head (the limb
    /// sits at 0.1875 of the plane's half side).
    static let cometComa: String = """
    #pragma arguments
    float4 rpFade;
    float rpClock;
    float rpMotion;
    float rpProbe;

    """ + lightArguments + """
    #pragma body

    """ + plane + light + """
    float rp_t = rpClock * rpMotion;
    float rp_lx = dot(rp_Lv, rp_v0);
    float rp_ly = dot(rp_Lv, rp_v1);
    float rp_cx = rp_qx / 0.1875;
    float rp_cy = rp_qy / 0.1875;
    float rp_cr = sqrt(rp_cx * rp_cx + rp_cy * rp_cy) + 0.0001;
    float rp_lp = sqrt(rp_lx * rp_lx + rp_ly * rp_ly) + 0.0001;
    float rp_ca = (rp_cx * rp_lx + rp_cy * rp_ly) / (rp_cr * rp_lp);
    float rp_sw = rp_ca * min(rp_lp * 1.5, 1.0);
    float rp_re = rp_cr * (1.0 + 0.5 * max(rp_sw, 0.0)) * (1.0 + 0.3 * min(rp_sw, 0.0));
    float rp_ang = atan2(rp_cy, rp_cx);

    """ + GraphShaderKit.noise("rp_cn", "float3(cos(rp_ang) * 2.5, sin(rp_ang) * 2.5, rp_cr * 1.2 - rp_t * 0.08)") + """
    float rp_g = 0.5 / (rp_re + 0.22) * exp(-rp_re * 0.24) * (0.8 + 0.4 * rp_cn);
    float rp_cd = (rp_re - 0.85) / 0.3;
    float rp_core = exp(-rp_cd * rp_cd) * 0.45;
    float rp_clear = 0.2 + 0.8 * smoothstep(0.5, 1.05, rp_cr);
    float rp_spin = rp_ang + rp_cr * 0.18 - rp_t * 0.25;
    float rp_j1 = pow(0.5 + 0.5 * cos(rp_spin * 3.0 + 0.6), 6.0);
    float rp_j2 = pow(0.5 + 0.5 * cos(rp_spin * 5.0 + 2.1), 9.0) * 0.6;
    float rp_fan = (rp_j1 + rp_j2) * smoothstep(-0.3, 0.6, rp_sw) * smoothstep(0.5, 0.95, rp_cr);
    rp_fan = rp_fan * exp(-rp_cr * 0.5) * (0.7 + 0.6 * rp_cn) * 0.32;
    float3 rp_hue = mix(float3(1.0, 0.99, 0.95), float3(0.98, 0.94, 0.78), smoothstep(0.2, 1.0, rp_cr));
    rp_hue = mix(rp_hue, float3(0.36, 1.0, 0.66), smoothstep(0.7, 2.6, rp_cr));
    float rp_edge = clamp((1.0 - rp_r) / 0.3, 0.0, 1.0);
    float3 rp_col = (rp_hue * (rp_g * rp_clear + rp_core) + float3(1.0, 0.97, 0.9) * rp_fan) * rp_edge;

    """ + fadedGlowEnd

    /// The ion tail, in a plane from the head (bottom) to the tip (top),
    /// turned by GraphStyleAnimator to point straight away from the light
    /// (SpaceOptics.cometTails): narrow, blue, in streamers that kink and
    /// carry knots out along it. Its z scale carries how fast the comet is
    /// moving: brighter (and the animator makes it longer).
    static let cometTail: String = """
    #pragma arguments
    float4 rpFade;
    float rpClock;
    float rpMotion;
    float rpProbe;

    #pragma body

    """ + plane + planeCode + """
    float rp_t = rpClock * rpMotion;
    float rp_ty = rp_qy * 0.5 + 0.5;
    float rp_tx = rp_qx;
    float rp_wi = 0.035 + 0.12 * rp_ty;

    """ + GraphShaderKit.noise("rp_in", "float3(rp_tx * 9.0, rp_ty * 5.0 - rp_t * 0.9, 0.0)") + """
    float rp_kink = (rp_in - 0.5) * 0.12 * rp_ty;
    float rp_ix = (rp_tx - rp_kink) / rp_wi;
    float rp_str = 0.55 + 0.45 * sin(rp_tx * 60.0 / (0.4 + rp_ty) + rp_in * 4.0);
    float rp_ion = exp(-rp_ix * rp_ix) * pow(max(1.0 - rp_ty, 0.0), 1.1) * rp_str;

    """ + GraphShaderKit.noise("rp_kn", "float3(rp_ty * 7.0 - rp_t * 1.6, 3.0, 1.0)") + """
    rp_ion = rp_ion * (0.7 + 0.6 * smoothstep(0.55, 0.85, rp_kn));
    float rp_head = exp(-rp_ty * 10.0) * exp(-rp_tx * rp_tx * 40.0);
    float3 rp_col = float3(0.42, 0.64, 1.0) * (rp_ion * 1.35) + float3(0.8, 0.92, 1.0) * (rp_head * 0.5);
    rp_col = rp_col * (0.8 + 0.6 * rp_m);

    """ + fadedGlowEnd

    /// The dust tail, in its own plane from the head (bottom) to the tip
    /// (top), turned by GraphStyleAnimator to lie between the light's away
    /// direction and where the comet has been, its +x towards the side it
    /// lags (SpaceOptics.cometTails): broad, pale gold, curving towards +x
    /// as it goes, with fine streaks fanning from the head and crossed by
    /// curved striae (bands of dust released together, each its own
    /// strength, bowing as the tail curves, drifting slowly out). Its z scale
    /// carries how fast the comet is moving: brighter, and shedding puffs
    /// of dust that stream away down the tail.
    static let cometDust: String = """
    #pragma arguments
    float4 rpFade;
    float rpClock;
    float rpMotion;
    float rpProbe;

    #pragma body

    """ + plane + planeCode + """
    float rp_t = rpClock * rpMotion;
    float rp_ty = rp_qy * 0.5 + 0.5;
    float rp_tx = rp_qx;
    float rp_xc = 0.38 * rp_ty * rp_ty;
    float rp_wd = 0.06 + 0.42 * rp_ty;
    float rp_dx = (rp_tx - rp_xc) / rp_wd;
    float rp_fan = exp(-rp_dx * rp_dx) * pow(max(1.0 - rp_ty, 0.0), 1.6);
    float rp_sa = atan2(rp_tx - rp_xc * 0.5, rp_ty + 0.05);
    float rp_striae = 0.72 + 0.28 * sin(rp_sa * 34.0 + rp_t * 0.2);
    float rp_bq = rp_dx * 0.35 + rp_ty * 7.0 - rp_ty * rp_ty * 3.0 - rp_t * 0.05;
    float rp_bi = floor(rp_bq);
    float rp_bf = fract(rp_bq) - 0.5;
    float rp_bh = fract(sin(rp_bi * 7.31 + 1.7) * 43758.5453);
    float rp_band = exp(-rp_bf * rp_bf * 18.0) * (0.3 + 0.7 * rp_bh);
    rp_striae = rp_striae * (0.6 + 1.0 * rp_band * smoothstep(0.08, 0.3, rp_ty));
    float rp_head = exp(-rp_ty * 7.0) * exp(-rp_tx * rp_tx * 25.0);
    float3 rp_col = float3(1.0, 0.92, 0.74) * (rp_fan * 1.05 * rp_striae);
    rp_col = rp_col + float3(1.0, 0.97, 0.88) * (rp_head * 0.45);
    float rp_pq = rp_ty * 9.0 - rp_t * 2.2;
    float rp_pf = fract(rp_pq) - 0.5;
    float rp_ph = fract(sin(floor(rp_pq) * 5.17) * 43758.5453);
    float rp_pd = (rp_tx - rp_xc - (rp_ph - 0.5) * rp_wd * 1.2) / (0.03 + 0.05 * rp_ty);
    float rp_puff = exp(-rp_pf * rp_pf * 60.0 - rp_pd * rp_pd) * step(0.4, rp_ph) * rp_m;
    rp_col = rp_col + float3(1.0, 0.93, 0.78) * (rp_puff * 0.5 * (1.0 - rp_ty));
    rp_col = rp_col * (0.8 + 0.5 * rp_m);

    """ + fadedGlowEnd

    // MARK: selection and folders

    /// The chosen note's orbit: a thin gold ring round it with a spark
    /// running along it, trailing light.
    static let orbit: String = """
    #pragma arguments
    float4 rpFade;
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

    """ + fadedGlowEnd

    /// A folder's gravity well, on a billboard round its notes: faint
    /// rings crowding towards the middle, as a funnel does seen from above,
    /// drifting slowly inwards, tinted by the folder (rpTintA).
    static let well: String = """
    #pragma arguments
    float4 rpFade;
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

    """ + fadedGlowEnd
}
