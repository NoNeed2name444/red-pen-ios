package com.stethoscore.app.ui

import com.stethoscore.app.ui.home.ExamCountdown
import com.stethoscore.app.ui.home.HomeFit
import com.stethoscore.app.ui.home.HomeHeader
import com.stethoscore.app.ui.home.HomePartBook
import com.stethoscore.app.ui.home.HomeRound
import com.stethoscore.app.ui.home.HomeRoundModel
import com.stethoscore.app.ui.home.homePart
import com.stethoscore.app.ui.home.homeRoundItems
import com.stethoscore.app.ui.home.homeShortWindow
import com.stethoscore.app.ui.ward.WardDock
import com.stethoscore.app.ui.ward.WardGround
import com.stethoscore.app.ui.ward.WardLift
import com.stethoscore.app.ui.ward.WardSpace
import com.stethoscore.app.ui.ward.WardTextStyle
import com.stethoscore.app.ui.ward.WardType
import com.stethoscore.app.ui.ward.textStyle
import com.stethoscore.app.ui.ward.wardChosenEdge
import com.stethoscore.app.ui.ward.wardDp
import com.stethoscore.app.ui.ward.wardFrameClearance
import com.stethoscore.app.ui.ward.WardCornerScope
import com.stethoscore.app.ui.ward.rememberWardCorners
import com.stethoscore.app.ui.ward.shape
import com.stethoscore.app.ui.ward.wardInset
import com.stethoscore.app.ui.ward.wardPressFace
import com.stethoscore.app.ui.ward.wardRaised
import com.stethoscore.app.ui.ward.WardPaperFrame
import com.stethoscore.app.ui.ward.WardSection
import com.stethoscore.app.ui.ward.WardToken
import com.stethoscore.app.ui.library.libraryItems

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
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.stethoscore.app.data.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable fun StethoscoreApp(store:StudyStore, initialScreen:String="home", forceDark:Boolean?=null) {
    val context=LocalContext.current
    val prefs=remember { context.getSharedPreferences("appearance",Context.MODE_PRIVATE) }
    // Learn's small marks and the ward round live in SharedPreferences (batch 14)
    remember(context) { com.stethoscore.app.ui.learn.PrefsLearnDefaults.install(context) }
    var dark by remember { mutableStateOf(forceDark ?: prefs.getBoolean("dark",false)) }
    var reviewSettings by remember { mutableStateOf(store.reviewSettings) }
    var screen by rememberSaveable { mutableStateOf(initialScreen) }
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
    var licencesFrom by rememberSaveable { mutableStateOf("settings") }
    var revision by remember { mutableIntStateOf(0) }
    var category by rememberSaveable { mutableStateOf("Questions") }
    var query by rememberSaveable { mutableStateOf("") }
    var notice by remember { mutableStateOf<String?>(null) }
    var nothingDue by remember { mutableStateOf(false) }
    // a quiz put together on the spot (a bed's drill), not in the library
    var quick by remember { mutableStateOf<StudySet?>(null) }
    // the library's own state: picking sets, its menus and sheets, and what it opened
    val lib=remember { com.stethoscore.app.ui.library.LibraryState() }
    var libQuiz by remember { mutableStateOf<com.stethoscore.app.ui.library.LibraryQuiz?>(null) }
    var libReview by remember { mutableStateOf<StudySet?>(null) }
    var shelf by rememberSaveable { mutableStateOf(com.stethoscore.app.ui.library.CategoryFeature.MULTIPLE_CHOICE.rawValue) }
    var newKind by rememberSaveable { mutableStateOf(StudySetKind.MCQ) }
    // the step New set opens on: the first, or the material step from Paste or import
    var newStep by rememberSaveable { mutableStateOf(com.stethoscore.app.ui.library.NewSetStep.KIND) }
    // New set's preset from the exam card's Study next (batch 16)
    var newPreset by remember { mutableStateOf<com.stethoscore.app.exam.NewSetPreset?>(null) }
    val scope=rememberCoroutineScope()
    DisposableEffect(store) { store.onSaveError={ message -> notice=message;revision++ };onDispose { store.onSaveError=null } }
    com.stethoscore.app.ui.learn.LearnHostEffects(store)
    fun refresh() { revision++ }
    /** Library changes the person asked for; a failed save is shown, never a crash. */
    fun change(action:()->Unit) { runCatching(action).onFailure { notice=it.message ?: "Could not save your library." };refresh() }
    fun goHome() { screen="home";newPreset=null;newStep=com.stethoscore.app.ui.library.NewSetStep.KIND;refresh() }
    fun open(set:StudySet) {
        selectedId=set.id;screen="study"
        // a textbook or narrate set opened for the first time: Guess first over it
        if(com.stethoscore.app.ui.learn.GuessFirst.isDue(set)) com.stethoscore.app.ui.learn.LearnRouter.open(com.stethoscore.app.ui.learn.LearnRoute.Pretest(set.id))
    }
    val imported=rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        // Reading, parsing and saving a large library takes seconds: keep it off the main thread.
        if(uri!=null) scope.launch {
            val result=withContext(Dispatchers.IO) { runCatching {
                val text=context.contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() } ?: error("Unable to open this file")
                require(text.length<=20_000_000) { "This file is too large. Import one set at a time." }
                store.importJson(text)
            } }
            notice=result.fold({ "Imported ${BedPlan.counted(it,"set")}" }) { it.message ?: "Couldn’t import that file. Check it’s a Stethoscore library and try again." };refresh()
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
            notice=result.fold({ "Printed ${set.name} as a PDF deck (${BedPlan.counted(it,"page")})" }) { it.message ?: "Unable to print this set" }
        }
    }
    var sharing by rememberSaveable { mutableStateOf<String?>(null) }
    val shared=rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        val set=store.library.firstOrNull { it.id==sharing }
        sharing=null
        if(uri!=null && set!=null) scope.launch {
            val result=withContext(Dispatchers.IO) { runCatching {
                val stream=context.contentResolver.openOutputStream(uri) ?: error("Unable to write to that location")
                stream.bufferedWriter().use { it.write(store.exportSet(set)) }
            } }
            notice=result.fold({ "Saved ${set.name} as a Stethoscore file" }) { it.message ?: "Unable to save this set" }
        }
    }
    val libActions=com.stethoscore.app.ui.library.LibraryActions(
        open=::open,
        quiz={ libQuiz=it;screen="libquiz" },
        review={ libReview=it;screen="libreview" },
        newSet={ newKind=it;screen="newset" },
        shelf={ shelf=it.rawValue;screen="shelf" },
        stats={ screen="stats" },
        due={ if(store.dueAcross().isNotEmpty()) screen="due" else nothingDue=true },
        ideas={ screen="ideas" },
        exportPdf={ set -> printing=set.id;printed.launch(com.stethoscore.app.export.DeckPdf.fileName(set)) },
        shareJson={ set -> sharing=set.id;shared.launch(set.name.replace(Regex("[^A-Za-z0-9 _-]"),"").trim().ifEmpty { "set" }+".json") },
        change=::change,
        edit={ set -> selectedId=set.id;screen="edit" },
        addMaterial={ newKind=com.stethoscore.app.ui.library.StudyCategory.named(category).mainKind;newStep=com.stethoscore.app.ui.library.NewSetStep.MATERIAL;screen="newset" },
    )
    // "Turn into…": an instant set opens straight away, in place of whatever
    // was open; a written one goes to New set, filled in (iOS LibraryView's modeSwitch)
    val modeSwitch=com.stethoscore.app.ui.library.ModeSwitch
    LaunchedEffect(modeSwitch.opening) { modeSwitch.opening?.let { set -> modeSwitch.opening=null;refresh();open(set) } }
    LaunchedEffect(modeSwitch.writing) { modeSwitch.writing?.let { p -> modeSwitch.writing=null;newPreset=p;screen="new" } }
    BackHandler(screen=="home" && lib.selecting) { lib.stopSelecting() }
    BackHandler(screen!="home") { when(screen) { "sources", "exam", "models" -> screen="settings"; "licences" -> screen=licencesFrom; else -> goHome() } }
    // Each part of the app wears its section's colours (WardSection): a set
    // takes its kind's, the brain map Ideas', everywhere else the outside look.
    val section = com.stethoscore.app.ui.learn.LearnRouter.section(store) ?: when(screen) {
        "study" -> store.library.firstOrNull { it.id==selectedId }?.let { WardSection.fromKindRaw(it.kind.rawValue) } ?: WardSection.outside
        "ideas" -> WardSection.ideas
        "due" -> WardSection.cards
        "quick" -> WardSection.fromKindRaw(StudySetKind.MCQ.rawValue)
        "mock" -> WardSection.fromKindRaw(StudySetKind.MCQ.rawValue)
        "photo" -> WardSection.cards
        "edit" -> store.library.firstOrNull { it.id==selectedId }?.let { WardSection.fromKindRaw(it.kind.rawValue) } ?: WardSection.outside
        "libreview" -> WardSection.cards
        "libquiz","stats" -> WardSection.fromKindRaw(StudySetKind.MCQ.rawValue)
        "shelf" -> com.stethoscore.app.ui.library.CategoryFeature.entries.firstOrNull { it.rawValue==shelf }?.shelfKind?.let { WardSection.fromKindRaw(it.rawValue) } ?: WardSection.outside
        "newset" -> WardSection.fromKindRaw(newKind.rawValue)
        // home wears its category's section, opening on Questions (WardSection.opening)
        "home" -> homeSection(category)
        else -> WardSection.outside
    }
    StethoscoreTheme(dark, section) {
        // Home stands on its ground (the section's wash and the paper's grid,
        // counted from the window's top left), the same ground the window's
        // background shows from the first frame (MainActivity), so nothing
        // changes at the hand-over.
        val onGround = screen=="home"
        // the grid only from the window's top to just under the header's
        // last line (iOS HomeBand, HomeBandTrack.belowHeader 10), following
        // the header as the list scrolls; gone with the header
        var bandBottom by remember { mutableStateOf<Float?>(null) }
        if(onGround) WardGroundBackground(WardGround.home(section, dark),Modifier.fillMaxSize(),gridBottom={ bandBottom })
        Surface(Modifier.fillMaxSize(),color=if(onGround) androidx.compose.ui.graphics.Color.Transparent else MaterialTheme.colorScheme.background) { WardCornerScope(framed=!onGround) {
            // a page in the paper's opening sits inside its ring (wardFrameClearance); home has
            // no frame, and the map (ui/map) keeps its own full-bleed layout
            val inFrame=!onGround && screen!="ideas"
            Box(if(inFrame) Modifier.fillMaxSize().wardFrameClearance() else Modifier.fillMaxSize().safeDrawingPadding()) {
                when(screen) {
                    "study" -> {
                        val set=store.library.firstOrNull { it.id==selectedId }
                        if(set!=null) when(set.kind) {
                            StudySetKind.MCQ -> QuizScreen(set,store,::goHome,onOpen={ refresh();open(it) })
                            StudySetKind.ANKI -> AnkiReviewScreen(set,store,::goHome)
                            else -> ClinicalScreen(set,store,::goHome)
                        } else LaunchedEffect(Unit) { goHome() }
                    }
                    // a preset (Coverage's Generate questions, the exam card's Study next) opens New set on
                    // Make with its writer (iOS NewSetView(preset:)); Your lectures' New set is the plain one
                    "new" -> newPreset?.let { p -> key(p) { com.stethoscore.app.ui.library.LibraryNewSetScreen(store,p.kind,::goHome,::goHome,preset=p) } }
                        ?: NewSetScreen({ set -> runCatching { store.addSet(set) }.onSuccess { newPreset=null;refresh();open(set) }.onFailure { notice=it.message } },::goHome,null)
                    "quick" -> quick?.let { q -> QuizScreen(q,store,{ quick=null;goHome() },onOpen={ refresh();open(it) },keepsProgress=false) } ?: LaunchedEffect(Unit) { goHome() }
                    "ideas" -> IdeasScreen(store,::goHome)
                    "vitals" -> VitalsScreen(store,::goHome) { newPreset=it;screen="new" }
                    "mock" -> com.stethoscore.app.ui.mock.MockPaperScreen(store) { goHome() }
                    "due" -> DueTodayScreen(store,::goHome)
                    "libquiz" -> libQuiz?.let { q -> QuizScreen(q.set,store,::goHome,keepsProgress=false,minReadSeconds=q.minReadSeconds,startsTimed=q.timed) } ?: LaunchedEffect(Unit) { goHome() }
                    "libreview" -> libReview?.let { AnkiReviewScreen(it,store,::goHome) } ?: LaunchedEffect(Unit) { goHome() }
                    // the Turn into… tile's page lists the category's sets (iOS TurnIntoListView)
                    "shelf" -> if(shelf==com.stethoscore.app.ui.library.CategoryFeature.TURN.rawValue) com.stethoscore.app.ui.library.TurnIntoListScreen(com.stethoscore.app.ui.library.StudyCategory.named(category).kinds,store,revision,::goHome)
                        else com.stethoscore.app.ui.library.KindShelfScreen(com.stethoscore.app.ui.library.CategoryFeature.entries.first { it.rawValue==shelf },store,revision,::goHome,::open) { newKind=it;screen="newset" }
                    "stats" -> com.stethoscore.app.ui.library.StatsScreen(store,revision,::goHome) { libQuiz=it;screen="libquiz" }
                    "newset" -> com.stethoscore.app.ui.library.LibraryNewSetScreen(store,newKind,::goHome,::goHome,newStep)
                    "edit" -> store.library.firstOrNull { it.id==selectedId }?.let { set -> com.stethoscore.app.ui.editors.CardsEditorScreen(set,store) { refresh();goHome() } } ?: LaunchedEffect(Unit) { goHome() }
                    "photo" -> com.stethoscore.app.ui.editors.PictureFromPhotoScreen(store,{ refresh();goHome() },onOpen={ refresh();open(it) })
                    "settings" -> SettingsScreen(dark,{ dark=it;prefs.edit().putBoolean("dark",it).apply();(context as? android.app.Activity)?.let { a -> com.stethoscore.app.MainActivity.showGround(a,it) } },{ imported.launch(arrayOf("application/json","text/plain")) },{ exported.launch("stethoscore-library.json") },{ change(store::loadExamples);goHome() },::goHome,reviewSettings,{ next -> runCatching { store.setReviewSettings(next) }.onSuccess { reviewSettings=store.reviewSettings } },
                        onSources={ screen="sources" },onLicences={ licencesFrom="settings";screen="licences" },onExam={ screen="exam" },onModels={ screen="models" })
                    "models" -> ModelSettingsScreen({ screen="settings" })
                    // batch 16: Settings, Your exam
                    "exam" -> com.stethoscore.app.ui.exam.ExamPickerScreen(store,{ screen="settings";refresh() })
                    // batch 9: the lectures in the library, the app's own sources, and one set's credits
                    "sources" -> com.stethoscore.app.ui.sources.SourcesLibraryScreen(store,{ screen="settings" },{ screen="new" })
                    "licences" -> com.stethoscore.app.ui.sources.ContentLicencesScreen { screen=licencesFrom }
                    "credits" -> {
                        val set=store.library.firstOrNull { it.id==selectedId }
                        if(set!=null) com.stethoscore.app.ui.sources.SetCreditsScreen(set,::goHome) { licencesFrom="credits";screen="licences" }
                        else LaunchedEffect(Unit) { goHome() }
                    }
                    else -> Box(Modifier.fillMaxSize()) {
                        val libSearch=com.stethoscore.app.ui.library.rememberLibrarySearch(store,revision,query,lib.scope)
                        // home: the header, today's ward round and its tiles (ui/home, iOS WardHome)
                        val shortWindow=homeShortWindow()
                        val home=remember(revision,shortWindow,store.library,com.stethoscore.app.ui.learn.LearnRouter.version) { if(store.library.isEmpty()) null else {
                            val due=store.dueAcross()
                            val situation=com.stethoscore.app.ui.learn.LearnLibrary.examSituation(store,due.size,com.stethoscore.app.ui.mock.MockLibrary.recordsFile(context.filesDir))
                            val input=HomeRound.input(store,due.size,HomeRound.dueSubjects(store,due),situation=situation,track=QuizPrefs.track(context))
                            val all=com.stethoscore.app.data.BedPlan.beds(input)
                            val days=HomeRound.studyDays(store)
                            val (ideas,links)=HomeRound.brainMap(store)
                            due.size to HomeRoundModel(all.take(HomeFit.shownBeds(all.size,shortWindow)),if(input.phase.holdsNewMaterial) input.phase.headline else null,
                                HomeRound.streak(days),com.stethoscore.app.data.RhythmReading.read(days,java.time.Instant.now(),java.time.ZoneId.systemDefault()),ideas,links,
                                com.stethoscore.app.ui.vitals.StoreInsight.readiness(store,due.size,QuizPrefs.track(context)))
                        } }
                        fun openBed(bed:com.stethoscore.app.data.BedPlan.Bed) { when(val kind=bed.kind) {
                            is com.stethoscore.app.data.BedPlan.Kind.DueCards -> screen="due"
                            is com.stethoscore.app.data.BedPlan.Kind.Weakest -> HomeRound.drill(store,kind.topic.name).takeIf { it.questions.isNotEmpty() }?.let { quick=it;screen="quick" }
                            is com.stethoscore.app.data.BedPlan.Kind.Fresh -> store.library.firstOrNull { it.id==kind.set.id }?.let(::open)
                            is com.stethoscore.app.data.BedPlan.Kind.OsceStation -> store.library.firstOrNull { it.id==kind.station.setID }?.let(::open)
                            is com.stethoscore.app.data.BedPlan.Kind.Priority -> when(val start=com.stethoscore.app.ui.learn.launchMission(store,kind.mission)) {
                                com.stethoscore.app.ui.learn.MissionStart.DueCards -> screen="due"
                                is com.stethoscore.app.ui.learn.MissionStart.Quiz -> { quick=start.set;screen="quick" }
                                com.stethoscore.app.ui.learn.MissionStart.Nothing -> Unit
                            }
                        } }
                        val book=remember { HomePartBook() }
                        LaunchedEffect(category,query) { book.clear() }
                        val listState=androidx.compose.foundation.lazy.rememberLazyListState()
                        val atRest by remember { derivedStateOf { !listState.isScrollInProgress && listState.firstVisibleItemIndex==0 && listState.firstVisibleItemScrollOffset==0 } }
                        LaunchedEffect(atRest) { book.settle(atRest) }
                        // The page is not cut above the bottom bar (the owner, 22 Oct: the band
                        // under New set and the tabs was wrong): its rows run on behind New set
                        // and the dock to the window's bottom edge, and the row that ends the
                        // list lets the last one scroll clear of them (HomeFit.endSpace). No
                        // soft edge under the bar either: nothing at the bottom fades.
                        var barHeight by remember { mutableStateOf(0.0) }
                            LazyColumn(Modifier.fillMaxSize(),state=listState,contentPadding=PaddingValues(WardSpace.gutter.wardDp,WardSpace.m.wardDp,WardSpace.gutter.wardDp,WardSpace.xl.wardDp),verticalArrangement=Arrangement.spacedBy(WardSpace.section.wardDp)) {
                                item { Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically) {
                                    SectionLabel("YOUR STUDY WARD")
                                    // a Ward circle, as iOS's toolbar button beside the search (.wardCircle)
                                    com.stethoscore.app.ui.ward.WardCircleButton(Icons.Rounded.Settings,"Settings",{ screen="settings" })
                                } }
                                // the search in a Ward well with its magnifier, as iOS's searchField (.wardField)
                                item { com.stethoscore.app.ui.ward.WardTextField(query,{query=it},Modifier.fillMaxWidth().semantics { contentDescription="Search" },
                                    placeholder="Search questions, cards, notes",leadingIcon=Icons.Rounded.Search) }
                                item {
                                    val below=with(androidx.compose.ui.platform.LocalDensity.current) { HomeFit.belowHeader.dp.toPx() }
                                    DisposableEffect(Unit) { onDispose { bandBottom=null } }
                                    HomeHeader(remember(revision) { ExamCountdown.text(store.examDate,examName=ExamCountdown.examName(com.stethoscore.app.exam.ExamChoice.defaults(context))) },
                                        Modifier.onGloballyPositioned { bandBottom=it.positionInWindow().y+it.size.height+below })
                                }
                                store.loadError?.let { message -> item { WardCard(Modifier.fillMaxWidth()) {
                                    Icon(Icons.Rounded.ErrorOutline,null,tint=MaterialTheme.colorScheme.error,modifier=Modifier.size(32.dp))
                                    Text("Your library could not be opened",style=WardType.title.textStyle())
                                    Text(message,color=MaterialTheme.colorScheme.onSurfaceVariant)
                                    Text("Nothing is saved until it opens, so the file is never overwritten. Restart the app to try again.",color=MaterialTheme.colorScheme.onSurfaceVariant)
                                } } }
                                if(store.library.isEmpty() && store.loadError==null) {
                                    item { WardCard(Modifier.fillMaxWidth()) {
                                        Icon(Icons.Rounded.AutoStories,null,tint=MaterialTheme.colorScheme.primary,modifier=Modifier.size(36.dp))
                                        Text("Make your first set",style=WardType.title.textStyle())
                                        Text("Add a lecture and Stethoscore turns it into questions or flashcards to study.",color=MaterialTheme.colorScheme.onSurfaceVariant)
                                        WardButton("Explore example sets",{ change(store::loadExamples) },Modifier.fillMaxWidth(),enabled=store.loadError==null)
                                        TextButton(onClick={imported.launch(arrayOf("application/json","text/plain"))}) { Text("Import a Stethoscore library") }
                                    } }
                                } else if(home!=null && query.isBlank() && (category=="Questions" || (category=="Cards" && home.first>0))) {
                                    // the round on Questions, and on Cards while cards are due; the tiles on Questions
                                    homeRoundItems(home.second,category=="Questions",book,::openBed,{ screen="vitals" },{ screen="ideas" },
                                        onPlan={ com.stethoscore.app.ui.learn.LearnRouter.open(com.stethoscore.app.ui.learn.LearnRoute.ExamPlan) })
                                    if(category=="Questions") item { com.stethoscore.app.ui.exam.ExamDashboardCard(store,revision,{ newPreset=it;screen="new" }) }
                                    if(category=="Questions") item { com.stethoscore.app.ui.mock.MockPaperTile({ screen="mock" }) }
                                }
                                if(query.isBlank() && category=="Cards" && store.library.isNotEmpty()) item { DueCardsTile(store,revision) { if(store.dueAcross().isNotEmpty()) screen="due" else nothingDue=true } }
                                if(query.isBlank() && category=="Cards" && store.loadError==null) item { com.stethoscore.app.ui.editors.PhotoCardsTile({ screen="photo" },Modifier.fillMaxWidth()) }
                                // the library: its sets, folders, search and practice tiles (iOS LibraryView and LibraryRows), each row a part of home's book
                                libraryItems(store,revision,com.stethoscore.app.ui.library.StudyCategory.named(category),query,libSearch,lib,libActions,
                                    rowModifier={ set -> Modifier.homePart(book,"set-${set.id}","a set row") },showsEmpty=false)
                                item { Text("Study aid · Not for clinical decisions",style=WardTextStyle.caption2.textStyle(),color=MaterialTheme.colorScheme.onSurfaceVariant,modifier=Modifier.padding(top=6.dp)) }
                                // the page is not cut above the bar, so this row is what lets the last tile scroll wholly clear of it (HomeFit.endSpace)
                                item { Spacer(Modifier.fillMaxWidth().height(HomeFit.endSpace(barHeight).dp)) }
                            }
                        // New set and the dock float on the page itself, with nothing behind them
                        // but the page: no strip, no line, no cut of the rows above them, so the
                        // page reads unbroken to the bottom (the owner, 9 and 22 Oct). Without a
                        // glow round them, only their edges (iOS wardUnlit).
                        val barDensity=androidx.compose.ui.platform.LocalDensity.current.density
                        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().onGloballyPositioned { barHeight=(it.size.height/barDensity).toDouble() }) { com.stethoscore.app.ui.ward.WardUnlit {
                        // New set on its own row over the dock, at the trailing end, once there is something to list (iOS newSetRow)
                        if(!lib.selecting && store.library.isNotEmpty()) Row(Modifier.fillMaxWidth().padding(horizontal=16.dp,vertical=6.dp),horizontalArrangement=Arrangement.End) {
                            com.stethoscore.app.ui.ward.WardButtonBox({ newKind=com.stethoscore.app.ui.library.StudyCategory.named(category).mainKind;screen="newset" },
                                Modifier.semantics { contentDescription="New set. Make questions or cards from a lecture" },fills=false) {
                                Icon(Icons.Rounded.Add,null,Modifier.size(18.dp));Text("New set")
                            }
                        }
                        if(lib.selecting) com.stethoscore.app.ui.library.LibrarySelectionBar(store,lib,libActions)
                        else CategoryDock(category,{ name -> if(name=="Ideas") screen="ideas" else {category=name;query="";lib.stopSelecting()} })
                        } }
                    }
                }
                if(screen=="home") {
                    com.stethoscore.app.ui.library.LibraryOverlays(store,lib,libActions)
                    com.stethoscore.app.ui.library.IncomingImportHost(store,busy=notice!=null || lib.naming!=null || lib.session!=null || lib.pendingDelete!=null || lib.turning!=null,onChanged=::refresh,
                        onLecture={ newPreset=it;screen="new" })
                }
                if(nothingDue) AlertDialog(onDismissRequest={nothingDue=false},title={Text("Nothing here yet")},text={Text("No cards are due right now. Come back later.")},confirmButton={TextButton(onClick={nothingDue=false}) {Text("Done")}})
                notice?.let { message -> AlertDialog(onDismissRequest={notice=null},title={Text("Library")},text={Text(message)},confirmButton={TextButton(onClick={notice=null}) {Text("Done")}}) }
            }
            // a learning screen over the app, in a sheet of its own (LearnRoutes): its face fills
            // the window, its screen sits inside the frame's ring
            com.stethoscore.app.ui.learn.LearnSheet(store,dark,section,onPreset={ com.stethoscore.app.ui.learn.LearnRouter.close();newPreset=it;screen="new" }) { set -> refresh();open(set) }
            // Every page but home stands in the paper's opening (iOS WardPaperFrame):
            // still ECG paper round the window, the page scrolling beneath it.
            if(!onGround) WardPaperFrame(Modifier.fillMaxSize())
            // a ward round's chip, over every screen while one runs
            com.stethoscore.app.ui.learn.WardRoundFloat()
        } }
    }
}

