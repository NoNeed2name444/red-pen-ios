#if canImport(SwiftUI)
import SwiftUI
import UIKit

// The Ward relief's soft lights, drawn once (the maths: WardLightSlice).
//
// A face's drop and inner shadows, and a pressable face's softening, are
// blurs. Left live, SwiftUI redraws every one of them each frame home's
// parts change scale in the launch hand-off, which held the opening up for
// over 100 ms (plan.md, the launch hitch). So a face whose lights are at
// rest draws itself with the very same SwiftUI code into an image, once per
// style, and shows that: a rounded rectangle as a stretchable slice, so one
// image serves every size, a capsule keyed by its height, a circle by its
// diameter. What the images do not cover keeps the live drawing: a fill that
// is not a colour, a shape that is not a rounded rectangle, capsule or
// circle, a press in motion or held, and any face whose style is not ready
// while the opening hands off (see `image`).

/// The outline of a covered shape, so the one drawing code can be run on it:
/// it delegates to SwiftUI's own RoundedRectangle, Capsule and Circle, so its
/// path (and its inset) is theirs.
struct WardOutline: InsettableShape {
    var kind: WardFaceShape
    var amount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        switch kind {
        case let .rounded(radius, continuous):
            return RoundedRectangle(cornerRadius: CGFloat(radius), style: continuous ? .continuous : .circular)
                .inset(by: amount).path(in: rect)
        case let .capsule(continuous):
            return Capsule(style: continuous ? .continuous : .circular).inset(by: amount).path(in: rect)
        case .circle:
            return Circle().inset(by: amount).path(in: rect)
        }
    }

    func inset(by amount: CGFloat) -> WardOutline {
        var outline = self
        outline.amount += amount
        return outline
    }
}

extension WardFaceShape {
    /// The covered shape a SwiftUI shape is, or nil for any other.
    init?<S: Shape>(_ shape: S) {
        if let rounded = shape as? RoundedRectangle {
            guard rounded.cornerSize.width == rounded.cornerSize.height else { return nil }
            self = .rounded(radius: Double(rounded.cornerSize.width), continuous: rounded.style == .continuous)
        } else if let capsule = shape as? Capsule {
            self = .capsule(continuous: capsule.style == .continuous)
        } else if shape is Circle {
            self = .circle
        } else {
            return nil
        }
    }
}

extension Color {
    /// This colour as the scheme and contrast resolve it, packed for a key
    /// (WardLightSlice.pack); nil when it has no RGB.
    func wardPacked(dark: Bool, strong: Bool) -> UInt32? {
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: dark ? .dark : .light),
            UITraitCollection(accessibilityContrast: strong ? .high : .normal),
        ])
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return WardLightSlice.pack(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
    }
}

/// An image to be made: what it is kept under, and how to draw it.
struct WardLightRequest {
    var key: WardLightKey
    var make: @MainActor () -> UIImage?
}

/// The images, kept for the life of the app.
///
/// An image is made the first time a face with that style is drawn. Home is
/// laid out and drawn whole under the splash before the opening hands off
/// (LaunchStage.warm), so the styles it needs are made then. Nothing is made
/// from when the opening starts (LaunchStage.handingOff) until home is
/// still: a face whose style is not ready then keeps its live drawing, and
/// is given its image once the hand-off is over (`catchUp`). The same
/// picture either way, so nothing changes on screen.
@MainActor
@Observable
final class WardLightImages {
    static let shared = WardLightImages()

    /// Counts the images made late, so the faces that drew live pick theirs
    /// up. A face reads it when it draws.
    private(set) var revision = 0

    @ObservationIgnored private var images: [WardLightKey: UIImage] = [:]
    /// Styles that could not be drawn: left to the live drawing for good.
    @ObservationIgnored private var failed: Set<WardLightKey> = []
    /// Styles asked for during the hand-off, made once it is over.
    @ObservationIgnored private var late: [WardLightKey: WardLightRequest] = [:]
    /// The other colour scheme's styles for what is on screen, made at rest
    /// so a light/dark switch finds its images ready and swaps them in the
    /// same frame (made on the spot, still in that frame, if it does not).
    @ObservationIgnored private var spare: [WardLightKey: WardLightRequest] = [:]
    @ObservationIgnored private var spareScheduled = false

    /// More than this many images are dropped and made again as needed.
    static let most = 256

    /// The image for a style, or nil if the face should draw live.
    func image(_ request: WardLightRequest, other: () -> WardLightRequest?) -> UIImage? {
        _ = revision
        if let hit = images[request.key] {
            return hit
        }
        if failed.contains(request.key) { return nil }
        if LaunchStage.shared.handingOff {
            // never inside the hand-off window: made once it is over
            late[request.key] = request
            LaunchStage.shared.mark("relief-late", once: true)
            return nil
        }
        let made = store(request)
        if let other = other(), images[other.key] == nil, !failed.contains(other.key) {
            spare[other.key] = other
            scheduleSpare()
        }
        return made
    }

