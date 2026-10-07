import SwiftUI

// MARK: - The ward round on screen
//
// The tile that starts one (on the exam plan), the chip that floats over the
// app while it runs and the panel it opens into (WardRoundOverlay), and the
// goal ring beside the streak.
//
// The time left is a WardRing that redraws once a second, and only while a
// clock is actually running: a paused round, a finished break and a finished
// round are still pictures.

enum WardRoundStyle {
    /// Theatre Blue while focusing, green on a break, grey while paused.
    static func tone(_ round: WardRound) -> WardTone {
        if round.phase == .rest || round.phase == .ready { return .green }
        return round.isPaused ? .grey : .blue
    }
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

/// The time left as a small ring with no numeral, for the tile and the chip
/// (the time sits beside it in SF Mono).
struct WardRoundMiniRing: View {
    let round: WardRound
    let now: Date
    var width: CGFloat = 3
    var size: CGFloat = 22

    var body: some View {
        WardRing(value: round.leftFraction(at: now), tone: WardRoundStyle.tone(round), lineWidth: width, centre: "")
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
        VStack(alignment: .leading, spacing: 12) {
            if let round = clock.round {
                running(round)
            } else {
                setup
            }
        }
        // raised as low as the tiles round it, the button proud of it
        .wardCard(padding: 14, lift: .low)
    }

    @ViewBuilder
    private var setup: some View {
        Label("Start a ward round", systemImage: "stethoscope")
            .font(.headline)
            .foregroundStyle(Color.wardInk)
        Text("Four rounds of focus with a break between. Everything you study while the clock runs counts on the round, and its minutes count for your streak.")
            .font(.caption)
            .foregroundStyle(Color.wardInkSecondary)
            .fixedSize(horizontal: false, vertical: true)
        WardSegmented(selection: $focus, options: WardRoundPlan.focusChoices) { minutes in
            Text("\(minutes) min")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Focus")
        .accessibilityIdentifier("wardRoundFocus")
        WardSegmented(selection: $rest, options: WardRoundPlan.breakChoices) { minutes in
            Text("\(minutes) min break")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Break")
        .accessibilityIdentifier("wardRoundBreak")
        Button(action: start) {
            Label("Start round 1", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.wardPrimary)
        .accessibilityIdentifier("wardRoundStart")
    }

    private func running(_ round: WardRound) -> some View {
        HStack(spacing: 12) {
            WardRoundTicker(round: round) { now in
                HStack(spacing: 12) {
                    WardRoundMiniRing(round: round, now: now, width: 4, size: 40)
                    Text(round.caption(at: now))
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.wardInk)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Button("Open") { WardRoundOverlay.shared.open() }
                .buttonStyle(.wardCompact)
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
                WardRoundMiniRing(round: round, now: now)
                Text(notice ?? words(at: now))
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(Color.wardInk)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .frame(maxWidth: 300)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ward round: " + round.caption(at: now))
        }
        .background(Color.wardSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.wardHairline, lineWidth: 1))
        .wardShadow()
        .contentShape(Capsule())
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

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.card, style: .continuous)
        VStack(spacing: 16) {
            header
            WardRoundTicker(round: round) { now in face(now) }
            if let notice {
                Text(notice)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.wardInk)
                    .multilineTextAlignment(.center)
            }
            controls
        }
        .wardCard(padding: 20)
        // a tap on the panel itself is not a tap on the dimming behind
        .contentShape(shape)
    }

    private var header: some View {
        HStack {
            Label("Ward round", systemImage: "stethoscope")
                .font(.headline)
                .foregroundStyle(Color.wardInk)
            Spacer(minLength: 8)
            Button(action: close) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.wardInkSecondary)
            .accessibilityLabel("Fold the ward round away")
            .accessibilityIdentifier("wardRoundFold")
        }
    }

    private func face(_ now: Date) -> some View {
        let time: String = WardRound.clock(round.remaining(at: now))
        return VStack(spacing: 10) {
            VStack(spacing: 8) {
                WardRing(value: round.leftFraction(at: now), tone: WardRoundStyle.tone(round), label: phaseWord,
                         lineWidth: 6, centre: round.isTimed ? time : "\u{2013}")
                    .frame(width: 180, height: 180)
                Text(round.roundWords)
                    .wardSmallCaps()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(round.caption(at: now))
            Text(tally)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(Color.wardInkSecondary)
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
                .foregroundStyle(Color.wardInkSecondary)
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
                .foregroundStyle(Color.wardDanger)
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("wardRoundStop")
    }

    private func wide(_ title: String, symbol: String, id: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.wardSecondary)
        .accessibilityIdentifier(id)
    }

    private func prominent(_ title: String, symbol: String, id: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.wardPrimary)
        .accessibilityIdentifier(id)
    }
}

// MARK: the goal ring

/// A thin ring of today against the daily goal, and "32 / 50 today".
struct DailyGoalRing: View {
    /// Cards, questions and steps done today (StudyLog.today).
    let done: Int
    /// Watched, so a new goal set in Settings redraws the ring at once.
    @AppStorage(DailyGoal.key) private var stored: Int = 50

    var body: some View {
        let progress = GoalProgress(done: done, goal: GoalProgress.goal(stored: stored))
        let tint: Color = progress.met ? Color.wardSuccess : Color.wardBeam
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.wardHairline, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress.fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
            Text(progress.label)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.wardInkSecondary)
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
                .foregroundStyle(streak > 0 ? Color.wardBeam : Color.wardInkSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(days).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Color.wardInk)
                Label(rest, systemImage: "moon.fill")
                    .font(.caption)
                    .foregroundStyle(Color.wardInkSecondary)
            }
            Spacer(minLength: 8)
            DailyGoalRing(done: log.today)
        }
        .padding(.vertical, 2)
    }
}
