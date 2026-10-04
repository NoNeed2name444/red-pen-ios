# Playgrounds stand-ins

`tools/make_swiftpm.py` makes the Swift Playgrounds package the owner runs on
the iPad. `--without <chunk>` leaves a feature out of that package and drops
in a stand-in from this folder, so the rest of the app compiles unchanged.
The full app (the Xcode build, and the package made without `--without`) is
never touched by anything here.

## Why

On 25 September 2026 the package stopped building on the iPad. Swift
Playgrounds showed "Build failed" with nothing in the console, on the
morning the app went from 39,000 to 78,000 lines of Swift, and it has not
built since, at 78,000 or 83,000 lines. The same packages build clean on the
GitHub runners with Xcode 26.2 and 26.3, the compilers closest to the one
inside Swift Playground 4.7, and the blank App template still builds on the
iPad. So the code is fine and the size is not: the iPad's build has a
ceiling somewhere between 36,600 lines (the last package that built there)
and 71,700 (the first that did not). The owner set the Playgrounds build's
limit at 36,000 lines.

## Chunks

| chunk | leaves out | stand-in |
|---|---|---|
| `graph3d` | the 3D Ideas map (`Features/Notes/Graph*.swift`), about 20,000 lines of SceneKit | `graph3d.swift` |
| `lens` | Study Lens (`Features/Lens`, `Shared/Lens`) | `lens.swift` |
| `analytics` | the Progress screen's rings and charts | `analytics.swift` |
| `core` | everything but the core, see below | `graph3d.swift` + `core/` + `core-shell-out/` + `core-audio-out/` |
| `core1` | the core's drops minus step 1 below (lecture audio, Voice, Recall, Narrate come back) | `graph3d.swift` + `core/` + `core-shell-out/` + `core-audio-in/` |
| `core2` | core1's drops minus step 2 below (imports, exports, backups, picture cards come back) | `graph3d.swift` + `core/` + `core-shell-out/` + `core-audio-in/` + `core-exports-in/` |
| `core3` | core2's drops minus step 3 below (the full shell, sessions, sync, and the Ward Round home's learning pieces come back) | `graph3d.swift` + `lens.swift` + `analytics.swift` + `CoreStandIns` + `CoreIdeas` + `core3/` |

`_common.swift` (the "not in this build" screen) goes in whenever anything
is left out.

## The core

`make_swiftpm.py ios/RedPen "Stethoscore Personal" com.cramdown.personal out.zip --without core`

About 34,000 lines. It keeps the library, the study modes (questions, cards,
textbook, OSCE), Sources, New set with the whole generation pipeline
and the accuracy engine, sign-in, the recording terms, the exam question,
and Settings for the account, the exam, reviews and help.

It leaves out: the Ideas map (2D and 3D), Study Lens, analytics, audio
lectures and the transcriber, spoken OSCE practice, commute mode and
explain-it-back, the reasoning tools (duels, scripts), draw
from memory, coverage, the exam plan and reminders, the examples hub, the
mistake-insight screens, mock papers, the living sky and the pop-out effect
(flat here), diagnostics, App Intents and Spotlight, sync (the personal
build skips it anyway), Anki packages and every export, backups, picture
cards from photos, the card editors, stats, custom sessions and search.

The core has its own shell in `core/`:

- `CoreApp.swift`: the app's entry point, in place of `RedPenApp.swift`.
- `CoreLibrary.swift`: `LibraryView` (folders and sets, Due today, Sources,
  New set, Settings), `CoreSetScreen` (a set in its mode), `CoreSettingsView`.
- `CoreStandIns.swift`: every name the kept files still use from the parts
  left out, under the same signatures: no-op diagnostics, a flat pop-out,
  a calm backdrop in place of the sky, haptics in place of the space cues,
  an idle sync engine, placeholder screens, and the small helpers.

The small shell is shared by core, core1 and core2. core3 does not copy
`CoreApp.swift` or `CoreLibrary.swift`: the app's own `RedPenApp` and
`LibraryView` are back. It also does not copy `core-shell-out/`, which holds
the stand-ins for `SyncEngine`, `LinkDeviceView`, `ModelSettingsView`,
`guessFirst` and `Store.picks` — the real files declare those. What differs
per step is in a folder of its own, copied in beside the shell:

