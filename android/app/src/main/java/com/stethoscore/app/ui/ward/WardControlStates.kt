package com.stethoscore.app.ui.ward

// A port of ios/RedPen/Shared/Ward/WardControlStates.swift (the
// states model; WardDock, the dock's geometry, is in WardDock.kt).
//
// How every Ward control looks in each of its states (the states gallery,
// WardStatesGallery): at rest, held under the finger, disabled and chosen,
// and, for a control that can be chosen, chosen and held, and chosen and
// disabled. For each state: the colours of its words and glyphs, the face
// they sit on, the solid mark it carries and how its face stands, as
// WardControls draws them.
//
// The colours are roles (WardToken), read for a section and a mode through
// WardGlide at rest: primaryInk is the section's accent and primary its fill
// (WardSection), the rest are the Ward palette's. No colour here is a hex of
// its own. Pure Kotlin, so every section and mode is checked on the JVM
// (WardStatesTest).
//
// The rules the states keep (the owner, 14 Oct: buttons "became too flat";
// 9 Oct: nothing in the app looks faded):
// - held, a control sinks into the base; a switch's knob sinks;
// - disabled, its words and glyphs go Biro Grey (disabledInk), solid, and it
//   lies at the lowest lift; a switch's words go Biro Grey, its on-track goes
//   Biro Grey and its knob lies flat;
// - chosen, it is pressed in, its words take the section's accent (a tile's
//   stay its caller's) and a solid edge in that accent goes round it (a
//   switch: the tint fills its track); chosen and disabled, it stays pressed
//   in and keeps the edge.
//
// Android adds one state iOS draws with the system's hover highlight: focused
// (a keyboard, a D-pad or a switch device on it). It is drawn as a ring in the
// section's accent just outside the face (focusRingWidth, focusRingGap), over
// whatever state it is in, so it never changes the state's own colours.

object WardControlStates {
    /**
     * A disabled control's words and glyphs, and a disabled switch's
     * on-track: Biro Grey, solid, 4.5:1 on every tier, and told apart from
     * Chart Ink, every section's accent and every colour that means
     * something. The one place it is named (wardDisabledInk reads it).
     */
    val disabledInk: WardToken = WardToken.inkSecondary

    /**
     * Every well's fill: text fields and search boxes, chips and pills,
     * progress tracks and grooves, a switch's track and a chosen or held
     * segment. The page colour: wells take the page colour and show as
     * wells through their inset shadows only (the owner, 22 Oct: "wells
     * and sheets one tone"). WardToken.well stays in the palette as it was;
     * no Ward well draws it. This is the one place the well's fill is named;
     * wardInset and wardWellFill read it.
     */
    val wellFill: WardToken = WardToken.background

    /**
     * The solid edge round a chosen chip, circle, segment or tile, in
     * points: the section's accent at full strength, twice the width of a
     * control's own 1-point edge.
     */
    const val chosenEdgeWidth = 2.0

    /**
     * The edge a disabled switch's flat knob keeps, in the disabled ink: a
     * flat face on its track (the well's fill, the page colour) would not
     * be told from it, so it would disappear.
     */
    const val knobEdgeWidth = 1.0

    /** Focused (Android): a ring in the section's accent, this wide, this far outside the face. */
    const val focusRingWidth = 2.0
    const val focusRingGap = 2.0
    /** The focus ring's ink: the section's accent, 3:1 on the base like any control's edge. */
    val focusInk: WardToken = WardToken.primaryInk
}

