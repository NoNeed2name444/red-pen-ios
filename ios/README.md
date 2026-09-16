# Red Pen — iOS (SwiftUI)

Phase 1 of the native rewrite: shared data model, local persistence, and the
two core study loops — **MCQ** and **Anki** (spaced repetition) — rebuilt
natively with the exact same scheduling behavior as the web app. Textbook,
OSCE, Narrate and QA Cards modes, AI-assisted set generation, and PDF export
are not in this pass yet (see the bottom of this file for the plan).

## What's here

- `RedPen/Models/` — `MCQQuestion`, `AnkiCard`, `StudySet`, `Folder` (mirrors
  the web app's `state.questions` / `state.ankiCards` / `state.library`
  shapes so a JSON export from either side can move to the other later).
- `RedPen/Persistence/Store.swift` — an `ObservableObject` that loads/saves
  the library as a single JSON file in the app's Documents directory (the
  native equivalent of the web app's `state.library` + IndexedDB/localStorage
  layer). No backend, no account — everything is on-device, same as the
  artifact today.
- `RedPen/Features/Library/` — the set list: create, rename, delete, open a
  saved MCQ or Anki set.
  - `NewSetView.swift` lets you either type/paste questions or cards in a
    simple line format, or import a `.json` file with the same shape the web
    app's own export uses (see `Models/StudySet.swift` doc comments) — this
    stands in for "AI generation" until that's wired up to a real API key in
    a later phase.
- `RedPen/Features/MCQ/` — `MCQQuizView.swift` (question/options/check/next,
  running score, same single-best-answer flow as the web app's `renderQuestion`)
  and `MCQSummaryView.swift`.
- `RedPen/Features/Anki/` — `AnkiScheduler.swift` is a line-for-line port of
  the web app's `ANKI_MIN` table and the Again/Hard/Good/Easy interval math
  (`formatInterval`, the `cur * 1.2 / 2.5 / 4` growth, the due-queue
  re-sort), so a card reviewed here reappears on the same real-world timing
  as it would in the artifact. `AnkiReviewView.swift` covers QA, cloze, and
  image-occlusion cards.

## Building it

You'll need a Mac with Xcode 15+.

This project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
instead of a hand-written `.xcodeproj` (hand-rolled Xcode project files are
notoriously easy to corrupt, and there's no way to verify one from outside
Xcode) — regenerating it is quick and safe any time files are added:

```sh
brew install xcodegen   # one-time
cd ios
xcodegen generate
open RedPen.xcodeproj
```

Then hit Run (⌘R) with an iOS 17+ simulator selected. No signing setup is
needed to run on the simulator; running on your own iPhone needs your Apple
ID added under Xcode → Settings → Accounts, and a free personal team
selected in the target's Signing settings.

## Seeing it without a Mac: the preview pipeline

`.github/workflows/ios-preview.yml` (at the repository root) builds this
project on GitHub's free macOS runner, launches it in the iOS Simulator once
per screen in light and dark mode (`-uiPreviewScreen library|new|quiz|
quiz-checked|summary|anki|anki-revealed`, see `RedPen/Shared/PreviewLaunch.swift`),
and pushes real screenshots plus the build log and any compile errors to a
`previews` branch. That is how the screenshots reach the artifact page, and
how compile errors get caught and fixed from chat. The preview launch uses
an in-memory store seeded with sample sets; a normal launch never sees it.

## Plan for later phases

1. **Textbook + QA Cards** modes.
2. **OSCE checklist** mode + PDF export (matching the web app's
   `renderOscePdf`/`renderQuestionsPdf`).
3. **Narrate** mode — recording + calling your existing Gemini bridge
   Worker over plain HTTPS (the bridge itself needs no changes; this is a
   native `URLSession` client for the same JSON API).
4. Optional: AI set generation from source text/images, calling an LLM API
   directly from the app (needs your own API key stored in Keychain, or a
   small backend to hold it).
