package com.stethoscore.app.data

import com.stethoscore.app.export.AnkiFields
import com.stethoscore.app.export.MiniZip
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.Base64

/**
 * What comes in from outside - text pasted from somebody's notes, a set shared
 * from another phone - and what goes out to Anki: iOS Tests/ImportTests.swift,
 * check for check, with the same labels.
 */
class ImportTest {
    @get:Rule val temp = TemporaryFolder()

    private fun check(label: String, ok: Boolean, detail: String = "") =
        assertTrue(if (detail.isEmpty()) label else "$label  | $detail", ok)

    @Test fun pastedTextWithWindowsLineEndings() {
        // in Swift "\r\n" is one Character, so splitting on "\n" found no lines at all
        val windows = "Q1 | A;B;C;D | B | why\r\nQ2 | E;F;G;H | C | because\r\nQ3 | I;J | A | so"
        val mcq = PlainTextImport.parseMCQ(windows)
        check("a CRLF list is every question, not one", mcq.size == 3, "${mcq.size}")
        check("and nothing of the next line leaks into an explanation",
            mcq.firstOrNull()?.explanation == "why", mcq.firstOrNull()?.explanation ?: "")
        check("old Mac line endings split too",
            PlainTextImport.parseMCQ("Q1 | A;B | A | x\rQ2 | A;B | B | y").size == 2)
        val osce = PlainTextImport.parseOsce("## Knee exam\r\nInspect\r\nPalpate\r\n## Hip exam\r\nGait\r\n")
        check("OSCE stations split on CRLF", osce.size == 2 && osce.firstOrNull()?.steps == listOf("Inspect", "Palpate"),
            "${osce.map { it.title }} ${osce.firstOrNull()?.steps ?: emptyList()}")
        check("Narrate lines split on CRLF",
            PlainTextImport.parseNarrate("en|One\r\nar|اثنان\r\nThree").size == 3)
        check("Cards split on CRLF",
            PlainTextImport.parseAnkiQA("Front | a; b\r\n{{c1::Aorta}} carries blood | why").size == 2)
    }

    @Test fun theAnswerLetter() {
        check("a blank answer letter is not quietly A",
            PlainTextImport.parseMCQ("Stem | a; b; c; d |  | why").isEmpty(),
            "${PlainTextImport.parseMCQ("Stem | a; b; c; d |  | why").map { it.correctIndex }}")
        check("a full-width letter is not quietly A",
            PlainTextImport.parseMCQ("Stem | a; b; c; d | Ｂ | why").isEmpty())
        check("a digit is not a letter",
            PlainTextImport.parseMCQ("Stem | a; b; c; d | 2 | why").isEmpty())
        check("a lower-case letter still counts",
            PlainTextImport.parseMCQ("Stem | a; b; c; d | c | why").firstOrNull()?.correctIndex == 2)
        check("a letter past the options is refused",
            PlainTextImport.parseMCQ("Stem | a; b | D | why").isEmpty())
        check("B is 1", PlainTextImport.optionIndex(" B ") == 1)
    }

