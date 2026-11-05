// The platform lane's decisions: which links the app routes (and which it
// must leave alone - the sign-in return), what a spoken subject means, what
// kind of file arrived, the digest the widgets read, and the age signal.
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func link(_ text: String) -> AppLink? {
    guard let url = URL(string: text) else { return nil }
    return AppLink.parse(url)
}

// MARK: links

let someID = UUID()
check("due link", link("redpen://due") == .reviewDue)
check("stethoscore scheme too", link("stethoscore://review") == .reviewDue)
check("set link by path", link("redpen://set/\(someID.uuidString)") == .openSet(someID))
check("set link by query", link("redpen://open?id=\(someID.uuidString)") == .openSet(someID))
check("bad set id is not routed", link("redpen://set/not-a-uuid") == nil)
check("quiz link", link("redpen://quiz?subject=cardiology") == .quiz(subject: "cardiology"))
check("quiz with spaces", link("redpen://quiz?subject=Infectious%20diseases") == .quiz(subject: "Infectious diseases"))
check("quiz without a subject is not routed", link("redpen://quiz") == nil)
check("sign-in return is never routed", link("redpen://auth?code=abc") == nil)
check("other schemes are ignored", link("https://example.com/due") == nil)
check("unknown host is ignored", link("redpen://somewhere") == nil)
check("search link", link("redpen://search?q=murmur") == .search("murmur"))
check("new set link", link("redpen://new") == .newSet)
check("exam link", link("redpen://exam") == .examPlan)
let savedFrom = NoteSource(kind: .question, setID: someID, itemID: UUID(), setName: "Cardiology")
check("item link", link(savedFrom.url.absoluteString) == .openItem(savedFrom))
check("item link on the old scheme",
      link("redpen://item/card/\(someID.uuidString)/-") == .openItem(NoteSource(kind: .card, setID: someID)))
check("item link without a set is not routed", link("redpen://item/card") == nil)

let roundTrip: [AppLink] = [.reviewDue, .openSet(someID), .quiz(subject: "Renal medicine"),
                            .search("a b"), .newSet, .examPlan, .openItem(savedFrom)]
for one in roundTrip {
    check("round trip \(one)", AppLink.parse(one.url) == one, one.url.absoluteString)
}

// MARK: subjects

check("folded drops case, accents and punctuation",
      SubjectMatch.folded("  Cardiología: Heart-Failure! ") == "cardiologia heart failure",
      SubjectMatch.folded("  Cardiología: Heart-Failure! "))
do {
    let a = UUID(), b = UUID(), c = UUID()
    // A run that was cancelled never confirmed b's rename or c's removal, so
    // the next run still sends both.
    let plan = SpotlightPlan.diff(confirmed: [a: "A|mcq|3", b: "B|mcq|2", c: "C|anki|9"],
                                  now: [a: "A|mcq|3", b: "B2|mcq|2"])
    check("spotlight resends unconfirmed changes", plan.changed == [b] && plan.gone == [c])
    check("spotlight nothing to do", SpotlightPlan.diff(confirmed: [a: "x"], now: [a: "x"]).changed.isEmpty)
}
check("alias cardio", SubjectMatch.score(query: "cardio", candidate: "Cardiology") == 3)
check("alias heart", SubjectMatch.score(query: "heart", candidate: "cardiology") == 3)
check("US and UK spelling", SubjectMatch.score(query: "pediatrics", candidate: "Paediatrics") == 3)
check("word of a longer name", SubjectMatch.score(query: "renal", candidate: "Renal physiology") >= 2)
check("prefix", SubjectMatch.score(query: "cardiol", candidate: "Cardiology") == 2)
check("contained", SubjectMatch.score(query: "ology", candidate: "Cardiology") == 1)
check("unrelated", SubjectMatch.score(query: "neurology", candidate: "Cardiology") == 0)
check("empty never matches", SubjectMatch.score(query: "", candidate: "Cardiology") == 0)
check("best of several names",
      SubjectMatch.score(query: "renal", names: ["General", "Week 4", "Renal"]) == 3)
let subjects = SubjectMatch.distinctSubjects(["Cardiology", "cardiology ", "Renal", "Cardiology", "", "Neuro"])
check("distinct subjects, busiest first", subjects == ["Cardiology", "Renal", "Neuro"], "\(subjects)")

// MARK: files

