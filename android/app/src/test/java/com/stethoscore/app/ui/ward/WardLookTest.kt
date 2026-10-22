package com.stethoscore.app.ui.ward

import org.junit.Test
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.min
import kotlin.math.sqrt

// A port of ios/RedPen/Tests/WardLookTests.swift, same cases and
// numbers. One animated value for every Ward colour: the light/dark shift and
// the move between sections. Its ends are the palette's own colours, the
// middle is a linear-light mix, every token of a frame is taken at the same
// point, a part held in the other mode stays put, each section's ink reads as
// an edge and sits apart (OKLab), and the relief, press and paper specs move
// with it.
class WardLookTest {

    private val tokens = listOf(WardToken.background, WardToken.surface, WardToken.raised, WardToken.well, WardToken.primary,
        WardToken.primaryInk, WardToken.onPrimary, WardToken.ecg, WardToken.beam, WardToken.success, WardToken.warning,
        WardToken.danger, WardToken.ink, WardToken.inkSecondary, WardToken.hairline, WardToken.monitor,
        WardToken.faded, WardToken.fadedInk)
    // the look outside any section, whose accents are the palette's own
    private val day = WardLook(dark = false, section = WardSection.outside)
    private val night = WardLook(dark = true, section = WardSection.outside)
    private val toNight = WardGlide(day, night, 0.0)
    private val mid = toNight.copy(progress = 0.5)
    private val sections = WardSection.entries
    private val modes = listOf(false, true)
    private fun mode(dark: Boolean) = if (dark) "dark" else "light"

    // MARK: - Ends and rest

    @Test fun endsAndRest() = checks {
        for (look in listOf(day, night)) {
            val rest = WardGlide.rest(look)
            check("at rest (${mode(look.dark)}): settled", rest.settled)
            val same = tokens.all { rest.hex(it, look.dark) == WardPalette.hex(it, look.dark) }
            check("at rest (${mode(look.dark)}): every token is the palette's", same)
            check("at rest: the ink is the section's", rest.ink(look.dark) == look.section.ink(look.dark))
        }
        check("a shift starts at the light palette",
            tokens.all { toNight.hex(it, true) == WardPalette.hex(it, false) })
        val end = toNight.copy(progress = 1.0)
        check("and ends at the dark one", tokens.all { end.hex(it, true) == WardPalette.hex(it, true) })
        check("a finished shift is settled", end.settled && !toNight.settled)
        check("the shift lasts about a third of a second", WardGlide.duration in 0.3..0.4, f3(WardGlide.duration))
    }

    // MARK: - Easing

    @Test fun easing() = checks {
        var lastEase = -1.0
        var smooth = true
        for (i in 0..100) {
            val e = toNight.copy(progress = i / 100.0).eased
            if (e < lastEase - 1e-12) smooth = false
            lastEase = e
        }
        check("the easing never runs backwards", smooth)
        check("the easing is symmetric, half way at half time", abs(mid.eased - 0.5) < 1e-12, f3(mid.eased))
        val early = toNight.copy(progress = 0.05)
        check("the easing starts gently", early.eased < 0.05, f3(early.eased))
        val over = toNight.copy(progress = 1.7)
        val under = toNight.copy(progress = -0.4)
        check("progress past the ends is held to them", over.eased == 1.0 && under.eased == 0.0)
    }

    // MARK: - One point for every token (no frame mixes two looks)

    @Test fun onePointForEveryToken() = checks {
        for (i in 1 until 10) {
            val g = toNight.copy(progress = i / 10.0)
            val n = g.night(true)
            val together = tokens.all {
                g.hex(it, true) == WardPalette.mix(WardPalette.hex(it, false), WardPalette.hex(it, true), n)
            }
            check("frame $i/10: every token sits at the same point of the shift", together)
        }
        var lastLum = WardPalette.luminance(WardPalette.hex(WardToken.background, false))
        var falling = true
        for (i in 1..20) {
            val l = WardPalette.luminance(toNight.copy(progress = i / 20.0).hex(WardToken.background, true))
            if (l > lastLum + 1e-9) falling = false
            lastLum = l
        }
        check("the base darkens steadily, without a flash", falling)
    }

