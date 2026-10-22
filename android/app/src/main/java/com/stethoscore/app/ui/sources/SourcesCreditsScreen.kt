package com.stethoscore.app.ui.sources

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.rounded.LibraryBooks
import androidx.compose.material.icons.rounded.Description
import androidx.compose.material.icons.rounded.Explore
import androidx.compose.material.icons.rounded.FolderOff
import androidx.compose.material.icons.rounded.InsertDriveFile
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.stethoscore.app.exam.ExamCatalog
import com.stethoscore.app.data.SourceDoc
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.reading.ContentSource
import com.stethoscore.app.reading.ContentSources
import com.stethoscore.app.reading.EvidenceRef
import com.stethoscore.app.reading.SetCredits
import com.stethoscore.app.reading.sourceKind
import com.stethoscore.app.ui.wardColor
import com.stethoscore.app.ui.ward.*

// A port of ios/RedPen/Features/Sources/SourcesCreditsView.swift (fed0105):
// where one set's content came from, with each part's licence and credit
// (SetCreditsView), every source of content the app itself brings
// (ContentLicencesView, in Settings under About), and one source's use,
// credit line, changes and licence links (ContentSourceDetail).

private const val BRAND = "Stethoscore"

/** The words the credits say, kept apart so they can be checked. */
object CreditsWords {
    const val title = "Sources and licences"
    const val emptyTitle = "Nothing recorded for this set"
    const val emptyMessage = "It was typed in, imported from a file, or made before $BRAND kept where a set came from. " +
        "Whatever is in it is yours, or came with the file you imported."
    const val madeFromFooter = "Your own material. $BRAND keeps it so you can read it again, and claims nothing over it."
    const val evidenceFooter = "What the accuracy checks read for this set. Titles and links only: each page stays with its publisher, under its own terms."
    const val yourMaterial = "Lectures, notes and decks you add are yours. $BRAND keeps them on your devices and in your own sync " +
        "so you can study from them, and claims nothing over them."

    fun cited(count: Int, noun: String): String = "Cited by $count ${if (count == 1) noun else noun + "s"}"

    fun styleFooter(style: ContentSource, exam: String): String =
        "When questions are written for $exam, the writer is shown a few real ${style.name} questions as examples of the exam’s style. " +
            "They are examples only: the writer is told never to copy them, and a question written on this device that copies one is dropped."

    /** A link's host, as iOS shows URL.host(). */
    fun host(url: String): String = runCatching { java.net.URI(url).host }.getOrNull() ?: url
}

/** Where one set's content came from (SetCreditsView). */
@Composable fun SetCreditsScreen(set: StudySet, onBack: () -> Unit, onLicences: () -> Unit) {
    val credits = remember(set) { SetCredits.make(set, ExamCatalog.exam(set.exam)?.let { it.name to it.exemplars.rawValue }) }
    var reading by remember { mutableStateOf<SourceDoc?>(null) }
    Column(Modifier.fillMaxSize()) {
        ReaderNavBar(CreditsWords.title, leading = { ReaderBackButton(onBack) })
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(vertical = WardSpace.s.wardDp),
            verticalArrangement = Arrangement.spacedBy(WardSpace.section.wardDp)) {
            if (credits.isEmpty) ReaderFormSection {
                Box(Modifier.fillMaxWidth().wardRowTile()) {
                    ReaderEmptyState(Icons.Rounded.FolderOff, CreditsWords.emptyTitle, CreditsWords.emptyMessage, tone = WardTone.Grey)
                }
            }
            if (credits.lectures.isNotEmpty() || credits.citedElsewhere.isNotEmpty()) {
                ReaderFormSection("Made from", CreditsWords.madeFromFooter) {
                    credits.lectures.forEach { lecture ->
                        Row(Modifier.fillMaxWidth().clickable(role = Role.Button, onClickLabel = "Opens the lecture") { reading = lecture.source }
                            .wardRowTile(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            WardIconSquare(kindIcon(lecture.source.sourceKind), tone = WardTone.Blue, size = 32.0)
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(lecture.source.name.ifEmpty { "Untitled lecture" }, style = WardTextStyle.body.textStyle(WardWeight.medium),
                                    color = wardColor(WardToken.ink))
                                Text(lecture.detail, style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
                                if (lecture.cited > 0) Text(CreditsWords.cited(lecture.cited, set.itemNoun),
                                    style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
                            }
                            Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(16.dp))
                        }
                    }
                    credits.citedElsewhere.forEach { name ->
                        Row(Modifier.fillMaxWidth().wardRowTile().semantics(mergeDescendants = true) {},
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Icon(Icons.Rounded.InsertDriveFile, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(20.dp))
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(name, style = WardTextStyle.body.textStyle(WardWeight.medium), color = wardColor(WardToken.ink))
                                Text("Cited, but not kept with this set", style = WardTextStyle.caption.textStyle(), color = wardColor(WardToken.inkSecondary))
                            }
                        }
                    }
                }
            }
            credits.style?.let { style ->
                ReaderFormSection("Question style", CreditsWords.styleFooter(style, credits.examName ?: "your exam")) {
                    Column(Modifier.fillMaxWidth().wardRowTile(), verticalArrangement = Arrangement.spacedBy(6.dp)) { ContentSourceDetail(style) }
                }
            }
            if (credits.evidence.isNotEmpty() || credits.otherEvidence.isNotEmpty()) {
                ReaderFormSection("Checked against", CreditsWords.evidenceFooter) {
                    credits.evidence.forEach { group ->
                        Disclosure(group.source.name, group.refs.size) {
                            group.refs.forEach { RefLink(it) }
                            ContentSourceDetail(group.source, showsUse = false)
                        }
                    }
                    if (credits.otherEvidence.isNotEmpty()) Disclosure("Other sources", credits.otherEvidence.size) {
                        credits.otherEvidence.forEach { RefLink(it) }
                    }
                }
            }
            ReaderFormSection {
                Box(Modifier.fillMaxWidth().clickable(role = Role.Button, onClick = onLicences).wardRowTile()) {
                    LabelRow(Icons.AutoMirrored.Rounded.LibraryBooks, "Every source and licence", chevron = true)
                }
            }
        }
    }
    reading?.let { source -> SourcePreviewSheet(source, set, 1) { reading = null } }
}

