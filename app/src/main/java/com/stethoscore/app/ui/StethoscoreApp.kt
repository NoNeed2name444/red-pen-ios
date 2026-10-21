package com.stethoscore.app.ui

import com.stethoscore.app.ui.ward.WardSection

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable fun StethoscoreApp(store:StudyStore, initialScreen:String="home", forceDark:Boolean?=null) {
    val context=LocalContext.current
    val prefs=remember { context.getSharedPreferences("appearance",Context.MODE_PRIVATE) }
    var dark by remember { mutableStateOf(forceDark ?: prefs.getBoolean("dark",false)) }
    var reviewSettings by remember { mutableStateOf(store.reviewSettings) }
    var screen by rememberSaveable { mutableStateOf(initialScreen) }
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    var revision by remember { mutableIntStateOf(0) }
    var category by rememberSaveable { mutableStateOf("Questions") }
    var query by rememberSaveable { mutableStateOf("") }
    var notice by remember { mutableStateOf<String?>(null) }
    val scope=rememberCoroutineScope()
    DisposableEffect(store) { store.onSaveError={ message -> notice=message;revision++ };onDispose { store.onSaveError=null } }
    fun refresh() { revision++ }
    /** Library changes the person asked for; a failed save is shown, never a crash. */
    fun change(action:()->Unit) { runCatching(action).onFailure { notice=it.message ?: "Could not save your library." };refresh() }
    fun goHome() { screen="home";refresh() }
    fun open(set:StudySet) { selectedId=set.id;screen="study" }
    val imported=rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        // Reading, parsing and saving a large library takes seconds: keep it off the main thread.
        if(uri!=null) scope.launch {
            val result=withContext(Dispatchers.IO) { runCatching {
                val text=context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() } ?: error("Unable to open this file")
                require(text.length<=20_000_000) { "This file is too large. Import one set at a time." }
                store.importJson(text)
            } }
            notice=result.fold({ "Imported $it sets" }) { it.message ?: "Unable to import this file" };refresh()
        }
    }
    val exported=rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if(uri!=null) scope.launch {
            val result=withContext(Dispatchers.IO) { runCatching {
                val stream=context.contentResolver.openOutputStream(uri) ?: error("Unable to write to that location")
                stream.bufferedWriter().use { it.write(store.exportJson()) }
            } }
            notice=result.fold({ "Library exported" }) { it.message ?: "Unable to export the library" }
        }
    }
    var printing by rememberSaveable { mutableStateOf<String?>(null) }
    val printed=rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/pdf")) { uri ->
        val set=store.library.firstOrNull { it.id==printing }
        printing=null
        if(uri!=null && set!=null) scope.launch {
            val result=withContext(Dispatchers.IO) { runCatching {
                val stream=context.contentResolver.openOutputStream(uri) ?: error("Unable to write to that location")
                stream.use { com.stethoscore.app.export.DeckPdf.write(set,it) }
            } }
            notice=result.fold({ "Printed ${set.name} as a PDF deck ($it pages)" }) { it.message ?: "Unable to print this set" }
        }
    }
    BackHandler(screen!="home") { goHome() }
    // Each part of the app wears its section's colours (WardSection): a set
    // takes its kind's, the brain map Ideas', everywhere else the outside look.
    val section = when(screen) {
        "study" -> store.library.firstOrNull { it.id==selectedId }?.let { WardSection.fromKindRaw(it.kind.rawValue) } ?: WardSection.outside
        "ideas" -> WardSection.ideas
        else -> WardSection.outside
    }
    StethoscoreTheme(dark, section) {
        Surface(Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.background) {
            Box(Modifier.fillMaxSize().safeDrawingPadding()) {
                when(screen) {
                    "study" -> {
                        val set=store.library.firstOrNull { it.id==selectedId }
                        if(set!=null) when(set.kind) {
                            StudySetKind.MCQ -> QuizScreen(set,store,::goHome)
                            StudySetKind.ANKI -> CardsScreen(set,store,::goHome)
                            else -> ClinicalScreen(set,store,::goHome)
                        } else LaunchedEffect(Unit) { goHome() }
                    }
                    "new" -> NewSetScreen({ set -> runCatching { store.addSet(set) }.onSuccess { refresh();open(set) }.onFailure { notice=it.message } },::goHome)
                    "ideas" -> IdeasScreen(store,::goHome)
                    "vitals" -> VitalsScreen(store,::goHome)
                    "settings" -> SettingsScreen(dark,{ dark=it;prefs.edit().putBoolean("dark",it).apply() },{ imported.launch(arrayOf("application/json","text/plain")) },{ exported.launch("stethoscore-library.json") },{ change(store::loadExamples);goHome() },::goHome,reviewSettings,{ next -> runCatching { store.setReviewSettings(next) }.onSuccess { reviewSettings=store.reviewSettings } })
                    else -> Column(Modifier.fillMaxSize()) {
                        Box(Modifier.weight(1f)) {
                            EcgGrid(Modifier.fillMaxWidth().height(250.dp))
                            LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(20.dp,12.dp,20.dp,20.dp),verticalArrangement=Arrangement.spacedBy(22.dp)) {
                                item { Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically) {
                                    SectionLabel("YOUR STUDY WARD")
                                    IconButton(onClick={screen="settings"},Modifier.size(44.dp).border(1.dp,MaterialTheme.colorScheme.outline,RoundedCornerShape(22.dp))) { Icon(Icons.Rounded.Settings,"Settings") }
                                } }
                                item { OutlinedTextField(query,{query=it},Modifier.fillMaxWidth(),placeholder={Text("Search your library",fontSize=14.sp)},leadingIcon={Icon(Icons.Rounded.Search,null)},singleLine=true,shape=RoundedCornerShape(30.dp),colors=OutlinedTextFieldDefaults.colors(unfocusedContainerColor=MaterialTheme.colorScheme.surface.copy(alpha=.9f))) }
                                item { Column(verticalArrangement=Arrangement.spacedBy(6.dp)) {
                                    SectionLabel(LocalDate.now().format(DateTimeFormatter.ofPattern("EEEE, MMMM d",Locale.ENGLISH)))
                                    Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)) { Text("Stethoscore",fontSize=34.sp,fontWeight=FontWeight.Bold,letterSpacing=(-1).sp);PulseLine(Modifier.size(46.dp,24.dp)) }
                                    Text("A little practice. A clearer picture.",color=MaterialTheme.colorScheme.onSurfaceVariant,fontSize=14.sp)
                                } }
                                store.loadError?.let { message -> item { WardCard(Modifier.fillMaxWidth()) {
                                    Icon(Icons.Rounded.ErrorOutline,null,tint=MaterialTheme.colorScheme.error,modifier=Modifier.size(32.dp))
                                    Text("Your library could not be opened",fontSize=20.sp,fontWeight=FontWeight.Bold)
                                    Text(message,color=MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text("Nothing is saved until it opens, so the file is never overwritten. Restart the app to try again.",color=MaterialTheme.colorScheme.onSurfaceVariant)
                                } } }
                                if(store.library.isEmpty() && store.loadError==null) {
                                    item { WardCard(Modifier.fillMaxWidth()) {
                                        Icon(Icons.Rounded.AutoStories,null,tint=MaterialTheme.colorScheme.primary,modifier=Modifier.size(36.dp))
                                        Text("Your ward starts here",fontSize=23.sp,fontWeight=FontWeight.Bold)
                                        Text("Bring your questions, cards and lecture notes together. Your library stays on this device.",color=MaterialTheme.colorScheme.onSurfaceVariant)
                                        WardButton("Explore example sets",{ change(store::loadExamples) },Modifier.fillMaxWidth(),enabled=store.loadError==null)
                                        TextButton(onClick={imported.launch(arrayOf("application/json","text/plain"))}) { Text("Import a Stethoscore library") }
                                    } }
                                } else if(query.isBlank() && category=="Questions") {
                                    item { RoundCard(store,revision,::open) }
                                    item { Row(horizontalArrangement=Arrangement.spacedBy(16.dp)) {
                                        WardCard(Modifier.weight(1f).clickable { screen="vitals" }) { SectionLabel("Vitals");Icon(Icons.Rounded.MonitorHeart,null,tint=MaterialTheme.colorScheme.secondary);Text("Your progress",fontWeight=FontWeight.Bold);Text("From your practice",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }
                                        WardCard(Modifier.weight(1f).clickable { screen="ideas" }) { SectionLabel("Brain map");Icon(Icons.Rounded.Hub,null,tint=MaterialTheme.colorScheme.primary);Text("${store.notes.size} ideas",fontWeight=FontWeight.Bold);Text("Make connections",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }
                                    } }
                                }
                                item { Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically) { SectionLabel(if(query.isBlank()) "Your ${category.lowercase()}" else "Search results");TextButton(onClick={screen="new"}) { Icon(Icons.Rounded.Add,null,Modifier.size(18.dp));Text("New set") } } }
                                val filtered=store.library.filter { set ->
                                    (query.isNotBlank() || when(category) { "Questions" -> set.kind==StudySetKind.MCQ || set.kind==StudySetKind.BOOK; "Cards" -> set.kind==StudySetKind.ANKI;"Cases" -> set.kind==StudySetKind.CASES;"OSCE" -> set.kind==StudySetKind.OSCE;else -> set.kind==StudySetKind.NARRATE }) && (query.isBlank() || "${set.name} ${set.subject} ${set.tags.joinToString()}".contains(query,true))
                                }
                                items(filtered,key={it.id}) { set -> SetRow(set,{open(set)},{ change { store.deleteSet(set.id) } },
                                    if(com.stethoscore.app.export.DeckBuilder.printsAsPdf(set.kind) && set.itemCount>0) ({ printing=set.id;printed.launch(com.stethoscore.app.export.DeckPdf.fileName(set)) }) else null) }
                                if(filtered.isEmpty() && store.library.isNotEmpty()) item { Text(if(query.isNotBlank()) "No matching sets." else "No sets here yet. Create or import one.",color=MaterialTheme.colorScheme.onSurfaceVariant) }
                                item { Text("Study aid · Not for clinical decisions",fontSize=11.sp,color=MaterialTheme.colorScheme.onSurfaceVariant,modifier=Modifier.padding(top=6.dp)) }
                            }
                        }
                        NavigationBar(containerColor=MaterialTheme.colorScheme.surface,tonalElevation=0.dp,modifier=Modifier.border(1.dp,MaterialTheme.colorScheme.outline,RoundedCornerShape(24.dp))) {
                            listOf("Questions" to Icons.Rounded.FactCheck,"Cards" to Icons.Rounded.Style,"Cases" to Icons.Rounded.MedicalServices,"OSCE" to Icons.Rounded.Assignment,"Audio" to Icons.Rounded.GraphicEq,"Ideas" to Icons.Rounded.Lightbulb).forEach { (name,icon) ->
                                NavigationBarItem(selected=category==name,onClick={if(name=="Ideas") screen="ideas" else {category=name;query=""}},icon={Icon(icon,name,Modifier.size(23.dp))},label={Text(name,fontSize=9.sp,maxLines=1)},colors=NavigationBarItemDefaults.colors(indicatorColor=MaterialTheme.colorScheme.primary.copy(alpha=.1f)))
                            }
                        }
                    }
                }
                notice?.let { message -> AlertDialog(onDismissRequest={notice=null},title={Text("Library")},text={Text(message)},confirmButton={TextButton(onClick={notice=null}) {Text("OK")}}) }
            }
        }
    }
}