    // MARK: - Parts held in the other mode

    @Test fun partsHeldInTheOtherMode() = checks {
        check("a part held in the other mode stays put during a shift",
            mid.night(false) == 0.0 && mid.hex(WardToken.surface, false) == WardPalette.hex(WardToken.surface, false))
        val toDay = WardGlide(night, day, 0.5)
        check("the always-dark monitor stays dark while the app turns light",
            toDay.night(true) == 1.0 && toDay.hex(WardToken.monitor, true) == WardPalette.hex(WardToken.monitor, true))
        check("a part marked held stays put, even in the mode the app is heading to",
            mid.night(true, held = true) == 1.0 && mid.hex(WardToken.surface, true, held = true) == WardPalette.hex(WardToken.surface, true) &&
                mid.ink(true, held = true) == WardSection.outside.ink.dark)
        check("the app's own page moves while it turns light", toDay.night(false) > 0 && toDay.night(false) < 1)
        val sideways = WardGlide(day, WardLook(false, WardSection.questions), 0.5)
        check("a move between sections keeps the palette where it is",
            sideways.night(false) == 0.0 && sideways.night(true) == 1.0)
    }

    // MARK: - Retargeting

    @Test fun retargeting() = checks {
        val back = mid.retargeted(day)
        check("turning back mid-way runs the same path in reverse from where it is",
            back.from == night && back.to == day && abs(back.progress - 0.5) < 1e-12 &&
                back.hex(WardToken.background, false) == mid.hex(WardToken.background, true))
        val q = toNight.copy(progress = 0.25)
        val backQ = q.retargeted(day)
        check("and lands on the same colour, a quarter in",
            backQ.hex(WardToken.surface, false) == q.hex(WardToken.surface, true),
            hx(backQ.hex(WardToken.surface, false)) + " vs " + hx(q.hex(WardToken.surface, true)))
        check("the same destination again changes nothing", mid.retargeted(night) == mid)
        val fresh = WardGlide.rest(day).retargeted(night)
        check("from rest a shift starts at the beginning", fresh.from == day && fresh.to == night && fresh.progress == 0.0)
        val elsewhere = mid.retargeted(WardLook(true, WardSection.osce))
        check("somewhere new starts from where it was headed",
            elsewhere.from == night && elsewhere.to.section == WardSection.osce && elsewhere.progress == 0.0)
    }

    // MARK: - Sections

    private fun hue(x: Int): Double {
        val o = oklab(x)
        val d = atan2(o.b, o.a) * 180 / Math.PI
        return if (d < 0) d + 360 else d
    }

    private fun distance(x: Int, y: Int): Double {
        val p = oklab(x)
        val q = oklab(y)
        return sqrt((p.L - q.L) * (p.L - q.L) + (p.a - q.a) * (p.a - q.a) + (p.b - q.b) * (p.b - q.b))
    }

    /** Swift's truncatingRemainder is Kotlin's %, both keeping the dividend's sign. */
    private fun apart(a: Double, b: Double): Double {
        val d = abs(a - b) % 360
        return min(d, 360 - d)
    }

    // How far apart (OKLab) two sections, or a section and a colour that
    // means something, must sit to be told apart at a glance.
    private val sectionsApart = 0.075

    // The tests whose cases the owner's exact colours fail (OwnerAccepted).
    private val sectionsTest = "WardLookTest.sections"
    private val accentsTest = "WardLookTest.eachSectionsAccents"

