package com.stethoscore.app.data

import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Search that finds the item, and the custom session built from a filter:
 * iOS Tests/LibrarySearchTests.swift, check for check, with the same labels.
 */
class LibrarySearchTest {

    private fun ok(condition: Boolean, what: String) = assertTrue(what, condition)

    private fun q(stem: String, options: List<String> = listOf("A", "B", "C", "D"), key: Int = 0, why: String = "") =
        MCQQuestion(stem = stem, options = options, correctIndex = key, explanation = why, imageIndex = null)

    private fun card(front: String, answer: String, why: String = "") =
        AnkiCard(type = AnkiCardType.QA, front = front, bullets = listOf(answer), why = why)

    private fun cloze(text: String) = AnkiCard(type = AnkiCardType.CLOZE, clozeText = text)

    private val renal = StudySet(name = "Renal block", subject = "Nephrology", kind = StudySetKind.MCQ, questions = listOf(
        q("Which finding defines the nephrotic syndrome?", listOf("Proteinuria over 3.5 g/day", "Haematuria", "Casts", "Hypertension")),
        q("A child has periorbital oedema after a sore throat. What is the likely cause?", why = "Post-streptococcal glomerulonephritis"),
        q("Which drug lowers potassium fastest?")))
    private val cardio = StudySet(name = "Heart failure", subject = "Cardiology", kind = StudySetKind.ANKI, cards = listOf(
        card("First-line diuretic in acute heart failure oedema", "Furosemide", why = "Loop diuretic #cardio"),
        cloze("{{c1::Spironolactone}} improves survival in HFrEF"),
        card("Drug that causes gynaecomastia among diuretics", "Spironolactone"),
        card("Diuretic class that causes hypokalaemia and hyperglycaemia", "Thiazides"),
        card("Beta blocker proven in HFrEF", "Bisoprolol"),
        card("ACE inhibitor side effect in the airways", "Dry cough")))
    private val lectureSet = StudySet(name = "Lecture only", subject = "Nephrology", kind = StudySetKind.MCQ, sources = listOf(
        SourceDoc(name = "Nephrotic lecture", pages = listOf(
            SourcePage(number = 1, text = "Nothing here"),
            SourcePage(number = 2, text = "The nephrotic syndrome causes oedema. Nephrotic again.")))))
    private val notes = listOf(LibrarySearch.NoteText(id = newId(), title = "Oedema mnemonic", body = "Pitting vs non-pitting", tags = listOf("renal")))
    private val sets = listOf(renal, cardio, lectureSet)
    private val index = LibrarySearch.build(sets, notes)

    @Test fun theIndex() {
        ok(index.entries.size == 3 + 3 + 6 + 1, "a set, its questions, its cards and each note are entries")
        ok(index.lectures.size == 1, "each lecture with pages is kept for page search")
        ok(LibrarySearch.clozeBare("{{c1::Warfarin::drug}} needs {{c2::INR}}") == "Warfarin needs INR",
            "a cloze reads with its gaps filled in")
        ok(LibrarySearch.clozeBare("broken {{c1::open") == "broken {{c1::open", "an unclosed cloze is left as written")
        ok(LibrarySearch.tokens("Édème, pitting-oedema a") == listOf("edeme", "pitting", "oedema"),
            "tokens are folded words of two letters or more")
    }

