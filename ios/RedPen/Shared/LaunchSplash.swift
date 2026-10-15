import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

/// The opening: the owner's stethoscope on home's own ECG paper
/// (LaunchPaper), exactly as the system launch screen drew it, and then,
/// once the home screen's first real frame is up (the library read), one
/// heartbeat:
///
/// 1. the chest piece beats, lub then dub, and the heartbeat is heard
///    (Assets.xcassets/Heartbeat, if the app's sound is on);
/// 2. one ECG complex is drawn under the mark (LaunchArt.trace), out from
///    the middle of a baseline, its R peak as the lub is heard and its T
///    wave ending as the dub is;
/// 3. the hand-off, straight into home with no wipe: the splash's paper
///    gives way to home's own (the same paper, with nothing of home drawn
///    on it yet), the ECG travels up and shrinks into the squiggle beside
///    the title, the stethoscope glides up and shrinks away into the title
///    as its letters settle in, and home's parts spring into place in one
///    wave up the screen behind the ECG (LaunchStage).
///
/// Nothing fades: everything is position, scale, stroke trims, a path
/// morph and (when the app's light or dark differs from the phone's) a
/// colour shift of the base.
/// The timings are LaunchOpening's, tested on Linux; here they are sampled
/// into Core Animation keyframes, so the animation runs in the render server
/// and a busy main thread cannot stall it. The sound and the drawing are
/// started from one host-clock moment (`AVAudioPlayer.play(atTime:)` on the
/// audio clock, `beginTime` on the same host clock the display link reports),
/// with the drawing held back by the output's latency when the sound is
/// really started, so on a Bluetooth headset what is heard and what is drawn
/// still meet. Muted or with the sound off, the ECG draws at the same times.
///
/// The Xcode build has a real launch screen (AppResources/LaunchScreen.storyboard:
/// the same two pictures, laid the same way), so this carries that picture
/// on without a jump. The Swift Playgrounds package has none, so there this
/// *is* the launch screen.
///
/// It never holds anything up: the app is running beneath it from the first
/// frame, it ignores touches, it is hidden from VoiceOver, and it goes as
/// soon as home is still (its ECG is the title's squiggle by then). If the library takes longer than
/// `longestHold`, it opens anyway, onto the screen saying the library is
/// opening (LibraryLoadingView): with no title to go to, the splash drops
/// away down the screen instead.
struct LaunchSplash: View {
    /// The longest it waits for the library to be read: a still picture held
    /// any longer looks hung.
    static let longestHold: Double = 2

    /// How long the base colour takes to move to the app's, when it has to.
    static let shift: Double = 0.25

    /// Settings: whether the opening's heartbeat is heard (on by default).
    /// The ECG draws either way.
    static let soundKey = "launch.heartbeat.sound"
    static var soundOn: Bool { UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true }

    /// Whether the phone itself (not the app's setting) is in dark mode: what
    /// the system launch screen, LaunchBackground and LaunchLogo, was drawn
    /// in. The screen's traits are the phone's; a window's can be the app's.
    @MainActor static var phoneIsDark: Bool {
        let screen = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
        return screen?.traitCollection.userInterfaceStyle == .dark
    }

    /// The Ward base as the system launch screen drew it: the very colour
    /// the launch screen names (LaunchBackground, as the asset compiler
    /// stored it), so the two are the same pixels, not a value a rounding
    /// apart (run 38595937165: one chroma step off in both modes, with the
    /// colour written out). The written-out value is only the fallback.
    static func baseCG(dark: Bool) -> CGColor {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        if let named = UIColor(named: "LaunchBackground", in: nil, compatibleWith: traits) {
            return named.resolvedColor(with: traits).cgColor
        }
        let (r, g, b) = WardPalette.rgb(WardPalette.hex(.background, dark: dark))
        return UIColor(red: r, green: g, blue: b, alpha: 1).cgColor
    }

    /// Once per process: a second window on iPad, or a scene rebuilt after a
    /// memory warning, is not a launch.
    @MainActor fileprivate static var shown = false

