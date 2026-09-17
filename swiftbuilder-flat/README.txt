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
     16b_MCQGenerator.swift    -> MCQGenerator (on-device MCQ generation — see the note below)
     17_NewSetView.swift       -> NewSetView (MCQ sets: Generate / Type / Import)
     18_PreviewLaunch.swift    -> PreviewLaunch, SampleData, PreviewRoot (CI screenshot hooks; harmless in the app)
     20_PDFExporter.swift      -> PDFExporter (the "Export PDF" swipe action's PDF builder)
     21_ShareSheet.swift       -> ShareSheet (system share sheet wrapper, used by the PDF export)
     22_ApkgExporter.swift     -> ApkgExporter, MiniZip, JSONExporter (Anki .apkg + JSON sharing)

3. 19_RedPenApp.swift is the app's entry point (`@main`). SwiftBuilder's
   own template already created one for you (usually called something like
   `App.swift` / `ContentView.swift`). Don't paste 19 in as a brand new
   file — instead:
     - open SwiftBuilder's existing `@main` file,
     - replace its whole contents with 19_RedPenApp.swift's contents, OR
     - if SwiftBuilder won't let you rename that file's struct, just copy
       the *body* (the `WindowGroup { LibraryView()... }` part) into
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
New set ▸ MCQ ▸ Generate writes a set from pasted notes on-device, with
Apple's Foundation Models (Apple Intelligence) — the same prompt rules the
web app's Claude-backed generator uses (single-best-answer format, no
"all/none of the above", length-matched distractors, a mix of vignette and
pure-recall questions), just answered by the model bundled with iOS instead
of a paid API call. That means it needs a device with Apple Intelligence
turned on (Settings ▸ Apple Intelligence & Siri) — on anything else
(older hardware, Apple Intelligence off, or the Simulator, which has no
on-device model at all) the Generate tab shows why it can't run instead of
a button that quietly does nothing, and Type / Import are still right there
as fallbacks. Nothing about this path — unlike a bring-your-own-API-key
version would — ever touches a Claude account or any other paid usage.
Once a set is generated, it opens as an ordinary quiz with its own "Save"
button in the header (and again on the results screen) — nothing is added
to the library until you tap it, matching the web app's generate-then-save
flow.

NOTE ON NARRATE MODE
---------------------
The web app's Narrate mode can also sync playback to a real recording,
with on-device transcription and AI-assisted correction. That part isn't
ported here — it's a much larger undertaking (on-device Whisper, audio
alignment). What's here is the typed-transcript, reading-pace player,
which is what most Narrate sets are read with anyway.

IF A PASTE DOESN'T COMPILE
----------------------------
The most common cause is paste order (a type used before it's defined) or
SwiftBuilder's own template file still having leftover placeholder code —
check its `@main` file first.
