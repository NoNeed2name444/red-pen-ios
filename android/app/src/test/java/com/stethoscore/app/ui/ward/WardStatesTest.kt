package com.stethoscore.app.ui.ward

import org.junit.Test
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.min
import kotlin.math.sqrt

// A port of ios/RedPen/Tests/WardStatesTests.swift (all but the
// dock's checks, which are WardDockTest), same cases and numbers. Every Ward
// control in every state (WardControlStates), for each section in light and
// dark. Words and glyphs read 4.5:1 on their face in every state. A disabled
// label reads 3:1 or more and is told apart from the enabled one. Chosen is
// told apart from unchosen by more than relief (an ink, a fill or a solid
// mark), disabled too. What sits on a fill reads on it. No state is a blue
// outside Cards (the primary's indigo). Held, every control sinks. And the
// disabled ink itself reads on every tier and is apart from every colour
// with a meaning. The states gallery (WardStatesGallery) draws the real
// controls in these states.
class WardStatesTest {

    private fun distance(x: Int, y: Int): Double {
        val p = oklab(x)
        val q = oklab(y)
        return sqrt((p.L - q.L) * (p.L - q.L) + (p.a - q.a) * (p.a - q.a) + (p.b - q.b) * (p.b - q.b))
    }
    private fun chroma(x: Int): Double { val o = oklab(x); return sqrt(o.a * o.a + o.b * o.b) }
    private fun hue(x: Int): Double {
        val o = oklab(x)
        val d = atan2(o.b, o.a) * 180 / Math.PI
        return if (d < 0) d + 360 else d
    }
    private fun hueApart(a: Double, b: Double): Double {
        val d = abs(a - b) % 360
        return min(d, 360 - d)
    }

    // Told apart at a glance: the distance the sections keep from one another
    // and from the colours that mean something (WardLookTests).
    private val apart = 0.075
    // A colour rather than one of the palette's greys, whose chroma is 0.04 at most.
    private val colourful = 0.06
    // A blue: within this many degrees of the primary's indigo or the paper's ink outside any section.
    private val blueReach = 25.0

    private val sections = WardSection.entries
    private val modes = listOf(false, true)
    private fun modeName(dark: Boolean) = if (dark) "dark" else "light"

    // The tests whose cases the owner's exact colours fail (OwnerAccepted).
    private val statesTest = "WardStatesTest.theStatesAsDrawn"
    private val focusTest = "WardStatesTest.theFocusRing"
    private fun f(x: Double) = f3(x)
    private fun h(x: Int) = hx(x)

    /**
     * How far `now` is told from `was` by colour alone, not relief: its
     * label, its face, or a solid mark it carries (`unmarked` is what was
     * there without it: a control's own edge, or a switch's knob).
     */
    private fun told(now: WardControlColours, was: WardControlColours, unmarked: Int): Double {
        var best = distance(now.face, was.face)
        val a = now.label
        val b = was.label
        if (a != null && b != null) best = maxOf(best, distance(a, b))
        now.mark?.let { best = maxOf(best, distance(it, was.mark ?: unmarked)) }
        val wasMark = was.mark
        if (wasMark != null && now.mark == null) best = maxOf(best, distance(wasMark, unmarked))
        return best
    }

    @Test fun theDisabledInk() = checks {
        for (dark in modes) {
            val mode = modeName(dark)
            val ink = WardPalette.hex(WardControlStates.disabledInk, dark)
            for (tier in WardPalette.tiers) {
                val r = WardPalette.contrast(ink, WardPalette.hex(tier, dark))
                check("$mode: the disabled ink reads 4.5:1 on the $tier", r >= 4.5, f(r))
            }
            var near = 9.0
            var what = ""
            for (token in listOf(WardToken.ink) + WardSection.semanticTokens) {
                val d = distance(ink, WardPalette.hex(token, dark))
                if (d < near) { near = d; what = "$token" }
            }
            for (s in sections) {
                val d = distance(ink, s.accent(dark))
                if (d < near) { near = d; what = "$s's accent" }
            }
            check("$mode: the disabled ink is told apart from Chart Ink, the meanings and every accent", near >= apart, "$what ${f(near)}")
        }
        check("the disabled ink is no accent",
            WardControlStates.disabledInk != WardToken.primaryInk && WardControlStates.disabledInk != WardToken.primary)
    }

