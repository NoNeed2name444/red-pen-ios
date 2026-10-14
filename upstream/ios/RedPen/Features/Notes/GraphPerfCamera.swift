// The Performance map's camera: an orbit round a target (turn, zoom, pan),
// its view and projection matrices in Metal's conventions, projecting a
// point to the screen and a screen point back to a ray, the view frustum,
// framing a ball inside the part of the screen not under glass, and an
// eased glide from one pose to another.
//
// Foundation only (its own 4 x 4 matrix, no simd module), free of
// Stethoscore types, so the camera's maths are tested on Linux and the
// renderer only uploads what it gives.
import Foundation

/// A 4 x 4 matrix as four columns, as Metal's float4x4 lays it out.
nonisolated struct GraphPerfMatrix: Sendable, Equatable {
    var c0: SIMD4<Float>
    var c1: SIMD4<Float>
    var c2: SIMD4<Float>
    var c3: SIMD4<Float>

    static let identity = GraphPerfMatrix(c0: SIMD4(1, 0, 0, 0), c1: SIMD4(0, 1, 0, 0),
                                          c2: SIMD4(0, 0, 1, 0), c3: SIMD4(0, 0, 0, 1))

    func apply(_ v: SIMD4<Float>) -> SIMD4<Float> {
        c0 * v.x + c1 * v.y + c2 * v.z + c3 * v.w
    }

    static func * (a: GraphPerfMatrix, b: GraphPerfMatrix) -> GraphPerfMatrix {
        GraphPerfMatrix(c0: a.apply(b.c0), c1: a.apply(b.c1), c2: a.apply(b.c2), c3: a.apply(b.c3))
    }

    /// The sixteen floats, column by column (what the GPU is handed).
    var floats: [Float] {
        [c0.x, c0.y, c0.z, c0.w, c1.x, c1.y, c1.z, c1.w, c2.x, c2.y, c2.z, c2.w, c3.x, c3.y, c3.z, c3.w]
    }
}

/// A plane n.p = d with n pointing out of the volume it bounds.
nonisolated struct GraphPerfPlane: Sendable, Equatable {
    var normal: SIMD3<Float>
    var d: Float

    /// How far `p` is outside (positive) or inside (negative).
    func distance(_ p: SIMD3<Float>) -> Float { (normal * p).sum() - d }
}

/// The view volume: near, far and four sides.
nonisolated struct GraphPerfFrustum: Sendable {
    let planes: [GraphPerfPlane]

    /// Whether any of a ball reaches inside.
    func touches(centre: SIMD3<Float>, radius: Float) -> Bool {
        for p in planes where p.distance(centre) > radius { return false }
        return true
    }
}

