// Crash and failure reports: nothing a student wrote can leave in one, the
// same problem is one fingerprint here and on the server, the queue keeps to
// its caps, and an unclean exit is told from a clean one.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func encoded(_ value: some Encodable) -> String {
    String(data: (try? JSONEncoder().encode(value)) ?? Data(), encoding: .utf8) ?? ""
}

let medical = "Patient Jane Doe, 34F, MRN 88231907, chest pain radiating to left arm; troponin 2.4 - jane.doe@uni.ac.uk /var/mobile/Containers/Data/Application/1B2C/Documents/notes.json token eyJhbGciOiJIUzI1NiJ9abcdefghijklmnop"
let leaks = ["Jane", "jane.doe", "88231907", "chest pain", "troponin", "/var/mobile", "eyJhbGciOiJIUzI1NiJ9"]

// MARK: scrubbing

check("a message must be a key, never a sentence",
      DiagScrub.messageKey("sync.failed") == "sync.failed" && DiagScrub.messageKey(medical) == nil
      && DiagScrub.messageKey("Chest pain") == nil)
check("an identifier must look like code",
      DiagScrub.identifier("NSRangeException") == "NSRangeException" && DiagScrub.identifier("chest pain") == nil)
check("a breadcrumb must be a name",
      DiagScrub.crumb("screen:library") == "screen:library" && DiagScrub.crumb("Jane Doe") == nil
      && DiagScrub.crumb("note:" + String(repeating: "x", count: 60)) == nil)
check("only a termination reason's namespace and code are kept",
      DiagScrub.termination("Namespace RUNNINGBOARD, Code 0xdead10cc Jane Doe /var/x/y") == "Namespace RUNNINGBOARD, Code 0xdead10cc"
      && DiagScrub.termination(medical) == nil)
if let cleaned = DiagScrub.clean(medical) {
    check("free text loses emails, paths, ids and tokens",
          !cleaned.contains("jane.doe@") && !cleaned.contains("/var/mobile") && !cleaned.contains("88231907")
          && !cleaned.contains("eyJhbGciOiJIUzI1NiJ9") && cleaned.contains("<email>") && cleaned.contains("<path>"), cleaned)
} else {
    check("free text is cleaned", false)
}

// an error whose payload is a server's reply about somebody's notes
enum FakeLLMError: Error, LocalizedError {
    case http(Int, String)
    case emptyReply
    var errorDescription: String? {
        switch self {
        case .http(let code, let text): return "\(code): \(text)"
        case .emptyReply: return "The model said nothing."
        }
    }
}
struct FakeStructError: Error, CustomStringConvertible { var description: String { medical } }
enum FakeDescribed: Error, CustomStringConvertible {
    case one
    var description: String { "chest pain in Jane Doe" }
}

let httpError = DiagScrub.error(FakeLLMError.http(502, medical))
check("an error with a payload keeps only its case name", httpError.name == "http", "\(httpError)")
check("an error with a payload keeps none of its text", !leaks.contains { encoded(httpError).contains($0) }, encoded(httpError))
check("a case without a payload keeps its name", DiagScrub.error(FakeLLMError.emptyReply).name == "emptyReply")
check("an error that describes itself is not read", !leaks.contains { encoded(DiagScrub.error(FakeStructError())).contains($0) })
check("nor an enum case that describes itself in a sentence", DiagScrub.error(FakeDescribed.one).name == nil)
let urlError = DiagScrub.error(NSError(domain: NSURLErrorDomain, code: -1001, userInfo: [NSLocalizedDescriptionKey: medical]))
check("an NSError keeps its domain and code, not its userInfo",
      urlError.domain == NSURLErrorDomain && urlError.code == -1001 && !encoded(urlError).contains("Jane"))