    @Test fun sections() = checks {
        check("seven sections", sections.size == 7)
        check("outside any section the look is Cards", WardSection.outside == WardSection.cards)
        check("the default paper ink is the outside look's",
            WardPaper.ink(dark = false, highContrast = false).hex == WardSection.outside.ink(false) &&
                WardPaper.ink(dark = true, highContrast = false).hex == WardSection.outside.ink(true))
        check("Questions: Vital Coral's hue 23 and its fill, the owner's #FF6B6B in both modes",
            WardSection.questions.hue == 23.0 && WardSection.questions.fill.light == 0xFF6B6B &&
                WardSection.questions.fill.dark == 0xFF6B6B)
        for (dark in modes) {
            check("${mode(dark)}: primary and primaryInk equal Cards' fill and accent",
                WardPalette.hex(WardToken.primary, dark) == WardSection.cards.fill(dark) &&
                    WardPalette.hex(WardToken.primaryInk, dark) == WardSection.cards.accent(dark))
        }
        for (dark in modes) {
            val m = mode(dark)
            var closest = 9.0
            var pair = ""
            for ((i, a) in sections.withIndex()) {
                for (b in sections.drop(i + 1)) {
                    val d = distance(a.ink(dark), b.ink(dark))
                    if (d < closest) { closest = d; pair = "$a/$b" }
                }
            }
            check("$m: every section's ink is told apart from the others' (0.06)", closest >= 0.06, "$pair ${f3(closest)}")
            for (s in sections) {
                check("$m $s: light and dark inks share a hue",
                    apart(hue(s.ink.light), hue(s.ink.dark)) <= 4, f3(apart(hue(s.ink.light), hue(s.ink.dark))))
            }
            for (s in sections) {
                for (tier in listOf(WardToken.background, WardToken.surface)) {
                    val base = WardPalette.hex(tier, dark)
                    val c = WardPalette.contrast(WardRelief.edgeColor(s, dark, on = base), base)
                    check("$m $s: a control's edge reads 3:1 on the $tier", c >= WardRelief.edgeContrast, f3(c),
                        OwnerCase(sectionsTest, "a control's edge reads 3:1", "a control's edge", "$s", m, "$tier"), c)
                }
            }
        }
        check("set kinds find their section",
            WardSection.fromKindRaw("anki") == WardSection.cards && WardSection.fromKindRaw("book") == WardSection.textbook &&
                WardSection.fromKindRaw("cases") == WardSection.cases && WardSection.fromKindRaw("osce") == WardSection.osce &&
                WardSection.fromKindRaw("narrate") == WardSection.audio && WardSection.fromKindRaw("mcq") == WardSection.questions)

        // (from the outside look, Cards, so the move is to Questions)
        val toCards = WardGlide(day, WardLook(false, WardSection.questions), 0.0)
        val cardsEnd = toCards.copy(progress = 1.0)
        check("a move to Questions starts in Care Blue and ends in coral",
            toCards.ink(false) == WardSection.cards.ink.light && cardsEnd.ink(false) == WardSection.questions.ink.light)
        val cardsMid = toCards.copy(progress = 0.5)
        check("half way it is the linear-light mix, not either",
            cardsMid.ink(false) == WardPalette.mix(WardSection.cards.ink.light, WardSection.questions.ink.light, 0.5))
        check("a move between sections leaves the palette alone, but for the accents",
            tokens.filter { it != WardToken.primary && it != WardToken.primaryInk }
                .all { cardsMid.hex(it, false) == WardPalette.hex(it, false) })
        check("half way between sections the accents are the linear-light mix",
            cardsMid.hex(WardToken.primaryInk, false) ==
                WardPalette.mix(WardSection.cards.accent.light, WardSection.questions.accent.light, 0.5))
        val both = WardGlide(day, WardLook(true, WardSection.textbook), 0.5)
        val n = both.night(true)
        val expect = WardPalette.mix(WardPalette.mix(WardSection.outside.ink.light, WardSection.outside.ink.dark, n),
            WardPalette.mix(WardSection.textbook.ink.light, WardSection.textbook.ink.dark, n), both.eased)
        check("mode and section move together, at the same point", both.ink(true) == expect)
        everyOwnerCaseMade(sectionsTest)
    }

