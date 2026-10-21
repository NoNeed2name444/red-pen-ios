// The Space theme's depth fade (docs/design/depth-fade.md) and near-only
// loading (plan 4e), as GraphSpaceDepth.swift and the Space shaders have
// them: the fade curve (D1), the band following the camera's focus at
// every zoom, along the view's depth (D2), the Graphics setting's reach
// (D3), Increase Contrast (D4), what is fully faded is not drawn and
// dissolves there with no pop (D5), shader detail by size on screen, whole
// up close (D6), the point level with its gap so nothing flickers (D7, D8),
// the view volume, the Performance theme's (D9), the shaders' fade and
// detail pieces (D10), the fade colour against the sky (D11), and the
// morphing noise octaves (D12).
//
// Compiled with GraphSpaceDepth.swift, GraphPerfLOD.swift,
// GraphPerfCamera.swift, GraphicsQuality.swift, GraphShaderKit.swift and
// GraphSpaceShaders.swift (Foundation only).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func near(_ a: Float, _ b: Float, _ tolerance: Float = 1e-5) -> Bool { abs(a - b) <= tolerance }

// MARK: D1 the curve

let band = SpaceDepthBand(start: 10, end: 30, exponent: 1.25, cap: 1)
let mid: Float = band.fade(20)
check("D1 crisp up to the start, gone at the end",
      band.fade(0) == 0 && band.fade(10) == 0 && band.fade(30) == 1 && band.fade(500) == 1,
      "\(band.fade(10)) \(band.fade(30))")
check("D1 f = clamp((z - start) / (end - start), 0, 1)^k", near(mid, pow(0.5, 1.25)), "\(mid)")
var rising = true
var last: Float = -1
for k in 0...400 {
    let f: Float = band.fade(Float(k) * 0.1)
    if f < last { rising = false }
    last = f
}
check("D1 never fades back in as depth grows", rising)
check("D1 additive light goes to nothing: light = 1 - f", near(band.light(20), 1 - mid) && band.light(30) == 0)
check("D1 a band never set fades nothing", SpaceDepthBand.off.fade(1000) == 0 && SpaceDepthBand.off.uniform == SIMD4<Float>(0, 0, 0, 0))

// MARK: D2 the band follows the focus

var focusCrisp = true
var sameAtEveryScale = true
for focus in [Float(0.01), 0.3, 1, 7, 40, 900] {
    let b: SpaceDepthBand = SpaceDepth.band(focusDepth: focus, tier: .high)
    let focusOK: Bool = b.fade(focus) == 0 && b.crisp(focus) && !b.gone(focus)
    if !focusOK { focusCrisp = false }
    let unit: SpaceDepthBand = SpaceDepth.band(focusDepth: 1, tier: .high)
    for z in stride(from: Float(0), through: 4, by: 0.25) where focus >= SpaceDepth.nearestFocus {
        if !near(b.fade(z * focus), unit.fade(z), 1e-4) { sameAtEveryScale = false }
    }
}
check("D2 what the camera looks at is crisp at every zoom", focusCrisp)
check("D2 start and end are multiples of the focus's depth: a small note up close fades as the whole map",
      sameAtEveryScale)
// depth is along the view, not distance from the map's centre or the eye
let eye = SIMD3<Float>(0, 0, 10)
let ahead = SIMD3<Float>(0, 0, -1)
let straight: Float = SpaceDepth.depth(of: SIMD3<Float>(0, 0, 0), eye: eye, forward: ahead)
let aside: Float = SpaceDepth.depth(of: SIMD3<Float>(6, -4, 0), eye: eye, forward: ahead)
check("D2 depth is view-space z: a body off to the side at the same z fades the same",
      straight == 10 && aside == 10, "\(straight) \(aside)")
