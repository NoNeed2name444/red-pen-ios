// The force layout that places the notes in the classic Space map: the same
// notes always settle in the same shape whatever order they come in, centred
// on the origin, joined notes and folder-mates closer than the rest - and a
// layout the map no longer wants stops at once when its rebuild is cancelled,
// instead of running all its rounds for nothing (Chat-me audit row 114).
//
// Compiled with Features/Notes/ForceLayout3D.swift, which imports only
// Foundation.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "PASS " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func gap(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    let d: SIMD3<Float> = a - b
    return (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
}

/// The largest distance any note sits from where the other layout put it.
func drift(_ a: [UUID: SIMD3<Float>], _ b: [UUID: SIMD3<Float>]) -> Float {
    guard Set(a.keys) == Set(b.keys) else { return .infinity }
    var most: Float = 0
    for (id, p) in a { most = max(most, gap(p, b[id]!)) }
    return most
}

/// Ids that sort the same way every run, so a failure reads the same.
func ids(_ count: Int) -> [UUID] {
    (0..<count).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }
}

// MARK: F1 - the small cases

check("F1a no notes, no places", ForceLayout3D.layout(nodes: [], edges: [], groups: [:]).isEmpty)
let one: UUID = ids(1)[0]
let alone = ForceLayout3D.layout(nodes: [one], edges: [], groups: [:])
check("F1b one note sits at the centre", alone.count == 1 && alone[one] == SIMD3<Float>(0, 0, 0))
let twice = ForceLayout3D.layout(nodes: [one, one, one], edges: [(one, one)], groups: [:])
check("F1c a note named three times is placed once", twice.count == 1)

// MARK: F2 - the same notes, the same shape

// twelve notes: two folders of four, four loose; a ring of links in each
// folder, one link between the folders, a link to a note that is not there
let n: [UUID] = ids(12)
let folderA: UUID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000000")!
let folderB: UUID = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000000")!
var groups: [UUID: UUID] = [:]
for i in 0..<4 { groups[n[i]] = folderA }
for i in 4..<8 { groups[n[i]] = folderB }
let missing: UUID = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000")!
let edges: [(UUID, UUID)] = [(n[0], n[1]), (n[1], n[2]), (n[2], n[3]), (n[3], n[0]),
                             (n[4], n[5]), (n[5], n[6]), (n[6], n[7]), (n[7], n[4]),
                             (n[3], n[4]), (n[8], missing)]
let laid = ForceLayout3D.layout(nodes: n, edges: edges, groups: groups)
check("F2a every note is placed, and only those", Set(laid.keys) == Set(n))
let again = ForceLayout3D.layout(nodes: n, edges: edges, groups: groups)
check("F2b the same notes settle the same way", drift(laid, again) == 0, "\(drift(laid, again))")
let shuffled = ForceLayout3D.layout(nodes: n.reversed(), edges: edges, groups: groups)
check("F2c the order the notes come in does not matter", drift(laid, shuffled) == 0, "\(drift(laid, shuffled))")
let flipped = ForceLayout3D.layout(nodes: n, edges: edges.map { ($0.1, $0.0) }, groups: groups)
check("F2d nor which way round a link is given", drift(laid, flipped) < 0.001, "\(drift(laid, flipped))")
let doubled = ForceLayout3D.layout(nodes: n, edges: edges + edges, groups: groups)
check("F2e a link given twice pulls once", drift(laid, doubled) < 0.001, "\(drift(laid, doubled))")
let reseeded = ForceLayout3D.layout(nodes: n, edges: edges, groups: groups, seed: 7)
check("F2f another seed is another shape", drift(laid, reseeded) > 0.1, "\(drift(laid, reseeded))")

// MARK: F3 - where they settle

var middle = SIMD3<Float>(0, 0, 0)
for p in laid.values { middle += p }
middle /= Float(laid.count)
check("F3a centred on the origin", gap(middle, SIMD3<Float>(0, 0, 0)) < 0.001, "\(middle)")
check("F3b no two notes on top of each other",
      n.indices.allSatisfy { i in n.indices.allSatisfy { j in i == j || gap(laid[n[i]]!, laid[n[j]]!) > 0.05 } })

