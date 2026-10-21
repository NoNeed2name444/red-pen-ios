package com.stethoscore.app.ui.vitals

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.stethoscore.app.data.CalibrationRow
import com.stethoscore.app.data.HeatLevel
import com.stethoscore.app.data.ReasonShare
import com.stethoscore.app.data.RhythmReading
import com.stethoscore.app.quiz.AnswerConfidence
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.ward.WardWeight
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.wardColor
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.time.temporal.WeekFields
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

// A port of upstream/ios/RedPen/Features/Analytics/AnalyticsVisuals.swift
// (ProgressRing, Sparkline, ReasonDonut, CalibrationChart, StudyHeatmap) and
// of AnalyticsView's two trend charts. Swift Charts has no Android
// counterpart in the offline cache, so each chart is drawn on a Canvas with
// the same marks, scale and colours: Theatre Blue (the section's accent ink)
// at a few strengths, a hairline track, Biro Grey for the reference lines.
// Each reads to TalkBack as one sentence.

/** One day's accuracy on a sparkline. */
data class SparkPoint(val day: LocalDate, val accuracy: Double)

/** One week on the accuracy chart. */
data class WeekPoint(val start: LocalDate, val answered: Int, val accuracy: Double)

/** One day on the practice chart. */
data class DayPoint(val day: LocalDate, val count: Int)

/**
 * A circular progress bar (ProgressRing, the plain fill): a hairline track
 * with an arc in [tint] and a rounded end, sweeping in when it first shows.
 */
@Composable fun ProgressRing(value: Double, modifier: Modifier = Modifier, tint: Color = wardColor(WardToken.primaryInk),
                             size: Double = 64.0, lineWidth: Double = 7.0) {
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val grow by animateFloatAsState(if (shown) 1f else 0f, tween(900), label = "ring")
    val track = wardColor(WardToken.hairline)
    Canvas(modifier.size(size.dp)) {
        val w = lineWidth.dp.toPx()
        val inset = w / 2
        val arc = Size(this.size.width - w, this.size.height - w)
        drawArc(track, 0f, 360f, false, Offset(inset, inset), arc, style = Stroke(w))
        val filled = value.coerceIn(0.0, 1.0).toFloat() * grow
        if (filled > 0) drawArc(tint, -90f, 360f * filled, false, Offset(inset, inset), arc, style = Stroke(w, cap = StrokeCap.Round))
    }
}

