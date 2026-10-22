package com.stethoscore.app.ui.ward

import org.json.JSONObject
import org.junit.Test
import java.io.File
import kotlin.math.abs
import kotlin.math.sqrt

// A port of ios/RedPen/Tests/WardPaletteTests.swift, same cases and
// numbers: every text colour keeps its promised contrast on the surface it
// sits on, in light and in dark, and the iOS AccentColor and LaunchBackground
// assets are the primary (Cards' indigo) and the bases from the same table.
class WardPaletteTest {

    // the nearest a chip's words come to its edge: its vertical padding (4)
    // and the line's own leading above a capital (2 at least)
    private val chipTextDepth = 6.0
    private val modes = listOf(false, true)
    private fun mode(dark: Boolean) = if (dark) "dark" else "light"

    // The tests whose cases the owner's exact colours fail (OwnerAccepted).
    private val promisesTest = "WardPaletteTest.promisesHold"
    private val chipsTest = "WardPaletteTest.chipInksReadOnTheirWell"
    private val twoCharactersTest = "WardPaletteTest.twoCharacters"

    private fun distance(x: Int, y: Int): Double {
        val p = oklab(x)
        val q = oklab(y)
        return sqrt((p.L - q.L) * (p.L - q.L) + (p.a - q.a) * (p.a - q.a) + (p.b - q.b) * (p.b - q.b))
    }

    @Test fun promisesHold() = checks {
        check("every token has a value", WardToken.entries.all { WardPalette.table[it] != null })
        check("white on black is 21", abs(WardPalette.contrast(0xFFFFFF, 0x000000) - 21) < 0.01)
        check("Theatre Blue on Clean Sheet is about 6.3",
            abs(WardPalette.contrast(0x1D5FB0, 0xFFFFFF) - 6.3) < 0.1, WardPalette.contrast(0x1D5FB0, 0xFFFFFF).toString())
        for (dark in modes) {
            for (p in WardPalette.promises) {
                val r = WardPalette.contrast(WardPalette.hex(p.text, dark), WardPalette.hex(p.on, dark))
                check("${mode(dark)}: ${p.text} on ${p.on} at least ${p.ratio}", r >= p.ratio, f2(r),
                    OwnerCase(promisesTest, "a text colour on what it sits on at least ${p.ratio}", "${p.text}", "the palette", mode(dark), "${p.on}"), r)
            }
        }
        everyOwnerCaseMade(promisesTest)
    }

    // The words of a chip or a pill sit on a well pressed into what is under
    // it, with the well's inner shade over its edge. Every ink a chip can wear
    // reads 4.5:1 on it, in light and dark, with and without Increase Contrast.
    @Test fun chipInksReadOnTheirWell() = checks {
        check("the shade is there at a chip's edge and gone where its words start",
            WardRelief.shadeCoverage(WardLift.low, depth = 0.0) > 0.5 && WardRelief.shadeCoverage(WardLift.low, depth = 6.0) < 0.01)
        val chipInks = listOf(WardToken.primaryInk, WardToken.ecg, WardToken.success, WardToken.warning, WardToken.danger,
            WardToken.inkSecondary, WardToken.ink)
        for (dark in modes) {
            for (hc in listOf(false, true)) {
                val m = "${mode(dark)}${if (hc) " with Increase Contrast" else ""}"
                val well = WardPalette.hex(WardToken.well, dark)
                val ground = WardRelief.insetGround(well, WardLift.low, dark, hc, chipTextDepth)
                for (token in chipInks) {
                    val r = WardPalette.contrast(WardPalette.hex(token, dark), ground)
                    check("$m: $token reads 4.5:1 on a chip's well", r >= 4.5, f3(r),
                        OwnerCase(chipsTest, "reads 4.5:1 on a chip's well", "$token", "the palette", m, "a chip's well"), r)
                }
                for (section in WardSection.entries) {
                    val r = WardPalette.contrast(section.accent(dark), ground)
                    check("$m: $section's accent reads 4.5:1 on a chip's well", r >= 4.5, f3(r),
                        OwnerCase(chipsTest, "reads 4.5:1 on a chip's well", "accent", "$section", m, "a chip's well"), r)
                }
            }
        }
        check("the monitor card is dark in both modes",
            WardPalette.luminance(WardPalette.hex(WardToken.monitor, false)) < 0.05 &&
                WardPalette.luminance(WardPalette.hex(WardToken.monitor, true)) < 0.05)
        everyOwnerCaseMade(chipsTest)
    }