check("apkg", ImportKind.of(fileName: "AnKing.apkg") == .ankiDeck)
check("colpkg", ImportKind.of(fileName: "collection.COLPKG") == .ankiCollection)
check("csv", ImportKind.of(fileName: "quizlet.csv") == .csv)
check("tsv", ImportKind.of(fileName: "quizlet.tsv") == .tsv)
check("our set", ImportKind.of(fileName: "Renal.stethoscore") == .studySet)
check("our backup", ImportKind.of(fileName: "Library.stethoscorebackup") == .backup)
check("pdf is a lecture", ImportKind.of(fileName: "lecture.pdf") == .lecture)
check("unknown", ImportKind.of(fileName: "thing.xyz") == .unknown)
let zipHead = Data([0x50, 0x4B, 0x03, 0x04])
let jsonHead = Data("\u{FEFF}  {\"name\":".utf8)
check("a .stethoscore that is a zip is a backup",
      ImportKind.of(fileName: "x.stethoscore", head: zipHead) == .backup)
check("a .stethoscore that is JSON is a set",
      ImportKind.of(fileName: "x.stethoscore", head: jsonHead) == .studySet)
check("a .json array is not a set", ImportKind.of(fileName: "x.json", head: Data("[1]".utf8)) == .unknown)
var backupHead = Data([0x50, 0x4B, 0x03, 0x04])
backupHead.append(Data(repeating: 0, count: 22))
backupHead.append(contentsOf: [13, 0, 0, 0])
backupHead.append(Data("manifest.json".utf8))
var otherHead = Data([0x50, 0x4B, 0x03, 0x04])
otherHead.append(Data(repeating: 0, count: 22))
otherHead.append(contentsOf: [9, 0, 0, 0])
otherHead.append(Data("photo.jpg".utf8))
check("a .zip whose first entry is the manifest is a backup",
      ImportKind.of(fileName: "Backup.zip", head: backupHead) == .backup)
check("any other .zip is not a backup", ImportKind.of(fileName: "Photos.zip", head: otherHead) == .unknown
      && ImportKind.of(fileName: "Backup.zip", head: zipHead) == .unknown)
check("the head read is long enough for the manifest's name", ImportKind.headLength >= 30 + 13)
check("an apkg stays an apkg", ImportKind.of(fileName: "d.apkg", head: zipHead) == .ankiDeck)
check("study data vs other", ImportKind.ankiDeck.isStudyData && !ImportKind.lecture.isStudyData)

// MARK: the digest

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!
let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13 UTC
let a = UUID()
let b = UUID()
let c = UUID()
let d = UUID()
var due: [(id: UUID, name: String)] = []
for _ in 0..<5 { due.append((a, "Cardiology")) }
for _ in 0..<2 { due.append((b, "Renal")) }
for _ in 0..<7 { due.append((c, "Neuro")) }
due.append((d, "Derm"))
let exam = now.addingTimeInterval(10 * 86_400)
let digest = GlanceDigest.make(now: now, due: due, nextDue: nil, examName: "PLAB 1",
                               examDate: exam, today: 12, streak: 4)
check("due is every card", digest.dueNow == 15)
check("busiest three decks", digest.topDecks.map(\.name) == ["Neuro", "Cardiology", "Renal"],
      "\(digest.topDecks.map(\.name))")
check("days to exam", digest.daysToExam(now: now, calendar: cal) == 10)
check("exam day is 0", digest.daysToExam(now: exam, calendar: cal) == 0)
let past = GlanceDigest.make(now: now, due: [], nextDue: nil, examName: "Old",
                             examDate: now.addingTimeInterval(-3 * 86_400), today: 0, streak: 0)
check("a past exam is dropped", past.examDate == nil && past.examName == nil)

let later = GlanceDigest.make(now: now.addingTimeInterval(60), due: due, nextDue: nil, examName: "PLAB 1",
                              examDate: exam, today: 12, streak: 4)
check("same content ignores when", digest.sameContent(as: later) && digest != later)
var changed = later
changed.today = 13
check("a new count is new content", !digest.sameContent(as: changed))

check("today reads 0 the next day", digest.todayShown(at: now.addingTimeInterval(86_400), calendar: cal) == 0)
check("today on the day", digest.todayShown(at: now, calendar: cal) == 12)
check("streak alive the next day", digest.streakShown(at: now.addingTimeInterval(86_400), calendar: cal) == 4)
check("streak gone after two days", digest.streakShown(at: now.addingTimeInterval(2 * 86_400), calendar: cal) == 0)
var withNext = digest
withNext.dueNow = 0
withNext.nextDue = now.addingTimeInterval(3600)
check("nothing due before the next card", withNext.dueShown(at: now) == 0)
check("at least one after it", withNext.dueShown(at: now.addingTimeInterval(7200)) == 1)

