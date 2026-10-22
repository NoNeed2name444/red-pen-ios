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
import com.stethoscore.app.data.*
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.textStyle

// The question screen is MCQQuizScreen.kt (a port of iOS's MCQQuizView).

@Composable fun CardImage(set:StudySet,index:Int,card:AnkiCard?=null,revealed:Boolean=false) {
    val encoded=set.images.getOrNull(index)
    val bitmap=remember(encoded) { runCatching { if(encoded==null || encoded.startsWith("blob:")) null else {val bytes=Base64.decode(encoded.substringAfter("base64,",encoded),Base64.DEFAULT);BitmapFactory.decodeByteArray(bytes,0,bytes.size)?.asImageBitmap()} }.getOrNull() }
    if(bitmap==null) {Text("Image unavailable on this device",style=WardType.caption.textStyle(),color=MaterialTheme.colorScheme.onSurfaceVariant);return}
    // an occlusion card's covers in OcclusionCovers' colours, as the card face draws them
    val masks=if(card?.type==AnkiCardType.OCCLUSION) card.siblings.map { it to OcclusionCovers.otherRgb }+if(!revealed) listOfNotNull(card.occlusion).map { it to OcclusionCovers.targetRgb } else emptyList() else emptyList()
    Box(Modifier.fillMaxWidth().aspectRatio(bitmap.width.toFloat()/bitmap.height)) {
        Image(bitmap,"Study illustration",Modifier.fillMaxSize())
        if(masks.isNotEmpty()) Canvas(Modifier.fillMaxSize()) { masks.forEach {(m,c)->drawRect(Color(c.first.toFloat(),c.second.toFloat(),c.third.toFloat()),Offset(m.x.toFloat()*size.width,m.y.toFloat()*size.height),Size(m.w.toFloat()*size.width,m.h.toFloat()*size.height))} }
    }
}