    @Test fun aSetSharedFromAnotherPhone() {
        val folder = newId()
        val picture = Base64.getEncoder().encodeToString("jpeg bytes".toByteArray())
        val shared = StudySet(name = "Heart", subject = "Cardiology", kind = StudySetKind.ANKI, folderId = folder,
            createdAt = 0, updatedAt = 0,
            images = listOf(picture, "blob:" + "a".repeat(64), picture),
            cards = listOf(
                AnkiCard(type = AnkiCardType.OCCLUSION, front = "What is labelled here?", bullets = listOf("Aorta"), imageIndex = 0,
                    occlusion = OcclusionBox(0.1, 0.1, 0.1, 0.1)),
                AnkiCard(type = AnkiCardType.OCCLUSION, front = "What is labelled here?", bullets = listOf("Vena cava"), imageIndex = 1,
                    occlusion = OcclusionBox(0.2, 0.2, 0.1, 0.1)),
                AnkiCard(type = AnkiCardType.OCCLUSION, front = "What is labelled here?", bullets = listOf("Septum"), imageIndex = 2,
                    occlusion = OcclusionBox(0.3, 0.3, 0.1, 0.1)),
                AnkiCard(type = AnkiCardType.QA, front = "Which valve?", bullets = listOf("Mitral"), imageIndex = 1)),
            bookMarkdown = "# Heart\n![Front view](image:0)\n![Missing](image:1)\n![Side view](image:2)")

        val now = 1_000_000_000L
        val isMissing: (String) -> Boolean = { it.startsWith("blob:") }
        val arrived = SetImport.received(shared, emptySet(), now, isMissing)
        check("a shared set gets an id of its own", arrived.set.id != shared.id)
        check("a folder this library does not have is dropped, so the set can be seen",
            arrived.set.folderId == null)
        check("and it is dated as new here",
            arrived.set.createdAt == now && arrived.set.updatedAt == now)
        check("a picture that only exists in the sender's account is left out",
            arrived.set.images == listOf(picture, picture) && arrived.missingPictures == 1,
            "${arrived.set.images.size} images, ${arrived.missingPictures} missing")
        check("the occlusion card that needed it goes with it",
            arrived.set.cards.none { it.bullets == listOf("Vena cava") })
        check("the cards after it point at their own picture still",
            arrived.set.cards.firstOrNull { it.bullets == listOf("Septum") }?.imageIndex == 1,
            "${arrived.set.cards.map { "${it.bullets.firstOrNull() ?: ""}:${it.imageIndex ?: -1}" }}")
        check("a written card keeps its words and loses only the picture",
            arrived.set.cards.firstOrNull { it.front == "Which valve?" }?.let { it.imageIndex == null } == true)
        check("a textbook page points at the renumbered pictures and drops the missing one",
            arrived.set.bookMarkdown == "# Heart\n![Front view](image:0)\n![Side view](image:1)",
            arrived.set.bookMarkdown)
        val home = SetImport.received(shared, setOf(folder), now, isMissing)
        check("a folder this library DOES have is kept", home.set.folderId == folder)
        val whole = shared.copy(images = listOf(picture), cards = listOf(shared.cards[0]))
        val untouched = SetImport.received(whole, emptySet(), now, isMissing)
        check("a set with every picture comes in whole",
            untouched.missingPictures == 0 && untouched.set.cards.size == 1 && untouched.set.images == listOf(picture))
    }

    @Test fun whatGoesIntoAnki() {
        check("a cloze is escaped like any other field",
            AnkiFields.cloze("<img src=x onerror=alert(1)>{{c1::aorta}}") == "&lt;img src=x onerror=alert(1)&gt;{{c1::aorta}}",
            AnkiFields.cloze("<img src=x onerror=alert(1)>{{c1::aorta}}"))
        check("ordinary medical text survives escaping",
            AnkiFields.cloze("{{c1::Na}} < 135 & K > 5") == "{{c1::Na}} &lt; 135 &amp; K &gt; 5")
        check("bold still works inside a cloze",
            AnkiFields.cloze("{{c1::**aorta**}}") == "{{c1::<b>aorta</b>}}")
        check("each cN is one card", AnkiFields.clozeOrdinals("{{c1::a}} {{c2::b}} {{c1::c}}") == listOf(0, 1))
        check("a c0 is not a card at ordinal -1", AnkiFields.clozeOrdinals("{{c0::a}}") == listOf(0))
        val split = AnkiFields.clozeCards("{{c1::Digoxin}} inhibits {{c2::Na/K ATPase::pump}}, raising {{c1::Ca}}")
        check("an Anki cloze note is a card per cN, each hiding only its own",
            split.map { it.number } == listOf(1, 2) &&
                split.map { it.text } == listOf("{{c1::Digoxin}} inhibits Na/K ATPase, raising {{c1::Ca}}",
                    "Digoxin inhibits {{c2::Na/K ATPase::pump}}, raising Ca"), "$split")
        check("a single-cN note is left as it is", AnkiFields.clozeCards("{{c1::a}} b").map { it.text } == listOf("{{c1::a}} b"))
        // a cloze whose braces were edited away is a basic note, not an empty card
        val lostBraces = AnkiFields.clozeNote("The aorta carries oxygenated blood", why = "Left ventricle out")
        check("a cloze with no deletion becomes a basic note", !lostBraces.isCloze, "$lostBraces")
        check("its sentence is the front and the why the back",
            lostBraces.fields == listOf("The aorta carries oxygenated blood",
                "<div class=\"why\"><b>Why / how</b>Left ventricle out</div>") && lostBraces.ordinals == listOf(0),
            "${lostBraces.fields}")
        check("a half-deleted cloze is not a cloze", !AnkiFields.clozeNote("The {{c1::aorta carries blood", why = "").isCloze)
        check("an empty deletion is not a cloze", !AnkiFields.clozeNote("The {{c1::}} carries blood", why = "").isCloze)
        check("a c0 alone is not a cloze", !AnkiFields.clozeNote("The {{c0::aorta}} carries blood", why = "").isCloze)
        val kept = AnkiFields.clozeNote("The {{c1::aorta}} carries {{c2::oxygenated}} blood", why = "**LV**")
        check("a real cloze stays a cloze note",
            kept.isCloze && kept.ordinals == listOf(0, 1) &&
                kept.fields == listOf("The {{c1::aorta}} carries {{c2::oxygenated}} blood", "<b>LV</b>"), "$kept")
        check("Anki's checksum reads the text, not the escaping",
            AnkiFields.stripped("<b>Na</b> &lt; 135 &amp;") == "Na < 135 &")
    }