let data = try! GlanceShelf.encoder.encode(digest)
check("digest round trip", GlanceShelf.decode(data) == digest)
var future = digest
future.version = GlanceDigest.currentVersion + 1
let futureData = try! GlanceShelf.encoder.encode(future)
check("a newer file is not misread", GlanceShelf.decode(futureData) == nil)
check("garbage is nothing", GlanceShelf.decode(Data("nope".utf8)) == nil)

// MARK: the digest's goal and home's exam name (widget slice 2)

let goalDigest = GlanceDigest.make(now: now, due: due, nextDue: nil, examName: "Step 1",
                                   examDate: exam, today: 32, streak: 4, goal: 80)
check("the goal is kept", goalDigest.goal == 80 && goalDigest.goalShown == 80)
let goalData = try! GlanceShelf.encoder.encode(goalDigest)
let goalJSON = String(decoding: goalData, as: UTF8.self)
check("the goal's key is Android's", goalJSON.contains("\"goal\":80"), goalJSON)
check("a file with a goal round-trips", GlanceShelf.decode(goalData) == goalDigest)
check("a goal does not change the version", goalDigest.version == 1 && GlanceDigest.currentVersion == 1)
check("no goal, no key", !String(decoding: data, as: UTF8.self).contains("\"goal\""))
let oldFile = """
{"dueNow":3,"examDate":"2023-11-24T22:13:20Z","examName":"PLAB 1","madeAt":"2023-11-14T22:13:20Z",\
"streak":4,"today":12,"topDecks":[],"version":1}
"""
let oldDigest: GlanceDigest? = GlanceShelf.decode(Data(oldFile.utf8))
check("an old file without a goal still decodes", oldDigest != nil && oldDigest?.goal == nil && oldDigest?.today == 12)
check("an old file's goal is the default 50", oldDigest?.goalShown == 50)
var odd = goalDigest
odd.goal = 0
check("a zero goal reads as 50", odd.goalShown == 50)
odd.goal = 5
check("a goal under the range is raised to it", odd.goalShown == 10)
odd.goal = 1000
check("a goal over the range is lowered to it", odd.goalShown == 300)
/// The fields an older widget's GlanceDigest decoded, before `goal`.
struct OlderDigest: Codable {
    var version: Int
    var madeAt: Date
    var dueNow: Int
    var topDecks: [GlanceDigest.DueDeck]
    var nextDue: Date?
    var examName: String?
    var examDate: Date?
    var today: Int
    var streak: Int
}
let olderRead: OlderDigest? = try? GlanceShelf.decoder.decode(OlderDigest.self, from: goalData)
check("an older widget still reads a file with a goal", olderRead?.today == 32 && olderRead?.version == 1)
let finals = GlanceDigest.make(now: now, due: [], nextDue: nil, examName: nil, examDate: exam,
                               today: 0, streak: 0, goal: 50)
check("no chosen exam keeps no name, so the widget says finals as home does",
      finals.examName == nil && finals.examDate == exam)
check("home's name is stored as given", goalDigest.examName == "Step 1")

// MARK: the medium widget's deck rows (D4)

let deckID = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
check("a deck row links to redpen://set/<id>",
      AppLink.openSet(deckID).url.absoluteString == "redpen://set/6F9619FF-8B86-D011-B42D-00C04FC964FF",
      AppLink.openSet(deckID).url.absoluteString)
check("the deck row's link opens that deck", AppLink.parse(AppLink.openSet(deckID).url) == .openSet(deckID))

// MARK: what a widget says (T0192): no file is not "nothing due"

check("no file is its own state", GlanceState.of(nil, at: now) == .noFile)
var caughtUp = digest
caughtUp.dueNow = 0
caughtUp.nextDue = nil
check("a file with nothing due", GlanceState.of(caughtUp, at: now) == .nothingDue)
check("a file with cards due", GlanceState.of(digest, at: now) == .due(15))
check("an empty digest read from a file is nothing due, not no file",
      GlanceState.of(.empty, at: now) == .nothingDue)
var comingDue = caughtUp
comingDue.nextDue = now.addingTimeInterval(3600)
check("a card come due since the file was written counts",
      GlanceState.of(comingDue, at: now.addingTimeInterval(7200)) == .due(1))
check("the three states differ",
      GlanceState.noFile != .nothingDue && GlanceState.nothingDue != .due(0) && GlanceState.noFile != .due(0))

// MARK: can the widgets read the app's file (T0192)

let group = "group.example.shared"
let box = URL(fileURLWithPath: "/tmp/glance-check")
check("no group named", GlanceShelfCheck.evaluate(groupID: nil, container: box, fileExists: true, data: data) == .noGroup)
check("the group's container does not open",
      GlanceShelfCheck.evaluate(groupID: group, container: nil, fileExists: false, data: nil) == .noContainer)