// a report built to leak, through every field
var leaky = DiagEvent(kind: .crash, area: .app, message: medical, at: 1_000)
leaky.exception = DiagException(type: 1, code: 0, signal: 11, name: "Jane Doe", className: "x@y.com", termination: medical)
leaky.error = DiagError(domain: "Patient Jane", code: 1, name: "chest pain")
leaky.breadcrumbs = [DiagCrumb(t: 2, s: "screen:library"), DiagCrumb(t: 1, s: "Jane Doe troponin")]
leaky.frames = [DiagFrame(b: "RedPen", u: "not a uuid", o: 1), DiagFrame(b: "Jane's notes; rm", u: nil, o: 2)]
let checkedLeak = DiagScrub.checked(leaky)
let leakJSON = encoded(checkedLeak)
check("a report built to leak keeps none of it", !leaks.contains { leakJSON.contains($0) } && !leakJSON.contains("x@y.com"), leakJSON)
check("its message becomes unknown", checkedLeak.message == "unknown")
check("its breadcrumbs keep only names", checkedLeak.breadcrumbs.map(\.s) == ["screen:library"])
check("its frames keep only binaries and UUIDs that look like them",
      checkedLeak.frames.count == 1 && checkedLeak.frames[0].u == nil)

// the whole path, through the center, with an error carrying medical text
let dir = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString)")
var on = true
let center = DiagnosticsCenter(folder: dir, enabled: { on })
var fakeNow = 1_760_000_000
center.clock = { fakeNow }
center.device = { DiagDevice(model: "iPhone17,3", os: "26.0.1", idiom: "phone", app: "1.2", build: "45", flavour: "testflight",
                             binary: "RedPen", memoryGB: 8, freeDiskGB: 52, thermal: "nominal", lowPower: false, graphics: "automatic") }
center.breadcrumb("screen:library")
center.breadcrumb("Jane Doe's lecture")
center.record(.error, area: .ai, message: "hosted.http_status", error: FakeLLMError.http(502, medical), code: 502)
let queuedJSON = encoded(center.batch())
check("a recorded failure keeps no medical text, email or path", !leaks.contains { queuedJSON.contains($0) }, queuedJSON)
check("and carries its trail", center.batch().first?.breadcrumbs.map(\.s) == ["screen:library", "fail:ai"],
      "\(center.batch().first?.breadcrumbs ?? [])")
center.record(.error, area: .ai, message: "hosted.http_status", error: CancellationError())
center.record(.error, area: .ai, message: "hosted.http_status", error: URLError(.notConnectedToInternet))
check("cancellation and no connection are not failures", center.batch().count == 1 && center.batch()[0].count == 1)
on = false
center.record(.error, area: .sync, message: "sync.failed")
check("nothing is recorded with reports turned off", center.batch().count == 1)
on = true

// MARK: fingerprints - the same vectors as server/tests/diagnostics.test.mjs

check("FNV-1a of nothing", DiagFingerprint.fnv1a64("") == "cbf29ce484222325")
check("FNV-1a of \"a\"", DiagFingerprint.fnv1a64("a") == "af63dc4c8601ec8c")
check("FNV-1a of a canonical failure", DiagFingerprint.fnv1a64("error|sync|sync.failed|NSURLErrorDomain|-1001||") == "d9020bac8713b2d5")
check("FNV-1a of a canonical crash", DiagFingerprint.fnv1a64("crash|t1:s11|RedPen+64,RedPen+c8") == "7f2398553371ac5f")

func crash(_ offset: UInt64) -> DiagEvent {
    var e = DiagEvent(kind: .crash, area: .app, message: "unknown", at: 5)
    e.exception = DiagException(type: 1, signal: 11)
    e.frames = [DiagFrame(b: "libsystem_kernel.dylib", u: nil, o: 5), DiagFrame(b: "RedPen", u: nil, o: offset),
                DiagFrame(b: "RedPen", u: nil, o: 200)]
    return e
}
check("a crash is known by its exception and its own frames (as the server)",
      DiagFingerprint.canonical(crash(100), binary: "RedPen") == "crash|t1:s11|RedPen+64,RedPen+c8",
      DiagFingerprint.canonical(crash(100), binary: "RedPen"))
var later = crash(100); later.at = 99; later.count = 7
check("the same crash, later, is the same fingerprint",
      DiagFingerprint.of(crash(100), binary: "RedPen") == DiagFingerprint.of(later, binary: "RedPen"))
check("a different place is a different crash",
      DiagFingerprint.of(crash(100), binary: "RedPen") != DiagFingerprint.of(crash(101), binary: "RedPen"))
var failure = DiagEvent(kind: .error, area: .sync, message: "sync.failed", at: 1)
failure.error = DiagError(domain: NSURLErrorDomain, code: -1001, name: nil)
check("a failure's canonical form matches the server's",
      DiagFingerprint.canonical(failure, binary: "RedPen") == "error|sync|sync.failed|NSURLErrorDomain|-1001||")