    @Test fun theApkgsZip() {
        val folderDir = temp.newFolder("minizip")
        val first = File(folderDir, "a")
        val second = File(folderDir, "b")
        val big = ByteArray(3_000_000) { (it % 251).toByte() }   // several read chunks
        first.writeBytes("collection".toByteArray())
        second.writeBytes(big)
        val zipFile = File(folderDir, "deck.apkg")
        var wrote = true
        try { MiniZip.write(listOf("collection.anki2" to first, "0" to second), zipFile) } catch (e: Exception) { wrote = false }
        check("the archive is written from files", wrote)
        val back = if (zipFile.exists()) Zip.entries(zipFile.readBytes()) else emptyMap()
        check("and reads back entry for entry",
            back["collection.anki2"]?.contentEquals("collection".toByteArray()) == true && back["0"]?.contentEquals(big) == true,
            "${back.keys.sorted()} ${back["0"]?.size ?: -1}")
        check("its CRC is the standard one",
            MiniZip.crc32("123456789".toByteArray()) == 0xCBF43926L,
            MiniZip.crc32("123456789".toByteArray()).toString(16))
        var refused = false
        try {
            val many = List(70_000) { "x" to first }
            MiniZip.write(many, File(folderDir, "many.apkg"))
        } catch (e: Exception) { refused = true }
        check("more entries than a zip can count is an error, not a crash", refused)
    }

    @Test fun lectureLanguage() {
        // a Narrate set keeps what its lecture is spoken in across a save and a load
        val spoken = StudySet(name = "Cardiology lecture", kind = StudySetKind.NARRATE).withLanguage(LectureLanguage.ENGLISH)
        val spokenBack = runCatching { StudyJson.decodeSets(StudyJson.encodeSet(spoken).toString()).single() }.getOrNull()
        check("a set's lecture language survives a save and a load",
            spokenBack?.language == LectureLanguage.ENGLISH && spokenBack.lectureLanguage == "english",
            "${spokenBack?.lectureLanguage}")
        val older = runCatching { StudyJson.decodeSets("""{"name":"Old lecture","kind":"narrate"}""").single() }.getOrNull()
        check("a set saved before the language was kept reads as mixed",
            older != null && older.lectureLanguage == null && older.language == LectureLanguage.MIXED)
        val odd = runCatching { StudyJson.decodeSets("""{"name":"Odd","kind":"narrate","lectureLanguage":7}""").single() }.getOrNull()
        check("a language that is not text loses only the language, not the set",
            odd?.name == "Odd" && odd.language == LectureLanguage.MIXED)
    }
}
