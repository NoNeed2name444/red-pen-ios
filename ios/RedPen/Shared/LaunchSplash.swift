import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

/// The opening: the owner's stethoscope on the home screen's base colour,
/// exactly as the system launch screen drew it, and then, once the home
/// screen's first real frame is up (the library read), one heartbeat:
///
/// 1. the chest piece beats, lub then dub, and the heartbeat is heard
///    (Assets.xcassets/Heartbeat, if the app's sound is on);
/// 2. one ECG complex is drawn under the mark (LaunchArt.trace), its R
///    peak as the lub is heard and its T wave ending as the dub is, then
///    erased from the left as a monitor sweeps;
/// 3. the home screen is uncovered by a circle opening from the chest piece,
///    while the mark scales up about it.
///
/// Nothing fades: everything is scale, stroke trims, a mask and (when the
/// app's light or dark differs from the phone's) a colour shift of the base.
/// The timings are LaunchOpening's, tested on Linux; here they are sampled
/// into Core Animation keyframes, so the animation runs in the render server
/// and a busy main thread cannot stall it. The sound and the drawing are
/// started from one host-clock moment (`AVAudioPlayer.play(atTime:)` on the
/// audio clock, `beginTime` on the same host clock the display link reports),
/// with the drawing held back by the output's latency when the sound is
/// really started, so on a Bluetooth headset what is heard and what is drawn
/// still meet. Muted or with the sound off, the ECG draws at the same times.
///
/// The Xcode build has a real launch screen (`UILaunchScreen` in project.yml,
/// the same image on the same colour), so this carries that picture on
/// without a jump. The Swift Playgrounds package has none, so there this
/// *is* the launch screen.
///
/// It never holds anything up: the app is running beneath it from the first
/// frame, it ignores touches, it is hidden from VoiceOver, and it goes as
/// soon as the circle has passed the screen's corners. If the library takes
/// longer than `longestHold`, it opens anyway, onto the screen saying the
/// library is opening (LibraryLoadingView).
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

    private let cover = CALayer()          // everything the hole opens through
    private let hole = CAShapeLayer()      // the cover's mask: all but a circle
    private let ground = CALayer()
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
        layer.addSublayer(cover)
        cover.mask = hole
        hole.fillRule = .evenOdd
        cover.addSublayer(ground)
        ground.backgroundColor = LaunchSplash.baseCG(dark: appDark)
        if appDark != phoneDark {
            // a colour shift, not a fade: from the phone's base to the app's
            let shift = CABasicAnimation(keyPath: "backgroundColor")
            shift.fromValue = LaunchSplash.baseCG(dark: phoneDark)
            shift.toValue = LaunchSplash.baseCG(dark: appDark)
            shift.duration = LaunchSplash.shift
            shift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shift.fillMode = .backwards
            ground.add(shift, forKey: "shift")
        }

        let traits = UITraitCollection(userInterfaceStyle: phoneDark ? .dark : .light)
        let image = UIImage(named: LaunchArt.imageName, in: nil, compatibleWith: traits)
        for l in [logo, chest] {
            l.contents = image?.cgImage
            l.contentsScale = image?.scale ?? UIScreen.main.scale
            l.contentsGravity = .resizeAspect
            // while it beats and grows: smooth resampling, so the metal's
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

        let (cr, cg, cb) = WardPalette.rgb(LaunchArt.trace(dark: phoneDark))
        ecg.strokeColor = UIColor(red: cr, green: cg, blue: cb, alpha: 1).cgColor
        ecg.fillColor = nil
        ecg.lineWidth = 2.5
        ecg.lineCap = .round
        ecg.lineJoin = .round
        ecg.strokeStart = 0
        ecg.strokeEnd = 0
        cover.addSublayer(ecg)
        cover.addSublayer(mark)
        CATransaction.commit()
    }

    /// Where the trace sits: under the mark, as wide as most of it.
    private static let traceWidth: CGFloat = 176
    private static let traceHeight: CGFloat = 36

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cover.frame = bounds
        ground.frame = bounds
        // centred in the safe area at its natural size, where UILaunchScreen
        // puts the same image: the window's insets, since this view spans the
        // whole screen (SwiftUI's ignoresSafeArea leaves its own at zero)
        let insets = window?.safeAreaInsets ?? safeAreaInsets
        let safe = bounds.inset(by: insets)
        let centre = CGPoint(x: safe.midX, y: safe.midY)
        let c = LaunchArt.chest(dark: phoneDark)
        // the image's corner on a whole device pixel, so at rest it is drawn
        // 1:1, exactly as the launch screen drew it, with no resampling
        let px = window?.screen.scale ?? UIScreen.main.scale
        let origin = CGPoint(x: ((centre.x - side / 2) * px).rounded() / px,
                             y: ((centre.y - side / 2) * px).rounded() / px)
        mark.position = CGPoint(x: origin.x + c.x * side, y: origin.y + c.y * side)
        let w = Self.traceWidth
        ecg.frame = CGRect(x: centre.x - w / 2, y: centre.y + side / 2 - 2, width: w, height: Self.traceHeight * 1.6)
        if !started { hole.path = holePath(radius: 0) }
        hole.frame = bounds
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
    }

    private var chestOnScreen: CGPoint { mark.position }

    private func holePath(radius: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.addRect(bounds.insetBy(dx: -4, dy: -4))
        let r = max(radius, 0.01)
        p.addEllipse(in: CGRect(x: chestOnScreen.x - r, y: chestOnScreen.y - r, width: 2 * r, height: 2 * r))
        return p
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

    private func animate(_ o: LaunchOpening, from zero: CFTimeInterval) {
        let times = o.times()
        let keyTimes = times.map { NSNumber(value: $0 / o.duration) }
        let maxR = CGFloat(LaunchOpening.farthest(x: chestOnScreen.x, y: chestOnScreen.y,
                                                  width: bounds.width, height: bounds.height))

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
        hole.add(keys("path", times.map { holePath(radius: CGFloat(o.reveal(at: $0)) * maxR) }), forKey: "reveal")
        mark.add(keys("transform.scale", times.map { o.markScale(at: $0) }), forKey: "grow")
        if !o.reduced {
            chest.add(keys("transform.scale", times.map { o.beat(at: $0) }), forKey: "beat")
            let trace = o.trace(width: Double(Self.traceWidth), height: Double(Self.traceHeight))
            let path = CGMutablePath()
            let top = CGFloat(Self.traceHeight) * 1.15
            for (i, p) in trace.points.enumerated() {
                let pt = CGPoint(x: p.x, y: Double(top) + p.y)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            ecg.path = path
            var starts: [Double] = [], ends: [Double] = []
            for t in times {
                if let d = o.ecgDrawn(at: t) {
                    starts.append(LaunchOpening.fraction(d.from, of: trace, end: o.traceEnd))
                    ends.append(LaunchOpening.fraction(d.to, of: trace, end: o.traceEnd))
                } else {
                    let v: Double = t < o.eraseStart ? 0 : 1
                    starts.append(v); ends.append(v)
                }
            }
            ecg.add(keys("strokeStart", starts), forKey: "start")
            ecg.add(keys("strokeEnd", ends), forKey: "end")
        }
        CATransaction.commit()

        // gone once the circle has passed every corner: nothing of it shows
        // by then, so taking it away changes no pixel
        let wait = max(0, zero + o.duration - CACurrentMediaTime()) + 0.03
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            self?.done?()
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
