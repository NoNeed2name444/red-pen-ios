package com.stethoscore.app.ui.coverage

import com.stethoscore.app.coverage.CoverageStatus

// A port of the parts of ios/RedPen/Features/Coverage/CoverageChecker.swift
// the Syllabus screen reads: whether the AI check can run, and what it
// found. The check itself asks Stethoscore Cloud, which needs the account
// sign-in Android does not have yet, so the blocker always stands and no
// check is ever run or kept here; the keyword check (CoverageEngine) is the
// whole of the screen, as it is on iOS before sign-in.

/** The AI's verdict on one subtopic (iOS CoverageVerdict). */
data class CoverageVerdict(val status: CoverageStatus, val evidence: String = "", val suggestion: String = "")

/** A finished AI check (iOS CoverageCheck): the verdicts by SubtopicCoverage.id. */
data class CoverageCheck(val track: String, val date: Long, val sources: List<String>, val verdicts: Map<String, CoverageVerdict>,
                         val failedAreas: List<String> = emptyList())

object CoverageChecker {
    /** The product's name, as iOS's Brand.name. */
    const val brand = "Stethoscore"

    /** Why the cloud cannot be asked right now: on Android, always the sign-in iOS asks for first. */
    val blocker: String? = "Sign in to have $brand Cloud check this too. Until then the keyword check below is all there is."

    /** The check on show: none, until Android can sign in to the cloud. */
    val check: CoverageCheck? = null
}
