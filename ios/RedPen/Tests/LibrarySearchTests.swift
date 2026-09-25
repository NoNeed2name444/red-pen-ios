// Search that finds the item, and the custom session built from a filter.

import Foundation

var failures = 0
func ok(_ condition: Bool, _ what: String) {
    print((condition ? "ok   " : "FAIL ") + what)
    if !condition { failures += 1 }
}

func q(_ stem: String, _ options: [String] = ["A", "B", "C", "D"], key: Int = 0,
       why: String = "") -> MCQQuestion {
    MCQQuestion(stem: stem, options: options, correctIndex: key, explanation: why, imageIndex: nil)
}

func card(_ front: String, _ answer: String, why: String = "") -> AnkiCard {
    var c = AnkiCard(type: .qa)
    c.front = front
    c.bullets = [answer]
    c.why = why
    return c
}

func cloze(_ text: String) -> AnkiCard {
    var c = AnkiCard(type: .cloze)
    c.clozeText = text
    return c
}

var renal = StudySet(name: "Renal block", subject: "Nephrology", kind: .mcq)
renal.questions = [
    q("Which finding defines the nephrotic syndrome?", ["Proteinuria over 3.5 g/day", "Haematuria", "Casts", "Hypertension"]),
    q("A child has periorbital oedema after a sore throat. What is the likely cause?", why: "Post-streptococcal glomerulonephritis"),
    q("Which drug lowers potassium fastest?"),
]
var cardio = StudySet(name: "Heart failure", subject: "Cardiology", kind: .anki)
cardio.cards = [
    card("First-line diuretic in acute heart failure oedema", "Furosemide", why: "Loop diuretic #cardio"),
    cloze("{{c1::Spironolactone}} improves survival in HFrEF"),
    card("Drug that causes gynaecomastia among diuretics", "Spironolactone"),
    card("Diuretic class that causes hypokalaemia and hyperglycaemia", "Thiazides"),
    card("Beta blocker proven in HFrEF", "Bisoprolol"),
    card("ACE inhibitor side effect in the airways", "Dry cough"),
]
var lectureSet = StudySet(name: "Lecture only", subject: "Nephrology", kind: .mcq)
lectureSet.sources = [SourceDoc(name: "Nephrotic lecture",
                                pages: [SourceDoc.Page(number: 1, text: "Nothing here"),
                                        SourceDoc.Page(number: 2, text: "The nephrotic syndrome causes oedema. Nephrotic again.")])]
let notes = [LibrarySearch.NoteText(id: UUID(), title: "Oedema mnemonic", body: "Pitting vs non-pitting", tags: ["renal"])]
let sets = [renal, cardio, lectureSet]
let index = LibrarySearch.build(sets: sets, notes: notes)

// MARK: the index

ok(index.entries.count == 3 + 3 + 6 + 1, "a set, its questions, its cards and each note are entries")
ok(index.lectures.count == 1, "each lecture with pages is kept for page search")
ok(LibrarySearch.clozeBare("{{c1::Warfarin::drug}} needs {{c2::INR}}") == "Warfarin needs INR",
   "a cloze reads with its gaps filled in")
ok(LibrarySearch.clozeBare("broken {{c1::open") == "broken {{c1::open", "an unclosed cloze is left as written")
ok(LibrarySearch.tokens("Édème, pitting-oedema a") == ["edeme", "pitting", "oedema"],
   "tokens are folded words of two letters or more")

// MARK: searching

var r = LibrarySearch.search("nephrotic syndrome", in: index, scope: .all)
ok(r.items.contains { $0.kind == .question && $0.itemID == renal.questions[0].id },
   "the question itself is found, not just its set")
ok(r.sets.first == renal.id, "and its set is listed")
let first = r.items.first { $0.kind == .question }
if let first {
    let chars = Array(first.snippet)
    let marked = String(chars[first.range])
    ok(marked.lowercased() == "nephrotic syndrome", "the matched phrase is where the range says")
} else { ok(false, "a question hit") }
ok(r.items.contains { $0.kind == .lecture && $0.page == 2 }, "a lecture page matches too")
ok(r.items.filter { $0.kind == .lecture }.count == 1, "one hit per page, however many times it says it")

r = LibrarySearch.search("OEDEMA", in: index, scope: .all)
ok(r.items.contains { $0.kind == .note }, "notes are searched, case aside")
ok(r.items.contains { $0.kind == .card }, "and cards")
ok(r.items.contains { $0.kind == .question }, "and questions, in their explanation too")

r = LibrarySearch.search("oedema", in: index, scope: .cards)
ok(!r.items.isEmpty && r.items.allSatisfy { $0.kind == .card }, "the Cards scope shows only cards")
ok(r.sets.isEmpty, "and no sets group")
r = LibrarySearch.search("oedema", in: index, scope: .notes)
ok(r.items.count == 1 && r.items[0].kind == .note, "the Notes scope, only notes")
r = LibrarySearch.search("oedema", in: index, scope: .lectures)
ok(r.items.allSatisfy { $0.kind == .lecture } && !r.items.isEmpty, "the Lectures scope, only pages")

