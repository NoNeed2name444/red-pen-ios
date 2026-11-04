package com.stethoscore.app.ui.ward

// A port of WardSection from ios/RedPen/Shared/Ward/WardLook.swift.
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
     * The ground behind every page: the plain base (WardPalette background),
     * #E9EDF2 by day and #171C24 at night, in every section. This is the ground
     * from before the section's wash (iOS 73f09a7, 21 Oct), which the owner
     * never asked for; the owner's phone build has plain grey grounds.
     */
    val wash: WardPair get() = WardPalette.table.getValue(WardToken.background)

    fun wash(dark: Boolean): Int = wash.of(dark)

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

        // The owner's 2026-10-21 hexes, exactly, in every role and both modes
        // (the mapping of docs/design/palette-2026-10-21.md).
        // (ink, accent, fill) as (light, dark) 0xRRGGBB.
        private val table: Map<WardSection, WardSectionColours> by lazy {
            mapOf(
                questions to WardSectionColours(23.0, WardPair(0xFF6B6B, 0xFF6B6B), WardPair(0xFF6B6B, 0xFF6B6B), WardPair(0xFF6B6B, 0xFF6B6B)),
                cards to WardSectionColours(260.0, WardPair(0x3B82F6, 0x3B82F6), WardPair(0x3B82F6, 0x3B82F6), WardPair(0x3B82F6, 0x3B82F6)),
                textbook to WardSectionColours(182.0, WardPair(0x14B8A6, 0x14B8A6), WardPair(0x14B8A6, 0x14B8A6), WardPair(0x14B8A6, 0x14B8A6)),
                cases to WardSectionColours(42.0, WardPair(0xFF9F7A, 0xFF9F7A), WardPair(0xFF9F7A, 0xFF9F7A), WardPair(0xFF9F7A, 0xFF9F7A)),
                osce to WardSectionColours(129.0, WardPair(0xA3E635, 0xA3E635), WardPair(0xA3E635, 0xA3E635), WardPair(0xA3E635, 0xA3E635)),
                audio to WardSectionColours(294.0, WardPair(0xA78BFA, 0xA78BFA), WardPair(0xA78BFA, 0xA78BFA), WardPair(0xA78BFA, 0xA78BFA)),
                ideas to WardSectionColours(350.0, WardPair(0xF472B6, 0xF472B6), WardPair(0xF472B6, 0xF472B6), WardPair(0xF472B6, 0xF472B6)),
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

/**
 * The colour wash behind a mode's screens (the owner, 4 Nov; iOS WardModeWash):
 * the base, top to bottom, mixed toward the mode's earlier colour, which serves
 * the wash alone (buttons, words and glyphs keep the section's accent). The
 * colour is first pulled toward grey, and the mix runs from the top edge to
 * nothing by a quarter down, nothing to six tenths, then up to the bottom edge;
 * at night it is weaker. Ideas has none. Mixed in plain sRGB components.
 */
object WardModeWash {
    /** Each mode's earlier colour, 0xRRGGBB. */
    val colour: Map<WardSection, Int> = mapOf(
        WardSection.questions to 0xC72929, WardSection.cards to 0x4F5CDB, WardSection.textbook to 0x1A8C80,
        WardSection.cases to 0xE67D21, WardSection.osce to 0x339E59, WardSection.audio to 0x8C52CC,
    )

    /** How far the colour is pulled toward [grey] before it is mixed in. */
    const val greyPull = 0.35
    val grey = WardRgb(0.5, 0.5, 0.52)

    /** (location, mix) from the top edge to the bottom edge. */
    val stops: List<Pair<Double, Double>> = listOf(0.0 to 0.08, 0.25 to 0.0, 0.60 to 0.0, 1.0 to 0.12)

    /** The night's share of each mix. */
    const val night = 0.7

    /** The wash's colour at [mix] (before the night's share), or null where the section has none. */
    fun hex(section: WardSection, dark: Boolean, mix: Double): Int? {
        val old = colour[section] ?: return null
        val o = WardPalette.rgb(old)
        val hue = WardRgb(o.r + (grey.r - o.r) * greyPull, o.g + (grey.g - o.g) * greyPull, o.b + (grey.b - o.b) * greyPull)
        val base = WardPalette.rgb(WardPalette.hex(WardToken.background, dark))
        val t = mix * (if (dark) night else 1.0)
        fun channel(b: Double, to: Double): Int = WardPalette.round((b + (to - b) * t).coerceIn(0.0, 1.0) * 255)
        return (channel(base.r, hue.r) shl 16) or (channel(base.g, hue.g) shl 8) or channel(base.b, hue.b)
    }

    /** The wash's stops as 0xRRGGBB, top to bottom, or null for no wash. */
    fun stops(section: WardSection, dark: Boolean): List<Pair<Double, Int>>? {
        if (section !in colour) return null
        return stops.map { (at, mix) -> at to hex(section, dark, mix)!! }
    }

    /** The wash at its strongest, the bottom edge, where contrast is least. */
    fun strongest(section: WardSection, dark: Boolean): Int? = hex(section, dark, stops.maxOf { it.second })

    /** The wash at the top edge, under the bar area. */
    fun top(section: WardSection, dark: Boolean): Int? = hex(section, dark, stops.first().second)
}

/** The wash behind the word being spoken in Audio: the section's fill at this strength, under Chart Ink words. */
object WardWash {
    const val alpha = 0.22
}