    // soft UI on close tiers: a well, the base, a card, a sheet, each a shade
    // off the one before, so a card is told from the ground mostly by relief
    @Test fun tiersAreSoftSteps() = checks {
        for (dark in modes) {
            val m = mode(dark)
            val lum = WardPalette.tiers.map { WardPalette.luminance(WardPalette.hex(it, dark)) }
            check("$m: the tiers rise from well to sheet", lum == lum.sorted() && lum.toSet().size == lum.size)
            for ((a, b) in WardPalette.tiers.zipWithNext()) {
                val step = WardPalette.contrast(WardPalette.hex(a, dark), WardPalette.hex(b, dark))
                check("$m: $a to $b is a soft step", step > 1.02 && step < 1.25, f3(step))
            }
            val groove = WardPalette.contrast(WardPalette.hex(WardToken.hairline, dark), WardPalette.hex(WardToken.background, dark))
            check("$m: a groove shows but stays soft", groove >= 1.1 && groove < 1.6, f2(groove))
        }
        // palette direction 3's grounds (16 Oct): the launch screen is drawn on them
        check("the bases the launch screen is drawn on are kept",
            WardPalette.hex(WardToken.background, false) == 0xE9EDF2 && WardPalette.hex(WardToken.background, true) == 0x171C24)
    }

    // two characters, not one palette inverted: every text colour differs
    // between the modes. The primary is the look outside any section: Cards'.
    @Test fun twoCharacters() = checks {
        for (dark in modes) {
            check("${mode(dark)}: primary and primaryInk are Cards' fill and accent",
                WardPalette.hex(WardToken.primary, dark) == WardSection.cards.fill(dark) &&
                    WardPalette.hex(WardToken.primaryInk, dark) == WardSection.cards.accent(dark) &&
                    WardSection.outside == WardSection.cards)
        }
        for (token in listOf(WardToken.primaryInk, WardToken.ecg, WardToken.success, WardToken.warning, WardToken.danger,
            WardToken.ink, WardToken.inkSecondary, WardToken.beam)) {
            val day = WardPalette.hex(token, false)
            val night = WardPalette.hex(token, true)
            // how far apart the two values are (OKLab): 0 when one value serves both modes
            val apart = distance(day, night)
            check("$token has a value of its own in each mode", day != night, "${hx(day)} / ${hx(night)} ${f3(apart)}",
                OwnerCase(twoCharactersTest, "a value of its own in each mode", "$token", "the palette", "light and dark", "the other mode"), apart)
        }
        // night reads its secondary text more strongly than day: dim rooms need it
        val daySecondary = WardPalette.contrast(WardPalette.hex(WardToken.inkSecondary, false), WardPalette.hex(WardToken.background, false))
        val nightSecondary = WardPalette.contrast(WardPalette.hex(WardToken.inkSecondary, true), WardPalette.hex(WardToken.background, true))
        check("night's secondary text has more contrast than day's", nightSecondary > daySecondary,
            "${f2(nightSecondary)} vs ${f2(daySecondary)}")
        everyOwnerCaseMade(twoCharactersTest)
    }

