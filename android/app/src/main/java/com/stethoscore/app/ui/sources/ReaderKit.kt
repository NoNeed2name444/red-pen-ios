package com.stethoscore.app.ui.sources

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.Article
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.Notes
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.Slideshow
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.stethoscore.app.reading.SourceKind
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.*

// The pieces the textbook reader and the lecture reader share, each a port of
// the iOS part it names, built from the Ward port (wardRaised, wardInset,
// wardRelief, WardButtonBox, WardIconSquare, the type and the tokens): the
// study header (StudyProgressHeader, ThinProgress), the bottom deck
// (StudyActionBar), the etched groove (WardEtch), a tiled row (WardRowTile,
// WardRow), a form section and the navigation bar's title with its Back or
// Done. The empty state is the Ward kit's (ui/ward/WardStates.kt).

/** iOS WindowSpan.broad: 700 points and wider, where two columns stop being a squeeze. */
internal fun isBroad(width: Dp): Boolean = width >= 700.dp

/** A lecture kind's symbol (SourceDoc.Kind.symbol). */
internal fun kindIcon(kind: SourceKind): ImageVector = when (kind) {
    SourceKind.pdf -> Icons.AutoMirrored.Rounded.Article        // doc.richtext
    SourceKind.word -> Icons.Rounded.Description                // doc.text
    SourceKind.powerpoint -> Icons.Rounded.Slideshow            // rectangle.on.rectangle
    SourceKind.text -> Icons.AutoMirrored.Rounded.Notes         // text.alignleft
}

/** A set's picture as stored (base64, with or without the web app's data: prefix). */
internal fun decodePicture(stored: String): ImageBitmap? = runCatching {
    if (stored.startsWith("blob:")) null else {
        val bytes = Base64.decode(stored.substringAfter("base64,", stored), Base64.DEFAULT)
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
    }
}.getOrNull()

/** The navigation bar: its title inline, Back or Done at the leading end, an action at the trailing one. */
@Composable internal fun ReaderNavBar(
    title: String,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    Box(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = WardSpace.s.wardDp)) {
        Row(Modifier.align(Alignment.CenterStart)) { leading?.invoke() }
        Text(title, Modifier.align(Alignment.Center).padding(horizontal = 96.dp).semantics { heading() },
            style = WardType.headline.textStyle(), color = wardColor(WardToken.ink), textAlign = TextAlign.Center,
            maxLines = 1, overflow = TextOverflow.Ellipsis)
        Row(Modifier.align(Alignment.CenterEnd)) { trailing?.invoke() }
    }
}

/** Back, to the page before. */
@Composable internal fun ReaderBackButton(onBack: () -> Unit) {
    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Back", tint = wardColor(WardToken.primaryInk)) }
}

/** A sheet's Done (wardCompact). */
@Composable internal fun ReaderDoneButton(title: String = "Done", onClick: () -> Unit) {
    WardTextButton(title, onClick, kind = WardButtonKind.compact, fills = false)
}

/**
 * The top of a study screen (StudyProgressHeader): where you are, a quieter
 * second fact, and the same as a length, on a thin slab raised low.
 */
@Composable internal fun StudyProgressHeader(status: String, detail: String? = null, fraction: Double? = null) {
    Box(Modifier.fillMaxWidth().padding(horizontal = WardSpace.m.wardDp).padding(top = WardSpace.s.wardDp), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = 700.dp).fillMaxWidth().wardRaised(WardRadius.bar, WardLift.low)
            .padding(horizontal = WardSpace.l.wardDp, vertical = WardSpace.m.wardDp),
            verticalArrangement = Arrangement.spacedBy(WardSpace.s.wardDp)) {
            Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(WardSpace.xs.wardDp)) {
                Text(status, style = WardType.headline.textStyle(), color = wardColor(WardToken.ink))
                if (detail != null) Text(detail, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary),
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            if (fraction != null) ThinProgress(fraction)
        }
    }
}

/** A thin progress bar (ThinProgress): a beam in a groove pressed into the base, filling from the leading edge. */
@Composable internal fun ThinProgress(fraction: Double) {
    val shown by animateFloatAsState(fraction.toFloat().coerceIn(0f, 1f), tween(300), label = "thinProgress")
    Box(Modifier.fillMaxWidth().height(6.dp).wardInset(CircleShape)) {
        Box(Modifier.fillMaxWidth(shown).fillMaxHeight().background(wardColor(WardToken.primaryInk), CircleShape))
    }
}

