package com.stethoscore.app.ui.ward

import com.stethoscore.app.ui.homeSection
import org.junit.Test
import java.io.File

// A port of ios/RedPen/Tests/WardLookTests.swift's "Each section's
// wash" and "The opening's ground is home's" checks, same cases. The owner,
// 21 Oct, on the launch's first frame and home: "the background color doesn't
// match the main menu". The window's starting background (ward_ground, light
// and night, and the Android 12 splash), the window's background from the
// app's first frame (WardGroundDrawable) and home (WardGroundBackground) all
// stand on home's ground for the section home opens on.
class WardGroundTest {

    private val modes = listOf(false, true)
    private fun mode(dark: Boolean) = if (dark) "dark" else "light"

    // The grounds are the plain base (light, dark), as before the section's
    // wash (iOS 73f09a7, 21 Oct) existed: the owner never asked for the wash,
    // and the owner's phone build has plain grey grounds.
    private val plainBase = WardPair(0xE9EDF2, 0x171C24)

    @Test fun eachSectionsWash() = checks {
        val test = "WardGroundTest.eachSectionsWash"
        for (dark in modes) {
            val chartInk = WardPalette.hex(WardToken.ink, dark)
            val biroGrey = WardPalette.hex(WardToken.inkSecondary, dark)
            for (s in WardSection.entries) {
                val wash = s.wash(dark)
                check("${mode(dark)} $s: wash is the plain base",
                    wash == WardPalette.hex(WardToken.background, dark) && wash == plainBase.of(dark) && s.wash.of(dark) == wash, hx(wash))
                val cChart = WardPalette.contrast(chartInk, wash)
                check("${mode(dark)} $s: Chart Ink keeps 4.5:1 on its wash", cChart >= 4.5, "${hx(wash)} ${f2(cChart)}")
                val cBiro = WardPalette.contrast(biroGrey, wash)
                check("${mode(dark)} $s: Biro Grey keeps 4.5:1 on its wash", cBiro >= 4.5, "${hx(wash)} ${f2(cBiro)}")
                val cAccent = WardPalette.contrast(s.accent(dark), wash)
                check("${mode(dark)} $s: its accent keeps 4.5:1 on its wash", cAccent >= 4.5, "${hx(wash)} ${f2(cAccent)}",
                    OwnerCase(test, "its accent keeps 4.5:1 on its wash", "accent", "$s", mode(dark), "its wash"), cAccent)
            }
            val washes = WardSection.entries.map { it.wash(dark) }
            check("${mode(dark)}: every section's wash is the same plain base", washes.toSet() == setOf(plainBase.of(dark)))
        }
        val now = WardLookNow()
        for (section in WardSection.entries) for (dark in modes) {
            now.set(WardGlide.rest(WardLook(dark, section)))
            check("drawn now: $section ${mode(dark)} wash", now.wash(dark) == section.wash(dark))
        }
        val shift = WardGlide(WardLook(false, WardSection.outside), WardLook(false, WardSection.questions), 0.5)
        now.set(shift)
        val expect = WardPalette.mix(WardSection.cards.wash(false), WardSection.questions.wash(false), shift.eased)
        check("mid-shift, wash is linear-light mix", now.wash(false) == expect, "${hx(now.wash(false))} vs ${hx(expect)}")
        everyOwnerCaseMade(test)
    }

    // The owner, 4 Nov: a wash of each mode's earlier colour behind its screens,
    // "randomly tinted like the screenshots", "stronger a bit" (iOS WardLookTests
    // "Each mode's wash", the same seeds and numbers): the earlier backdrop's 3x3
    // mesh, each screen's from its own seed. Measured at the strongest point a mesh
    // can have, the cap, since cards and wells are see-through over it. Ideas has
    // none, and home's ground stays the plain base.
    private class MeshPin(val seed: Long, val strengths: List<Double>, val x: List<Double>, val y: List<Double>,
                          val questionsLight: List<Int>, val cardsDark: List<Int>, val top: Int, val bottom: Int, val sample: Double)

