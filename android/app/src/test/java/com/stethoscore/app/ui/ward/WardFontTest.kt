package com.stethoscore.app.ui.ward

import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontListFontFamily
import androidx.compose.ui.text.font.ResourceFont
import com.stethoscore.app.R
import com.stethoscore.app.reading.ContentSources
import org.junit.Test
import java.io.File
import java.util.Locale

// The app's type (owner D5): Nunito, and Baloo Bhaijaan 2 in Arabic, bundled
// in res/font, every face of WardType in it, observations still in the
// system mono, and each font the same file iOS bundles, with its licence
// shipped beside it. What this cannot show on Linux: the font drawn on a
// device (that the wght of each weight is honoured, and the sp scaling at a
// large font size), which the emulator shots do.
@OptIn(ExperimentalTextApi::class)
class WardFontTest {

    private fun root(): File {
        var dir: File? = File("").absoluteFile
        while (dir != null && !File(dir, "ios/RedPen").exists()) dir = dir.parentFile
        return requireNotNull(dir) { "the repository root, with ios/RedPen" }
    }

    /** The family name a font file carries: the typographic family (name 16) if it has one, else name 1. */
    private fun familyName(file: File): String {
        val b = file.readBytes()
        fun u16(at: Int) = ((b[at].toInt() and 0xFF) shl 8) or (b[at + 1].toInt() and 0xFF)
        fun u32(at: Int) = (u16(at).toLong() shl 16) or u16(at + 2).toLong()
        val tables = u16(4)
        val name = (0 until tables).map { 12 + it * 16 }.firstOrNull { String(b, it, 4, Charsets.US_ASCII) == "name" } ?: return ""
        val at = u32(name + 8).toInt()
        val count = u16(at + 2)
        val strings = at + u16(at + 4)
        val found = mutableMapOf<Int, String>()
        for (i in 0 until count) {
            val r = at + 6 + i * 12
            val platform = u16(r); val language = u16(r + 4); val id = u16(r + 6)
            if (platform != 3 || language != 0x409 || (id != 1 && id != 16)) continue
            found[id] = String(b, strings + u16(r + 10), u16(r + 8), Charsets.UTF_16BE)
        }
        return found[16] ?: found[1] ?: ""
    }

    private fun weights(family: FontFamily): List<Pair<Int, Float?>> =
        (family as FontListFontFamily).fonts.map { font ->
            val res = font as ResourceFont
            res.weight.weight to res.variationSettings.settings.firstOrNull { it.axisName == "wght" }?.toVariationValue(null)
        }

    @Test fun theFamiliesAreTheBundledFonts() = checks {
        val latin = (WardFont.latin as FontListFontFamily).fonts.map { (it as ResourceFont).resId }.toSet()
        val arabic = (WardFont.arabic as FontListFontFamily).fonts.map { (it as ResourceFont).resId }.toSet()
        check("Nunito is res/font/nunito", latin == setOf(R.font.nunito))
        check("Baloo Bhaijaan 2 is res/font/baloo_bhaijaan_2", arabic == setOf(R.font.baloo_bhaijaan_2))
        check("each Nunito weight is the variable font at that wght",
            weights(WardFont.latin) == WardFont.latinWeights.map { it to it.toFloat() })
        check("each Baloo Bhaijaan 2 weight is the variable font at that wght, 400 to 800",
            weights(WardFont.arabic) == WardFont.arabicWeights.map { it to it.toFloat() })
        check("every Ward weight has its own instance in both",
            WardWeight.entries.all { it.value in WardFont.latinWeights && it.value in WardFont.arabicWeights })
    }

    @Test fun everyFaceIsInTheAppsFontAndObservationsStayMono() = checks {
        val was = Locale.getDefault()
        try {
            Locale.setDefault(Locale.ENGLISH)
            check("English is Nunito", WardFont.current == WardFont.latin)
            for (face in listOf(WardType.display, WardType.title, WardType.headline, WardType.body, WardType.caption,
                WardType.buttonPrimary, WardType.button, WardType.chip, WardType.smallCaps)) {
                check("$face is Nunito", face.textStyle().fontFamily == WardFont.latin)
            }
            val typography = wardTypography()
            check("Material's roles are Nunito, so a Text with no family of its own is",
                listOf(typography.bodyLarge, typography.titleLarge, typography.labelLarge, typography.displayLarge)
                    .all { it.fontFamily == WardFont.latin })
            check("observations stay in the system mono",
                WardType.obs.textStyle().fontFamily == FontFamily.Monospace &&
                    WardType.obsLarge.textStyle().fontFamily == FontFamily.Monospace &&
                    WardType.timer.textStyle().fontFamily == FontFamily.Monospace)
            check("the sizes are untouched: body 17 sp on 22", WardType.body.textStyle().fontSize.value == 17f &&
                WardType.body.textStyle().lineHeight.value == 22f)
            Locale.setDefault(Locale.forLanguageTag("ar"))
            check("Arabic is Baloo Bhaijaan 2", WardFont.current == WardFont.arabic &&
                WardType.body.textStyle().fontFamily == WardFont.arabic)
            check("Arabic observations stay mono", WardType.obs.textStyle().fontFamily == FontFamily.Monospace)
        } finally {
            Locale.setDefault(was)
        }
    }

    @Test fun theFilesAreIOSsWithTheirLicences() = checks {
        val root = root()
        val pairs = listOf(
            Triple("nunito.ttf", "Nunito-Variable.ttf", "Nunito"),
            Triple("baloo_bhaijaan_2.ttf", "BalooBhaijaan2-Variable.ttf", "Baloo Bhaijaan 2"))
        for ((android, ios, family) in pairs) {
            val mine = File(root, "android/app/src/main/res/font/$android")
            val theirs = File(root, "ios/RedPen/Resources/Fonts/$ios")
            check("$android is bundled", mine.exists())
            check("$android is the same file as iOS's $ios", mine.exists() && theirs.exists() && mine.readBytes().contentEquals(theirs.readBytes()))
            check("$android's family is $family", mine.exists() && familyName(mine) == family)
        }
        for (licence in listOf("Nunito-OFL.txt", "BalooBhaijaan2-OFL.txt")) {
            val shipped = File(root, "android/app/src/main/assets/licenses/$licence")
            val ios = File(root, "ios/RedPen/Resources/Fonts/$licence")
            check("$licence ships in the app's assets", shipped.exists() && shipped.readText().contains("SIL Open Font License, Version 1.1"))
            check("$licence is iOS's", shipped.exists() && ios.exists() && shipped.readText() == ios.readText())
        }
        check("the fonts are in Settings' credits under the OFL",
            ContentSources.fonts in ContentSources.all && ContentSources.fonts.licences == listOf(ContentSources.ofl))
    }
}
