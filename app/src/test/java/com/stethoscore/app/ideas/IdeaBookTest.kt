package com.stethoscore.app.ideas

import com.stethoscore.app.data.AnkiCardType
import com.stethoscore.app.data.Note
import com.stethoscore.app.map.SpaceStyle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * The idea dump's rules as iOS NoteStore, IdeaEdges, NoteTone, NoteCards, NoteMarkdown,
 * GraphTheme and GraphStyleChoice have them (fed0105). iOS has no suite of its own for these
 * (its NoteStore is checked through the app); these are Android's, case by case from the source.
 */
class IdeaBookTest {
    private var clock = 1_000L
    private val saved = ArrayList<Int>()
    private fun book(notes: List<Note> = emptyList(), folders: List<NoteFolder> = emptyList()) =
        IdeaBook(notes, folders, now = { clock }, onChange = { n, _ -> saved.add(n.size) })
    private fun id(n: Int) = "00000000-0000-4000-8000-" + n.toString().padStart(12, '0')

    @Test fun createTrimsAndSpiralsOut() {
        val b = book()
        val first = b.create("  Heart failure \n")
        assertEquals("the title trimmed", "Heart failure", first.title)
        assertEquals("the first at the centre", BoardPoint(0.0, 0.0), BoardPoint(first.boardX, first.boardY))
        val second = b.create("Second")
        assertTrue("the second one step out on the golden spiral",
            abs(second.boardX - 90 * kotlin.math.cos(2.399963)) < 1e-9 && abs(second.boardY - 90 * kotlin.math.sin(2.399963)) < 1e-9)
        val third = b.create("Third", at = BoardPoint(5.0, -7.0))
        assertEquals("a given spot is kept", BoardPoint(5.0, -7.0), BoardPoint(third.boardX, third.boardY))
        assertTrue("radius 90 times the square root of the count",
            abs(sqrt(second.boardX * second.boardX + second.boardY * second.boardY) - 90) < 1e-9)
        assertEquals("each change saved", listOf(1, 2, 3), saved)
        assertEquals("an idea unless asked", "idea", first.kind)
    }

    @Test fun updateStampsOnlyARealChange() {
        val b = book()
        val note = b.create("A")
        clock = 5_000
        b.update(note.copy(updatedAt = 99))
        assertEquals("opening and closing is not a change", 1_000L, b.note(note.id)!!.updatedAt)
        b.update(note.copy(body = "new"))
        assertEquals("a change is stamped", 5_000L, b.note(note.id)!!.updatedAt)
        b.setPosition(note.id, 3.0, 4.0)
        assertEquals("moving on the board is not an edit", 5_000L, b.note(note.id)!!.updatedAt)
        clock = 6_000
        b.move(note.id, "f")
        assertEquals("moving to a folder is", 6_000L, b.note(note.id)!!.updatedAt)
        val count = saved.size
        b.move(note.id, "f")
        assertEquals("moving to where it is saves nothing", count, saved.size)
    }

    @Test fun searchAndContentsNewestFirst() {
        val b = book(listOf(
            Note(id = id(1), title = "Aortic stenosis", body = "slow rising pulse", updatedAt = 10),
            Note(id = id(2), title = "Mitral", body = "Aortic? no", tags = listOf("valve"), updatedAt = 30, folderId = "f"),
            Note(id = id(3), title = "Other", updatedAt = 20),
        ))
        assertEquals("every word, anywhere", listOf(id(2)), b.search("aortic VALVE").map { it.id })
        assertEquals("newest first", listOf(id(2), id(1)), b.search("aortic").map { it.id })
        assertEquals("no words: everything, newest first", listOf(id(2), id(3), id(1)), b.search("  ").map { it.id })
        assertEquals("loose notes", listOf(id(3), id(1)), b.contents(null).map { it.id })
    }

    @Test fun linksAreHeldOnceAndReadBothWays() {
        val b = book(listOf(Note(id = id(1), title = "A"), Note(id = id(2), title = "B")))
        b.link(id(1), id(2))
        b.link(id(2), id(1))
        b.link(id(1), id(1))
        assertEquals("kept on the first only", listOf(id(2)), b.note(id(1))!!.links)
        assertTrue("and not again from the other end", b.note(id(2))!!.links.isEmpty())
        assertTrue("linked either way", b.isLinked(id(2), id(1)))
        b.unlink(id(2), id(1))
        assertFalse("unlinked from either side", b.isLinked(id(1), id(2)))
        b.link(id(1), id(2))
        b.delete(id(2))
        assertTrue("deleting a note removes the hand links to it", b.note(id(1))!!.links.isEmpty())
    }

