package com.stethoscore.app.data

/**
 * Each case's latest run, kept on this device: what was done, the ladder's
 * history and the score. Progress, not material, so it lives beside the
 * library rather than in it, the way a quiz's place does. Port of iOS
 * Features/Cases/CaseRunStore.swift: on Android the runs sit in the store's
 * `caseRuns` (saved with the library's progress), keyed by the case's id, in
 * the shape iOS writes them.
 */
class CaseRunStore(private val store: StudyStore) {

    /** Every kept run, by case id; entries in another shape (an older Android session) are left out. */
    val runs: Map<String, CaseRun> get() = store.caseRuns.mapNotNull { (key, json) -> CaseRun.fromJson(json)?.takeIf { it.caseID == key }?.let { key to it } }.toMap()

    fun run(file: CaseFile): CaseRun? = CaseRun.fromJson(store.caseRuns[file.id])?.takeIf { it.caseID == file.id }

    fun state(file: CaseFile): CaseRun.State = run(file).caseState

    /** Keeps a run, after every step, rung and decision. */
    fun save(run: CaseRun) = store.saveCaseRun(run.caseID, run.toJson().toString())

    /** Starts the case again from arrival. */
    fun reset(file: CaseFile) = store.clearCaseRun(file.id)
}