func meanGap(_ pairs: [(UUID, UUID)]) -> Float {
    pairs.map { gap(laid[$0.0]!, laid[$0.1]!) }.reduce(0, +) / Float(max(pairs.count, 1))
}
let joined: [(UUID, UUID)] = Array(edges.prefix(9))
var unjoined: [(UUID, UUID)] = []
for i in 0..<12 {
    for j in (i + 1)..<12 where !joined.contains(where: { ($0.0 == n[i] && $0.1 == n[j]) || ($0.0 == n[j] && $0.1 == n[i]) }) {
        unjoined.append((n[i], n[j]))
    }
}
check("F3c joined notes sit closer than the rest", meanGap(joined) < meanGap(unjoined),
      "\(meanGap(joined)) vs \(meanGap(unjoined))")
// folder-mates that are not linked (across each ring) against notes in
// different folders
let mates: [(UUID, UUID)] = [(n[0], n[2]), (n[1], n[3]), (n[4], n[6]), (n[5], n[7])]
var across: [(UUID, UUID)] = []
for i in 0..<4 { for j in 4..<8 { across.append((n[i], n[j])) } }
check("F3d a folder's notes gather", meanGap(mates) < meanGap(across), "\(meanGap(mates)) vs \(meanGap(across))")

// MARK: F4 - a layout the map no longer wants stops (audit row 114)

let unsettled = ForceLayout3D.layout(nodes: n, edges: edges, groups: groups, iterations: 0)
check("F4a the full layout moves the notes from where they start", drift(laid, unsettled) > 0.1,
      "\(drift(laid, unsettled))")
let stopped: [UUID: SIMD3<Float>] = await Task { () -> [UUID: SIMD3<Float>] in
    withUnsafeCurrentTask { $0?.cancel() }
    return ForceLayout3D.layout(nodes: n, edges: edges, groups: groups)
}.value
check("F4b a cancelled layout takes not one more step", drift(stopped, unsettled) == 0,
      "\(drift(stopped, unsettled))")
let kept: [UUID: SIMD3<Float>] = await Task { () -> [UUID: SIMD3<Float>] in
    ForceLayout3D.layout(nodes: n, edges: edges, groups: groups)
}.value
check("F4c a layout nobody cancels runs to the end, as before", drift(kept, laid) == 0, "\(drift(kept, laid))")

// the rebuild's off-main job: its answer comes back, and cancelling the
// rebuild that waits on it reaches the job
let answer: Int = await GraphWork.offMain { 41 + 1 }
check("F4d the off-main job's answer comes back", answer == 42)
let began = Date()
let rebuild = Task { () -> Bool in
    await GraphWork.offMain { () -> Bool in
        // a job that runs until it is told to stop (or 5 s pass)
        while !Task.isCancelled && Date().timeIntervalSince(began) < 5 {}
        return Task.isCancelled
    }
}
try? await Task.sleep(nanoseconds: 50_000_000)
rebuild.cancel()
let told: Bool = await rebuild.value
let took: Double = Date().timeIntervalSince(began)
check("F4e cancelling the rebuild cancels its off-main job", told && took < 4, "told \(told), \(took) s")
let early = Task { () -> Bool in
    withUnsafeCurrentTask { $0?.cancel() }
    return await GraphWork.offMain { Task.isCancelled }
}
let toldEarly: Bool = await early.value
check("F4f a rebuild cancelled before its job starts cancels it too", toldEarly)

// a bigger map asked for far more rounds than it could finish in minutes,
// cancelled a moment in: it stops within the round it is on
let big: [UUID] = ids(300)
let ring: [(UUID, UUID)] = (0..<300).map { (big[$0], big[($0 + 1) % 300]) }
let partStart = Date()
let part = Task { () -> Int in
    await GraphWork.offMain { ForceLayout3D.layout(nodes: big, edges: ring, groups: [:], iterations: 100_000).count }
}
try? await Task.sleep(nanoseconds: 50_000_000)
part.cancel()
let partCount: Int = await part.value
let partTook: Double = Date().timeIntervalSince(partStart)
check("F4g a long layout cancelled a moment in stops at once", partCount == 300 && partTook < 3,
      "\(partCount) notes, \(partTook) s")

print(failures.isEmpty ? "ALL PASSED" : "\(failures.count) FAILED: \(failures.joined(separator: ", "))")
exit(failures.isEmpty ? 0 : 1)
