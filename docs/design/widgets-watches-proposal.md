# Widgets and watch apps: proposal (T0190)

For the owner to answer yes or no. It covers T0142/T0143 (home-screen widgets) and T0142w/T0143w (watch apps) on both platforms. Nothing here is built yet; the slices at the end are the build order.

**Design source.** No design came with the task, and no spec exists. The iOS widget extension in `ios/StethoscoreWidgets` is the nearest thing to follow, so it gives the shape. The other three surfaces copy its content, its data and its look.

## What exists today

iOS already has a widget extension, which this proposal keeps and fixes rather than replaces:

- `StethoscoreWidgetsBundle.swift:13-21`: Due cards, Exam countdown, Today and streak, the Review due control, and two Live Activities.
- Every widget reads one small file, the digest (`GlanceDigest.swift:16-44`), which the app writes into the App Group (`GlanceShelf`, `GlanceDigest.swift:126-181`). No widget opens the library, the schedule or the network.
- The app writes the digest from `GlancePublisher.publish` (`GlancePublisher.swift:24-47`). It is called from `AppIntentsRouting.swift:243`, `:250` and `:303`. It reloads timelines only when a number changed (`:49-57`).
- Its numbers come from:
  - `ReviewPlan.dueToday` (`ReviewOptions.swift:248`), the same queue as `DueTodayView` (`DueTodayView.swift:12`);
  - `StudyLog.today` and `StudyLog.streak` (`StudyLog.swift:84`, `:90`);
  - `ExamCap.storedDate` (`ReviewPlan.swift:249`).

Android has no widget, no watch module and no link handling:

- `MainActivity.kt:21-43` only takes incoming files, and `AndroidManifest.xml` declares no URL scheme.
- `settings.gradle.kts` includes `:app` only.
- `app/build.gradle.kts` has no Glance, Wear or Play services library.

No Apple Watch or Wear OS code exists anywhere in the repository.

### Three things in the current widgets this proposal changes

1. **The streak.** The "Today and streak" widget (`TodayStreakWidget.swift:6-16`) shows the streak with a flame (`:30`, `:40`). Streaks are ruled out, so it becomes "Done today" (below). The digest keeps its `streak` field so older files still decode, and no surface shows it.
2. **The exam name.** Home writes "Step 1 in 90 days":
   - the name comes from `ExamCountdown.examName` (`WardHome.swift:20-38`), which is the chosen exam's short name (`ExamCatalog.swift:249`), or "Finals" with none;
   - the sentence comes from `WardWords.countdown` (`WardWords.swift:19`).

   The widgets take `ExamTrack.title` instead (`GlancePublisher.swift:32`), so they say "USMLE Step 1 / Step 2 CK" or "Your exam". The widgets follow home: the publisher stores `ExamCountdown.examName`, and the widgets use `WardWords.countdown`. `WardWords.swift` is Foundation-only (`:10`), so the extension can compile it. (The literal "Step 1 in 90 days" appears in the code only as an accessibility test text, `PreviewExtras.swift:229`.)
3. **The missing-file case.** If the shared container cannot be opened, `GlanceShelf` falls back to the extension's own caches (`GlanceDigest.swift:136-145`). The timeline then reads `.empty` (`GlanceTimeline.swift:31`), and the widget says "All caught up" while cards are waiting. A widget with no file should say so instead: "Open Stethoscore to see your cards".

## The four surfaces

All four show the same three things, which the digest already carries: cards due now with the busiest decks, days to the exam, and how much was done today. None shows a streak, XP, a rank, a leaderboard, the logo or any AI output. None uses the network.

### 1. iOS widgets (WidgetKit)

**Purpose:** what is due and how long until the exam, without opening the app.

| Widget | Family | Content | Tap |
|---|---|---|---|
| Due cards | systemSmall | glyph `rectangle.stack`, the count, "due now" or "All caught up" | whole widget: `redpen://due` (`AppLink.reviewDue`) |
| | systemMedium | the count on the left; up to **2** deck rows (name, count) and a Review button on the right | each deck row: `redpen://set/<id>` (`AppLink.openSet`); Review: `ReviewDueIntent` (in-widget button); elsewhere: `redpen://due` |
| | accessoryCircular | count over "due" | whole widget: `redpen://due` |
| | accessoryRectangular | "24 cards due", 2 decks | whole widget: `redpen://due` |
| | accessoryInline | "24 cards due" or "Nothing due" | whole widget: `redpen://due` |
| Exam countdown | systemSmall | glyph `calendar`, the days, "days to Step 1"; with no date: "Set your exam date" | `redpen://exam` (`AppLink.examPlan`) |
| | accessoryCircular | days over "days" | `redpen://exam` |
| | accessoryRectangular, accessoryInline | home's sentence: "Step 1 in 90 days", "Finals tomorrow" | `redpen://exam` |
| Done today (replaces Today and streak) | systemSmall | the count, "of 50 done today" (goal: `DailyGoal.current`, `DailyGoal.swift:9`) | `redpen://due` |
| | accessoryCircular | a gauge, today out of the goal | `redpen://due` |
| | accessoryInline | "32 of 50 done today" | `redpen://due` |
| Review due control | Control Centre, Action button | unchanged | `ReviewDueIntent` |

