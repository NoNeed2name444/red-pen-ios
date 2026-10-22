package com.stethoscore.app.ui.ward

import com.stethoscore.app.ui.homeSection
import org.junit.Test
import java.io.File

// A port of upstream/ios/RedPen/Tests/WardLookTests.swift's "Each section's
// wash" and "The opening's ground is home's" checks, same cases. The owner,
// 21 Oct, on the launch's first frame and home: "the background color doesn't
// match the main menu". The window's starting background (ward_ground, light
// and night, and the Android 12 splash), the window's background from the
// app's first frame (WardGroundDrawable) and home (WardGroundBackground) all
// stand on home's ground for the section home opens on.
class WardGroundTest {

    private val modes = listOf(false, true)
    private fun mode(dark: Boolean) = if (dark) "dark" else "light"

    // The grounds are pinned to 7af549b, before the owner's ten colours, so
    // they no longer follow the fills: each section's fill then, and the wash
    // it made (light, dark).
    private val fillsAt7af549b = mapOf(
        WardSection.questions to WardPair(0xC03946, 0xCB3E4B),
        WardSection.cards to WardPair(0x5260BC, 0x5A68C5),
        WardSection.textbook to WardPair(0x227D75, 0x258279),
        WardSection.cases to WardPair(0xAC5A21, 0xB05C23),
        WardSection.osce to WardPair(0x3D7C49, 0x42814F),
        WardSection.audio to WardPair(0x8150AD, 0x8B57B8),
        WardSection.ideas to WardPair(0xB23E86, 0xBA438E),
    )
    private val washesAt7af549b = mapOf(
        WardSection.questions to WardPair(0xE7E7EC, 0x49212A),
        WardSection.cards to WardPair(0xE3E8EF, 0x242B4C),
        WardSection.textbook to WardPair(0xE3E8ED, 0x193335),
        WardSection.cases to WardPair(0xE6E7EC, 0x402824),
        WardSection.osce to WardPair(0xE3E8EC, 0x1E322B),
        WardSection.audio to WardPair(0xE4E7EF, 0x332747),
        WardSection.ideas to WardPair(0xE6E7ED, 0x43223A),
    )

    @Test fun eachSectionsWash() = checks {
        for (dark in modes) {
            val chartInk = WardPalette.hex(WardToken.ink, dark)
            val biroGrey = WardPalette.hex(WardToken.inkSecondary, dark)
            for (s in WardSection.entries) {
                val wash = s.wash(dark)
                check("${mode(dark)} $s: wash is the base mixed toward its 7af549b fill (0.06 by day, 0.10 at night)",
                    wash == WardPalette.mix(WardPalette.hex(WardToken.background, dark), fillsAt7af549b.getValue(s).of(dark), if (dark) 0.10 else 0.06) &&
                        s.wash.of(dark) == wash, hx(wash))
                val cChart = WardPalette.contrast(chartInk, wash)
                check("${mode(dark)} $s: Chart Ink keeps 4.5:1 on its wash", cChart >= 4.5, "${hx(wash)} ${f2(cChart)}")
                val cBiro = WardPalette.contrast(biroGrey, wash)
                check("${mode(dark)} $s: Biro Grey keeps 4.5:1 on its wash", cBiro >= 4.5, "${hx(wash)} ${f2(cBiro)}")
                val cAccent = WardPalette.contrast(s.accent(dark), wash)
                check("${mode(dark)} $s: its accent keeps 4.5:1 on its wash", cAccent >= 4.5, "${hx(wash)} ${f2(cAccent)}")
            }
            val washes = WardSection.entries.map { it.wash(dark) }
            check("${mode(dark)}: no two sections' washes are the same", washes.toSet().size == washes.size)
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
    }

    // The backgrounds are exactly as they were at 7af549b, whatever the
    // fills: every section's wash, the outside look's ground, home's ground
    // and the window's and the splash's (ward_ground), and the neutral tiers
    // the dock's panel and the bottom deck's slab stand on.
    @Test fun theGroundsAreAsAt7af549b() = checks {
        for (dark in modes) {
            for (s in WardSection.entries) {
                val want = washesAt7af549b.getValue(s).of(dark)
                check("${mode(dark)} $s: the wash is 7af549b's", s.wash(dark) == want, "${hx(s.wash(dark))} vs ${hx(want)}")
                check("${mode(dark)} $s: home's ground stands on it", WardGround.home(s, dark).base == want, hx(WardGround.home(s, dark).base))
            }
            val outside = WardGround.home(WardSection.outside, dark).base
            check("${mode(dark)}: the outside look's ground is 7af549b's", outside == (if (dark) 0x242B4C else 0xE3E8EF), hx(outside))
            val home = WardGround.home(dark = dark).base
            check("${mode(dark)}: home's ground (Questions) is 7af549b's", home == (if (dark) 0x49212A else 0xE7E7EC), hx(home))
            val res = colour(if (dark) "values-night" else "values", "ward_ground")
            check("${mode(dark)}: ward_ground, the window's and the splash's ground, is 7af549b's",
                res == (if (dark) 0x49212A else 0xE7E7EC), res?.let(::hx) ?: "none")
        }
        // the base, cards and the dock's and deck's slabs (surface), sheets (raised) and wells
        val tiers = mapOf(
            WardToken.background to WardPair(0xE9EDF2, 0x171C24),
            WardToken.surface to WardPair(0xEEF1F5, 0x242B35),
            WardToken.raised to WardPair(0xF1F4F8, 0x2E353F),
            WardToken.well to WardPair(0xDDE2E8, 0x090E15),
        )
        for ((token, pair) in tiers) for (dark in modes) {
            val hex = WardPalette.hex(token, dark)
            check("${mode(dark)} $token is 7af549b's", hex == pair.of(dark), hx(hex))
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
        check("home draws the same ground for its section", app.contains("WardGroundBackground(WardGround.home(section, dark),Modifier.fillMaxSize())") &&
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