    @Test fun searching() {
        var r = LibrarySearch.search("nephrotic syndrome", index, LibrarySearch.Scope.ALL)
        ok(r.items.any { it.kind == LibrarySearch.Kind.QUESTION && it.itemId == renal.questions[0].id },
            "the question itself is found, not just its set")
        ok(r.sets.firstOrNull() == renal.id, "and its set is listed")
        val first = r.items.firstOrNull { it.kind == LibrarySearch.Kind.QUESTION }
        if (first != null) {
            val marked = first.snippet.substring(first.range)
            ok(marked.lowercase() == "nephrotic syndrome", "the matched phrase is where the range says")
        } else ok(false, "a question hit")
        ok(r.items.any { it.kind == LibrarySearch.Kind.LECTURE && it.page == 2 }, "a lecture page matches too")
        ok(r.items.count { it.kind == LibrarySearch.Kind.LECTURE } == 1, "one hit per page, however many times it says it")

        r = LibrarySearch.search("OEDEMA", index, LibrarySearch.Scope.ALL)
        ok(r.items.any { it.kind == LibrarySearch.Kind.NOTE }, "notes are searched, case aside")
        ok(r.items.any { it.kind == LibrarySearch.Kind.CARD }, "and cards")
        ok(r.items.any { it.kind == LibrarySearch.Kind.QUESTION }, "and questions, in their explanation too")

        r = LibrarySearch.search("oedema", index, LibrarySearch.Scope.CARDS)
        ok(r.items.isNotEmpty() && r.items.all { it.kind == LibrarySearch.Kind.CARD }, "the Cards scope shows only cards")
        ok(r.sets.isEmpty(), "and no sets group")
        r = LibrarySearch.search("oedema", index, LibrarySearch.Scope.NOTES)
        ok(r.items.size == 1 && r.items[0].kind == LibrarySearch.Kind.NOTE, "the Notes scope, only notes")
        r = LibrarySearch.search("oedema", index, LibrarySearch.Scope.LECTURES)
        ok(r.items.all { it.kind == LibrarySearch.Kind.LECTURE } && r.items.isNotEmpty(), "the Lectures scope, only pages")

        r = LibrarySearch.search("spironolactone", index, LibrarySearch.Scope.ALL)
        ok(r.items.any { it.itemId == cardio.cards[1].id }, "a cloze is found by its hidden answer")

        r = LibrarySearch.search("heart", index, LibrarySearch.Scope.ALL)
        ok(r.sets.firstOrNull() == cardio.id, "a set whose name matches comes first")

        r = LibrarySearch.search("potassium drug", index, LibrarySearch.Scope.ALL)
        ok(r.items.any { it.itemId == renal.questions[2].id }, "every word anywhere will do when the phrase is nowhere")

        r = LibrarySearch.search("n", index, LibrarySearch.Scope.ALL)
        ok(r.items.isEmpty() && r.sets.isNotEmpty(), "one letter matches sets only")

        ok(LibrarySearch.search("   ", index, LibrarySearch.Scope.ALL).isEmpty, "a blank search finds nothing")

        val many = StudySet(name = "Big", kind = StudySetKind.MCQ, questions = (0 until 80).map { q("Renal question number $it here") })
        val big = LibrarySearch.build(listOf(many), emptyList())
        r = LibrarySearch.search("renal", big, LibrarySearch.Scope.QUESTIONS)
        ok(r.items.size == LibrarySearch.itemLimit && r.more, "results are capped at fifty, and say there are more")

        val longText = "word ".repeat(40) + "TARGET" + " more".repeat(40)
        val m = LibrarySearch.find("target", longText)
        if (m != null) {
            val (line, range) = LibrarySearch.snippet(longText, m)
            ok(line.startsWith("…") && line.endsWith("…"), "a snippet cut from the middle says so")
            ok(line.substring(range) == "TARGET", "and marks the match in the original case")
        } else ok(false, "find in long text")
    }

    @Test fun openingAnItemInItsSet() {
        val opened = LibrarySearch.opening(renal, renal.questions[1].id)
        ok(opened?.questions?.firstOrNull()?.id == renal.questions[1].id, "a question opens first in its set")
        ok(opened?.questions?.size == 3 && opened.id == renal.id, "with the rest of the set after it")
        ok(LibrarySearch.opening(renal, newId()) == null, "a question not in the set opens nothing")
    }

