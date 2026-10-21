// A shader check's answer is kept only when it can be trusted
// (GraphProbeMemo): when every shader passed, or when the app was in front,
// in the same visit, from the check's start to its end. A failure with the
// app away, or one the app left or came back during, is made again at the
// next build; the main thread never checks again while building, and never
// waits behind a running check once there is an answer (Chat-me audit row
// 112: one check made in the background used to leave the map plain until
// the app was quit).
//
// Compiled with Features/Notes/GraphProbeMemo.swift, which imports only
// Foundation off Apple's systems.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

/// A value several threads touch, behind a lock.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) { self.value = value }

    var get: T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ new: T) {
        lock.lock()
        value = new
        lock.unlock()
    }

    func change(_ edit: (inout T) -> Void) {
        lock.lock()
        edit(&value)
        lock.unlock()
    }
}

/// What the app does while a check runs.
enum Move {
    case stay
    case leave
    case arrive(Int)
}

/// The app's visit to the front (nil while away), which the checks read.
let front = Box<Int?>(nil)
/// Whether every shader passes the next check.
let passing = Box<Bool>(false)
/// What the app does once a check is under way.
let move = Box<Move>(.stay)
/// Set to hold the next check until it is signalled; `entered` says it began.
let hold = Box<DispatchSemaphore?>(nil)
let entered = DispatchSemaphore(value: 0)
/// Checks running now, and the most ever at once.
let inside = Box<Int>(0)
let most = Box<Int>(0)

func visit() -> Int? { front.get }

/// A fresh memo over the pretend check: "all" when every shader passes,
/// "some" when one fails.
func memo() -> GraphProbeMemo<String> {
    GraphProbeMemo<String> {
        inside.change { $0 += 1 }
        let now: Int = inside.get
        most.change { $0 = max($0, now) }
        switch move.get {
        case .stay: break
        case .leave: front.set(nil)
        case .arrive(let next): front.set(next)
        }
        if let wait = hold.get {
            entered.signal()
            wait.wait()
        }
        Thread.sleep(forTimeInterval: 0.002)
        let ok: Bool = passing.get
        inside.change { $0 -= 1 }
        return (ok ? "all" : "some", ok)
    }
}

/// Sets the scene for one check.
func set(front now: Int?, passing ok: Bool, move m: Move = .stay) {
    front.set(now)
    passing.set(ok)
    move.set(m)
}

// MARK: P1 - which answers are kept

do {
    let m = memo()
    set(front: nil, passing: true)
    let first: String = m.check(visit: visit)
    set(front: 1, passing: false)
    let second: String = m.check(visit: visit)
    check("P1a every shader passing is kept, even with the app away",
          first == "all" && second == "all" && m.runs == 1, "\(first) \(second) \(m.runs)")
}
do {
    let m = memo()
    set(front: 1, passing: false)
    let first: String = m.check(visit: visit)
    set(front: 1, passing: true)
    let second: String = m.check(visit: visit)
    check("P1b a failure with the app in front throughout is kept",
          first == "some" && second == "some" && m.runs == 1, "\(first) \(second) \(m.runs)")
}
do {
    let m = memo()
    set(front: nil, passing: false)
    let first: String = m.check(visit: visit)
    set(front: 2, passing: true)
    let second: String = m.check(visit: visit)
    check("P1c a failure with the app away is checked again at the next build",
          first == "some" && second == "all" && m.runs == 2, "\(first) \(second) \(m.runs)")
}
do {
    let m = memo()
    set(front: 1, passing: false, move: .leave)
    let first: String = m.check(visit: visit)
    set(front: 2, passing: true)
    let second: String = m.check(visit: visit)
    check("P1d a failure the app left during is not kept",
          first == "some" && second == "all" && m.runs == 2, "\(first) \(second) \(m.runs)")
}
do {
    let m = memo()
    set(front: nil, passing: false, move: .arrive(3))
    let first: String = m.check(visit: visit)
    set(front: 3, passing: true)
    let second: String = m.check(visit: visit)
    check("P1e a failure the app came back during is not kept",
          first == "some" && second == "all" && m.runs == 2, "\(first) \(second) \(m.runs)")
}
do {
    let m = memo()
    // in front at both ends, but away in between: another visit
    set(front: 4, passing: false, move: .arrive(5))
    let first: String = m.check(visit: visit)
    set(front: 5, passing: true)
    let second: String = m.check(visit: visit)
    check("P1f a failure the app left and came back during is not kept",
          first == "some" && second == "all" && m.runs == 2, "\(first) \(second) \(m.runs)")
}
do {
    let m = memo()
    set(front: nil, passing: false)
    _ = m.check(visit: visit)
    set(front: 6, passing: false)
    let second: String = m.check(visit: visit)
    set(front: 6, passing: true)
    let third: String = m.check(visit: visit)
    check("P1g a failure in front after one that was not kept is kept",
          second == "some" && third == "some" && m.runs == 2, "\(second) \(third) \(m.runs)")
}
do {
    let m = memo()
    set(front: nil, passing: false)
    _ = m.check(visit: visit)
    set(front: nil, passing: true)
    let second: String = m.check(visit: visit)
    set(front: nil, passing: false)
    let third: String = m.check(visit: visit)
    check("P1h a pass after a failure that was not kept is kept",
          second == "all" && third == "all" && m.runs == 2, "\(second) \(third) \(m.runs)")
}

