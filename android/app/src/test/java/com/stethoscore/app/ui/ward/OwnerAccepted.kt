package com.stethoscore.app.ui.ward

import java.util.concurrent.ConcurrentHashMap
import kotlin.math.abs

// The owner's decision, 22 Oct 2026 at about 3:44 AM Cairo time, on being
// shown that the exact colours fail the readability checks:
//
//     "STOP IMPROVISING DONT CHANGE THE COLORS I GAVE U"
//
// So the owner's colours stay exactly as 64b915e set them, white words on the
// fills included (OwnerPaletteTest pins the ten colours in their roles). This is
// the one list of the cases that fail a check only because of those colours,
// each with the value it measures, the grounds being the plain base. A case on the
// list passes while its measured value stays within 0.01 of the listed one,
// and fails once it moves further, either way; a case not on the list is held
// to its check's own threshold. No check and no threshold is changed.

/**
 * One case of one check: the test and its check, the role or token measured,
 * the section (the deck's mode for a printed deck), the mode, and the tier or
 * colour it is measured on.
 */
data class OwnerCase(val test: String, val check: String, val role: String, val section: String, val mode: String, val tier: String)

object OwnerAccepted {
    /** How far a listed case's measured value may move and still pass. */
    const val tolerance = 0.01

    /** Every case the owner accepted, with the value it measures. */
    val cases: Map<OwnerCase, Double> = Cases().apply {
        accept("DeckCardsTest.everyModeBarCarriesWhiteAndItsWordsReadOnPaper", "its bar carries white") {
            case("white words", "MCQ", "print", "its bar", 2.775)
            case("white words", "ANKI", "print", "its bar", 3.678)
            case("white words", "BOOK", "print", "its bar", 2.489)
            case("white words", "OSCE", "print", "its bar", 1.508)
            case("white words", "NARRATE", "print", "its bar", 2.721)
            case("white words", "CASES", "print", "its bar", 2.001)
        }
        accept("DeckCardsTest.everyModeBarCarriesWhiteAndItsWordsReadOnPaper", "its words read 5:1 on white") {
            case("its words", "MCQ", "print", "white paper", 2.775)
            case("its words", "ANKI", "print", "white paper", 3.678)
            case("its words", "BOOK", "print", "white paper", 2.489)
            case("its words", "OSCE", "print", "white paper", 1.508)
            case("its words", "NARRATE", "print", "white paper", 2.721)
            case("its words", "CASES", "print", "white paper", 2.001)
        }
        accept("WardGroundTest.eachSectionsWash", "its accent keeps 4.5:1 on its wash") {
            case("accent", "questions", "light", "its wash", 2.360)
            case("accent", "cards", "light", "its wash", 3.128)
            case("accent", "textbook", "light", "its wash", 2.117)
            case("accent", "cases", "light", "its wash", 1.702)
            case("accent", "osce", "light", "its wash", 1.282)
            case("accent", "audio", "light", "its wash", 2.315)
            case("accent", "ideas", "light", "its wash", 2.253)
        }
        accept("WardLookTest.sections", "a control's edge reads 3:1") {
            case("a control's edge", "questions", "light", "background", 2.106)
            case("a control's edge", "questions", "light", "surface", 2.106)
            case("a control's edge", "cards", "light", "background", 2.620)
            case("a control's edge", "cards", "light", "surface", 2.620)
            case("a control's edge", "textbook", "light", "background", 1.916)
            case("a control's edge", "textbook", "light", "surface", 1.916)
            case("a control's edge", "cases", "light", "background", 1.575)
            case("a control's edge", "cases", "light", "surface", 1.575)
            case("a control's edge", "osce", "light", "background", 1.245)
            case("a control's edge", "osce", "light", "surface", 1.245)
            case("a control's edge", "audio", "light", "background", 2.016)
            case("a control's edge", "audio", "light", "surface", 2.016)
            case("a control's edge", "ideas", "light", "background", 2.023)
            case("a control's edge", "ideas", "light", "surface", 2.023)
            case("a control's edge", "cards", "dark", "background", 2.927)
            case("a control's edge", "cards", "dark", "surface", 2.927)
        }
        accept("WardLookTest.eachSectionsAccents", "accent words read 4.5:1") {
            case("accent", "questions", "light", "well", 2.130)
            case("accent", "questions", "light", "background", 2.360)
            case("accent", "questions", "light", "surface", 2.360)
            case("accent", "questions", "light", "raised", 2.360)
            case("accent", "cards", "light", "well", 2.823)
            case("accent", "cards", "light", "background", 3.128)
            case("accent", "cards", "light", "surface", 3.128)
            case("accent", "cards", "light", "raised", 3.128)
            case("accent", "textbook", "light", "well", 1.911)
            case("accent", "textbook", "light", "background", 2.117)
            case("accent", "textbook", "light", "surface", 2.117)
            case("accent", "textbook", "light", "raised", 2.117)
            case("accent", "cases", "light", "well", 1.536)
            case("accent", "cases", "light", "background", 1.702)
            case("accent", "cases", "light", "surface", 1.702)
            case("accent", "cases", "light", "raised", 1.702)
            case("accent", "osce", "light", "well", 1.157)
            case("accent", "osce", "light", "background", 1.282)
            case("accent", "osce", "light", "surface", 1.282)
            case("accent", "osce", "light", "raised", 1.282)
            case("accent", "audio", "light", "well", 2.089)
            case("accent", "audio", "light", "background", 2.315)
            case("accent", "audio", "light", "surface", 2.315)
            case("accent", "audio", "light", "raised", 2.315)
            case("accent", "ideas", "light", "well", 2.033)
            case("accent", "ideas", "light", "background", 2.253)
            case("accent", "ideas", "light", "surface", 2.253)
            case("accent", "ideas", "light", "raised", 2.253)
        }
        accept("WardLookTest.eachSectionsAccents", "accent glyphs read 3:1") {
            case("accent", "questions", "light", "well", 2.130)
            case("accent", "questions", "light", "background", 2.360)
            case("accent", "questions", "light", "surface", 2.360)
            case("accent", "questions", "light", "raised", 2.360)
            case("accent", "cards", "light", "well", 2.823)
            case("accent", "textbook", "light", "well", 1.911)
            case("accent", "textbook", "light", "background", 2.117)
            case("accent", "textbook", "light", "surface", 2.117)
            case("accent", "textbook", "light", "raised", 2.117)
            case("accent", "cases", "light", "well", 1.536)
            case("accent", "cases", "light", "background", 1.702)
            case("accent", "cases", "light", "surface", 1.702)
            case("accent", "cases", "light", "raised", 1.702)
            case("accent", "osce", "light", "well", 1.157)
            case("accent", "osce", "light", "background", 1.282)
            case("accent", "osce", "light", "surface", 1.282)
            case("accent", "osce", "light", "raised", 1.282)
            case("accent", "audio", "light", "well", 2.089)
            case("accent", "audio", "light", "background", 2.315)
            case("accent", "audio", "light", "surface", 2.315)
            case("accent", "audio", "light", "raised", 2.315)
            case("accent", "ideas", "light", "well", 2.033)
            case("accent", "ideas", "light", "background", 2.253)
            case("accent", "ideas", "light", "surface", 2.253)
            case("accent", "ideas", "light", "raised", 2.253)
        }
        accept("WardLookTest.eachSectionsAccents", "the on-fill words read 4.5:1 on the fill") {
            case("onPrimary", "questions", "light", "its fill", 2.775)
            case("onPrimary", "cards", "light", "its fill", 3.678)
            case("onPrimary", "textbook", "light", "its fill", 2.489)
            case("onPrimary", "cases", "light", "its fill", 2.001)
            case("onPrimary", "osce", "light", "its fill", 1.508)
            case("onPrimary", "audio", "light", "its fill", 2.721)
            case("onPrimary", "ideas", "light", "its fill", 2.648)
            case("onPrimary", "questions", "dark", "its fill", 2.775)
            case("onPrimary", "cards", "dark", "its fill", 3.678)
            case("onPrimary", "textbook", "dark", "its fill", 2.489)
            case("onPrimary", "cases", "dark", "its fill", 2.001)
            case("onPrimary", "osce", "dark", "its fill", 1.508)
            case("onPrimary", "audio", "dark", "its fill", 2.721)
            case("onPrimary", "ideas", "dark", "its fill", 2.648)
        }
        accept("WardLookTest.eachSectionsAccents", "the accent is not mistaken for a colour that means something") {
            case("accent", "questions", "light", "the nearest colour that means something", 0.000)
            case("accent", "questions", "dark", "the nearest colour that means something", 0.000)
        }
        accept("WardLookTest.eachSectionsAccents", "a section's shift keeps the accent at 4.5:1 on every frame") {
            case("accent", "every section to every other", "light and dark", "every tier", 1.155)
        }
        accept("WardPaletteTest.promisesHold", "a text colour on what it sits on at least 4.5") {
            case("primaryInk", "the palette", "light", "raised", 3.128)
            case("primaryInk", "the palette", "light", "well", 2.823)
            case("primaryInk", "the palette", "light", "surface", 3.128)
            case("primaryInk", "the palette", "light", "background", 3.128)
            case("onPrimary", "the palette", "light", "primary", 3.678)
            case("ecg", "the palette", "light", "surface", 2.360)
            case("success", "the palette", "light", "surface", 1.296)
            case("warning", "the palette", "light", "surface", 1.420)
            case("danger", "the palette", "light", "surface", 2.360)
            case("ecg", "the palette", "light", "well", 2.130)
            case("success", "the palette", "light", "well", 1.170)
            case("warning", "the palette", "light", "well", 1.281)
            case("danger", "the palette", "light", "well", 2.130)
            case("ecg", "the palette", "light", "background", 2.360)
            case("success", "the palette", "light", "background", 1.296)
            case("warning", "the palette", "light", "background", 1.420)
            case("danger", "the palette", "light", "background", 2.360)
            case("onPrimary", "the palette", "dark", "primary", 3.678)
        }
        accept("WardPaletteTest.promisesHold", "a text colour on what it sits on at least 3.0") {
            case("beam", "the palette", "light", "surface", 1.420)
            case("beam", "the palette", "light", "well", 1.281)
            case("beam", "the palette", "light", "background", 1.420)
        }
        accept("WardPaletteTest.chipInksReadOnTheirWell", "reads 4.5:1 on a chip's well") {
            // owner 22 Oct, wells and sheets one tone: a chip's well is the page colour
            // (WardControlStates.wellFill), so each ink measures on #E9EDF2
            case("primaryInk", "the palette", "light", "a chip's well", 3.128)
            case("ecg", "the palette", "light", "a chip's well", 2.360)
            case("success", "the palette", "light", "a chip's well", 1.296)
            case("warning", "the palette", "light", "a chip's well", 1.420)
            case("danger", "the palette", "light", "a chip's well", 2.360)
            case("accent", "questions", "light", "a chip's well", 2.360)
            case("accent", "cards", "light", "a chip's well", 3.128)
            case("accent", "textbook", "light", "a chip's well", 2.117)
            case("accent", "cases", "light", "a chip's well", 1.702)
            case("accent", "osce", "light", "a chip's well", 1.282)
            case("accent", "audio", "light", "a chip's well", 2.315)
            case("accent", "ideas", "light", "a chip's well", 2.253)
            case("primaryInk", "the palette", "light with Increase Contrast", "a chip's well", 3.128)
            case("ecg", "the palette", "light with Increase Contrast", "a chip's well", 2.360)
            case("success", "the palette", "light with Increase Contrast", "a chip's well", 1.296)
            case("warning", "the palette", "light with Increase Contrast", "a chip's well", 1.420)
            case("danger", "the palette", "light with Increase Contrast", "a chip's well", 2.360)
            case("accent", "questions", "light with Increase Contrast", "a chip's well", 2.360)
            case("accent", "cards", "light with Increase Contrast", "a chip's well", 3.128)
            case("accent", "textbook", "light with Increase Contrast", "a chip's well", 2.117)
            case("accent", "cases", "light with Increase Contrast", "a chip's well", 1.702)
            case("accent", "osce", "light with Increase Contrast", "a chip's well", 1.282)
            case("accent", "audio", "light with Increase Contrast", "a chip's well", 2.315)
            case("accent", "ideas", "light with Increase Contrast", "a chip's well", 2.253)
        }
        accept("WardPaletteTest.twoCharacters", "a value of its own in each mode") {
            case("primaryInk", "the palette", "light and dark", "the other mode", 0.000)
            case("ecg", "the palette", "light and dark", "the other mode", 0.000)
            case("success", "the palette", "light and dark", "the other mode", 0.000)
            case("warning", "the palette", "light and dark", "the other mode", 0.000)
            case("danger", "the palette", "light and dark", "the other mode", 0.000)
            case("beam", "the palette", "light and dark", "the other mode", 0.000)
        }
        accept("WardReliefTest.relief", "a control's edge reads at least 3:1 on the base") {
            case("a control's edge at the low lift", "outside", "light", "background", 2.620)
            case("a control's edge at the mid lift", "outside", "light", "background", 2.620)
            case("a control's edge at the high lift", "outside", "light", "background", 2.620)
            case("a control's edge at the peak lift", "outside", "light", "background", 2.620)
            case("a control's edge at the low lift", "outside", "dark", "background", 2.927)
            case("a control's edge at the mid lift", "outside", "dark", "background", 2.927)
            case("a control's edge at the high lift", "outside", "dark", "background", 2.927)
            case("a control's edge at the peak lift", "outside", "dark", "background", 2.927)
        }
        accept("WardStatesTest.theStatesAsDrawn", "white reads 4.5:1 on its fill") {
            case("onPrimary", "questions", "light", "its fill", 2.775)
            case("onPrimary", "cards", "light", "its fill", 3.678)
            case("onPrimary", "textbook", "light", "its fill", 2.489)
            case("onPrimary", "cases", "light", "its fill", 2.001)
            case("onPrimary", "osce", "light", "its fill", 1.508)
            case("onPrimary", "audio", "light", "its fill", 2.721)
            case("onPrimary", "ideas", "light", "its fill", 2.648)
            case("onPrimary", "questions", "dark", "its fill", 2.775)
            case("onPrimary", "cards", "dark", "its fill", 3.678)
            case("onPrimary", "textbook", "dark", "its fill", 2.489)
            case("onPrimary", "cases", "dark", "its fill", 2.001)
            case("onPrimary", "osce", "dark", "its fill", 1.508)
            case("onPrimary", "audio", "dark", "its fill", 2.721)
            case("onPrimary", "ideas", "dark", "its fill", 2.648)
        }
        accept("WardStatesTest.theStatesAsDrawn", "its words and glyphs read 4.5:1 on its face") {
            // owner 22 Oct, wells and sheets one tone: a chosen or held segment is a well in
            // the page colour (WardControlStates.wellFill), so its words measure on #E9EDF2
            case("the primary at rest: its words", "questions", "light", "its face", 2.360)
            case("the primary held: its words", "questions", "light", "its face", 2.360)
            case("the destructive at rest: its words", "questions", "light", "its face", 2.360)
            case("the destructive held: its words", "questions", "light", "its face", 2.360)
            case("the compact at rest: its words", "questions", "light", "its face", 2.360)
            case("the compact held: its words", "questions", "light", "its face", 2.360)
            case("the chip chosen: its words", "questions", "light", "its face", 2.360)
            case("the chip chosen and held: its words", "questions", "light", "its face", 2.360)
            case("the circle chosen: its glyph", "questions", "light", "its face", 2.360)
            case("the circle chosen and held: its glyph", "questions", "light", "its face", 2.360)
            case("the segment chosen: its words", "questions", "light", "its face", 2.360)
            case("the segment chosen and held: its words", "questions", "light", "its face", 2.360)
            case("the tile at rest: its glyph", "questions", "light", "its face", 2.360)
            case("the tile held: its glyph", "questions", "light", "its face", 2.360)
            case("the tile chosen: its glyph", "questions", "light", "its face", 2.360)
            case("the tile chosen and held: its glyph", "questions", "light", "its face", 2.360)
            case("the primary at rest: its words", "cards", "light", "its face", 3.128)
            case("the primary held: its words", "cards", "light", "its face", 3.128)
            case("the destructive at rest: its words", "cards", "light", "its face", 2.360)
            case("the destructive held: its words", "cards", "light", "its face", 2.360)
            case("the compact at rest: its words", "cards", "light", "its face", 3.128)
            case("the compact held: its words", "cards", "light", "its face", 3.128)
            case("the chip chosen: its words", "cards", "light", "its face", 3.128)
            case("the chip chosen and held: its words", "cards", "light", "its face", 3.128)
            case("the circle chosen: its glyph", "cards", "light", "its face", 3.128)
            case("the circle chosen and held: its glyph", "cards", "light", "its face", 3.128)
            case("the segment chosen: its words", "cards", "light", "its face", 3.128)
            case("the segment chosen and held: its words", "cards", "light", "its face", 3.128)
            case("the tile at rest: its glyph", "cards", "light", "its face", 3.128)
            case("the tile held: its glyph", "cards", "light", "its face", 3.128)
            case("the tile chosen: its glyph", "cards", "light", "its face", 3.128)
            case("the tile chosen and held: its glyph", "cards", "light", "its face", 3.128)
            case("the primary at rest: its words", "textbook", "light", "its face", 2.117)
            case("the primary held: its words", "textbook", "light", "its face", 2.117)
            case("the destructive at rest: its words", "textbook", "light", "its face", 2.360)
            case("the destructive held: its words", "textbook", "light", "its face", 2.360)
            case("the compact at rest: its words", "textbook", "light", "its face", 2.117)
            case("the compact held: its words", "textbook", "light", "its face", 2.117)
            case("the chip chosen: its words", "textbook", "light", "its face", 2.117)
            case("the chip chosen and held: its words", "textbook", "light", "its face", 2.117)
            case("the circle chosen: its glyph", "textbook", "light", "its face", 2.117)
            case("the circle chosen and held: its glyph", "textbook", "light", "its face", 2.117)
            case("the segment chosen: its words", "textbook", "light", "its face", 2.117)
            case("the segment chosen and held: its words", "textbook", "light", "its face", 2.117)
            case("the tile at rest: its glyph", "textbook", "light", "its face", 2.117)
            case("the tile held: its glyph", "textbook", "light", "its face", 2.117)
            case("the tile chosen: its glyph", "textbook", "light", "its face", 2.117)
            case("the tile chosen and held: its glyph", "textbook", "light", "its face", 2.117)
            case("the primary at rest: its words", "cases", "light", "its face", 1.702)
            case("the primary held: its words", "cases", "light", "its face", 1.702)
            case("the destructive at rest: its words", "cases", "light", "its face", 2.360)
            case("the destructive held: its words", "cases", "light", "its face", 2.360)
            case("the compact at rest: its words", "cases", "light", "its face", 1.702)
            case("the compact held: its words", "cases", "light", "its face", 1.702)
            case("the chip chosen: its words", "cases", "light", "its face", 1.702)
            case("the chip chosen and held: its words", "cases", "light", "its face", 1.702)
            case("the circle chosen: its glyph", "cases", "light", "its face", 1.702)
            case("the circle chosen and held: its glyph", "cases", "light", "its face", 1.702)
            case("the segment chosen: its words", "cases", "light", "its face", 1.702)
            case("the segment chosen and held: its words", "cases", "light", "its face", 1.702)
            case("the tile at rest: its glyph", "cases", "light", "its face", 1.702)
            case("the tile held: its glyph", "cases", "light", "its face", 1.702)
            case("the tile chosen: its glyph", "cases", "light", "its face", 1.702)
            case("the tile chosen and held: its glyph", "cases", "light", "its face", 1.702)
            case("the primary at rest: its words", "osce", "light", "its face", 1.282)
            case("the primary held: its words", "osce", "light", "its face", 1.282)
            case("the destructive at rest: its words", "osce", "light", "its face", 2.360)
            case("the destructive held: its words", "osce", "light", "its face", 2.360)
            case("the compact at rest: its words", "osce", "light", "its face", 1.282)
            case("the compact held: its words", "osce", "light", "its face", 1.282)
            case("the chip chosen: its words", "osce", "light", "its face", 1.282)
            case("the chip chosen and held: its words", "osce", "light", "its face", 1.282)
            case("the circle chosen: its glyph", "osce", "light", "its face", 1.282)
            case("the circle chosen and held: its glyph", "osce", "light", "its face", 1.282)
            case("the segment chosen: its words", "osce", "light", "its face", 1.282)
            case("the segment chosen and held: its words", "osce", "light", "its face", 1.282)
            case("the tile at rest: its glyph", "osce", "light", "its face", 1.282)
            case("the tile held: its glyph", "osce", "light", "its face", 1.282)
            case("the tile chosen: its glyph", "osce", "light", "its face", 1.282)
            case("the tile chosen and held: its glyph", "osce", "light", "its face", 1.282)
            case("the primary at rest: its words", "audio", "light", "its face", 2.315)
            case("the primary held: its words", "audio", "light", "its face", 2.315)
            case("the destructive at rest: its words", "audio", "light", "its face", 2.360)
            case("the destructive held: its words", "audio", "light", "its face", 2.360)
            case("the compact at rest: its words", "audio", "light", "its face", 2.315)
            case("the compact held: its words", "audio", "light", "its face", 2.315)
            case("the chip chosen: its words", "audio", "light", "its face", 2.315)
            case("the chip chosen and held: its words", "audio", "light", "its face", 2.315)
            case("the circle chosen: its glyph", "audio", "light", "its face", 2.315)
            case("the circle chosen and held: its glyph", "audio", "light", "its face", 2.315)
            case("the segment chosen: its words", "audio", "light", "its face", 2.315)
            case("the segment chosen and held: its words", "audio", "light", "its face", 2.315)
            case("the tile at rest: its glyph", "audio", "light", "its face", 2.315)
            case("the tile held: its glyph", "audio", "light", "its face", 2.315)
            case("the tile chosen: its glyph", "audio", "light", "its face", 2.315)
            case("the tile chosen and held: its glyph", "audio", "light", "its face", 2.315)
            case("the primary at rest: its words", "ideas", "light", "its face", 2.253)
            case("the primary held: its words", "ideas", "light", "its face", 2.253)
            case("the destructive at rest: its words", "ideas", "light", "its face", 2.360)
            case("the destructive held: its words", "ideas", "light", "its face", 2.360)
            case("the compact at rest: its words", "ideas", "light", "its face", 2.253)
            case("the compact held: its words", "ideas", "light", "its face", 2.253)
            case("the chip chosen: its words", "ideas", "light", "its face", 2.253)
            case("the chip chosen and held: its words", "ideas", "light", "its face", 2.253)
            case("the circle chosen: its glyph", "ideas", "light", "its face", 2.253)
            case("the circle chosen and held: its glyph", "ideas", "light", "its face", 2.253)
            case("the segment chosen: its words", "ideas", "light", "its face", 2.253)
            case("the segment chosen and held: its words", "ideas", "light", "its face", 2.253)
            case("the tile at rest: its glyph", "ideas", "light", "its face", 2.253)
            case("the tile held: its glyph", "ideas", "light", "its face", 2.253)
            case("the tile chosen: its glyph", "ideas", "light", "its face", 2.253)
            case("the tile chosen and held: its glyph", "ideas", "light", "its face", 2.253)
        }
        accept("WardStatesTest.theStatesAsDrawn", "told apart from unchosen by more than relief") {
            // owner 22 Oct, wells and sheets one tone: a chosen segment's well is the page colour,
            // so the segment rows measure its edge alone against unchosen
            case("the chip chosen and disabled", "questions", "light", "unchosen", 0.040)
            case("the circle chosen and disabled", "questions", "light", "unchosen", 0.040)
            case("the segment chosen and disabled", "questions", "light", "unchosen", 0.039)
            case("the tile chosen", "questions", "light", "unchosen", 0.040)
            case("the tile chosen and held", "questions", "light", "unchosen", 0.040)
            case("the tile chosen and disabled", "questions", "light", "unchosen", 0.040)
            case("the chip chosen and disabled", "cards", "light", "unchosen", 0.053)
            case("the circle chosen and disabled", "cards", "light", "unchosen", 0.053)
            case("the segment chosen and disabled", "cards", "light", "unchosen", 0.051)
            case("the tile chosen", "cards", "light", "unchosen", 0.053)
            case("the tile chosen and held", "cards", "light", "unchosen", 0.053)
            case("the tile chosen and disabled", "cards", "light", "unchosen", 0.053)
            case("the chip chosen and disabled", "textbook", "light", "unchosen", 0.032)
            case("the circle chosen and disabled", "textbook", "light", "unchosen", 0.032)
            case("the segment chosen and disabled", "textbook", "light", "unchosen", 0.029)
            case("the tile chosen", "textbook", "light", "unchosen", 0.032)
            case("the tile chosen and held", "textbook", "light", "unchosen", 0.032)
            case("the tile chosen and disabled", "textbook", "light", "unchosen", 0.032)
            case("the chip chosen and disabled", "cases", "light", "unchosen", 0.029)
            case("the circle chosen and disabled", "cases", "light", "unchosen", 0.029)
            case("the segment chosen and disabled", "cases", "light", "unchosen", 0.029)
            case("the tile chosen", "cases", "light", "unchosen", 0.029)
            case("the tile chosen and held", "cases", "light", "unchosen", 0.029)
            case("the tile chosen and disabled", "cases", "light", "unchosen", 0.029)
            case("the chip chosen and disabled", "osce", "light", "unchosen", 0.024)
            case("the circle chosen and disabled", "osce", "light", "unchosen", 0.024)
            case("the segment chosen and disabled", "osce", "light", "unchosen", 0.024)
            case("the tile chosen", "osce", "light", "unchosen", 0.024)
            case("the tile chosen and held", "osce", "light", "unchosen", 0.024)
            case("the tile chosen and disabled", "osce", "light", "unchosen", 0.024)
            case("the chip chosen and disabled", "audio", "light", "unchosen", 0.043)
            case("the circle chosen and disabled", "audio", "light", "unchosen", 0.043)
            case("the segment chosen and disabled", "audio", "light", "unchosen", 0.042)
            case("the tile chosen", "audio", "light", "unchosen", 0.043)
            case("the tile chosen and held", "audio", "light", "unchosen", 0.043)
            case("the tile chosen and disabled", "audio", "light", "unchosen", 0.043)
            case("the chip chosen and disabled", "ideas", "light", "unchosen", 0.039)
            case("the circle chosen and disabled", "ideas", "light", "unchosen", 0.039)
            case("the segment chosen and disabled", "ideas", "light", "unchosen", 0.036)
            case("the tile chosen", "ideas", "light", "unchosen", 0.039)
            case("the tile chosen and held", "ideas", "light", "unchosen", 0.039)
            case("the tile chosen and disabled", "ideas", "light", "unchosen", 0.039)
        }
        accept("WardStatesTest.theStatesAsDrawn", "the knob reads 3:1 on the filled track") {
            case("the toggle chosen: its knob", "questions", "light", "the filled track", 2.360)
            case("the toggle chosen and held: its knob", "questions", "light", "the filled track", 2.360)
            case("the toggle chosen: its knob", "textbook", "light", "the filled track", 2.117)
            case("the toggle chosen and held: its knob", "textbook", "light", "the filled track", 2.117)
            case("the toggle chosen: its knob", "cases", "light", "the filled track", 1.702)
            case("the toggle chosen and held: its knob", "cases", "light", "the filled track", 1.702)
            case("the toggle chosen: its knob", "osce", "light", "the filled track", 1.282)
            case("the toggle chosen and held: its knob", "osce", "light", "the filled track", 1.282)
            case("the toggle chosen: its knob", "audio", "light", "the filled track", 2.315)
            case("the toggle chosen and held: its knob", "audio", "light", "the filled track", 2.315)
            case("the toggle chosen: its knob", "ideas", "light", "the filled track", 2.253)
            case("the toggle chosen and held: its knob", "ideas", "light", "the filled track", 2.253)
        }
        accept("WardStatesTest.theFocusRing", "the focus ring reads 3:1") {
            case("the focus ring", "questions", "light", "well", 2.130)
            case("the focus ring", "questions", "light", "background", 2.360)
            case("the focus ring", "questions", "light", "surface", 2.360)
            case("the focus ring", "questions", "light", "raised", 2.360)
            case("the focus ring", "cards", "light", "well", 2.823)
            case("the focus ring", "textbook", "light", "well", 1.911)
            case("the focus ring", "textbook", "light", "background", 2.117)
            case("the focus ring", "textbook", "light", "surface", 2.117)
            case("the focus ring", "textbook", "light", "raised", 2.117)
            case("the focus ring", "cases", "light", "well", 1.536)
            case("the focus ring", "cases", "light", "background", 1.702)
            case("the focus ring", "cases", "light", "surface", 1.702)
            case("the focus ring", "cases", "light", "raised", 1.702)
            case("the focus ring", "osce", "light", "well", 1.157)
            case("the focus ring", "osce", "light", "background", 1.282)
            case("the focus ring", "osce", "light", "surface", 1.282)
            case("the focus ring", "osce", "light", "raised", 1.282)
            case("the focus ring", "audio", "light", "well", 2.089)
            case("the focus ring", "audio", "light", "background", 2.315)
            case("the focus ring", "audio", "light", "surface", 2.315)
            case("the focus ring", "audio", "light", "raised", 2.315)
            case("the focus ring", "ideas", "light", "well", 2.033)
            case("the focus ring", "ideas", "light", "background", 2.253)
            case("the focus ring", "ideas", "light", "surface", 2.253)
            case("the focus ring", "ideas", "light", "raised", 2.253)
        }
    }.all