/** A reading surface (contentCard): a soft card raised off the base, padded wide. */
@Composable internal fun Modifier.contentCard(): Modifier =
    this.wardRaised(WardRadius.card, WardLift.mid).padding(WardSpace.xl.wardDp)

/**
 * The bottom study deck (StudyActionBar): an open slab with its controls,
 * and, when it [folds], a band whose small pill folds it away into one round
 * button at the trailing edge.
 */
@Composable internal fun StudyActionBar(folds: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    var folded by rememberSaveable { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(bottom = 8.dp), contentAlignment = Alignment.BottomCenter) {
        if (folds && folded) {
            // folded, it floats over the page with no strip: no glow to haze what scrolls under it
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) { WardUnlit {
                WardButtonBox({ folded = false }, Modifier.semantics { contentDescription = "Show buttons" },
                    kind = WardButtonKind.secondary, fills = false) {
                    Icon(Icons.Rounded.KeyboardArrowUp, null, Modifier.size(16.dp))
                }
            } }
        } else {
            Column(Modifier.widthIn(max = 700.dp).fillMaxWidth().wardRaised(WardRadius.bar, WardLift.high, fill = WardToken.raised)) {
                if (folds) FoldBand { folded = true }
                Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = if (folds) 0.dp else 12.dp, bottom = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
            }
        }
    }
}

/** The open deck's folding band: the chevron in a small pill at the trailing end, pressed in while held. */
@Composable private fun FoldBand(onFold: () -> Unit) {
    Row(Modifier.fillMaxWidth().height(44.dp), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
        WardTile(onFold, Modifier.padding(end = 12.dp).size(width = 44.dp, height = 28.dp).semantics { contentDescription = "Hide buttons" },
            cornerRadius = 14.0) {
            Icon(Icons.Rounded.KeyboardArrowDown, null, tint = wardColor(WardToken.ink), modifier = Modifier.size(18.dp))
        }
    }
}

/** A line cut into the base (WardEtch): a shade line over a highlight line; upright, shade left of highlight. */
@Composable internal fun ReaderEtch(vertical: Boolean = false, modifier: Modifier = Modifier) {
    val spec = WardRelief.raised(WardLift.low, wardNight())
    val shade = lightColor(spec.shade)
    val highlight = lightColor(spec.highlight)
    if (vertical) Row(modifier.fillMaxHeight()) {
        Box(Modifier.width(1.dp).fillMaxHeight().background(shade)); Box(Modifier.width(1.dp).fillMaxHeight().background(highlight))
    } else Column(modifier.fillMaxWidth()) {
        Box(Modifier.height(1.dp).fillMaxWidth().background(shade)); Box(Modifier.height(1.dp).fillMaxWidth().background(highlight))
    }
}

private fun lightColor(light: WardReliefLight): Color =
    Color((((light.alpha.coerceIn(0.0, 1.0) * 255) + 0.5).toInt() shl 24) or (light.hex and 0xFFFFFF))

/**
 * A List or Form row as a soft tile raised low off the base, with a
 * control's ink edge (wardRowBackground, WardRowTile): 8 clear of the
 * cell's edges, the content 8 above and below and 12 at the sides inside
 * it. Pressed in ([inset]), it marks the chosen row.
 */
@Composable internal fun Modifier.wardRowTile(inset: Boolean = false): Modifier =
    this.padding(WardSpace.s.wardDp)
        .wardRelief(RoundedCornerShape(WardRadius.field.wardDp), WardLift.low, inset = inset, control = true)
        .padding(horizontal = 12.dp, vertical = 8.dp)

/** A row (WardRow): icon square, the title, a detail line and a chevron. */
@Composable internal fun WardRowItem(icon: ImageVector, title: String, detail: String? = null, tone: WardTone = WardTone.Blue, chevron: Boolean = true) {
    Row(Modifier.fillMaxWidth().padding(vertical = WardSpace.s.wardDp).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(WardSpace.m.wardDp)) {
        WardIconSquare(icon, tone = tone)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = WardTextStyle.body.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
            if (detail != null) Text(detail, style = WardTextStyle.subheadline.textStyle(), color = wardColor(WardToken.inkSecondary))
        }
        if (chevron) Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(18.dp))
    }
}

/** A Form's section (wardForm): a small-caps header, its rows as tiles, a footnote under them. */
@Composable internal fun ReaderFormSection(header: String? = null, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        if (header != null) WardSmallCapsText(header, Modifier.padding(horizontal = 20.dp).padding(bottom = 2.dp).semantics { heading() })
        content()
        if (footer != null) Text(footer, Modifier.padding(horizontal = 20.dp).padding(top = 2.dp),
            style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary))
    }
}