    @Test fun customSessions() {
        val now = System.currentTimeMillis()
        val day = 86_400_000L
        val ctx = CustomSession.Context(now = now)
        ctx.lastMissed[renal.questions[0].id] = now - 2 * day
        ctx.lastMissed[renal.questions[1].id] = now - 20 * day
        ctx.cards[cardio.cards[0].id] = CustomSession.CardState(due = now - 60_000, lapses = 1, ratedAt = now - day)
        ctx.cards[cardio.cards[2].id] = CustomSession.CardState(due = now + day * 5, lapses = 0, ratedAt = now - day)
        ctx.cards[cardio.cards[3].id] = CustomSession.CardState(due = now - 60_000, lapses = 2, ratedAt = now - 3 * day, suspended = true)

        var f = CustomSession.Filter()
        ok(!f.narrows, "an empty filter does not narrow the library")
        f.failedWithinDays = 7
        ok(f.narrows, "missed this week does")
        var plan = CustomSession.plan(sets, f, ctx)
        ok(plan.questions.map { it.question?.id } == listOf(renal.questions[0].id), "only questions missed within the week")
        ok(plan.cards.map { it.card?.id } == listOf(cardio.cards[0].id), "and cards that lapsed and were rated this week, not suspended ones")

        f = CustomSession.Filter()
        f.dueOnly = true
        plan = CustomSession.plan(sets, f, ctx)
        ok(plan.questions.isEmpty() && plan.cards.size == 1, "Due takes only cards due now")

        f = CustomSession.Filter()
        f.subject = "Cardiology"
        f.include = CustomSession.Include.CARDS
        plan = CustomSession.plan(sets, f, ctx)
        ok(plan.cards.size == 5 && plan.questions.isEmpty(), "a subject, cards only (the suspended one left out)")

        f = CustomSession.Filter()
        f.tag = "#cardio"
        plan = CustomSession.plan(sets, f, ctx)
        ok(plan.cards.size == 5, "a tag matching the set's subject takes the set")
        f.tag = "loop"
        plan = CustomSession.plan(sets, f, ctx)
        ok(plan.count == 0, "a tag is a #tag or the set's topic, not any word")

        f = CustomSession.Filter()
        f.accuracyFlagged = true
        ctx.accuracyFlagged = setOf(renal.questions[2].id, cardio.cards[4].id)
        plan = CustomSession.plan(sets, f, ctx)
        ok(plan.count == 2, "flagged by the accuracy engine")

        f = CustomSession.Filter()
        f.text = "diuretic"
        plan = CustomSession.plan(sets, f, ctx)
        ok(plan.cards.size == 2, "words as the search reads them (the suspended card left out)")

        f = CustomSession.Filter()
        f.subject = "Nephrology"
        f.limit = 2
        plan = CustomSession.plan(sets, f, ctx)
        ok(plan.count == 2, "the limit holds")
        ok(plan.questions.firstOrNull()?.question?.id == renal.questions[0].id, "most recently missed first")

        // the session as a quiz: cards become questions with distractors from the deck
        f = CustomSession.Filter()
        f.failedWithinDays = 7
        f.include = CustomSession.Include.CARDS
        plan = CustomSession.plan(sets, f, ctx)
        val alone = QuizFromCards.build(plan.cards.mapNotNull { it.card })
        ok(alone.questions.isEmpty(), "one card alone cannot make a question")
        val quiz = CustomSession.quiz(plan, sets, "Missed")
        ok(quiz.set.questions.size == 1 && quiz.skipped == 0, "with its deck as the pool, it can")
        ok(quiz.set.kind == StudySetKind.MCQ, "and the session is a quiz")
        val key = quiz.set.questions.firstOrNull()?.let { it.options[it.correctIndex] }
        ok(key == "Furosemide", "keyed on the card's answer")

        // the old build is unchanged by the new overload
        val whole = QuizFromCards.build(cardio.cards, seed = 3uL)
        val pooled = QuizFromCards.build(cardio.cards, emptyList(), seed = 3uL)
        ok(whole.questions.map { it.options } == pooled.questions.map { it.options }, "the deck-only build is as it was")

        val pics = cardio.copy(images = listOf("img0", "img1"), cards = cardio.cards.mapIndexed { i, c -> if (i == 0) c.copy(imageIndex = 1) else c })
        f = CustomSession.Filter()
        f.text = "first-line"
        plan = CustomSession.plan(listOf(pics), f, ctx)
        val deck = CustomSession.deck(plan, listOf(pics), "Deck")
        ok(deck.kind == StudySetKind.ANKI && deck.cards.firstOrNull()?.id == pics.cards[0].id, "a review deck keeps the card's own id")
        ok(deck.cards.firstOrNull()?.imageIndex?.let { deck.images[it] } == "img1", "and its picture")

        ok(CustomSession.title(f) == "“first-line”", "the session is named after its filter")
        f.failedWithinDays = 7
        f.subject = "Cardiology"
        ok(CustomSession.title(f).startsWith("Missed this week · Cardiology"), "in words")
        ok(CustomSession.subjects(sets) == listOf("Cardiology", "Nephrology"), "subjects for the picker")
    }

