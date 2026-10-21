package com.stethoscore.app.ui.learn

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.stethoscore.app.data.ExamWeekPlanner
import com.stethoscore.app.data.LearnDefaults
import com.stethoscore.app.data.StudySet
import com.stethoscore.app.data.StudyStore
import com.stethoscore.app.ui.home.HomeRound

// What the app's root needs from Learn: the device's small marks kept in
// SharedPreferences (iOS UserDefaults.standard), the ward round's clock kept
// in step with the app coming and going and with what is studied, and home's
// mission started (LibraryRows.launch).

/** LearnDefaults on SharedPreferences. */
internal class PrefsLearnDefaults(private val prefs: SharedPreferences) : LearnDefaults {
    override fun string(key: String): String? = prefs.getString(key, null)
    override fun set(key: String, value: String?) {
        prefs.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    }

    companion object {
        const val file = "learn"
        /** Once, before anything reads a mark. */
        fun install(context: Context) {
            if (LearnDefaults.shared is PrefsLearnDefaults) return
            LearnDefaults.shared = PrefsLearnDefaults(context.applicationContext.getSharedPreferences(file, Context.MODE_PRIVATE))
        }
    }
}

/**
 * The ward round's clock, kept in step: a round left running is picked up,
 * what is studied counts on it, and whatever ended while the app was away is
 * caught up when it comes back.
 */
@Composable internal fun LearnHostEffects(store: StudyStore) {
    LaunchedEffect(Unit) { WardRoundClock.restore() }
    DisposableEffect(store) {
        store.onStudied = { count -> WardRoundClock.studied(count) }
        onDispose { store.onStudied = null }
    }
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner) {
        val watch = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> WardRoundClock.returned()
                Lifecycle.Event.ON_PAUSE -> WardRoundClock.inFront = false
                else -> Unit
            }
        }
        owner.lifecycle.addObserver(watch)
        onDispose { owner.lifecycle.removeObserver(watch) }
    }
}

/** What starting a mission asks of the library's own screens. */
internal sealed class MissionStart {
    data object Nothing : MissionStart()
    /** The due cards, on the library's own screen. */
    data object DueCards : MissionStart()
    /** A quiz put together on the spot. */
    data class Quiz(val set: StudySet) : MissionStart()
}

/**
 * Starts a mission (LibraryRows.launch): the due cards and quick quizzes on
 * the library's own screens, everything else through LearnRouter.
 */
internal fun launchMission(store: StudyStore, mission: ExamWeekPlanner.Mission): MissionStart = when (mission) {
    ExamWeekPlanner.Mission.ExamKit -> { LearnRouter.open(LearnRoute.ExamKit); MissionStart.Nothing }
    is ExamWeekPlanner.Mission.MorningCheck -> { LearnRouter.open(LearnRoute.MorningCheck); MissionStart.Nothing }
    is ExamWeekPlanner.Mission.DueCards -> MissionStart.DueCards
    // the real paper; marked sat only when a sitting is finished
    ExamWeekPlanner.Mission.Mock -> { LearnRouter.open(LearnRoute.MockPaper); MissionStart.Nothing }
    is ExamWeekPlanner.Mission.ConfidentErrors -> MissionStart.Quiz(LearnLibrary.confidentMistakesQuiz(store))
    is ExamWeekPlanner.Mission.Mistakes -> MissionStart.Quiz(LearnLibrary.mistakesQuiz(store))
    is ExamWeekPlanner.Mission.LockIn -> MissionStart.Quiz(LearnLibrary.lockInQuiz(store))
    is ExamWeekPlanner.Mission.Flagged -> LearnLibrary.flaggedQuiz(store)?.let { MissionStart.Quiz(it) } ?: MissionStart.Nothing
    is ExamWeekPlanner.Mission.Weakest -> MissionStart.Quiz(HomeRound.drill(store, mission.subject))
    ExamWeekPlanner.Mission.NewQuestions -> MissionStart.Quiz(LearnLibrary.untriedQuiz(store))
    ExamWeekPlanner.Mission.Nothing -> MissionStart.Nothing
}
