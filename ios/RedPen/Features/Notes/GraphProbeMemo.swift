import Foundation
#if canImport(UIKit)
import UIKit
#endif

// Keeping the answer of a shader check (GraphShaderProbe, GraphStyleProbe,
// NeuronProbe), but only an answer that can be trusted.
//
// Each check draws its shaders in a tiny offscreen render. With the app
// away, iOS refuses work on the graphics chip, so every shader seems to
// fail, and the answer used to be kept for the life of the process: one
// check made in the background left the map plain until the app was quit
// (Chat-me audit row 112: "Cache only when the app is active at probe
// time"). Now a check is kept when every shader passed, or when the app was
// in front, in the same visit, from its start to its end; any other is used
// for the build it was made for and made again for the next one.
//
// Foundation only, so it is tested on Linux; the part that follows the app
// in and out of front (GraphForeground.watch) is UIKit's.

/// One shader check's answer, kept once it can be trusted. Safe from any
/// thread; one check runs at a time.
nonisolated final class GraphProbeMemo<Value: Sendable>: @unchecked Sendable {
    /// One check at a time.
    private let gate = NSLock()
    /// Guards what is below; held only for a moment, never across a check.
    private let lock = NSLock()
    /// The check: what it found, and whether every shader passed.
    private let work: @Sendable () -> (Value, Bool)
    private var last: Value?
    private var kept: Bool = false
    /// How many checks have run; the tests read it.
    private var count: Int = 0

    init(_ work: @escaping @Sendable () -> (Value, Bool)) {
        self.work = work
    }

    var runs: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    /// Whether the last answer was not kept: some shader failed with the
    /// app away, or as it came or went. The map checks again once the app is
    /// in front (Graph3DView). A check still running does not count: the
    /// build waiting for it looks again when it ends, so the app's arrival
    /// at launch, mid-check, does not build the map twice. Never waits for a
    /// running check.
    var unsure: Bool {
        lock.lock()
        defer { lock.unlock() }
        return last != nil && !kept
    }

    /// The kept answer, or a fresh check: off the main thread, before a
    /// build. `visit` is the app's current visit to the front (nil while it
    /// is away): GraphForeground.visit.
    func check(visit: () -> Int?) -> Value {
        gate.lock()
        defer { gate.unlock() }
        if let found = answer(keptOnly: true) { return found }
        return run(visit: visit)
    }

    /// The last answer, kept or not, without checking again: the main
    /// thread, building with the answer its check just gave. It never waits
    /// for a check that is running unless there is no answer at all.
    func latest(visit: () -> Int?) -> Value {
        if let found = answer(keptOnly: false) { return found }
        gate.lock()
        defer { gate.unlock() }
        if let found = answer(keptOnly: false) { return found }
        return run(visit: visit)
    }

    private func answer(keptOnly: Bool) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return kept || !keptOnly ? last : nil
    }

    /// Runs the check; the gate is held.
    private func run(visit: () -> Int?) -> Value {
        let before: Int? = visit()
        let (found, whole) = work()
        let after: Int? = visit()
        lock.lock()
        count += 1
        last = found
        kept = whole || (before != nil && before == after)
        lock.unlock()
        return found
    }
}

/// Whether the app is in front, as a count of its visits there: a check
/// that starts and ends in the same visit ran in front throughout, even if
/// it took seconds. Safe from any thread.
nonisolated final class GraphForeground: @unchecked Sendable {
    static let shared = GraphForeground()

    private let lock = NSLock()
    private var current: Int?
    private var visits: Int = 0
    /// Set by watch, on the main thread only.
    private var watching: Bool = false

    /// The app's current visit to the front, or nil while it is away (and
    /// before anything watches: a check made then is not kept unless it
    /// passed).
    var visit: Int? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    /// The app came to the front; a second arrival without a leaving is the
    /// same visit.
    func arrive() {
        lock.lock()
        defer { lock.unlock() }
        if current == nil {
            visits += 1
            current = visits
        }
    }

    /// The app is no longer in front.
    func leave() {
        lock.lock()
        defer { lock.unlock() }
        current = nil
    }
}

#if canImport(UIKit)
extension GraphForeground {
    /// Follows the app in and out of the front from now on: Graph3DView
    /// calls it before each build, and only the first call does anything.
    /// Inactive counts as away, as the audit asks.
    @MainActor func watch() {
        guard !watching else { return }
        watching = true
        let center = NotificationCenter.default
        _ = center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                               queue: nil) { [weak self] _ in self?.arrive() }
        let away: [Notification.Name] = [UIApplication.willResignActiveNotification,
                                         UIApplication.didEnterBackgroundNotification]
        for name in away {
            _ = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.leave() }
        }
        if UIApplication.shared.applicationState == .active {
            arrive()
        } else {
            leave()
        }
    }
}
#endif