    private val meshPins = listOf(
        MeshPin(1, listOf(0.3883, 0.2742, 0.4000, 0.1889, 0.0514, 0.2776, 0.3755, 0.2046, 0.3321),
            listOf(0.5706, 0.5253, 0.4846), listOf(0.4770, 0.4892, 0.5072),
            listOf(0xD2ADB0, 0xD9C0C4, 0xD1ABAE, 0xDECED2, 0xE6E4E9, 0xD9BFC3, 0xD3AFB3, 0xDDCBCF, 0xD5B6BA),
            listOf(0x2B314E, 0x252B41, 0x2B314F, 0x212638, 0x1A1F29, 0x252B42, 0x2A304C, 0x21273A, 0x282E48),
            0xD4B2B6, 0xD7BBBF, 0.242218),
        MeshPin(42, listOf(0.4000, 0.1570, 0.2807, 0.1688, 0.0000, 0.2986, 0.2437, 0.2601, 0.3430),
            listOf(0.5284, 0.4983, 0.5396), listOf(0.4292, 0.5032, 0.5048),
            listOf(0xD1ABAE, 0xE0D3D7, 0xD8BEC3, 0xDFD1D5, 0xE9EDF2, 0xD7BCC0, 0xDBC5C9, 0xDAC2C6, 0xD5B4B8),
            listOf(0x2B314F, 0x1F2435, 0x252B42, 0x202536, 0x171C24, 0x262C44, 0x23293E, 0x242A40, 0x292E49),
            0xD9BFC3, 0xD8BEC2, 0.198770),
        MeshPin(20261104, listOf(0.3475, 0.2451, 0.4000, 0.1471, 0.1585, 0.3057, 0.3070, 0.1889, 0.3504),
            listOf(0.5277, 0.4752, 0.5134), listOf(0.4483, 0.5525, 0.4536),
            listOf(0xD4B3B7, 0xDBC4C9, 0xD1ABAE, 0xE0D5D9, 0xE0D3D7, 0xD7BABE, 0xD7BABE, 0xDECED2, 0xD4B3B7),
            listOf(0x292F49, 0x24293E, 0x2B314F, 0x1F2434, 0x1F2435, 0x272C45, 0x272C45, 0x212638, 0x292F49),
            0xD5B6BA, 0xD8BEC2, 0.237478),
    )

    private fun near(a: List<Double>, b: List<Double>) = a.size == b.size && a.zip(b).all { (p, q) -> kotlin.math.abs(p - q) < 5e-5 }

