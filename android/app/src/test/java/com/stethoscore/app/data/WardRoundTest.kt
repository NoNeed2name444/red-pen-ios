package com.stethoscore.app.data

import com.stethoscore.app.data.WardRound.Event
import com.stethoscore.app.data.WardRound.Phase
import com.stethoscore.app.ui.ward.checks
import org.junit.Test
import kotlin.math.abs

// The focus-session clock parts of ios/RedPen/Tests/WardRoundTests.swift
// (blocks, breaks, pausing, a locked phone coming back, stopping early),
// case for case. The goal and streak parts are in StudyStreakTest.
//
// Swift mutates the round in place and returns the events; the Kotlin value
// returns a Step (the new round and the events), so each `round.advance`
// below is followed by taking the new round back.
class WardRoundTest {
    // Date(timeIntervalSinceReferenceDate: 800_000_000), in epoch ms
    private val t0: Long = (978_307_200L + 800_000_000L) * 1000L

    private fun at(minutes: Double): Long = t0 + (minutes * 60_000).toLong()
    private fun at(minutes: Int): Long = at(minutes.toDouble())

    @Test fun thePlan() = checks {
        val standard = WardRoundPlan.standard
        check("standard is 25 on, 5 off, 4 rounds",
            standard.focusMinutes == 25 && standard.breakMinutes == 5 && standard.rounds == 4)
        val silly = WardRoundPlan(focusMinutes = 0, breakMinutes = 900, rounds = 99)
        check("a stored plan is held to sane values",
            silly.focusMinutes == 1 && silly.breakMinutes == 30 && silly.rounds == 8, "$silly")
        check("choices", WardRoundPlan.focusChoices == listOf(25, 50) && WardRoundPlan.breakChoices == listOf(5, 10))
    }