- **Medium: why 2 deck rows, not 3.** Each row becomes a 44 pt target, and so does the Review button. Three rows and the button come to 176 pt, which does not fit a medium widget. Two rows and the button come to 132 pt, which does. Today the button has no minimum height (`DueCardsWidget.swift:65-70`), so it gets `minHeight: 44`.
- **Lock Screen families:** the system makes the whole widget one target, so there is nothing to size.
- **Data:** the digest (`GlanceDigest.swift:16-44`), written by `GlancePublisher.swift:24-57`. The slice adds two fields to version 1: `goal`, and the home-style exam name. Both are optional, so an older widget still reads the file.
- **Refresh:**
  - the app writes the digest a few seconds after the library or schedule stops changing, and reloads only on a real change (`GlancePublisher.swift:51-55`);
  - the timeline adds entries at midnight and at the next card's due time, and asks again after 4 hours (`GlanceTimeline.swift:29-43`);
  - `dueShown`, `todayShown` and `daysToExam` correct a stale file when it is read (`GlanceDigest.swift:56-96`).

  This stays as it is.

### 2. Android widgets (Jetpack Glance)

**Purpose:** the same as iOS, on the Android home screen.

| Widget | Size (cells) | Content | Tap |
|---|---|---|---|
| Due cards | 2×2 | the count, "due now" or "All caught up" | `stethoscore://due` |
| | 4×2 | the count; up to 2 deck rows; a Review button | each row: `stethoscore://set/<id>`; Review: `stethoscore://due` |
| Exam countdown | 2×1 | "Step 1 in 90 days" (`WardWords.countdown`, `WardWords.kt:15`) | `stethoscore://exam` |
| | 2×2 | the days, "days to Step 1"; with no date: "Set your exam date" | `stethoscore://exam` |
| Done today | 2×1, 2×2 | "32 of 50 done today" | `stethoscore://due` |

- **Sizing:** Glance `SizeMode.Responsive` with the two sizes above. Each row and the button get at least 48 dp of height, and the 4×2 cell height leaves room for two rows and the button. Material Symbols stand in for SF Symbols, as everywhere else on Android (`android/docs/parity.md`).
- **Look:** the same flat ground, ink and Vital Coral as `GlanceStyle` (`GlanceTimeline.swift:48-68`), taken from the Android Ward palette (`ui/ward/`). The values are not repeated.
- **Data:** a Kotlin port of the digest, written as JSON to the app's own files directory. A widget runs in the app's process, so no shared container is needed, but loading the whole library on every widget update would be slow. The digest is built from:
  - due: `StudyStore.dueAcross` (`StudyStore.kt:374`), the same queue as `DueTodayScreen` (`AnkiReviewScreen.kt:140`);
  - exam date: `StudyStore.examDate` (`StudyStore.kt:52`); exam name: `ExamCountdown.examName` (`HomeRound.kt:30`);
  - today: `LibraryStats.streakAndToday` (`LibraryStats.kt:185`), taking the today half only.
- **Links (new):** Android has none today. The slice will:
  - add a `VIEW` intent filter for the `stethoscore` scheme on `MainActivity`;
  - port `AppLink.parse` (`AppLink.swift:39-70`) to Kotlin, with its round-trip test (`PlatformTests.swift:44`);
  - pass the result in as `initialScreen` (`StethoscoreApp.kt:78`), which already has a `"due"` screen (`:251`).

  The exam link opens Learn's Exam plan (`LearnRoutes.kt:141`). The slice finds how Learn is entered, and falls back to the exam picker (`StethoscoreApp.kt:264`) if that is the only way in.
- **Refresh:**
  - the app writes the digest from `StudyStore.save` (`StudyStore.kt:150`) and from `setExamDate` (`:410`), and calls `updateAll()` only when the content changed;
  - `updatePeriodMillis` is 3 hours, and the read-time corrections from iOS are ported with the digest.

### 3. Apple Watch app (watchOS)

**Purpose:** the due count and the countdown on the wrist.