/** The Cards page's "Due cards" tile: every deck's waiting cards in one queue (iOS CategoryFeature.due). */
@Composable private fun DueCardsTile(store:StudyStore,revision:Int,open:()->Unit) {
    val due=remember(revision) { store.dueCount() }
    WardCard(Modifier.fillMaxWidth().clickable(onClick=open)) {
        Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp)) {
            Icon(Icons.Rounded.Inbox,null,tint=MaterialTheme.colorScheme.primary,modifier=Modifier.size(28.dp))
            Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(3.dp)) {
                Text("Due cards",style=WardType.headline.textStyle())
                Text(if(due>0) "Cards waiting today \u00B7 $due" else "Cards waiting today",style=WardType.caption.textStyle(),color=MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Icon(Icons.Rounded.ChevronRight,null,tint=MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

fun modeIcon(kind:StudySetKind):ImageVector = when(kind) { StudySetKind.MCQ -> Icons.Rounded.FactCheck;StudySetKind.ANKI -> Icons.Rounded.Style;StudySetKind.BOOK -> Icons.Rounded.AutoStories;StudySetKind.CASES -> Icons.Rounded.MedicalServices;StudySetKind.OSCE -> Icons.Rounded.Assignment;StudySetKind.NARRATE -> Icons.Rounded.GraphicEq }

/** Home's section for a dock category (WardSection.opening for Questions, the first). */
fun homeSection(category:String):WardSection = when(category) {
    "Cards" -> WardSection.cards
    "Cases" -> WardSection.cases
    "OSCE" -> WardSection.osce
    "Audio" -> WardSection.audio
    else -> WardSection.opening
}

/**
 * Home's dock along the bottom (iOS CategoryDock): the five categories on a
 * panel of WardDock's radius, and Ideas on a pill of its own beside it, the
 * bar at most WardDock.barMaxWidth wide. The chosen tab's hollow and ring are
 * concentric with the panel, their radius the panel's less the inset between
 * them, so the two corners run parallel. Each tab keeps WardDock's room round
 * its symbol and name, so the name always sits inside the ring, clear of its
 * corners; short of width, the five names shrink alike (WardDock.tabWidths,
 * to WardDock.leastNameScale at the least) rather than crossing the ring.
 */
@Composable fun CategoryDock(chosen:String,choose:(String)->Unit) {
    val inset=WardDock.barInset
    val tab=RoundedCornerShape(WardDock.tabRadius(inset).toFloat().dp)
    val categories=listOf("Questions" to Icons.Outlined.FactCheck,"Cards" to Icons.Outlined.Style,"Cases" to Icons.Outlined.MedicalServices,"OSCE" to Icons.Outlined.Assignment,"Audio" to Icons.Outlined.GraphicEq)
    // One hollow travels between the five with the choice, never past the tab it goes to (iOS StudyCategory.swift:748:
    // .snappy(duration: 0.3)), and with animations off it is simply there. On Ideas there is none; back from Ideas it
    // is simply there, as iOS's appears.
    val at=categories.indexOfFirst { it.first==chosen }
    val reduce=com.stethoscore.app.ui.ward.wardReduceMotion()
    val hollow=remember { androidx.compose.animation.core.Animatable(maxOf(at,0).toFloat()) }
    val was=remember { mutableIntStateOf(at) }
    LaunchedEffect(at) {
        val from=was.intValue
        was.intValue=at
        if(at<0) return@LaunchedEffect
        if(reduce || from<0) hollow.snapTo(at.toFloat())
        else hollow.animateTo(at.toFloat(),com.stethoscore.app.ui.ward.wardSpring(com.stethoscore.app.ui.ward.WardMotion.travel,reduce))
    }
    // the panel and the Ideas pill sit at the screen's bottom corners: concentric with the display's (WardCorner.radii)
    val (panelAt,panelCorners)=rememberWardCorners(WardDock.panelRadius)
    val (ideasAt,ideasCorners)=rememberWardCorners(WardDock.panelRadius)
    Box(Modifier.fillMaxWidth().padding(horizontal=WardDock.barSide.toFloat().dp).padding(bottom=10.dp),contentAlignment=Alignment.Center) {
        Row(Modifier.widthIn(max=WardDock.barMaxWidth.toFloat().dp).fillMaxWidth().height(IntrinsicSize.Min),
            horizontalArrangement=Arrangement.spacedBy(WardDock.barSpacing.toFloat().dp)) {
            // raised high on its rim with the ink edge, as iOS's panel (wardRaised lift high, control)
            DockSlots(Modifier.weight(1f).then(panelAt)
                .wardRaised(panelCorners,WardLift.high,control=true)
                .padding(WardDock.barInset.toFloat().dp).selectableGroup(),
                hollowAt={ if(at<0) null else if(was.intValue<0) at.toFloat() else hollow.value }) {
                // the chosen tab's hollow with the accent's ring: one, under the five, where the choice is
                Box(Modifier.wardChosenEdge(tab,true).wardInset(tab,WardLift.low))
                categories.forEach { (name,rest) ->
                    val selected=chosen==name
                    val source=remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
                    val held by source.collectIsPressedAsState()
                    // the chosen tab stands in the hollow; a held one sinks into a hollow of its own (iOS WardItemButtonStyle); no ripple
                    Column(Modifier
                        .then(if(held && !selected) Modifier.wardInset(tab,WardLift.low) else Modifier)
                        .selectable(selected=selected,interactionSource=source,indication=null,role=androidx.compose.ui.semantics.Role.Tab,onClick={ choose(name) })
                        .heightIn(min=WardDock.tabMinHeight.toFloat().dp)
                        .padding(horizontal=WardDock.labelSide.toFloat().dp,vertical=WardDock.labelVertical.toFloat().dp),
                        horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.Center) {
                        DockItemFace(rest,name,selected)
                    }
                }
            }
            // Ideas, on a panel of its own beside the categories: pressed in with the accent edge when chosen, sinking when held
            val source=remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
            val held by source.collectIsPressedAsState()
            val ideas=chosen=="Ideas"
            val ideasShape=ideasCorners.shape()
            Column(Modifier.width(WardDock.ideasWidth.toFloat().dp).fillMaxHeight().heightIn(min=56.dp).then(ideasAt)
                .wardChosenEdge(ideasShape,ideas)
                .wardPressFace(ideasShape,WardLift.high,com.stethoscore.app.ui.ward.wardDepth(ideas || held))
                .selectable(selected=ideas,interactionSource=source,indication=null,role=androidx.compose.ui.semantics.Role.Tab,onClick={ choose("Ideas") }),
                horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.Center) {
                DockItemFace(if(ideas) Icons.Rounded.Lightbulb else Icons.Outlined.Lightbulb,"Ideas",ideas)
            }
        }
    }
}

/**
 * The tabs side by side in WardDock's slots: each its ideal width (its name and side room, never under WardDock.leastTab),
 * water-filled or shrunk alike to fit (WardDock.tabWidths). The first child is the chosen hollow, laid under the tabs where
 * [hollowAt] has it (WardDock.hollow), or not at all when that is null. Only this layout reads where it is, never the bar's
 * sizing, so its travel neither recomposes the dock nor measures the bar again.
 */
@Composable private fun DockSlots(modifier:Modifier,hollowAt:() -> Float?,content:@Composable () -> Unit) {
    val policy=remember(hollowAt) { DockSlotsPolicy(hollowAt) }
    androidx.compose.ui.layout.Layout(content,modifier,policy)
}

private class DockSlotsPolicy(private val hollowAt:() -> Float?):androidx.compose.ui.layout.MeasurePolicy {
    /** Each tab's slot in [maxWidth] (their ideals when it is unbounded), in pixels. */
    private fun androidx.compose.ui.unit.Density.slots(tabs:List<androidx.compose.ui.layout.IntrinsicMeasurable>,maxWidth:Int):List<Int> {
        val ideals=tabs.map { maxOf(WardDock.leastTab,it.maxIntrinsicWidth(Int.MAX_VALUE).toDouble()/density) }
        val room=if(maxWidth!=androidx.compose.ui.unit.Constraints.Infinity) maxWidth.toDouble()/density else ideals.sum()
        return WardDock.tabWidths(ideals,room).map { (it*density).toInt() }
    }

    /** The row's height: the tallest tab in its slot. */
    private fun tallest(tabs:List<androidx.compose.ui.layout.IntrinsicMeasurable>,slots:List<Int>):Int =
        tabs.zip(slots).maxOfOrNull { (m,w) -> m.minIntrinsicHeight(w) } ?: 0

    override fun androidx.compose.ui.layout.MeasureScope.measure(measurables:List<androidx.compose.ui.layout.Measurable>,
                                                                 constraints:androidx.compose.ui.unit.Constraints):androidx.compose.ui.layout.MeasureResult {
        val tabs=measurables.drop(1)
        val slots=slots(tabs,constraints.maxWidth)
        val height=tallest(tabs,slots).coerceAtLeast(constraints.minHeight)
        val placeables=tabs.zip(slots).map { (m,w) -> m.measure(androidx.compose.ui.unit.Constraints.fixed(w,height)) }
        val span=hollowAt()?.let { WardDock.hollow(slots.map { w -> w.toDouble() },it.toDouble()) }
        val hollow=span?.let { measurables.first().measure(androidx.compose.ui.unit.Constraints.fixed(kotlin.math.round(it.width).toInt(),height)) }
        return layout(if(constraints.hasBoundedWidth) constraints.maxWidth else slots.sum(),height) {
            if(span!=null && hollow!=null) hollow.placeRelative(kotlin.math.round(span.left).toInt(),0)
            var x=0
            placeables.forEach { it.placeRelative(x,0);x+=it.width }
        }
    }

    // the bar's sizing asks only the tabs, never where the hollow is
    override fun androidx.compose.ui.layout.IntrinsicMeasureScope.minIntrinsicHeight(measurables:List<androidx.compose.ui.layout.IntrinsicMeasurable>,width:Int):Int =
        measurables.drop(1).let { tabs -> tallest(tabs,slots(tabs,width)) }
    override fun androidx.compose.ui.layout.IntrinsicMeasureScope.maxIntrinsicHeight(measurables:List<androidx.compose.ui.layout.IntrinsicMeasurable>,width:Int):Int =
        minIntrinsicHeight(measurables,width)
    override fun androidx.compose.ui.layout.IntrinsicMeasureScope.minIntrinsicWidth(measurables:List<androidx.compose.ui.layout.IntrinsicMeasurable>,height:Int):Int =
        slots(measurables.drop(1),androidx.compose.ui.unit.Constraints.Infinity).sum()
    override fun androidx.compose.ui.layout.IntrinsicMeasureScope.maxIntrinsicWidth(measurables:List<androidx.compose.ui.layout.IntrinsicMeasurable>,height:Int):Int =
        minIntrinsicWidth(measurables,height)
}

/** One dock item's face: an outline glyph over its name, Chart Ink at rest and the section's ink when chosen (iOS DockItemFace). The name keeps to one line, shrinking to WardDock.leastNameScale before it would cross the ring. */
@Composable private fun DockItemFace(icon:ImageVector,name:String,selected:Boolean) {
    val tint=if(selected) wardColor(WardToken.primaryInk) else wardColor(WardToken.ink)
    Icon(icon,null,Modifier.size(23.dp),tint=tint)
    Spacer(Modifier.height(3.dp))
    androidx.compose.foundation.text.BasicText(name,maxLines=1,softWrap=false,
        style=androidx.compose.ui.text.TextStyle(color=tint,fontSize=11.sp,fontWeight=FontWeight.Bold),
        autoSize=androidx.compose.foundation.text.TextAutoSize.StepBased(minFontSize=(11*WardDock.leastNameScale).sp,maxFontSize=11.sp,stepSize=0.25.sp))
}
