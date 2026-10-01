import SwiftUI

/// The one piece of generation running right now, shown as a floating card
/// with a ring for how much is done and a Cancel that really stops it.
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

        var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }
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
        job = Job(id: id, title: title, done: 0, total: total, phase: nil)
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

/// The floating card: a ring filling as the work gets done, what is being
/// written, how many of how many, and Cancel - the one way to stop it.
///
/// A floating glass slab standing out of the screen, at the bottom where the
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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        HStack(spacing: 16) {
            GenerationRing(fraction: job.fraction)
            GenerationLines(job: job)
            Spacer(minLength: 8)
            Button(role: .destructive, action: cancel) {
                Text("Cancel").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .hoverEffect(.highlight)
            .accessibilityIdentifier("cancelGeneration")
        }
        .padding(14)
        .liquidGlassPanel(cornerRadius: 20)
        .popOut(.floating, in: shape)
    }
}

/// How much is done, as a ring with the percentage in it.
private struct GenerationRing: View {
    let fraction: Double

    var body: some View {
        let scaled: Double = (fraction * 100).rounded()
        let percent: Int = Int(scaled)
        let shown: String = "\(percent)%"
        let spoken: String = "\(percent) percent done"
        let line = StrokeStyle(lineWidth: 6, lineCap: .round)
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.accentColor, style: line)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
            Text(shown)
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .frame(width: 52, height: 52)
        .accessibilityElement()
        .accessibilityLabel(spoken)
    }
}

/// What is being written, and how many of how many.
private struct GenerationLines: View {
    let job: GenerationCenter.Job

    private var counts: String {
        guard job.total > 0 else { return "Starting\u{2026}" }
        let left: Int = max(0, job.total - job.done)
        let done: String = "\(job.done) of \(job.total)"
        return "\(done) \u{00B7} \(left) left"
    }

    var body: some View {
        let counted: String = counts
        VStack(alignment: .leading, spacing: 2) {
            Text(job.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(counted)
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if let phase = job.phase {
                Text(phase).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
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
        safeAreaInset(edge: .bottom, spacing: 0) { GenerationHUD() }
    }
}
