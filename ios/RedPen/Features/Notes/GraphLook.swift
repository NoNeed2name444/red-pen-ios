import SceneKit
import UIKit
import Metal
import simd

// The look of the space: every note a small black hole - a black sphere, a
// thin photon ring hugging its rim and a tilted, streaky accretion disk - and
// every link a plasma stream with an electric aura, on a deep blue starfield.
//
// Everything here is made once. Textures are generated in code the first
// time they are asked for and shared by every scene after that; materials
// are made once per folder, never per note or per frame. The motion itself
// lives in GraphSim (on SceneKit's render loop) and in the shader modifiers
// below.

// MARK: - proportions

/// Sizes of the pieces of one black hole, as multiples of its sphere's
/// radius. The textures are drawn to match these.
nonisolated enum GraphShape {
    /// The side of the photon ring's square, billboarded plane.
    static let ringPlane: Float = 4.2
    /// Where the thin photon ring peaks, as a fraction of that plane's half
    /// side: 1.04 radii out, just clear of the silhouette.
    static let ringPeak: Float = 0.495
    /// How far towards the camera the ring's plane sits: more than one radius,
    /// so it is always in front of its own sphere.
    static let ringLift: Float = 1.08
    /// The accretion disk's outer radius.
    static let diskRadius: Float = 2.5
    /// Where the disk's inner edge sits, as a fraction of its outer radius.
    static let diskInner: Float = 0.43
    /// Half the width of a link's ribbon, in the space's units.
    static let linkHalfWidth: Float = 0.18
    /// Links start this many radii out from a note's centre: under its
    /// ring's lensed arc, so the ring reads in front of the line, which
    /// fades in from there (see GraphShaders.link).
    static let linkTrim: Float = 1.35
    /// The shader clock wraps round at this many seconds (50 minutes). The
    /// ring's motions, the links' pulses and surges and the crackle's
    /// rhythm turn a whole number of times in it, so their wrap never shows;
    /// the rest (noise drift, filaments, helix, flicker) shift once, a small
    /// jump in already-irregular motion, every 50 minutes. At this size a 32-bit float still holds it to well under
    /// a millisecond.
    static let clockPeriod: Double = 3000
}

// MARK: - shader modifiers