@Composable private fun RoundCard(store:StudyStore,revision:Int,open:(StudySet)->Unit) {
    val beds=remember(revision) { val due=store.library.filter { it.kind==StudySetKind.ANKI && store.dueCards(it).isNotEmpty() }; (due+store.library.filter { it.kind==StudySetKind.MCQ || it.kind==StudySetKind.BOOK || it.kind==StudySetKind.OSCE }).distinctBy {it.id}.take(3) }
    if(beds.isEmpty()) return
    WardCard(Modifier.fillMaxWidth()) {
        SectionLabel("Today's ward round · ${beds.size} stops")
        beds.forEachIndexed { i,set ->
            Row(Modifier.fillMaxWidth().clickable {open(set)}.padding(vertical=6.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp)) {
                Icon(modeIcon(set.kind),null,tint=if(i==0) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.primary,modifier=Modifier.size(28.dp))
                Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(3.dp)) {
                    SectionLabel("Bed ${i+1} · ${set.subject}")
                    Text(if(set.kind==StudySetKind.ANKI) "${store.dueCards(set).size} cards due" else set.name,fontSize=17.sp,fontWeight=FontWeight.SemiBold,maxLines=2,overflow=TextOverflow.Ellipsis)
                    Text(if(set.kind==StudySetKind.ANKI) "Spaced review" else "${set.kind.label} · ${set.itemCount} ${set.itemNoun}${if(set.itemCount!=1) "s" else ""}",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Icon(Icons.Rounded.ChevronRight,null,tint=MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if(i<beds.lastIndex) HorizontalDivider(color=MaterialTheme.colorScheme.outline.copy(alpha=.35f))
        }
        WardButton("Start ward round",{open(beds.first())},Modifier.fillMaxWidth())
    }
}
fun modeIcon(kind:StudySetKind):ImageVector = when(kind) { StudySetKind.MCQ -> Icons.Rounded.FactCheck;StudySetKind.ANKI -> Icons.Rounded.Style;StudySetKind.BOOK -> Icons.Rounded.AutoStories;StudySetKind.CASES -> Icons.Rounded.MedicalServices;StudySetKind.OSCE -> Icons.Rounded.Assignment;StudySetKind.NARRATE -> Icons.Rounded.GraphicEq }
@Composable private fun SetRow(set:StudySet,open:()->Unit,delete:()->Unit,print:(()->Unit)?=null) {
    var confirm by remember { mutableStateOf(false) }
    WardCard(Modifier.fillMaxWidth()) {
        Row(verticalAlignment=Alignment.CenterVertically) {
            Column(Modifier.weight(1f).clickable(onClick=open),verticalArrangement=Arrangement.spacedBy(7.dp)) { SectionLabel(set.subject);Text(set.name,fontSize=19.sp,fontWeight=FontWeight.SemiBold);Text("${set.kind.label} · ${set.itemCount} ${set.itemNoun}${if(set.itemCount!=1) "s" else ""}",fontSize=12.sp,color=MaterialTheme.colorScheme.onSurfaceVariant) }
            if(print!=null) IconButton(onClick=print) {Icon(Icons.Rounded.PictureAsPdf,"Export ${set.name} as a PDF deck",tint=MaterialTheme.colorScheme.onSurfaceVariant)}
            IconButton(onClick={confirm=true}) {Icon(Icons.Rounded.DeleteOutline,"Delete ${set.name}",tint=MaterialTheme.colorScheme.onSurfaceVariant)}
        }
        WardButton("Open ${set.kind.label.lowercase()}",open,Modifier.fillMaxWidth())
    }
    if(confirm) AlertDialog(onDismissRequest={confirm=false},title={Text("Delete this set?")},text={Text(set.name)},confirmButton={TextButton(onClick={confirm=false;delete()}) {Text("Delete")}},dismissButton={TextButton(onClick={confirm=false}) {Text("Cancel")}})
}
