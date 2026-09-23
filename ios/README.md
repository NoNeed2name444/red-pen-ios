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

## Medical models: Doctor-R1, MedVAL and hosted models

Settings ▸ **AI models** chooses two things:

| Role | On the device | Hosted |
|---|---|---|
| **Writer**: writes MCQs and OSCE stations, plays the patient in Cases | Doctor-R1 8B (GGUF) | Baichuan-M2-32B, or any model below |
| **Checker**: grades generated text for hallucinations, omissions and certainty, risk level 1–4 | MedVAL-4B (GGUF) | any model below, given MedVAL's prompt |

A writer chosen here takes priority over Apple's on-device model and Gemma. With neither chosen, the app behaves exactly as before.

**Tiers.** Free: Apple's on-device model and the Gemma fallback. Pro: Doctor-R1 and MedVAL on the device, and CramDown Cloud. A hosted model added with your own API key is not gated (you pay that provider).

### On the device
Tap **Download** next to a model. The app picks the largest build this device has memory for:

| Model | Build | Size | Needs |
|---|---|---|---|
| Doctor-R1 | Q4_K_M | 5.0 GB | 11 GB+ memory (M-series iPad Pro/Air, recent 12–16 GB devices) |
| Doctor-R1 | Q3_K_M | 4.1 GB | 8 GB (iPhone 15 Pro and later, M1+ iPads) |
| MedVAL-4B | Q4_K_M | 2.5 GB | 8 GB |
| MedVAL-4B | Q3_K_M | 2.1 GB | 6 GB (iPhone 13 Pro, 14, 15) |

Devices with less memory show "Too large for this device". They use a hosted model for that role instead. Only one on-device model is in memory at a time, so a case with both loads them in turn.

Where the files come from (downloaded by the app, nothing to do by hand):
- Doctor-R1: `huggingface.co/mradermacher/Doctor-R1-GGUF` (conversion of `unicornftk/Doctor-R1`, MIT licence)
- MedVAL-4B: `huggingface.co/stanfordmimi/MedVAL-4B-GGUF` (MIT licence)

Both run through llama.cpp via LocalLLMClient, the same engine as the Gemma fallback. The same GGUF files run on Android through llama.cpp. VeRL and DSPy are only needed to *train* these models, not to run them.

### Hosted: one interface, several providers
**Add a hosted model** offers these presets. Every field stays editable:
- **Baichuan-M2-32B (Hugging Face)**: `https://router.huggingface.co/v1`, model `baichuan-inc/Baichuan-M2-32B`. Needs a Hugging Face token. If no provider on the router serves it, deploy it as a Hugging Face Inference Endpoint and paste that endpoint's `/v1` address instead.
- **OpenRouter**, **OpenAI**, **Groq/Together** (all OpenAI-compatible), **Claude** (Anthropic Messages API), **Gemini** (Google).
- **Your own server**: anything that speaks `/v1/chat/completions`, e.g. `llama-server -m Doctor-R1.Q4_K_M.gguf --port 8080` or `vllm serve unicornftk/Doctor-R1`, at `http://<machine>:8080/v1`. Plain `http` is allowed on the local network only.

Keys are stored in the keychain on the device and never built into the app. For an App Store release where students shouldn't need their own keys, put the key behind the existing Cloudflare worker (`server/`) as an OpenAI-compatible `/v1/chat/completions` proxy, and ship that address as a preset.

### What is checked
- **Cases**: the case file is checked against the card it was written from. Before it is shown, every patient reply is checked against the case file. Replies graded level 3–4 are regenerated with MedVAL's findings as a correction (up to twice). Anything still failing is listed in the debrief as "treat with caution".
- **MCQ / OSCE generation**: each question or station is checked against the matching part of the lecture. Level 4 is dropped, and level 3 is kept but counted in the status line. You can turn this off in AI models.
- **Every mode**: **Check accuracy** (shield button) on the current MCQ (once answered), Anki card, Textbook page, Cases card or OSCE station. It checks against the best-matching pages of the set's source, or against standard teaching when the set has no source (the sheet says so).

A study aid, not medical advice.