    @Test fun wikiTitlesAsObsidianReadsThem() {
        assertEquals(listOf("Heart failure", "Asthma", "Gout"),
            IdeaBook.wikiTitles("see [[ Heart failure ]] and [[Asthma|the wheezy one]], [[Gout]] [[]] [[ |x]] [[broken\nline]] [[open"))
    }

    @Test fun titlesResolveOldestFirstAndEdgesOnce() {
        val b = book(listOf(
            Note(id = id(3), title = "Gout", createdAt = 30),
            Note(id = id(1), title = "gout ", createdAt = 10, body = "[[Asthma]] [[asthma]] [[Nothing]] [[Gout]]"),
            Note(id = id(2), title = "Asthma", createdAt = 20, links = listOf(id(1), id(9), id(2))),
        ))
        assertEquals("the older of two titles wins", id(1), b.titleIndex()["gout"])
        assertEquals("each named once, in order, unknown left out", listOf(id(2), id(1)), b.resolve("[[Asthma]] [[asthma]] [[Nothing]] [[Gout]]"))
        assertEquals("outgoing: hand links then names, known, not itself", listOf(id(2)), b.outgoing(id(1)))
        assertEquals("backlinks by hand or by name, not itself", listOf(id(2)), b.backlinks(id(1)))
        assertEquals("connections either way", setOf(id(2)), b.connections(id(1)))
        assertEquals("every pair once, ordered by id, no self or unknown", listOf(id(1) to id(2)), b.allEdges())
    }

    @Test fun edgePairsOrderLikeIos() {
        val upper = "B0000000-0000-4000-8000-000000000000".lowercase()
        val lower = "0A000000-0000-4000-8000-000000000000".lowercase()
        assertEquals("a digit before a letter, as iOS's uppercase strings sort", listOf(lower to upper),
            IdeaEdges.pairs(listOf(upper to listOf(lower), lower to listOf(upper))))
    }

    @Test fun foldersNestAndDeleteIntoTheParent() {
        val b = book()
        val top = b.createFolder(" Cardio ")
        val inner = b.createFolder("Valves", top.id)
        val deep = b.createFolder("Week 10", inner.id)
        b.createFolder("Week 2", inner.id)
        val note = b.create("AS", folderId = deep.id)
        b.create("Loose")
        assertEquals("trimmed", "Cardio", top.name)
        assertEquals("by name, numbers by value", listOf("Week 2", "Week 10"), b.subfolders(inner.id).map { it.name })
        assertEquals("the path, outermost first", listOf("Cardio", "Valves", "Week 10"), b.path(deep.id).map { it.name })
        assertEquals("the root folder", top.id, b.rootFolder(deep.id))
        assertEquals("outline with depths", listOf("Cardio" to 0, "Valves" to 1, "Week 2" to 2, "Week 10" to 2), b.folderOutline().map { it.first.name to it.second })
        assertEquals("counted all the way down", 1, b.count(top.id))
        b.renameFolder(inner.id, "   ")
        assertEquals("a blank name is refused", "Valves", b.folder(inner.id)!!.name)
        b.deleteFolder(inner.id)
        assertEquals("its folders move up", top.id, b.folder(deep.id)!!.parentId)
        assertEquals("nothing deleted with it", 1, b.count(top.id))
        b.deleteFolder(deep.id)
        assertEquals("its notes move up", top.id, b.note(note.id)!!.folderId)
        assertEquals("indented with em spaces", "  Valves", IdeaBook.indented("Valves", 2))
    }

    @Test fun aLoopInTheParentsStops() {
        val b = book(folders = listOf(NoteFolder(id = "a", name = "A", parentId = "b"), NoteFolder(id = "b", name = "B", parentId = "a")))
        assertEquals(listOf("B", "A"), b.path("a").map { it.name })
    }

