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

    /**
     * The wash behind every page: the base mixed toward the section's fill
     * in linear light (WardPalette.mix): 0.06 by day, 0.10 at night.
     */
    val wash: WardPair get() = WardPair(wash(false), wash(true))

    fun wash(dark: Boolean): Int =
        WardPalette.mix(WardPalette.hex(WardToken.background, dark), fill(dark), if (dark) 0.10 else 0.06)

    companion object {
        /**
         * The look outside any section: Cards' Care Blue, which is also the
         * palette's primary. Not Questions, or every screen without a
         * section would turn red.
         */
        val outside: WardSection = cards

        /**
         * The section home opens on: the dock's first category, Questions
         * (home's category starts there). The window's starting background
         * and the first frame stand on its ground (WardGround).
         */
        val opening: WardSection = questions

        /** The colours that mean something, which no section's accent may look like. */
        val semanticTokens: List<WardToken> =
            listOf(WardToken.success, WardToken.danger, WardToken.warning, WardToken.ecg, WardToken.beam)

        // Generated on iOS by tools/ward_accents.py; copied verbatim.
        // (ink, accent, fill) as (light, dark) 0xRRGGBB.
        private val table: Map<WardSection, WardSectionColours> by lazy {
            mapOf(
                questions to WardSectionColours(23.0, WardPair(0xBE2130, 0xFEBAB5), WardPair(0x8A0219, 0xFEBAB5), WardPair(0xFF6B6B, 0xFF6B6B)),
                cards to WardSectionColours(260.0, WardPair(0x2A71E5, 0x84B2FD), WardPair(0x0251C2, 0x84B2FD), WardPair(0x3B82F6, 0x3B82F6)),
                textbook to WardSectionColours(182.0, WardPair(0x157C70, 0x1EC8B4), WardPair(0x0A574D, 0x1EC8B4), WardPair(0x14B8A6, 0x14B8A6)),
                cases to WardSectionColours(42.0, WardPair(0xCE4F08, 0xFE9F79), WardPair(0x983803, 0xFF9F7A), WardPair(0xFF9F7A, 0xFF9F7A)),
                osce to WardSectionColours(129.0, WardPair(0x476A05, 0xAFE172), WardPair(0x2D4601, 0xA3E635), WardPair(0xA3E635, 0xA3E635)),
                audio to WardSectionColours(294.0, WardPair(0x845BDD, 0xB097FD), WardPair(0x6538B8, 0xB097FD), WardPair(0xA78BFA, 0xA78BFA)),
                ideas to WardSectionColours(350.0, WardPair(0xCA3F8D, 0xF383BB), WardPair(0xA00B69, 0xF383BB), WardPair(0xF472B6, 0xF472B6)),
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
