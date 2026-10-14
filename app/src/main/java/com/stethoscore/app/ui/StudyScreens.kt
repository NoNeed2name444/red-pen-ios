package com.stethoscore.app.ui

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.*

@Composable fun QuizScreen(set:StudySet,store:StudyStore,onBack:()->Unit) {
    val saved=remember(set.id) { store.quizProgress[set.id]?.takeIf {it.questionIds==set.questions.map {q->q.id}} }
    var index by rememberSaveable(set.id) { mutableIntStateOf(saved?.current ?: 0) }
    var answers by remember(set.id) { mutableStateOf(saved?.answers ?: set.questions.map {MCQAnswer()}) }
    val order=remember(set.id) { saved?.optionOrders?.takeIf {it.size==set.questions.size} ?: set.questions.map {it.options.indices.shuffled()} }
    fun persist() { store.saveQuizProgress(set.id,QuizProgress(index,answers,set.questions.map {it.id},order)) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(22.dp)) {
        ScreenHeader("Questions",set.name,onBack)
        if(set.questions.isEmpty()) { Text("This set has no questions yet.");return@Column }
        if(index>=set.questions.size) {
            val correct=answers.zip(set.questions).count {(a,q)->a.isCorrect(q)}
            WardCard(Modifier.fillMaxWidth()) {
                SectionLabel("Round complete")
                Icon(Icons.Rounded.TaskAlt,null,tint=MaterialTheme.colorScheme.tertiary,modifier=Modifier.size(42.dp))
                Text("$correct / ${set.questions.size}",fontSize=48.sp,fontWeight=FontWeight.Bold)
                Text("${(correct*100.0/set.questions.size).toInt()}% correct",fontSize=20.sp)
                Text("Take a moment to revisit the explanations. Every answer is saved in your Vitals.",color=MaterialTheme.colorScheme.onSurfaceVariant)
                WardButton("Review this set again",{ index=0;answers=set.questions.map {MCQAnswer()};store.clearQuizProgress(set.id) },Modifier.fillMaxWidth())
                WardButton("Back to your ward",onBack,Modifier.fillMaxWidth())
            }
        } else {
            val question=set.questions[index];val answer=answers[index]
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) { SectionLabel(set.subject);Text("${index+1} / ${set.questions.size}",color=MaterialTheme.colorScheme.primary,fontWeight=FontWeight.Bold) }
            LinearProgressIndicator(progress={index.toFloat()/set.questions.size},modifier=Modifier.fillMaxWidth().height(5.dp).clip(RoundedCornerShape(5.dp)),color=MaterialTheme.colorScheme.primary,trackColor=MaterialTheme.colorScheme.outline.copy(alpha=.25f))
            WardCard(Modifier.fillMaxWidth()) {
                SectionLabel("Single best answer")
                question.imageIndex?.let { CardImage(set,it) }
                Text(question.stem,fontSize=22.sp,lineHeight=31.sp,fontWeight=FontWeight.Medium)
            }
            Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
                order[index].forEachIndexed { display,pos ->
                    val correct=answer.checked && pos==question.correctIndex
                    val wrong=answer.checked && answer.selected==pos && !correct
                    val selected=answer.selected==pos
                    val tint=when {correct->MaterialTheme.colorScheme.tertiary;wrong->MaterialTheme.colorScheme.error;selected->MaterialTheme.colorScheme.primary;else->MaterialTheme.colorScheme.outline}
                    Row(Modifier.fillMaxWidth().border(if(selected||correct) 2.dp else 1.dp,tint,RoundedCornerShape(18.dp)).background(tint.copy(alpha=if(selected||correct) .08f else .015f),RoundedCornerShape(18.dp)).clickable(enabled=!answer.checked) {answers=answers.toMutableList().also {it[index]=answer.copy(selected=pos)};persist()}.padding(16.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp)) {
                        Text(('A'+display).toString(),color=tint,fontWeight=FontWeight.Bold)
                        Text(question.options[pos],Modifier.weight(1f),fontSize=16.sp)
                        if(correct) Icon(Icons.Rounded.CheckCircle,"Correct answer",tint=tint,modifier=Modifier.size(22.dp))
                        else if(selected) Icon(if(wrong) Icons.Rounded.Cancel else Icons.Rounded.RadioButtonChecked,if(wrong) "Your answer was incorrect" else "Selected",tint=tint,modifier=Modifier.size(22.dp))
                    }
                }
            }
            if(answer.checked) {
                WardCard(Modifier.fillMaxWidth()) {
                    Text(if(answer.isCorrect(question)) "Well reasoned." else "A point to revisit.",color=if(answer.isCorrect(question)) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.error,fontWeight=FontWeight.Bold,fontSize=18.sp)
                    Text(question.explanation.ifBlank {"No explanation supplied for this question."},lineHeight=25.sp)
                    question.source?.let { Text(it,fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }
                    Text("Source content · Not independently verified",fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                }
                WardButton(if(index==set.questions.lastIndex) "Finish round" else "Next question",{index++;persist()},Modifier.fillMaxWidth())
            } else WardButton("Check answer",{
                if(answer.selected!=null) { val checked=answer.copy(checked=true);answers=answers.toMutableList().also {it[index]=checked};store.recordAnswer(question.id,checked.isCorrect(question));persist() }
            },Modifier.fillMaxWidth(),enabled=answer.selected!=null)
        }
    }
}

