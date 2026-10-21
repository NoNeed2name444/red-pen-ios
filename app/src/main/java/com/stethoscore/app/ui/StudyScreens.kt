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

// The question screen is MCQQuizScreen.kt (a port of iOS's MCQQuizView).

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
                val labels=ReviewOptions.previewLabels(record, System.currentTimeMillis(), store.examDate, store.reviewSettings.scheduler)
                Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
                    AnkiRating.entries.chunked(2).forEach { pair -> Row(horizontalArrangement=Arrangement.spacedBy(12.dp)) {pair.forEach {rating ->
                        OutlinedButton(onClick={store.rateCard(card,rating);reviewed++;revision++},modifier=Modifier.weight(1f).height(70.dp),shape=RoundedCornerShape(18.dp)) {Column(horizontalAlignment=Alignment.CenterHorizontally) {Text(rating.label,fontWeight=FontWeight.Bold);Text(labels[rating] ?: "",fontSize=12.sp)}}
                    }} }
                }
            }
            Text(if(store.reviewSettings.scheduler==ReviewScheduler.FSRS) "Scheduled by FSRS-5, as in Stethoscore on iOS. Change it in Settings." else "Your schedule uses the same review intervals as Stethoscore on iOS.",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
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