/** A tiny line of accuracy day by day, with no axes: the shape, not the numbers. 90 by 20. */
@Composable fun Sparkline(points: List<SparkPoint>, tint: Color = wardColor(WardToken.primaryInk)) {
    val spoken = if (points.isEmpty()) "No recent answers"
    else "Last two weeks: from ${percentOf(points.first().accuracy)} to ${percentOf(points.last().accuracy)} percent right"
    Canvas(Modifier.size(90.dp, 20.dp).clearAndSetSemantics { contentDescription = spoken }) {
        if (points.size < 2) return@Canvas
        val first = points.first().day
        val span = max(1L, ChronoUnit.DAYS.between(first, points.last().day)).toFloat()
        val pad = 1.5.dp.toPx()
        val xy = points.map { p ->
            Offset(ChronoUnit.DAYS.between(first, p.day) / span * size.width,
                pad + (1f - p.accuracy.toFloat().coerceIn(0f, 1f)) * (size.height - 2 * pad))
        }
        drawPath(monotone(xy), tint, style = Stroke(1.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/**
 * A line through [points] that never overshoots between them (Swift
 * Charts' monotone interpolation, Fritsch-Carlson).
 */
internal fun monotone(points: List<Offset>): Path {
    val path = Path()
    if (points.isEmpty()) return path
    path.moveTo(points[0].x, points[0].y)
    if (points.size == 1) return path
    val n = points.size
    val d = FloatArray(n - 1) { i -> (points[i + 1].y - points[i].y) / max(1e-6f, points[i + 1].x - points[i].x) }
    val m = FloatArray(n) { i ->
        when (i) {
            0 -> d[0]
            n - 1 -> d[n - 2]
            else -> if (d[i - 1] * d[i] <= 0) 0f else (d[i - 1] + d[i]) / 2
        }
    }
    for (i in 0 until n - 1) {
        if (d[i] == 0f) { m[i] = 0f; m[i + 1] = 0f; continue }
        val a = m[i] / d[i]
        val b = m[i + 1] / d[i]
        val s = a * a + b * b
        if (s > 9) { val t = 3 / kotlin.math.sqrt(s); m[i] = t * a * d[i]; m[i + 1] = t * b * d[i] }
    }
    for (i in 0 until n - 1) {
        val p0 = points[i]
        val p1 = points[i + 1]
        val h = (p1.x - p0.x) / 3
        path.cubicTo(p0.x + h, p0.y + m[i] * h, p1.x - h, p1.y - m[i + 1] * h, p1.x, p1.y)
    }
    return path
}

/** The section's accent at a strength that steps down with each reason, commonest strongest. */
@Composable private fun donutShade(index: Int): Color =
    wardColor(WardToken.primaryInk).copy(alpha = max(0.25, 0.9 - index * 0.16).toFloat())

/** Why marks were lost, as a donut with a legend under it. */
@Composable fun ReasonDonut(shares: List<ReasonShare>) {
    val total = shares.sumOf { it.count }
    val shades = shares.indices.map { donutShade(it) }
    val spoken = "Why you lose marks: " + shares.joinToString(", ") { "${it.reason.title} ${percentOf(it.share)} percent" }
    Column(Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = spoken }, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.fillMaxWidth().height(150.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.size(150.dp)) {
                val outer = size.minDimension / 2
                val ring = outer * (1 - 0.62f)
                val inset = ring / 2
                var start = -90f
                val gap = 1.5f
                for ((i, share) in shares.withIndex()) {
                    val sweep = if (total == 0) 0f else 360f * share.count / total
                    val shown = max(0.5f, sweep - gap)
                    drawArc(shades[i], start + gap / 2, shown, false, Offset(inset, inset),
                        Size(size.width - ring, size.height - ring), style = Stroke(ring))
                    start += sweep
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("$total", style = WardTextStyle.title3.textStyle(WardWeight.bold, mono = true), color = wardColor(WardToken.ink))
                Text(if (total == 1) "reason" else "reasons", style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary))
            }
        }
        for ((i, share) in shares.withIndex()) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.size(12.dp).background(shades[i], RoundedCornerShape(3.dp)))
                Icon(reasonIcon(share.reason), null, tint = wardColor(WardToken.ink), modifier = Modifier.size(14.dp))
                Text(share.reason.title, Modifier.weight(1f), style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.ink))
                Text(percentText(share.share), style = WardTextStyle.caption.textStyle(mono = true), color = wardColor(WardToken.inkSecondary))
            }
        }
    }
}

/** Roughly where a well-calibrated student would sit, in percent. */
fun idealCalibration(confidence: AnswerConfidence): Double = when (confidence) {
    AnswerConfidence.sure -> 95.0
    AnswerConfidence.maybe -> 65.0
    AnswerConfidence.guess -> 25.0
}

/** Draws "0%", "50%" and "100%" at the right of a 0-100 plot, with their grid lines. */
private fun DrawScope.percentAxis(plot: Size, measurer: TextMeasurer, style: TextStyle, grid: Color) {
    for (v in listOf(0.0, 50.0, 100.0)) {
        val y = plot.height * (1 - v / 100).toFloat()
        drawLine(grid, Offset(0f, y), Offset(plot.width, y), 0.5.dp.toPx())
        val label = measurer.measure("${v.toInt()}%", style)
        drawText(label, topLeft = Offset(plot.width + 4.dp.toPx(), (y - label.size.height / 2f).coerceIn(0f, size.height - label.size.height)))
    }
}

