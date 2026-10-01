Red Pen — flat Swift files for SwiftBuilder: Swift Studio
===========================================================

These are the same source files from the Xcode/XcodeGen project (all six
modes: MCQ, Anki, Textbook, Cases, OSCE, and Narrate — plus PDF export and
the iOS 26 Liquid Glass UI), split so each one can be pasted into
SwiftBuilder as its own file — no folders, no Info.plist, no
Assets.xcassets, no project.yml. SwiftBuilder manages the app shell
itself, so none of that Xcode scaffolding is needed here.

HOW TO ADD THEM
----------------
1. In SwiftBuilder, create a new project (or open the one you already
   started).
2. Add a new Swift file for each of 00 through 22 below, name each file
   whatever SwiftBuilder asks (the name doesn't have to match the number
   prefix — that's just paste order), and paste in that file's contents.
   Paste them in this order so each file's types exist before something
   later references them:

     00_LiquidGlass.swift      -> .liquidGlassPanel() / .liquidGlassChip() shape helpers over Apple's glassEffect (see the note below)
     00b_Theme.swift           -> per-mode tints/symbols, ModeTile, ModeBackdrop, ContentCard, ThinProgress, ScoreRing (the visual system)
     01_MCQQuestion.swift      -> MCQQuestion, MCQAnswer
     02_AnkiCard.swift         -> AnkiCardType, OcclusionBox, AnkiCard, AnkiQueueItem
     03_QACard.swift           -> QACard (Cases mode)
     04_OsceChecklist.swift    -> OsceChecklist (OSCE mode)
     05_NarrateSegment.swift   -> NarrateSegment, NarrateScheduler (Narrate mode)
     06_StudySet.swift         -> StudySetKind, StudySet, StudyFolder, PlainTextImport
     07_Store.swift            -> Store (the on-device JSON library)
     08_AnkiScheduler.swift    -> AnkiRating, AnkiScheduler
     09_AnkiReviewView.swift   -> AnkiReviewView
     10_MCQQuizView.swift      -> MCQQuizView
     11_MCQSummaryView.swift   -> MCQSummaryView
     12_BookReaderView.swift   -> BookPage, BookPages, BookReaderView (Textbook mode)
     13_QACardsView.swift      -> QACardsView (Cases mode)
     14_OsceReviewView.swift   -> OsceReviewView (OSCE mode)
     15_NarrateReviewView.swift -> NarrateReviewView, FlowText (Narrate mode)
     16_LibraryView.swift      -> LibraryView (now with a swipe-to-export-PDF action)
     16b_MCQGenerator.swift    -> MCQGenerator (on-device MCQ generation, Apple's model — see the note below)
     16c_GemmaModel.swift      -> GemmaModel (the Gemma 4 E2B fallback for devices Apple's model can't run on — see the note below; needs a package dependency, see step 2b)
     17_NewSetView.swift       -> NewSetView (MCQ sets: Generate / Type / Import)
     18_PreviewLaunch.swift    -> PreviewLaunch, SampleData, PreviewRoot (CI screenshot hooks; harmless in the app)
     20_PDFExporter.swift      -> PDFExporter (the "Export PDF" swipe action's PDF builder)
     21_ShareSheet.swift       -> ShareSheet (system share sheet wrapper, used by the PDF export)
     22_ApkgExporter.swift     -> ApkgExporter, MiniZip, JSONExporter (Anki .apkg + JSON sharing)

2b. 16c_GemmaModel.swift needs a Swift package SwiftBuilder doesn't add on
    its own: LocalLLMClient. In SwiftBuilder's package-dependency screen
    (or Xcode's File > Add Package Dependencies, if SwiftBuilder opens the
    project in Xcode under the hood), add:
        https://github.com/tattn/LocalLLMClient
    branch: main — and select all three of its products: LocalLLMClient,
    LocalLLMClientLlama, LocalLLMClientUtility. Skipping this step means
    16c_GemmaModel.swift (and anything that imports it) won't compile;
    the standalone Xcode project (project.yml) already declares this
    dependency, so this step is only needed here.

3. 19_RedPenApp.swift is the app's entry point (`@main`). SwiftBuilder's
   own template already created one for you (usually called something like
   `App.swift` / `ContentView.swift`). Don't paste 19 in as a brand new
   file — instead:
     - open SwiftBuilder's existing `@main` file,
     - replace its whole contents with 19_RedPenApp.swift's contents, OR
     - if SwiftBuilder won't let you rename that file's struct, just copy
       the *body* (the `WindowGroup { LibraryView()... }` part, including
       both `.environmentObject(store)` and `.environmentObject(gemma)` —
       NewSetView needs the second one to offer the Gemma fallback) into
       whatever `@main` struct it already generated, and delete any
       `ContentView()` placeholder it was showing instead.
   There must be exactly ONE `@main` in the whole project — if SwiftBuilder
   created its own and you also paste this one in as a second file, delete
   one of them or you'll get a duplicate-@main build error.

WHAT THIS GETS YOU
-------------------
All six study modes, all backed by on-device JSON storage — same as the
standalone Xcode project, just without the Xcode-specific files:

  - MCQ quiz mode (multiple-choice, checked answers, results summary)
  - Anki spaced-repetition review (QA / cloze / image-occlusion cards)
  - Textbook mode (Markdown split into pages, table of contents)
  - Cases mode (clinical-case and recall Q&A cards)
  - OSCE mode (step-by-step checklist recall with a missed-step second pass)
  - Narrate mode (a lecture transcript read at a reading pace, with
    play/pause, speed control, and tap-to-jump — no audio recording yet,
    see the note below)

The library also has folders (select sets → Folder, or long-press → Move to
folder), Combine (merge two or more sets of the same kind into one), rename,
and — on a long-press — Export PDF, Export Anki deck (.apkg, opens straight
in Anki) and Share as JSON (the same file the Import button reads, so sets
move phone-to-phone or to the web app). MCQ quizzes shuffle their options
each session, save progress as you go and offer to resume, and the results
screen has a Retake button.

Every set in the library also gets a leading swipe action, "Export PDF" —
it builds a print-ready PDF of that set's content (questions + answers +
explanations for MCQ, front/back/why for Anki, and so on) with Core Text,
then hands it to the system share sheet (Mail, Files, AirDrop, etc.).

Building/running inside SwiftBuilder gets you a live on-device preview; it
does not sign a build for the App Store (that still needs Xcode + your own
Apple Developer account on a Mac, further down the line).

NOTE ON LIQUID GLASS
---------------------
The floating control bars and glass buttons across every mode use Apple's
own iOS 26 Liquid Glass API — `View.glassEffect(_:in:)`,
`GlassEffectContainer`, and the `.glass` / `.glassProminent` button styles
(00_LiquidGlass.swift is just two one-line shape helpers on top of that).
That means the project needs an iOS 26 SDK (Xcode 26+) and a deployment
target of iOS 26 — set that in SwiftBuilder's project settings, or the
`glassEffect` symbols won't resolve.

NOTE ON MCQ GENERATION
------------------------
New set ▸ MCQ ▸ Generate writes a set from pasted notes on-device — the
same prompt rules the web app's Claude-backed generator uses (single-best-
answer format, no "all/none of the above", length-matched distractors, a
mix of vignette and pure-recall questions) — through one of two on-device
models, tried in this order, neither of which ever touches a Claude
account or any other paid usage:

  1. Apple's Foundation Models (Apple Intelligence), bundled with iOS —
     needs a device with Apple Intelligence turned on (Settings ▸ Apple
     Intelligence & Siri). This is instant: no download.
  2. If that's unavailable (older hardware, Apple Intelligence off, or
     the Simulator, which has neither) — a downloaded Gemma 4 E2B model
     (Google's small "edge" model, ~2.8 GB as a 4-bit GGUF checkpoint),
     run entirely on-device through the LocalLLMClient / llama.cpp
     package (see step 2b above). The Generate tab offers a one-time
     "Download offline model" button for this, with progress, cancel,
     retry-on-failure, and a "Remove downloaded model" option once it's
     in place — all in GemmaModel.swift.

If neither is available yet (e.g. the download hasn't finished), the
Generate tab explains why instead of showing a button that quietly does
nothing, and Type / Import are still right there as fallbacks. Once a set
is generated (by either model), it opens as an ordinary quiz with its own
"Save" button in the header (and again on the results screen) — nothing is
added to the library until you tap it, matching the web app's
generate-then-save flow.

NOTE ON NARRATE MODE
---------------------
The web app's Narrate mode can also sync playback to a real recording,
with on-device transcription and AI-assisted correction. That part isn't
ported here — it's a much larger undertaking (on-device Whisper, audio
alignment). What's here is the typed-transcript, reading-pace player,
which is what most Narrate sets are read with anyway.

IF A PASTE DOESN'T COMPILE
----------------------------
The most common cause is paste order (a type used before it's defined),
a missing package dependency (see step 2b — this is the most likely
cause if 16c_GemmaModel.swift specifically won't compile), or
SwiftBuilder's own template file still having leftover placeholder code —
check its `@main` file first.
