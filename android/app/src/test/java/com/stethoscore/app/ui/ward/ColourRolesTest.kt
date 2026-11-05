package com.stethoscore.app.ui.ward

import org.junit.Test
import java.io.File

// The colour roles (docs/design/colour-roles.md in the iOS repo, task T0134):
// which of the owner's ten hexes each role takes, the same as on the iPhone
// (tests/ward/colour-roles.test.mjs there). The owner, 23 Oct 2026: "little
// to no colour consistency across the app"; D1, words on the page are ink and
// colour goes on icons, edges and fills; D7 (30 Oct), a right answer takes
// the mode's colour in every mode, Questions' coral too; D8 (30 Oct), a chosen
// chip or segment is filled with the accent under near-black words. This
// reads the app's Kotlin sources and fails when a screen names a mode's
// colour other than its own, draws an accent literal, marks a right answer in
// Fresh Mint by hand, or sets one line of words in an accent.
class ColourRolesTest {

    private val main = File("src/main/java/com/stethoscore/app")
    private val sources: List<Pair<String, String>> by lazy {
        main.walkTopDown().filter { it.isFile && it.extension == "kt" }
            .map { it.relativeTo(main).path.replace('\\', '/') to it.readText() }
            // the Ward token layer defines the roles; the 3D map is art (T0118)
            .filter { (rel, _) -> !rel.startsWith("ui/ward/") && !rel.startsWith("ui/map/") }
            .toList()
    }

    @Test fun aRightAnswerTakesTheRightRole() = checks {
        // D7: the mode colour token (primaryInk, the section's accent) in every mode, Questions too
        for (dark in listOf(false, true)) {
            val mode = if (dark) "dark" else "light"
            for (s in WardSection.entries) {
                check("$s $mode: a right answer takes the mode's colour",
                    WardGlide.rest(WardLook(dark, s)).hex(WardToken.primaryInk, dark) == s.accent(dark))
            }
        }
        val quiz = File(main, "ui/ChartQuizViews.kt").readText()
        check("the option row draws a right answer in the mode's colour", quiz.contains("ChartQuiz.Mark.chosen, ChartQuiz.Mark.right -> accent") &&
            quiz.contains("val accent = wardColor(WardToken.primaryInk)"))
        val mint = Regex("""if \((correct|right|isRight|isTrue|verdict|ok)\) wardColor\(WardToken\.success\)""")
        val byHand = sources.flatMap { (rel, text) -> text.lines().mapIndexedNotNull { i, l -> if (mint.containsMatchIn(l)) "$rel:${i + 1}" else null } }
        check("no screen marks a right answer in Fresh Mint (D7: the mode's colour)", byHand.isEmpty(), byHand.joinToString("; "))
        val split = Regex("""\bwardRight\b|\brightIsOwn\b""")
        val stray = (sources + listOf("ui/ward/" to File(main, "ui/ward").walkTopDown().filter { it.isFile }.joinToString("\n") { it.readText() }))
            .filter { (_, text) -> split.containsMatchIn(text) }.map { it.first }
        check("no second right-answer colour (D7: one mode colour token)", stray.isEmpty(), stray.joinToString("; "))
    }

