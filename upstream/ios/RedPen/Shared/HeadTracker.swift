#if canImport(ARKit)
import ARKit
import UIKit

// MARK: - Head-coupled perspective (optional, OFF by default)
//
// Where the device has a TrueDepth camera, ARKit's face tracking says where
// the viewer's head is. Driving the pop-out from THAT instead of the tilt
// gives true off-axis parallax - the strongest "it sticks out of the device"
// illusion there is.
//
// Only the head's position is used, as a few numbers per frame. Nothing is
// recorded, stored or sent, no frame is ever kept, and the camera is off
// whenever the pop-out is not live or a voice / recording / drawing screen is
// showing (popOutFacePaused). Pull mode: no delegate, the display link reads
// `currentFrame` when it ticks.

@MainActor
final class HeadTracker: PopOutFaceSource {
    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    private let session = ARSession()
    private(set) var running = false
    private var baseline = SIMD2<Double>(0, 0)
    private var hasBaseline = false
    private var lastOrientation: UIInterfaceOrientation = .unknown

    func start() {
        guard !running, HeadTracker.isSupported else { return }
        let config = ARFaceTrackingConfiguration()
        config.maximumNumberOfTrackedFaces = 1
        config.isLightEstimationEnabled = false
        let formats = ARFaceTrackingConfiguration.supportedVideoFormats
        let smallest = formats.min { $0.imageResolution.width < $1.imageResolution.width }
        if let smallest { config.videoFormat = smallest }
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        running = true
        hasBaseline = false
    }

    func stop() {
        guard running else { return }
        session.pause()
        running = false
        hasBaseline = false
    }

    func headOffset(_ orientation: UIInterfaceOrientation, dt: Double) -> CGPoint? {
        guard running, let frame = session.currentFrame else { return nil }
        var tracked: ARFaceAnchor?
        for anchor in frame.anchors {
            if let face = anchor as? ARFaceAnchor, face.isTracked {
                tracked = face
                break
            }
        }
        guard let face = tracked else { return nil }
        // the face in the camera's own space (metres; the camera looks
        // along -z)
        let relative = simd_mul(simd_inverse(frame.camera.transform), face.transform)
        let p = relative.columns.3
        let depth: Double = max(0.15, Double(abs(p.z)))
        // camera axes to device axes (+x right, +y up). A starting guess:
        // PopOutTuning.faceAxes flips either axis after the on-device check.
        let axes: CGPoint = PopOutTuning.faceAxes
        let hx: Double = Double(axes.x) * Double(p.y) / depth
        let hy: Double = Double(axes.y) * Double(p.x) / depth
        let screen: SIMD2<Double> = PopOutMotion.screenVector(SIMD2<Double>(hx, hy), orientation)

        if orientation != lastOrientation {
            lastOrientation = orientation
            hasBaseline = false
        }
        if !hasBaseline {
            baseline = screen
            hasBaseline = true
        }
        // a slow baseline absorbs the camera sitting off the screen's centre
        let k: Double = 1 - exp(-dt / 6.0)
        baseline += (screen - baseline) * k
        let raw: SIMD2<Double> = (screen - baseline) / 0.12
        let x: Double = min(1, max(-1, raw.x))
        let y: Double = min(1, max(-1, raw.y))
        return CGPoint(x: x, y: y)
    }
}
#endif