/** One state of a control: chosen or not, held or not, enabled or not. */
data class WardControlState(
    val isChosen: Boolean = false,
    val isHeld: Boolean = false,
    val isEnabled: Boolean = true,
) {
    /** The same state on an enabled control: what a disabled one is told apart from. */
    val enabledTwin: WardControlState get() = copy(isEnabled = true)

    /** The same state, not chosen: what a chosen one is told apart from. */
    val unchosenTwin: WardControlState get() = copy(isChosen = false)

    override fun toString(): String {
        val words = mutableListOf<String>()
        if (isChosen) words.add("chosen")
        if (isHeld) words.add("held")
        if (!isEnabled) words.add("disabled")
        return if (words.isEmpty()) "at rest" else words.joinToString(" and ")
    }

    companion object {
        val rest = WardControlState()
        val pressed = WardControlState(isHeld = true)
        val disabled = WardControlState(isEnabled = false)
        val selected = WardControlState(isChosen = true)
        val selectedPressed = WardControlState(isChosen = true, isHeld = true)
        val selectedDisabled = WardControlState(isChosen = true, isEnabled = false)
    }
}

/** How a face stands off the base. */
sealed class WardStand {
    /** Raised by its lights at this lift (a button by its small rim). */
    data class Raised(val lift: WardLift) : WardStand()
    /** Pressed into the base, the lift's lights inside it: held or chosen. */
    data class PressedIn(val lift: WardLift) : WardStand()
    /** No lights at all: a disabled switch's knob. */
    object Flat : WardStand() { override fun toString() = "flat" }

    val isPressedIn: Boolean get() = this is PressedIn
}

/** A control's look in one state, as colour roles. */
data class WardControlLook(
    /** Its words, where it has them. */
    val words: WardToken? = null,
    /** Its glyph, where it has one. */
    val glyph: WardToken? = null,
    /** The face its words and glyph sit on; for a switch, its track (primaryInk there is the tint). */
    val face: WardToken,
    val stand: WardStand,
    /** A solid mark that is not words: a chosen control's edge, or a disabled switch's knob edge. */
    val mark: WardToken? = null,
    /** A switch's knob, and how it stands on the track. */
    val knob: WardToken? = null,
    val knobStand: WardStand? = null,
    /** Where its words sit when that is not [face]: a switch's words stand on the row beside its track. */
    val wordsFace: WardToken? = null,
) {
    /** What the eye reads first: the words, or else the glyph. */
    val label: WardToken? get() = words ?: glyph

    /** This look's colours for [section] in light or dark, 0xRRGGBB, read through the palette and the section's table. */
    fun colours(section: WardSection, dark: Boolean): WardControlColours {
        val glide = WardGlide.rest(WardLook(dark, section))
        fun hex(token: WardToken): Int = glide.hex(token, dark)
        return WardControlColours(words = words?.let(::hex), glyph = glyph?.let(::hex), face = hex(face),
            mark = mark?.let(::hex), knob = knob?.let(::hex), wordsFace = wordsFace?.let(::hex))
    }
}

/** A look's colours for one section and mode, as 0xRRGGBB. */
data class WardControlColours(
    val words: Int? = null,
    val glyph: Int? = null,
    val face: Int,
    val mark: Int? = null,
    val knob: Int? = null,
    val wordsFace: Int? = null,
) {
    val label: Int? get() = words ?: glyph

    /** What its words and glyph are read against. */
    val readOn: Int get() = wordsFace ?: face

    /** Every colour the state draws. */
    val all: List<Int> get() = listOfNotNull(words, glyph, mark, knob, wordsFace) + face
}

/** The Ward controls the gallery shows, in its order. */
enum class WardControl {
    /** WardButton's kinds. */
    primary, secondary, destructive, compact, quiet,
    /** WardChipButton (Sure, Hint, Flag), with no tone of its own. */
    chip,
    /** WardCircleButton (a stepper's minus and plus), at its own lift. */
    circle,
    /** WardToggle: chosen is on. */
    toggle,
    /** One segment of WardSegmented: chosen is the selected one. */
    segment,
    /**
     * WardTile on the raised plane. The tile leaves its label's colours to
     * the caller; these are the gallery's label, which colours itself as a
     * careful caller does: Chart Ink words and a glyph in the accent, Biro
     * Grey when disabled.
     */
    tile;