    @Test fun eachModesWash() = checks {
        val test = "WardGroundTest.eachModesWash"
        val colours = mapOf(
            WardSection.questions to 0xC72929, WardSection.cards to 0x4F5CDB, WardSection.textbook to 0x1A8C80,
            WardSection.cases to 0xE67D21, WardSection.osce to 0x339E59, WardSection.audio to 0x8C52CC,
        )
        check("each mode's wash colour is its earlier colour", WardModeWash.colour == colours)
        check("Ideas has no wash", WardModeWash.colours(WardSection.ideas, false, WardModeWash.mesh(1)) == null &&
            WardModeWash.strongest(WardSection.ideas, true) == null)
        check("the wash's rule: the earlier mesh's strengths, moved 0.08 and 0.12, a quarter stronger to 0.40, 0.7 at night, 35% to grey",
            WardModeWash.strengths == listOf(0.30, 0.18, 0.26, 0.16, 0.05, 0.18, 0.24, 0.16, 0.30) &&
                WardModeWash.strengthJitter == 0.08 && WardModeWash.pointJitter == 0.12 && WardModeWash.boost == 1.25 &&
                WardModeWash.cap == 0.40 && WardModeWash.night == 0.7 && WardModeWash.greyPull == 0.35)
        for (pin in meshPins) {
            val mesh = WardModeWash.mesh(pin.seed)
            check("seed ${pin.seed}: the mesh's strengths", near(mesh.strengths, pin.strengths), mesh.strengths.toString())
            check("seed ${pin.seed}: the inner points moved",
                near(listOf(mesh.x[1], mesh.x[4], mesh.x[7]), pin.x) && near(listOf(mesh.y[3], mesh.y[4], mesh.y[5]), pin.y) &&
                    listOf(0, 2, 3, 5, 6, 8).all { mesh.x[it] == listOf(0.0, 0.5, 1.0)[it % 3] } &&
                    listOf(0, 1, 2, 6, 7, 8).all { mesh.y[it] == listOf(0.0, 0.5, 1.0)[it / 3] })
            check("seed ${pin.seed}: the same seed, the same mesh", WardModeWash.mesh(pin.seed) == mesh)
            check("seed ${pin.seed}: Questions by day", WardModeWash.colours(WardSection.questions, false, mesh) == pin.questionsLight)
            check("seed ${pin.seed}: Cards at night", WardModeWash.colours(WardSection.cards, true, mesh) == pin.cardsDark)
            check("seed ${pin.seed}: the bars' colours, the rows' means",
                WardModeWash.edge(WardSection.questions, false, mesh, bottom = false) == pin.top &&
                    WardModeWash.edge(WardSection.questions, false, mesh, bottom = true) == pin.bottom)
            check("seed ${pin.seed}: the blend between the points", kotlin.math.abs(WardModeWash.strength(mesh, 0.25, 0.25) - pin.sample) < 5e-6)
            check("seed ${pin.seed}: the blend is each point's own at it",
                (0 until 9).all { WardModeWash.strength(mesh, mesh.x[it], mesh.y[it]) == mesh.strengths[it] })
            val px = WardModeWash.pixels(WardSection.questions, false, mesh, 4, 4)
            check("seed ${pin.seed}: the drawn picture is the blend, opaque",
                px != null && px.size == 16 && px.all { (it ushr 24) == 0xFF } &&
                    px[5] == (0xFF000000.toInt() or WardModeWash.hex(WardSection.questions, false, WardModeWash.strength(mesh, 0.375, 0.375))!!))
        }
        var top = 0.0
        for (seed in 0L until 2000L) {
            val mesh = WardModeWash.mesh(seed)
            top = maxOf(top, mesh.strengths.max(), WardModeWash.strength(mesh, 0.3, 0.7))
        }
        check("no mesh is stronger than the cap", top <= WardModeWash.cap, f2(top))
        val strongestPossible = mapOf(
            "light questions" to 0xD1ABAE, "light cards" to 0xB2B8DD, "light textbook" to 0xA4C4C5,
            "light cases" to 0xD9C1AC, "light osce" to 0xABC9BB, "light audio" to 0xC2B5D9,
            "dark questions" to 0x41282E, "dark cards" to 0x2B314F, "dark textbook" to 0x223A3E,
            "dark cases" to 0x47372D, "dark osce" to 0x263D37, "dark audio" to 0x37304C,
        )
        for (dark in modes) {
            val chartInk = WardPalette.hex(WardToken.ink, dark)
            val biroGrey = WardPalette.hex(WardToken.inkSecondary, dark)
            val base = plainBase.of(dark)
            for (s in WardSection.entries.filter { it != WardSection.ideas }) {
                val strongest = WardModeWash.strongest(s, dark)
                check("${mode(dark)} $s: the strongest possible point is as measured",
                    strongest == strongestPossible["${mode(dark)} $s"], strongest?.let(::hx) ?: "none")
                check("${mode(dark)} $s: home's ground stays the plain base", WardGround.home(s, dark).base == base)
                if (strongest == null) continue
                val cChart = WardPalette.contrast(chartInk, strongest)
                check("${mode(dark)} $s: Chart Ink keeps 4.5:1 on its mode wash", cChart >= 4.5, "${hx(strongest)} ${f2(cChart)}")
                val cBiro = WardPalette.contrast(biroGrey, strongest)
                check("${mode(dark)} $s: Biro Grey keeps 4.5:1 on its mode wash", cBiro >= 4.5, "${hx(strongest)} ${f2(cBiro)}",
                    OwnerCase(test, "Biro Grey keeps 4.5:1 on its mode wash", "Biro Grey", "$s", mode(dark), "its mode wash"), cBiro)
                val cAccent = WardPalette.contrast(s.accent(dark), strongest)
                check("${mode(dark)} $s: its accent keeps 4.5:1 on its mode wash", cAccent >= 4.5, "${hx(strongest)} ${f2(cAccent)}",
                    OwnerCase(test, "its accent keeps 4.5:1 on its mode wash", "accent", "$s", mode(dark), "its mode wash"), cAccent)
            }
        }
        check("every case pending the owner's word is on the list", OwnerAccepted.pending.all { it in OwnerAccepted.cases })
        val app = File("src/main/java/com/stethoscore/app/ui/StethoscoreApp.kt").takeIf { it.exists() }?.readText() ?: ""
        check("the wash stands behind the mode's screens only, not home, settings, Sources or Ideas",
            app.contains("val washed=screen in modeWashScreens && section in com.stethoscore.app.ui.ward.WardModeWash.colour") &&
                com.stethoscore.app.ui.modeWashScreens.none { it in setOf("home", "settings", "sources", "ideas", "licences", "exam") })
        check("what floats over the page has no wash under it",
            app.contains("LocalWardModeWash provides null) {\n                com.stethoscore.app.ui.learn.WardRoundFloat()") &&
                app.contains("LocalWardModeWash provides null) {\n            com.stethoscore.app.ui.learn.LearnSheet("))
        everyOwnerCaseMade(test)
    }