/** How often each confidence level was right, against where it should be: "Sure" right nearly every time, "Guess" about at chance. */
@Composable fun CalibrationChart(rows: List<CalibrationRow>) {
    val measurer = rememberTextMeasurer()
    val axis = WardTextStyle.caption2.textStyle().copy(color = wardColor(WardToken.inkSecondary))
    val bar = wardColor(WardToken.primaryInk).copy(alpha = 0.7f)
    val ideal = wardColor(WardToken.inkSecondary)
    val grid = wardColor(WardToken.hairline)
    val spoken = "Accuracy by confidence. " + rows.joinToString(". ") {
        "${it.confidence.title}: ${percentOf(it.accuracy)} percent right, ideal about ${idealCalibration(it.confidence).toInt()}"
    }
    Canvas(Modifier.fillMaxWidth().height(150.dp).clearAndSetSemantics { contentDescription = spoken }) {
        val labelRoom = 16.dp.toPx()
        val axisRoom = 34.dp.toPx()
        val plot = Size(size.width - axisRoom, size.height - labelRoom)
        percentAxis(plot, measurer, axis, grid)
        if (rows.isEmpty()) return@Canvas
        val band = plot.width / rows.size
        val centres = rows.indices.map { band * (it + 0.5f) }
        rows.forEachIndexed { i, row ->
            val h = plot.height * row.accuracy.toFloat().coerceIn(0f, 1f)
            val w = band * 0.6f
            drawRoundRect(bar, Offset(centres[i] - w / 2, plot.height - h), Size(w, h), CornerRadius(4.dp.toPx()))
            val label = measurer.measure(row.confidence.title, axis)
            drawText(label, topLeft = Offset(centres[i] - label.size.width / 2f, plot.height + 2.dp.toPx()))
        }
        val points = rows.mapIndexed { i, row -> Offset(centres[i], plot.height * (1 - idealCalibration(row.confidence) / 100).toFloat()) }
        val line = Path().apply { points.forEachIndexed { i, p -> if (i == 0) moveTo(p.x, p.y) else lineTo(p.x, p.y) } }
        drawPath(line, ideal, style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))))
        points.forEach { drawCircle(ideal, 2.5.dp.toPx(), it) }
    }
}

/** Accuracy week by week over the last eight, with the typical pass mark as a dashed line. 150 tall. */
@Composable fun WeeklyChart(weeks: List<WeekPoint>, passMark: Double) {
    val measurer = rememberTextMeasurer()
    val axis = WardTextStyle.caption2.textStyle().copy(color = wardColor(WardToken.inkSecondary))
    val ink = wardColor(WardToken.primaryInk)
    val rule = wardColor(WardToken.inkSecondary)
    val grid = wardColor(WardToken.hairline)
    val format = DateTimeFormatter.ofPattern("d MMM", Locale.getDefault())
    val spoken = "Accuracy by week. " + weeks.joinToString(". ") { "Week of ${it.start.format(format)}: ${percentOf(it.accuracy)} percent" } +
        ". Pass mark about ${passMark.toInt()} percent"
    Canvas(Modifier.fillMaxWidth().height(150.dp).clearAndSetSemantics { contentDescription = spoken }) {
        val labelRoom = 16.dp.toPx()
        val axisRoom = 34.dp.toPx()
        val plot = Size(size.width - axisRoom, size.height - labelRoom)
        percentAxis(plot, measurer, axis, grid)
        if (weeks.isEmpty()) return@Canvas
        val first = weeks.first().start
        val days = max(1L, ChronoUnit.DAYS.between(first, weeks.last().start)).toFloat()
        val edge = 10.dp.toPx()
        fun x(d: LocalDate): Float = if (weeks.size == 1) plot.width / 2 else edge + ChronoUnit.DAYS.between(first, d) / days * (plot.width - 2 * edge)
        val points = weeks.map { Offset(x(it.start), plot.height * (1 - it.accuracy.toFloat().coerceIn(0f, 1f))) }
        drawPath(monotone(points), ink, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
        points.forEach { drawCircle(ink, 3.dp.toPx(), it) }
        val passY = plot.height * (1 - passMark / 100).toFloat()
        drawLine(rule, Offset(0f, passY), Offset(plot.width, passY), 1.dp.toPx(),
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx())))
        // the dates along the bottom: the first and the last week, and one between on a wide chart
        val labelled = if (weeks.size <= 2) weeks else listOf(weeks.first(), weeks[weeks.size / 2], weeks.last())
        labelled.distinct().forEach { w ->
            val label = measurer.measure(w.start.format(format), axis)
            val left = (x(w.start) - label.size.width / 2f).coerceIn(0f, plot.width - label.size.width)
            drawText(label, topLeft = Offset(left, plot.height + 2.dp.toPx()))
        }
    }
}

