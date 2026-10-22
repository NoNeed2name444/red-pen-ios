package com.stethoscore.app.ui.ward

import org.junit.Test
import java.io.File
import kotlin.math.sqrt

// A port of the dock's checks in ios/RedPen/Tests/WardStatesTests.swift
// (MARK: The dock's chosen tab: concentric with the panel, its name inside),
// same cases and numbers. The owner, 21 Oct: "the corner of the part doesn't
// match the corner around it". The chosen tab's ring is concentric with the
// dock's panel (its radius the panel's less the inset between them), and its
// name sits wholly inside the ring at every text size the dock is drawn at.
// iOS draws continuous corners and Android circular ones: both are checked.
class WardDockTest {

    private fun f(x: Double) = f2(x)
    private fun distance(a: WardDock.Point, b: WardDock.Point): Double {
        val dx = a.x - b.x
        val dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
    private fun gaps(points: List<WardDock.Point>, outer: List<WardDock.Point>): Pair<Double, Double> {
        val d = points.map { p -> outer.minOf { q -> distance(p, q) } }
        return (d.minOrNull() ?: 0.0) to (d.maxOrNull() ?: 0.0)
    }
    private val tabs = listOf(Triple("bar", WardDock.barInset, WardDock.barTabRadius), Triple("rail", WardDock.railInset, WardDock.railTabRadius))

    @Test fun concentric() = checks {
        check("the dock's panel is WardRadius.bar's 24 points", WardDock.panelRadius == WardScale.xl && WardDock.panelRadius == 24.0)
        check("the chosen ring is 2 points (chosenEdgeWidth), wider than a control's 1-point edge", WardDock.ringWidth == 2.0)
        check("the bar's inset is 4 and the rail's 5, so the tab is 20 and 19",
            WardDock.barInset == 4.0 && WardDock.railInset == 5.0 && WardDock.barTabRadius == 20.0 && WardDock.railTabRadius == 19.0)
        for ((name, inset, tab) in tabs) {
            check("$name: the tab's radius is the panel's less the inset (${f(WardDock.panelRadius)} - ${f(inset)})",
                tab == WardDock.panelRadius - inset && WardDock.tabRadius(inset) == tab && tab > WardDock.ringWidth, f(tab))
            // continuous corners (iOS): parallel within a tenth of the inset
            val outer = WardDock.cornerPoints(WardDock.panelRadius, steps = 120)
            val inner = WardDock.cornerPoints(tab, steps = 120).map { WardDock.Point(it.x + inset, it.y + inset) }
            val (lo, hi) = gaps(inner, outer)
            check("$name: the tab's corner runs parallel to the panel's, ${f(inset)} apart", lo >= inset * 0.9 && hi <= inset * 1.0001, "${f(lo)}...${f(hi)}")
            val (oldLo, _) = gaps(WardDock.cornerPoints(16.0, steps = 120).map { WardDock.Point(it.x + inset, it.y + inset) }, outer)
            check("$name: the old 16-point tab was not parallel (the check bites)", oldLo < inset * 0.9, f(oldLo))
            // circular corners (what Compose draws): exactly the inset apart
            val outerCircle = WardDock.circlePoints(WardDock.panelRadius)
            val innerCircle = WardDock.circlePoints(tab).map { WardDock.Point(it.x + inset, it.y + inset) }
            val (clo, chi) = gaps(innerCircle, outerCircle)
            check("$name, circular: the tab's corner runs parallel to the panel's, ${f(inset)} apart",
                clo >= inset * 0.99 && chi <= inset * 1.0001, "${f(clo)}...${f(chi)}")
            val (oldCircle, _) = gaps(WardDock.circlePoints(16.0).map { WardDock.Point(it.x + inset, it.y + inset) }, outerCircle)
            check("$name, circular: the old 16-point tab was not parallel (the check bites)", oldCircle < inset * 0.9, f(oldCircle))
        }
    }

    @Test fun theNameFits() = checks {
        // caption2 bold, from the smallest text size to xxxLarge: (point, line)
        val caption2 = listOf(11.0 to 13.0, 11.0 to 13.0, 11.0 to 13.0, 11.0 to 13.0, 13.0 to 16.0, 15.0 to 18.0, 17.0 to 20.0)
        val symbolLine = listOf(24.0, 24.0, 24.0, 24.0, 26.0, 28.0, 31.0)
        for ((size, pl) in caption2.withIndex()) {
            val (point, line) = pl
            // the widest name, "Questions", at about 0.6 em a letter
            val width = point * 0.6 * 9
            val content = symbolLine[size] + 3 + line
            val height = maxOf(WardDock.tabMinHeight, content + 2 * WardDock.labelVertical)
            val below = (height - content) / 2
            for ((name, _, radius) in tabs) {
                check("$name, text size $size: the chosen name sits inside its ring, ${f(WardDock.labelClearance)} clear",
                    below >= WardDock.labelVertical &&
                        WardDock.labelFits(width, below, width + 2 * WardDock.labelSide, radius), "below ${f(below)}")
                check("$name, circular, text size $size: the chosen name sits inside its ring, ${f(WardDock.labelClearance)} clear",
                    WardDock.labelFitsCircle(width, below, width + 2 * WardDock.labelSide, radius), "below ${f(below)}")
            }
        }
        check("a name's room keeps it clear of the ring at its smallest (labelVertical under it)",
            WardDock.labelFits(60.0, WardDock.labelVertical, 60 + 2 * WardDock.labelSide, WardDock.barTabRadius) &&
                WardDock.labelFits(60.0, WardDock.labelVertical, 60 + 2 * WardDock.labelSide, WardDock.railTabRadius) &&
                WardDock.labelFitsCircle(60.0, WardDock.labelVertical, 60 + 2 * WardDock.labelSide, WardDock.barTabRadius) &&
                WardDock.labelFitsCircle(60.0, WardDock.labelVertical, 60 + 2 * WardDock.labelSide, WardDock.railTabRadius))
        check("the old room (4 at the sides, 2 below at large text) crossed the ring's corner (the check bites)",
            !WardDock.labelFits(60.0, 2.0, 60.0 + 8, 16.0) && !WardDock.labelFits(60.0, 8.0, 60.0 + 8, 16.0) &&
                !WardDock.labelFitsCircle(60.0, 2.0, 60.0 + 8, 16.0))
        // a continuous corner of radius 20 meets its diagonal about 0.323 radii in from each edge
        check("a continuous corner: clear past its reach, cut off across its diagonal",
            WardDock.inside(1.6 * 20, 0.5, 20.0, 0.4) && !WardDock.inside(6.0, 6.0, 20.0, 0.0) &&
                WardDock.inside(7.2, 7.2, 20.0, 0.4) && !WardDock.inside(6.6, 6.6, 20.0, 0.4) &&
                WardDock.inside(20.0, 20.0, 20.0, 1.0))
        // a circle of radius 20 meets its diagonal 0.293 radii (5.86) in
        check("a circular corner: clear past its radius, cut off across its diagonal",
            WardDock.insideCircle(20.5, 0.5, 20.0, 0.4) && !WardDock.insideCircle(5.5, 5.5, 20.0, 0.0) &&
                WardDock.insideCircle(6.5, 6.5, 20.0, 0.4) && !WardDock.insideCircle(5.9, 5.9, 20.0, 0.4) &&
                WardDock.insideCircle(20.0, 20.0, 20.0, 1.0))
    }

    // The dock draws with these numbers (the source, read from the module's directory).
    @Test fun theDockDrawsWithThem() = checks {
        val app = File("src/main/java/com/stethoscore/app/ui/StethoscoreApp.kt").takeIf { it.exists() }?.readText() ?: ""
        val start = app.indexOf("@Composable fun CategoryDock")
        val dock = if (start >= 0) app.substring(start) else ""
        check("found the dock's source", dock.isNotEmpty())
        check("home draws the dock, not Material's NavigationBar", app.contains("CategoryDock(category,") && !app.contains("NavigationBar("))
        check("the panel is WardDock's radius", dock.contains("val panel=RoundedCornerShape(WardDock.panelRadius.toFloat().dp)"))
        // iOS (StudyCategory.swift): the panel raised high on its rim, the chosen
        // tab in a low hollow with the chosen edge (WardDock.ringWidth is
        // WardControlStates.chosenEdgeWidth, the width wardChosenEdge draws)
        check("the ring is the chosen edge's width", WardDock.ringWidth == WardControlStates.chosenEdgeWidth)
        check("the chosen tab is the panel's radius less the inset, in a hollow with the chosen edge",
            dock.contains("val inset=WardDock.barInset") && dock.contains("val tab=RoundedCornerShape(WardDock.tabRadius(inset).toFloat().dp)") &&
                dock.contains("Box(Modifier.wardChosenEdge(tab,true).wardInset(tab,WardLift.low))"))
        // iOS StudyCategory.swift:748: one hollow travels with the choice (.snappy(duration: 0.3)), at once under
        // Reduce Motion; a held tab that is not chosen sinks into a hollow of its own (WardItemButtonStyle)
        check("one hollow travels between the tabs, never one per tab shown and hidden",
            dock.contains("WardDock.hollow(") && !dock.contains(".wardChosenEdge(tab,selected)") &&
                dock.contains("if(held && !selected) Modifier.wardInset(tab,WardLift.low)"))
        check("it travels on the travel token, and with animations off or back from Ideas it is simply there",
            dock.contains("wardSpring(com.stethoscore.app.ui.ward.WardMotion.travel,reduce)") &&
                dock.contains("if(reduce || from<0) hollow.snapTo(") && dock.contains("val reduce=com.stethoscore.app.ui.ward.wardReduceMotion()"))
        check("only the dock's layout reads where the hollow is, never the bar's sizing",
            dock.contains("override fun androidx.compose.ui.layout.IntrinsicMeasureScope.minIntrinsicHeight") &&
                dock.contains("hollowAt={ if(at<0) null"))
        check("the panel is raised high on its rim, as iOS", dock.contains(".wardRaised(WardDock.panelRadius,WardLift.high,control=true)"))
        check("no flat panel, border, Material colours or ripple",
            !dock.contains(".border(") && !dock.contains("colorScheme") && dock.contains("indication=null") && !dock.contains(".clip("))
        check("the bar as iOS's: the five on the panel, Ideas on its own pill, at most barMaxWidth wide",
            dock.contains("Row(Modifier.widthIn(max=WardDock.barMaxWidth.toFloat().dp)") &&
                dock.contains("horizontalArrangement=Arrangement.spacedBy(WardDock.barSpacing.toFloat().dp)") &&
                dock.contains("padding(horizontal=WardDock.barSide.toFloat().dp)") &&
                dock.contains("Column(Modifier.width(WardDock.ideasWidth.toFloat().dp)") &&
                !dock.contains("\"Audio\" to Icons.Outlined.GraphicEq,\"Ideas\""))
        check("the slots are WardDock's, and the names shrink alike to WardDock's least",
            dock.contains("WardDock.tabWidths(ideals,room)") && dock.contains("maxOf(WardDock.leastTab,") &&
                dock.contains("minFontSize=(11*WardDock.leastNameScale).sp"))
        check("outline glyphs at rest", dock.contains("Icons.Outlined.FactCheck") && !dock.contains("\"Questions\" to Icons.Rounded"))
        check("the inset is WardDock's", dock.contains(".padding(WardDock.barInset.toFloat().dp)"))
        check("every tab keeps its name's room and least height",
            dock.contains(".heightIn(min=WardDock.tabMinHeight.toFloat().dp)") &&
                dock.contains(".padding(horizontal=WardDock.labelSide.toFloat().dp,vertical=WardDock.labelVertical.toFloat().dp)"))
        check("a name too long for its slot gets smaller, on one line, rather than crossing the ring",
            dock.contains("maxLines=1,softWrap=false") && dock.contains("autoSize="))
    }

    // iOS WardStatesTests (T0112): short of room every name shrinks alike and
    // every tab keeps its side room; with room to spare the narrower tabs
    // share it equally.
    @Test fun theRowFitsAsIOSDoes() = checks {
        check("short of room, the names shrink alike", WardDock.tabWidths(listOf(80.0, 40.0, 40.0), 110.0) == listOf(50.0, 30.0, 30.0) &&
            WardDock.nameScale(listOf(80.0, 40.0, 40.0), 110.0) == 0.5)
        check("with room to spare, the narrower tabs share it", WardDock.tabWidths(listOf(80.0, 40.0, 40.0), 200.0) == listOf(80.0, 60.0, 60.0) &&
            WardDock.nameScale(listOf(80.0, 40.0, 40.0), 200.0) == 1.0)
        check("the bar's numbers are iOS's", WardDock.barSide == 10.0 && WardDock.ideasWidth == 56.0 && WardDock.barSpacing == 6.0 &&
            WardDock.barMaxWidth == 560.0 && WardDock.leastTab == 44.0 && WardDock.leastNameScale == 0.5)
    }

    // The one hollow the choice moves (iOS matchedGeometryEffect): on a tab
    // it is that tab; between two its place and width are taken that far
    // from one to the next; it never leaves the row.
    @Test fun theHollowTravels() = checks {
        val widths = listOf(60.0, 80.0, 50.0)
        check("on a tab it is that tab", WardDock.hollow(widths, 0.0) == WardDock.Span(0.0, 60.0) &&
            WardDock.hollow(widths, 1.0) == WardDock.Span(60.0, 80.0) && WardDock.hollow(widths, 2.0) == WardDock.Span(140.0, 50.0))
        val half = WardDock.hollow(widths, 0.5)
        check("half way from the first to the second, half way in place and in width",
            kotlin.math.abs(half.left - 30.0) < 1e-9 && kotlin.math.abs(half.width - 70.0) < 1e-9, "$half")
        val quarter = WardDock.hollow(widths, 1.25)
        check("a quarter of the way from the second to the third",
            kotlin.math.abs(quarter.left - 80.0) < 1e-9 && kotlin.math.abs(quarter.width - 72.5) < 1e-9, "$quarter")
        check("it never leaves the first or the last tab",
            WardDock.hollow(widths, -0.3) == WardDock.Span(0.0, 60.0) && WardDock.hollow(widths, 2.4) == WardDock.Span(140.0, 50.0))
        val total = widths.sum()
        check("all the way along it stays on the row, its two edges moving one way",
            (0..200).map { WardDock.hollow(widths, it / 100.0) }.let { spans ->
                spans.all { it.left >= 0 && it.left + it.width <= total + 1e-9 } &&
                    spans.zipWithNext().all { (a, b) -> b.left >= a.left - 1e-9 && b.left + b.width >= a.left + a.width - 1e-9 }
            })
        check("no tabs, no hollow", WardDock.hollow(emptyList(), 1.0) == WardDock.Span(0.0, 0.0))
    }
}