@Composable fun CardsScreen(set:StudySet,store:StudyStore,onBack:()->Unit) {
    var revision by remember { mutableIntStateOf(0) }
    var reviewed by rememberSaveable(set.id) { mutableIntStateOf(0) }
    val due=remember(revision) {store.dueCards(set)}
    val card=due.firstOrNull()
    var revealed by rememberSaveable(card?.id) {mutableStateOf(false)}
    // A card rated Again comes back in minutes: when the queue is empty, wait for the next one
    // due within the next half hour and bring it back instead of staying on "All caught up".
    LaunchedEffect(revision,card==null) {
        if(card!=null) return@LaunchedEffect
        val now=System.currentTimeMillis()
        val next=set.cards.mapNotNull { store.reviews[it.id]?.takeIf { r -> !r.suspended }?.due }.filter { it>now && it-now<=30*60_000L }.minOrNull() ?: return@LaunchedEffect
        kotlinx.coroutines.delay(next-now+500)
        revision++
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(24.dp)) {
        ScreenHeader("Spaced review",set.name,onBack)
        Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween) {SectionLabel(set.subject);Text("${due.size} due",color=MaterialTheme.colorScheme.primary,fontWeight=FontWeight.Bold)}
        if(card==null) {
            WardCard(Modifier.fillMaxWidth()) {Icon(Icons.Rounded.TaskAlt,null,tint=MaterialTheme.colorScheme.tertiary,modifier=Modifier.size(44.dp));Text("All caught up",fontSize=28.sp,fontWeight=FontWeight.Bold);Text("$reviewed cards reviewed this session. Your next review is saved on this device.");WardButton("Back to your ward",onBack,Modifier.fillMaxWidth())}
        } else {
            WardCard(Modifier.fillMaxWidth().heightIn(min=300.dp)) {
                SectionLabel(if(card.type==AnkiCardType.CLOZE) "Fill the gap" else "Active recall")
                Spacer(Modifier.height(12.dp))
                if(card.pictureOnFront || revealed) card.imageIndex?.let { CardImage(set,it,card, revealed) }
                Text(if(card.type==AnkiCardType.CLOZE) card.cloze(revealed) else card.displayFront,fontSize=25.sp,lineHeight=34.sp,fontWeight=FontWeight.Medium)
                if(revealed) {
                    HorizontalDivider(Modifier.padding(vertical=10.dp),color=MaterialTheme.colorScheme.outline)
                    card.bullets.forEach {Text("•  ${it.replace("**","")}",lineHeight=26.sp,fontSize=18.sp)}
                    if(card.why.isNotBlank()) Text(card.why,lineHeight=24.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                    card.source?.let {Text(it,fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)}
                } else Text("Say the answer before you turn the card.",color=MaterialTheme.colorScheme.onSurfaceVariant,fontSize=13.sp,modifier=Modifier.padding(top=20.dp))
            }
            if(!revealed) WardButton("Reveal answer",{revealed=true},Modifier.fillMaxWidth())
            else {
                SectionLabel("How well did you remember?")
                val record=store.reviews[card.id] ?: ReviewRecord(System.currentTimeMillis(),0.0)
                val labels=ReviewPlan.previewLabels(record, exam=store.examDate)
                Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
                    AnkiRating.entries.chunked(2).forEach { pair -> Row(horizontalArrangement=Arrangement.spacedBy(12.dp)) {pair.forEach {rating ->
                        OutlinedButton(onClick={store.rateCard(card,rating);reviewed++;revision++},modifier=Modifier.weight(1f).height(70.dp),shape=RoundedCornerShape(18.dp)) {Column(horizontalAlignment=Alignment.CenterHorizontally) {Text(rating.label,fontWeight=FontWeight.Bold);Text(labels[rating] ?: "",fontSize=12.sp)}}
                    }} }
                }
            }
            Text("Your schedule uses the same review intervals as Stethoscore on iOS.",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable fun CardImage(set:StudySet,index:Int,card:AnkiCard?=null,revealed:Boolean=false) {
    val encoded=set.images.getOrNull(index)
    val bitmap=remember(encoded) { runCatching { if(encoded==null || encoded.startsWith("blob:")) null else {val bytes=Base64.decode(encoded.substringAfter("base64,",encoded),Base64.DEFAULT);BitmapFactory.decodeByteArray(bytes,0,bytes.size)?.asImageBitmap()} }.getOrNull() }
    if(bitmap==null) {Text("Image unavailable on this device",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant);return}
    val masks=if(card?.type==AnkiCardType.OCCLUSION) card.siblings+if(!revealed) listOfNotNull(card.occlusion) else emptyList() else emptyList()
    Box(Modifier.fillMaxWidth().aspectRatio(bitmap.width.toFloat()/bitmap.height)) {
        Image(bitmap,"Study illustration",Modifier.fillMaxSize())
        if(masks.isNotEmpty()) Canvas(Modifier.fillMaxSize()) { masks.forEach {m->drawRect(Color(0xFF1D5FB0),Offset(m.x.toFloat()*size.width,m.y.toFloat()*size.height),Size(m.w.toFloat()*size.width,m.h.toFloat()*size.height))} }
    }
}
