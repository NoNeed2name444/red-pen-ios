import SwiftUI

// MARK: - The ward round on screen
//
// The tile that starts one (on the exam plan), the chip that floats over the
// app while it runs and the panel it opens into (WardRoundOverlay), and the
// goal ring beside the streak.
//
// The time left is a thin orbit ring that redraws once a second, and only
// while a clock is actually running: a paused round, a finished break and a
// finished round are still pictures. Breaks sit on a calm, still star field -
// nothing on it moves.

enum WardRoundStyle {
    /// Starlight blue: calm, and apart from the pen red of the actions.
    static let tint = Color(red: 0.55, green: 0.78, blue: 0.94)
}

/// Redraws `content` once a second while the round's clock runs, on the
/// second the clock text changes; otherwise draws it once.
struct WardRoundTicker<Content: View>: View {
    let round: WardRound
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if round.ticks {
            // counted from a whole number of seconds before the phase's end,
            // so each tick lands as the clock text turns over
            let origin: Date = round.phaseEnds.addingTimeInterval(-7_200)
            TimelineView(.periodic(from: origin, by: 1)) { context in
                content(context.date)
            }
        } else {
            content(Date())
        }
    }
}

/// A thin ring of the time left, with a small body riding its end.
struct OrbitRing: View {
    let fraction: Double
    var tint: Color = WardRoundStyle.tint
    var width: CGFloat = 3
    var size: CGFloat = 22

    var body: some View {
        let turn: Double = 360 * fraction
        let dot: CGFloat = width * 2.2
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: width)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(tint)
                .frame(width: dot, height: dot)
                .offset(y: -size / 2)
                .rotationEffect(.degrees(turn))
                .opacity(fraction > 0 ? 1 : 0)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: the tile

/// "Start a ward round": the choice of 25 or 50 minutes and a 5- or
/// 10-minute break, and the start. While one runs, its ring and a way in.
struct WardRoundTile: View {
    @ObservedObject private var clock = WardRoundClock.shared
    @AppStorage(WardRoundClock.focusKey) private var focus: Int = 25
    @AppStorage(WardRoundClock.breakKey) private var rest: Int = 5

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            if let round = clock.round {
                running(round)
            } else {
                setup
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(WardRoundStyle.tint.opacity(0.14)), in: shape)
        .popOut(.raised, in: shape)
    }