check("a crash has a readable title", DiagFingerprint.title(crash(100), binary: "RedPen") == "Crash: SIGSEGV at RedPen+0x64")

// MARK: the queue's caps

var box = DiagOutbox()
for i in 0..<5 {
    var e = failure
    e.id = UUID().uuidString
    e.at = 100 + i
    e.fingerprint = "same"
    box.add(e)
}
check("the same failure five times is one report counted five times", box.events.count == 1 && box.events[0].count == 5)
for i in 0..<70 {
    var e = failure
    e.id = UUID().uuidString
    e.at = 200 + i
    e.fingerprint = "f\(i)"
    box.add(e)
}
var fatal = crash(1)
fatal.at = 150
fatal.fingerprint = "crash"
box.add(fatal)
check("at most 60 wait", box.events.count == DiagOutbox.maxQueued, "\(box.events.count)")
check("a crash is kept over failures", box.events.contains { $0.fingerprint == "crash" })
let today = "2026-09-25"
var batch = box.batch(today: today)
check("at most 10 in one request, crashes first", batch.count == DiagOutbox.maxPerUpload && batch[0].kind == .crash)
var sentTotal = 0
for _ in 0..<10 {
    batch = box.batch(today: today)
    if batch.isEmpty { break }
    sentTotal += batch.count
    box.sent(batch.map(\.id), today: today)
}
check("at most 40 a day", sentTotal == DiagOutbox.maxPerDay && box.batch(today: today).isEmpty, "\(sentTotal)")
check("the next day sends again", !box.batch(today: "2026-09-26").isEmpty)
check("what was sent is kept to show", box.recent.count == DiagOutbox.recentKept)
box.prune(now: 400 + 15 * 86_400)
check("reports older than two weeks are dropped", box.events.isEmpty)
check("a build says it runs once a day", box.pingDue(today: today, build: "1.2 (45)"))
box.pinged(today: today, build: "1.2 (45)")
check("and not twice", !box.pingDue(today: today, build: "1.2 (45)") && box.pingDue(today: today, build: "1.2 (46)"))
check("days are UTC dates", DiagOutbox.dayString(1_760_000_000) == "2025-10-09", DiagOutbox.dayString(1_760_000_000))

var trail = DiagBreadcrumbs()
for i in 0..<80 { trail.add("screen:s\(i)", at: i) }
check("the trail keeps the last 50", trail.items.count == 50 && trail.items.first?.s == "screen:s30")
check("in seconds before the problem", trail.before(79).last?.t == 0 && trail.before(79).first?.t == 49)

// MARK: unclean exits

let cleanRun = DiagRunMarker(build: "1.2 (45)", startedAt: 10, activeSince: nil, crumbs: [DiagCrumb(t: 11, s: "screen:library")])
check("a run that went to the background ended cleanly", DiagRunMarker.uncleanExit(cleanRun, binary: "RedPen") == nil)
check("no marker, nothing to report", DiagRunMarker.uncleanExit(nil, binary: "RedPen") == nil)
let killed = DiagRunMarker(build: "1.2 (45)", startedAt: 10, activeSince: 20,
                           crumbs: [DiagCrumb(t: 21, s: "screen:library"), DiagCrumb(t: 30, s: "screen:graph3d")])
if let unclean = DiagRunMarker.uncleanExit(killed, binary: "RedPen") {
    check("a run still active when it ended is an unclean exit", unclean.kind == .unclean && unclean.at == 30)
    check("with the trail up to it", unclean.breadcrumbs.map(\.s) == ["screen:library", "screen:graph3d"] && unclean.breadcrumbs.first?.t == 9)
    check("named by where it happened", DiagFingerprint.title(unclean, binary: "RedPen") == "Unclean exit (killed or crashed) after screen:graph3d")
    var q = DiagOutbox()
    q.add(unclean)
    var real = crash(3)
    real.at = 40
    real.fingerprint = "c"
    q.add(real)
    check("MetricKit's crash report replaces the guess, keeping its trail",
          q.events.count == 1 && q.events[0].kind == .crash && q.events[0].breadcrumbs.count == 2)
} else {
    check("a run still active when it ended is an unclean exit", false)
}

