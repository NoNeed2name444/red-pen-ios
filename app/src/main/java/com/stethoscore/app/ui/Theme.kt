package com.stethoscore.app.ui

import android.app.Activity
import android.content.ContextWrapper
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// Direct port of WardPalette.swift at be11a56. The matte base is shared by cards and ground.
private val Light = lightColorScheme(primary=Color(0xFF1D5FB0), onPrimary=Color.White, background=Color(0xFFE0E5EC), surface=Color(0xFFE0E5EC), onBackground=Color(0xFF0E1B2C), onSurface=Color(0xFF0E1B2C), onSurfaceVariant=Color(0xFF4E5E73), secondary=Color(0xFFBA273B), tertiary=Color(0xFF137045), outline=Color(0xFF8DA4C1), error=Color(0xFFC0262D))
private val Dark = darkColorScheme(primary=Color(0xFF7DB0F2), onPrimary=Color(0xFF0E1B2C), background=Color(0xFF2A2E35), surface=Color(0xFF2A2E35), onBackground=Color(0xFFE8EEF5), onSurface=Color(0xFFE8EEF5), onSurfaceVariant=Color(0xFFA3B1C3), secondary=Color(0xFFF2788A), tertiary=Color(0xFF4CC38A), outline=Color(0xFF5F789A), error=Color(0xFFF57A7F))
val LocalWardDark = staticCompositionLocalOf { false }

@Composable fun StethoscoreTheme(dark:Boolean=false, content:@Composable ()->Unit) {
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val activity = generateSequence(view.context) { (it as? ContextWrapper)?.baseContext }
                .filterIsInstance<Activity>().firstOrNull()
            activity?.let {
                WindowCompat.getInsetsController(it.window, view).apply {
                    isAppearanceLightStatusBars = !dark
                    isAppearanceLightNavigationBars = !dark
                }
            }
        }
    }
    CompositionLocalProvider(LocalWardDark provides dark) {
        MaterialTheme(colorScheme=if(dark) Dark else Light, typography=Typography(), content=content)
    }
}

fun Modifier.relief(dark:Boolean, radius:Float=24f):Modifier = drawBehind {
    drawIntoCanvas { canvas ->
        val p=Paint().asFrameworkPaint()
        p.isAntiAlias=true
        p.color=android.graphics.Color.parseColor(if(dark) "#2A2E35" else "#E0E5EC")
        val r=radius.dp.toPx()
        p.setShadowLayer(9.dp.toPx(),-4.dp.toPx(),-4.dp.toPx(),if(dark) 0x14FFFFFF else 0xCCFFFFFF.toInt())
        canvas.nativeCanvas.drawRoundRect(0f,0f,size.width,size.height,r,r,p)
        p.setShadowLayer(9.dp.toPx(),4.dp.toPx(),4.dp.toPx(),if(dark) 0x99000000.toInt() else 0x88A3B1C6.toInt())
        canvas.nativeCanvas.drawRoundRect(0f,0f,size.width,size.height,r,r,p)
        p.clearShadowLayer()
    }
}

@Composable fun WardCard(modifier:Modifier=Modifier, content:@Composable ColumnScope.()->Unit) {
    Column(modifier.relief(LocalWardDark.current).background(MaterialTheme.colorScheme.surface,RoundedCornerShape(24.dp)).padding(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp),content=content)
}
@Composable fun WardButton(text:String,onClick:()->Unit,modifier:Modifier=Modifier,enabled:Boolean=true) {
    OutlinedButton(onClick=onClick,modifier=modifier.heightIn(min=50.dp),enabled=enabled,shape=RoundedCornerShape(24.dp),border=androidx.compose.foundation.BorderStroke(1.dp,MaterialTheme.colorScheme.primary.copy(alpha=if(enabled) .75f else .25f))) {
        Text(text,fontWeight=FontWeight.SemiBold,fontSize=15.sp)
    }
}
@Composable fun SectionLabel(text:String) { Text(text.uppercase(),fontSize=11.sp,letterSpacing=1.4.sp,fontWeight=FontWeight.Bold,color=MaterialTheme.colorScheme.onSurfaceVariant) }
@Composable fun ScreenHeader(title:String,subtitle:String,onBack:()->Unit) {
    Row(Modifier.fillMaxWidth().padding(bottom=8.dp),verticalAlignment=androidx.compose.ui.Alignment.CenterVertically) {
        IconButton(onClick=onBack) { Icon(Icons.AutoMirrored.Rounded.ArrowBack,contentDescription="Back") }
        Column(Modifier.weight(1f)) { Text(title,fontSize=25.sp,fontWeight=FontWeight.Bold); if(subtitle.isNotBlank()) Text(subtitle,fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }
    }
}
@Composable fun EcgGrid(modifier:Modifier=Modifier) {
    val blue=MaterialTheme.colorScheme.primary
    Canvas(modifier) {
        val step=12.dp.toPx()
        var x=0f; var i=0
        while(x<size.width) { drawLine(blue.copy(alpha=if(i%5==0) .22f else .08f),Offset(x,0f),Offset(x,size.height),1f); x+=step;i++ }
        var y=0f;i=0
        while(y<size.height) { drawLine(blue.copy(alpha=if(i%5==0) .22f else .08f),Offset(0f,y),Offset(size.width,y),1f); y+=step;i++ }
    }
}
@Composable fun PulseLine(modifier:Modifier=Modifier) {
    val color=MaterialTheme.colorScheme.secondary
    Canvas(modifier) {
        val pts=listOf(0f to .55f,.24f to .55f,.31f to .4f,.4f to .65f,.5f to .05f,.61f to .92f,.69f to .45f,.8f to .55f,1f to .55f)
        pts.zipWithNext().forEach { (a,b)-> drawLine(color,Offset(a.first*size.width,a.second*size.height),Offset(b.first*size.width,b.second*size.height),3.dp.toPx(),cap=androidx.compose.ui.graphics.StrokeCap.Round) }
    }
}