r = LibrarySearch.search("spironolactone", in: index, scope: .all)
ok(r.items.contains { $0.itemID == cardio.cards[1].id }, "a cloze is found by its hidden answer")

r = LibrarySearch.search("heart", in: index, scope: .all)
ok(r.sets.first == cardio.id, "a set whose name matches comes first")

r = LibrarySearch.search("potassium drug", in: index, scope: .all)
ok(r.items.contains { $0.itemID == renal.questions[2].id }, "every word anywhere will do when the phrase is nowhere")

r = LibrarySearch.search("n", in: index, scope: .all)
ok(r.items.isEmpty && !r.sets.isEmpty, "one letter matches sets only")

ok(LibrarySearch.search("   ", in: index, scope: .all).isEmpty, "a blank search finds nothing")

var many = StudySet(name: "Big", kind: .mcq)
many.questions = (0..<80).map { q("Renal question number \($0) here") }
let big = LibrarySearch.build(sets: [many], notes: [])
r = LibrarySearch.search("renal", in: big, scope: .questions)
ok(r.items.count == LibrarySearch.itemLimit && r.more, "results are capped at fifty, and say there are more")

let longText = String(repeating: "word ", count: 40) + "TARGET" + String(repeating: " more", count: 40)
if let m = LibrarySearch.find("target", in: longText) {
    let (line, range) = LibrarySearch.snippet(of: longText, around: m)
    ok(line.hasPrefix("\u{2026}") && line.hasSuffix("\u{2026}"), "a snippet cut from the middle says so")
    ok(String(Array(line)[range]) == "TARGET", "and marks the match in the original case")
} else { ok(false, "find in long text") }

// MARK: opening an item in its set

let opened = LibrarySearch.opening(renal, atQuestion: renal.questions[1].id)
ok(opened?.questions.first?.id == renal.questions[1].id, "a question opens first in its set")
ok(opened?.questions.count == 3 && opened?.id == renal.id, "with the rest of the set after it")
ok(LibrarySearch.opening(renal, atQuestion: UUID()) == nil, "a question not in the set opens nothing")

// MARK: custom sessions

let now = Date()
var ctx = CustomSession.Context()
ctx.now = now
ctx.lastMissed[renal.questions[0].id] = now.addingTimeInterval(-2 * 86_400)
ctx.lastMissed[renal.questions[1].id] = now.addingTimeInterval(-20 * 86_400)
ctx.cards[cardio.cards[0].id] = CustomSession.CardState(due: now.addingTimeInterval(-60), lapses: 1,
                                                          ratedAt: now.addingTimeInterval(-86_400))
ctx.cards[cardio.cards[2].id] = CustomSession.CardState(due: now.addingTimeInterval(86_400 * 5), lapses: 0,
                                                          ratedAt: now.addingTimeInterval(-86_400))
ctx.cards[cardio.cards[3].id] = CustomSession.CardState(due: now.addingTimeInterval(-60), lapses: 2,
                                                          ratedAt: now.addingTimeInterval(-3 * 86_400),
                                                          suspended: true)

var f = CustomSession.Filter()
ok(!f.narrows, "an empty filter does not narrow the library")
f.failedWithinDays = 7
ok(f.narrows, "missed this week does")
var plan = CustomSession.plan(sets: sets, filter: f, context: ctx)
ok(plan.questions.map { $0.question?.id } == [renal.questions[0].id], "only questions missed within the week")
ok(plan.cards.map { $0.card?.id } == [cardio.cards[0].id], "and cards that lapsed and were rated this week, not suspended ones")

f = CustomSession.Filter()
f.dueOnly = true
plan = CustomSession.plan(sets: sets, filter: f, context: ctx)
ok(plan.questions.isEmpty && plan.cards.count == 1, "Due takes only cards due now")

f = CustomSession.Filter()
f.subject = "Cardiology"
f.include = .cards
plan = CustomSession.plan(sets: sets, filter: f, context: ctx)
ok(plan.cards.count == 5 && plan.questions.isEmpty, "a subject, cards only (the suspended one left out)")

f = CustomSession.Filter()
f.tag = "#cardio"
plan = CustomSession.plan(sets: sets, filter: f, context: ctx)
ok(plan.cards.count == 5, "a tag matching the set's subject takes the set")
f.tag = "loop"
plan = CustomSession.plan(sets: sets, filter: f, context: ctx)
ok(plan.count == 0, "a tag is a #tag or the set's topic, not any word")

f = CustomSession.Filter()
f.accuracyFlagged = true
ctx.accuracyFlagged = [renal.questions[2].id, cardio.cards[4].id]
plan = CustomSession.plan(sets: sets, filter: f, context: ctx)
ok(plan.count == 2, "flagged by the accuracy engine")

f = CustomSession.Filter()
f.text = "diuretic"
plan = CustomSession.plan(sets: sets, filter: f, context: ctx)
ok(plan.cards.count == 2, "words as the search reads them (the suspended card left out)")