    @Test fun everyScreenNamesOnlyItsOwnModesColour() = checks {
        // a folder that belongs to one mode, and that mode's section
        val modeOf = mapOf("ui/cases/" to "cases", "ui/osce/" to "osce", "ui/narrate/" to "audio", "ui/ideas/" to "ideas",
            "ui/book/" to "textbook", "ui/mock/" to "questions")
        // the router (the section each route wears) is where sections are given out
        val router = setOf("ui/StethoscoreApp.kt")
        val named = Regex("""WardSection\.(questions|cards|textbook|cases|osce|audio|ideas)\b""")
        val stray = mutableListOf<String>()
        for ((rel, text) in sources) {
            if (rel in router) continue
            val own = modeOf.entries.firstOrNull { rel.startsWith(it.key) }?.value
            text.lines().forEachIndexed { i, l ->
                val code = l.substringBefore("//")
                named.findAll(code).forEach { if (it.groupValues[1] != own) stray.add("$rel:${i + 1} ${it.value}") }
            }
        }
        check("every screen names only its own mode's colour", stray.isEmpty(), stray.joinToString("; "))
        // a mode's own glyph shown elsewhere takes that mode's colour, as iOS's ModeTile
        val newSet = File(main, "ui/library/LibraryNewSetScreen.kt").readText()
        check("New set shows each mode in its own colour",
            newSet.contains("WardIconSquare(modeIcon(option), tone = WardTone.Accent(com.stethoscore.app.ui.ward.WardSection.fromKindRaw(option.rawValue))"))
        val list = File(main, "ui/library/LibraryList.kt").readText()
        check("the empty library shows each mode in its own colour",
            list.contains("tone = WardTone.Accent(com.stethoscore.app.ui.ward.WardSection.fromKindRaw(kind.rawValue)), size = 52.0"))
    }

    @Test fun noScreenDrawsAnAccentLiteral() = checks {
        val literal = Regex("""\bColor\(0x[0-9A-Fa-f]{6,8}\)|\bColor\.(Red|Blue|Green|Yellow|Magenta|Cyan)\b""")
        // wardRgb is the one door from the palette's table to Compose
        val doors = setOf("ui/Theme.kt")
        val found = sources.filter { it.first !in doors }.flatMap { (rel, text) ->
            text.lines().mapIndexedNotNull { i, l -> if (literal.containsMatchIn(l.substringBefore("//"))) "$rel:${i + 1}" else null }
        }
        check("no screen draws an accent literal", found.isEmpty(), found.joinToString("; "))
    }

    @Test fun wordsOnThePageAreInk() = checks {
        // the clinical flags (an abnormal value in red, the owner's targets doc) wait on the owner with D1; the
        // destructive menu items match iOS's system red; a swipe action's words match iOS's swipe button; the
        // library header's links match iOS LibraryView, which another task (T0140) owns at this commit. Home and
        // the dock are held to it since T0211 A1.
        val later = setOf("ui/library/LibraryList.kt", "ui/book/BookReaderScreen.kt")
        val accentWords = Regex("""\bText\((?!.*DropdownMenuItem).*color = (wardColor\(WardToken\.(primaryInk|success|warning|beam|ecg)\)|wardRight\(\))""")
        val found = sources.filter { it.first !in later }.flatMap { (rel, text) ->
            text.lines().mapIndexedNotNull { i, l -> if (accentWords.containsMatchIn(l) && !l.contains("DropdownMenuItem")) "$rel:${i + 1}" else null }
        }
        check("no line of words is set in an accent", found.isEmpty(), found.joinToString("; "))

        // the states model: buttons and chips say their words in ink, the kind's colour on the glyph
        for (control in WardControl.entries.filter { it.isButton || it == WardControl.chip || it == WardControl.segment }) {
            val look = control.look(WardControlState.rest)
            check("$control at rest: its words are Chart Ink", look.words == WardToken.ink, "${look.words}")
        }
        check("the main button's glyph is the section's accent", WardControl.primary.look(WardControlState.rest).glyph == WardToken.primaryInk)
        check("a destructive button's glyph is the wrong colour", WardControl.destructive.look(WardControlState.rest).glyph == WardToken.danger)
        // D8: chosen, a chip or segment is filled with the accent and says its words in near-black
        for (control in listOf(WardControl.chip, WardControl.segment)) {
            for (state in listOf(WardControlState.selected, WardControlState.selectedPressed)) {
                check("a $control $state: the accent fill, near-black words, an accent edge",
                    control.look(state).let { it.face == WardToken.primary && it.words == WardToken.onAccent && it.glyph == null && it.mark == WardToken.primaryInk })
            }
        }
        check("a chosen and disabled chip keeps its accent edge, its glyph Biro Grey",
            WardControl.chip.look(WardControlState.selectedDisabled).let { it.mark == WardToken.primaryInk && it.glyph == WardControlStates.disabledInk })
        check("onAccent is near-black #090E15 in both schemes",
            WardPalette.hex(WardToken.onAccent, false) == 0x090E15 && WardPalette.hex(WardToken.onAccent, true) == 0x090E15)
        for (dark in listOf(false, true)) for (s in WardSection.entries) {
            val r = WardPalette.contrast(WardPalette.hex(WardToken.onAccent, dark), s.fill(dark))
            check("${if (dark) "dark" else "light"} $s: near-black words read 4.5:1 on the accent fill", r >= 4.5, "%.2f".format(r))
        }
        // D8: a chosen chip with a tone keeps its tone's fill (WardChipButton's chosenInk, WardTone.ink()),
        // under near-black words: every fill a chosen chip can wear, in both schemes
        for (dark in listOf(false, true)) {
            val fills = mutableListOf("red (ecg)" to WardPalette.hex(WardToken.ecg, dark),
                "green (success)" to WardPalette.hex(WardToken.success, dark),
                "amber and warning (warning)" to WardPalette.hex(WardToken.warning, dark),
                "danger" to WardPalette.hex(WardToken.danger, dark))
            for (s in WardSection.entries) fills.add("$s's accent (blue, accent)" to s.accent(dark))
            for ((name, fill) in fills) {
                val r = WardPalette.contrast(WardPalette.hex(WardToken.onAccent, dark), fill)
                check("${if (dark) "dark" else "light"}: a chosen chip toned $name: near-black words read 4.5:1 on its fill", r >= 4.5, "%.2f".format(r))
            }
        }
        // Biro Grey would not carry near-black words (3.06:1 by day), so no chosen chip is toned grey
        val greyChip = sources.flatMap { (rel, text) ->
            Regex("""WardChipButton\(""").findAll(text).mapNotNull { m ->
                // the whole call, to its closing bracket
                var depth = 0
                var end = m.range.last
                while (end < text.length) {
                    if (text[end] == '(') depth++ else if (text[end] == ')' && --depth == 0) break
                    end++
                }
                val call = text.substring(m.range.first, minOf(text.length, end + 1))
                if (call.contains("tone = WardTone.Grey")) rel else null
            }.toList()
        }
        check("no chosen chip is toned grey", greyChip.isEmpty(), greyChip.joinToString("; "))
    }