// turning: the far side comes forward and sharpens, the near side goes back
let farSide = SIMD3<Float>(0, 0, -8)
let b10: SpaceDepthBand = SpaceDepth.band(focusDepth: 10, tier: .high)
let before: Float = b10.fade(SpaceDepth.depth(of: farSide, eye: eye, forward: ahead))
let turnedEye = SIMD3<Float>(0, 0, -10)
let turnedAhead = SIMD3<Float>(0, 0, 1)
let after: Float = b10.fade(SpaceDepth.depth(of: farSide, eye: turnedEye, forward: turnedAhead))
let nearSideAfter: Float = b10.fade(SpaceDepth.depth(of: SIMD3<Float>(0, 0, 8), eye: turnedEye,
                                                     forward: turnedAhead))
check("D2 turned round the focus, the far side sharpens and the near side fades",
      before > 0.3 && after == 0 && nearSideAfter > 0.3, "\(before) \(after) \(nearSideAfter)")

// MARK: D3 the Graphics setting sets the reach

let high: SpaceDepthBand = SpaceDepth.band(focusDepth: 10, tier: .high)
let smooth: SpaceDepthBand = SpaceDepth.band(focusDepth: 10, tier: .smooth)
check("D3 Smooth pulls the end in (less drawn), High pushes it out",
      smooth.end < high.end && smooth.start > 10 && high.start > 10, "\(smooth) \(high)")
check("D3 every tier reaches the background, so what is past it is not drawn", high.culls && smooth.culls)

// MARK: D4 Increase Contrast

let plain: SpaceDepthBand = SpaceDepth.band(focusDepth: 10, tier: .high)
let contrast: SpaceDepthBand = SpaceDepth.band(focusDepth: 10, tier: .high, contrast: true)
check("D4 with Increase Contrast the fade starts later and stops short of the sky",
      contrast.start > plain.start && contrast.fade(1e6) < 1 && contrast.fade(1e6) > 0.3)
check("D4 nothing stopped short is culled or dissolved", !contrast.culls && !contrast.gone(1e6)
      && contrast.dissolve(1e6) == 1)

// MARK: D5 fully faded is not drawn, with no pop

check("D5 past the end is gone, before it is not", plain.gone(plain.end) && !plain.gone(plain.end - 0.01))
var dissolveSmooth = true
var lastDissolve: Float = 1
for k in 0...2000 {
    let z: Float = plain.start + (plain.end - plain.start) * Float(k) / 2000
    let d: Float = plain.dissolve(z)
    if abs(d - lastDissolve) > 0.01 { dissolveSmooth = false }
    lastDissolve = d
}
check("D5 a solid body keeps its opacity until nearly faded, then goes smoothly to nothing at the end",
      plain.dissolve(plain.start) == 1 && dissolveSmooth && plain.dissolve(plain.end) == 0,
      "\(plain.dissolve(plain.end))")
let lastBit: Float = plain.dissolve(plain.end - (plain.end - plain.start) * 0.001)
check("D5 just before it is culled nothing of it is left to pop", lastBit < 0.001, "\(lastBit)")
let atHalf: Float = plain.start + (plain.end - plain.start) * pow(0.85, 1 / SpaceDepth.exponent)
check("D5 the dissolve starts only where f is 0.85", near(plain.dissolve(atHalf - 0.01), 1, 1e-3))

// MARK: D6 shader detail by size on screen

check("D6 up close the whole detail, every pixel the same as before",
      SpaceDepth.detail(pixelRadius: GraphStyleShaders.detailHigh) == 1
      && SpaceDepth.detail(pixelRadius: 400) == 1)
check("D6 small on screen, the simple path", SpaceDepth.detail(pixelRadius: GraphStyleShaders.detailLow) == 0
      && SpaceDepth.detail(pixelRadius: 1) == 0)