/** Every source of content the app itself brings (ContentLicencesView). */
@Composable fun ContentLicencesScreen(onBack: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        ReaderNavBar(CreditsWords.title, leading = { ReaderBackButton(onBack) })
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(vertical = WardSpace.s.wardDp),
            verticalArrangement = Arrangement.spacedBy(WardSpace.section.wardDp)) {
            ReaderFormSection("Your material") {
                Box(Modifier.fillMaxWidth().wardRowTile()) {
                    Text(CreditsWords.yourMaterial, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.ink))
                }
            }
            ContentSources.all.forEach { source ->
                ReaderFormSection(source.name) {
                    Column(Modifier.fillMaxWidth().wardRowTile(), verticalArrangement = Arrangement.spacedBy(6.dp)) { ContentSourceDetail(source) }
                }
            }
        }
    }
}

/** One source's use, credit line, changes and licence links (ContentSourceDetail). */
@Composable fun ContentSourceDetail(source: ContentSource, showsUse: Boolean = true) {
    Column(Modifier.padding(vertical = 2.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (showsUse) Text(source.use, style = WardTextStyle.subheadline.textStyle(WardWeight.semibold), color = wardColor(WardToken.ink))
        Text(source.attribution, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.ink))
        source.changes?.let { Text("Changes: $it", style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.inkSecondary)) }
    }
    source.licences.forEach { licence -> LinkRow(Icons.Rounded.Verified, licence.name, licence.url) }
    LinkRow(Icons.Rounded.Explore, CreditsWords.host(source.home), source.home)
}

/** A link out, opened only when it is https (Link). */
@Composable private fun LinkRow(icon: ImageVector, title: String, url: String) {
    val opener = LocalUriHandler.current
    val safe = url.startsWith("https://")
    Row(Modifier.fillMaxWidth().then(if (safe) Modifier.clickable(role = Role.Button) { runCatching { opener.openUri(url) } } else Modifier)
        .padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, null, tint = wardColor(WardToken.primaryInk), modifier = Modifier.size(16.dp))
        Text(title, style = WardTextStyle.footnote.textStyle(), color = wardColor(WardToken.primaryInk))
    }
}

@Composable private fun RefLink(ref: EvidenceRef) {
    if (ref.url.startsWith("https://")) LinkRow(Icons.Rounded.Link, ref.title.ifEmpty { ref.url }, ref.url)
    else LabelRow(Icons.Rounded.Description, ref.label, small = true)
}

@Composable private fun LabelRow(icon: ImageVector, title: String, chevron: Boolean = false, small: Boolean = false) {
    Row(Modifier.fillMaxWidth().padding(vertical = if (small) 4.dp else 6.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(icon, null, tint = wardColor(if (small) WardToken.inkSecondary else WardToken.primaryInk), modifier = Modifier.size(if (small) 16.dp else 20.dp))
        Text(title, Modifier.weight(1f), style = (if (small) WardTextStyle.footnote else WardTextStyle.body).textStyle(), color = wardColor(WardToken.ink))
        if (chevron) Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = wardColor(WardToken.inkSecondary), modifier = Modifier.size(16.dp))
    }
}

/** A DisclosureGroup with a LabeledContent label: the name, the count in mono, a turning chevron. */
@Composable private fun Disclosure(name: String, count: Int, content: @Composable ColumnScope.() -> Unit) {
    var open by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().wardRowTile()) {
        Row(Modifier.fillMaxWidth().clickable(role = Role.Button, onClickLabel = if (open) "Collapse" else "Expand") { open = !open }
            .padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(name, Modifier.weight(1f), style = WardTextStyle.body.textStyle(), color = wardColor(WardToken.ink))
            Text("$count", style = WardType.obs.textStyle(), color = wardColor(WardToken.inkSecondary))
            Icon(Icons.Rounded.KeyboardArrowDown, null, tint = wardColor(WardToken.primaryInk),
                modifier = Modifier.size(18.dp).rotate(if (open) 0f else -90f))
        }
        if (open) Column(Modifier.fillMaxWidth().padding(start = 8.dp, bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(2.dp), content = content)
    }
}