    // the contrast maths, against WCAG's own worked values
    @Test fun contrastMaths() = checks {
        check("contrast is symmetric", WardPalette.contrast(0x1D5FB0, 0xE0E5EC) == WardPalette.contrast(0xE0E5EC, 0x1D5FB0))
        check("a colour on itself is 1", WardPalette.contrast(0x2A2E35, 0x2A2E35) == 1.0)
        check("mid grey #777 on white is about 4.48 (just under AA)",
            abs(WardPalette.contrast(0x777777, 0xFFFFFF) - 4.48) < 0.01, WardPalette.contrast(0x777777, 0xFFFFFF).toString())
        check("#767676 on white is about 4.54 (just AA)",
            abs(WardPalette.contrast(0x767676, 0xFFFFFF) - 4.54) < 0.01, WardPalette.contrast(0x767676, 0xFFFFFF).toString())
        check("luminance of white is 1 and black 0", WardPalette.luminance(0xFFFFFF) == 1.0 && WardPalette.luminance(0) == 0.0)
    }

    // the appearance glide: a colour shift through linear light, from one
    // palette to the other, about a third of a second
    @Test fun glideMixesInLinearLight() = checks {
        check("the glide takes 0.3 to 0.4 s", WardSchemeGlide.duration in 0.3..0.4)
        for (token in WardToken.entries) {
            check("glide $token: starts at day and ends at night",
                WardSchemeGlide.frame(token, 0.0) == WardPalette.hex(token, false) &&
                    WardSchemeGlide.frame(token, 1.0) == WardPalette.hex(token, true))
        }
        check("mix clamps", WardPalette.mix(0x000000, 0xFFFFFF, -1.0) == 0 && WardPalette.mix(0x000000, 0xFFFFFF, 2.0) == 0xFFFFFF)
        check("halfway between black and white in linear light is #BCBCBC",
            WardPalette.mix(0x000000, 0xFFFFFF, 0.5) == 0xBCBCBC, Integer.toHexString(WardPalette.mix(0, 0xFFFFFF, 0.5)))
        var lastLum = 2.0
        var steady = true
        for (i in 0..20) {
            val l = WardPalette.luminance(WardSchemeGlide.frame(WardToken.background, i / 20.0))
            if (l > lastLum + 1e-9) steady = false
            lastLum = l
        }
        check("the base darkens steadily through the glide, never flashing", steady)
    }

    @Test fun spacingScaleAndBases() = checks {
        check("the scale is 4, 8, 12, 16, 24, 32", WardScale.steps == listOf(4.0, 8.0, 12.0, 16.0, 24.0, 32.0) &&
            listOf(WardScale.xs, WardScale.s, WardScale.m, WardScale.l, WardScale.xl, WardScale.xxl) == WardScale.steps)
        check("on the scale", WardScale.onScale(12.0) && !WardScale.onScale(10.0) && !WardScale.onScale(20.0))
        check("light: the base is a light grey", WardPalette.luminance(WardPalette.hex(WardToken.background, false)) > 0.7)
        // 0.010, not 0.015: the owner's #171C24 measures 0.0114, still far from black
        check("dark: the base is a dark grey, not black",
            WardPalette.luminance(WardPalette.hex(WardToken.background, true)) in 0.010..0.06)
    }

    private fun chroma(x: Int): Double {
        val o = oklab(x)
        return sqrt(o.a * o.a + o.b * o.b)
    }