    // The backgrounds are the plain base, whatever the section and the fills:
    // every section's wash, the outside look's ground, home's ground and the
    // window's and the splash's (ward_ground); and the neutral tiers the
    // dock's panel and the bottom deck's slab stand on are as they were.
    @Test fun theGroundsAreThePlainBase() = checks {
        for (dark in modes) {
            val want = plainBase.of(dark)
            for (s in WardSection.entries) {
                check("${mode(dark)} $s: the wash is the plain base", s.wash(dark) == want, "${hx(s.wash(dark))} vs ${hx(want)}")
                check("${mode(dark)} $s: home's ground stands on it", WardGround.home(s, dark).base == want, hx(WardGround.home(s, dark).base))
            }
            val outside = WardGround.home(WardSection.outside, dark).base
            check("${mode(dark)}: the outside look's ground is the plain base", outside == want, hx(outside))
            val home = WardGround.home(dark = dark).base
            check("${mode(dark)}: home's ground (Questions) is the plain base", home == want, hx(home))
            val res = colour(if (dark) "values-night" else "values", "ward_ground")
            check("${mode(dark)}: ward_ground, the window's and the splash's ground, is the plain base",
                res == want, res?.let(::hx) ?: "none")
        }
        // the base, cards and the dock's and deck's slabs (surface), sheets (raised) and wells;
        // cards and sheets are the base's own colour (one tone, the owner 22 Oct: "there shouldn't be 2 tones")
        val tiers = mapOf(
            WardToken.background to WardPair(0xE9EDF2, 0x171C24),
            WardToken.surface to WardPair(0xE9EDF2, 0x171C24),
            WardToken.raised to WardPair(0xE9EDF2, 0x171C24),
            WardToken.well to WardPair(0xDDE2E8, 0x090E15),
        )
        for ((token, pair) in tiers) for (dark in modes) {
            val hex = WardPalette.hex(token, dark)
            check("${mode(dark)} $token is as it was", hex == pair.of(dark), hx(hex))
            for (s in WardSection.entries) {
                check("${mode(dark)} $token stays put in $s", WardGlide.rest(WardLook(dark, s)).hex(token, dark) == pair.of(dark))
            }
        }
    }