/** A step for an axis that gives three or four labels up to [top]. */
internal fun niceStep(top: Int): Int {
    if (top <= 4) return 1
    val raw = top / 3.0
    val magnitude = Math.pow(10.0, kotlin.math.floor(kotlin.math.log10(raw)))
    val step = listOf(1.0, 2.0, 5.0, 10.0).first { it * magnitude >= raw } * magnitude
    return max(1, step.toInt())
}

/** Studied per day over the last 30, as bars. 120 tall. */
@Composable fun DailyChart(days: List<DayPoint>) {
    val measurer = rememberTextMeasurer()
    val axis = WardTextStyle.caption2.textStyle().copy(color = wardColor(WardToken.inkSecondary))
    val bar = wardColor(WardToken.primaryInk).copy(alpha = 0.7f)
    val grid = wardColor(WardToken.hairline)
    val format = DateTimeFormatter.ofPattern("d MMM", Locale.getDefault())
    val busiest = days.maxOfOrNull { it.count } ?: 0
    val total = days.sumOf { it.count }
    val spoken = "Studied per day, last ${days.size} days: $total in all, at most $busiest in a day"
    Canvas(Modifier.fillMaxWidth().height(120.dp).clearAndSetSemantics { contentDescription = spoken }) {
        val labelRoom = 16.dp.toPx()
        val axisRoom = 34.dp.toPx()
        val plot = Size(size.width - axisRoom, size.height - labelRoom)
        val step = niceStep(max(1, busiest))
        val top = max(step, ceil(max(1, busiest) / step.toDouble()).toInt() * step)
        var tick = 0
        while (tick <= top) {
            val y = plot.height * (1 - tick / top.toFloat())
            drawLine(grid, Offset(0f, y), Offset(plot.width, y), 0.5.dp.toPx())
            val label = measurer.measure("$tick", axis)
            drawText(label, topLeft = Offset(plot.width + 4.dp.toPx(), (y - label.size.height / 2f).coerceIn(0f, size.height - label.size.height)))
            tick += step
        }
        if (days.isEmpty()) return@Canvas
        val band = plot.width / days.size
        days.forEachIndexed { i, d ->
            if (d.count <= 0) return@forEachIndexed
            val h = plot.height * d.count / top.toFloat()
            drawRect(bar, Offset(band * i + band * 0.12f, plot.height - h), Size(band * 0.76f, h))
        }
        // a date under every seventh day, from the oldest
        for (i in days.indices step 7) {
            val label = measurer.measure(days[i].day.format(format), axis)
            val left = (band * i).coerceIn(0f, plot.width - label.size.width)
            drawText(label, topLeft = Offset(left, plot.height + 2.dp.toPx()))
        }
    }
}

/**
 * Twelve weeks of study as a calendar grid, a column a week from the
 * reader's first weekday, shaded by how much was done each day (HeatLevel),
 * today outlined and a small moon on each rest day that kept the streak.
 * TalkBack hears a summary, then each week in turn.
 */