    // MARK: - What moves, and what changes in one step

    private fun inkOnBase(g: WardGlide, dark: Boolean): Double =
        WardPalette.contrast(g.hex(WardToken.ink, dark), g.hex(WardToken.background, dark))

    @Test fun whatMovesAndWhatChangesInOneStep() = checks {
        val swap = WardGlide.toward(night, from = WardGlide.rest(day))
        check("light to dark arrives in one step, every colour at once",
            swap.settled && swap.to == night && tokens.all { swap.hex(it, true) == WardPalette.hex(it, true) })
        val cardsMid = WardGlide(day, WardLook(false, WardSection.questions), 0.5)
        val swapBack = WardGlide.toward(WardLook(true, WardSection.questions), from = cardsMid)
        check("a mode change mid-way through a section's shift lands at once too",
            swapBack.settled && swapBack.to == WardLook(true, WardSection.questions))
        val toOsce = WardGlide.toward(WardLook(true, WardSection.osce), from = WardGlide.rest(night))
        check("a move between sections shifts, from the start", !toOsce.settled && toOsce.progress == 0.0)

        // Text keeps its contrast on every frame the app can show: never below
        // the lower of the two ends (a mix of light and dark falls to about 1.2:1).
        var worstText = Double.POSITIVE_INFINITY
        for ((from, to) in listOf(day to night, night to day, day to WardLook(false, WardSection.audio),
            night to WardLook(true, WardSection.ideas), day to WardLook(true, WardSection.cases))) {
            var g = WardGlide.toward(to, from = WardGlide.rest(from))
            val floor = min(inkOnBase(WardGlide.rest(from), from.dark), inkOnBase(WardGlide.rest(to), to.dark))
            for (i in 0..20) {
                if (!g.settled) g = g.copy(progress = i / 20.0)
                val c = inkOnBase(g, to.dark)
                worstText = min(worstText, c / floor)
            }
        }
        check("text never loses contrast in any shift the app makes", worstText >= 0.999, f3(worstText))
        val mixed = WardGlide(day, night, 0.5)
        check("(the mix it avoids: text half way between the palettes is grey on grey)",
            inkOnBase(mixed, true) < 2, f3(inkOnBase(mixed, true)))
    }

    // MARK: - Relief, press and paper move with it

    @Test fun reliefPressAndPaperMoveWithIt() = checks {
        for (lift in WardLift.entries) {
            check("$lift: the relief's ends are light and dark",
                WardRelief.raised(lift, night = 0.0) == WardRelief.raised(lift, dark = false) &&
                    WardRelief.raised(lift, night = 1.0) == WardRelief.raised(lift, dark = true) &&
                    WardRelief.rim(lift, night = 0.0) == WardRelief.rim(lift, dark = false) &&
                    WardRelief.rim(lift, night = 1.0) == WardRelief.rim(lift, dark = true) &&
                    WardRelief.inset(lift, night = 1.0, control = true) == WardRelief.inset(lift, dark = true, control = true))
            val m = WardRelief.rim(lift, night = 0.5)
            val a = WardRelief.rim(lift, dark = false)
            val b = WardRelief.rim(lift, dark = true)
            check("$lift: half way, the rim's lights sit between",
                m.highlight.alpha >= minOf(a.highlight.alpha, b.highlight.alpha) &&
                    m.highlight.alpha <= maxOf(a.highlight.alpha, b.highlight.alpha) &&
                    m.shade.hex == WardPalette.mix(a.shade.hex, b.shade.hex, 0.5))
            check("$lift: the rim never reaches further half way",
                WardRelief.reach(m.highlight) <= WardRelief.rimReach + 1e-9 && WardRelief.reach(m.shade) <= WardRelief.rimReach + 1e-9)
            check("$lift: the press's ends are light and dark",
                WardPress.spec(lift, depth = 0.4, night = 0.0) == WardPress.spec(lift, depth = 0.4, dark = false) &&
                    WardPress.spec(lift, depth = 0.4, night = 1.0) == WardPress.spec(lift, depth = 0.4, dark = true))
        }
        for (hc in listOf(false, true)) {
            val p0 = WardPaper.ink(night = 0.0, highContrast = hc, hex = 0x123456)
            val p1 = WardPaper.ink(night = 1.0, highContrast = hc, hex = 0x123456)
            val l = WardPaper.ink(dark = false, highContrast = hc)
            val d = WardPaper.ink(dark = true, highContrast = hc)
            check("paper (contrast $hc): its strengths run from light to dark, in the section's ink",
                p0.fine == l.fine && p0.bold == l.bold && p1.fine == d.fine && p1.bold == d.bold && p0.hex == 0x123456)
        }
    }