    @Test fun theStatesAsDrawn() = checks {
        check("ten controls", WardControl.entries.size == 10)
        for (control in WardControl.entries) {
            check("$control: ${if (control.isButton) "three states, none chosen" else "six states"}",
                control.states.size == (if (control.isButton) 3 else 6) && control.states.all { !it.isChosen || !control.isButton })
        }

        for (dark in modes) {
            val mode = modeName(dark)
            val blues = listOf(WardPalette.hex(WardToken.primaryInk, dark), WardPalette.hex(WardToken.primary, dark),
                WardSection.outside.ink(dark))
            for (s in sections) {
                // a chosen state that stands on the section's fill has white words
                val white = WardPalette.contrast(WardPalette.hex(WardToken.onPrimary, dark), s.fill(dark))
                check("$mode $s: white reads 4.5:1 on its fill", white >= 4.5, f(white),
                    OwnerCase(statesTest, "white reads 4.5:1 on its fill", "onPrimary", "$s", mode, "its fill"), white)
                for (control in WardControl.entries) {
                    for (state in control.states) {
                        val look = control.look(state)
                        val c = look.colours(s, dark)
                        val name = "$mode $s: the $control $state"
                        // what was there before a mark: the control's own edge on its face, or a switch's knob
                        fun unmarked(was: WardControlColours): Int =
                            if (control == WardControl.toggle) (was.knob ?: was.face)
                            else WardRelief.edgeColor(s, dark, on = was.face)

                        // words and glyphs, 4.5:1 on their face in every state
                        for ((what, ink) in listOf("words" to c.words, "glyph" to c.glyph)) {
                            if (ink == null) continue
                            val r = WardPalette.contrast(ink, c.readOn)
                            check("$name: its $what read 4.5:1 on its face", r >= 4.5, "${h(ink)} on ${h(c.readOn)} ${f(r)}",
                                OwnerCase(statesTest, "its words and glyphs read 4.5:1 on its face", "the $control $state: its $what",
                                    "$s", mode, "its face"), r)
                        }
                        // what sits on a fill reads on it
                        if (look.face == WardToken.primary) {
                            check("$name: on the fill its words are white", look.words == WardToken.onPrimary && look.glyph == null)
                        }
                        val knob = c.knob
                        if (knob != null && look.face != WardToken.well) {
                            val r = WardPalette.contrast(knob, c.face)
                            check("$name: the knob reads 3:1 on the filled track", r >= 3, "${h(knob)} on ${h(c.face)} ${f(r)}",
                                OwnerCase(statesTest, "the knob reads 3:1 on the filled track", "the $control $state: its knob",
                                    "$s", mode, "the filled track"), r)
                        }
                        // no state is a blue outside Cards, whose indigo the primary is
                        if (s != WardSection.outside) {
                            for (x in c.all) {
                                check("$name: ${h(x)} is not the palette's blue", !blues.contains(x))
                                if (chroma(x) < colourful) continue
                                val d = blues.minOf { hueApart(hue(x), hue(it)) }
                                check("$name: ${h(x)} is not a blue", d >= blueReach, "${f(d)} degrees from blue")
                            }
                        }
                        // held, it sinks: the face, or a switch's knob
                        if (state.isHeld && state.isEnabled) {
                            val sinks = if (control == WardControl.toggle) look.knobStand?.isPressedIn == true else look.stand.isPressedIn
                            check("$name: sinks into the base", sinks)
                        }
                        // disabled: 3:1 or more, and told apart from enabled by its label (a switch by its
                        // track or its knob's edge); it lies at the lowest lift
                        if (!state.isEnabled) {
                            val twin = control.look(state.enabledTwin).colours(s, dark)
                            val label = c.label
                            val was = twin.label
                            if (label != null && was != null) {
                                val r = WardPalette.contrast(label, c.readOn)
                                check("$name: its label reads 3:1 on its face", r >= 3, f(r))
                                val d = distance(label, was)
                                check("$name: its label is told apart from enabled", d >= apart, "${h(label)} vs ${h(was)} ${f(d)}")
                            } else {
                                val d = told(c, twin, unmarked(twin))
                                check("$name: told apart from enabled by more than relief", d >= apart, f(d))
                            }
                            if (control == WardControl.toggle) {
                                val dt = told(c, twin, unmarked(twin))
                                check("$name: its track or knob edge is told apart from enabled by more than relief", dt >= apart, f(dt))
                            }
                            if (control != WardControl.toggle) {
                                val low = look.stand == WardStand.Raised(WardLift.low) || look.stand == WardStand.PressedIn(WardLift.low)
                                check("$name: lies at the lowest lift", low, "${look.stand}")
                            }
                        }
                        // chosen: told apart from unchosen by more than relief, in every state, disabled too;
                        // pressed in (a switch: the tint fills its track)
                        if (state.isChosen) {
                            val twin = control.look(state.unchosenTwin).colours(s, dark)
                            val d = told(c, twin, unmarked(twin))
                            check("$name: told apart from unchosen by more than relief", d >= apart, f(d),
                                OwnerCase(statesTest, "told apart from unchosen by more than relief", "the $control $state",
                                    "$s", mode, "unchosen"), d)
                            if (control != WardControl.toggle) {
                                check("$name: pressed in", look.stand.isPressedIn)
                                check("$name: a solid edge in the accent", look.mark == WardToken.primaryInk)
                            }
                        }
                    }
                }
            }
        }
        everyOwnerCaseMade(statesTest)
    }

