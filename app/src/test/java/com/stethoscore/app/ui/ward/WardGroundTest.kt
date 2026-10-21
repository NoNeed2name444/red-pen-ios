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

    @Test fun eachSectionsWash() = checks {
        for (dark in modes) {
            val chartInk = WardPalette.hex(WardToken.ink, dark)
            val biroGrey = WardPalette.hex(WardToken.inkSecondary, dark)
            for (s in WardSection.entries) {
                val wash = s.wash(dark)
                check("${mode(dark)} $s: wash is the base mixed toward the fill (0.06 by day, 0.10 at night)",
                    wash == WardPalette.mix(WardPalette.hex(WardToken.background, dark), s.fill(dark), if (dark) 0.10 else 0.06) &&
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
