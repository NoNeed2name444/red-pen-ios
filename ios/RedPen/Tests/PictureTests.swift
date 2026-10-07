// Pictures travel with the questions and cards that show them: the Mistakes
// set (audit #20), combined sets and books (audit #19), and an imported
// card's picture on the side of the card it came from (audit #14).
import Foundation

var failures: [String] = []

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "ok   " : "FAIL ") + label + (ok ? "" : "  | " + detail))
    if !ok { failures.append(label) }
}

func question(_ stem: String, picture: Int? = nil) -> MCQQuestion {
    var q = MCQQuestion(stem: stem, options: ["a", "b", "c", "d"], correctIndex: 0, explanation: "")
    q.imageIndex = picture
    return q
}

// MARK: the Mistakes set brings each question's picture
var practised = StudySet(name: "Cardiology", kind: .mcq)
practised.images = ["ECG-0", "ECG-1", "XRAY-2"]
practised.questions = [question("rhythm?", picture: 1), question("film?", picture: 2), question("plain?")]
practised.sources = [SourceDoc(name: "Lecture 3")]
var mistakes = StudySet(name: "Mistakes \u{2013} Cardiology", kind: .mcq)
mistakes.addMistakes([practised.questions[0], practised.questions[2]], from: practised)
check("a missed question keeps its picture",
      mistakes.questions.first?.imageIndex.map { mistakes.images[$0] } == "ECG-1", "\(mistakes.images)")
check("one without a picture stays without", mistakes.questions.last?.imageIndex == nil)
check("only the pictures needed are copied", mistakes.images == ["ECG-1"])
check("the lecture comes along, so citations still open", mistakes.sources.map(\.name) == ["Lecture 3"])
mistakes.addMistakes([practised.questions[0], practised.questions[1]], from: practised)
check("a top-up adds only new questions", mistakes.questions.map(\.stem) == ["rhythm?", "plain?", "film?"])
check("and a picture already here is not copied again", mistakes.images == ["ECG-1", "XRAY-2"], "\(mistakes.images)")
check("the new question points at its own picture",
      mistakes.questions.last?.imageIndex.map { mistakes.images[$0] } == "XRAY-2")
check("and the lecture is not listed twice", mistakes.sources.count == 1)
var other = StudySet(name: "x", kind: .mcq)
check("a picture index past the end carries nothing", other.carryPicture(9, from: practised) == nil && other.images.isEmpty)

// MARK: combining sets re-bases every picture, books included
var bookA = StudySet(name: "A", kind: .book)
bookA.images = ["A0", "A1"]
bookA.bookMarkdown = "# Heart\n![The valves](image:1)\nText."
bookA.sources = [SourceDoc(name: "Heart lecture")]
var bookB = StudySet(name: "B", kind: .book)
bookB.images = ["B0"]
bookB.bookMarkdown = "# Lungs\n  ![The alveoli](image:0)\nMore text with image:0 in a sentence."
bookB.sources = [SourceDoc(name: "Lung lecture")]
let joined = StudySet.combined([bookA, bookB], name: "Both")
check("the books are joined with every picture", joined?.images == ["A0", "A1", "B0"])
check("the second book's figure points at its own picture, not the first book's",
      joined?.bookMarkdown.contains("![The alveoli](image:2)") == true, joined?.bookMarkdown ?? "")
check("the first book's figures are untouched", joined?.bookMarkdown.contains("![The valves](image:1)") == true)
check("words that only mention image:0 in a sentence are left alone",
      joined?.bookMarkdown.contains("More text with image:0 in a sentence.") == true)
check("both books' sources are kept", joined?.sources.map(\.name) == ["Heart lecture", "Lung lecture"])
var deckA = StudySet(name: "DA", kind: .anki)
deckA.images = ["P0"]
var occ = AnkiCard(type: .occlusion, front: "Name it"); occ.imageIndex = 0
deckA.cards = [occ]
var deckB = StudySet(name: "DB", kind: .anki)
deckB.images = ["Q0", "Q1"]
var basic = AnkiCard(type: .qa, front: "What is shown?", bullets: ["x"]); basic.imageIndex = 1
deckB.cards = [basic]
let decks = StudySet.combined([deckA, deckB], name: "Decks")
check("a card's picture is re-based into the joined pool",
      decks?.cards.last?.imageIndex.map { decks!.images[$0] } == "Q1")
check("sets of different kinds are not combined", StudySet.combined([deckA, bookA], name: "no") == nil)
check("one set is not a combination", StudySet.combined([deckA], name: "no") == nil)
check("rebasing by nothing changes nothing", BookFigures.rebased(bookA.bookMarkdown, by: 0) == bookA.bookMarkdown)

// MARK: an imported card's picture is shown, on its own side
let both = AnkiCard.picture(front: ["front.png"], back: ["back.png"], available: { _ in true })
check("a question-side picture is the card's, on the front", both.name == "front.png" && !both.onBack)
let backOnly = AnkiCard.picture(front: ["gone.png"], back: ["back.png"], available: { $0 != "gone.png" })
check("one only on the answer side is the answer's", backOnly.name == "back.png" && backOnly.onBack)
let none = AnkiCard.picture(front: [], back: ["gone.png"], available: { _ in false })
check("none the package carries: none", none.name == nil && !none.onBack)
var answerPicture = AnkiCard(type: .qa, front: "What does a target lesion look like?", bullets: ["see it"])
answerPicture.imageIndex = 0
answerPicture.pictureOnBack = true
check("an answer's picture waits for the reveal", !answerPicture.pictureOnFront)
check("a card's picture shows on the front by default", AnkiCard(type: .cloze, clozeText: "{{c1::x}}").pictureOnFront)
var occFlag = AnkiCard(type: .occlusion); occFlag.pictureOnBack = true
check("an occlusion card's picture is always the question", occFlag.pictureOnFront)
let encoded = try JSONEncoder().encode(answerPicture)
let decoded = try JSONDecoder().decode(AnkiCard.self, from: encoded)
check("the side is saved with the card", decoded.pictureOnBack == true)
let older = try JSONDecoder().decode(AnkiCard.self, from: Data(#"{"type":"qa","front":"Q","imageIndex":0}"#.utf8))
check("a card saved before the side existed reads as a front picture", older.pictureOnBack == nil && older.pictureOnFront)

// MARK: a picture is decoded once, not on every redraw (audit #67)

final class Decoded { let bytes: Data; init(_ bytes: Data) { self.bytes = bytes } }
let cache = PictureCache<Decoded>()
var decodes = 0
let jpegish = Data((0..<300).map { UInt8($0 % 251) })
let stored = jpegish.base64EncodedString()
let first = cache.picture(for: stored) { decodes += 1; return Decoded($0) }
let again = cache.picture(for: stored) { decodes += 1; return Decoded($0) }
check("the same picture is decoded once", decodes == 1 && first === again && first?.bytes == jpegish, "\(decodes)")
let uri = cache.picture(for: "data:image/jpeg;base64," + stored) { decodes += 1; return Decoded($0) }
check("a data: URI decodes to the same bytes", uri?.bytes == jpegish)
var middle = Array(stored)
middle[200] = middle[200] == "A" ? "B" : "A"
let changed = cache.picture(for: String(middle)) { decodes += 1; return Decoded($0) }
check("a picture differing only in the middle is not mistaken for another",
      changed != nil && changed !== first && changed?.bytes != jpegish)
check("text that is not a picture gives none", cache.picture(for: "%%%") { _ in nil } == nil)

print(failures.isEmpty ? "\nALL PICTURE TESTS PASS" : "\n\(failures.count) PICTURE TEST FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
