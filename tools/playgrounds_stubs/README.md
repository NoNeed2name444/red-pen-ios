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
| `core` | everything but the core, see below | `graph3d.swift` + `core/` |

`_common.swift` (the "not in this build" screen) goes in whenever anything
is left out.

## The core

`make_swiftpm.py ios/RedPen "Stethoscore Personal" com.cramdown.personal out.zip --without core`

About 34,000 lines. It keeps the library, the study modes (questions, cards,
textbook, cases, OSCE), Sources, New set with the whole generation pipeline
and the accuracy engine, sign-in, the recording terms, the exam question,
and Settings for the account, the exam, reviews and help.

It leaves out: the Ideas map (2D and 3D), Study Lens, analytics, audio
lectures and the transcriber, spoken OSCE practice, commute mode and
explain-it-back, the reasoning tools (clue cases, duels, scripts), draw
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

When the full app changes, a kept file may start using a new name from a
left-out part. The package check (`swiftpm-check.yml`) builds the core on
every push to `personal` and fails with the missing name; add it to
`CoreStandIns.swift` or move the file into `CORE_KEEP` in `make_swiftpm.py`.
The launch workflow (`swiftpm-launch.yml`, on `ci/launch`) also launches the
core in the simulator.

## Finding the iPad's real ceiling

Each chunk added back to the core is one zip for the owner to try. The
first that fails to build marks the ceiling; everything under it can stay.
