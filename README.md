# Stethoscore for Android

Native Kotlin / Jetpack Compose app targeting **Android 17 (API 37)**, on the independent `android/kotlin` branch.
The source is `red-pen-ios/personal@be11a567cff6f96d74266cdadba63415b832a32c` (9 October 2026), selected after auditing 4 accessible repositories and 162 branches. This branch runs only the Android workflow. The iOS working branch is unaffected.

## Build and install

Open this directory in Android Studio with JDK 17, Android 17 SDK (API 37) and Gradle 9.7.1. Or run:

```sh
gradle :app:assembleDebug :app:testDebugUnitTest
```

The [Android workflow](https://github.com/NoNeed2name444/red-pen-ios/actions/workflows/android.yml) produces a debug APK and test reports. Download its `stethoscore-android-build` artifact, then install `outputs/apk/debug/app-debug.apk` on an Android 8+ device. Screenshot tests run the real app on an Android 17 emulator and save PNGs in `screenshots/` and the screenshot artifact.

## Implemented in this preview

- Local JSON library, import/export, duplicate-safe identifiers and atomic saving.
- MCQs with shuffled options, explanations, saved progress and answer history.
- QA, cloze and image-occlusion cards, early-review protection and exam capping.
- Review scheduling as on iOS: Classic intervals or FSRS-5 (chosen in Settings), learning steps, a study day that turns over at 4 am, daily new and review limits across the library, suspend and bury.
- PDF export of any non-Anki set as a printable flashcard deck: cover, contents index, then each question on its own page with its answer on the next.
- OSCE recall chains, textbook reading, transcript playback with Android text-to-speech.
- Source-derived Cases with findings, investigation time costs, diagnosis and debrief.
- Editable linked notes with a list view and a 3D map (OpenGL ES 3.0): octree chunks, frustum culling, continuous level of detail by on-screen size, summary points and link bundles for far chunks, changes by morphing (never fading), all nodes resident on the GPU, an LRU link cache with a guard band ahead of the motion, and an adaptive frame budget at the display's highest refresh rate (Surface.setFrameRate, display modes, Choreographer).
- A 1,000,000-node demo of the map with a live readout (fps, display max Hz, frame ms, drawn nodes, chunks).
- Practice metrics, light/dark Ward design.
- Backend transport and encrypted credential storage, preserved server source and regression tests.

Examples are optional and copied from the iOS examples. A normal first launch has an empty library. Screenshots use examples; progress is never fabricated.

## Remaining parity work

This is an Android preview, not a finished one-to-one conversion. Still missing: cloud generation and the accuracy UI, sign-in and full conflict-preserving sync, transcription and recording, APKG import and export (Anki deck files), subscription billing, widgets, and a Vulkan path for the map (OpenGL ES 3.0 is the baseline). PDF export has no tappable contents links, because Android's PdfDocument has no link annotations; it lists page numbers instead. Backend transport is not automatic account sync, and examples are not independently verified medical content.

`upstream/ios/` and `upstream/docs/` preserve the selected Swift source and design record. `docs/audit/` records source selection and branch heads. Do not deploy the preserved server without configuring its resources and explicit authorization. No server was deployed for this port.