check("no file in the container",
      GlanceShelfCheck.evaluate(groupID: group, container: box, fileExists: false, data: nil) == .noFile)
check("a file that cannot be opened",
      GlanceShelfCheck.evaluate(groupID: group, container: box, fileExists: true, data: nil) == .unreadable)
check("a file that does not decode",
      GlanceShelfCheck.evaluate(groupID: group, container: box, fileExists: true, data: Data("nope".utf8)) == .unreadable)
check("a newer app's file is unreadable",
      GlanceShelfCheck.evaluate(groupID: group, container: box, fileExists: true, data: futureData) == .unreadable)
let readable = GlanceShelfCheck.evaluate(groupID: group, container: box, fileExists: true, data: data)
check("a readable file", readable == .ready && readable.widgetsCanRead)
check("only ready means yes",
      [GlanceShelfCheck.noGroup, .noContainer, .noFile, .unreadable].allSatisfy { !$0.widgetsCanRead })
#if !canImport(Darwin)
check("off Apple platforms there is no shared container", GlanceShelf.sharedContainer == nil
      && GlanceShelf.readShared() == nil)
#endif

// MARK: exam-day window

var dayCal = Calendar(identifier: .gregorian)
dayCal.timeZone = TimeZone(identifier: "UTC")!
let examMidnight = dayCal.date(from: DateComponents(year: 2026, month: 10, day: 12))!
let examAtNine = dayCal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 9))!
let evening = dayCal.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 18, minute: 30))!
let afternoon = dayCal.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 15))!
let lateOnDay = dayCal.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 23, minute: 59))!
let dayAfter = dayCal.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 0, minute: 1))!
check("window opens the evening before", ExamDayWindow.contains(evening, exam: examMidnight, calendar: dayCal))
check("not that afternoon", !ExamDayWindow.contains(afternoon, exam: examMidnight, calendar: dayCal))
check("still on late in the day", ExamDayWindow.contains(lateOnDay, exam: examAtNine, calendar: dayCal))
check("over the next day", !ExamDayWindow.contains(dayAfter, exam: examAtNine, calendar: dayCal))
check("a date alone has no start time", ExamDayWindow.startsAt(exam: examMidnight, calendar: dayCal) == nil)
check("a time is the start", ExamDayWindow.startsAt(exam: examAtNine, calendar: dayCal) == examAtNine)

// MARK: age signal

check("declined says nothing", AgeSignal.from(lowerBound: 18, upperBound: nil, declined: true) == .unknown)
check("under 13 is a minor", AgeSignal.from(lowerBound: nil, upperBound: 12, declined: false) == .minor)
check("16 to 17 is a minor", AgeSignal.from(lowerBound: 16, upperBound: 17, declined: false) == .minor)
check("18 and over is an adult", AgeSignal.from(lowerBound: 18, upperBound: nil, declined: false) == .adult)
check("no ends known says nothing", AgeSignal.from(lowerBound: nil, upperBound: nil, declined: false) == .unknown)
check("only a minor loses community", !AgeSignal.minor.allowsCommunity
      && AgeSignal.adult.allowsCommunity && AgeSignal.unknown.allowsCommunity)

// MARK: app lock (audit #8)

check("a locked app asks on return", AppLockRule.asksOnReturn(locked: true, cancelled: false))
check("not again after a cancel", !AppLockRule.asksOnReturn(locked: true, cancelled: true))
check("an open app never asks", !AppLockRule.asksOnReturn(locked: false, cancelled: false))

// MARK: files before the library (audit #3)

check("a file waits out the sign-in screen", !AppLink.fileToInbox(previewRegistered: false, libraryOnScreen: false))
check("with the library up and no preview, the inbox", AppLink.fileToInbox(previewRegistered: false, libraryOnScreen: true))
check("a preview takes it", !AppLink.fileToInbox(previewRegistered: true, libraryOnScreen: true))

// MARK: notification links (audit #7)

let readySet = UUID()
check("the review reminder opens the due cards",
      AppLink.fromNotification([AppLink.notificationKey: AppLink.reviewDue.url.absoluteString]) == .reviewDue)
check("a ready set opens that set",
      AppLink.fromNotification([AppLink.notificationKey: AppLink.openSet(readySet).url.absoluteString]) == .openSet(readySet))
check("no link, nowhere", AppLink.fromNotification(["kind": "qotd"]) == nil)
check("a foreign link is not followed", AppLink.fromNotification([AppLink.notificationKey: "https://example.com"]) == nil)

if failures.isEmpty {
    print("all platform checks passed")
} else {
    print("\(failures.count) FAILED")
    exit(1)
}