    // The model's rules, as WardControls draws them: a disabled control says its word in the disabled
    // ink, whatever its kind; chosen and disabled, it stays chosen.
    @Test fun theRules() = checks {
        for (control in WardControl.entries) {
            val off = control.look(WardControlState.disabled)
            check("$control: disabled, its label is the disabled ink", off.label == WardControlStates.disabledInk)
            if (control == WardControl.toggle) {
                check("toggle: disabled, its words are the disabled ink", off.words == WardControlStates.disabledInk)
                check("toggle: disabled, its knob edge is the disabled ink", off.mark == WardControlStates.disabledInk)
                for (state in control.states.filter { !it.isEnabled }) {
                    check("toggle: $state, its words are the disabled ink", control.look(state).words == WardControlStates.disabledInk)
                }
                for (state in control.states.filter { it.isEnabled }) {
                    check("toggle: $state, its words are Chart Ink", control.look(state).words == WardToken.ink)
                }
            }
            if (!control.isButton) {
                val both = control.look(WardControlState.selectedDisabled)
                check("$control: chosen and disabled, still chosen",
                    if (control == WardControl.toggle) both.face == WardControlStates.disabledInk
                    else both.stand.isPressedIn && both.mark == WardToken.primaryInk)
            }
        }
        check("a disabled switch's knob lies flat with an edge",
            WardControl.toggle.look(WardControlState.disabled).knobStand == WardStand.Flat && WardControlStates.knobEdgeWidth > 0)
        check("a chosen edge is wider than a control's own 1-point edge", WardControlStates.chosenEdgeWidth > 1)
    }

    // Android's focused state: the ring is the accent, as wide as the chosen edge, clear of the face,
    // and reads 3:1 on the base in every section and mode (a control's edge's promise, WardRelief.edgeContrast).
    @Test fun theFocusRing() = checks {
        check("the focus ring is the accent, as wide as the chosen edge, outside the face",
            WardControlStates.focusInk == WardToken.primaryInk && WardControlStates.focusRingWidth == WardControlStates.chosenEdgeWidth &&
                WardControlStates.focusRingGap > 0)
        for (dark in modes) for (s in sections) {
            val ring = WardGlide.rest(WardLook(dark, s)).hex(WardControlStates.focusInk, dark)
            for (tier in WardPalette.tiers) {
                val r = WardPalette.contrast(ring, WardPalette.hex(tier, dark))
                check("${modeName(dark)} $s: the focus ring reads 3:1 on the $tier", r >= WardRelief.edgeContrast, f(r),
                    OwnerCase(focusTest, "the focus ring reads 3:1", "the focus ring", "$s", modeName(dark), "$tier"), r)
            }
        }
        everyOwnerCaseMade(focusTest)
    }
}