    @Test fun aRoundFromStartToFinish() = checks {
        val standard = WardRoundPlan.standard
        var round = WardRound.begin(standard, t0)
        check("starts on round 1, focusing", round.round == 1 && round.phase == Phase.Focus)
        check("full clock at the start", round.remaining(t0) == 25.0 * 60)
        check("ring full at the start", round.leftFraction(t0) == 1.0)
        check("ring half way", abs(round.leftFraction(at(12.5)) - 0.5) < 0.0001)
        check("clock text at the start", WardRound.clock(round.remaining(t0)) == "25:00")
        check("clock text rounds up", WardRound.clock(0.2) == "0:01" && WardRound.clock(760.0) == "12:40")
        var step = round.advance(at(24.9))
        round = step.round
        check("nothing ends early", step.events.isEmpty() && round.phase == Phase.Focus)

        round = round.noteStudied(3)
        round = round.noteStudied(0)
        check("items counted while focusing", round.items == 3)
        val twelveForty = t0 + 740_000L
        check("caption", round.caption(twelveForty) == "Block 1 of 4 · 12:40 · 3 cards",
            round.caption(twelveForty))

        step = round.advance(at(26)); round = step.round
        var events = step.events
        check("round 1 ends into its break",
            events == listOf(Event.FocusEnded(1, 1500.0, at(25))) && round.phase == Phase.Rest, "$events")
        check("the break runs from when the round ran out, not from now", round.remaining(at(26)) == 4.0 * 60)
        round = round.noteStudied(5)
        check("items in a break are not the round's", round.items == 3)
        check("break caption", round.caption(at(26)).startsWith("Break · 4:00"), round.caption(at(26)))

        step = round.advance(at(31)); round = step.round; events = step.events
        check("the break ends and waits", events == listOf(Event.RestEnded(1)) && round.phase == Phase.Ready, "$events")
        check("waiting has no clock", round.remaining(at(40)) == 0.0 && !round.ticks)
        step = round.advance(at(500)); round = step.round
        check("waiting does not move on by itself", step.events.isEmpty() && round.phase == Phase.Ready)
        check("ready caption", round.caption(at(40)).startsWith("Block 2 of 4 when you"), round.caption(at(40)))

        round = round.startNext(at(40))
        check("round 2 starts when asked",
            round.round == 2 && round.phase == Phase.Focus && round.remaining(at(40)) == 25.0 * 60)

        // a locked phone coming back: the phone is put away mid round 2 and
        // picked up long after its break
        step = round.advance(at(90)); round = step.round; events = step.events
        check("the round and its break both end on the way", events == listOf(
            Event.FocusEnded(2, 1500.0, at(65)), Event.RestEnded(2)) && round.phase == Phase.Ready, "$events")
        check("focus minutes add up", round.focusMinutes == 50)

        // pause
        round = round.startNext(at(100))
        round = round.pause(at(110))
        check("paused holds the clock", round.isPaused && round.remaining(at(200)) == 15.0 * 60)
        val itemsBeforePause = round.items
        round = round.noteStudied(4)
        check("items while paused are not the round's", round.items == itemsBeforePause, "${round.items}")
        step = round.advance(at(1000)); round = step.round
        check("nothing ends while paused", step.events.isEmpty() && round.phase == Phase.Focus)
        check("no alarms while paused", round.alarms(at(200)).isEmpty())
        round = round.resume(at(200))
        check("resumed from where it was held", !round.isPaused && round.remaining(at(200)) == 15.0 * 60)
        step = round.advance(at(216)); round = step.round; events = step.events
        check("round 3 ends 15 minutes after resuming",
            events == listOf(Event.FocusEnded(3, 1500.0, at(215))), "$events")

        // skipping
        round = round.startNext(at(217))
        check("starting from a break skips the rest of it", round.round == 4 && round.phase == Phase.Focus)
        step = round.skip(at(227)); round = step.round; events = step.events
        check("the last round cut short still counts its ten minutes, and finishes",
            events == listOf(Event.FocusEnded(4, 600.0, at(227)), Event.Finished) && round.phase == Phase.Done, "$events")
        check("focus total", round.focusMinutes == 85, "${round.focusMinutes}")
        check("done caption", round.caption(at(230)) == "Focus session done · 85 min · 3 cards",
            round.caption(at(230)))
        round = round.startNext(at(240))
        check("no fifth round", round.phase == Phase.Done && round.round == 4)
        check("stopping a finished round does nothing", round.stop(at(241)).events.isEmpty())

        var skipper = WardRound.begin(WardRoundPlan(focusMinutes = 50, breakMinutes = 10), t0)
        skipper = skipper.advance(at(51)).round
        check("a 50-minute round has a 10-minute break",
            skipper.phase == Phase.Rest && skipper.remaining(at(51)) == 9.0 * 60)
        step = skipper.skip(at(52)); skipper = step.round
        check("a skipped break goes to ready", step.events == listOf(Event.RestEnded(1)) && skipper.phase == Phase.Ready)
    }

    @Test fun stopping() = checks {
        val standard = WardRoundPlan.standard
        var stopper = WardRound.begin(standard, t0)
        stopper = stopper.pause(at(5))
        var step = stopper.stop(at(30)); stopper = step.round
        check("stopping mid round counts the time sat, not the time paused",
            step.events == listOf(Event.FocusEnded(1, 300.0, at(30)), Event.Finished) && stopper.phase == Phase.Done,
            "${step.events}")
        var inBreak = WardRound.begin(standard, t0)
        inBreak = inBreak.advance(at(27)).round
        step = inBreak.stop(at(28))
        check("stopping in a break logs no more focus", step.events == listOf(Event.Finished), "${step.events}")
    }

    @Test fun alarmsAndRoundTrip() = checks {
        val fresh = WardRound.begin(WardRoundPlan.standard, t0)
        val alarms = fresh.alarms(t0)
        check("two alarms: the round's end and the break's end", alarms.size == 2 &&
            alarms[0].date == at(25) && alarms[1].date == at(30), "$alarms")
        check("alarm ids are the known ones", WardRound.alarmIDs.toSet().containsAll(alarms.map { it.id }))
        check("round alarm says which block", alarms[0].title == "Block 1 of 4 done", alarms[0].title)
        var last = WardRound.begin(WardRoundPlan(focusMinutes = 25, breakMinutes = 5, rounds = 1), t0)
        check("the last round's alarm is the end", last.alarms(t0).map { it.title } == listOf("Focus session done"))
        last = last.advance(at(26)).round
        check("no alarms when done", last.alarms(at(26)).isEmpty())

        val saved = fresh.toJson()
        val loaded = WardRound.fromJson(saved)
        check("a round survives being saved", loaded == fresh)
    }
}