- **App, one screen:**
  - the count, large, with "due now" or "All caught up";
  - up to 3 deck rows, display only;
  - "Step 1 in 90 days";
  - a footer line, "Updated 10:42 AM".

  After 24 hours with no update, the footer reads "Open Stethoscore on your iPhone to update". Before the first update it reads "Open Stethoscore on your iPhone once to see your cards here".
- **Complications** (WidgetKit on watchOS): accessoryCircular, accessoryRectangular, accessoryInline and accessoryCorner. They reuse the Lock Screen views of Due cards and Exam countdown.
- **Taps:**
  - a complication opens the watch app (the system decides this);
  - the app has one control, "Refresh", full width, at least 44 pt tall, which asks the iPhone for a new digest.

  A watch cannot open the iPhone app, so there are no links.
- **Data:** the digest again. The watch cannot read the iPhone's App Group, so `GlancePublisher.save` (`GlancePublisher.swift:49-57`) also sends it with `WCSession.updateApplicationContext`. The watch app saves it into its own App Group, where its complications read it through the same `GlanceShelf`.
- **Refresh:**
  - the iPhone sends a digest on each real change;
  - the watch reloads complications when one arrives, and keeps the midnight and next-due entries from `GlanceTimeline.swift:29-43`;
  - watchOS limits how often complications reload, so the read-time corrections matter more here.

### 4. Wear OS app

**Purpose:** the same as the Apple Watch app, on Wear OS.

- **App, one screen:** the same content and footer lines as the Apple Watch app, with "phone" in place of "iPhone". It uses Wear Compose Material 3, with "Refresh" as a full-width chip at least 48 dp tall.
- **Tile:** the count and "Step 1 in 90 days". A tap opens the Wear app.
- **Complications:** `SHORT_TEXT` with the count and "due", and `LONG_TEXT` with "24 cards due". A tap opens the Wear app.
- **Data:** the Kotlin digest from surface 2, sent from the phone as one Data Layer item at `/glance` (`DataClient.putDataItem`). On the watch, a `WearableListenerService` saves it and asks the tile and complications to update. The Data Layer needs Google Play services on both devices (decision D2).
- **Refresh:** a send on each real change, and a 4-hour tile freshness interval. Complications update when an item arrives.

## Constraints, checked

**Free Apple ID and App IDs.**
- The app and the widget extension already use two App IDs: `com.cramdown.app` and `com.cramdown.app.widgets` (`project.yml:259`, `:308`).
- Slices 1 to 7 change only those targets and Android, so they need **no new App ID**.
- The Apple Watch app needs two: `com.cramdown.app.watchkitapp` for the app, and `com.cramdown.app.watchkitapp.widgets` for its complications. That is the whole 7-day allowance.
- If the owner says yes, create the watch app's ID first. It works without complications: the screen and Refresh are usable on their own. The complications extension adds nothing until the app's data arrives.
- AltStore's own FAQ adds its own limit: "You can only register up to 10 App IDs at a time", and "each App ID expires after one week", with each app extension needing its own App ID ([AltStore: App IDs](https://faq.altstore.io/altstore-classic/app-ids)). The owner's rule of 2 a week is the stricter one.