    val isButton: Boolean get() = when (this) {
        primary, secondary, destructive, compact, quiet -> true
        chip, circle, toggle, segment, tile -> false
    }

    /** Its states. A button has no chosen ones. */
    val states: List<WardControlState> get() = if (isButton) {
        listOf(WardControlState.rest, WardControlState.pressed, WardControlState.disabled)
    } else {
        listOf(WardControlState.rest, WardControlState.pressed, WardControlState.disabled,
            WardControlState.selected, WardControlState.selectedPressed, WardControlState.selectedDisabled)
    }

    /** How high it stands at rest: the main button a step above the rest. */
    val lift: WardLift get() = when (this) {
        primary -> WardLift.high
        secondary, destructive, tile -> WardLift.mid
        compact, quiet, chip, circle, toggle, segment -> WardLift.low
    }

    /** An enabled button's words: the kind shows in the label's colour. */
    private val buttonWords: WardToken get() = when (this) {
        primary, compact -> WardToken.primaryInk
        destructive -> WardToken.danger
        else -> WardToken.ink
    }

    /** Its look in [state], as WardControls draws it. */
    fun look(state: WardControlState): WardControlLook {
        val enabled = state.isEnabled
        val disabledInk = WardControlStates.disabledInk
        // disabled, it lies at the lowest lift; held (only while enabled) or
        // chosen, it is pressed in
        val lift = if (enabled) this.lift else WardLift.low
        val down = state.isChosen || (enabled && state.isHeld)
        val stand: WardStand = if (down) WardStand.PressedIn(lift) else WardStand.Raised(lift)
        val chosenEdge: WardToken? = if (state.isChosen) WardToken.primaryInk else null
        val chosenInk = if (state.isChosen) WardToken.primaryInk else WardToken.ink
        return when (this) {
            // the main button's face is a sheet's, a tier up, while enabled
            primary, secondary, destructive, compact, quiet -> WardControlLook(
                words = if (enabled) buttonWords else disabledInk,
                face = if (this == primary && enabled) WardToken.raised else WardToken.surface, stand = stand)
            chip -> WardControlLook(words = if (enabled) chosenInk else disabledInk, face = WardToken.surface,
                stand = stand, mark = chosenEdge)
            circle -> WardControlLook(glyph = if (enabled) chosenInk else disabledInk, face = WardToken.surface,
                stand = stand, mark = chosenEdge)
            // a segment sits on the control's raised capsule; held or chosen,
            // it is a well pressed into it (the well's fill, WardControlStates.wellFill)
            segment -> WardControlLook(words = if (enabled) chosenInk else disabledInk,
                face = if (down) WardControlStates.wellFill else WardToken.surface,
                stand = if (down) WardStand.PressedIn(WardLift.low) else WardStand.Raised(WardLift.low), mark = chosenEdge)
            // the track is a well (the well's fill); on, the tint fills it,
            // Biro Grey when disabled; the knob sinks while held and lies
            // flat, with an edge, when disabled; its words, on the row beside
            // it, go Biro Grey too
            toggle -> {
                val track = if (state.isChosen) (if (enabled) WardToken.primaryInk else disabledInk) else WardControlStates.wellFill
                val knobStand: WardStand = when {
                    !enabled -> WardStand.Flat
                    state.isHeld -> WardStand.PressedIn(WardLift.low)
                    else -> WardStand.Raised(WardLift.low)
                }
                WardControlLook(words = if (enabled) WardToken.ink else disabledInk, face = track,
                    stand = WardStand.PressedIn(WardLift.low), mark = if (enabled) null else disabledInk,
                    knob = WardToken.surface, knobStand = knobStand, wordsFace = WardToken.surface)
            }
            tile -> WardControlLook(words = if (enabled) WardToken.ink else disabledInk,
                glyph = if (enabled) WardToken.primaryInk else disabledInk, face = WardToken.surface, stand = stand,
                mark = chosenEdge)
        }
    }
}
