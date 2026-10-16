#if canImport(SwiftUI)
import SwiftUI
import UIKit
import QuartzCore

// The Ward relief's soft lights, drawn once (the maths: WardLightSlice).
//
// A face's drop and inner shadows, and a pressable face's softening, are
// blurs. Left live, SwiftUI redraws every one of them each frame home's
// parts change scale in the launch hand-off, which held the opening up for
// over 100 ms (plan.md, the launch hitch). So a face whose lights are at
// rest draws itself with the very same SwiftUI code into an image, once per
// style, and shows that: a rounded rectangle as a stretchable slice, so one
// image serves every size, a capsule keyed by its height, a circle by its
// diameter, a readiness ring's groove by its box. What the images do not
// cover keeps the live drawing: a fill that is not a colour, a shape that is
// not a rounded rectangle, capsule, circle or ring, a press in motion or
// held, and any face whose style is not ready while the opening hands off
// (see `image`). A recorded opening counts every face and how it was drawn
// (WardReliefCensus, WardFaceToken), so a fallback is never silent.

/// The outline of a covered shape, so the one drawing code can be run on it:
/// it delegates to SwiftUI's own RoundedRectangle, Capsule and Circle (and
/// WardAnnulus), so its path (and its inset) is theirs.
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
        case let .annulus(width):
            return WardAnnulus(width: CGFloat(width)).inset(by: amount).path(in: rect)
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
        } else if let ring = shape as? WardAnnulus, ring.insetAmount == 0 {
            self = .annulus(width: Double(ring.width))
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

/// A relief face's place in the census (WardReliefCensus): held as the
/// face's @State, so it lives as long as the face does and is dropped from
/// the count when the face goes. Inert (no number, nothing noted) outside a
/// recorded opening.
final class WardFaceToken {
    private let id: UInt64

    init() {
        id = LaunchStage.recording ? WardReliefCensus.shared.newFace() : 0
    }

    deinit {
        if id != 0 { WardReliefCensus.shared.forget(id) }
    }

    /// How the face was drawn this time.
    func note(_ path: WardReliefPath) {
        if id != 0 { WardReliefCensus.shared.note(id, path) }
    }
}

/// An image to be made: what it is kept under, and how to draw it.
struct WardLightRequest {
    var key: WardLightKey
    var make: @MainActor () -> UIImage?
}

/// What asking for an image gives.
enum WardLightOutcome {
    case image(UIImage)
    /// Asked for inside the hand-off: made once it is over.
    case late
    /// Could not be drawn (yet): the face draws live.
    case failed
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
    /// Styles that could not be drawn `attemptsAllowed` times: left to the
    /// live drawing for good.
    @ObservationIgnored private var failed: Set<WardLightKey> = []
    @ObservationIgnored private var attempts: [WardLightKey: Int] = [:]
    @ObservationIgnored private var catchUpScheduled = false
    /// Styles asked for during the hand-off, made once it is over.
    @ObservationIgnored private var late: [WardLightKey: WardLightRequest] = [:]
    /// The other colour scheme's styles for what is on screen, made at rest
    /// so a light/dark switch finds its images ready and swaps them in the
    /// same frame (made on the spot, still in that frame, if it does not).
    @ObservationIgnored private var spare: [WardLightKey: WardLightRequest] = [:]
    @ObservationIgnored private var spareScheduled = false

    /// More than this many images are dropped and made again as needed.
    static let most = 256
    /// A style that fails to draw is tried again (outside any drawing of a
    /// face) this many times in all before it is left live.
    static let attemptsAllowed = 3

    /// The image for a style, or why the face should draw live.
    func image(_ request: WardLightRequest, other: () -> WardLightRequest?) -> WardLightOutcome {
        _ = revision
        if let hit = images[request.key] {
            return .image(hit)
        }
        if failed.contains(request.key) { return .failed }
        if LaunchStage.shared.handingOff {
            // never inside the hand-off window: made once it is over
            late[request.key] = request
            LaunchStage.shared.mark("relief-late", once: true)
            return .late
        }
        guard let made = store(request) else {
            // tried again on the next turn of the main queue, not here
            if !failed.contains(request.key) {
                late[request.key] = request
                scheduleCatchUp()
            }
            return .failed
        }
        if let other = other(), images[other.key] == nil, !failed.contains(other.key) {
            spare[other.key] = other
            scheduleSpare()
        }
        return .image(made)
    }

    /// The hand-off is over (LaunchStage): make what it asked for. What
    /// fails again stays asked for until its attempts are used up.
    func catchUp() {
        var any = false
        var again: [WardLightKey: WardLightRequest] = [:]
        for request in late.values where images[request.key] == nil && !failed.contains(request.key) {
            if store(request) != nil {
                any = true
            } else if !failed.contains(request.key) {
                again[request.key] = request
            }
        }
        late = again
        if any { revision += 1 }
        if !again.isEmpty { scheduleCatchUp() }
        scheduleSpare()
    }

    private func scheduleCatchUp() {
        guard !catchUpScheduled else { return }
        catchUpScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.catchUpScheduled = false
                // inside the hand-off, LaunchStage calls catchUp when it is over
                if !LaunchStage.shared.handingOff { self.catchUp() }
            }
        }
    }

    private func store(_ request: WardLightRequest) -> UIImage? {
        if images.count >= Self.most { images.removeAll() }
        let start = CACurrentMediaTime()
        guard let image = LaunchStage.shared.measure("relief", { request.make() }) else {
            WardReliefCensus.shared.failure()
            let tried = (attempts[request.key] ?? 0) + 1
            attempts[request.key] = tried
            if tried >= Self.attemptsAllowed { failed.insert(request.key) }
            return nil
        }
        WardReliefCensus.shared.made(seconds: CACurrentMediaTime() - start)
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
        if let image = renderer.uiImage { return image }
        // the other way ImageRenderer hands a picture over
        return renderer.cgImage.map { UIImage(cgImage: $0, scale: CGFloat(scale), orientation: .up) }
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
    let face: WardFaceToken
    let draw: @MainActor (WardOutline, Bool) -> AnyView

    @Environment(\.displayScale) private var displayScale

    init(kind: WardFaceShape, look: WardLightLook, lift: WardLift, control: Bool, dark: Bool, strong: Bool,
         fill: Color, reach: Int, inner: Bool, live: Live, face: WardFaceToken,
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
        self.face = face
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
        switch outcome(in: size) {
        case let .lit(plan, image):
            if plan.centred {
                // a circle in a box that is not square: its own size, in the
                // middle, the lights reaching past the box as they do live
                Image(uiImage: image)
                    .resizable()
                    .frame(width: CGFloat(plan.imageWidth), height: CGFloat(plan.imageHeight))
                    .frame(width: CGFloat(plan.width), height: CGFloat(plan.height))
                    .contentShape(WardOutline(kind: plan.shape))
                    .position(x: size.width / 2, y: size.height / 2)
                    .accessibilityHidden(true)
            } else {
                // The image is the shape and the room its lights reach, drawn
                // over the shape's own frame: nothing it adds takes layout
                // room, or a tap.
                Image(uiImage: image)
                    .resizable(capInsets: EdgeInsets(top: CGFloat(plan.capY), leading: CGFloat(plan.capX),
                                                     bottom: CGFloat(plan.capY), trailing: CGFloat(plan.capX)),
                               resizingMode: .stretch)
                    .padding(-CGFloat(plan.pad))
                    .contentShape(WardOutline(kind: plan.shape))
                    .accessibilityHidden(true)
            }
        case .live:
            live
        }
    }

    private enum Outcome {
        case lit(WardLightPlan, UIImage)
        case live(WardLiveReason)
    }

    /// The image to show, or why the face draws live; noted for the census.
    private func outcome(in size: CGSize) -> Outcome {
        let result = resolve(in: size)
        switch result {
        case .lit: face.note(.cached)
        case let .live(reason): face.note(.live(reason))
        }
        return result
    }

    private func resolve(in size: CGSize) -> Outcome {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return .live(.empty)
        }
        let scale = Double(displayScale)
        guard let plan = WardLightSlice.plan(kind, width: Double(size.width), height: Double(size.height),
                                             reach: reach, inner: inner, scale: scale) else {
            return .live(.plan(width: Int(size.width.rounded()), height: Int(size.height.rounded())))
        }
        guard let request = makeRequest(plan, dark: dark, scale: scale) else { return .live(.fill) }
        switch WardLightImages.shared.image(request, other: { makeRequest(plan, dark: !dark, scale: scale) }) {
        case let .image(image): return .lit(plan, image)
        case .late: return .live(.late)
        case .failed: return .live(.failed)
        }
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