    @Test fun coloredWordsReadAAWhereTheReviewFoundThem() = checks {
        // T0211 A1: by day, Due's amber words read 1.42:1, New's, Open plan's and the chosen dock tab's coral 2.36:1,
        // and the Ideas switcher's pink 2.25:1. Each site's words are read from its source and measured, in every
        // section, light and dark, with and without high contrast, on what is behind them: the base (one tone: the
        // page, a card, the dock's panel) and, for a chip, a pill or a chosen segment, the shade inside its well where
        // the words start. No owner case excuses a short one: words become ink, the colour goes on the glyph.
        val base = listOf(WardToken.background, WardToken.surface, WardToken.raised, WardToken.well)
        data class Site(val file: String, val anchor: String, val name: String, val pressedIn: Boolean)
        val sites = listOf(
            Site("ui/home/WardHome.kt", "@Composable private fun HomePill(", "home's countdown pill", true),
            Site("ui/home/WardHome.kt", "@Composable private fun HomeChip(", "home's Due and New chips", true),
            Site("ui/home/WardHome.kt", "Text(\"Open plan\"", "home's Open plan link", false),
            Site("ui/StethoscoreApp.kt", "@Composable private fun DockItemFace(", "the dock's tab names", true),
            Site("ui/ward/WardSwitcher.kt", "@Composable private fun <T> SwitcherStrip(", "the Ideas switcher's segments", true),
        )
        val words = Regex("""\b(?:Basic)?Text\(""")
        val colour = Regex("""color\s*=\s*(wardColor\(WardToken\.(\w+)\)|[A-Za-z_][\w.]*(?:\(\))?)""")
        for (site in sites) {
            val text = File(main, site.file).readText()
            val at = text.indexOf(site.anchor)
            check("${site.name}: found in ${site.file}", at >= 0)
            if (at < 0) continue
            // a function to its closing brace, a one-line call to its line's end
            val end = if (site.anchor.startsWith("@Composable")) text.indexOf("\n}\n", at) else text.indexOf('\n', at)
            val region = text.substring(at, if (end < 0) text.length else end)
            val inks = words.findAll(region).map { m ->
                // the call, to its closing bracket
                var depth = 0
                var i = m.range.last
                while (i < region.length) {
                    if (region[i] == '(') depth++ else if (region[i] == ')' && --depth == 0) break
                    i++
                }
                colour.find(region.substring(m.range.first, minOf(region.length, i + 1)))
            }.toList()
            check("${site.name}: every line of words names its colour", inks.isNotEmpty() && inks.all { it != null },
                "${inks.size} calls, ${inks.count { it == null }} without a colour")
            for (ink in inks.filterNotNull()) {
                val token = ink.groupValues[2].takeIf { it.isNotEmpty() }?.let { n -> WardToken.entries.firstOrNull { it.name == n } }
                check("${site.name}: its words are a palette token, so they can be measured", token != null, ink.value)
                if (token == null) continue
                for (dark in listOf(false, true)) for (hc in listOf(false, true)) for (s in WardSection.entries) {
                    val glide = WardGlide.rest(WardLook(dark, s))
                    val grounds = base.map { it.name to glide.hex(it, dark) }.toMutableList()
                    if (site.pressedIn) grounds.add("its well" to WardRelief.insetGround(glide.hex(WardToken.well, dark), WardLift.low, dark, hc, 6.0))
                    for ((on, ground) in grounds) {
                        val r = WardPalette.contrast(glide.hex(token, dark), ground)
                        check("${if (dark) "dark" else "light"}${if (hc) " high contrast" else ""} $s: ${site.name} ($token) read 4.5:1 on $on",
                            r >= 4.5, f2(r))
                    }
                }
            }
        }
    }