// MARK: P2 - the main thread builds with the answer it has

do {
    let m = memo()
    set(front: nil, passing: false)
    _ = m.check(visit: visit)
    set(front: 7, passing: true)
    let built: String = m.latest(visit: visit)
    check("P2a building after a failure that was not kept uses it, without checking again",
          built == "some" && m.runs == 1, "\(built) \(m.runs)")
}
do {
    let m = memo()
    set(front: 7, passing: true)
    let first: String = m.latest(visit: visit)
    let second: String = m.latest(visit: visit)
    check("P2b building with no answer yet checks once", first == "all" && second == "all" && m.runs == 1,
          "\(first) \(second) \(m.runs)")
}
do {
    let m = memo()
    let fresh: Bool = m.unsure
    set(front: nil, passing: false)
    _ = m.check(visit: visit)
    let away: Bool = m.unsure
    set(front: 8, passing: false)
    _ = m.check(visit: visit)
    let settled: Bool = m.unsure
    check("P2c unsure: not before any check, yes after a failure not kept, no once kept",
          !fresh && away && !settled, "\(fresh) \(away) \(settled)")
}

// MARK: P3 - checks from many threads

do {
    let m = memo()
    set(front: 9, passing: true)
    let answers = Box<[String]>([])
    DispatchQueue.concurrentPerform(iterations: 8) { _ in
        let found: String = m.check(visit: visit)
        answers.change { $0.append(found) }
    }
    check("P3a eight builds at once run one check", m.runs == 1 && answers.get == Array(repeating: "all", count: 8),
          "\(m.runs) \(answers.get)")
}
do {
    let m = memo()
    most.set(0)
    set(front: nil, passing: false)
    DispatchQueue.concurrentPerform(iterations: 8) { _ in _ = m.check(visit: visit) }
    check("P3b checks never overlap, even when none is kept", m.runs == 8 && most.get == 1,
          "\(m.runs) runs, \(most.get) at once")
}
do {
    // the launch's check, held while the app arrives: the arrival must not
    // build the map again (the build that made the check looks when it ends)
    let m = memo()
    set(front: nil, passing: true, move: .arrive(10))
    let release = DispatchSemaphore(value: 0)
    hold.set(release)
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        _ = m.check(visit: visit)
        done.signal()
    }
    let began: Bool = entered.wait(timeout: .now() + 5) == .success
    let seen = Box<Bool?>(nil)
    let answered = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        seen.set(m.unsure)
        answered.signal()
    }
    let quick: Bool = answered.wait(timeout: .now() + 2) == .success
    hold.set(nil)
    release.signal()
    let finished: Bool = done.wait(timeout: .now() + 5) == .success
    _ = answered.wait(timeout: .now() + 5)
    check("P3c a check still running is not unsure, reading that never waits for it, and a pass is kept",
          began && quick && seen.get == false && finished && !m.unsure,
          "began \(began), quick \(quick), seen \(String(describing: seen.get)), after \(m.unsure)")
}
do {
    let m = memo()
    set(front: nil, passing: false)
    _ = m.check(visit: visit)
    // a second check, held while it runs
    let release = DispatchSemaphore(value: 0)
    hold.set(release)
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        _ = m.check(visit: visit)
        done.signal()
    }
    let began: Bool = entered.wait(timeout: .now() + 5) == .success
    let seen = Box<String?>(nil)
    let answered = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        seen.set(m.latest(visit: visit))
        answered.signal()
    }
    let quick: Bool = answered.wait(timeout: .now() + 2) == .success
    hold.set(nil)
    release.signal()
    let finished: Bool = done.wait(timeout: .now() + 5) == .success
    _ = answered.wait(timeout: .now() + 5)
    check("P3d building never waits behind a running check once there is an answer",
          began && quick && seen.get == "some" && finished, "began \(began), quick \(quick), \(seen.get ?? "nil")")
}

// MARK: P4 - the app's visits to the front

do {
    let app = GraphForeground()
    let unwatched: Int? = app.visit
    app.arrive()
    let first: Int? = app.visit
    app.arrive()
    let again: Int? = app.visit
    app.leave()
    let away: Int? = app.visit
    app.leave()
    app.arrive()
    let next: Int? = app.visit
    check("P4a away until told otherwise", unwatched == nil)
    check("P4b arriving starts a visit; arriving again is the same one", first == 1 && again == 1,
          "\(String(describing: first)) \(String(describing: again))")
    check("P4c leaving ends it; the next arrival is a new visit, however many leavings",
          away == nil && next == 2, "\(String(describing: away)) \(String(describing: next))")
}

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED: \(failures.joined(separator: ", "))")
exit(failures.isEmpty ? 0 : 1)
