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
 * The colour wash behind a mode's screens (the owner, 4 Nov: "randomly tinted like
 * the screenshots", "stronger a bit"; iOS WardModeWash, the same numbers): the
 * earlier backdrop's uneven 3x3 mesh on the base, each point mixed toward the mode's
 * earlier colour, which serves the wash alone (buttons, words and glyphs keep the
 * section's accent). Each screen draws its own from a seed it keeps while shown: the
 * pattern is turned a quarter at a time and may be mirrored, so its strongest corner
 * lands anywhere; its pale middle may trade places with an edge's middle; every
 * point's strength moves, and the inner points move along their edge or, in the
 * middle, both ways; then all are made a quarter stronger, to [top]. A mode's colour
 * is pulled toward grey first, and the mesh is scaled so its strongest possible point
 * is that mode's cap, by day and at night: as strong as it can be while every colour
 * that reads on the plain base still reads on it. Ideas has none. Plain sRGB mixing.
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

    /** The earlier backdrop's strengths, row by row from the top left. */
    val strengths: List<Double> = listOf(0.30, 0.18, 0.26, 0.16, 0.05, 0.18, 0.24, 0.16, 0.30)

    /** How far a seed moves each point's strength, either way. */
    const val strengthJitter = 0.12

    /** How far a seed moves an inner point (in the unit square), either way. */
    const val pointJitter = 0.12

    /** Every strength is made this much stronger after the jitter, to [top]. */
    const val boost = 1.25
    const val top = 0.40

    /**
     * Each mode's mix at the mesh's strongest possible point, (day, night): the most
     * that keeps every pair that reads on the plain base reading (Chart Ink, Biro Grey
     * and the meaning colours at 4.5:1, the beam at 3:1, the section's accent at 4.5:1
     * as words and 3:1 as glyphs).
     */
    val cap: Map<WardSection, Pair<Double, Double>> = mapOf(
        WardSection.questions to (0.135 to 0.340), WardSection.cards to (0.030 to 0.030), WardSection.textbook to (0.160 to 0.255),
        WardSection.cases to (0.190 to 0.215), WardSection.osce to (0.180 to 0.230), WardSection.audio to (0.150 to 0.275),
    )

    /** The points a seed moves, and which way: the edges' middles along their edge, the middle both ways. */
    val moved: List<Triple<Int, Boolean, Boolean>> = listOf(
        Triple(1, true, false), Triple(3, false, true), Triple(4, true, true), Triple(5, false, true), Triple(7, true, false),
    )

    /** The edges' middles the pale middle may trade places with. */
    val paleSpots: List<Int> = listOf(1, 3, 5, 7)

    /** One screen's mesh: nine strengths and points, row by row. */
    data class Mesh(val strengths: List<Double>, val x: List<Double>, val y: List<Double>)

    /** The mesh for [seed], the same on every platform (SplitMix64; iOS takes the seed as UInt64). */
    fun mesh(seed: Long): Mesh {
        var state = seed
        fun unit(): Double {
            state += 0x9E3779B97F4A7C15uL.toLong()
            var z = state
            z = (z xor (z ushr 30)) * 0xBF58476D1CE4E5B9uL.toLong()
            z = (z xor (z ushr 27)) * 0x94D049BB133111EBuL.toLong()
            z = z xor (z ushr 31)
            return (z ushr 11).toDouble() * (1.0 / 9007199254740992.0)
        }
        val turns = minOf(3, (unit() * 4).toInt())
        val mirrored = unit() < 0.5
        val pale = minOf(4, (unit() * 5).toInt())
        var g = strengths
        repeat(turns) { val o = g; g = List(9) { o[(2 - it % 3) * 3 + it / 3] } }
        if (mirrored) { val o = g; g = List(9) { o[(it / 3) * 3 + 2 - it % 3] } }
        if (pale > 0) {
            val m = g.toMutableList()
            val j = paleSpots[pale - 1]
            m[4] = g[j]; m[j] = g[4]
            g = m
        }
        val s = g.map { minOf(top, maxOf(0.0, (it + strengthJitter * (2 * unit() - 1)) * boost)) }
        val x = mutableListOf(0.0, 0.5, 1.0, 0.0, 0.5, 1.0, 0.0, 0.5, 1.0)
        val y = mutableListOf(0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 1.0, 1.0, 1.0)
        for ((i, mx, my) in moved) {
            if (mx) x[i] += pointJitter * (2 * unit() - 1)
            if (my) y[i] += pointJitter * (2 * unit() - 1)
        }
        return Mesh(s, x, y)
    }

    /** The wash's colour at [mix] (the share of the mode's colour), or null where the section has none. */
    fun hex(section: WardSection, dark: Boolean, mix: Double): Int? {
        val old = colour[section] ?: return null
        val o = WardPalette.rgb(old)
        val hue = WardRgb(o.r + (grey.r - o.r) * greyPull, o.g + (grey.g - o.g) * greyPull, o.b + (grey.b - o.b) * greyPull)
        val base = WardPalette.rgb(WardPalette.hex(WardToken.background, dark))
        fun channel(b: Double, to: Double): Int = WardPalette.round((b + (to - b) * mix).coerceIn(0.0, 1.0) * 255)
        return (channel(base.r, hue.r) shl 16) or (channel(base.g, hue.g) shl 8) or channel(base.b, hue.b)
    }

    /** The mix a mesh [strength] draws at: scaled so [top] is the cap. */
    fun mix(section: WardSection, dark: Boolean, strength: Double): Double? =
        cap[section]?.let { (if (dark) it.second else it.first) * minOf(top, maxOf(0.0, strength)) / top }

    /** The mesh's nine colours as 0xRRGGBB, or null for no wash. */
    fun colours(section: WardSection, dark: Boolean, mesh: Mesh): List<Int>? {
        if (section !in colour) return null
        return mesh.strengths.map { hex(section, dark, mix(section, dark, it)!!)!! }
    }

    /**
     * The strength at ([x], [y]) in the unit square, blended from the nine points by
     * inverse squared distance: what Android draws, having no mesh gradient. Never
     * past the strongest point.
     */
    fun strength(mesh: Mesh, x: Double, y: Double): Double {
        var num = 0.0
        var den = 0.0
        for (i in 0 until 9) {
            val d2 = (x - mesh.x[i]) * (x - mesh.x[i]) + (y - mesh.y[i]) * (y - mesh.y[i])
            if (d2 < 1e-12) return mesh.strengths[i]
            num += mesh.strengths[i] / d2
            den += 1 / d2
        }
        return num / den
    }

    /** The wash as [width] x [height] ARGB pixels, each at its centre, or null for no wash: drawn once, stretched smooth. */
    fun pixels(section: WardSection, dark: Boolean, mesh: Mesh, width: Int, height: Int): IntArray? {
        if (section !in colour) return null
        return IntArray(width * height) { k ->
            val px = (k % width + 0.5) / width
            val py = (k / width + 0.5) / height
            hex(section, dark, mix(section, dark, strength(mesh, px, py))!!)!! or (0xFF shl 24)
        }
    }

    /** A solid bar's colour over the wash: the mean of its edge's row. */
    fun edge(section: WardSection, dark: Boolean, mesh: Mesh, bottom: Boolean): Int? {
        val row = if (bottom) mesh.strengths.subList(6, 9) else mesh.strengths.subList(0, 3)
        return mix(section, dark, row.sum() / 3)?.let { hex(section, dark, it) }
    }

    /** The wash at its strongest possible point, the cap, where contrast is least. */
    fun strongest(section: WardSection, dark: Boolean): Int? = mix(section, dark, top)?.let { hex(section, dark, it) }
}

/** The wash behind the word being spoken in Audio: the section's fill at this strength, under Chart Ink words. */
object WardWash {
    const val alpha = 0.22
}