    // MARK: - Each section's accents

    @Test fun eachSectionsAccents() = checks {
        for (dark in modes) {
            val m = mode(dark)
            for (s in sections) {
                val accent = s.accent(dark)
                val fill = s.fill(dark)
                for (tier in WardPalette.tiers) {
                    val c = WardPalette.contrast(accent, WardPalette.hex(tier, dark))
                    check("$m $s: accent words read 4.5:1 on the $tier", c >= 4.5, "${hx(accent)} ${f3(c)}",
                        OwnerCase(accentsTest, "accent words read 4.5:1", "accent", "$s", m, "$tier"), c)
                    check("$m $s: accent glyphs read 3:1 on the $tier", c >= 3, f3(c),
                        OwnerCase(accentsTest, "accent glyphs read 3:1", "accent", "$s", m, "$tier"), c)
                }
                val white = WardPalette.contrast(WardPalette.hex(WardToken.onPrimary, dark), fill)
                check("$m $s: the on-fill words read 4.5:1 on the fill", white >= 4.5, "${hx(fill)} ${f3(white)}",
                    OwnerCase(accentsTest, "the on-fill words read 4.5:1 on the fill", "onPrimary", "$s", m, "its fill"), white)
                if (dark) {
                    val mc = WardPalette.contrast(accent, WardPalette.hex(WardToken.monitor, true))
                    check("$s: the accent reads 4.5:1 on the monitor", mc >= 4.5, f3(mc))
                }
                // the glide hands out the section's accents for the palette's accent tokens
                val rest = WardGlide.rest(WardLook(dark, s))
                check("$m $s: at rest the accent tokens are the section's",
                    rest.hex(WardToken.primaryInk, dark) == accent && rest.hex(WardToken.primary, dark) == fill)
                check("$m $s: the palette's own primaryInk stays the palette's",
                    rest.paletteHex(WardToken.primaryInk, dark) == WardPalette.hex(WardToken.primaryInk, dark))
                // the hue is the section's, in all three roles
                for ((role, c) in listOf("ink" to s.ink(dark), "accent" to accent, "fill" to fill)) {
                    check("$m $s: its $role is its hue", apart(hue(c), s.hue) <= 2, f3(hue(c)))
                }
            }
            // the sections apart from one another in their accents too
            var closest = 9.0
            var pair = ""
            for ((i, a) in sections.withIndex()) {
                for (b in sections.drop(i + 1)) {
                    val d = distance(a.accent(dark), b.accent(dark))
                    if (d < closest) { closest = d; pair = "$a/$b" }
                }
            }
            check("$m: every section's accent is told apart from the others'", closest >= sectionsApart, "$pair ${f3(closest)}")
            // and from what means something, and (away from Cards) the primary
            for (s in sections) {
                var near = 9.0
                var what = ""
                for (token in WardSection.semanticTokens) {
                    val d = distance(s.accent(dark), WardPalette.hex(token, dark))
                    if (d < near) { near = d; what = "$token" }
                }
                if (s != WardSection.cards) {
                    val d = distance(s.accent(dark), WardPalette.hex(WardToken.primaryInk, dark))
                    if (d < near) { near = d; what = "the primary's Care Blue" }
                }
                check("$m $s: the accent is not mistaken for a colour that means something", near >= sectionsApart,
                    "$what ${f3(near)}", OwnerCase(accentsTest, "the accent is not mistaken for a colour that means something",
                        "accent", "$s", m, "the nearest colour that means something"), near)
                // a wrong answer's faded ink is a grey, never taken for an accent
                val faded = distance(s.accent(dark), WardPalette.hex(WardToken.fadedInk, dark))
                check("$m $s: the faded ink is 0.095 or more from the accent", faded >= 0.095, f3(faded))
            }
        }

        // Changing section shifts the accents over the glide with their
        // contrast never below the lower end, and light and dark still swap
        // them in one step.
        var worstAccent = Double.POSITIVE_INFINITY
        var leastAccent = Double.POSITIVE_INFINITY
        for (dark in modes) {
            for (a in sections) {
                for (b in sections) {
                    if (b == a) continue
                    val from = WardLook(dark, a)
                    val to = WardLook(dark, b)
                    var g = WardGlide.toward(to, from = WardGlide.rest(from))
                    for (tier in WardPalette.tiers) {
                        val ground = WardPalette.hex(tier, dark)
                        val floor = min(WardPalette.contrast(a.accent(dark), ground), WardPalette.contrast(b.accent(dark), ground))
                        for (i in 0..20) {
                            g = g.copy(progress = i / 20.0)
                            val c = WardPalette.contrast(g.hex(WardToken.primaryInk, dark), ground)
                            worstAccent = min(worstAccent, c / floor)
                            leastAccent = min(leastAccent, c)
                        }
                    }
                }
            }
        }
        // within a byte's rounding of the lower end, and never under 4.5:1
        check("a section's shift never drops the accent's contrast below either end", worstAccent >= 0.99, f3(worstAccent))
        check("a section's shift keeps the accent at 4.5:1 on every frame", leastAccent >= 4.5, f3(leastAccent),
            OwnerCase(accentsTest, "a section's shift keeps the accent at 4.5:1 on every frame", "accent",
                "every section to every other", "light and dark", "every tier"), leastAccent)
        val accentSwap = WardGlide.toward(WardLook(true, WardSection.cards), from = WardGlide.rest(WardLook(false, WardSection.cards)))
        check("light to dark swaps the accents in one step",
            accentSwap.settled && accentSwap.hex(WardToken.primaryInk, true) == WardSection.cards.accent.dark)

        // Audio's highlighted line: the word being spoken washed in the
        // accent's fill, its words in Chart Ink, which keeps 4.5:1 on the wash;
        // the line is a well, in the well's fill (the page colour, the owner 22 Oct).
        for (dark in modes) {
            for (s in sections) {
                val well = WardPalette.hex(WardControlStates.wellFill, dark)
                val wash = WardRelief.composite(WardReliefLight(s.fill(dark), WardWash.alpha, 0.0, 0.0, 0.0), on = well)
                val c = WardPalette.contrast(WardPalette.hex(WardToken.ink, dark), wash)
                check("${mode(dark)} $s: words on the spoken word's wash read 4.5:1", c >= 4.5, f3(c))
            }
        }
        everyOwnerCaseMade(accentsTest)
    }

