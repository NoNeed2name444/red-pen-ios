package com.stethoscore.app.ui

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.*
import com.stethoscore.app.ui.ward.WardChipButton
import com.stethoscore.app.ui.ward.WardCircleButton
import com.stethoscore.app.ui.ward.WardSegmented
import com.stethoscore.app.ui.ward.WardToggle

/** New set; a [preset] (the exam's Study next, the Ward pocket's Practise this) fills in its name, subject and mode. */
@Composable fun NewSetScreen(onSave:(StudySet)->Unit,onBack:()->Unit,preset:com.stethoscore.app.exam.NewSetPreset?=null) {
    var name by rememberSaveable { mutableStateOf(preset?.name ?: "") }
    var subject by rememberSaveable { mutableStateOf(preset?.subject ?: "") }
    var kindName by rememberSaveable { mutableStateOf((preset?.kind ?: StudySetKind.ANKI).name) }
    val kind=StudySetKind.valueOf(kindName)
    var content by rememberSaveable { mutableStateOf("") }
    var error by remember {mutableStateOf<String?>(null)}
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(20.dp)) {
        ScreenHeader("New study set","Make something worth remembering",onBack)
        OutlinedTextField(name,{name=it},Modifier.fillMaxWidth(),label={Text("Set name")},singleLine=true)
        OutlinedTextField(subject,{subject=it},Modifier.fillMaxWidth(),label={Text("Subject")},singleLine=true)
        SectionLabel("Study mode")
        // the mode, one chosen: Ward chip buttons (the chosen one pressed in with its accent edge)
        StudySetKind.entries.filter {it!=StudySetKind.CASES}.chunked(3).forEach { row -> Row(horizontalArrangement=Arrangement.spacedBy(6.dp)) {row.forEach { mode -> WardChipButton(mode.label,{kindName=mode.name},on=kind==mode)} } }
        WardCard(Modifier.fillMaxWidth()) {
            Text(when(kind) {StudySetKind.ANKI->"One card per line";StudySetKind.MCQ->"One question per block";StudySetKind.OSCE->"One checklist step per line";StudySetKind.NARRATE->"One transcript segment per line";else->"Write or paste your notes"},fontWeight=FontWeight.Bold)
            Text(when(kind) {StudySetKind.ANKI->"Question | Answer\nUse {{c1::answer}} for a cloze card.";StudySetKind.MCQ->"Question\nA) Option\n*B) Correct option\nC) Option\nWhy: Explanation\n\nSeparate questions with a blank line.";StudySetKind.BOOK->"Use # headings and ## page titles. Your text stays editable in exported JSON.";StudySetKind.OSCE->"Use the set name as the station title. Each non-empty line becomes a recall step.";else->"Paste the transcript. Playback uses the text-to-speech voice installed on your device."},fontSize=13.sp,lineHeight=21.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        // what the questions are to be written on (iOS gives it to the writer as its notes)
        if(preset!=null && preset.notes.isNotBlank()) WardCard(Modifier.fillMaxWidth()) { SectionLabel("Notes");Text(preset.notes,fontSize=13.sp,lineHeight=21.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }
        if(kind==StudySetKind.OSCE) com.stethoscore.app.ui.osce.OsceGenerateSection(content,{content=it;error=null},subject,{subject=it})
        OutlinedTextField(content,{content=it;error=null},Modifier.fillMaxWidth().heightIn(min=230.dp),label={Text("Study content")},minLines=8)
        error?.let {Text(it,color=MaterialTheme.colorScheme.error)}
        WardButton("Save study set",{
            runCatching { onSave(parseStudySet(name,subject,kind,content)) }.onFailure {error=it.message ?: "Check your content and try again."}
        },Modifier.fillMaxWidth(),name.isNotBlank() && content.isNotBlank())
        Text("To add a Cases set, import a Stethoscore JSON file from Settings.",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

fun parseStudySet(name:String,subject:String,kind:StudySetKind,content:String):StudySet {
    require(name.isNotBlank() && content.isNotBlank()) {"Add a name and some content."}
    val base=StudySet(name=name.trim(),subject=subject.trim().ifBlank {"General"},kind=kind)
    val lines=content.lines().map {it.trim()}.filter {it.isNotEmpty()}
    return when(kind) {
        StudySetKind.ANKI -> base.copy(cards=lines.map {line->
            if(Regex("\\{\\{c\\d+::").containsMatchIn(line)) AnkiCard(type=AnkiCardType.CLOZE,clozeText=line)
            else {val pair=line.split('|',limit=2);require(pair.size==2 && pair.all {it.isNotBlank()}) {"Each card needs Question | Answer, or a cloze sentence."};AnkiCard(front=pair[0].trim(),bullets=listOf(pair[1].trim()))}
        })
        StudySetKind.MCQ -> base.copy(questions=content.trim().split(Regex("\\n\\s*\\n")).mapIndexed {i,block->
            val parts=block.lines().map {it.trim()}.filter {it.isNotEmpty()};val options=parts.drop(1).filter {Regex("^\\*?[A-Z][).]\\s+.+").matches(it)}
            val correct=options.indexOfFirst {it.startsWith("*")}
            require(options.size>=2 && options.count {it.startsWith("*")}==1) {"Question ${i+1} needs at least two lettered options and exactly one marked with *."}
            MCQQuestion(stem=parts.first(),options=options.map {it.replace(Regex("^\\*?[A-Z][).]\\s+"),"")},correctIndex=correct,explanation=parts.firstOrNull {it.startsWith("Why:",true)}?.substringAfter(':')?.trim().orEmpty())
        })
        StudySetKind.BOOK -> base.copy(bookMarkdown=content.trim())
        StudySetKind.OSCE -> base.copy(osceChecklists=OsceText.parseOsce(content).ifEmpty {listOf(OsceChecklist(title=name.trim(),steps=lines))})
        StudySetKind.NARRATE -> base.copy(narrateSegments=lines.map {NarrateSegment(text=it)})
        else -> error("Import a Cases JSON file instead.")
    }
}

@Composable fun SettingsScreen(dark:Boolean,onDark:(Boolean)->Unit,onImport:()->Unit,onExport:()->Unit,onExamples:()->Unit,onBack:()->Unit,
    review:ReviewSettings=ReviewSettings(),onReview:(ReviewSettings)->Unit={},
    onSources:(()->Unit)?=null,onLicences:(()->Unit)?=null,onExam:(()->Unit)?=null,onModels:(()->Unit)?=null) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(22.dp)) {
        ScreenHeader("Settings","Your study space",onBack)
        WardCard(Modifier.fillMaxWidth()) {
            SectionLabel("Appearance")
            // a Ward switch, the whole row toggling it (iOS's Toggle in wardForm), its note under it
            WardToggle(dark,onDark,label="Night shift")
            Text("Stethoscore's dark palette",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        // iOS: Settings, "Your exam" (ExamPickerView)
        if(onExam!=null) WardCard(Modifier.fillMaxWidth()) {
            val context=LocalContext.current
            val exam=remember { com.stethoscore.app.exam.ExamChoice.current(context) }
            SectionLabel("Your exam")
            Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
                Text("Exam",Modifier.weight(1f),fontSize=18.sp,fontWeight=FontWeight.SemiBold)
                Text(exam?.shortName ?: "Choose",fontSize=16.sp,color=MaterialTheme.colorScheme.primary)
            }
            WardButton(if(exam==null) "Choose your exam" else "Change exam",onExam,Modifier.fillMaxWidth().testTag("chooseExam"))
            Text("Questions and stations are written in your exam's style: USMLE uses US units and guidelines; PLAB, MRCP and MRCS use SI units, NICE and the BNF, and their own station formats.",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        // iOS: Settings, "AI models" (ModelSettingsView)
        if(onModels!=null) WardCard(Modifier.fillMaxWidth()) {
            SectionLabel("AI models")
            Text("The writer and Stethoscore Cloud",fontSize=18.sp,fontWeight=FontWeight.SemiBold)
            WardButton("AI models",onModels,Modifier.fillMaxWidth().testTag("aiModels"))
        }
        WardCard(Modifier.fillMaxWidth()) {
            SectionLabel("Review")
            Text("Scheduler",fontSize=18.sp,fontWeight=FontWeight.SemiBold)
            // as iOS ReviewSettingsSection: the scheduler on the segmented control
            WardSegmented(review.scheduler,ReviewScheduler.entries,{ onReview(review.copy(scheduler=it)) },Modifier.semantics { contentDescription="Scheduler" }) { s,style,ink ->
                Text(s.title,style=style,color=ink)
            }
            Text(if(review.scheduler==ReviewScheduler.FSRS) "FSRS-5 with its published weights: each card's stability and difficulty set its next interval." else "Classic: the web app's intervals, the default.",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
            LimitStepper("New cards a day",review.limits.newPerDay,5) { onReview(review.copy(limits=review.limits.copy(newPerDay=it))) }
            LimitStepper("Reviews a day",review.limits.reviewsPerDay,10) { onReview(review.copy(limits=review.limits.copy(reviewsPerDay=it))) }
            Text("Learning cards always come back when due. A study day turns over at 4 am.",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        WardCard(Modifier.fillMaxWidth()) {
            SectionLabel("Your library")
            Text("Saved on this device",fontSize=20.sp,fontWeight=FontWeight.SemiBold)
            Text("Import sets from Stethoscore or export a backup of your library, notes and review history.",color=MaterialTheme.colorScheme.onSurfaceVariant)
            WardButton("Import JSON",onImport,Modifier.fillMaxWidth())
            WardButton("Export library backup",onExport,Modifier.fillMaxWidth())
            WardButton("Add example sets",onExamples,Modifier.fillMaxWidth())
            // iOS: Support centre, "Your lectures" (SourcesLibraryView)
            if(onSources!=null) WardButton("Your lectures",onSources,Modifier.fillMaxWidth().testTag("sourcesLibrary"))
        }
        // iOS: Settings, About, "Sources and licences" (ContentLicencesView)
        if(onLicences!=null) WardCard(Modifier.fillMaxWidth()) {
            SectionLabel("About")
            WardButton("Sources and licences",onLicences,Modifier.fillMaxWidth().testTag("contentLicences"))
        }
        WardCard(Modifier.fillMaxWidth()) {
            SectionLabel("Android preview · 0.1")
            Text("Native Kotlin. Same study foundations.",fontSize=20.sp,fontWeight=FontWeight.SemiBold)
            Text("Questions, spaced cards, OSCE, textbook, transcript playback, Cases and linked notes work locally. Account sync, cloud AI, audio transcription and the 3D renderer are still being ported.",lineHeight=24.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
            Text("Built from the audited October 9 Stethoscore source.",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text("Stethoscore is a study aid. Source material and sample answers have not been independently verified for clinical use.",fontSize=12.sp,lineHeight=18.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable private fun LimitStepper(label:String,value:Int,step:Int,onChange:(Int)->Unit) {
    Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) { Text(label,fontSize=16.sp,fontWeight=FontWeight.SemiBold); Text(if(value<=0) "No limit" else "$value",fontSize=13.sp,color=MaterialTheme.colorScheme.primary) }
        // a stepper's minus and plus: Ward circles
        WardCircleButton(Icons.Rounded.Remove,"Fewer ${label.lowercase()}",{ onChange((value-step).coerceAtLeast(0)) },enabled=value>0)
        Spacer(Modifier.width(8.dp))
        WardCircleButton(Icons.Rounded.Add,"More ${label.lowercase()}",{ onChange((value+step).coerceAtMost(9999)) })
    }
}