    @Test fun toneByTopLevelFolder() {
        val b = book()
        val second = b.createFolder("B")
        val first = b.createFolder("A")
        val inside = b.createFolder("Inside", second.id)
        assertNull("loose notes are grey", NoteTone.index(null, b))
        assertEquals("a folder's place among the top level, by name", 0, NoteTone.index(first.id, b))
        assertEquals("a subfolder takes its top folder's", 1, NoteTone.index(inside.id, b))
        assertTrue("the palette", NoteTone.palette.size == 7 && NoteTone.palette[0].contentEquals(floatArrayOf(20 / 255f, 184 / 255f, 166 / 255f)))
        assertTrue("wrapping", NoteTone.at(-1).contentEquals(NoteTone.palette[6]) && NoteTone.at(7).contentEquals(NoteTone.palette[0]))
    }

    @Test fun modesAndTheirWords() {
        assertEquals(listOf("List", "Board", "Space"), IdeasMode.entries.map { it.title })
        assertEquals(listOf("ideasMode-list", "ideasMode-board", "ideasMode-space"), IdeasMode.entries.map { it.identifier })
        assertEquals("unknown is the list", IdeasMode.LIST, IdeasMode.of("cube"))
        assertEquals("vignette.ideas.mode", IdeasMode.KEY)
        assertEquals("a newer kind reads as an idea", NoteKind.IDEA, NoteKind.of("canvas"))
    }

    @Test fun noteCards() {
        val paired = NoteCards.cards(Note(title = "T", body = "What is AS? | Slow rising pulse; ESM\nplain line"))
        assertEquals("question | answer lines", listOf("What is AS?"), paired.map { it.front })
        val six = (1..6).joinToString("\n") { "- point $it" }
        val bullets = NoteCards.cards(Note(title = " Signs ", body = six))
        assertEquals("four bullets a card, numbered when more", listOf("Signs (1)", "Signs (2)"), bullets.map { it.front })
        assertEquals(listOf(4, 2), bullets.map { it.bullets.size })
        assertEquals(AnkiCardType.QA, bullets[0].type)
        val few = NoteCards.cards(Note(title = "Signs", body = "* one\n• two\n-  \n- three"))
        assertEquals("one card for a few, empty bullets skipped", listOf("Signs"), few.map { it.front })
        assertEquals(listOf("one", "two", "three"), few[0].bullets)
        assertTrue("no title, no cards", NoteCards.cards(Note(title = "  ", body = "- a")).isEmpty())
    }

    @Test fun markdownBlocks() {
        val blocks = NoteMarkdown.blocks("# Title\nfirst line\nsecond line\n\n- a\n  * b\n3) c\n> quoted\n---\n```\ncode  here\n```\n#nospace")
        assertEquals(listOf(
            NoteMarkdown.Block.Heading(1, "Title"),
            NoteMarkdown.Block.Paragraph("first line second line"),
            NoteMarkdown.Block.Bullet(0, "•", "a"),
            NoteMarkdown.Block.Bullet(1, "•", "b"),
            NoteMarkdown.Block.Bullet(0, "3.", "c"),
            NoteMarkdown.Block.Quote("quoted"),
            NoteMarkdown.Block.Rule,
            NoteMarkdown.Block.Code("code  here"),
            NoteMarkdown.Block.Paragraph("#nospace"),
        ), blocks)
        assertTrue("nothing written", NoteMarkdown.blocks(" \n").isEmpty())
        assertEquals("an unclosed fence runs to the end", listOf(NoteMarkdown.Block.Code("x")), NoteMarkdown.blocks("```\nx"))
    }

    @Test fun markdownInline() {
        val spans = NoteMarkdown.inline("**bold** and *it* `c` [[Heart failure|HF]] [[Gout]] [site](https://x.org)")
        assertEquals(NoteMarkdown.Span("bold", bold = true), spans[0])
        assertEquals(NoteMarkdown.Span("it", italic = true), spans[2])
        assertEquals(NoteMarkdown.Span("c", code = true), spans[4])
        assertEquals("the page before the bar, the words after it shown", NoteMarkdown.Span("HF", noteLink = "Heart failure"), spans[6])
        assertEquals(NoteMarkdown.Span("Gout", noteLink = "Gout"), spans[8])
        assertEquals(NoteMarkdown.Span("site", url = "https://x.org"), spans[10])
        assertEquals("a lone star is plain", listOf(NoteMarkdown.Span("2 * 3")), NoteMarkdown.inline("2 * 3"))
    }