    // A colour reads the look as it is drawn (WardLookNow), not as it was
    // when a view's body ran.
    @Test fun drawnNow() = checks {
        val now = WardLookNow()
        val outside = WardLook(false, WardSection.outside)
        check("the look starts outside any section",
            now.glide == WardGlide.rest(outside) && WardLookNow.shared.glide == WardGlide.rest(outside))
        now.set(WardGlide.rest(WardLook(false, WardSection.questions)))
        check("a right answer made outside any section shows Questions' accent by day",
            now.hex(WardToken.primaryInk, false) == 0xFF6B6B, hx(now.hex(WardToken.primaryInk, false)))
        check("and at night", now.hex(WardToken.primaryInk, true) == 0xFF6B6B, hx(now.hex(WardToken.primaryInk, true)))
        check("and its edges Questions' ink", now.ink(false) == 0xFF6B6B && now.ink(true) == 0xFF6B6B)
        for (section in WardSection.entries) {
            for (dark in modes) {
                now.set(WardGlide.rest(WardLook(dark, section)))
                for (token in WardToken.entries) {
                    val want = when (token) {
                        WardToken.primaryInk -> section.accent(dark)
                        WardToken.primary -> section.fill(dark)
                        else -> WardPalette.hex(token, dark)
                    }
                    check("drawn now: $section ${mode(dark)} $token", now.hex(token, dark) == want,
                        hx(now.hex(token, dark)) + " vs " + hx(want))
                }
                check("drawn now: $section ${mode(dark)} ink", now.ink(dark) == section.ink(dark))
            }
        }
        val shift = WardGlide(outside, WardLook(false, WardSection.questions), 0.5)
        now.set(shift)
        check("mid-shift, a colour is this frame's",
            now.hex(WardToken.primaryInk, false) == shift.hex(WardToken.primaryInk, false) && now.ink(false) == shift.ink(false))
        check("a part held in one mode keeps it mid-shift",
            now.hex(WardToken.primaryInk, true, held = true) == shift.hex(WardToken.primaryInk, true, held = true))
        val rest = WardLook(true, WardSection.audio)
        check("a face or the paper draws the look at rest it was handed",
            WardGlide.drawn(rest = rest, live = shift) == WardGlide.rest(rest))
        check("and the shift's frame where it was handed none", WardGlide.drawn(rest = null, live = shift) == shift)
    }

