import SceneKit
import UIKit
import Metal
import simd

// The node styles' shader modifiers live in GraphSpaceShaders.swift (pure
// Foundation, so tools/shader_check.py and the shaders suite check them on
// Linux); here, the check that they compile and draw on this device, and
// the safe values every argument starts from.

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

/// Tries each style shader off the main thread, in the same tiny offscreen
/// render GraphShaderProbe uses. Bodies must also see a real normal to
/// pass.
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
        ("cometDust", GraphStyleShaders.cometDust),
        ("orbit", GraphStyleShaders.orbit),
        ("well", GraphStyleShaders.well)
    ]

    /// Checked off the main thread before a build (Graph3DView), and kept
    /// once it can be trusted: every shader passed, or the app was in front
    /// for the whole check (GraphProbeMemo; Chat-me audit row 112).
    static var support: GraphStyleSupport { memo.check(visit: { GraphForeground.shared.visit }) }

    /// The answer the last check gave, without checking again: for the main
    /// thread, building with it.
    static var latest: GraphStyleSupport { memo.latest(visit: { GraphForeground.shared.visit }) }

    /// Whether the last answer was not kept (GraphProbeMemo.unsure).
    static var unsure: Bool { memo.unsure }

    private static let memo = GraphProbeMemo<GraphStyleSupport> {
        let found: GraphStyleSupport = GraphStyleProbe.run()
        return (found, found.passed.count == GraphStyleProbe.all.count)
    }

    private static func run() -> GraphStyleSupport {
        guard let device = MTLCreateSystemDefaultDevice() else { return .none }
        var passed = Set<String>()
        for (name, source) in all where passes(source, device: device) {
            passed.insert(name)
        }
        return GraphStyleSupport(passed: passed)
    }

    private static func passes(_ source: String, device: MTLDevice) -> Bool {
        renders([.surface: source], on: SCNPlane(width: 4, height: 4), device: device) { _ in }
    }

    /// Whether `modifiers` compile and draw on this device, on `geometry`
    /// (centred, 4 units across at most), with `setup` giving the material
    /// its arguments; `rpProbe` is set to 1 after it, so a working modifier
    /// paints the centre white. The themes check their shaders with it
    /// (GraphNeuronLook).
    static func renders(_ modifiers: [SCNShaderModifierEntryPoint: String], on geometry: SCNGeometry,
                        device: MTLDevice, setup: (SCNMaterial) -> Void) -> Bool {
        let scene = SCNScene()
        scene.background.contents = UIColor.black
        let material = SCNMaterial()
        material.lightingModel = .constant
        // the same tiny texture the real materials carry (blackImage): SceneKit
        // hands texture coordinates only to a property holding a texture, so
        // a `setup` that puts other contents on the diffuse is tested as is
        guard let black = blackImage else { return false }
        material.diffuse.contents = black
        material.isDoubleSided = true
        material.shaderModifiers = modifiers
        GraphStyleUniforms.defaults(material)
        setup(material)
        material.setValue(NSNumber(value: 1.0), forKey: "rpProbe")
        geometry.materials = [material]
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))
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

    /// A 4x4 black texture for the diffuse of every material whose shader
    /// modifier reads `_surface.diffuseTexcoord` but paints its own colour:
    /// with a plain colour there, SceneKit passes no texture coordinates and
    /// they read as 0 on a device. Made once, safe off the main thread.
    static let blackImage: CGImage? = blackTexture()

    /// blackImage as material contents (plain black if it could not be made).
    static var blackContents: Any {
        if let image = blackImage { return image }
        return UIColor.black
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
        // rpRinged: a gas giant has its ring (and its shadow) unless told not
        for name in ["rpDetail", "rpEnergy", "rpRinged"] {
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