var detailSmooth = true
var lastDetail: Float = 0
for k in 0...4000 {
    let px: Float = Float(k) * 0.01
    let w: Float = SpaceDepth.detail(pixelRadius: px)
    if w < lastDetail || w - lastDetail > 0.002 { detailSmooth = false }
    lastDetail = w
}
check("D6 detail falls gradually and smoothly as it zooms out: no step anywhere", detailSmooth)
let focal: Float = SpaceDepth.focal(viewHeight: 800, fovY: 55 * Float.pi / 180)
check("D6 size on screen is the Performance theme's (radius x focal / depth)",
      near(SpaceDepth.pixelRadius(2, depth: 10, viewHeight: 800, fovY: 55 * Float.pi / 180),
           GraphPerfLOD.pixelRadius(2, depth: 10, focal: focal)) && near(focal, 400 / tan(27.5 * Float.pi / 180), 1e-2))

// MARK: D7 the point level, with a gap

var state: SpaceBodyLevel = .body
var flips = 0
for k in 0..<200 {
    // a body hovering round the edge: 1.6 to 2.1 points and back
    let px: Float = 1.85 + 0.25 * sin(Float(k) * 0.3)
    let next: SpaceBodyLevel = SpaceDepth.level(state, pixelRadius: px, fade: 0, gone: false, inView: true)
    if next != state { flips += 1 }
    state = next
}
check("D7 a body at the edge of the point size does not flicker", flips == 0 && state == .body, "\(flips)")
let toPoint: SpaceBodyLevel = SpaceDepth.level(.body, pixelRadius: 1.4, fade: 0, gone: false, inView: true)
let staysPoint: SpaceBodyLevel = SpaceDepth.level(.point, pixelRadius: 2.0, fade: 0, gone: false, inView: true)
let backToBody: SpaceBodyLevel = SpaceDepth.level(.point, pixelRadius: 2.3, fade: 0, gone: false, inView: true)
check("D7 under 1.5 points a point; back to its body only from 2.25", toPoint == .point && staysPoint == .point
      && backToBody == .body)
let fadedPoint: SpaceBodyLevel = SpaceDepth.level(.body, pixelRadius: 2.9, fade: 0.7, gone: false, inView: true)
let crispBody: SpaceBodyLevel = SpaceDepth.level(.body, pixelRadius: 2.9, fade: 0.2, gone: false, inView: true)
check("D7 detail drops sooner only where the body has mostly faded (f 0.6)",
      fadedPoint == .point && crispBody == .body)
check("D7 outside the view or past the band: gone",
      SpaceDepth.level(.body, pixelRadius: 50, fade: 0, gone: false, inView: false) == .gone
      && SpaceDepth.level(.point, pixelRadius: 50, fade: 1, gone: true, inView: true) == .gone)
check("D7 coming back into view it takes the level its size says",
      SpaceDepth.level(.gone, pixelRadius: 40, fade: 0, gone: false, inView: true) == .body
      && SpaceDepth.level(.gone, pixelRadius: 1, fade: 0, gone: false, inView: true) == .point)

// MARK: D8 the point is the body's size

check("D8 a point is drawn at the body's own size on screen, never under a point",
      SpaceDepth.pointRadius(pixelRadius: 1.4) == 1.4 && SpaceDepth.pointRadius(pixelRadius: 0.2) == 1)

// MARK: D9 the view volume (the Performance theme's)

var orbit = GraphPerfCamera()
orbit.yaw = 0.7
orbit.pitch = 0.3
orbit.distance = 20
let theirs: GraphPerfFrustum = orbit.frustum(width: 390, height: 844, near: 0.1, far: 100)
let ours: GraphPerfFrustum = SpaceDepth.frustum(eye: orbit.eye, forward: orbit.forward, right: orbit.right,
                                                up: orbit.up, fovY: orbit.fovY, width: 390, height: 844,
                                                near: 0.1, far: 100)
check("D9 the same view volume as the Performance theme's camera", theirs.planes == ours.planes)
let viewEye = SIMD3<Float>(0, 0, 10)
let viewForward = SIMD3<Float>(0, 0, -1)
let volume: GraphPerfFrustum = SpaceDepth.frustum(eye: viewEye, forward: viewForward,
                                                   right: SIMD3<Float>(1, 0, 0), up: SIMD3<Float>(0, 1, 0),
                                                   fovY: 55 * Float.pi / 180, width: 390, height: 844,
                                                   near: 0.01, far: 1000)
