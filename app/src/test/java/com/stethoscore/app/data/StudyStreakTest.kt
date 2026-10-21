package com.stethoscore.app.data

import com.stethoscore.app.ui.ward.checks
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.abs

// The home parts of upstream/ios/RedPen/Tests/WardRoundTests.swift: the
// daily goal and the streak, case for case. (The ward-round clock checks
// belong to batch 14.)
class StudyStreakTest {
    @Test fun theDailyGoal() = checks {
        check("goal label", GoalProgress(done = 32, goal = 50).label == "32 / 50 today")
        check("goal fraction", abs(GoalProgress(done = 32, goal = 50).fraction - 0.64) < 0.0001)
        check("goal ring stops at full", GoalProgress(done = 80, goal = 50).fraction == 1.0)
        check("goal met", GoalProgress(done = 50, goal = 50).met && !GoalProgress(done = 49, goal = 50).met)
        check("no goal, no ring", GoalProgress(done = 5, goal = 0).fraction == 0.0 && !GoalProgress(done = 5, goal = 0).met)
        check("stored goal: nothing stored reads 50", GoalProgress.goal(stored = 0) == 50)
        check("stored goal: held to the range", GoalProgress.goal(stored = 3) == 10 && GoalProgress.goal(stored = 5000) == 300)
        check("stored goal: a chosen goal is kept", GoalProgress.goal(stored = 120) == 120)
        val before = DailyGoal.store
        val goalDefaults = DailyGoal.MemoryStore()
        DailyGoal.store = goalDefaults
        try {
            goalDefaults.remove(DailyGoal.key)
            check("goal defaults to 50", DailyGoal.current == 50)
            DailyGoal.current = 5
            check("goal held to the bottom of the range", DailyGoal.current == 10, "${DailyGoal.current}")
            DailyGoal.current = 1000
            check("goal held to the top of the range", DailyGoal.current == 300, "${DailyGoal.current}")
            DailyGoal.current = 70
            check("goal kept", DailyGoal.current == 70)
            check("the ring reads what Settings stored the way DailyGoal does",
                GoalProgress.goal(stored = goalDefaults.int(DailyGoal.key)) == DailyGoal.current)
            goalDefaults.remove(DailyGoal.key)
        } finally {
            DailyGoal.store = before
        }
    }

    private fun streak(days: List<Int>, today: Int) = StudyStreak.run(days.toSet(), today)

    @Test fun theStreakOnDayNumbers() = checks {
        check("nothing studied", streak(listOf(), today = 10).streak == 0)
        check("a plain run ending today", streak(listOf(8, 9, 10), today = 10).streak == 3)
        check("a run ending yesterday is alive before today's first card", streak(listOf(7, 8, 9), today = 10).streak == 3)
        val oneOff = streak(listOf(5, 6, 8, 9, 10), today = 10)
        check("one missed day is a rest day", oneOff.streak == 5 && oneOff.rests == listOf(7), "$oneOff")
        check("a rest day used means none is ready", !oneOff.restReady)
        val yesterdayOff = streak(listOf(7, 8), today = 10)
        check("yesterday missed: the run lives while today can still close it",
            yesterdayOff.streak == 2 && yesterdayOff.rests == listOf(9), "$yesterdayOff")
        val twoOff = streak(listOf(5, 6, 9, 10), today = 10)
        check("two missed days end it and use no rest day", twoOff.streak == 2 && twoOff.rests.isEmpty(), "$twoOff")
        check("two missed days before today end it", streak(listOf(6, 7), today = 10).streak == 0)
        val twiceInAWeek = streak(listOf(1, 3, 4, 6, 7), today = 7)
        check("a second rest day inside a week is not covered",
            twiceInAWeek.streak == 2 && twiceInAWeek.rests == listOf(2), "$twiceInAWeek")
        val weekApart = streak(listOf(1, 3, 4, 5, 6, 7, 8, 9, 11), today = 11)
        check("rest days a week apart are both covered",
            weekApart.streak == 9 && weekApart.rests == listOf(2, 10), "$weekApart")
        check("a rest day is ready again a week later", streak(listOf(1, 3, 4, 5, 6, 7, 8, 9), today = 9).restReady)
        check("and not six days later", !streak(listOf(1, 3, 4, 5, 6, 7, 8), today = 8).restReady)
        check("a gap before anything was studied is no rest day", streak(listOf(5), today = 5).rests.isEmpty())
    }

    @Test fun theStreakOnRealDates() = checks {
        val utc = ZoneId.of("UTC")
        val today = ZonedDateTime.of(2026, 9, 25, 9, 0, 0, 0, utc).toInstant()
        check("key format", StudyStreak.key(today, utc) == "2026-09-25")
        val keyed = StudyStreak.summary(setOf("2026-09-22", "2026-09-23", "2026-09-25"), today, utc)
        check("keys: a rest day on the 24th", keyed.streak == 3 && keyed.restDays == setOf("2026-09-24"), "$keyed")
        check("keys: future and junk keys ignored",
            StudyStreak.summary(setOf("2026-09-25", "2026-09-26", "junk"), today, utc).streak == 1)
        val acrossMonths = StudyStreak.summary(setOf("2026-08-30", "2026-08-31", "2026-09-02"), today, utc)
        check("keys: across a month end, a gap of 23 days ends it", acrossMonths.streak == 0, "$acrossMonths")
        val monthEnd = ZonedDateTime.of(2026, 9, 2, 20, 0, 0, 0, utc).toInstant()
        val bridgesMonth = StudyStreak.summary(setOf("2026-08-30", "2026-08-31", "2026-09-02"), monthEnd, utc)
        check("keys: a rest day on the 1st bridges the month", bridgesMonth.streak == 3 &&
            bridgesMonth.restDays == setOf("2026-09-01"), "$bridgesMonth")

        // summer time: London moves its clocks on 29 March 2026
        val london = ZoneId.of("Europe/London")
        val afterChange = ZonedDateTime.of(2026, 3, 30, 8, 0, 0, 0, london).toInstant()
        val dst = StudyStreak.summary(setOf("2026-03-27", "2026-03-28", "2026-03-29", "2026-03-30"), afterChange, london)
        check("summer time does not break a run", dst.streak == 4 && dst.restDays.isEmpty(), "$dst")
        val n1 = StudyStreak.dayNumber("2026-03-29", london) ?: 0
        val n2 = StudyStreak.dayNumber("2026-03-30", london) ?: 0
        check("consecutive days are one apart across the change", n2 - n1 == 1, "$n1 $n2")
        val back = StudyStreak.key(StudyStreak.date(n1, london), london)
        check("a day number turns back into its key", back == "2026-03-29", back)
    }
}
