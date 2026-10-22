package com.stethoscore.app.ui.ward

import org.junit.Test
import java.io.File

// The motion in the app's screens, read from their sources (ui/**, but not
// ui/map, the Space map's own camera): every tween, spring and animated value
// names a Ward motion token (WardMotion in WardTokens.kt, WardPress for the
// press) rather than numbers of its own, and nothing loops but the working
// trace. The one pair of numbers kept is the score ring's slow spring, a
// celebration that waits on the owner (iOS Q8). The tokens themselves are
// checked in WardTokensTest.theMotion.
class WardMotionTest {

    @Test fun everyMotionNamesAToken() = checks {
        check("found the screens", WardScreens.sources.size > 50, "${WardScreens.sources.size}")
        val tweens = WardScreens.sites("tween").filter { s ->
            val time = s.args.substringBefore(",").trim()
            !(time.startsWith("wardMillis(") || time.contains("WardPress."))
        }
        check("every tween's time is a token (wardMillis of a WardMotion or WardPress time)", tweens.isEmpty(),
            tweens.joinToString { "${it.at} (${it.args})" })
        val springs = WardScreens.sites("spring").filter { s -> s.args.any { it.isDigit() } && !(s.args == Q8 && s.at.startsWith("mock/MockKit.kt:")) }
        check("no spring has numbers of its own (wardSpring: critically damped over a WardMotion time)", springs.isEmpty(),
            springs.joinToString { "${it.at} (${it.args})" })
        val kept = WardScreens.sites("spring").filter { it.args == Q8 }
        check("the score ring's slow spring is kept as it is, once (iOS Q8)", kept.size == 1 && kept[0].at.startsWith("mock/MockKit.kt:"),
            kept.joinToString { it.at })
        val material = WardScreens.lines(Regex("\\b(LinearEasing|FastOutSlowInEasing|LinearOutSlowInEasing|FastOutLinearInEasing|Spring\\.(DampingRatio|Stiffness)\\w*)\\b"))
        check("no Material curve or spring constant: iOS's ease-out and ease-in-out, WardMotion's springs", material.isEmpty(), material.joinToString())
        val unnamed = WardScreens.sites("animate[A-Za-z]*AsState|animateTo").filter { s ->
            listOf("wardEaseOut(", "wardSpring(", "WardPress.", "spring($Q8)").none { s.args.contains(it) }
        }
        check("every animated value and Animatable names its motion (wardEaseOut, wardSpring or WardPress)", unnamed.isEmpty(),
            unnamed.joinToString { it.at })
        val loops = WardScreens.sites("infiniteRepeatable")
        check("nothing loops but the working trace (EcgLoader, on WardMotion.trace)", loops.size == 1 &&
            loops[0].at.startsWith("editors/EditorKit.kt:") && loops[0].args.startsWith("tween(wardMillis(WardMotion.trace), easing = WardEaseInOut)"),
            loops.joinToString { "${it.at} (${it.args})" })
        check("nothing repeats a set number of times", WardScreens.sites("repeatable").isEmpty())
    }

    private companion object {
        /** iOS ScoreRing's spring (response 1.1, damping 0.72), kept as it is (iOS Q8). */
        const val Q8 = "dampingRatio = 0.72f, stiffness = 30f"
    }
}

/** The screens' sources (every file under ui/ but ui/map), and the calls in them. */
internal object WardScreens {
    private val root = File("src/main/java/com/stethoscore/app/ui")
    private val trailing = Regex("\\s//\\s")

    /** Each source by its path under ui/, its comment lines blank so a note never counts as code. */
    val sources: Map<String, String> by lazy {
        root.walkTopDown().filter { it.isFile && it.extension == "kt" }
            .map { it.relativeTo(root).invariantSeparatorsPath to it }
            .filter { (path, _) -> !path.startsWith("map/") }
            .associate { (path, file) -> path to file.readLines().joinToString("\n") { code(it) } }
    }

    /** A line without its comment: blank for a comment line, cut where a trailing one starts. */
    private fun code(line: String): String {
        val t = line.trimStart()
        if (t.startsWith("//") || t.startsWith("*") || t.startsWith("/*")) return ""
        val cut = trailing.find(line) ?: return line
        return line.substring(0, cut.range.first)
    }

    /** A call: where it is (path:line), what is between its brackets, and its line up to the call. */
    data class Site(val at: String, val args: String, val lead: String)

    /** Every call to a function whose whole name matches [name] (a regex). */
    fun sites(name: String): List<Site> {
        val re = Regex("(?<![A-Za-z0-9_])(?:$name)\\s*\\(")
        return sources.flatMap { (path, text) ->
            re.findAll(text).map { m ->
                val lineStart = text.lastIndexOf('\n', m.range.first) + 1
                Site("$path:${line(text, m.range.first)}", inside(text, m.range.last), text.substring(lineStart, m.range.first))
            }.toList()
        }
    }

    /** Every match of [re], as path:line. */
    fun lines(re: Regex): List<String> = sources.flatMap { (path, text) ->
        re.findAll(text).map { m -> "$path:${line(text, m.range.first)}" }.toList()
    }

    private fun line(text: String, at: Int): Int = text.substring(0, at).count { it == '\n' } + 1

    /** What lies between the bracket at [open] and its partner, brackets in quotes aside. */
    private fun inside(text: String, open: Int): String {
        var depth = 0
        var quoted = false
        for (i in open until text.length) {
            val c = text[i]
            if (c == '"' && text[i - 1] != '\\') quoted = !quoted
            if (quoted) continue
            if (c == '(') depth++
            if (c == ')') {
                depth--
                if (depth == 0) return text.substring(open + 1, i)
            }
        }
        return text.substring(open + 1)
    }
}