    @Test fun aChosenLabelSaysItsWordsInNearBlack() = checks {
        // D8: a chip that draws its own label (ChipBox's chipInk, Coverage's CountChip) and the
        // timer on a chosen fill (WardTimerPill's onFill, the OSCE clock) say their words in onAccent
        val mock = File(main, "ui/mock/MockKit.kt").readText()
        check("ChipBox's chosen label is near-black (chipInk)", mock.contains("on -> wardColor(WardToken.onAccent)"))
        val coverage = File(main, "ui/coverage/CoverageScreen.kt").readText()
        check("CountChip's chosen count, words and glyph are near-black",
            coverage.contains("val onFill = wardColor(WardToken.onAccent)") &&
                coverage.contains("val countInk = if (chosen) onFill else") &&
                coverage.contains("val words = if (chosen) onFill else") &&
                coverage.contains("tint = if (chosen) onFill else"))
        val controls = File(main, "ui/ward/WardControls.kt").readText()
        check("the timer's words and glyph on a chosen fill are near-black (onFill)",
            controls.contains("val words = if (onFill) wardColor(WardToken.onAccent) else") &&
                controls.contains("val glyph = if (onFill) words else"))
        val osce = File(main, "ui/osce/OsceReviewScreen.kt").readText()
        check("the OSCE clock on its chosen fill draws the timer onFill, its glyph near-black",
            osce.contains("onFill = running") && osce.contains("tint = wardColor(if (running) WardToken.onAccent else"))
    }

    @Test fun aClozeGapIsInkUnderTheModesColour() = checks {
        // D16: a cloze answer's words are ink, the underline drawn under it the mode colour token
        val face = File(main, "ui/AnkiCardFace.kt").readText()
        val cloze = face.substringAfter("@Composable private fun ClozeSentence(").substringBefore("\n}\n")
        check("the cloze gap's underline takes the mode colour token",
            cloze.contains("val accent = wardColor(WardToken.primaryInk)") && cloze.contains("drawLine(accent,"))
        check("the cloze sentence's words are ink", cloze.contains("color = wardColor(WardToken.ink)") &&
            face.contains("val ink = wardColor(WardToken.ink)"))
    }
}
