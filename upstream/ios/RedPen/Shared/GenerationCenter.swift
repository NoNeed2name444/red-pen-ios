import SwiftUI

/// The one piece of generation running right now, shown as a floating card
/// with a strip for how much is done and a Cancel that really stops it.
///
/// Every generator (MCQs, stations, cards, pages) reports here instead of
/// drawing its own spinner, so there is one progress display and one cancel
/// that behave the same everywhere.
@MainActor
final class GenerationCenter: ObservableObject {
    static let shared = GenerationCenter()

    struct Job: Equatable {
        let id: UUID
        var title: String
        var done: Int
        var total: Int
        var phase: String?
        /// When it began, for the time-left estimate.
        var started: Date = Date()

        var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }

        /// Seconds left at the pace so far; nil until there is a pace to go on.
        func secondsLeft(now: Date = Date()) -> Int? {
            guard done > 0, total > done else { return nil }
            let elapsed: Double = now.timeIntervalSince(started)
            guard elapsed >= 5 else { return nil }
            let perItem: Double = elapsed / Double(done)
            return Int((perItem * Double(total - done)).rounded())
        }
    }

    @Published private(set) var job: Job?
    private var stop: (() -> Void)?
    /// The running job's cloud deliveries, told who stopped it.
    private var keep: CloudJobs.Delivery?
    /// The screen that started the running job (New set), if any.
    private var owner: UUID?

    /// Why a new generation cannot start now, in words for the student; nil
    /// when nothing is running. Asked before a screen starts anything.
    var busy: String? {
        if case .refuse(let why) = GenerationRules.admit(running: job?.title) { return why }
        return nil
    }

    /// Starts showing a job, or refuses with nil while another one runs.
    /// `onCancel` must cancel the work's Task and put the screen that
    /// started it back to idle; it runs on the main actor. `delivery`: the
    /// generation's cloud deliveries, if it may run a cloud job. `owner`:
    /// the screen it is started under (`generationOwner`), which stops it
    /// when it closes.
    @discardableResult
    func begin(_ title: String, total: Int, owner: UUID? = nil, keeping delivery: CloudJobs.Delivery? = nil,
               onCancel: @escaping () -> Void) -> UUID? {
        // One job at a time, and the one running is never stopped to make
        // room: a cancelled cloud job is deleted on the server with what it
        // had written (GenerationRules). Only the student stops it (the
        // card's Cancel, closing the screen that started it, or Stop on the
        // system's progress indicator), or the system, which leaves its cloud
        // job to finish when the app can tell it was the system (stopAtExpiry).
        guard GenerationRules.admit(running: job?.title) == .start else { return nil }
        let id = UUID()
        job = Job(id: id, title: title, done: 0, total: total, phase: nil, started: Date())
        stop = onCancel
        keep = delivery
        self.owner = owner
        // carries on if the student leaves the app, and says when it is done
        BackgroundWork.begin(id, title: title)
        Task { await AppNotifications.requestIfNeeded() }
        return id
    }

    /// Progress from a generator's callback, from any thread. Ignored once
    /// the job has finished or been cancelled, so a late report cannot bring
    /// the card back.
    nonisolated func update(_ id: UUID, done: Int, total: Int, phase: String? = nil) {
        Task { @MainActor in
            guard var current = self.job, current.id == id else { return }
            current.done = done
            current.total = total
            current.phase = phase
            self.job = current
            BackgroundWork.progress(id, done: done, total: total, phase: phase)
        }
    }

    /// The job is over. `finished` says what was made, for the notification
    /// sent when the student is not in the app; nil for a job that failed.
    func end(_ id: UUID, finished: String? = nil) {
        guard job?.id == id else { return }
        let title = job?.title
        job = nil
        stop = nil
        keep = nil
        owner = nil
        BackgroundWork.end(id, success: finished != nil)
        if let finished { AppNotifications.generationFinished(finished, body: title.map { "Done: \($0.lowercased())." } ?? "Done.") }
    }

    func cancel() {
        let stopping = stop
        if let id = job?.id { BackgroundWork.end(id, success: false) }
        job = nil
        stop = nil
        keep = nil
        owner = nil
        stopping?()
    }

    /// A screen is closing (New set): what it started stops, as with Cancel,
    /// and nothing else does (GenerationRules.closingStops).
    func cancel(startedBy screen: UUID) {
        guard job != nil, GenerationRules.closingStops(running: owner, closing: screen) else { return }
        cancel()
    }

    /// The continued processing task expired (BackgroundWork). The work
    /// stops as with Cancel; a cloud job under it is kept for the collector
    /// only when the stop was surely the system's, not the student's Stop on
    /// the progress indicator (CloudJobRules.stopAtExpiry, afterStop).
    func stopAtExpiry(appActive: Bool) {
        keep?.stopped(by: CloudJobRules.stopAtExpiry(appActive: appActive))
        cancel()
    }
}

