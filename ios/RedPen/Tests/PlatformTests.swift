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

let roundTrip: [AppLink] = [.reviewDue, .openSet(someID), .quiz(subject: "Renal medicine"),
                            .search("a b"), .newSet, .examPlan]
for one in roundTrip {
    check("round trip \(one)", AppLink.parse(one.url) == one, one.url.absoluteString)
}

// MARK: subjects

check("folded drops case, accents and punctuation",
      SubjectMatch.folded("  Cardiología: Heart-Failure! ") == "cardiologia heart failure",
      SubjectMatch.folded("  Cardiología: Heart-Failure! "))
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

if failures.isEmpty {
    print("all platform checks passed")
} else {
    print("\(failures.count) FAILED")
    exit(1)
}