@Composable fun StudyHeatmap(counts: Map<String, Int>, restDays: Set<String> = emptySet(), weeks: Int = 12,
                             today: LocalDate = LocalDate.now()) {
    class Cell(val date: LocalDate, val key: String, val count: Int, val isToday: Boolean, val isFuture: Boolean)
    val firstDay = WeekFields.of(Locale.getDefault()).firstDayOfWeek
    val thisWeek = today.minusDays(((today.dayOfWeek.value - firstDay.value + 7) % 7).toLong())
    val first = thisWeek.minusDays(7L * (weeks - 1))
    val grid = (0 until weeks).map { column ->
        (0 until 7).map { row ->
            val date = first.plusDays((column * 7 + row).toLong())
            val key = RhythmReading.key(date)
            Cell(date, key, counts[key] ?: 0, date == today, date.isAfter(today))
        }
    }
    val cells = grid.flatten().filter { !it.isFuture }
    val busiest = cells.maxOfOrNull { it.count } ?: 0
    val studied = cells.count { it.count > 0 }
    val rested = cells.count { it.key in restDays }
    val summary = "Study calendar, last $weeks weeks: something studied on ${counted(studied, "day")}, at most $busiest in a day." +
        if (rested > 0) " $rested rest day${if (rested == 1) "" else "s"} kept the streak." else ""
    val weekFormat = DateTimeFormatter.ofPattern("d MMMM", Locale.getDefault())
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.widthIn(max = 320.dp).fillMaxWidth().clearAndSetSemantics { contentDescription = summary },
            horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            for (column in grid) {
                val past = column.filter { !it.isFuture }
                val days = past.count { it.count > 0 }
                val most = past.maxOfOrNull { it.count } ?: 0
                val spokenWeek = "Week of ${column.first().date.format(weekFormat)}: ${counted(days, "day")} studied" +
                    if (most > 0) ", most $most in a day" else ""
                Column(Modifier.weight(1f).clearAndSetSemantics { contentDescription = spokenWeek }, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    for (cell in column) HeatSquare(HeatLevel.of(cell.count, busiest), cell.isFuture, cell.isToday, cell.key in restDays,
                        Modifier.fillMaxWidth())
                }
            }
        }
        Row(Modifier.clearAndSetSemantics {}, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Less", style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary))
            for (level in HeatLevel.entries) HeatSquare(level, future = false, today = false, rest = false, modifier = Modifier.size(12.dp))
            Text("More", style = WardTextStyle.caption2.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
    }
}

/** "1 day", "4 days" (SpokenText.count). */
internal fun counted(n: Int, noun: String): String = "$n " + if (n == 1) noun else noun + "s"

/** One day's square: its shade, today's outline, and a rest day's moon. */
@Composable private fun HeatSquare(level: HeatLevel, future: Boolean, today: Boolean, rest: Boolean, modifier: Modifier) {
    val shape = RoundedCornerShape(3.dp)
    val fill = when {
        future -> Color.Transparent
        level == HeatLevel.none -> wardColor(WardToken.hairline)
        else -> wardColor(WardToken.primaryInk).copy(alpha = (0.25 + 0.7 * level.strength).toFloat())
    }
    Box(modifier.aspectRatio(1f).background(fill, shape)
        .then(if (today) Modifier.border(1.5.dp, wardColor(WardToken.ink), shape) else Modifier),
        contentAlignment = Alignment.Center) {
        if (rest) Icon(Icons.Rounded.Bedtime, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(7.dp))
    }
}

/** Keeps a Spacer import honest for callers laying out under a chart. */
@Composable internal fun ChartGap() = Spacer(Modifier.height(4.dp))

/** The smaller of two, for the layout maths. */
internal fun lesser(a: Float, b: Float): Float = min(a, b)
