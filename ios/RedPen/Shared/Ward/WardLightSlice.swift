import Foundation

// The Ward relief's soft lights, drawn once. A face's drop and inner shadows
// (and a pressable face's softening) are blurs that SwiftUI would redraw
// every frame home's parts change scale, which held the opening's hand-off
// up (plan.md, the launch hitch). The faces keep their drawing; it is
// rendered into an image once per style and that image is shown instead.
//
// This file is the maths of that, Foundation only so Linux tests it
// (WardLightSliceTests): which shapes the images cover, how far a face's
// lights reach beyond its shape, how an image is cut into a stretchable
// slice so one image serves every size of a rounded rectangle, and what the
// images are keyed by. WardLightImages draws and shows them.

/// The shapes whose lights can be drawn once. Anything else (an annulus, a
/// shape inset by hand, a non-colour fill) keeps the live drawing.
enum WardFaceShape: Equatable, Sendable {
    case rounded(radius: Double, continuous: Bool)
    case capsule(continuous: Bool)
    case circle
}

/// How a face is lit, which sets what its image holds.
enum WardLightLook: Int, Hashable, Sendable {
    /// Highlight and shade dropped outside the shape.
    case raised
    /// The same two cast inside it.
    case inset
    /// A pressable face at rest (depth 0): the shade dropped outside, the
    /// face and shade softened together.
    case press
}

/// One image's layout: what shape is drawn into it, how far it reaches
/// beyond the shape, and, where it is cut to stretch, the cap each side
/// keeps. Points throughout; every length is a whole number of points (or of
/// pixels, on an axis that is not stretched) so the caps fall on the pixel
/// grid at any display scale.
struct WardLightPlan: Equatable, Sendable {
    /// The shape as drawn into the image (a rounded rectangle's radius is
    /// the one it really has, clamped to the size).
    var shape: WardFaceShape
    /// How far the image extends beyond the shape on every side.
    var pad: Int
    /// The size of the shape drawn into the image.
    var width: Double
    var height: Double
    /// Whether the image is cut to stretch along each axis.
    var stretchX: Bool
    var stretchY: Bool
    /// The cap kept at each end of a stretched axis (image points, from the
    /// image's edge); 0 where the axis is not stretched.
    var capX: Int
    var capY: Int
    /// An axis that is not stretched is keyed by its size, in pixels; 0 where
    /// it is stretched.
    var keyWidth: Int
    var keyHeight: Int

    /// The image's size: the shape and the room its lights reach.
    var imageWidth: Double { width + Double(2 * pad) }
    var imageHeight: Double { height + Double(2 * pad) }

    /// The size the image is shown at for a shape of this size: the shape
    /// and its reach on every side.
    static func shown(width: Double, height: Double, pad: Int) -> (width: Double, height: Double) {
        (width + Double(2 * pad), height + Double(2 * pad))
    }
}

/// Everything that changes an image, and nothing that does not: a stretched
/// axis is left out, since one image serves every size along it.
struct WardLightKey: Hashable, Sendable {
    var shape: Int
    /// A rounded rectangle's radius, in hundredths of a point; 0 otherwise.
    var radius: Int
    var keyWidth: Int
    var keyHeight: Int
    var look: WardLightLook
    var lift: Int
    var control: Bool
    var dark: Bool
    var strong: Bool
    /// The fill's colour as 8-bit RGBA (WardLightSlice.pack).
    var fill: UInt32
    /// The display scale, in hundredths.
    var scale: Int
}

enum WardLightSlice {
    /// A continuous corner curves over this many radii along each edge
    /// (a circular one over one); the cut keeps the whole curve in its caps.
    static let continuousCurve = 1.53
    /// How far a shadow's soft edge reaches, in blur radii. SwiftUI's shadow
    /// radius is twice its Gaussian's deviation, so 1.5 radii is three
    /// deviations, where less than 0.2% of a light's strength is left.
    static let shadowSpread = 1.5
    /// How far a blur softens, in blur radii (its radius is the deviation).
    static let blurSpread = 3.0
    /// The width of the stretched middle of a slice, in points.
    static let core = 2.0
    /// The display scales the images are made for.
    static let scaleRange: ClosedRange<Double> = 1...4

    // MARK: reach

    /// How far one light reaches beyond the shape: its offset and the
    /// spread of its soft edge.
    static func reach(of light: WardReliefLight) -> Double {
        light.lit ? max(abs(light.x), abs(light.y)) + shadowSpread * light.radius : 0
    }

    /// Whole points a raised or inset face's lights reach beyond its shape,
    /// with one to spare.
    static func reach(_ spec: WardReliefSpec) -> Int {
        Int(max(reach(of: spec.highlight), reach(of: spec.shade)).rounded(.up)) + 1
    }

    /// The same for a pressable face at rest: the shade, and the softening
    /// of the whole group by `blur`.
    static func reach(_ spec: WardPressSpec) -> Int {
        Int((max(reach(of: spec.outerShade), reach(of: spec.innerShade), reach(of: spec.innerHighlight))
             + blurSpread * spec.blur).rounded(.up)) + 1
    }