    // A wrong answer is the faded row, in colours, never opacity: its ink
    // reads 4.5:1 on its face and on its inset row, with and without Increase
    // Contrast. Once checked, a wrong pick reads faded, never like the right
    // answer, and its ring reads 3:1 against the face, the cards and the base.
    @Test fun wrongAnswerIsFaded() = checks {
        for (dark in modes) {
            val m = mode(dark)
            val ink = WardPalette.hex(WardToken.fadedInk, dark)
            val face = WardPalette.hex(WardToken.faded, dark)
            val r = WardPalette.contrast(ink, face)
            check("$m: the faded ink reads 4.5:1 on the faded row", r >= 4.5, f2(r))
            for (hc in listOf(false, true)) {
                val ground = WardRelief.insetGround(face, WardLift.low, dark, hc, chipTextDepth)
                val c = WardPalette.contrast(ink, ground)
                check("$m${if (hc) " with Increase Contrast" else ""}: the faded ink reads 4.5:1 on its inset row", c >= 4.5, f2(c))
            }
        }
        val nightFace = WardPalette.hex(WardToken.faded, true)
        val nightCard = WardPalette.hex(WardToken.surface, true)
        check("night: the faded face is plainly lighter than the cards",
            WardPalette.luminance(nightFace) > WardPalette.luminance(nightCard) &&
                WardPalette.contrast(nightFace, nightCard) >= 1.4, f2(WardPalette.contrast(nightFace, nightCard)))
        check("night: the faded face is grey, greyer than the cards",
            chroma(nightFace) <= 0.015 && chroma(nightFace) < chroma(nightCard),
            String.format(java.util.Locale.ROOT, "%.4f", chroma(nightFace)))
        check("day: the faded face is as it was", WardPalette.hex(WardToken.faded, false) == 0xDDE2E8)
        for (dark in modes) {
            val face = WardPalette.hex(WardToken.faded, dark)
            for (hc in listOf(false, true)) {
                val ring = WardRelief.composite(WardReliefLight(WardPalette.hex(WardToken.fadedInk, dark),
                    WardRelief.edgeAlpha(dark, hc), 0.0, 0.0, 0.0), on = face)
                for (ground in listOf(WardToken.faded, WardToken.surface, WardToken.background)) {
                    val r = WardPalette.contrast(ring, WardPalette.hex(ground, dark))
                    check("${mode(dark)}${if (hc) " with Increase Contrast" else ""}: a wrong pick's ring reads 3:1 on the $ground",
                        r >= WardRelief.edgeContrast, f2(r))
                }
            }
        }
        for (p in WardPalette.monitorPromises) {
            val r = WardPalette.contrast(WardPalette.hex(p.text, true), WardPalette.hex(WardToken.monitor, true))
            check("monitor: ${p.text} at least ${p.ratio}", r >= p.ratio, f2(r))
        }
    }

    // the iOS asset catalogue agrees with the table (the test runs from the
    // module or the repository root, or anywhere under it)
    @Test fun iosAssetsAgreeWithTheTable() = checks {
        var root: File? = File(System.getProperty("user.dir")).absoluteFile
        while (root != null && !File(root, "ios/RedPen").exists()) root = root.parentFile
        val base = File(root ?: File("/"), "ios/RedPen/Assets.xcassets")
        val accent = File(base, "AccentColor.colorset/Contents.json")
        check("the AccentColor asset is found", accent.exists(), accent.path)
        fun components(appearance: String?, asset: File = accent): Int? {
            val json = runCatching { JSONObject(asset.readText()) }.getOrNull() ?: return null
            val colors = json.optJSONArray("colors") ?: return null
            for (i in 0 until colors.length()) {
                val entry = colors.getJSONObject(i)
                val appearances = entry.optJSONArray("appearances")
                val value = appearances?.optJSONObject(0)?.optString("value")
                if (value != appearance) continue
                val c = entry.optJSONObject("color")?.optJSONObject("components") ?: continue
                fun byte(k: String): Int? = c.optString(k, "").removePrefix("0x").removePrefix("0X").toIntOrNull(16)
                val r = byte("red") ?: return null
                val g = byte("green") ?: return null
                val b = byte("blue") ?: return null
                return (r shl 16) or (g shl 8) or b
            }
            return null
        }
        check("AccentColor (light) is the primary, Cards' Care Blue", components(null) == WardPalette.hex(WardToken.primary, false),
            Integer.toHexString(components(null) ?: 0))
        check("AccentColor (dark) is the night primary ink, Cards' Care Blue", components("dark") == WardPalette.hex(WardToken.primaryInk, true),
            Integer.toHexString(components("dark") ?: 0))
        val launch = File(base, "LaunchBackground.colorset/Contents.json")
        check("LaunchBackground (light) is the base", components(null, launch) == WardPalette.hex(WardToken.background, false),
            Integer.toHexString(components(null, launch) ?: 0))
        check("LaunchBackground (dark) is the base", components("dark", launch) == WardPalette.hex(WardToken.background, true),
            Integer.toHexString(components("dark", launch) ?: 0))
    }
}
