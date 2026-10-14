# Stethoscore for Android

Native Kotlin / Jetpack Compose port on the independent `android/kotlin` branch.
The source is `red-pen-ios/personal@be11a567cff6f96d74266cdadba63415b832a32c` (9 October 2026), selected after auditing 4 accessible repositories and 162 branches. This branch runs only the Android workflow. The iOS working branch is unaffected.

## Build and install

Open this directory in Android Studio with JDK 17, Android SDK 35 and Gradle 8.11.1. Or run:

```sh
gradle :app:assembleDebug :app:testDebugUnitTest
```

The [Android workflow](../../actions/workflows/android.yml) produces a debug APK and test reports. Download its `stethoscore-android-build` artifact, then install `debug/app-debug.apk` on an Android 8+ device. Screenshot tests run the real app on an Android 15 emulator and save PNGs in `screenshots/` and the screenshot artifact.

## Implemented in this preview

- Local JSON library, import/export, duplicate-safe identifiers and atomic saving.
- MCQs with shuffled options, explanations, saved progress and answer history.
- QA, cloze and image-occlusion cards, Classic review intervals, early-review protection and exam capping.
- OSCE recall chains, textbook reading, transcript playback with Android text-to-speech.
- Source-derived Cases with findings, investigation time costs, diagnosis and debrief.
- Editable linked notes with a 2D map, practice metrics, light/dark Ward design.
- Backend transport and encrypted credential storage, preserved server source and regression tests.

Examples are optional and copied from the iOS examples. A normal first launch has an empty library. Screenshots use examples; progress is never fabricated.

## Remaining parity work

This is an Android preview, not a finished one-to-one conversion. Cloud generation/accuracy UI, sign-in and full conflict-preserving sync, transcription/recording, APKG/PDF import/export, FSRS and full daily review limits, subscription billing, widgets, and the iOS 3D neuron/space renderer still require Android implementations. The map here is explicitly 2D. Backend transport is not automatic account sync, and examples are not independently verified medical content.

`upstream/ios/` and `upstream/docs/` preserve the selected Swift source and design record. `docs/audit/` records source selection and branch heads. Do not deploy the preserved server without configuring its resources and explicit authorization. No server was deployed for this port.
