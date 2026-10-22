package com.stethoscore.app.ui.ward

import com.stethoscore.app.data.OcclusionCovers
import com.stethoscore.app.data.StudySetKind
import com.stethoscore.app.export.DeckPalette
import com.stethoscore.app.ideas.NoteTone
import com.stethoscore.app.map.MapPalette
import org.junit.Test
import java.io.File
import kotlin.math.roundToInt

// The owner's ten colours, each its exact hex in every role the iOS repo's
// docs/design/palette-2026-10-21.md gives it on Android, in both modes, with
// white words on the fills. The owner, 22 Oct 2026: "STOP IMPROVISING DONT
// CHANGE THE COLORS I GAVE U" (OwnerAccepted lists the checks they fail). The
// brand mark and signal, the red pen, the widget and the launch pictures are
// the iPhone's only.
class OwnerPaletteTest {

    private val pulseTeal = 0x14B8A6
    private val freshMint = 0x6EE7B7
    private val careBlue = 0x3B82F6
    private val electricIndigo = 0x6366F1
    private val softLilac = 0xA78BFA
    private val vitalCoral = 0xFF6B6B
    private val peachGlow = 0xFF9F7A
    private val optimisticAmber = 0xFBBF24
    private val bubblegumPink = 0xF472B6
    private val limeZest = 0xA3E635

    private val modes = listOf(false, true)
    private fun mode(dark: Boolean) = if (dark) "dark" else "light"
    private fun byte(x: Double) = (x * 255).roundToInt()
    private fun hex(r: Double, g: Double, b: Double) = (byte(r) shl 16) or (byte(g) shl 8) or byte(b)
    private fun hex(rgb: FloatArray) = hex(rgb[0].toDouble(), rgb[1].toDouble(), rgb[2].toDouble())

    @Test fun theTenColoursInTheirRoles() = checks {
        val ten = listOf(pulseTeal, freshMint, careBlue, electricIndigo, softLilac, vitalCoral, peachGlow,
            optimisticAmber, bubblegumPink, limeZest)
        check("ten colours, each its own", ten.toSet().size == 10)

        // Questions Vital Coral, Cards Care Blue, Textbook Pulse Teal, Cases Peach Glow, OSCE Lime Zest,
        // Audio Soft Lilac, Ideas Bubblegum Pink: the section's ink, accent and fill, in both modes
        val sections = mapOf(
            WardSection.questions to vitalCoral, WardSection.cards to careBlue, WardSection.textbook to pulseTeal,
            WardSection.cases to peachGlow, WardSection.osce to limeZest, WardSection.audio to softLilac,
            WardSection.ideas to bubblegumPink,
        )
        check("every section has its colour", sections.keys == WardSection.entries.toSet())
        for ((s, want) in sections) for (dark in modes) {
            for ((role, got) in listOf("ink" to s.ink(dark), "accent" to s.accent(dark), "fill" to s.fill(dark))) {
                check("$s ${mode(dark)}: its $role is ${hx(want)}", got == want, hx(got))
            }
        }

        // Care Blue is the primary, the look outside any section (Cards'), and the paper's ink there;
        // a right answer is Fresh Mint; a wrong answer and the ECG red Vital Coral; due, warnings and the
        // progress beam Optimistic Amber; and the words on a fill are white
        check("the look outside any section is Cards'", WardSection.outside == WardSection.cards)
        val tokens = mapOf(
            WardToken.primary to careBlue, WardToken.primaryInk to careBlue, WardToken.success to freshMint,
            WardToken.danger to vitalCoral, WardToken.ecg to vitalCoral, WardToken.warning to optimisticAmber,
            WardToken.beam to optimisticAmber, WardToken.onPrimary to 0xFFFFFF,
        )
        for ((token, want) in tokens) for (dark in modes) {
            val got = WardPalette.hex(token, dark)
            check("${mode(dark)} $token is ${hx(want)}", got == want, hx(got))
        }
        // Material's words on its fills (onPrimary) are white in both modes too
        for (s in WardSection.entries) for (dark in modes) {
            val on = com.stethoscore.app.ui.wardColorScheme(WardLook(dark, s)).onPrimary
            check("${mode(dark)} $s: Material's onPrimary is white", on == com.stethoscore.app.ui.wardRgb(0xFFFFFF), on.toString())
        }
        for (dark in modes) for (hc in listOf(false, true)) {
            val got = WardPaper.ink(dark, highContrast = hc).hex
            check("${mode(dark)}${if (hc) " with Increase Contrast" else ""}: the paper's ink outside a section is Care Blue",
                got == careBlue, hx(got))
        }

        // the folders (NoteTone), in order
        val folders = listOf(pulseTeal, electricIndigo, peachGlow, softLilac, limeZest, bubblegumPink, careBlue)
        val tones = NoteTone.palette.map { hex(it) }
        check("the folders are Pulse Teal, Electric Indigo, Peach Glow, Soft Lilac, Lime Zest, Bubblegum Pink and Care Blue",
            tones == folders, tones.joinToString { hx(it) })

        // the occlusion cover (the asked label) is Peach Glow; Android's occlusion masks are Care Blue
        val cover = OcclusionCovers.targetRgb.let { hex(it.first, it.second, it.third) }
        check("the occlusion cover is Peach Glow", cover == peachGlow, hx(cover))
        val study = File("src/main/java/com/stethoscore/app/ui/StudyScreens.kt").takeIf { it.exists() }?.readText() ?: ""
        check("the occlusion masks are Care Blue", study.contains("drawRect(Color(0xFF3B82F6)"))

        // the exported deck: each mode's colour is its section's fill, and its bars and words are that hex
        val deck = mapOf(
            StudySetKind.MCQ to vitalCoral, StudySetKind.ANKI to careBlue, StudySetKind.BOOK to pulseTeal,
            StudySetKind.OSCE to limeZest, StudySetKind.NARRATE to softLilac, StudySetKind.CASES to peachGlow,
        )
        check("every mode of the deck has its colour", deck.keys == StudySetKind.entries.toSet())
        for ((kind, want) in deck) {
            val p = DeckPalette.of(kind)
            for ((role, got) in listOf("colour" to p, "bar" to p.barFill(), "words" to p.ink())) {
                val rgb = got.argb() and 0xFFFFFF
                check("the deck's $kind $role is ${hx(want)}", rgb == want, hx(rgb))
            }
        }

        // the graph's nodes (MapPalette), by group
        val nodes = (0 until MapPalette.rgb.size / 3).map {
            hex(MapPalette.rgb[3 * it].toDouble(), MapPalette.rgb[3 * it + 1].toDouble(), MapPalette.rgb[3 * it + 2].toDouble())
        }
        check("the graph's nodes are Care Blue, Pulse Teal, Optimistic Amber, Soft Lilac, Bubblegum Pink and Lime Zest",
            nodes == listOf(careBlue, pulseTeal, optimisticAmber, softLilac, bubblegumPink, limeZest), nodes.joinToString { hx(it) })
    }
}