    @Test fun editorCompletion() {
        assertEquals("he", NoteEditing.openFragment("see [[Ast]] and [[he"))
        assertNull("closed", NoteEditing.openFragment("see [[Asthma]]"))
        assertNull("over a line", NoteEditing.openFragment("[[a\nb"))
        assertEquals("", NoteEditing.openFragment("x [["))
        assertEquals("see [[Heart failure]]", NoteEditing.complete("see [[he", "Heart failure"))
        val notes = (1..10).map { Note(id = id(it), title = "Heart $it", updatedAt = it.toLong()) } + Note(id = id(11), title = "")
        val s = NoteEditing.suggestions("[[heart", notes, id(10))
        assertEquals("eight, newest first, not itself or untitled", (9 downTo 2).map { id(it) }, s.map { it.id })
        assertTrue(NoteEditing.suggestions("no bracket", notes, id(1)).isEmpty())
        assertEquals("“Gout” is in your Cards now, 1 card ready to review.", NoteEditing.cardsMade("Gout", 1))
        assertEquals("“Gout” is in your Cards now, 3 cards ready to review.", NoteEditing.cardsMade("Gout", 3))
    }

    @Test fun editorLinksAsTyped() {
        val b = book(listOf(Note(id = id(1), title = "A", links = listOf(id(2))), Note(id = id(2), title = "B"),
            Note(id = id(3), title = "C", body = "[[A]]")))
        assertEquals(listOf(id(2), id(3)), NoteEditing.outgoing(b, id(1), "[[C]] [[B]] [[A]]"))
        assertEquals("not listed twice", emptyList<String>(), NoteEditing.backlinks(b, id(1), "[[C]]"))
        assertEquals(listOf(id(3)), NoteEditing.backlinks(b, id(1), ""))
        assertEquals("unknown names, each once", listOf("Nope"), NoteEditing.unresolved(b, "[[Nope]] [[nope]] [[A]]"))
    }

    @Test fun themes() {
        assertEquals("vignette.space.theme", GraphTheme.KEY)
        assertEquals("unknown is Space", GraphTheme.SPACE, GraphTheme.stored("galaxy"))
        assertEquals(GraphTheme.PERFORMANCE, GraphTheme.stored("performance"))
        assertEquals("Neurons is not ported: Space", GraphTheme.SPACE, GraphTheme.stored("neurons"))
        assertEquals(listOf("Space", "Performance"), GraphTheme.offered.map { it.title })
        assertEquals(listOf("Space of ideas", "Network of ideas", "Fast map of ideas"), GraphTheme.entries.map { it.mapLabel })
    }

    @Test fun styleChoice() {
        val f1 = id(100); val f2 = id(101)
        val raw = "$f2=sun;junk;$f1=blackHole;$f1=x;notauuid=sun"
        assertEquals("unreadable parts skipped", mapOf(f2 to SpaceStyle.SUN, f1 to SpaceStyle.BLACK_HOLE), GraphStyleChoice.folders(raw))
        assertEquals("encoded sorted by id", "$f1=blackHole;$f2=sun", GraphStyleChoice.encode(GraphStyleChoice.folders(raw)))
        val b = book(listOf(Note(id = id(1), title = "p", kind = "page"), Note(id = id(2), title = "i"), Note(id = id(3), title = "in", folderId = id(102))),
            listOf(NoteFolder(id = f1, name = "Top"), NoteFolder(id = id(102), name = "Sub", parentId = f1)))
        assertEquals("the safety net: pages gas giants, ideas rocky; a folder look wins",
            mapOf(id(1) to SpaceStyle.GAS_GIANT, id(2) to SpaceStyle.ROCKY, id(3) to SpaceStyle.BLACK_HOLE),
            GraphStyleChoice.resolve(b, GraphStyleChoice.AUTO, "$f1=blackHole"))
        assertEquals("one look for all", SpaceStyle.COMET, GraphStyleChoice.resolve(b, "comet", "")[id(1)])
        val codes = GraphStyleChoice.codes(b, listOf(id(1), id(2), id(3)), intArrayOf(0, 5, 0), GraphStyleChoice.AUTO, "$f1=pulsar")
        assertEquals("the Universe's stand-in by links, folder looks over it",
            listOf(SpaceStyle.COMET.code, SpaceStyle.SUN.code, SpaceStyle.PULSAR.code), codes.map { it.toInt() })
        assertEquals(0, GraphStyleChoice.palette(null))
        assertTrue(GraphStyleChoice.palette(f1) in 0..2)
        assertEquals(listOf("blackHole", "rocky", "gasGiant", "comet", "pulsar", "sun"), SpaceStyle.entries.map { it.rawValue })
    }
}