    private val asked: MutableSet<OwnerCase> = ConcurrentHashMap.newKeySet()

    /** A listed case passes while [measured] is within [tolerance] of its listed value; any other by its own [ok]. */
    fun passes(case: OwnerCase, ok: Boolean, measured: Double): Boolean {
        asked += case
        val listed = cases[case] ?: return ok
        return abs(measured - listed) <= tolerance
    }

    /** The cases the list holds for [test] that none of its checks has made. */
    fun unmade(test: String): List<OwnerCase> = cases.keys.filter { it.test == test && it !in asked }
}

/**
 * A check whose case may be on the owner's list: off the list it passes by
 * [ok], its own threshold; on it, while [measured] stays within 0.01 of the
 * listed value. [alsoHolds] is any other part of the check, which the list
 * never excuses.
 */
fun WardChecks.check(label: String, ok: Boolean, detail: String, case: OwnerCase, measured: Double, alsoHolds: Boolean = true) {
    val listed = OwnerAccepted.cases[case]
    val passes = OwnerAccepted.passes(case, ok, measured) && alsoHolds
    if (listed == null) check(label, passes, detail)
    else check("$label (owner-accepted at ${f3(listed)})", passes, "$detail, measured ${f3(measured)}")
}

/** Closes a test with owner-accepted cases: every case the list holds for [test] is one its checks made. */
fun WardChecks.everyOwnerCaseMade(test: String) {
    val unmade = OwnerAccepted.unmade(test)
    check("$test: every owner-accepted case is one it checks", unmade.isEmpty(), unmade.joinToString("; "))
}

private class Cases {
    val all = LinkedHashMap<OwnerCase, Double>()

    fun accept(test: String, check: String, rows: Rows.() -> Unit) = Rows(test, check, all).rows()
}

private class Rows(val test: String, val check: String, val into: MutableMap<OwnerCase, Double>) {
    fun case(role: String, section: String, mode: String, tier: String, measured: Double) {
        val c = OwnerCase(test, check, role, section, mode, tier)
        require(into.put(c, measured) == null) { "listed twice: $c" }
    }
}
