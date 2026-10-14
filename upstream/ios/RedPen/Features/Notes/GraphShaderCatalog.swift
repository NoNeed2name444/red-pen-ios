import Foundation

// MARK: - Every shader modifier of the 3D map, in one list
//
// SceneKit compiles a shader modifier only on the device, at run time, and a
// broken one fails quietly (the probes fall back to plain looks). This list
// lets them be checked before that: tools/shader_check.py compiles each one
// against a stand-in for Metal and SceneKit's entry points, and the shaders
// suite (Tests/ShaderSourceTests) reads each one for the mistakes a
// compiler would catch - an undeclared or twice-declared name, an argument
// used but not declared, unbalanced brackets, a GLSL spelling.
//
// A new shader goes in this list as well as in its probe. Foundation only.

nonisolated struct GraphShaderItem: Sendable {
    let name: String
    /// SceneKit's entry point: "surface" or "geometry".
    let entry: String
    let source: String
}

nonisolated enum GraphShaderCatalog {
    static var all: [GraphShaderItem] {
        space + neurons
    }

    /// Geometry and surface modifiers that share one material: SceneKit
    /// fails such a material if both declare the same argument.
    static let pairs: [(String, String)] = [
        ("neuronWobble", "neuronSoma"),
        ("neuronSway", "neuronArbor"),
        ("neuronMembraneSway", "neuronMembrane")
    ]

    /// The Space theme's node styles and links (GraphSpaceShaders.swift).
    static var space: [GraphShaderItem] {
        let surfaces: [(String, String)] = [
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
        return surfaces.map { GraphShaderItem(name: $0.0, entry: "surface", source: $0.1) }
    }

    /// The Neurons theme (GraphNeuronShaders.swift).
    static var neurons: [GraphShaderItem] {
        [
            GraphShaderItem(name: "neuronSoma", entry: "surface", source: NeuronShaders.soma),
            GraphShaderItem(name: "neuronWobble", entry: "geometry", source: NeuronShaders.wobble),
            GraphShaderItem(name: "neuronArbor", entry: "surface", source: NeuronShaders.arbor),
            GraphShaderItem(name: "neuronSway", entry: "geometry", source: NeuronShaders.sway),
            GraphShaderItem(name: "neuronMembrane", entry: "surface", source: NeuronShaders.membrane),
            GraphShaderItem(name: "neuronMembraneSway", entry: "geometry", source: NeuronShaders.membraneSway),
            GraphShaderItem(name: "neuronHalo", entry: "surface", source: NeuronShaders.halo),
            GraphShaderItem(name: "neuronArrival", entry: "surface", source: NeuronShaders.arrival),
            GraphShaderItem(name: "neuronAxon", entry: "surface", source: NeuronShaders.axon),
            GraphShaderItem(name: "neuronBridge", entry: "surface", source: NeuronShaders.bridge)
        ]
    }
}