/// The floating card: the ECG loader while the work runs, what is being
/// written, how many of how many and about how long is left, a strip filling
/// as it gets done, and Cancel - the one way to stop it.
///
/// A soft card raised high off the base, at the bottom where the
/// thumb is. A screen with its own bottom slab (New set) shows this in place
/// of that slab while a job runs; any other screen uses `generationHUD()`.
struct GenerationHUD: View {
    @ObservedObject private var center = GenerationCenter.shared

    var body: some View {
        ZStack {
            if let job = center.job {
                GenerationCard(job: job, cancel: { center.cancel() })
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: 560)
                    .transition(.slideIn(.bottom))
            }
        }
        .animation(.spring(duration: 0.3), value: center.job?.id)
    }
}

/// The card itself.
private struct GenerationCard: View {
    let job: GenerationCenter.Job
    let cancel: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: WardRadius.card, style: .continuous)
        VStack(alignment: .leading, spacing: WardSpace.m) {
            HStack(spacing: WardSpace.m) {
                EcgLoader()
                GenerationLines(job: job)
                Spacer(minLength: 8)
                Button(role: .destructive, action: cancel) {
                    Text("Cancel")
                }
                .buttonStyle(.wardCompact)
                .accessibilityIdentifier("cancelGeneration")
            }
            GenerationProgress(fraction: job.fraction)
        }
        .padding(14)
        .wardRaised(in: shape, lift: .high)
    }
}

/// How much is done, as the amber strip with the percentage beside it.
private struct GenerationProgress: View {
    let fraction: Double

    var body: some View {
        let scaled: Double = (fraction * 100).rounded()
        let percent: Int = Int(scaled)
        let shown: String = L10nFormat.percent(fraction, locale: L10n.locale)
        let spoken: String = "\(percent) percent done"
        HStack(spacing: WardSpace.s) {
            EcgStrip(progress: fraction)
            Text(shown)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.wardInk)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// What is being written, how many of how many, and about how long is left.
private struct GenerationLines: View {
    let job: GenerationCenter.Job

    private var counts: String {
        guard job.total > 0 else { return "Starting\u{2026}" }
        let left: Int = max(0, job.total - job.done)
        let done: String = "\(job.done) of \(job.total)"
        return "\(done) \u{00B7} \(left) left"
    }

    /// "~2 min left", "<1 min left"; nil until there is a pace to go on.
    private var timeLeft: String? {
        guard let seconds = job.secondsLeft() else { return nil }
        if seconds < 60 { return "<1 min left" }
        let minutes: Int = (seconds + 30) / 60
        return "~\(minutes) min left"
    }

    var body: some View {
        let counted: String = counts
        VStack(alignment: .leading, spacing: 2) {
            Text(job.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.wardInk)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(counted)
                if let timeLeft {
                    Text("\u{00B7} \(timeLeft)")
                }
            }
            .font(.system(.caption, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Color.wardInkSecondary)
            if let phase = job.phase {
                Text(phase).font(.caption2).foregroundStyle(Color.wardInkSecondary).lineLimit(1)
            }
        }
    }
}

/// The screen that generations started under here belong to: New set gives
/// everything in it one, so closing it stops only what it started.
private struct GenerationOwnerKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var generationOwner: UUID? {
        get { self[GenerationOwnerKey.self] }
        set { self[GenerationOwnerKey.self] = newValue }
    }
}

extension View {
    /// The generation card at the bottom of this screen. An inset rather than
    /// an overlay, so the rows under it can still be scrolled into view.
    func generationHUD() -> some View {
        // it floats over the rows, so no glow round it
        safeAreaInset(edge: .bottom, spacing: 0) { GenerationHUD().wardUnlit() }
    }
}