    @Test fun theOpeningsGroundIsHomes() = checks {
        check("home opens on WardSection.opening: Questions, the dock's first category",
            WardSection.opening == WardSection.questions && homeSection("Questions") == WardSection.opening)
        check("each other category is its own section",
            homeSection("Cards") == WardSection.cards && homeSection("Cases") == WardSection.cases &&
                homeSection("OSCE") == WardSection.osce && homeSection("Audio") == WardSection.audio)
        for (section in WardSection.entries) for (dark in modes) {
            val ground = WardGround.home(section, dark)
            val look = WardGlide.rest(WardLook(dark, section))
            check("$section ${mode(dark)}: the ground's base is home's wash",
                ground.base == section.wash(dark) && ground.base == look.wash(dark), hx(ground.base))
            check("$section ${mode(dark)}: the ground's grid is home's paper ink",
                ground.ink == WardPaper.ink(look, dark, highContrast = false) && ground.ink.hex == section.ink(dark), hx(ground.ink.hex))
            val high = WardGround.home(section, dark, highContrast = true)
            check("$section ${mode(dark)}: under high contrast the ground has no grid, as home's paper",
                high.ink.fine == 0.0 && high.ink.bold == 0.0)
        }
    }

    /** A colour resource's 0xRRGGBB, from res/<dir>/colors.xml. */
    private fun colour(dir: String, name: String): Int? {
        val file = File("src/main/res/$dir/colors.xml")
        if (!file.exists()) return null
        val m = Regex("<color name=\"$name\">#FF([0-9A-Fa-f]{6})</color>").find(file.readText()) ?: return null
        return m.groupValues[1].toInt(16)
    }

    @Test fun theWindowStandsOnIt() = checks {
        for (dark in modes) {
            val res = colour(if (dark) "values-night" else "values", "ward_ground")
            val ground = WardGround.home(dark = dark)
            check("ward_ground (${mode(dark)}) is home's ground for the opening section", res == ground.base,
                "${res?.let(::hx) ?: "none"} vs ${hx(ground.base)}")
        }
        val styles = File("src/main/res/values/styles.xml").takeIf { it.exists() }?.readText() ?: ""
        val v31 = File("src/main/res/values-v31/styles.xml").takeIf { it.exists() }?.readText() ?: ""
        check("the starting window's background is ward_ground", styles.contains("<item name=\"android:windowBackground\">@color/ward_ground</item>"))
        check("Android 12's splash screen stands on ward_ground", v31.contains("<item name=\"android:windowSplashScreenBackground\">@color/ward_ground</item>"))
        val activity = File("src/main/java/com/stethoscore/app/MainActivity.kt").takeIf { it.exists() }?.readText() ?: ""
        check("the window's background from the first frame is the drawn ground, in the app's mode",
            activity.contains("WardGroundDrawable(WardGround.home(dark = dark)") && activity.indexOf("showGround(this, dark)") in 0 until activity.indexOf("setContent {"))
        val app = File("src/main/java/com/stethoscore/app/ui/StethoscoreApp.kt").takeIf { it.exists() }?.readText() ?: ""
        check("home draws the same ground for its section", app.contains("WardGroundBackground(WardGround.home(section, dark),Modifier.fillMaxSize(),gridBottom={ bandBottom })") &&
            app.contains("\"home\" -> homeSection(category)"))
        check("home starts on Questions", app.contains("var category by rememberSaveable { mutableStateOf(\"Questions\") }"))
    }

    // The drawable and Compose draw the same lines: each k·cell, bold every fifth, from the top left.
    @Test fun theGridLines() = checks {
        val lines = com.stethoscore.app.ui.wardGridLines(100f, 15.75f)
        check("lines at every cell from 0", lines.map { it.first } == (0..6).map { it * 15.75f }, lines.toString())
        check("bold every fifth, from the first", lines.map { it.second } == listOf(true, false, false, false, false, true, false))
        check("no lines for nothing", com.stethoscore.app.ui.wardGridLines(0f, 15.75f).isEmpty())
    }
}