check("D9 a body in front is in view", SpaceDepth.inView(volume, centre: SIMD3<Float>(0, 0, 0), radius: 0.2, reach: 4))
check("D9 a body behind the camera is not", !SpaceDepth.inView(volume, centre: SIMD3<Float>(0, 0, 14),
                                                                radius: 0.2, reach: 4))
check("D9 a body far off to the side is not", !SpaceDepth.inView(volume, centre: SIMD3<Float>(30, 0, 0),
                                                                  radius: 0.2, reach: 4))
// half a screen off the left edge: its sphere is out, its tail is in
let edgeX: Float = 10 * tan(atan(tan(27.5 * Float.pi / 180) * 390 / 844))
let offLeft = SIMD3<Float>(-edgeX - 1, 0, 0)
check("D9 a comet just off screen whose tail reaches in is kept",
      !SpaceDepth.inView(volume, centre: offLeft, radius: 0.2, reach: 1)
      && SpaceDepth.inView(volume, centre: offLeft, radius: 0.2, reach: SpaceDepth.reachOfLook(styleCode: 3)))
check("D9 every look reaches past its body", (0...5).allSatisfy { SpaceDepth.reachOfLook(styleCode: $0) >= 3 })

// MARK: D10 the shaders' pieces

let spaceShaders: [(String, String)] = [
    ("link", GraphStyleShaders.link), ("bhDisk", GraphStyleShaders.bhDisk), ("bhRing", GraphStyleShaders.bhRing),
    ("sunBody", GraphStyleShaders.sunBody), ("sunCorona", GraphStyleShaders.sunCorona),
    ("rockBody", GraphStyleShaders.rockBody), ("moonBody", GraphStyleShaders.moonBody),
    ("halo", GraphStyleShaders.halo), ("gasBody", GraphStyleShaders.gasBody), ("gasRing", GraphStyleShaders.gasRing),
    ("pulsarCore", GraphStyleShaders.pulsarCore), ("pulsarGlow", GraphStyleShaders.pulsarGlow),
    ("pulsarBeam", GraphStyleShaders.pulsarBeam), ("cometNucleus", GraphStyleShaders.cometNucleus),
    ("cometComa", GraphStyleShaders.cometComa), ("cometTail", GraphStyleShaders.cometTail),
    ("cometDust", GraphStyleShaders.cometDust), ("orbit", GraphStyleShaders.orbit), ("well", GraphStyleShaders.well)
]
let unfaded: [String] = spaceShaders.filter { !$0.1.contains("float4 rpFade;") || !$0.1.contains("rp_dfF") }.map { $0.0 }
check("D10 every Space shader fades by depth", unfaded.isEmpty, "\(unfaded)")
let bodies: [String] = ["sunBody", "rockBody", "moonBody", "gasBody", "pulsarCore", "cometNucleus"]
let glows: [String] = spaceShaders.map { $0.0 }.filter { !bodies.contains($0) }
let c: SIMD3<Float> = GraphStyleShaders.fadeLinear
let colourText: String = "float3(" + [c.x, c.y, c.z].map { GraphStyleShaders.literal($0) }.joined(separator: ", ") + ")"
let fadeMix: String = "rp_col = mix(rp_col, " + colourText + ", rp_dfF);"
let badBodies: [String] = spaceShaders.filter { bodies.contains($0.0) && !$0.1.contains(fadeMix) }.map { $0.0 }
let badGlows: [String] = spaceShaders.filter {
    glows.contains($0.0) && (!$0.1.contains("rp_col = rp_col * (1.0 - rp_dfF);") || $0.1.contains(fadeMix))
}.map { $0.0 }
check("D10 a solid body dissolves into the sky's colour; additive light only towards nothing",
      badBodies.isEmpty && badGlows.isEmpty, "\(badBodies) \(badGlows)")
check("D10 the colour faded towards is the sky's near-black, in linear light",
      GraphStyleShaders.fadedBodyEnd.contains(colourText), colourText)