f = CustomSession.Filter()
f.subject = "Nephrology"
f.limit = 2
plan = CustomSession.plan(sets: sets, filter: f, context: ctx)
ok(plan.count == 2, "the limit holds")
ok(plan.questions.first?.question?.id == renal.questions[0].id, "most recently missed first")

// the session as a quiz: cards become questions with distractors from the deck
f = CustomSession.Filter()
f.failedWithinDays = 7
f.include = .cards
plan = CustomSession.plan(sets: sets, filter: f, context: ctx)
let alone = QuizFromCards.build(from: plan.cards.compactMap { $0.card })
ok(alone.questions.isEmpty, "one card alone cannot make a question")
let quiz = CustomSession.quiz(plan, sets: sets, name: "Missed")
ok(quiz.set.questions.count == 1 && quiz.skipped == 0, "with its deck as the pool, it can")
ok(quiz.set.kind == .mcq, "and the session is a quiz")
let key = quiz.set.questions.first.map { $0.options[$0.correctIndex] }
ok(key == "Furosemide", "keyed on the card's answer")

// the old build is unchanged by the new overload
let whole = QuizFromCards.build(from: cardio.cards, seed: 3)
let pooled = QuizFromCards.build(from: cardio.cards, distractorsFrom: [], seed: 3)
ok(whole.questions.map(\.options) == pooled.questions.map(\.options), "the deck-only build is as it was")

var pics = cardio
pics.images = ["img0", "img1"]
pics.cards[0].imageIndex = 1
f = CustomSession.Filter()
f.text = "first-line"
plan = CustomSession.plan(sets: [pics], filter: f, context: ctx)
let deck = CustomSession.deck(plan, sets: [pics], name: "Deck")
ok(deck.kind == .anki && deck.cards.first?.id == pics.cards[0].id, "a review deck keeps the card's own id")
ok(deck.cards.first.flatMap { $0.imageIndex }.map { deck.images[$0] } == "img1", "and its picture")

ok(CustomSession.title(for: f) == "\u{201C}first-line\u{201D}", "the session is named after its filter")
f.failedWithinDays = 7
f.subject = "Cardiology"
ok(CustomSession.title(for: f).hasPrefix("Missed this week \u{00B7} Cardiology"), "in words")
ok(CustomSession.subjects(in: sets) == ["Cardiology", "Nephrology"], "subjects for the picker")

// MARK: tags (Anki's, kept on import)

var tagged = StudySet(name: "AnKing part 1", subject: "General", kind: .anki)
var taggedCard = card("Digoxin toxicity sign", "Yellow vision")
taggedCard.tags = ["#AK_Step1::Cardio"]
var plainCard = card("Loop diuretic", "Furosemide")
plainCard.tags = ["#AK_Step1::Renal"]
tagged.cards = [taggedCard, plainCard]
var setTaggedDeck = StudySet(name: "Pharm deck", subject: "General", kind: .anki)
setTaggedDeck.tags = ["Cardio"]
setTaggedDeck.cards = [card("Beta blocker", "Atenolol")]
let tagIndex = LibrarySearch.build(sets: [tagged, setTaggedDeck], notes: [])
let byHash = LibrarySearch.search("#cardio", in: tagIndex, scope: .all)
ok(byHash.items.contains { $0.itemID == taggedCard.id } && !byHash.items.contains { $0.itemID == plainCard.id },
   "#cardio finds the card tagged #AK_Step1::Cardio, not its neighbour")
ok(byHash.items.contains { $0.itemID == setTaggedDeck.cards[0].id }, "a set's tag covers its cards")
ok(byHash.sets.contains(tagged.id) && byHash.sets.contains(setTaggedDeck.id), "the sets holding them are listed")
let byParent = LibrarySearch.search("tag:AK_Step1", in: tagIndex, scope: .cards)
ok(byParent.items.count == 2, "a parent tag finds everything filed under it")
let withText = LibrarySearch.search("#cardio yellow", in: tagIndex, scope: .all)
ok(withText.items.map { $0.itemID } == [taggedCard.id], "a tag and words together")
let plainWord = LibrarySearch.search("cardio", in: tagIndex, scope: .cards)
ok(plainWord.items.contains { $0.itemID == taggedCard.id }, "a plain word finds a tag too")

var tf = CustomSession.Filter()
tf.tag = "cardio"
let tagPlan = CustomSession.plan(sets: [tagged, setTaggedDeck], filter: tf, context: CustomSession.Context())
let tagIDs: [UUID] = tagPlan.cards.compactMap { $0.card?.id }
ok(tagIDs.contains(taggedCard.id) && tagIDs.contains(setTaggedDeck.cards[0].id) && !tagIDs.contains(plainCard.id),
   "Build a session: tag cardio takes the cards tagged Cardio (nested or on the set)")
tf.tag = "#ak_step1"
let parentPlan = CustomSession.plan(sets: [tagged], filter: tf, context: CustomSession.Context())
ok(parentPlan.cards.count == 2, "Build a session: a parent tag, any case, with its #")

print(failures == 0 ? "\nALL LIBRARY SEARCH TESTS PASS" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