// the marker on disk, across a pretend relaunch
center.launched(build: "1.2 (45)")
center.becameActive()
center.breadcrumb("screen:graph3d")
center.flushToDisk()
let relaunch = DiagnosticsCenter(folder: dir, enabled: { true })
relaunch.clock = { fakeNow + 60 }
relaunch.device = center.device
relaunch.launched(build: "1.2 (45)")
check("killed while active: the next launch reports it",
      relaunch.batch().contains { $0.kind == .unclean && $0.breadcrumbs.last?.s == "screen:graph3d" },
      "\(relaunch.batch().map(\.kind))")
relaunch.becameActive()
relaunch.wentBackground()
relaunch.flushToDisk()
let third = DiagnosticsCenter(folder: dir, enabled: { true })
third.device = center.device
let before = third.batch().filter { $0.kind == .unclean }.count
third.launched(build: "1.2 (45)")
check("left through the background: nothing more", third.batch().filter { $0.kind == .unclean }.count == before)

// killed during a foreground launch (the watchdog, before the first frame)
let slowDir = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString)")
let slow = DiagnosticsCenter(folder: slowDir, enabled: { true })
slow.device = center.device
slow.launched(build: "1.2 (45)", foreground: true)
slow.flushToDisk()
let afterSlow = DiagnosticsCenter(folder: slowDir, enabled: { true })
afterSlow.device = center.device
afterSlow.launched(build: "1.2 (45)")
check("a launch killed before it was on screen is reported", afterSlow.batch().contains { $0.kind == .unclean })
let bgDir = FileManager.default.temporaryDirectory.appendingPathComponent("diag-\(UUID().uuidString)")
let bg = DiagnosticsCenter(folder: bgDir, enabled: { true })
bg.device = center.device
bg.launched(build: "1.2 (45)", foreground: false)
bg.flushToDisk()
let afterBg = DiagnosticsCenter(folder: bgDir, enabled: { true })
afterBg.device = center.device
afterBg.launched(build: "1.2 (45)")
check("a background launch ended by iOS is not", afterBg.batch().isEmpty)
try? FileManager.default.removeItem(at: slowDir)
try? FileManager.default.removeItem(at: bgDir)

// MARK: MetricKit's call-stack JSON

let stackJSON = """
{"callStackPerThread":true,"callStacks":[
 {"threadAttributed":false,"callStackRootFrames":[{"binaryName":"UIKitCore","binaryUUID":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","offsetIntoBinaryTextSegment":1,"sampleCount":1}]},
 {"threadAttributed":true,"callStackRootFrames":[{"binaryName":"libsystem_kernel.dylib","binaryUUID":"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB","offsetIntoBinaryTextSegment":7,"sampleCount":1,
   "subFrames":[{"binaryName":"RedPen","binaryUUID":"247F0C11-9AF0-3D41-9C6A-3C6B0C9D2FB4","offsetIntoBinaryTextSegment":123456,"sampleCount":1,
     "subFrames":[{"binaryName":"RedPen","binaryUUID":"247F0C11-9AF0-3D41-9C6A-3C6B0C9D2FB4","offsetIntoBinaryTextSegment":200,"sampleCount":1}]}]}]}]}
"""
let frames = DiagCallStack.frames(fromJSON: Data(stackJSON.utf8))
check("the crashed thread's frames, innermost first",
      frames.map(\.b) == ["libsystem_kernel.dylib", "RedPen", "RedPen"] && frames[1].o == 123456, "\(frames)")
check("unreadable JSON is no frames", DiagCallStack.frames(fromJSON: Data("nope".utf8)).isEmpty)

// MARK: what goes over the wire

var wire = failure
wire.id = "x"
wire.fingerprint = "f"
let wireJSON = encoded(wire)
check("a report encodes with the server's field names",
      wireJSON.contains("\"kind\":\"error\"") && wireJSON.contains("\"area\":\"sync\"") && wireJSON.contains("\"message\":\"sync.failed\"")
      && wireJSON.contains("\"domain\":\"NSURLErrorDomain\""), wireJSON)
check("areas are the server's", DiagArea.allCases.map(\.rawValue).joined(separator: ",")
      == "app,ai,cloud_jobs,transcribe,voice,audio,sync,import,export,graph3d,metal,download,account,metrickit")

try? FileManager.default.removeItem(at: dir)
print(failures.isEmpty ? "\nALL DIAGNOSTICS TESTS PASS"
                       : "\n\(failures.count) DIAGNOSTICS TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