    /// The hand-off is over (LaunchStage): make what it asked for.
    func catchUp() {
        var any = false
        for request in late.values where images[request.key] == nil {
            if store(request) != nil { any = true }
        }
        late.removeAll()
        if any { revision += 1 }
        scheduleSpare()
    }

    private func store(_ request: WardLightRequest) -> UIImage? {
        if images.count >= Self.most { images.removeAll() }
        guard let image = LaunchStage.shared.measure("relief", { request.make() }) else {
            failed.insert(request.key)
            return nil
        }
        images[request.key] = image
        return image
    }

    /// A few of the other scheme's images per turn of the main queue, once
    /// the opening is over.
    private func scheduleSpare() {
        guard !spare.isEmpty, !spareScheduled else { return }
        spareScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated { self?.makeSpare() }
        }
    }

    private func makeSpare() {
        spareScheduled = false
        let stage = LaunchStage.shared
        // still opening: catchUp comes when it is over
        guard !stage.handingOff, !stage.warm, !stage.now.isFinite else { return }
        for request in spare.values.prefix(4) {
            spare[request.key] = nil
            if images[request.key] == nil { _ = store(request) }
        }
        scheduleSpare()
    }

    /// Draws `content`, the face's own drawing, into an image: the plan's
    /// shape and the room its lights reach, at the display's scale, in the
    /// colour scheme the key is for.
    static func render(_ content: AnyView, plan: WardLightPlan, dark: Bool, scale: Double) -> UIImage? {
        let renderer = ImageRenderer(content: content
            .frame(width: CGFloat(plan.width), height: CGFloat(plan.height))
            .padding(CGFloat(plan.pad))
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = CGFloat(scale)
        return renderer.uiImage
    }
}

/// A face whose lights are at rest, shown from its image. `live` is the
/// face's own drawing, used until the image is ready and wherever the images
/// do not cover; `draw` is the same drawing code on any outline, which the
/// image is made from.
struct WardLitFace<Live: View>: View {
    let kind: WardFaceShape
    let look: WardLightLook
    let lift: WardLift
    let control: Bool
    let dark: Bool
    let strong: Bool
    let fill: Color
    /// How far the lights reach (WardLightSlice.reach), and whether they all
    /// fall inside the shape.
    let reach: Int
    let inner: Bool
    let live: Live
    let draw: @MainActor (WardOutline, Bool) -> AnyView

    @Environment(\.displayScale) private var displayScale

    init(kind: WardFaceShape, look: WardLightLook, lift: WardLift, control: Bool, dark: Bool, strong: Bool,
         fill: Color, reach: Int, inner: Bool, live: Live,
         draw: @escaping @MainActor (WardOutline, Bool) -> AnyView) {
        self.kind = kind
        self.look = look
        self.lift = lift
        self.control = control
        self.dark = dark
        self.strong = strong
        self.fill = fill
        self.reach = reach
        self.inner = inner
        self.live = live
        self.draw = draw
    }

    var body: some View {
        // read here so a face that drew live is drawn again once its image
        // has been made
        let revision = WardLightImages.shared.revision
        GeometryReader { geometry in
            picture(in: geometry.size, revision: revision)
        }
    }

    @ViewBuilder
    private func picture(in size: CGSize, revision: Int) -> some View {
        if let lit = litImage(in: size) {
            // The image is the shape and the room its lights reach, drawn
            // over the shape's own frame: nothing it adds takes layout room,
            // or a tap.
            Image(uiImage: lit.image)
                .resizable(capInsets: EdgeInsets(top: CGFloat(lit.plan.capY), leading: CGFloat(lit.plan.capX),
                                                 bottom: CGFloat(lit.plan.capY), trailing: CGFloat(lit.plan.capX)),
                           resizingMode: .stretch)
                .padding(-CGFloat(lit.plan.pad))
                .contentShape(WardOutline(kind: lit.plan.shape))
                .accessibilityHidden(true)
        } else {
            live
        }
    }

    private func litImage(in size: CGSize) -> (plan: WardLightPlan, image: UIImage)? {
        let scale = Double(displayScale)
        guard let plan = WardLightSlice.plan(kind, width: Double(size.width), height: Double(size.height),
                                             reach: reach, inner: inner, scale: scale),
              let request = makeRequest(plan, dark: dark, scale: scale) else { return nil }
        guard let image = WardLightImages.shared.image(request, other: {
            makeRequest(plan, dark: !dark, scale: scale)
        }) else { return nil }
        return (plan, image)
    }

    private func makeRequest(_ plan: WardLightPlan, dark: Bool, scale: Double) -> WardLightRequest? {
        guard let packed = fill.wardPacked(dark: dark, strong: strong) else { return nil }
        let key = WardLightSlice.key(plan, look: look, lift: lift, control: control, dark: dark, strong: strong,
                                     fill: packed, scale: scale)
        let draw = draw
        return WardLightRequest(key: key) {
            WardLightImages.render(draw(WardOutline(kind: plan.shape), dark), plan: plan, dark: dark, scale: scale)
        }
    }
}
#endif