    // MARK: - A given section's ink (mode tile ring)

    @Test fun aGivenSectionsInk() = checks {
        for (section in listOf(WardSection.questions, WardSection.cards)) {
            // A glide between two different sections (textbook -> osce) shifting from light to dark
            val shift = WardGlide(WardLook(false, WardSection.textbook), WardLook(true, WardSection.osce), 0.0)
            check("$section: at night 0, ink is the section's light ink",
                shift.ink(section, true) == section.ink.light && shift.ink(section, false) == section.ink.light)
            val shiftEnd = shift.copy(progress = 1.0)
            check("$section: at night 1, ink is the section's dark ink", shiftEnd.ink(section, true) == section.ink.dark)
            for (i in 1..9) {
                val m = shift.copy(progress = i / 10.0)
                val n = m.night(true)
                val expected = WardPalette.mix(section.ink.light, section.ink.dark, n)
                check("$section: frame $i/10 is the light/dark mix without hue shift", m.ink(section, true) == expected)
            }
            val restLight = WardGlide.rest(WardLook(false, WardSection.cases))
            check("$section: at rest in another section (light), ink is section's light ink",
                restLight.ink(section, false) == section.ink.light)
            val restDark = WardGlide.rest(WardLook(true, WardSection.cases))
            check("$section: at rest in another section (dark), ink is section's dark ink",
                restDark.ink(section, true) == section.ink.dark)
        }
        val now = WardLookNow()
        now.set(WardGlide.rest(WardLook(false, WardSection.textbook)))
        check("WardLookNow: Questions ink in Textbook section is Questions' light ink",
            now.ink(WardSection.questions, false) == WardSection.questions.ink.light)
        check("WardLookNow: Cards ink in Textbook section is Cards' light ink",
            now.ink(WardSection.cards, false) == WardSection.cards.ink.light)
    }
}
