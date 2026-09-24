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
        }
    }

    func end(_ id: UUID) {
        guard job?.id == id else { return }
        job = nil
        stop = nil
    }

    func cancel() {
        let stopping = stop
        job = nil
        stop = nil
        stopping?()
    }
}

/// The floating card: a ring filling as the work gets done, what is being
/// written, how many of how many, and Cancel.
struct GenerationHUD: View {
    @ObservedObject private var center = GenerationCenter.shared

    var body: some View {
        ZStack {
            if let job = center.job { card(job) }
        }
        .animation(.spring(duration: 0.3), value: center.job?.id)
    }

    private func card(_ job: GenerationCenter.Job) -> some View {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: job.fraction)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.4), value: job.fraction)
                    Text("\(Int((job.fraction * 100).rounded()))%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
                .frame(width: 52, height: 52)
                .accessibilityElement()
                .accessibilityLabel("\(Int((job.fraction * 100).rounded())) percent done")

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(job.total > 0 ? "\(job.done) of \(job.total) \u{00B7} \(max(0, job.total - job.done)) left"
                                       : "Starting\u{2026}")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    if let phase = job.phase {
                        Text(phase).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Button(role: .destructive) { center.cancel() } label: {
                    Text("Cancel").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("cancelGeneration")
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: 520)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    /// The generation card at the bottom of this screen. An inset rather than
    /// an overlay, so the rows under it can still be scrolled into view.
    func generationHUD() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { GenerationHUD() }
    }
}