- `core-audio-out/CoreAudioStandIns.swift` (the core): the stand-ins for
  the step-1 parts (the spoken OSCE station, the narrate reader, draw
  from memory, the transcriber's line shape, the commute
  sheet) and the library's "not in this build" pieces.
- `core-audio-in/CoreAudio.swift` (core1): the narrate reader is the app's
  own, and the library gets a Spoken section (commute mode, explain it back),
  which the full app reaches from its study categories instead.
- `core-exports-in/CoreExports.swift` (core2): the picture-card and export
  ways into the small shell. core3 does not copy it: `CategoryFeature`,
  `CategoryHeading` and `StudySetScreen` in that file are the real library's.
- `core3/Core3Gaps.swift` (core3): the names the returning shell still uses
  from Ideas, the sky, diagnostics, the platform, reasoning, insight,
  coverage and onboarding.

When the full app changes, a kept file may start using a new name from a
left-out part. The package check (`swiftpm-check.yml`) builds the core on
every push to `personal` and fails with the missing name; add it to
`CoreStandIns.swift` or move the file into `CORE_KEEP` in `make_swiftpm.py`.
The launch workflow (`swiftpm-launch.yml`, on `ci/launch`) also launches the
core in the simulator.

## Finding the iPad's real ceiling

Each chunk added back to the core is one zip for the owner to try. The
first that fails to build marks the ceiling; everything under it can stay.

The parts the core leaves out, measured on 30 September (lines of Swift),
in the order worth adding them back, so that each step is about 10,000
lines and the ceiling, expected between 36,600 and 71,700, shows within
four zips:

| step | adds back | lines | package after |
|---|---|---|---|
| 1 | lecture audio: transcriber, player, narrate plan, pronunciation, corrections (1,965), Voice (5,190), Recall and Narrate (2,269) | 9,424 | about 43,200 |
| 2 | imports and exports: Anki packages, PDFs, backups, occlusion and picture cards, scanner | 9,585 | about 52,800 |
| 3 | the full shell, sessions, stats and editors, sync, and Learn. Ward Round's home calls `BedPlan`, `ExamWeekPlanner`, `RhythmReading`, `WardWords` and `LearnRouter`, so `Shared/Learn` and `Features/Learn` come back with the shell rather than as an empty bed plan | about 12,900 | about 67,700 kept lines, before stand-ins |
| 4 | Coverage, Examples, Insight, Mock and Reasoning. Learn already came back in step 3, so this step is not a chunk yet | | |
| 5 | Study Lens (3,520), analytics (1,477), the 2D Ideas map (2,261) | 7,258 | about 78,200 |
| 6 | the living sky, pop-out, diagnostics, platform, App Intents | 6,920 | about 85,100 |
| 7 | the 3D Ideas map | 20,433 | about 105,500 |

Each step is its own chunk in `make_swiftpm.py` (`core1` is step 1, `core2`
is step 2, `core3` is step 3), so the core itself stays as it was sent: the
step's chunk drops `CORE_DROP` minus the paths it brings back, and the
stand-ins for those parts move from the shared shell into the step's own
folder. The package check (`swiftpm-check.yml`) compiles every chunk on each
push to `personal` before a zip goes out. `tools/playgrounds_cut.py --drop
<the remaining drops> --names` lists what the remaining stand-ins must still
provide; the extension methods it cannot see (`guessFirst`,
`commuteModeSheet`, `picks`, `platformRoutes`, `skyScroll`) are found by the
compile.

`GraphLineStyle.swift` and `GraphicsQuality.swift` stay in every core
package (`CORE_KEEP`). They are Foundation only, and Settings in the full
shell reads them.

Status: `core`, `core1` and `core2` are the chunks already on this ladder.
`core3` is the next zip. Measured while assembling it: 67,699 lines of the
app's own Swift come back, and the zip is 295 Swift files, 68,891 lines
once the stand-ins are in. That sits in the gap between the last package
that built on the iPad (about 36,600) and the first that did not (about
71,700), so this is the zip that can show the ceiling. This machine cannot
compile it: there is no iOS SDK here. `swiftpm-check.yml` compiles it on a
Mac runner once the branch is `personal`.