nonisolated struct GraphPerfCamera: Sendable, Equatable {
    /// What it turns round and looks at.
    var target = SIMD3<Float>(0, 0, 0)
    /// How far the eye is from the target.
    var distance: Float = 10
    /// Turned round the world's up (y) axis, and tipped over it: positive
    /// pitch puts the eye above the target, looking down. Radians.
    var yaw: Float = 0
    var pitch: Float = 0
    /// The vertical field of view (radians).
    var fovY: Float = Float.pi / 3

    static let pitchLimit: Float = 1.48

    // MARK: - The pose

    /// From the target to the eye, unit length.
    var back: SIMD3<Float> {
        SIMD3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
    }

    var eye: SIMD3<Float> { target + back * distance }
    /// Where it looks (eye to target), unit length.
    var forward: SIMD3<Float> { -back }
    /// The screen's right and up in the world.
    var right: SIMD3<Float> { SIMD3(cos(yaw), 0, -sin(yaw)) }
    var up: SIMD3<Float> { Self.cross(right, forward) }

    // MARK: - Moving it

    /// A one-finger drag: turn round the target.
    mutating func orbit(yaw dYaw: Float, pitch dPitch: Float) {
        yaw = Self.wrap(yaw + dYaw)
        pitch = min(max(pitch + dPitch, -Self.pitchLimit), Self.pitchLimit)
    }

    /// A pinch: nearer (factor > 1) or further, within `limits`.
    mutating func zoom(by factor: Float, limits: ClosedRange<Float>) {
        guard factor > 0, factor.isFinite else { return }
        distance = min(max(distance / factor, limits.lowerBound), limits.upperBound)
    }

    /// A two-finger drag of `dx`, `dy` points: the target slides with the
    /// fingers, as far as the screen moves at the target's depth.
    mutating func pan(dx: Float, dy: Float, viewHeight: Float) {
        let perPoint: Float = distance / max(focal(viewHeight: viewHeight), 1e-3)
        target -= right * (dx * perPoint)
        target += up * (dy * perPoint)
    }

    // MARK: - Matrices (Metal: right-handed view space, clip z 0...1)

    /// The focal length in points for a view this tall: what a world unit at
    /// depth 1 measures on screen.
    func focal(viewHeight: Float) -> Float {
        viewHeight / 2 / tan(fovY / 2)
    }

    /// World to view: the eye at the origin looking down -z.
    func viewMatrix() -> GraphPerfMatrix {
        let r = right, u = up, f = forward, e = eye
        return GraphPerfMatrix(c0: SIMD4(r.x, u.x, -f.x, 0), c1: SIMD4(r.y, u.y, -f.y, 0),
                               c2: SIMD4(r.z, u.z, -f.z, 0),
                               c3: SIMD4(-(r * e).sum(), -(u * e).sum(), (f * e).sum(), 1))
    }

    /// View to clip, depth 0 at `near` and 1 at `far`.
    func projectionMatrix(aspect: Float, near: Float, far: Float) -> GraphPerfMatrix {
        let ys: Float = 1 / tan(fovY / 2)
        let xs: Float = ys / max(aspect, 1e-6)
        let zs: Float = far / (near - far)
        return GraphPerfMatrix(c0: SIMD4(xs, 0, 0, 0), c1: SIMD4(0, ys, 0, 0),
                               c2: SIMD4(0, 0, zs, -1), c3: SIMD4(0, 0, zs * near, 0))
    }

    /// Near and far planes that hold a map of `radius` round `centre`:
    /// near never under a hundredth of a body's spacing, far past its back.
    func depthRange(centre: SIMD3<Float>, radius: Float) -> (near: Float, far: Float) {
        let toCentre = ((centre - eye) * forward).sum()
        let far = max(toCentre + radius * 1.2, 1)
        let near = min(max(toCentre - radius * 1.2, 0.02), far * 0.5)
        return (near, far)
    }

    // MARK: - Screen and world

    /// A point's place on a `width` x `height` (points) screen, and its
    /// depth in front of the eye (negative behind it).
    func project(_ p: SIMD3<Float>, width: Float, height: Float) -> (x: Float, y: Float, depth: Float) {
        let v = p - eye
        let depth = (v * forward).sum()
        let f = focal(viewHeight: height)
        let w = abs(depth) > 1e-6 ? depth : 1e-6
        return (width / 2 + (v * right).sum() * f / w, height / 2 - (v * up).sum() * f / w, depth)
    }

    /// The ray from the eye through screen point (x, y): origin and unit direction.
    func ray(x: Float, y: Float, width: Float, height: Float) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let f = focal(viewHeight: height)
        let d = forward + right * ((x - width / 2) / f) + up * ((height / 2 - y) / f)
        return (eye, d / (d * d).sum().squareRoot())
    }

    /// The view volume for a screen this shape.
    func frustum(width: Float, height: Float, near: Float, far: Float) -> GraphPerfFrustum {
        let f = forward, r = right, u = up, e = eye
        let halfY = fovY / 2
        let halfX = atan(tan(halfY) * width / max(height, 1e-6))
        // each side's outward normal, tipped from the screen axis towards forward
        func side(_ axis: SIMD3<Float>, _ half: Float) -> GraphPerfPlane {
            let n = axis * cos(half) - f * sin(half)
            return GraphPerfPlane(normal: n, d: (n * e).sum())
        }
        let nearPlane = GraphPerfPlane(normal: -f, d: (-f * e).sum() - near)
        let farPlane = GraphPerfPlane(normal: f, d: (f * e).sum() + far)
        return GraphPerfFrustum(planes: [nearPlane, farPlane, side(r, halfX), side(-r, halfX), side(u, halfY),
                                         side(-u, halfY)])
    }

    // MARK: - Framing

    /// The camera that shows a ball of `radius` round `centre`, from this
    /// camera's direction, filling `fill` of the smaller side of a window:
    /// the part of a `width` x `height` screen inside the insets (points),
    /// with the ball's centre in the middle of that window.
    func framing(centre: SIMD3<Float>, radius: Float, width: Float, height: Float,
                 insets: (top: Float, left: Float, bottom: Float, right: Float) = (0, 0, 0, 0),
                 fill: Float = 0.9) -> GraphPerfCamera {
        var out = self
        let w = max(width - insets.left - insets.right, 1)
        let h = max(height - insets.top - insets.bottom, 1)
        let f = focal(viewHeight: height)
        let half = max(min(w, h) / 2 * fill, 1)
        // the ball's silhouette at distance D has half-width R f / sqrt(D^2 - R^2)
        let ratio = f / half
        out.distance = max(radius, 1e-3) * (1 + ratio * ratio).squareRoot()
        // shift the target so the centre lands in the window's middle
        let ox = (insets.left + w / 2) - width / 2
        let oy = height / 2 - (insets.top + h / 2)
        out.target = centre - (right * ox + up * oy) * (out.distance / f)
        return out
    }

    /// Part way (t, 0...1, eased) from `a` to `b`; the turn takes the short way round.
    static func glide(_ a: GraphPerfCamera, _ b: GraphPerfCamera, t: Float) -> GraphPerfCamera {
        if t <= 0 { return a }
        if t >= 1 { return b }
        let s = t * t * (3 - 2 * t)
        var out = b
        out.target = a.target + (b.target - a.target) * s
        // distance in log space: a zoom feels even all the way
        out.distance = exp(log(max(a.distance, 1e-6)) * (1 - s) + log(max(b.distance, 1e-6)) * s)
        out.yaw = wrap(a.yaw + wrap(b.yaw - a.yaw) * s)
        out.pitch = a.pitch + (b.pitch - a.pitch) * s
        out.fovY = a.fovY + (b.fovY - a.fovY) * s
        return out
    }

    // MARK: - Helpers

    /// An angle in -pi...pi.
    static func wrap(_ a: Float) -> Float {
        var x = a.truncatingRemainder(dividingBy: 2 * Float.pi)
        if x > Float.pi { x -= 2 * Float.pi }
        if x < -Float.pi { x += 2 * Float.pi }
        return x
    }

    static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
}