check("D10 a link fades by each fragment's depth, a body by its centre's",
      GraphStyleShaders.link.contains("float rp_dfZ = -_surface.position.z;")
      && GraphStyleShaders.fadedGlowEnd.contains("float rp_dfZ = -scn_node.modelViewTransform[3].z;"))
let detailed: [String] = ["bhDisk", "bhRing", "sunBody", "rockBody", "moonBody", "gasBody"]
let undetailed: [String] = spaceShaders.filter {
    detailed.contains($0.0) && !($0.1.contains("float rpFocal;") && $0.1.contains("rp_dl"))
}.map { $0.0 }
let stepped: [String] = spaceShaders.filter { $0.1.contains("rpDetail > 0.5") }.map { $0.0 }
check("D10 granulation, lensing, clouds, ring shadows and city lights step down by size, with no switch left",
      undetailed.isEmpty && stepped.isEmpty, "\(undetailed) \(stepped)")
check("D10 the shaders' detail band is SpaceDepth's",
      GraphStyleShaders.detail.contains("smoothstep(" + GraphStyleShaders.literal(GraphStyleShaders.detailLow) + ", "
                                        + GraphStyleShaders.literal(GraphStyleShaders.detailHigh) + ", rp_lodPx)"))
check("D10 the city lights and the ring's shadow go with size alone, so Smooth keeps them up close",
      GraphStyleShaders.rockBody.contains("(1.0 - 0.85 * rp_cloud) * rp_lod;")
      && GraphStyleShaders.gasBody.contains("* rpRinged * rp_lod;"))

// MARK: D11 the fade colour against the sky

// GraphSpace.skyColour: the poles (darkest) and the band's middle (brightest base, sRGB)
let pole = SIMD3<Float>(0.004, 0.006, 0.022)
let band0 = SIMD3<Float>(0.018, 0.032, 0.095)
let fadeColour: SIMD3<Float> = GraphStyleShaders.fadeSRGB
let between: Bool = (0..<3).allSatisfy { fadeColour[$0] >= pole[$0] && fadeColour[$0] <= band0[$0] }
let gap: Float = max((fadeColour - pole).max(), (band0 - fadeColour).max())
check("D11 between the sky's darkest and its band, close to both (no grey veil, no dark hole)",
      between && gap < 0.05, "\(gap)")
check("D11 the sky's blue, not a grey", fadeColour.z > fadeColour.y * 2 && fadeColour.y > fadeColour.x)

// MARK: D12 the noise octaves morph

var exact = true
var ends = true
var morphSmooth = true
for k in 0..<50 {
    let p = SIMD3<Float>(Float(k) * 0.37, Float(k) * 0.11 + 2, 5 - Float(k) * 0.23)
    if GraphShaderKit.fbm(p, octaves: 5, from: 3, fine: 1) != GraphShaderKit.fbm(p, octaves: 5) { exact = false }
    if !near(GraphShaderKit.fbm(p, octaves: 5, from: 3, fine: 0), GraphShaderKit.fbm(p, octaves: 3)) { ends = false }
    var previous: Float = GraphShaderKit.fbm(p, octaves: 5, from: 3, fine: 0)
    for j in 1...100 {
        let v: Float = GraphShaderKit.fbm(p, octaves: 5, from: 3, fine: Float(j) / 100)
        if abs(v - previous) > 0.01 { morphSmooth = false }
        previous = v
    }
}
check("D12 at full weight the octaves are the old ones to the bit (the look up close is unchanged)", exact)
check("D12 at none they are the simple path's, and between they morph with no step", ends && morphSmooth)
check("D12 the shaders use the morphing octaves", GraphStyleShaders.gasBody.contains("float rp_tb_k = rp_tb_o < 3 ? 1.0 : rp_dl;")
      && GraphStyleShaders.moonBody.contains("float rp_mh_k = rp_mh_o < 2 ? 1.0 : rp_dl;"))

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED")
exit(failures.isEmpty ? 0 : 1)