    // MARK: pixels

    /// A length on the pixel grid.
    static func quantised(_ points: Double, scale: Double) -> Double {
        (points * scale).rounded() / scale
    }

    static func pixels(_ points: Double, scale: Double) -> Int {
        Int((points * scale).rounded())
    }

    /// An 8-bit RGBA colour as one number: what a fill is keyed by.
    static func pack(red: Double, green: Double, blue: Double, alpha: Double) -> UInt32 {
        func byte(_ x: Double) -> UInt32 { UInt32((min(1, max(0, x)) * 255).rounded()) }
        return byte(red) << 24 | byte(green) << 16 | byte(blue) << 8 | byte(alpha)
    }

    // MARK: the cut

    /// The layout of the image for a shape of this size, or nil when the
    /// shape is not covered (a circle in a box that is not square, or a size
    /// that is not a size). `reach` is how far the lights fall (see
    /// `reach(_:)`), `inner` whether they all fall inside the shape, which
    /// then needs no room around it.
    ///
    /// A rounded rectangle is cut like a nine-slice: its four corners, and
    /// the strips between them stretched. That is only the same picture as
    /// the live one where the strip is farther from the corners than their
    /// curve, the lights' offset and the spread of their soft edge, so each
    /// cap is the pad, the curve and the reach, and a side shorter than two
    /// caps and a core is not cut: it is drawn at its own size and keyed by
    /// it. A capsule is the same with its radius half its short side, a
    /// circle is drawn at its own size.
    static func plan(_ shape: WardFaceShape, width: Double, height: Double, reach: Int, inner: Bool,
                     scale: Double) -> WardLightPlan? {
        guard width.isFinite, height.isFinite, width > 0, height > 0, scale.isFinite,
              scaleRange.contains(scale), reach >= 0 else { return nil }
        let pad = inner ? 0 : reach
        let qw = quantised(width, scale: scale), qh = quantised(height, scale: scale)
        guard qw > 0, qh > 0 else { return nil }

        let radius: Double, curve: Double
        var drawn = shape
        switch shape {
        case .circle:
            // a circle fills the shorter side; a box that is not square is
            // left to the live drawing
            guard abs(width - height) <= 1 / scale else { return nil }
            let d = min(qw, qh)
            return WardLightPlan(shape: .circle, pad: pad, width: d, height: d,
                                 stretchX: false, stretchY: false, capX: 0, capY: 0,
                                 keyWidth: pixels(d, scale: scale), keyHeight: pixels(d, scale: scale))
        case let .rounded(r, continuous):
            guard r.isFinite, r >= 0 else { return nil }
            radius = (min(r, width / 2, height / 2) * 100).rounded() / 100
            curve = (continuous ? radius * continuousCurve : radius).rounded(.up)
            drawn = .rounded(radius: radius, continuous: continuous)
        case let .capsule(continuous):
            radius = min(width, height) / 2
            curve = (continuous ? radius * continuousCurve : radius).rounded(.up)
        }

        // each cap: the pad, the curve and the reach; the core between them
        let cap = pad + Int(curve) + reach
        let least = Double(2 * (Int(curve) + reach)) + core
        let stretchX = width >= least, stretchY = height >= least
        let w = stretchX ? least : qw, h = stretchY ? least : qh
        return WardLightPlan(shape: drawn, pad: pad, width: w, height: h,
                             stretchX: stretchX, stretchY: stretchY,
                             capX: stretchX ? cap : 0, capY: stretchY ? cap : 0,
                             keyWidth: stretchX ? 0 : pixels(w, scale: scale),
                             keyHeight: stretchY ? 0 : pixels(h, scale: scale))
    }

    /// The key an image is kept under.
    static func key(_ plan: WardLightPlan, look: WardLightLook, lift: WardLift, control: Bool,
                    dark: Bool, strong: Bool, fill: UInt32, scale: Double) -> WardLightKey {
        let kind: Int, radius: Int
        switch plan.shape {
        case let .rounded(r, continuous): kind = continuous ? 1 : 0; radius = Int((r * 100).rounded())
        case let .capsule(continuous): kind = continuous ? 3 : 2; radius = 0
        case .circle: kind = 4; radius = 0
        }
        return WardLightKey(shape: kind, radius: radius, keyWidth: plan.keyWidth, keyHeight: plan.keyHeight,
                            look: look, lift: lift.rawValue, control: control, dark: dark, strong: strong,
                            fill: fill, scale: Int((scale * 100).rounded()))
    }

    /// Which source column or row of a cut image fills column or row `i` of
    /// the image shown at `shown` along an axis whose cut keeps `cap` at each
    /// end of an image `source` long: the caps carry over as they are, the
    /// middle repeats its first point's worth. For checking that stretching
    /// reproduces drawing the shape at the larger size.
    static func sourceIndex(_ i: Int, shown: Int, source: Int, cap: Int) -> Int {
        if i < cap { return i }
        if i >= shown - cap { return source - (shown - i) }
        return cap
    }
}