**App Groups on a free account.** Possible in practice, but not verified on the owner's iPhone.
- Apple's capability table ([Supported capabilities, iOS](https://developer.apple.com/help/account/reference/supported-capabilities-ios)) did not render its tick marks when read, so it settled nothing.
- AltStore, which itself installs with a free Apple ID, ships a home-screen widget, and its release notes cover app-group handling for sideloaded apps (1.5: "Fixed some apps having access to AltStore's app group"; 2.0: "missing app group" fixes) ([AltStore release notes](https://faq.altstore.io/release-notes/altstore)). That is good evidence that sideloading apps provision App Groups under a free account.
- Against it, one third-party sideloaded app says its widget "needs a paid Apple Developer account for App Groups" ([ai_usage ios-0.5.1](https://github.com/Neoo-Blue/ai_usage/releases/tag/ios-0.5.1)).
- One risk is specific to this code. A sideloading app may rename the group (often by adding the team ID). It does not know about our `RedPenAppGroup` key (`project.yml:91`, `:297`; read at `GlanceDigest.swift:130-134`). The app and the widget would then each fall back to their own caches and never meet. Slice 1 makes this visible on the device before anything else is built on it.

**Watch hardware.** The owner has an iPhone and an iPad (`CLAUDE.md`, line 1), and no Apple Watch or Wear OS watch is mentioned. Both watch apps can be checked only in simulators and emulators on CI, by screenshots. This is behind decision D1.

**Touch targets.**
- iOS: every tappable thing inside a widget, and Refresh on the watch, is at least 44 pt. Lock Screen and complication taps are whole-surface.
- Android: rows, buttons and chips are at least 48 dp. Tiles and complications are whole-surface.

**No streaks, XP, ranks or leaderboards.** The streak widget is replaced, and no surface reads `streak`.

**No paid AI.** No surface calls the Worker, a model or the network. The only sync is phone to watch.

**No logo.**
- Widget content uses system glyphs only, as today.
- The system's own pickers show the app icon next to a widget's name, and the watch grid shows the watch app's icon. None of these are captured.
- Screenshots crop to the widget, the watch app's own screen, the tile or the complication. Android's picker preview is a layout, not an image of the icon.

## Decisions for the owner

1. **D1. Should the Apple Watch app wait?** It takes the week's two new App IDs, and there is no Apple Watch to use it on. *Default: build it in CI and check it with simulator screenshots, but keep it out of the .ipa, so no App ID is registered until you say so.*
2. **D2. Can the Wear OS app use Google Play services to get data from the phone?** It is free and needs no key, but it would be the app's first Google library. *Default: yes, `play-services-wearable` only. The phone app works the same without a watch.*
3. **D3. Should the watch only show, or also review cards?** Reviewing on the watch means sending cards and ratings both ways. *Default: show only.*
4. **D4. In the medium widget, what does tapping a deck open?** *Default: that deck (`redpen://set/<id>`, a link the app already handles). The other choice is a new link that opens only that deck's due cards.*

## Slices, in order

Each slice is one task packet. Slices 1 to 3 are iOS, 4 to 6 are Android, and 7 onwards are watches. Slices 7 and 8 wait on D2. Slices 9 and 10 wait on D1.

1. **Shared file check (iOS).**
   - A row in Settings' platform section (`PlatformSettingsSection.swift`) says whether the widgets can read the app's data.
   - The no-file state replaces the false "All caught up".
   - Tests in PlatformTests. The owner checks the row once on the next .ipa.
2. **Widget wording and Done today (iOS).**
   - The exam name and sentence come from home (`ExamCountdown.examName`, `WardWords.countdown`); add `WardWords.swift` to the extension's sources.
   - Done today replaces Today and streak; the digest gains `goal`.
   - PlatformTests and BedPlanTests updated.
3. **Medium widget targets (iOS).** Two deck rows as links, and a 44 pt Review button. Screenshots in CI.
4. **Digest on Android.**
   - Port `GlanceDigest` and `GlanceShelf` to `data/`, with their tests.
   - `StudyStore` writes the digest on save. No UI.
5. **Links on Android.** `AppLink` in Kotlin, the intent filter, `MainActivity` and `initialScreen`. Unit tests, and an instrumented test that opens `stethoscore://due`.
6. **Glance widgets.**
   - The Glance library and receivers; Due cards, Exam countdown and Done today.
   - Emulator screenshots at both sizes, in light and dark.
7. **Wear OS module and sync (D2).**
   - `:wear` in `settings.gradle.kts`, `android/wear/build.gradle.kts` with the same application ID as the phone app (the Data Layer pairs by package and signing key), and the Data Layer send and receive.
   - Tests for encoding and decoding the digest.
8. **Wear OS screen, tile and complications.** Wear emulator screenshots, round and square.
9. **Apple Watch app (D1).**
   - New `StethoscoreWatch` target in `project.yml`: an application, platform watchOS, `com.cramdown.app.watchkitapp`, with its own App Group entitlement.
   - Shares `GlanceDigest.swift`; `WCSession` send from `GlancePublisher`; the app's one screen.
   - Not embedded in the .ipa until D1 is answered. Simulator screenshots.
10. **Apple Watch complications.** New `StethoscoreWatchWidgets` app-extension target (watchOS, `com.cramdown.app.watchkitapp.widgets`), reusing the accessory views.

### Build changes in brief

- **`ios/project.yml`:**
  - slices 1 to 3: sources only, adding `RedPen/Shared/Learn/WardWords.swift` to `StethoscoreWidgets`;
  - slices 9 and 10: two targets, with `deploymentTarget` gaining `watchOS: "26.0"`, and the app's dependency list gaining the watch app only when D1 says so.
- **Android:**
  - `app/build.gradle.kts` gains `androidx.glance:glance-appwidget` (slice 6), and `play-services-wearable` with D2 (slice 7);
  - the new `android/wear` module uses Wear Compose Material 3, Tiles with ProtoLayout, and the complications data source library;
  - each version is the newest stable one, checked when its slice starts;
  - the manifest gains the `stethoscore` intent filter, and the widget receivers with `res/xml` widget info files.