    @Test fun tagsAnkisKeptOnImport() {
        val taggedCard = card("Digoxin toxicity sign", "Yellow vision").copy(tags = listOf("#AK_Step1::Cardio"))
        val plainCard = card("Loop diuretic", "Furosemide").copy(tags = listOf("#AK_Step1::Renal"))
        val tagged = StudySet(name = "AnKing part 1", subject = "General", kind = StudySetKind.ANKI, cards = listOf(taggedCard, plainCard))
        val setTaggedDeck = StudySet(name = "Pharm deck", subject = "General", kind = StudySetKind.ANKI, tags = listOf("Cardio"),
            cards = listOf(card("Beta blocker", "Atenolol")))
        val tagIndex = LibrarySearch.build(listOf(tagged, setTaggedDeck), emptyList())
        val byHash = LibrarySearch.search("#cardio", tagIndex, LibrarySearch.Scope.ALL)
        ok(byHash.items.any { it.itemId == taggedCard.id } && byHash.items.none { it.itemId == plainCard.id },
            "#cardio finds the card tagged #AK_Step1::Cardio, not its neighbour")
        ok(byHash.items.any { it.itemId == setTaggedDeck.cards[0].id }, "a set's tag covers its cards")
        ok(tagged.id in byHash.sets && setTaggedDeck.id in byHash.sets, "the sets holding them are listed")
        val byParent = LibrarySearch.search("tag:AK_Step1", tagIndex, LibrarySearch.Scope.CARDS)
        ok(byParent.items.size == 2, "a parent tag finds everything filed under it")
        val withText = LibrarySearch.search("#cardio yellow", tagIndex, LibrarySearch.Scope.ALL)
        ok(withText.items.map { it.itemId } == listOf(taggedCard.id), "a tag and words together")
        val plainWord = LibrarySearch.search("cardio", tagIndex, LibrarySearch.Scope.CARDS)
        ok(plainWord.items.any { it.itemId == taggedCard.id }, "a plain word finds a tag too")

        val tf = CustomSession.Filter()
        tf.tag = "cardio"
        val tagPlan = CustomSession.plan(listOf(tagged, setTaggedDeck), tf, CustomSession.Context())
        val tagIds = tagPlan.cards.mapNotNull { it.card?.id }
        ok(taggedCard.id in tagIds && setTaggedDeck.cards[0].id in tagIds && plainCard.id !in tagIds,
            "Build a session: tag cardio takes the cards tagged Cardio (nested or on the set)")
        tf.tag = "#ak_step1"
        val parentPlan = CustomSession.plan(listOf(tagged), tf, CustomSession.Context())
        ok(parentPlan.cards.size == 2, "Build a session: a parent tag, any case, with its #")
    }
}