    @ViewBuilder
    private var setup: some View {
        Label("Start a ward round", systemImage: "stethoscope")
            .font(.headline)
            .foregroundStyle(.primary)
        Text("Four rounds of focus with a break between. Everything you study while the clock runs counts on the round, and its minutes count for your streak.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Picker("Focus", selection: $focus) {
            ForEach(WardRoundPlan.focusChoices, id: \.self) { minutes in
                Text("\(minutes) min").tag(minutes)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("wardRoundFocus")
        Picker("Break", selection: $rest) {
            ForEach(WardRoundPlan.breakChoices, id: \.self) { minutes in
                Text("\(minutes) min break").tag(minutes)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("wardRoundBreak")
        Button(action: start) {
            Label("Start round 1", systemImage: "play.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .popOut(.hero, in: Capsule(), tint: .accentColor)
        .accessibilityIdentifier("wardRoundStart")
    }

    private func running(_ round: WardRound) -> some View {
        HStack(spacing: 12) {
            WardRoundTicker(round: round) { now in
                HStack(spacing: 12) {
                    OrbitRing(fraction: round.leftFraction(at: now), width: 4, size: 40)
                    Text(round.caption(at: now))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Button("Open") { WardRoundOverlay.shared.open() }
                .buttonStyle(.glass)
                .accessibilityIdentifier("wardRoundOpen")
        }
    }

    private func start() {
        clock.start(WardRoundPlan(focusMinutes: focus, breakMinutes: rest))
    }
}

// MARK: the chip

/// The small chip over the app while a round runs: the ring and the time,
/// or for a few seconds what just ended. Tap to open the round; the overlay
/// drags it (so it is a tap gesture here, not a Button, which would take the
/// drag for a press).
struct WardRoundChip: View {
    let round: WardRound
    let notice: String?
    let open: () -> Void

    var body: some View {
        WardRoundTicker(round: round) { now in
            HStack(spacing: 8) {
                OrbitRing(fraction: round.leftFraction(at: now))
                Text(notice ?? words(at: now))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .frame(maxWidth: 300)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ward round: " + round.caption(at: now))
        }
        .contentShape(Capsule())
        .glassEffect(.regular.interactive(), in: Capsule())
        .popOut(.floating, in: Capsule())
        .onTapGesture(perform: open)
        .sensoryFeedback(.success, trigger: notice) { _, new in new != nil }
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .accessibilityHint("Opens the ward round. Drag to move it to another corner.")
        .accessibilityIdentifier("wardRoundChip")
    }

    private func words(at now: Date) -> String {
        let time: String = WardRound.clock(round.remaining(at: now))
        switch round.phase {
        case .focus: return round.isPaused ? "Paused \u{00B7} " + time : time
        case .rest: return "Break \u{00B7} " + time
        case .ready: return "Round \(round.round + 1) ready"
        case .done: return "Done"
        }
    }
}

// MARK: the panel

/// The round, open over the app: the ring, the count, and what to do next.
struct WardRoundPanel: View {
    let round: WardRound
    let notice: String?
    let close: () -> Void

    private var clock: WardRoundClock { WardRoundClock.shared }

    private var resting: Bool { round.phase == .rest || round.phase == .ready }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(spacing: 16) {
            header
            WardRoundTicker(round: round) { now in face(now) }
            if let notice {
                Text(notice)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            controls
        }
        .padding(20)
        .background {
            if resting { StillStarField().clipShape(shape) }
        }
        .glassEffect(.regular, in: shape)
        // a tap on the panel's own glass is not a tap on the dimming behind
        .contentShape(shape)
        .popOut(.floating, in: shape)
        .environment(\.colorScheme, resting ? .dark : colorSchemeBeneath)
    }

    @Environment(\.colorScheme) private var colorSchemeBeneath

    private var header: some View {
        HStack {
            Label("Ward round", systemImage: "stethoscope")
                .font(.headline)
            Spacer(minLength: 8)
            Button(action: close) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Fold the ward round away")
            .accessibilityIdentifier("wardRoundFold")
        }
    }

    private func face(_ now: Date) -> some View {
        let time: String = WardRound.clock(round.remaining(at: now))
        return VStack(spacing: 10) {
            ZStack {
                OrbitRing(fraction: round.leftFraction(at: now), width: 6, size: 190)
                VStack(spacing: 4) {
                    Text(phaseWord)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(round.isTimed ? time : "\u{2013}")
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    Text(round.roundWords)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(round.caption(at: now))
            Text(tally)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var phaseWord: String {
        switch round.phase {
        case .focus: return round.isPaused ? "Paused" : "Focus"
        case .rest: return "Break"
        case .ready: return "Ready"
        case .done: return "Done"
        }
    }

    /// "38 cards · 31 min focused".
    private var tally: String {
        let cards: String = WardRound.cardWords(round.items)
        return cards + " \u{00B7} \(round.focusMinutes) min focused"
    }

    @ViewBuilder
    private var controls: some View {
        switch round.phase {
        case .focus:
            HStack(spacing: 12) {
                if round.isPaused {
                    wide("Resume", symbol: "play.fill", id: "wardRoundResume") { clock.resume() }
                } else {
                    wide("Pause", symbol: "pause.fill", id: "wardRoundPause") { clock.pause() }
                }
                wide("End round", symbol: "forward.end.fill", id: "wardRoundSkip") { clock.skip() }
            }
            stopButton
        case .rest:
            Text("Look away from the screen for a while.")
                .font(.caption)
                .foregroundStyle(.secondary)
            wide("Start round \(round.round + 1) now", symbol: "play.fill", id: "wardRoundNext") { clock.startNext() }
            stopButton
        case .ready:
            prominent("Start round \(round.round + 1)", symbol: "play.fill", id: "wardRoundNext") { clock.startNext() }
            stopButton
        case .done:
            prominent("Close", symbol: "checkmark", id: "wardRoundClose") {
                close()
                clock.close()
            }
        }
    }

    private var stopButton: some View {
        Button(role: .destructive) {
            close()
            clock.stop()
        } label: {
            Text("Stop the ward round")
                .font(.subheadline)
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("wardRoundStop")
    }

    private func wide(_ title: String, symbol: String, id: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier(id)
    }

    private func prominent(_ title: String, symbol: String, id: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .popOut(.hero, in: Capsule(), tint: .accentColor)
        .accessibilityIdentifier(id)
    }
}

/// A calm night for the break: stars drawn once, in place. Nothing moves.
struct StillStarField: View {
    private struct Star {
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var glow: Double
    }

    /// The same sky every time, from a fixed seed.
    private static let stars: [Star] = {
        var seed: UInt64 = 0x5EED_CA1D
        func next() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(seed >> 40) / CGFloat(1 << 24)
        }
        var out: [Star] = []
        for _ in 0..<90 {
            let x: CGFloat = next()
            let y: CGFloat = next()
            let size: CGFloat = 0.6 + 1.8 * next() * next()
            let glow: Double = Double(0.35 + 0.6 * next())
            out.append(Star(x: x, y: y, size: size, glow: glow))
        }
        return out
    }()

    var body: some View {
        Canvas { context, size in
            for star in Self.stars {
                let point = CGPoint(x: star.x * size.width, y: star.y * size.height)
                let box = CGRect(x: point.x - star.size / 2, y: point.y - star.size / 2,
                                 width: star.size, height: star.size)
                context.fill(Path(ellipseIn: box), with: .color(.white.opacity(star.glow)))
            }
        }
        .background(SkyPalette.ink)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: the goal ring

/// A thin ring of today against the daily goal, and "32 / 50 today".
struct DailyGoalRing: View {
    let progress: GoalProgress

    var body: some View {
        let tint: Color = progress.met ? .green : .orange
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress.fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
            Text(progress.label)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily goal: \(progress.done) of \(progress.goal) done today")
    }
}

/// The streak, the rest day and the goal ring, for the exam plan's Today.
struct TodayGoalRow: View {
    @ObservedObject private var log = StudyLog.shared

    var body: some View {
        let streak: Int = log.streak
        let days: String = streak == 1 ? "1-day streak" : "\(streak)-day streak"
        let rest: String = log.restDayReady ? "Rest day ready" : "Rest day used this week"
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .foregroundStyle(streak > 0 ? Color.orange : Color.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(days).font(.subheadline.weight(.semibold))
                Label(rest, systemImage: "moon.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            DailyGoalRing(progress: log.goalProgress)
        }
        .padding(.vertical, 2)
    }
}