/// The shader modifiers, as SceneKit (Metal) surface modifiers.
///
/// All three write the final colour into `_surface.diffuse`; with the
/// constant lighting model that is what reaches the screen, added to what is
/// behind by the material's additive blend. Each ends by adding `rpProbe`,
/// which is 0 in the app and 1 only in GraphShaderProbe's test render - so a
/// modifier that fails to compile (which SceneKit reports only in the log)
/// is caught, and the plain baked textures are used instead.
///
/// Time comes from `rpClock`, which GraphSim sets once a frame, wrapped at
/// GraphShape.clockPeriod. `scn_frame.time` is not used: it counts from the
/// device's boot, and after a few days of uptime a 32-bit float no longer
/// holds it finely enough for smooth motion at 120 frames a second.
nonisolated enum GraphShaders {
    /// The photon ring: a slow brightness pulse and a hot spot orbiting the
    /// rim. The phase comes from where the ring is, so no two notes shimmer
    /// in step though they share one material.
    static let ring: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpProbe;

    #pragma body
    float2 rp_q = _surface.diffuseTexcoord - float2(0.5, 0.5);
    float rp_r = length(rp_q) * 2.0;
    float rp_a = atan2(-rp_q.y, rp_q.x);
    float3 rp_pos = scn_node.modelTransform[3].xyz;
    float rp_seed = dot(rp_pos, float3(1.7, 2.3, 3.1));
    float rp_t = rpClock * rpMotion;
    float rp_c = max(cos(rp_a - rp_t * 0.6283185 - rp_seed), 0.0);
    float rp_c2 = rp_c * rp_c;
    float rp_c4 = rp_c2 * rp_c2;
    float rp_spot = rp_c4 * rp_c4;
    float rp_b = (rp_r - 0.495) / 0.035;
    float rp_band = exp(-rp_b * rp_b);
    float rp_wave = sin(rp_t * 1.2566371 + rp_seed * 2.0);
    float rp_pulse = 1.0 + 0.14 * rpMotion * rp_wave;
    float rp_heat = rp_spot * rp_band * 0.9 * rpMotion;
    float3 rp_col = _surface.diffuse.rgb * rp_pulse;
    rp_col = rp_col + float3(1.0, 0.9, 0.7) * rp_heat;
    _surface.diffuse = float4(rp_col + float3(rpProbe), 1.0);
    """

    /// The accretion disk: brighter on the right of the screen and dimmer on
    /// the left, whichever way the disk is turned, as Gargantua's is.
    static let disk: String = """
    #pragma arguments
    float rpProbe;

    #pragma body
    float3 rp_centre = scn_node.modelViewTransform[3].xyz;
    float2 rp_off = _surface.position.xy - rp_centre.xy;
    float rp_side = rp_off.x / (length(rp_off) + 0.0001);
    float rp_boost = 0.8 + 0.25 * rp_side + 0.45 * max(rp_side, 0.0);
    float3 rp_col = _surface.diffuse.rgb * rp_boost;
    _surface.diffuse = float4(rp_col + float3(rpProbe), 1.0);
    """

    /// A link: one beam. A steady white-gold core, an orange inner glow
    /// and a haze, all under one cross-section envelope that reaches exactly
    /// zero at the ribbon's edges, with one hue running from white-gold in
    /// the middle through orange to a faint violet at the very edge. Round
    /// the core: three layers of streaming filaments, two thin helix strands
    /// and crackling branched sparks. Along it: long soft pulses and rarer,
    /// faster surges, which lift only the centre.
    ///
    /// Nothing repeats section by section: three slow value noises along
    /// the link (per-link seed, drifting in time) vary the filaments'
    /// density, brightness and speed, the haze's thickness, the helix, and
    /// how often it crackles. Nothing steps in time, and nothing has an edge
    /// across the beam. Its ends fade in from under each note's ring.
    ///
    /// The ribbon's texture coordinates carry its numbers (GraphSim builds
    /// them): u = seed * 64 + 1 + distance along the ribbon, in the space's
    /// units; v = k + position across it, where k = 2 * (length * 16) plus 1
    /// if the link touches the selected or dragged note. Mirrored line for
    /// line by the design mock (scratchpad mock/beam4.py).
    static let link: String = """
    #pragma arguments
    float rpClock;
    float rpMotion;
    float rpEnergy;
    float rpSolid;
    float rpProbe;

    #pragma body
    float2 rp_uv = _surface.diffuseTexcoord;
    float rp_seed = floor(rp_uv.x / 64.0);
    float rp_along = rp_uv.x - rp_seed * 64.0 - 1.0;
    float rp_k = floor(rp_uv.y);
    float rp_spanQ = floor(rp_k * 0.5);
    float rp_lit = rp_k - 2.0 * rp_spanQ;
    float rp_toEnd = rp_spanQ * 0.0625 - rp_along;
    float rp_s = fract(rp_uv.y) * 2.0 - 1.0;
    float rp_x = rp_along + rp_seed * 1.37;
    float rp_m = rpMotion;
    float rp_t = rpClock * rp_m;
    float rp_a = abs(rp_s);
    float rp_a2 = rp_a * rp_a;
    float rp_w = clamp(1.0 - rp_a2, 0.0, 1.0);
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
    float rp_thick = (0.7 + 0.5 * rp_nH) * rp_breath;
    float rp_haze = exp(-rp_a2 * 3.0 / (rp_thick * rp_thick)) * rp_w3;
    rp_haze = rp_haze * (0.16 + 0.22 * rp_nD);

    float rp_pp = rp_x * 0.3 - rp_t * 0.42 + rp_seed * 0.618;
    float rp_pi = floor(rp_pp);
    float rp_dw = (fract(rp_pp) - 0.5) / 0.3;
    float rp_sig = mix(0.7, 0.4, smoothstep(-0.2, 0.2, rp_dw));
    float rp_pz = rp_dw / rp_sig;
    float rp_ph = fract(sin(rp_pi * 7.13 + rp_seed) * 43758.5453);
    float rp_pulse = exp(-rp_pz * rp_pz) * (0.45 + 0.55 * rp_ph) * rp_m;
    float rp_sp = rp_x * 0.13 - rp_t * 0.31 + rp_seed * 0.37;
    float rp_si = floor(rp_sp);
    float rp_sw = (fract(rp_sp) - 0.5) / 0.13;
    float rp_ssig = mix(1.0, 0.5, smoothstep(-0.3, 0.3, rp_sw));
    float rp_sz = rp_sw / rp_ssig;
    float rp_sh = fract(sin(rp_si * 3.31 + rp_seed * 1.7) * 43758.5453);
    float rp_surge = exp(-rp_sz * rp_sz) * smoothstep(0.55, 0.9, rp_sh) * rp_m;
    float rp_mid = exp(-rp_a2 * 20.0);
    float rp_kick = (rp_pulse * 1.2 + rp_surge * 2.2) * rp_mid;

    float3 rp_gold = float3(1.0, 0.753, 0.302);
    float3 rp_white = float3(1.0, 0.95, 0.84);
    float3 rp_orange = float3(1.0, 0.416, 0.0);
    float3 rp_amber = float3(1.0, 0.30, 0.02);
    float3 rp_violet = float3(0.45, 0.28, 1.0);
    float rp_heat = clamp(rp_core * 0.9 + rp_inner * 0.3 + rp_kick * 0.5, 0.0, 1.0);
    float rp_rim = smoothstep(0.5, 1.0, rp_a) * 0.55;
    float3 rp_base = mix(rp_orange, rp_violet, rp_rim);
    float3 rp_hot = mix(rp_gold, rp_white, clamp(rp_heat * 2.0 - 1.0, 0.0, 1.0));
    float3 rp_hue = mix(rp_base, rp_hot, rp_heat);
    float rp_glow = rp_core * 0.8 + rp_inner * 0.4 + rp_haze;
    rp_glow = rp_glow + (rp_core * 1.6 + rp_inner * 0.4) * rp_kick;
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
    rp_col = rp_col + rp_fl * (rp_w2 * 0.4);

    float rp_ph1 = rp_x * 3.1 - rp_t * 2.3 + rp_seed * 1.3 + rp_nH * 2.0;
    float rp_y1 = 0.32 * (0.6 + 0.8 * rp_nH) * sin(rp_ph1);
    float rp_e1 = rp_s - rp_y1;
    float rp_s1 = exp(-rp_e1 * rp_e1 * 900.0) * (0.55 + 0.45 * cos(rp_ph1));
    float rp_ph2 = rp_x * 2.3 + rp_t * 1.4 + rp_seed * 2.9 - rp_nH * 1.5;
    float rp_y2 = 0.26 * (1.3 - 0.6 * rp_nH) * sin(rp_ph2);
    float rp_e2 = rp_s - rp_y2;
    float rp_s2 = exp(-rp_e2 * rp_e2 * 900.0) * (0.55 + 0.45 * cos(rp_ph2));
    float rp_helix = (rp_s1 + rp_s2) * rp_w * 0.5 * rp_m;
    rp_col = rp_col + mix(rp_gold, rp_white, 0.5) * rp_helix;

    // (no crackle: the owner chose the calm beam without the blue-white sparks)

    float rp_f = sin(rp_t * 4.1 + rp_seed * 3.1) * sin(rp_t * 2.3 + rp_seed * 7.7);
    float rp_flicker = 1.0 - 0.08 * rp_m * (0.5 + 0.5 * rp_f);
    float rp_boost = 1.0 + 0.5 * rp_lit;
    float rp_ends = smoothstep(0.0, 0.28, rp_along) * smoothstep(0.0, 0.28, rp_toEnd);
    rp_col = rp_col * (rp_flicker * rp_boost * rp_ends * rpEnergy);
    _surface.diffuse = float4(rp_col + float3(rpProbe), 1.0);
    """
}

// MARK: - checking the shaders work

/// Which shader modifiers compiled and drew on this device.
nonisolated struct GraphShaderSupport: Sendable {
    let ring: Bool
    let disk: Bool
    let link: Bool

    static let none = GraphShaderSupport(ring: false, disk: false, link: false)
}

/// A shader modifier that fails to compile fails silently: SceneKit logs it
/// and draws nothing, or the plain material. So before the space is built,
/// each modifier is tried once, off the main thread, in a tiny offscreen
/// render: a plane covered with a black texture and the modifier, with
/// `rpProbe` set to 1. A working modifier paints it white; a broken one
/// leaves it black. Any that fail are left off, and those pieces use their
/// baked textures alone - the notes and links still show, just still.
nonisolated enum GraphShaderProbe {
    /// Worked out once per launch, the first time it is asked for.
    static let support: GraphShaderSupport = run()

    private static func run() -> GraphShaderSupport {
        guard let device = MTLCreateSystemDefaultDevice() else { return .none }
        let ring: Bool = passes(GraphShaders.ring, device: device)
        let disk: Bool = passes(GraphShaders.disk, device: device)
        let link: Bool = passes(GraphShaders.link, device: device)
        return GraphShaderSupport(ring: ring, disk: disk, link: link)
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
        material.setValue(NSNumber(value: 1.0), forKey: "rpProbe")
        material.setValue(NSNumber(value: 0.0), forKey: "rpClock")
        material.setValue(NSNumber(value: 0.0), forKey: "rpMotion")
        material.setValue(NSNumber(value: 1.0), forKey: "rpEnergy")
        material.setValue(NSNumber(value: 0.0), forKey: "rpSolid")
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

    /// A tiny all-black texture, drawn without UIKit's renderers so it is
    /// safe off the main thread.
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

    /// The brightest channel of the middle pixel, 0 to 1.
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
            // draw the image so that its middle pixel lands on the only one
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

// MARK: - textures

/// The textures, generated in code once and shared.
///
/// The glow textures are opaque: black where there is nothing, so that with
/// additive blending black adds nothing and no alpha is involved at all.
nonisolated enum GraphArt {
    static let orange = SIMD3<Float>(1.0, 0.416, 0.0)     // #FF6A00
    static let gold = SIMD3<Float>(1.0, 0.753, 0.302)     // #FFC04D
    static let ember = SIMD3<Float>(0.62, 0.08, 0.0)
    static let whiteHot = SIMD3<Float>(1.0, 0.95, 0.84)
    static let violet = SIMD3<Float>(0.42, 0.26, 1.0)

    /// The photon ring, for a plane GraphShape.ringPlane radii across: a thin
    /// ring just outside the silhouette, brighter and whiter on the right;
    /// the lensed far side of the disk arching over the top and under the
    /// bottom; and a soft orange glow outside.
    static let ring: UIImage = square(256) { x, y in ringShade(x, y) }

    /// The accretion disk, face on: layered, streaky, fiery bands following
    /// the orbit, white-gold at the inner edge through orange to red.
    static let disk: UIImage = square(400) { x, y in diskShade(x, y) }

    /// Across a link's ribbon (down the image): used as is when the link
    /// shader is off, and to carry texture coordinates when it is on.
    static let linkGlow: UIImage = strip(bold: false)
    static let linkGlowBold: UIImage = strip(bold: true)

    /// One spark of a comet trail.
    static let spark: UIImage = square(32) { x, y in
        let r2: Float = x * x + y * y
        let glow: Float = exp(-r2 * 7)
        let core: Float = exp(-r2 * 40)
        let warm: SIMD3<Float> = SIMD3<Float>(1, 1, 1) * glow
        let hot: SIMD3<Float> = SIMD3<Float>(1, 1, 1) * core
        return warm * 0.7 + hot * 0.3
    }

    // MARK: shading

    private static func ringShade(_ x: Float, _ y: Float) -> SIMD3<Float> {
        let r: Float = (x * x + y * y).squareRoot()
        guard r > 0.3 else { return .zero }
        let cosA: Float = x / r
        let sinA: Float = y / r
        // 1 on the right, 0 on the left
        let side: Float = 0.5 + 0.5 * cosA
        let bright: Float = 0.5 + 0.8 * side

        // the photon ring: sharp inside, a little softer outside
        let d: Float = r - GraphShape.ringPeak
        let sigma: Float = d < 0 ? 0.010 : 0.022
        let q: Float = d / sigma
        let photon: Float = exp(-q * q)
        let hue: SIMD3<Float> = mix(gold, whiteHot, t: side * side)
        let ringPart: SIMD3<Float> = hue * (photon * bright * 1.2)

        // the lensed arcs, over the top and under the bottom
        let lensAt: Float = 0.64
        let ld: Float = (r - lensAt) / 0.06
        let topBottom: Float = pow(abs(sinA), 1.5)
        let lensWeight: Float = 0.25 + 0.75 * topBottom
        let lens: Float = exp(-ld * ld) * lensWeight * 0.8
        let lensHue: SIMD3<Float> = mix(orange, gold, t: 0.35)
        let lensPart: SIMD3<Float> = lensHue * (lens * (0.7 + 0.5 * side))

        // a soft glow outside the rim
        let outside: Float = max(d, 0)
        let inner: Float = d > 0 ? 1 : photon
        let halo: Float = exp(-outside / 0.16) * 0.28 * inner
        let haloHue: SIMD3<Float> = mix(orange, gold, t: 0.3)
        let haloPart: SIMD3<Float> = haloHue * (halo * bright)

        let sum: SIMD3<Float> = ringPart + lensPart + haloPart
        return sum * edgeFade(r)
    }

    private static func diskShade(_ x: Float, _ y: Float) -> SIMD3<Float> {
        let r: Float = (x * x + y * y).squareRoot()
        let inner: Float = GraphShape.diskInner
        guard r > inner - 0.02, r < 1 else { return .zero }
        let a: Float = atan2(y, x)
        let u: Float = (r - inner) / (1 - inner)
        let rise: Float = smooth(clamp01(u / 0.05))
        let falloff: Float = pow(max(1 - u, 0), 1.6)

        // bands following the orbit, gently wavy
        let wave1: Float = sin(a * 2 + 1.3) * 0.9 + sin(a * 5 + 0.4) * 0.35
        let b1: Float = 0.5 + 0.5 * sin(r * 95 + wave1 * 1.4)
        let wave2: Float = sin(a * 3 + 2) * 1.1
        let b2: Float = 0.5 + 0.5 * sin(r * 47 + 2.1 + wave2)
        let wave3: Float = sin(a * 7 + 0.7) * 2
        let b3: Float = 0.5 + 0.5 * sin(r * 180 + wave3)
        let bands: Float = 0.35 + 0.4 * b1 * b2 + 0.25 * b3

        // streaks: brighter and darker stretches along the orbit
        let swirl: Float = sin(a * 2) * 1.5
        let streak: Float = 0.55 + 0.45 * sin(a * 6 + r * 30 + swirl)

        let heat: Float = rise * falloff * bands * (0.6 + 0.4 * streak)
        return fire(heat * 1.15)
    }

    /// Black through ember red, orange and gold to white-hot.
    private static func fire(_ heat: Float) -> SIMD3<Float> {
        let t: Float = clamp01(heat)
        let stops: [Float] = [0, 0.25, 0.5, 0.7, 0.88, 1]
        let colours: [SIMD3<Float>] = [
            .zero, ember, SIMD3<Float>(0.9, 0.22, 0), orange, gold, whiteHot
        ]
        for k in 1..<stops.count where t <= stops[k] {
            let low: Float = stops[k - 1]
            let span: Float = stops[k] - low
            let f: Float = (t - low) / span
            return mix(colours[k - 1], colours[k], t: f)
        }
        return whiteHot
    }

    /// Across a link, from edge (-1) through the middle to edge (1).
    private static func strip(bold: Bool) -> UIImage {
        image(width: 2, height: 128) { _, s in
            let s2: Float = s * s
            let coreWidth: Float = bold ? 60 : 420
            let core: Float = exp(-s2 * coreWidth)
            let inner: Float = exp(-s2 * 20) * (bold ? 0.8 : 0.6)
            let aura: Float = exp(-abs(s) * 3.0) * 0.6
            let edge: Float = clamp01(abs(s) * 1.4 - 0.2)
            let auraHue: SIMD3<Float> = mix(orange, violet, t: edge)
            let white: SIMD3<Float> = whiteHot * core
            let warm: SIMD3<Float> = orange * inner
            let outer: SIMD3<Float> = auraHue * aura
            let fade: Float = clamp01((1 - abs(s)) * 4)
            let sum: SIMD3<Float> = white + warm + outer
            return sum * fade
        }
    }

    // MARK: helpers

    private static func edgeFade(_ r: Float) -> Float {
        let e: Float = clamp01((1 - r) / 0.18)
        return smooth(e)
    }

    private static func smooth(_ e: Float) -> Float {
        e * e * (3 - 2 * e)
    }

    private static func clamp01(_ v: Float) -> Float {
        min(max(v, 0), 1)
    }

    private static func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
        let d: SIMD3<Float> = b - a
        return a + d * t
    }

    private static func square(_ size: Int, _ shade: (Float, Float) -> SIMD3<Float>) -> UIImage {
        image(width: size, height: size, shade)
    }

    /// An opaque image, each pixel shaded from its position: x and y run from
    /// -1 to 1, y upwards.
    private static func image(width: Int, height: Int,
                              _ shade: (Float, Float) -> SIMD3<Float>) -> UIImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let halfW: Float = Float(width) / 2
        let halfH: Float = Float(height) / 2
        for row in 0..<height {
            let y: Float = (halfH - Float(row) - 0.5) / halfH
            for col in 0..<width {
                let x: Float = (Float(col) + 0.5 - halfW) / halfW
                let c: SIMD3<Float> = shade(x, y)
                let k: Int = (row * width + col) * 4
                bytes[k] = byte(c.x)
                bytes[k + 1] = byte(c.y)
                bytes[k + 2] = byte(c.z)
                bytes[k + 3] = 255
            }
        }
        let data = Data(bytes)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8,
                               bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                               bitmapInfo: info, provider: provider, decode: nil,
                               shouldInterpolate: true, intent: .defaultIntent)
        else { return UIImage() }
        return UIImage(cgImage: cg)
    }

    private static func byte(_ v: Float) -> UInt8 {
        let clamped: Float = min(max(v, 0), 1)
        return UInt8(clamped * 255 + 0.5)
    }
}

// MARK: - the space behind

/// Deep space, drawn as geometry rather than a picture, so it is sharp at
/// any screen size and never stretched:
///
/// - a sky sphere whose vertex colours carry a blue-black gradient and a
///   faint Milky Way band with blue, violet and teal nebula in it (smooth,
///   low-frequency colour, interpolated across the triangles - nothing to
///   magnify into blocks);
/// - about 6,000 stars as points of a fixed size on screen (1 to 3 pixels),
///   crowded along the same band;
/// - ten brighter blue-white stars with a small, dim glow.
///
/// Everything is made once, on a sphere of radius 1, and shared by every
/// scene; the builder scales the node, and GraphSim keeps it centred on the
/// camera each frame, so the sky is at infinity: it turns as the camera
/// turns and never moves by itself (so Reduce Motion needs nothing).
@MainActor
enum GraphSpace {
    /// The Milky Way's plane, tilted across the sky.
    nonisolated static let bandNormal: SIMD3<Float> = simd_normalize(SIMD3<Float>(0.35, 0.9, 0.25))

    /// A new node holding the three layers (the geometry is shared).
    static func makeSky() -> SCNNode {
        let sky = SCNNode()
        sky.name = "sky"
        sky.categoryBitMask = 2
        let domeNode = SCNNode(geometry: Self.dome)
        domeNode.renderingOrder = -30
        let starNode = SCNNode(geometry: Self.stars)
        starNode.renderingOrder = -29
        let glowNode = SCNNode(geometry: Self.glowStars)
        glowNode.renderingOrder = -28
        for layer in [domeNode, starNode, glowNode] {
            layer.categoryBitMask = 2
            sky.addChildNode(layer)
        }
        return sky
    }

    // MARK: the dome

    private static let dome: SCNGeometry = makeDome()

    private static func makeDome() -> SCNGeometry {
        let columns: Int = 96
        let rows: Int = 48
        var positions: [SCNVector3] = []
        var colours: [Float] = []
        let blobs: [(SIMD3<Float>, Float, SIMD3<Float>)] = nebulaBlobs()
        for row in 0...rows {
            let lat: Float = Float.pi * (Float(row) / Float(rows) - 0.5)
            for column in 0...columns {
                let lon: Float = 2 * Float.pi * Float(column) / Float(columns)
                let flat: Float = cos(lat)
                let dir = SIMD3<Float>(flat * cos(lon), sin(lat), flat * sin(lon))
                positions.append(SCNVector3(x: dir.x, y: dir.y, z: dir.z))
                let c: SIMD3<Float> = linear(skyColour(dir, blobs: blobs))
                colours.append(c.x)
                colours.append(c.y)
                colours.append(c.z)
            }
        }
        var indices: [Int32] = []
        let stride: Int = columns + 1
        for row in 0..<rows {
            for column in 0..<columns {
                let a = Int32(row * stride + column)
                let b = Int32(row * stride + column + 1)
                let c = Int32((row + 1) * stride + column)
                let d = Int32((row + 1) * stride + column + 1)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        let source = SCNGeometrySource(vertices: positions)
        let tint = colourSource(colours, count: positions.count)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source, tint], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        geometry.materials = [material]
        return geometry
    }

    /// The sky's colour looking along `dir` (sRGB).
    private static func skyColour(_ dir: SIMD3<Float>,
                                  blobs: [(SIMD3<Float>, Float, SIMD3<Float>)]) -> SIMD3<Float> {
        let pole = SIMD3<Float>(0.004, 0.006, 0.022)
        let middle = SIMD3<Float>(0.018, 0.032, 0.095)
        let height: Float = abs(dir.y)
        let towardsPole: Float = pow(height, 0.8)
        let base: SIMD3<Float> = middle + (pole - middle) * towardsPole
        let across: Float = simd_dot(dir, bandNormal) / 0.22
        let band: Float = exp(-across * across)
        let glow: SIMD3<Float> = SIMD3<Float>(0.02, 0.03, 0.07) * band
        var cloud = SIMD3<Float>(0, 0, 0)
        for (centre, reach, hue) in blobs {
            let gap: Float = simd_distance(dir, centre) / reach
            cloud += hue * exp(-gap * gap)
        }
        let soft: Float = band.squareRoot()
        let sum: SIMD3<Float> = base + glow
        return sum + cloud * soft
    }

    /// Nebula clouds along the band: direction, reach and colour (with
    /// strength).
    private static func nebulaBlobs() -> [(SIMD3<Float>, Float, SIMD3<Float>)] {
        let hues: [SIMD3<Float>] = [
            SIMD3<Float>(0.20, 0.30, 0.78),
            SIMD3<Float>(0.36, 0.22, 0.66),
            SIMD3<Float>(0.12, 0.36, 0.58)
        ]
        var random = SplitMix64(seed: 0x0B1A)
        var blobs: [(SIMD3<Float>, Float, SIMD3<Float>)] = []
        for k in 0..<30 {
            let near: SIMD3<Float> = onBand(&random, spread: 0.12)
            let reach: Float = 0.18 + (random.unit() * 0.5 + 0.5) * 0.3
            let strength: Float = 0.07 + (random.unit() * 0.5 + 0.5) * 0.09
            blobs.append((near, reach, hues[k % hues.count] * strength))
        }
        return blobs
    }

    // MARK: the stars

    private static let stars: SCNGeometry = makeStars()

    private static func makeStars() -> SCNGeometry {
        var random = SplitMix64(seed: 0x57A3)
        let tints: [SIMD3<Float>] = [
            SIMD3<Float>(1, 1, 1),
            SIMD3<Float>(0.76, 0.85, 1),
            SIMD3<Float>(1, 0.9, 0.76)
        ]
        var positions: [SCNVector3] = []
        var colours: [Float] = []
        // three sizes, one element each
        var small: [Int32] = []
        var medium: [Int32] = []
        var large: [Int32] = []
        for k in 0..<14000 {
            let dir: SIMD3<Float> = k % 5 < 2 ? onBand(&random, spread: 0.18) : anywhere(&random)
            let roll: Float = random.unit() * 0.5 + 0.5
            let shine: Float = roll * roll * roll * roll
            let brightness: Float = 0.42 + shine * 0.95
            let c: SIMD3<Float> = linear(tints[k % tints.count] * brightness)
            let index = Int32(positions.count)
            positions.append(SCNVector3(x: dir.x, y: dir.y, z: dir.z))
            colours.append(c.x)
            colours.append(c.y)
            colours.append(c.z)
            if shine < 0.12 {
                small.append(index)
            } else if shine < 0.5 {
                medium.append(index)
            } else {
                large.append(index)
            }
        }
        let source = SCNGeometrySource(vertices: positions)
        let tint = colourSource(colours, count: positions.count)
        let elements: [SCNGeometryElement] = [
            points(small, radius: 1.0),
            points(medium, radius: 1.6),
            points(large, radius: 2.3)
        ]
        let geometry = SCNGeometry(sources: [source, tint], elements: elements)
        let material = additive(UIColor.white)
        geometry.materials = [material]
        return geometry
    }

    /// Points a fixed number of pixels across, whatever the distance.
    private static func points(_ indices: [Int32], radius: CGFloat) -> SCNGeometryElement {
        let element = SCNGeometryElement(indices: indices, primitiveType: .point)
        element.pointSize = 0.001
        element.minimumPointScreenSpaceRadius = radius
        element.maximumPointScreenSpaceRadius = radius
        return element
    }

    // MARK: the few bright stars

    private static let glowStars: SCNGeometry = makeGlowStars()

    /// Small square cards facing the sphere's centre - where the camera
    /// always is - each with a soft glow; dim, and none large.
    private static func makeGlowStars() -> SCNGeometry {
        var random = SplitMix64(seed: 0x6105)
        var positions: [SCNVector3] = []
        var uvs: [Float] = []
        var colours: [Float] = []
        var indices: [Int32] = []
        let tint: SIMD3<Float> = linear(SIMD3<Float>(0.78, 0.85, 1.0))
        for _ in 0..<36 {
            let dir: SIMD3<Float> = anywhere(&random)
            let helper: SIMD3<Float> = abs(dir.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
            let side: SIMD3<Float> = simd_normalize(simd_cross(dir, helper))
            let up: SIMD3<Float> = simd_cross(side, dir)
            // about 7 pixels from the middle to the card's edge on a phone
            let size: Float = 0.0032 + (random.unit() * 0.5 + 0.5) * 0.0022
            let across: SIMD3<Float> = side * size
            let along: SIMD3<Float> = up * size
            let base = Int32(positions.count)
            let corners: [SIMD3<Float>] = [dir - across - along, dir + across - along,
                                           dir - across + along, dir + across + along]
            for corner in corners {
                positions.append(SCNVector3(x: corner.x, y: corner.y, z: corner.z))
                colours.append(tint.x)
                colours.append(tint.y)
                colours.append(tint.z)
            }
            uvs.append(contentsOf: [0, 1, 1, 1, 0, 0, 1, 0])
            indices.append(contentsOf: [base, base + 1, base + 2, base + 2, base + 1, base + 3])
        }
        let source = SCNGeometrySource(vertices: positions)
        let tintSource = colourSource(colours, count: positions.count)
        let uvData: Data = uvs.withUnsafeBufferPointer { Data(buffer: $0) }
        let uvSource = SCNGeometrySource(data: uvData, semantic: .texcoord,
                                         vectorCount: positions.count, usesFloatComponents: true,
                                         componentsPerVector: 2, bytesPerComponent: 4,
                                         dataOffset: 0, dataStride: 8)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [source, tintSource, uvSource], elements: [element])
        let material = additive(GraphArt.spark)
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }

    // MARK: helpers

    private static func additive(_ contents: Any) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = contents
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        return material
    }

    /// Per-vertex colour, three floats each (linear).
    private static func colourSource(_ colours: [Float], count: Int) -> SCNGeometrySource {
        let data: Data = colours.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: data, semantic: .color, vectorCount: count,
                                 usesFloatComponents: true, componentsPerVector: 3,
                                 bytesPerComponent: 4, dataOffset: 0, dataStride: 12)
    }

    /// sRGB to linear: SceneKit shades in linear space, and vertex colours
    /// are taken as linear.
    private static func linear(_ c: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(pow(max(c.x, 0), 2.2), pow(max(c.y, 0), 2.2), pow(max(c.z, 0), 2.2))
    }

    /// A random direction, even over the sphere.
    private static func anywhere(_ random: inout SplitMix64) -> SIMD3<Float> {
        let y: Float = random.unit()
        let turn: Float = random.unit() * Float.pi
        let flat: Float = max(1 - y * y, 0).squareRoot()
        return SIMD3<Float>(flat * cos(turn), y, flat * sin(turn))
    }

    /// A random direction near the band's plane.
    private static func onBand(_ random: inout SplitMix64, spread: Float) -> SIMD3<Float> {
        let dir: SIMD3<Float> = anywhere(&random)
        let off: Float = simd_dot(dir, bandNormal)
        let scatter: Float = random.unit() * random.unit() * spread
        let flat: SIMD3<Float> = dir - bandNormal * off
        let lifted: SIMD3<Float> = flat + bandNormal * scatter
        return simd_normalize(lifted)
    }
}

// MARK: - materials

/// The materials, made once per folder (and once for the selected note),
/// never per note or per frame.
@MainActor
enum GraphLook {
    /// The folder's colour, drawn only a little way into white, so it tints
    /// the ring and disk without leaving the warm palette.
    static func tint(_ folder: UIColor) -> UIColor {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard folder.getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
        let share: CGFloat = 0.3
        let keep: CGFloat = 1 - share
        return UIColor(red: keep + r * share, green: keep + g * share,
                       blue: keep + b * share, alpha: 1)
    }

    /// The sphere: pure black, unlit, opaque, writing depth so that what is
    /// behind it - the far half of its disk, other notes, links - is hidden.
    static func hole() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.black
        material.specular.contents = UIColor.black
        material.emission.contents = UIColor.black
        material.transparency = 1
        material.blendMode = .replace
        return material
    }

    /// The photon ring. `hot` is the brighter one for the selected note.
    static func ring(tint: UIColor, hot: Bool, shader: Bool, lively: Bool) -> SCNMaterial {
        let material = glow(GraphArt.ring)
        material.multiply.contents = hot ? UIColor.white : tint
        material.diffuse.intensity = hot ? 1.7 : 1
        material.isDoubleSided = true
        if shader {
            material.shaderModifiers = [.surface: GraphShaders.ring]
            set(material, "rpClock", 0)
            set(material, "rpMotion", lively ? 1 : 0)
            set(material, "rpProbe", 0)
        }
        return material
    }

    /// The accretion disk. `hot` is the brighter one for the selected note.
    static func disk(tint: UIColor, hot: Bool, shader: Bool) -> SCNMaterial {
        let material = glow(GraphArt.disk)
        material.multiply.contents = hot ? UIColor.white : tint
        material.diffuse.intensity = hot ? 1.45 : 1
        material.isDoubleSided = true
        if shader {
            material.shaderModifiers = [.surface: GraphShaders.disk]
            set(material, "rpProbe", 0)
        }
        return material
    }

    /// Every link, all in one geometry.
    static func link(bold: Bool, shader: Bool, lively: Bool) -> SCNMaterial {
        let material = glow(bold ? GraphArt.linkGlowBold : GraphArt.linkGlow)
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.isDoubleSided = true
        if shader {
            material.shaderModifiers = [.surface: GraphShaders.link]
            set(material, "rpClock", 0)
            set(material, "rpMotion", lively ? 1 : 0)
            set(material, "rpEnergy", bold ? 1.5 : 1)
            set(material, "rpSolid", bold ? 1 : 0)
            set(material, "rpProbe", 0)
        } else if bold {
            material.diffuse.intensity = 1.4
        }
        return material
    }

    /// A short-lived comet trail of orange sparks. It emits nothing until
    /// GraphSim raises its birth rate for a moving note.
    /// `scale` is the notes' size over the original 0.2 radius.
    static func trail(scale: Float) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.birthRate = 0
        system.loops = true
        system.emissionDuration = 1
        system.particleLifeSpan = 0.5
        system.particleLifeSpanVariation = 0.2
        system.particleSize = CGFloat(0.035 * scale)
        system.particleSizeVariation = CGFloat(0.02 * scale)
        system.particleVelocity = CGFloat(0.12 * scale)
        system.particleVelocityVariation = CGFloat(0.1 * scale)
        system.spreadingAngle = 180
        system.dampingFactor = 1.5
        system.particleImage = GraphArt.spark
        system.particleColor = UIColor(red: 1, green: 0.55, blue: 0.12, alpha: 1)
        system.particleColorVariation = SCNVector4(x: 0.04, y: 0.1, z: 0.1, w: 0)
        system.blendMode = .additive
        system.isLightingEnabled = false
        system.isAffectedByGravity = false
        // born where the note is, then left behind in the space
        system.isLocal = false
        system.sortingMode = .none
        let fade = CAKeyframeAnimation()
        fade.values = [NSNumber(value: 1.0), NSNumber(value: 0.6), NSNumber(value: 0.0)]
        fade.keyTimes = [NSNumber(value: 0.0), NSNumber(value: 0.4), NSNumber(value: 1.0)]
        let shrink = CAKeyframeAnimation()
        shrink.values = [NSNumber(value: 1.0), NSNumber(value: 0.3)]
        shrink.keyTimes = [NSNumber(value: 0.0), NSNumber(value: 1.0)]
        system.propertyControllers = [
            .opacity: SCNParticlePropertyController(animation: fade),
            .size: SCNParticlePropertyController(animation: shrink)
        ]
        return system
    }

    /// Additive, unlit, over whatever is behind; tested against depth (so a
    /// black sphere in front hides it) but never writing it.
    private static func glow(_ image: UIImage) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.diffuse.mipFilter = .linear
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        return material
    }

    private static func set(_ material: SCNMaterial, _ key: String, _ value: Float) {
        material.setValue(NSNumber(value: value), forKey: key)
    }
}
