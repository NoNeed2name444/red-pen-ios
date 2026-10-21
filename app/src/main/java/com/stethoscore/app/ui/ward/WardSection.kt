package com.stethoscore.app.ui.ward

// A port of WardSection from upstream/ios/RedPen/Shared/Ward/WardLook.swift.
//
// The parts of the app, each with a colour of its own (palette direction 3,
// seven section colours). Every accent is drawn from the section's hue: the
// paper's grid and the controls' edges (`ink`), the words and glyphs of
// buttons, links, the chosen tab, progress and a right answer (`accent`), and
// the fills under white words (`fill`). The base, the cards, the body text
// and the colours that mean something (Discharge green, Resus red, Caution
// amber, ECG red, the beam) stay the Ward palette's.

/** One section's colours, light and dark (WardSection's table). */
data class WardSectionColours(
    val hue: Double,
    val ink: WardPair,
    val accent: WardPair,
    val fill: WardPair,
)

@Suppress("EnumEntryName")
enum class WardSection {
    questions, cards, textbook, cases, osce, audio, ideas;

    private val colours: WardSectionColours get() = table.getValue(this)

    /** The hue, in OKLCH degrees. */
    val hue: Double get() = colours.hue

    /** The grid's lines and the controls' edges: 3:1 on the base and a card at a control's edge strength. */
    val ink: WardPair get() = colours.ink

    /** Words and glyphs in the section's colour: 4.5:1 on every tier of its mode. */
    val accent: WardPair get() = colours.accent

    /** A fill under white words: white reads 4.5:1 on it. */
    val fill: WardPair get() = colours.fill

    fun accent(dark: Boolean): Int = accent.of(dark)
    fun fill(dark: Boolean): Int = fill.of(dark)
    fun ink(dark: Boolean): Int = ink.of(dark)

    companion object {
        /**
         * The look outside any section: Cards' indigo, which is also the
         * palette's primary. Not Questions, or every screen without a
         * section would turn red.
         */
        val outside: WardSection = cards

        /** The colours that mean something, which no section's accent may look like. */
        val semanticTokens: List<WardToken> =
            listOf(WardToken.success, WardToken.danger, WardToken.warning, WardToken.ecg, WardToken.beam)

        // Generated on iOS by tools/ward_accents.py; copied verbatim.
        // (ink, accent, fill) as (light, dark) 0xRRGGBB.
        private val table: Map<WardSection, WardSectionColours> by lazy {
            mapOf(
                questions to WardSectionColours(20.0, WardPair(0xC82D40, 0xF0777A), WardPair(0x970525, 0xD98888), WardPair(0xC03946, 0xCB3E4B)),
                cards to WardSectionColours(274.0, WardPair(0x5866E5, 0xA5B6FE), WardPair(0x4046C2, 0xA5B6FE), WardPair(0x5260BC, 0x5A68C5)),
                textbook to WardSectionColours(186.0, WardPair(0x0E7C74, 0x0FC8BA), WardPair(0x065650, 0x0FC8BA), WardPair(0x227D75, 0x258279)),
                cases to WardSectionColours(51.0, WardPair(0xAC5102, 0xF48C49), WardPair(0x783907, 0xF48C49), WardPair(0xAC5A21, 0xB05C23)),
                osce to WardSectionColours(149.0, WardPair(0x01712E, 0x5DC474), WardPair(0x024B1D, 0x5DC474), WardPair(0x3D7C49, 0x42814F)),
                audio to WardSectionColours(307.0, WardPair(0x9853D0, 0xCD99FE), WardPair(0x772FAB, 0xCD99FE), WardPair(0x8150AD, 0x8B57B8)),
                ideas to WardSectionColours(346.0, WardPair(0xC74195, 0xE97EBB), WardPair(0x9E1071, 0xE97EBB), WardPair(0xB23E86, 0xBA438E)),
            )
        }

        /**
         * Where a kind of set lives, by StudySetKind's raw value. A kind not
         * listed is a question set, so it is Questions, not the outside look.
         */
        fun fromKindRaw(kindRaw: String): WardSection = when (kindRaw) {
            "anki" -> cards
            "book" -> textbook
            "cases" -> cases
            "osce" -> osce
            "narrate" -> audio
            else -> questions
        }
    }
}

/** The wash behind the word being spoken in Audio: the section's fill at this strength, under Chart Ink words. */
object WardWash {
    const val alpha = 0.22
}
