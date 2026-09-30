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

    /// Starts showing a job. `onCancel` must cancel the work's Task and put
    /// the screen that started it back to idle; it runs on the main actor.
    @discardableResult
    func begin(_ title: String, total: Int, onCancel: @escaping () -> Void) -> UUID {
        // one job at a time: whatever was running is stopped, not orphaned
        // to finish later into a draft that has moved on
        if job != nil { cancel() }
        let id = UUID()
        job = Job(id: id, title: title, done: 0, total: total, phase: nil)
        stop = onCancel
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
        BackgroundWork.end(id, success: finished != nil)
        if let finished { AppNotifications.generationFinished(finished, body: title.map { "Done: \($0.lowercased())." } ?? "Done.") }
    }

    func cancel() {
        let stopping = stop
        if let id = job?.id { BackgroundWork.end(id, success: false) }
        job = nil
        stop = nil
        stopping?()
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

extension View {
    /// The generation card at the bottom of this screen. An inset rather than
    /// an overlay, so the rows under it can still be scrolled into view.
    func generationHUD() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { GenerationHUD() }
    }
}