    /// No splash for CI screenshots, the graph design preview, or a launch
    /// that asks for none (`-noSplash`). `-uiPreviewSplash` keeps it on a
    /// preview launch, to record the opening (`-uiPreviewSplashHold` with it
    /// holds its first frame, to be compared with the launch screen).
    @MainActor static var wanted: Bool {
        let args = ProcessInfo.processInfo.arguments
        if !shown && args.contains("-uiPreviewSplash") { return true }
        return !shown
            && PreviewLaunch.screen == nil
            && !GraphPreview.isOn
            && !args.contains("-noSplash")
    }

    /// False while the library is still being read: the opening waits for it.
    var ready: Bool = true

    @Environment(\.colorScheme) private var scheme
    @State private var visible: Bool = LaunchSplash.wanted
    /// The phone's light or dark, read once, at launch.
    @State private var phoneDark: Bool = LaunchSplash.phoneIsDark

    var body: some View {
        ZStack {
            if visible {
                LaunchOpeningLayer(phoneDark: phoneDark, appDark: scheme == .dark, ready: ready) {
                    visible = false
                }
                .ignoresSafeArea()
                // no fade, even under an animation from around it
                .transition(.identity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if visible { LaunchSplash.shown = true } }
    }
}

/// The opening's layers, in UIKit so Core Animation plays them.
private struct LaunchOpeningLayer: UIViewRepresentable {
    let phoneDark: Bool
    let appDark: Bool
    let ready: Bool
    let done: () -> Void

    func makeUIView(context: Context) -> LaunchOpeningView {
        let view = LaunchOpeningView(phoneDark: phoneDark, appDark: appDark)
        view.done = done
        return view
    }

    func updateUIView(_ view: LaunchOpeningView, context: Context) {
        view.done = done
        view.setReady(ready)
    }
}

final class LaunchOpeningView: UIView {
    var done: (() -> Void)?

    private let phoneDark: Bool
    private let appDark: Bool
    private let side = CGFloat(LaunchArt.side)

    private let ground = CALayer()         // the launch screen's base and paper, until the hand-off
    private let paper = CALayer()          // LaunchPaper, at the screen's top left at its own size
    private let mark = CALayer()           // scales about the chest piece
    private let logo = CALayer()
    private let chest = CALayer()          // the chest piece alone, for the beat
    private let ecg = CAShapeLayer()

    private var started = false
    private var link: CADisplayLink?
    private var frames = 0
    private var waited: DispatchWorkItem?
    #if canImport(AVFoundation)
    private var player: AVAudioPlayer?
    #endif

    init(phoneDark: Bool, appDark: Bool) {
        self.phoneDark = phoneDark
        self.appDark = appDark
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        build()
        prepareSound()
        // the library may never be read in time: open anyway, after a while
        let item = DispatchWorkItem { [weak self] in self?.begin() }
        waited = item
        DispatchQueue.main.asyncAfter(deadline: .now() + LaunchSplash.longestHold, execute: item)
    }

    required init?(coder: NSCoder) { nil }

    private func build() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.addSublayer(ground)
        ground.backgroundColor = LaunchSplash.baseCG(dark: appDark)
        ground.masksToBounds = true
        ground.addSublayer(paper)
        let sheet = Self.paperImage(dark: appDark)
        paper.contents = sheet?.cgImage
        paper.contentsScale = sheet?.scale ?? UIScreen.main.scale
        paper.contentsGravity = .resize
        paper.magnificationFilter = .nearest
        if appDark != phoneDark {
            // a colour shift, not a fade: from the phone's base to the app's,
            // the paper's lines turning over halfway
            let shift = CABasicAnimation(keyPath: "backgroundColor")
            shift.fromValue = LaunchSplash.baseCG(dark: phoneDark)
            shift.toValue = LaunchSplash.baseCG(dark: appDark)
            shift.duration = LaunchSplash.shift
            shift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shift.fillMode = .backwards
            ground.add(shift, forKey: "shift")
            let turn = CAKeyframeAnimation(keyPath: "contents")
            turn.values = [Self.paperImage(dark: phoneDark)?.cgImage as Any, sheet?.cgImage as Any]
            turn.keyTimes = [0, 0.5, 1]
            turn.calculationMode = .discrete
            turn.duration = LaunchSplash.shift
            turn.fillMode = .backwards
            paper.add(turn, forKey: "shift")
        }

        let traits = UITraitCollection(userInterfaceStyle: phoneDark ? .dark : .light)
        let image = UIImage(named: LaunchArt.imageName, in: nil, compatibleWith: traits)
        for l in [logo, chest] {
            l.contents = image?.cgImage
            l.contentsScale = image?.scale ?? UIScreen.main.scale
            l.contentsGravity = .resizeAspect
            // while it beats and moves: smooth resampling, so the metal's
            // fine highlights do not shimmer
            l.magnificationFilter = .linear
            l.minificationFilter = .trilinear
        }
        let c = LaunchArt.chest(dark: phoneDark)
        let anchor = CGPoint(x: c.x, y: c.y)
        mark.anchorPoint = anchor
        mark.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        logo.frame = mark.bounds
        chest.anchorPoint = anchor
        chest.bounds = mark.bounds
        chest.position = CGPoint(x: c.x * side, y: c.y * side)
        let disc = CAShapeLayer()
        let r = c.r * side
        disc.path = UIBezierPath(ovalIn: CGRect(x: c.x * side - r, y: c.y * side - r,
                                                width: 2 * r, height: 2 * r)).cgPath
        chest.mask = disc
        mark.addSublayer(logo)
        mark.addSublayer(chest)

        ecg.strokeColor = Self.traceColor(dark: phoneDark)
        ecg.fillColor = nil
        ecg.lineWidth = 2.5
        ecg.contentsScale = UIScreen.main.scale
        ecg.lineCap = .round
        ecg.lineJoin = .round
        ecg.strokeStart = 0
        ecg.strokeEnd = 0
        layer.addSublayer(ecg)
        layer.addSublayer(mark)
        CATransaction.commit()
    }

    /// Home's ECG paper as the launch screen lays it (LaunchPaper, made by
    /// tools/make_launch_paper.py), in light or dark.
    private static func paperImage(dark: Bool) -> UIImage? {
        UIImage(named: "LaunchPaper", in: nil,
                compatibleWith: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
    }

    private static func traceColor(dark: Bool) -> CGColor {
        let (cr, cg, cb) = WardPalette.rgb(LaunchArt.trace(dark: dark))
        return UIColor(red: cr, green: cg, blue: cb, alpha: 1).cgColor
    }

    /// How long after home is still the splash goes.
    private static let afterStill = 0.1

    /// Where the trace sits: under the mark, as wide as most of it.
    private static let traceWidth: CGFloat = 176
    private static let traceHeight: CGFloat = 36
    /// The trace's baseline within the ECG layer.
    private static var traceTop: CGFloat { traceHeight * 1.15 }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ground.frame = bounds
        // the paper from the screen's top left at its own size, as the launch
        // screen pins it, so its lines fall on home's
        let sheet = (paper.contents != nil ? Self.paperImage(dark: appDark) : nil)?.size ?? .zero
        paper.frame = CGRect(origin: convert(CGPoint.zero, from: nil), size: sheet)
        // centred in the safe area at its natural size, where the launch
        // screen puts the same image: the window's insets, since this view
        // spans the whole screen (SwiftUI's ignoresSafeArea leaves its own
        // at zero)
        let insets = window?.safeAreaInsets ?? safeAreaInsets
        let safe = bounds.inset(by: insets)
        let centre = CGPoint(x: safe.midX, y: safe.midY)
        let c = LaunchArt.chest(dark: phoneDark)
        // the image's corner on a whole device pixel, so at rest it is drawn
        // 1:1, exactly as the launch screen drew it, with no resampling
        let px = window?.screen.scale ?? UIScreen.main.scale
        let origin = CGPoint(x: ((centre.x - side / 2) * px).rounded() / px,
                             y: ((centre.y - side / 2) * px).rounded() / px)
        if !started { mark.position = CGPoint(x: origin.x + c.x * side, y: origin.y + c.y * side) }
        let w = Self.traceWidth
        ecg.frame = CGRect(x: centre.x - w / 2, y: centre.y + side / 2 - 2, width: w, height: Self.traceHeight * 1.6)
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
    }

    // MARK: starting

    func setReady(_ ready: Bool) {
        guard ready, !started, link == nil else { return }
        // the home screen's first real frame: wait for the next two display
        // refreshes, so the frame with the library in it is committed first
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        frames += 1
        if frames >= 2 { begin() }
    }

    private func prepareSound() {
        #if canImport(AVFoundation)
        guard LaunchSplash.soundOn, let data = NSDataAsset(name: HeartbeatSound.asset)?.data else { return }
        // off the main thread: the audio session and the player's buffers
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let session = AVAudioSession.sharedInstance()
            // ambient: silent with the ring switch, mixed with (never stopping)
            // anything already playing; only set when nothing else has chosen
            if session.category == .soloAmbient {
                try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            }
            try? session.setActive(true, options: [])
            guard let player = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.caf.rawValue) else { return }
            player.prepareToPlay()
            DispatchQueue.main.async { self?.player = player }
        }
        #endif
    }

    private func begin() {
        guard !started, window != nil || bounds.width > 0 else { return }
        // a preview launch can hold the first frame, to photograph it against
        // the system launch screen, marked (a red square at the left edge's
        // middle) so a screenshot shows which of the two it caught
        if ProcessInfo.processInfo.arguments.contains("-uiPreviewSplashHold") {
            let tag = CALayer()
            tag.backgroundColor = UIColor.red.cgColor
            tag.frame = CGRect(x: 0, y: bounds.midY - 4, width: 8, height: 8)
            layer.addSublayer(tag)
            started = true
            link?.invalidate(); link = nil
            waited?.cancel(); waited = nil
            return
        }
        started = true
        link?.invalidate(); link = nil
        waited?.cancel(); waited = nil
        layoutIfNeeded()

        let opening = LaunchOpening(reduced: UIAccessibility.isReduceMotionEnabled)
        let lead = 0.06
        var latency = 0.0
        #if canImport(AVFoundation)
        if let player, LaunchSplash.soundOn {
            latency = max(0, AVAudioSession.sharedInstance().outputLatency)
            player.play(atTime: player.deviceCurrentTime + lead + opening.audioAt)
        }
        #endif
        // zero on the host clock: when the file's start would be heard, less
        // `audioAt`; held back by the latency only when the sound is started
        let zero = CACurrentMediaTime() + lead + latency
        animate(opening, from: zero)
    }

    // MARK: the opening

    /// Home's title and its squiggle, in this view's points, when both are
    /// on screen: where the stethoscope and the ECG go.
    private var targets: (title: CGRect, squiggle: CGRect)? {
        let stage = LaunchStage.shared
        guard let title = stage.title, let squiggle = stage.squiggle else { return nil }
        let t = convert(title, from: nil), q = convert(squiggle, from: nil)
        guard bounds.contains(t), bounds.contains(q), t.width > 0, q.width > 0 else { return nil }
        return (t, q)
    }

    private func animate(_ o: LaunchOpening, from zero: CFTimeInterval) {
        // where the ECG starts, which the wave of home's parts follows up
        let stage = LaunchStage.shared
        stage.traceStart = convert(CGPoint(x: ecg.frame.midX, y: ecg.frame.minY + Self.traceTop), to: nil)
        stage.window = window?.bounds.size ?? bounds.size
        let times = o.times()
        let keyTimes = times.map { NSNumber(value: $0 / o.duration) }
        let goal = o.reduced ? nil : targets

        func keys(_ path: String, _ values: [Any]) -> CAKeyframeAnimation {
            let a = CAKeyframeAnimation(keyPath: path)
            a.values = values
            a.keyTimes = keyTimes
            a.calculationMode = .linear
            a.duration = o.duration
            a.beginTime = zero
            a.fillMode = .both
            a.isRemovedOnCompletion = false
            return a
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !o.reduced {
            chest.add(keys("transform.scale", times.map { o.beat(at: $0) }), forKey: "beat")
            addTrace(o, times: times, goal: goal?.squiggle, keys: { keys($0, $1) })
        }
        if let goal {
            // the stethoscope glides up into the title and shrinks away there
            let from = mark.position
            let to = CGPoint(x: goal.title.midX, y: goal.title.midY)
            mark.add(keys("position", times.map { t -> NSValue in
                let e = CGFloat(o.markTravel(at: t))
                // a little arc: up first, then across
                let x = from.x + (to.x - from.x) * e * e
                let y = from.y + (to.y - from.y) * e
                return NSValue(cgPoint: CGPoint(x: x, y: y))
            }), forKey: "glide")
            mark.add(keys("transform.scale", times.map { o.markScale(at: $0) }), forKey: "shrink")
            // the splash's paper gives way to home's (the same paper, with
            // nothing of home drawn on it yet): no pixel changes
            let gone = CAKeyframeAnimation(keyPath: "hidden")
            gone.values = [false, true]
            gone.keyTimes = [0, NSNumber(value: o.handoff / o.duration), 1]
            gone.calculationMode = .discrete
            gone.duration = o.duration
            gone.beginTime = zero
            gone.fillMode = .both
            gone.isRemovedOnCompletion = false
            ground.add(gone, forKey: "handoff")
            enterNavigationBars(o, from: zero)
        } else if o.reduced {
            // Reduce Motion: the mark shrinks where it stands, then home is there
            mark.add(keys("transform.scale", times.map { o.markScale(at: $0) }), forKey: "shrink")
        } else {
            // home is not showing its title (still opening the library, or
            // another page): the splash, ground and all, goes down off the
            // screen while the mark shrinks away
            let drop = bounds.height + 40
            layer.add(keys("sublayerTransform", times.map { t -> NSValue in
                let e = CGFloat(LaunchOpening.easeIn((t - o.handoff) / LaunchOpening.travel))
                return NSValue(caTransform3D: CATransform3DMakeTranslation(0, drop * e, 0))
            }), forKey: "drop")
            mark.add(keys("transform.scale", times.map { o.markScale(at: $0) }), forKey: "shrink")
        }
        CATransaction.commit()

        // home is posed from the same clock: its parts arrive from the
        // hand-off, in a wave that follows the ECG up from where it starts
        stage.play(reduced: o.reduced, handoffHost: zero + o.handoff)
        // The ECG stays on as the squiggle until home is still, then the
        // splash goes and home draws the squiggle in the same update: the
        // same line in the same place, so nothing changes, and the work of
        // taking the splash away falls where nothing is moving, a little
        // after home has stopped. (With no title to land on, the splash has
        // dropped away by `duration`.)
        let end = goal == nil ? o.duration + 0.03 : o.settled + LaunchOpening.runOn + Self.afterStill
        let wait = max(0, zero + end - CACurrentMediaTime())
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            LaunchStage.shared.land()
            self?.done?()
        }
    }

    /// The ECG: drawn in step with the sound, then, at the hand-off, carried
    /// up and shrunk into the squiggle beside home's title (`goal`), turning
    /// the squiggle's colour and weight as it goes.
    private func addTrace(_ o: LaunchOpening, times: [Double], goal: CGRect?,
                          keys: (String, [Any]) -> CAKeyframeAnimation) {
        let trace = o.trace(width: Double(Self.traceWidth), height: Double(Self.traceHeight))
        let top = Double(Self.traceTop)
        func path(_ points: [(x: Double, y: Double)]) -> CGPath {
            let p = CGMutablePath()
            for (i, q) in points.enumerated() {
                let pt = CGPoint(x: q.x, y: q.y)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            return p
        }
        var starts: [Double] = [], ends: [Double] = []
        for t in times {
            if let d = o.ecgDrawn(at: t) {
                starts.append(LaunchOpening.fraction(d.from, of: trace, end: o.traceEnd))
                ends.append(LaunchOpening.fraction(d.to, of: trace, end: o.traceEnd))
            } else {
                starts.append(0); ends.append(t > o.traceEnd ? 1 : 0)
            }
        }
        guard let goal else {
            ecg.path = path(trace.points.map { ($0.x, top + $0.y) })
            ecg.add(keys("strokeStart", starts), forKey: "start")
            ecg.add(keys("strokeEnd", ends), forKey: "end")
            return
        }
        // the trace with every corner of the squiggle on it, so the same
        // points make both; the squiggle in this layer's points
        let pairs = o.morph(trace.points, width: Double(Self.traceWidth))
        let target = ecg.convert(goal, from: layer)
        let shapes = times.map { t -> CGPath in
            path(LaunchOpening.morphed(pairs, at: o.travel(at: t), origin: (0, top),
                                       target: (Double(target.minX), Double(target.minY),
                                                Double(target.width), Double(target.height))))
        }
        // the trim fractions were of the trace alone; the morph's extra
        // points lie on it, so its lengths are the trace's
        ecg.path = shapes.first
        ecg.add(keys("path", shapes), forKey: "travel")
        ecg.add(keys("strokeStart", starts), forKey: "start")
        ecg.add(keys("strokeEnd", ends), forKey: "end")
        let traits = UITraitCollection(userInterfaceStyle: appDark ? .dark : .light)
        let red = UIColor(Color.wardEcg).resolvedColor(with: traits).cgColor
        let ink = Self.traceColor(dark: phoneDark)
        ecg.add(keys("strokeColor", times.map { t -> CGColor in
            Self.mix(ink, red, CGFloat(o.travel(at: t)))
        }), forKey: "tint")
        ecg.add(keys("lineWidth", times.map { t -> CGFloat in
            2.5 + (CGFloat(LaunchOpening.squiggleLine) - 2.5) * CGFloat(o.travel(at: t))
        }), forKey: "weight")
    }

    private static func mix(_ a: CGColor, _ b: CGColor, _ e: CGFloat) -> CGColor {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let ca = a.converted(to: srgb, intent: .defaultIntent, options: nil)?.components ?? [0, 0, 0, 1]
        let cb = b.converted(to: srgb, intent: .defaultIntent, options: nil)?.components ?? [0, 0, 0, 1]
        let c = (0..<3).map { ca[$0] + (cb[$0] - ca[$0]) * e } + [1]
        return CGColor(colorSpace: srgb, components: c) ?? b
    }

    /// The navigation bar (home's account button and search field) is
    /// UIKit's, out of SwiftUI's reach: it arrives whole, with all on it, as
    /// the wave up the screen reaches it (after the ECG has landed: it is
    /// above the title), on the same spring as the rest of home, held at
    /// nothing until then.
    private func enterNavigationBars(_ o: LaunchOpening, from zero: CFTimeInterval) {
        guard let window else { return }
        var bars: [UINavigationBar] = []
        func walk(_ v: UIView) {
            if let bar = v as? UINavigationBar {
                if !bar.isHidden, bar.window != nil { bars.append(bar) }
                return
            }
            v.subviews.forEach(walk)
        }
        walk(window)
        let length = LaunchOpening.settleTime + LaunchOpening.runOn
        let n = max(2, Int((length * 120).rounded(.up)))
        let ts = (0...n).map { length * Double($0) / Double(n) }
        let stage = LaunchStage.shared
        for bar in bars {
            let middle = bar.convert(CGPoint(x: bar.bounds.midX, y: bar.bounds.midY), to: nil).y
            let start = stage.squiggle.map {
                o.arrival(y: Double(middle), from: Double(stage.traceStart.y), to: Double($0.midY))
            } ?? o.openingArrives
            let a = CAKeyframeAnimation(keyPath: "transform")
            a.values = ts.map { t -> NSValue in
                let e = o.entrance(from: start, at: start + t)
                var m = CATransform3DMakeTranslation(0, CGFloat(e.drop), 0)
                m = CATransform3DScale(m, CGFloat(e.scale), CGFloat(e.scale), 1)
                return NSValue(caTransform3D: m)
            }
            a.keyTimes = ts.map { NSNumber(value: $0 / length) }
            a.duration = length
            a.beginTime = zero + start
            // nothing of it shows until it enters, and it ends as it is
            a.fillMode = .backwards
            a.isRemovedOnCompletion = true
            bar.layer.add(a, forKey: "launchEntrance")
        }
    }
}

/// What shows beneath the splash while a big library is still being read
/// (Store): the matte base and a spinner, and no screen that could show the
/// library, or write into it, before it is in.
struct LibraryLoadingView: View {
    var body: some View {
        VStack(spacing: WardSpace.m) {
            ProgressView()
            Text("Opening your library…")
                .font(.subheadline)
                .foregroundStyle(Color.wardInkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wardScreen()
    }
}

extension View {
    /// Lays the launch opening over this view, until it has played: it
    /// starts once `ready` (the library read) and the next frame is drawn.
    func launchSplash(until ready: Bool = true) -> some View {
        overlay { LaunchSplash(ready: ready) }
    }
}
