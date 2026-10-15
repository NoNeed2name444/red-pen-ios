// The million map's scripted proof tour (D5; plan 4f's before and after),
// driven by GraphPerfMapView under the launch argument -graphPreviewPerfTour.
//
// This file holds the interface only, so the app builds without the tour:
// the proof harness (design/perf-proof) replaces it with the tour itself.
//
// Foundation only, free of Stethoscore types.
import Foundation

/// What the tour knows about the map (filled by the map view).
nonisolated struct GraphPerfTourMap: Sendable {
    var centre: SIMD3<Float>
    var radius: Float
    /// The view's size (points).
    var width: Float
    var height: Float
    /// The whole map's framing.
    var whole: GraphPerfCamera
    /// A well-linked note near the front, to fly to and choose.
    var hub: Int?
    var hubPosition: SIMD3<Float>?
}

/// What the tour asks of one frame.
nonisolated struct GraphPerfTourStep: Sendable, Equatable {
    /// The pose for this frame.
    var camera: GraphPerfCamera
    /// The readout shows "tour: <phase>".
    var phase: String
    /// A Graphics level to force (nil keeps the user's).
    var tier: GraphPerfTier? = nil
    /// The depth fade on; off gives the "before" numbers.
    var fade: Bool = true
    /// A body to choose (the scene's body index).
    var select: Int? = nil
    /// This frame counts towards `phase`'s numbers.
    var measuring: Bool = false
}

/// One drawn frame's numbers, from the renderer.
nonisolated struct GraphPerfFrameReport: Sendable, Equatable {
    /// Seconds since the frame before.
    var interval: Double
    /// The CPU's own frame time (seconds).
    var cpu: Double
    /// The GPU's (seconds; a wall-clock estimate on the simulator).
    var gpu: Double
    var drawCalls: Int
    /// Bodies, glows, bundles and the chosen neighbourhood drawn.
    var instances: Int
    /// MTLDevice.currentAllocatedSize (bytes).
    var gpuMemory: Int
    /// Cells still moving to their shell's detail.
    var ramping: Int
    /// Cells in the front, middle and back shells.
    var shells: SIMD3<Int32>
}

/// The tour: absent from this build (step gives nil, so the map is left alone).
nonisolated final class GraphPerfTour {
    init(map: GraphPerfTourMap) {}

    /// The step at `seconds` into the tour; nil when it is done.
    func step(at seconds: Double) -> GraphPerfTourStep? { nil }

    func record(_ report: GraphPerfFrameReport, step: GraphPerfTourStep) {}

    /// One line per phase, for the readout's accessibility value.
    var summary: String { "" }
}
