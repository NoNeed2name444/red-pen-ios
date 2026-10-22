package com.stethoscore.app.ui.ward

import org.junit.Assert.fail

/**
 * The iOS suites are scripts of labelled checks (`check(label, ok, detail)`);
 * this keeps their labels, so a failure here names the same case as there.
 * Every check in a test runs; the test fails at the end, listing each failure.
 */
class WardChecks {
    private val failures = mutableListOf<String>()
    var count = 0
        private set

    fun check(label: String, ok: Boolean, detail: String = "") {
        count += 1
        if (!ok) failures.add(if (detail.isEmpty()) label else "$label  | $detail")
    }

    fun done() {
        if (failures.isNotEmpty()) fail("${failures.size} of $count failed:\n" + failures.joinToString("\n"))
    }
}

fun checks(block: WardChecks.() -> Unit) {
    val c = WardChecks()
    c.block()
    c.done()
}

fun f3(x: Double): String = String.format(java.util.Locale.ROOT, "%.3f", x)
fun f2(x: Double): String = String.format(java.util.Locale.ROOT, "%.2f", x)
fun hx(x: Int): String = String.format(java.util.Locale.ROOT, "#%06X", x)

/** OKLab (Ottosson), as the iOS suites compute it. */
data class OkLab(val L: Double, val a: Double, val b: Double)

fun oklab(x: Int): OkLab {
    val c = WardPalette.rgb(x)
    val r = WardPalette.linear(c.r)
    val g = WardPalette.linear(c.g)
    val b = WardPalette.linear(c.b)
    val l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    val m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    val s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return OkLab(
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    )
}
