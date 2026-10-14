import SwiftUI
import Observation

/// Home's side of the opening's hand-off (LaunchSplash, LaunchOpening).
///
/// While an opening is going to play, home is laid out but none of it is
/// drawn except its base: every part waits at nothing, so when the splash's
/// own ground gives way there is no change to see. At the hand-off, home's
/// parts grow into place in turn (LaunchEntrance), the title's letters
/// settle in (LetterSettle), the ECG paper is drawn outward from the trace
/// (gridReach), and the squiggle beside the title appears the moment the
/// splash's ECG lands on it. Nothing fades: every part moves and scales.
///
/// Home tells the splash where the title and its squiggle are, so the
/// stethoscope and the ECG can travel there.
@MainActor
@Observable
final class LaunchStage {
    static let shared = LaunchStage()

    /// Home's parts in place.
    private(set) var entered: Bool
    /// The squiggle beside the title shown: the splash's ECG has landed.
    private(set) var landed: Bool
    /// The ECG paper still being drawn out.
    private(set) var gridDrawing = false
    /// Reduce Motion: home appears in place, with no movement.
    private(set) var reduced = false

    @ObservationIgnored private var handoffDate: Date?
    /// Where the paper is drawn out from, and the window it fills (window
    /// points): set by the splash at the hand-off.
    @ObservationIgnored var gridOrigin: CGPoint = .zero
    @ObservationIgnored var window: CGSize = .zero

    /// Where home's title and the squiggle beside it are (window points),
    /// while they are on screen.
    @ObservationIgnored var title: CGRect?
    @ObservationIgnored var squiggle: CGRect?

    /// The longest home waits for an opening before it shows itself anyway.
    static let longestWait: Double = 6

    init() {
        let waiting = LaunchSplash.wanted
        entered = !waiting
        landed = !waiting
        if waiting {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.longestWait) { [weak self] in
                self?.land()
            }
        }
    }

    /// The hand-off has started: home's parts begin to enter.
    func enter(reduced: Bool) {
        guard !entered else { return }
        self.reduced = reduced
        handoffDate = Date()
        gridDrawing = !reduced
        entered = true
        if !reduced {
            DispatchQueue.main.asyncAfter(deadline: .now() + LaunchOpening.gridLength + 0.05) { [weak self] in
                self?.gridDrawing = false
            }
        }
    }

    /// The ECG is on the squiggle and the splash has gone.
    func land() {
        if !entered { enter(reduced: true) }
        landed = true
    }

    /// How far the ECG paper is drawn out, from the hand-off: nil once whole
    /// (or with no opening), else the reach of its lines, in window points,
    /// across (x) and down (y).
    func gridReach(at date: Date) -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>)? {
        guard let start = handoffDate else { return entered ? nil : (0...0, 0...0) }
        let o = LaunchOpening(reduced: reduced)
        let f = CGFloat(o.gridReach(at: o.handoff + date.timeIntervalSince(start)))
        if f >= 1 { return nil }
        let p = gridOrigin
        let dx = max(p.x, window.width - p.x) + 2, dy = max(p.y, window.height - p.y) + 2
        return ((p.x - f * dx)...(p.x + f * dx), (p.y - f * dy)...(p.y + f * dy))
    }

    /// Seconds since the hand-off started, in the opening's own time.
    func openingTime(at date: Date) -> Double {
        let o = LaunchOpening(reduced: reduced)
        guard let start = handoffDate else { return entered ? o.settled : 0 }
        return o.handoff + date.timeIntervalSince(start)
    }
}

/// A part of home that enters at the hand-off, `order`-th in turn: it grows
/// from nothing and rises the last few points into place on a spring.
struct LaunchEntrance: ViewModifier {
    let order: Int

    func body(content: Content) -> some View {
        let stage = LaunchStage.shared
        let on = stage.entered
        let delay = LaunchOpening.entranceLead + LaunchOpening.stagger * Double(order)
        content
            .scaleEffect(on ? 1 : 0.0001)
            .offset(y: on ? 0 : LaunchOpening.rise)
            .animation(stage.reduced ? nil
                       : Animation.spring(response: LaunchOpening.spring.response,
                                          dampingFraction: LaunchOpening.spring.damping).delay(delay),
                       value: on)
    }
}

extension View {
    /// Enters at the opening's hand-off, `order`-th in turn (0 first).
    @MainActor
    func launchEntrance(_ order: Int) -> some View {
        modifier(LaunchEntrance(order: min(order, LaunchOpening.lastOrder)))
    }

    /// Tells the opening where this is on screen (the title, or its squiggle).
    @MainActor
    func launchTarget(_ target: LaunchTarget) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            switch target {
            case .title: LaunchStage.shared.title = frame
            case .squiggle: LaunchStage.shared.squiggle = frame
            }
        }
    }
}

enum LaunchTarget { case title, squiggle }

/// The title's letters, settling in one after another at the hand-off: each
/// grows from nothing and rises the last few points into place. At rest it
/// draws the text exactly as SwiftUI would.
struct LetterSettle: TextRenderer {
    /// The opening's time (LaunchOpening), animated through the hand-off.
    var time: Double
    var reduced: Bool

    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let o = LaunchOpening(reduced: reduced)
        if time >= o.settled {
            for line in layout { context.draw(line) }
            return
        }
        var i = 0
        for line in layout {
            for run in line {
                for slice in run {
                    let l = o.letter(i, at: time)
                    i += 1
                    guard l.scale > 0.001 else { continue }
                    let b = slice.typographicBounds.rect
                    var c = context
                    c.translateBy(x: b.midX, y: b.midY + CGFloat(l.drop))
                    c.scaleBy(x: CGFloat(l.scale), y: CGFloat(l.scale))
                    c.translateBy(x: -b.midX, y: -b.midY)
                    c.draw(slice)
                }
            }
        }
    }
}

extension View {
    /// The app's name as home's title: its letters settle in at the opening's
    /// hand-off.
    @MainActor
    func launchLetters() -> some View {
        let stage = LaunchStage.shared
        let o = LaunchOpening(reduced: stage.reduced)
        return textRenderer(LetterSettle(time: stage.entered ? o.settled : o.handoff, reduced: stage.reduced))
            .animation(stage.reduced ? nil : Animation.linear(duration: o.settled - o.handoff), value: stage.entered)
    }
}
