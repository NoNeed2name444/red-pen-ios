> **Source design, feature group C** (architect output, 2026-09-24), copied verbatim.
> It is an input to [`../implementation-plan.md`](../implementation-plan.md). Where the two disagree, **the plan wins**:
> see the plan's section 2 (conflict resolutions) and the work package that implements this design.

# Group C design: retention outside the app (widgets, Live Activity, App Intents/Siri, Spotlight)

I read the existing code first. The Playgrounds build is compiled with `SWIFT_PACKAGE` defined, and `PersonalBuild.swift` already relies on that. Nothing in Group C needs the server, so there is **no D1 migration and no new Worker route**. Group C only uses Group D's `/config` keys and Group E's counters, both listed in §6.

## 0. What already exists and shapes this design

- **Existing intents.** `Features/Library/DeckExportIntents.swift` has `StudySetEntity`, `StudySetQuery`, two export intents and **the app's only `AppShortcutsProvider`** (`RedPenShortcuts`). An app may have only one provider, with at most 10 App Shortcuts. New shortcuts go into this provider; they do not get a second one. `StudySetQuery.all()` builds a whole `Store()`, which decodes the full library (tens of MB, with images as base64) on every Siri or Shortcuts query. That is too heavy for an extension and slow for Siri.
- **Data files.** The library and progress are in `Documents/redpen-library.json` and `-progress.json`. The schedule is in `Documents/redpen-reviews.json` (`ReviewStore`, a map from UUID to `ReviewRecord`). The streak is in `StudyLog` (`UserDefaults.standard`, key `study.log`). The exam date is in `UserDefaults.standard` under `exam.date`, stored as a date only with no time (`ModelSettingsView`). An extension can read none of these, so an **App Group** is needed.
- **Pure scheduling code.** `ReviewPlan.swift`, `AnkiScheduler.swift` and `Models/AnkiCard.swift` import Foundation or CoreGraphics only. This is proved by the `schedule` suite in swift-tests.yml, which compiles exactly those three files. The widget extension can therefore compute a rating's next `ReviewRecord` itself.
- **Merging ratings.** `ReviewStore.merge(_:)` / `ReviewPlan.merging` already merge card by card on `ratedAt`. Ratings made in the widget can come into the app through this same function, and then sync picks them up with no new sync code.
- **Sync kinds.** `SyncKind` is a closed enum (`set|folder|review|saying`). A new doc kind would stop older app versions from decoding the changes feed. So **the exam date and widget settings do not sync**; they stay per device.
- **URL scheme.** `redpen://` is already declared (`CFBundleURLTypes`) for auth. Deep links reuse it. There is no `onOpenURL` or `onContinueUserActivity` anywhere yet.
- **How Playgrounds is packaged.** `make_swiftpm.py` copies `ios/RedPen` whole into `.executableTarget(path: ".")`. Any `@main WidgetBundle` inside `ios/RedPen` would break the Playgrounds build. **Extension-only code therefore lives in a new sibling folder, `ios/RedPenWidgets/`, which make_swiftpm never copies.** make_swiftpm.py needs no change.
- **Reuse for quizzes.** `Store.temporaryQuiz(named:subject:from:)`, `Store.subjectName(_:)` and `QuizFromCards.build(from:)` already exist. Siri's "quiz me" reuses them. `LibraryView` already has `quickQuiz`, `showingDue` and `opened` for navigation.

## 1. Surfaces (all free, not Pro)

These keep students coming back, and that is what converts them to Pro. Guideline 3.1.1 applies: no price, purchase button or "Get Pro" appears in any widget, control or Live Activity.

| Surface | Families / where | Xcode build | Playgrounds |
|---|---|---|---|
| **Due card** (interactive) | systemSmall: count, next card and "Show answer". systemMedium/Large: card, Show answer, then Again/Hard/Good/Easy | yes | none (no extensions) |
| **Exam countdown** | systemSmall, accessoryCircular (gauge), accessoryRectangular ("PLAB 1 · 23 days · 140 due"), accessoryInline | yes | the in-app countdown already exists |
| **Today** | systemSmall: streak, studied today, due now | yes | none |
| **Control** "Review due cards" | Control Center, Lock Screen, Action button (ControlWidget) | yes | none |
| **Exam-day Live Activity** | Lock Screen and Dynamic Island, a scheduled start on exam morning | yes (iPhone) | toggle hidden |
| **App Intents / Siri** | "Quiz me on cardiology in Vignette", "Review my due cards", "How many cards are due", "How long until my exam" | yes | code compiles and works in-app. Shortcuts/Siri may not list them, because Playgrounds may not extract App Intents metadata |
| **Spotlight** | sets, plus up to 5,000 questions and cards | yes | yes (CoreSpotlight needs no entitlement) |
| **Handoff / Siri suggestions** | `NSUserActivity` on the set screen | yes | activity is set, but not advertised (no Info.plist key) |

**The Live Activity cannot count down for weeks.** A Live Activity lasts at most **8 hours active, then up to 4 hours on the Lock Screen**. The multi-day countdown therefore belongs to the widgets. The Live Activity covers exam morning only, and iOS 26's scheduled start (`startDate` plus the required `AlertConfiguration`) means no server and no APNs are needed.

## 2. Files and code layout

### 2.1 Shared by the app and the extension: `ios/RedPen/Shared/Glance/`

Everything here must compile in the extension. It may use Foundation, SwiftUI, WidgetKit, AppIntents and ActivityKit only. It must not use UIKit, `Store`, `Theme` or LocalLLMClient.

- **`GlanceModels.swift`**
  ```swift
  struct GlanceSnapshot: Codable { var version = 1; var builtAt: Date
    var cards: [GlanceCard]            // due now or within 24h, soonest first, ≤50, text only
    var dueNow: Int; var nextDueAt: Date?; var studiedToday: Int; var streak: Int
    var exam: ExamPlan?; var flags: GlanceFlags }
  struct GlanceCard: Codable, Identifiable, Hashable { var id: UUID; var setID: UUID
    var setName: String; var subject: String
    var prompt: String /*≤280*/; var answer: String /*≤400*/; var why: String? /*≤280*/
    var due: Date; var record: ReviewRecord? /* nil = never rated */ }
  struct GlanceRating: Codable, Identifiable { var id: UUID; var cardID: UUID; var setID: UUID
    var rating: String /* AnkiRating.rawValue */; var ratedAt: Date; var record: ReviewRecord }
  struct GlanceWidgetState: Codable { var revealedCardID: UUID?; var revealedAt: Date? }
  struct GlanceFlags: Codable { var ratings = true; var liveActivity = true; var showRuleOnLock = false }
  struct LibraryIndexEntry: Codable, Identifiable { var id: UUID; var name: String; var subject: String
    var kind: String; var count: Int; var updatedAt: Date }
  ```
  Decoding is tolerant, following the house style: a missing field takes its default, and an unknown `version` means "empty, open the app".
- **`GlanceBuilder.swift`** (pure). `static func build(decks: [GlanceDeckInput], records:, texts: [UUID: GlanceText], studiedToday:, streak:, exam:, flags:, now:) -> GlanceSnapshot`. It leaves out occlusion cards (they need a picture), caps the list at 50, sorts by due date, and truncates text on grapheme boundaries. `GlanceDeckInput` is `{id, name, subject, cards: [AnkiCard]}`. Card text is rendered by the app (below), so this file does not pull in `CardQuality`.
- **`GlanceJournal.swift`** (pure). It covers:
  - `rate(card:, rating:, journal:, now:) -> GlanceRating`, whose base is the latest journal record, then `card.record`, then a new record, followed by `ReviewPlan.after`;
  - `effectiveQueue(snapshot:, journal:, now:)`: a journaled record replaces the card's due date, so an "Again" card comes back after one minute;
  - `pending(journal:, after watermark:)`;
  - `pruned(journal:, now:)`: drops entries older than 14 days and keeps at most 500;
  - a double-tap guard that ignores a second rating of the same card within 2 seconds.
- **`GlanceStore.swift`** (Foundation, file I/O).
  - It resolves the container from the Info.plist key `RedPenAppGroup` via `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`. If the key or the entitlement is missing (Playgrounds), it falls back to `Application Support/Glance` and sets `isShared = false`. `init(directory:)` exists for tests.
  - Each file has exactly one writer:
    - `snapshot.json` and `library-index.json`: written **only by the app**;
    - `journal.json` and `widget-state.json`: written **only by the extension**. The app never truncates the journal; it keeps a drain watermark in its own `UserDefaults.standard` (`glance.drainedThrough`).
  - All writes are `.atomic`. Files use `FileProtectionType.completeUntilFirstUserAuthentication`, because Lock Screen widgets have to read them while the phone is locked.
  - `static let defaults = UserDefaults(suiteName: group) ?? .standard` holds `exam.date`, `exam.minuteOfDay` and the surface toggles.
  - `wipe()` removes everything.
- **`ExamCountdown.swift`** (pure).
  - `struct ExamPlan: Codable, Hashable { var title: String; var day: Date; var minuteOfDay: Int = 540 }` with `start(in: Calendar)`.
  - `daysLeft(plan, now, calendar)` counts calendar days, so it is safe across DST.
  - `label(days)`: "Today", "Tomorrow", or "N days", localised.
  - `gaugeFraction(plan, setAt:, now)`.
  - `midnights(from:, count: 8)` for the widget timeline.
  - `liveActivityWindow(plan, now, calendar) -> (start: Date, stale: Date)?`, where start = max(examStart − 8h, 06:00 on exam day, now). The result is nil if the exam has already started, or if fewer than 15 minutes would remain before it. stale = examStart + 4h.
- **`ExamDayAttributes.swift`**
  ```swift
  struct ExamDayAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable { var dueCount: Int; var rule: String? } // rule ≤120 chars
    var examTitle: String; var examStart: Date }
  ```
- **`GlanceViews.swift`** (SwiftUI). All widget and Live Activity views live here, so the app can also render them for CI screenshots through `PreviewExtras`.
  - Only leading/trailing alignment, so Arabic lays out right to left automatically. Numbers use `.formatted()`, which gives Arabic-Indic digits under `ar`.
  - Card text carries `.privacySensitive()`.
  - Every button has an accessibility label.
  - The palette is a small set of local constants; `Theme.swift` is not imported.
  - Countdowns use `Text(timerInterval: now...examStart, countsDown: true)` and `ProgressView(timerInterval:)`, so no updates need to be pushed.

### 2.2 Shared by the app and the extension: `ios/RedPen/Shared/Intents/` and `DeepLink.swift`

- **`Shared/DeepLink.swift`** (pure).
  ```swift
  enum DeepLink: Equatable { case due(card: UUID?), set(UUID), quiz(subject: String?, count: Int), exam }
  init?(url:)   // scheme "redpen" only; hosts due|set|quiz|exam; UUIDs validated;
                // subject ≤80 chars, count clamped 5...50; "auth" and anything unknown → nil
  var url: URL
  init?(spotlightID:)   // "set:<uuid>", "item:<setUUID>:<itemUUID>" → .set
  ```
  Deep links only navigate. No URL ever rates, deletes, buys or changes data, because any app or web page can open a custom scheme.
- **`Shared/Intents/StudySetEntity.swift`**. `StudySetEntity` and `StudySetQuery` move here out of `DeckExportIntents.swift`. The query now reads `library-index.json` through `GlanceStore`, which is cheap and works inside the extension. It falls back to `Store()` only under `#if !WIDGET_EXTENSION`, when the index is missing. The file also adds `EntityStringQuery` (`entities(matching:)`), and under `#if !SWIFT_PACKAGE` an `IndexedEntity` conformance.
- **`Shared/Intents/SubjectEntity.swift`**. `SubjectEntity: AppEntity` has id = the folded subject and a display name. Its `EntityStringQuery` reads library-index subjects and set names. `suggestedEntities` returns the subjects sorted by set count.
- **`Shared/Intents/SubjectMatch.swift`** (pure).
  - `fold(_:)`: lower-cases, drops diacritics, and normalises Arabic (removes tashkeel U+064B–U+0652 and tatweel U+0640; أ/إ/آ→ا, ة→ه, ى→ي).
  - `score(query:, subject:, setName:) -> Int`.
  - A small synonym table: cardiology ↔ cardio, cardiac, heart, قلب; renal ↔ nephrology, kidney, كلى; and so on for about 20 specialties.
- **`Shared/Intents/GlanceIntents.swift`**. These run in the **extension process**, which is where widget button intents run by default. All have `isDiscoverable = false`, so they never appear in Shortcuts.
  - `RevealGlanceCardIntent(cardID: String)` writes `widget-state.json`.
  - `RateGlanceCardIntent(cardID: String, rating: GlanceRatingValue)`, where `GlanceRatingValue` is an `AppEnum` (again, hard, good, easy). It checks that the card is in the snapshot, applies `GlanceJournal.rate`, appends to `journal.json` and clears the reveal. WidgetKit reloads the timeline itself after a button intent.
  - `OpenDueReviewIntent`, for the Control. It is compiled into both targets, has `supportedModes = .foreground(.immediate)`, and `perform` sets `AppRouter.shared.pending = .due(card: nil)` inside `#if !WIDGET_EXTENSION`. The system opens the app, which is Apple's documented pattern for controls that open their app.
  - **The widget intents deliberately do not use `LiveActivityIntent` to force themselves into the app process.** That uses the protocol for something it was not designed for, and it is a review risk. The journal design makes it unnecessary.

### 2.3 App-only files (never compiled into the extension)

- **`ios/RedPen/Persistence/GlancePublisher.swift`** (`@MainActor final class`)
  - `drainWidgetRatings()`:
    1. Read the journal and keep entries newer than the watermark.
    2. Validate each entry: the card exists in the library, the rating parses, `ratedAt` is no more than 5 minutes in the future, and `intervalMin` is between 0 and 3650 days.
    3. Pass them to `reviews.merge([cardID: record])`. It keeps the later `ratedAt`, so a card rated in the app after the widget is never overwritten.
    4. Call `StudyLog.shared.record(n)` and move the watermark forward.
    5. Count `widget.rate` for Group E, only if the user opted in.
  - `publish()`:
    1. Always drain first.
    2. Render the text: the prompt comes from `QuizFromCards.stem` (a cloze with a blank), and the answer from the bullets joined with " · " or the cloze filled via `CardQuality.clozeBare`.
    3. Call `GlanceBuilder.build`.
    4. Write the snapshot only if its digest changed, then call `WidgetCenter.shared.reloadTimelines(ofKind:)` only for the kinds that changed. This protects WidgetKit's reload budget.
    5. Write `library-index.json` when the library changes.
    6. Call `RedPenShortcuts.updateAppShortcutParameters()` when the set of subjects changes.
  - Triggers:
    - `store.changeCount` / `reviews.changeCount`, debounced 3 s;
    - scenePhase `.active` (drain, then publish);
    - `.background` (publish);
    - after `SyncEngine` adopts remote reviews;
    - the existing background refresh in `CloudJobCollector`.
  - Encoding runs off the main thread on value copies.
- **`ios/RedPen/Shared/AppRouter.swift`**: `@MainActor final class AppRouter: ObservableObject { static let shared; @Published var pending: DeepLink? }`. A pending link stays until `LibraryView` consumes it. That covers cold launches, sign-in and the terms screen.
- **`ios/RedPen/Shared/Spotlight/SpotlightPlan.swift`** (pure).
  - `diff(previous: [String: Date], current: [SpotlightSource]) -> (upsert: [UUID], removeSets: [UUID])`, plus caps: at most 300 items per set and at most 5,000 in total, newest sets first.
  - Item ids are `set:<uuid>` (domain `sets`) and `item:<set>:<item>` (domain `set.<uuid>`), so deleting one set's domain removes all of its questions and cards.
- **`ios/RedPen/Shared/Spotlight/SpotlightIndexer.swift`**
  - Index: `CSSearchableIndex(name: "vignette", protectionClass: .completeUntilFirstUserAuthentication)`.
  - Set items: `CSSearchableItemAttributeSet(contentType: .content)` with the title, the description `"\(kind.label) · \(count) \(noun)s · \(subject)"`, keywords [subject, kind, exam track], and creation and modification dates.
  - Question/card items: the stem or front as title, and the set name as description.
  - Items are indexed in batches of 200 on a utility task. Stamps are kept in `Application Support/spotlight-stamps.json`.
  - Under `#if !SWIFT_PACKAGE`: `item.associateAppEntity(StudySetEntity(...), priority:)` (iOS 18 API; check the exact signature at implementation time).
  - Two toggles, "Show in Spotlight" and "Include questions and cards", both default on. Turning either off calls `deleteSearchableItems`.
- **`ios/RedPen/Shared/LiveActivities/ExamDayScheduler.swift`**. `sync(plan: ExamPlan?, enabled: Bool, dueCount:, rule:)`:
  1. List `Activity<ExamDayAttributes>.activities`, which on iOS 26 includes pending ones.
  2. End any activity whose attributes differ, with `.immediate`.
  3. If the window has already begun, request now with `pushType: nil`.
  4. Otherwise call `Activity.request(attributes:content:pushType: nil, style: .standard, alertConfiguration: AlertConfiguration(title: "Exam day", body: "\(title) at \(time). You've got this.", sound: .default), start: window.start)`.
  5. When the app is open on exam day, call `update` with the due count.

  Errors are logged and retried on the next `.active`, since how far ahead a start may be scheduled is not documented. It runs on every `.active` and whenever the exam settings change. Guards: `SystemSurfaces.liveActivities`.
- **`ios/RedPen/Shared/SystemSurfaces.swift`**
  ```swift
  enum SystemSurfaces {
    static let hasWidgetExtension: Bool = {
      #if SWIFT_PACKAGE
      return false
      #else
      guard let dir = Bundle.main.builtInPlugInsURL,
            let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
      else { return false }
      return items.contains { $0.pathExtension == "appex" && $0.lastPathComponent.hasPrefix("RedPenWidgets") }
      #endif
    }()
    static var liveActivities: Bool { hasWidgetExtension && ActivityAuthorizationInfo().areActivitiesEnabled && RemoteFlags.liveActivity }
    static var appGroup: Bool { GlanceStore.shared.isShared }
  }
  ```
- **`ios/RedPen/Features/Intents/QuizIntents.swift`**
  - `QuizMeIntent`: `@Parameter subject: SubjectEntity?` and `@Parameter count: Int = 10`, with `supportedModes = .foreground(.immediate)`. `perform` routes to `.quiz`.
  - `ReviewDueIntent`: foreground, routes to `.due`.
  - `DueCountIntent`: runs in the background and reads the snapshot. It returns `ReturnsValue<Int> & ProvidesDialog & ShowsSnippetView`, for example "34 cards are due. Your exam is in 23 days."
  - `ExamCountdownIntent`: runs in the background, with a dialog.
  - `OpenStudySetIntent: OpenIntent` (target `StudySetEntity`), for taps from Spotlight and Siri.

  The new intents use `supportedModes`, not `openAppWhenRun`, which iOS 26 deprecates.
- **`ios/RedPen/Features/Settings/SurfacesSection.swift`**. This is a "Home Screen, Lock Screen & Siri" section:
  - the Spotlight toggles;
  - "Exam-day Live Activity" (default on once an exam date is set, with a footer explaining it);
  - "Show a rule from your rule sheet on the Lock Screen" (default off);
  - "Answer cards in widgets" (default on);
  - a Siri tip (`SiriTipView(intent: QuizMeIntent())`) and a `ShortcutsLink()`.

  In the Playgrounds build it shows one line in their place: "Widgets, Live Activities and Siri phrases come with the App Store version."
- **`Persistence/StoreStudy.swift`**, new `extension Store`: `func subjectQuiz(matching: String?, count: Int) -> StudySet?`.
  1. Use MCQ questions from sets that `SubjectMatch` ranks highly.
  2. If there are none, build questions from cards with `QuizFromCards.build`.
  3. Pass the result to `temporaryQuiz`. If nothing matches, return nil; the router then opens Due Today and shows a notice.

### 2.4 Extension-only files: `ios/RedPenWidgets/`

- `RedPenWidgetsBundle.swift`: `@main struct RedPenWidgets: WidgetBundle` containing `DueCardWidget()`, `ExamCountdownWidget()`, `TodayWidget()`, `ReviewControl()` and `ExamDayLiveActivity()`.
- `DueCardWidget.swift`:
  - `AppIntentConfiguration` with `DueCardConfig: WidgetConfigurationIntent { @Parameter deck: StudySetEntity? }`.
  - `AppIntentTimelineProvider` loads the snapshot, journal and state, then `GlanceJournal.effectiveQueue`. It makes entries at now and at each future due time in the next 24 h (at most 12), with policy `.after(next due or midnight)`.
  - The entry's state is `.card`, `.empty` ("All done"), `.stale` (snapshot more than 3 days old: "Open Vignette to refresh"), or `.needsApp` (no shared group or version mismatch).
  - `widgetURL(DeepLink.due(card:).url)`. The rating buttons are hidden when `flags.ratings == false`.
- `ExamCountdownWidget.swift` and `TodayWidget.swift`: `StaticConfiguration`, a timeline of midnights, policy `.atEnd`.
- `ReviewControl.swift`: `ControlWidgetButton(action: OpenDueReviewIntent())`.
- `ExamDayLiveActivity.swift`: `ActivityConfiguration(for: ExamDayAttributes.self)`.
  - Lock Screen: exam title, the countdown to the start, the due count, and the optional rule.
  - Dynamic Island: compact leading a book symbol; compact trailing and minimal the timer; expanded adds the rule.
  - After the start: "Good luck", then dismissed at the stale date.
- `Info.plist`, `RedPenWidgets.entitlements`, and `Localizable.xcstrings` (en, ar) for the gallery names and descriptions. Suggested description: "Answer a due card from your Home Screen. For study, not clinical decisions."

### 2.5 Existing files that change

These are touched by the jobs editing now, so coordinate merges.

| File | Change |
|---|---|
| `Features/Library/DeckExportIntents.swift` | Move the entity and query out (§2.2). Add `QuizMeIntent`, `ReviewDueIntent`, `DueCountIntent` and `ExamCountdownIntent` to `RedPenShortcuts`, making 6 of the 10 allowed. Phrases: "Quiz me on \(\.$subject) in \(.applicationName)", "\(.applicationName) quiz on \(\.$subject)", "Quiz me with \(.applicationName)", "Review my \(.applicationName) cards", "How many \(.applicationName) cards are due", "How long until my exam in \(.applicationName)". |
| `RedPenApp.swift` | Own a `GlancePublisher`. Add `.onOpenURL { AppRouter.shared.pending = DeepLink(url: $0) }`, `.onContinueUserActivity(CSSearchableItemActionType)` and `.onContinueUserActivity("com.cramdown.app.set")`. Wire the publisher's triggers into the existing `onReceive` debounce and the `phase` handlers. On `.active`, call `ExamDayScheduler.sync`. The `redpen://auth` callback is ignored here (it goes through the web-auth session). |
| `Features/Library/LibraryView.swift` | `.onReceive(AppRouter.shared.$pending.compactMap { $0 })`: `.due` → `showingDue = true`; `.set` → `opened = [set]`; `.quiz` → `quickQuiz = store.subjectQuiz(...)`; `.exam` → the settings page. Clear it once handled. |
| `Features/Anki/DueTodayView.swift` | Optional `startAt: UUID?`, which puts that card first. |
| `Shared/ExamTrack.swift` | The date and the new `exam.minuteOfDay` are read from `GlanceStore.defaults`, with a one-time copy from `.standard` on first launch. Add `shortTitle` ("PLAB 1", "USMLE", "MRCP", "MRCS"). |
| `Features/Support/ModelSettingsView.swift` | `@AppStorage(..., store: GlanceStore.defaults)`. Add a "Starts at" time picker (`.hourAndMinute`, default 09:00) and embed `SurfacesSection`. |
| `Shared/BackgroundWork.swift` | `AppNotifications.scheduleReviews` stays as it is. The background refresh in `CloudJobCollector` also calls `publisher.publish()`. |
| Set detail screen(s) | `.userActivity("com.cramdown.app.set") { $0.title = set.name; $0.userInfo = ["id": ...]; $0.isEligibleForSearch = false; $0.isEligibleForPrediction = true }`. Spotlight is handled by CoreSpotlight, so the set is not indexed twice. |
| `Shared/PreviewExtras.swift` | A `surfaces` screen that renders `GlanceViews` at widget sizes (small 170×170, medium 364×170, large 364×382, and the accessory sizes) in light, dark and Arabic RTL, for the preview workflows. |

## 3. `ios/project.yml`

```yaml
settings:
  base:
    RED_PEN_APP_GROUP: group.com.cramdown.app      # one place; personal.yml may override
targets:
  RedPen:
    dependencies:
      - target: RedPenWidgets
        embed: true
    entitlements:
      properties:
        com.apple.security.application-groups: [$(RED_PEN_APP_GROUP)]
    info:
      properties:
        NSSupportsLiveActivities: true
        NSUserActivityTypes: [com.cramdown.app.set]
        RedPenAppGroup: $(RED_PEN_APP_GROUP)
  RedPenWidgets:
    type: app-extension
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - path: RedPenWidgets
      - path: RedPen/Shared/Glance
      - path: RedPen/Shared/Intents/StudySetEntity.swift
      - path: RedPen/Shared/Intents/GlanceIntents.swift
      - path: RedPen/Shared/DeepLink.swift
      - path: RedPen/Models/AnkiCard.swift
      - path: RedPen/Shared/ReviewPlan.swift
      - path: RedPen/Features/Anki/AnkiScheduler.swift
    entitlements:
      path: RedPenWidgets/RedPenWidgets.entitlements
      properties:
        com.apple.security.application-groups: [$(RED_PEN_APP_GROUP)]
    info:
      path: RedPenWidgets/Info.plist
      properties:
        CFBundleDisplayName: Vignette
        NSExtension: { NSExtensionPointIdentifier: com.apple.widgetkit-extension }
        RedPenAppGroup: $(RED_PEN_APP_GROUP)
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.cramdown.app.widgets
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) WIDGET_EXTENSION"
        APPLICATION_EXTENSION_API_ONLY: YES
        SKIP_INSTALL: YES
```

- LocalLLMClient is **not** linked into the extension. Widgets have a memory limit of about 30 MB; the snapshot is under about 100 KB.
- Files in `Shared/Glance` belong to both targets. The app target's `excludes: Tests/**` stays.
- **The App Group id must not depend on the Playgrounds bundle id.** Playgrounds has no entitlement, so `GlanceStore` falls back to its own sandbox.

## 4. How it behaves in each build

- **Playgrounds.**
  - `#if SWIFT_PACKAGE` is true and there is no appex, so every widget and Live Activity path is off, and the settings section says they come with the App Store version.
  - `GlancePublisher` still runs against the sandbox fallback: it writes about 100 KB and the widget reloads do nothing. This keeps a single code path.
  - Spotlight works. App Intents compile; if the metadata is not extracted, Siri and Shortcuts simply don't list them, and nothing inside the app depends on that.
  - Deep links only matter inside the app.
- **Xcode / App Store.** Everything is on.
- **iPad.** Widgets and Control are available. The Live Activity toggle is hidden whenever `areActivitiesEnabled` is false.

## 5. App Store Review risks and how to stay compliant

- **2.5.16** (widgets, extensions and notifications must relate to the app): every surface shows the student's own cards, schedule or exam. No ads and no cross-promotion.
- **4.5.3** (no unsolicited Live Activities): the Live Activity starts only after the student sets an exam date, and there is a visible toggle with a footer explaining it. There is exactly one per exam and it is never used for marketing.
- **2.5.11** (Siri / Shortcuts): the phrases describe only what the app does and all include the app name. No intent claims to diagnose or treat.
- **1.4.1** (medical): the gallery description, the Siri dialogs and Spotlight descriptions say "study" and never "diagnose"; the widget description carries the education disclaimer. Lock Screen content is only what the student wrote.
- **3.1.1**: no purchasing or Pro upsell in any extension surface. If a surface is ever made Pro, it shows "Open Vignette" and nothing else.
- **2.5.1** (public APIs only): no process-hopping tricks, no private APIs.
- **5.1.1 / privacy labels**: all data stays on the device (App Group, on-device Spotlight index), and nothing is collected. The Group E counters are opt-in and aggregate-only, covered by E's label entry.
- **Accessibility**: Dynamic Type, VoiceOver labels on the rating buttons, and `.privacySensitive()` redaction when locked.

## 6. Server touchpoints (no D1 changes)

**Group D's `GET /config`** (KV or D1, owned by D). Group C adds these keys, and the app writes the effective values into `GlanceSnapshot.flags` so the extension respects them without going online:

```json
{ "surfaces": { "widgets": true, "widgetRatings": true, "liveActivity": true,
                "spotlight": true, "spotlightItems": true, "spotlightMaxItems": 5000,
                "siriQuizMax": 50 } }
```

The defaults above are baked into the app, so a missing config means everything stays on.

**Group E's opt-in counter endpoint.** Allowlist these event names: `widget.rate`, `widget.open`, `control.open`, `la.scheduled`, `la.started`, `intent.quiz`, `intent.due`, `intent.countdown`, `spotlight.open`. The extension never makes network calls; the app counts on drain or launch.

**Considered and rejected:** push-to-start or updates for the Live Activity through APNs. That needs an APNs `.p8` key (a manual step for the owner and one more secret) and gains nothing over the local scheduled start.

## 7. Security and privacy

- **No tokens or network in the extension.** There is no shared keychain access group. The session token stays in the app's keychain.
- **What the App Group holds:** the text of at most 50 due cards, the library index (names and subjects only), the exam plan and flags. No images, answer history, account id or email.
- **Wipe.** "Show cards in widgets" off → `GlanceStore.wipe()`, `WidgetCenter.reloadAllTimelines()`, and all Live Activities ended. Deleting the account or erasing the library does the same and also deletes the Spotlight index.
- **Journal input is validated before merging** (§2.3), so a tampered container cannot inject nonsense into the schedule.
- **URL handling:** an allowlist of hosts and validated parameters. Links only navigate and never change data.
- **Lock Screen:** accessory widgets show only counts and days. Card text is marked `.privacySensitive()`. The Live Activity rule is off by default.
- **Siri:** `DueCountIntent` and `ExamCountdownIntent` expose only numbers, so they may run while locked. `QuizMeIntent` opens the app, which needs an unlock.
- **Remote kill switch** for each surface (§6).

## 8. Tests

**Swift suites.** These are Foundation-only `main.swift` suites in `ios/RedPen/Tests/`, with lines added to `swift-tests.yml`:

```
suite glance GlanceTests.swift $M/AnkiCard.swift $F/Anki/AnkiScheduler.swift $S/ReviewPlan.swift \
      $S/Glance/GlanceModels.swift $S/Glance/GlanceBuilder.swift $S/Glance/GlanceJournal.swift \
      $S/Glance/GlanceStore.swift $S/Glance/ExamCountdown.swift
suite surfaces SurfacesTests.swift $S/DeepLink.swift $S/Intents/SubjectMatch.swift $S/Spotlight/SpotlightPlan.swift
```

GlanceModels must not import ActivityKit; keep `ExamDayAttributes` in its own file, outside these suites. Add `ios/RedPen/Persistence/**` to the workflow's `paths` only if the publisher's logic moves into a pure file.

- **GlanceTests** check:
  - the builder leaves out occlusion cards, caps at 50, sorts by due date, truncates at grapheme boundaries (including Arabic text and emoji), and counts `dueNow` beyond the cap;
  - a rating equals `ReviewPlan.after` exactly;
  - an "Again" card comes back in the effective queue after one minute;
  - a double tap within 2 s is ignored;
  - pruning (14 days / 500 entries);
  - draining past the watermark, and a merge with a newer in-app `ratedAt` keeping the app's record;
  - a snapshot with an unknown version decodes to empty;
  - GlanceStore works in a temporary directory: one writer per file, atomic round trip, wipe.
- **ExamCountdown tests** check:
  - days left across a DST change and in a UTC+2/+3 time zone (Cairo);
  - the Today and Tomorrow labels;
  - the window: exam at 09:00 starts at 06:00 (not 01:00); exam at 14:00 starts at 06:00; exam at 06:10 gives nil (less than 15 minutes); a past exam gives nil;
  - the gauge fraction is clamped to 0...1.
- **SurfacesTests** check:
  - DeepLink round trips for every case; bad UUIDs, other schemes, `auth` and unknown hosts are rejected; count is clamped; subjects over 80 characters are cut;
  - Spotlight ids parse;
  - SubjectMatch: "cardiology" matches "Cardiology" and "Cardio L3"; "قلب" matches Arabic subjects written with tashkeel or alef variants; the empty query case;
  - SpotlightPlan: a changed set is upserted, a deleted set's domain is removed, and the caps are enforced.

**CI (`app-build.yml`).** After the build, assert that:
- `RedPen.app/PlugIns/RedPenWidgets.appex` exists;
- the app's Info.plist has `NSSupportsLiveActivities` true;
- `grep -rq QuizMeIntent RedPen.app/Metadata.appintents` succeeds, which catches missing App Intents metadata.

**UI test (`ios/UITests`).** After the existing sign-in and terms taps, `app.open(URL(string: "redpen://due")!)` shows Due Today, and `redpen://quiz?subject=cardiology` opens a quiz or the "nothing matched" notice. `ios-preview.yml` screenshots the `surfaces` preview screen in en and ar.

**Server.** No new server test file for Group C. Add two assertions to Group D's and E's tests:
- the `/config` defaults include `surfaces.*` with safe values;
- the counter allowlist accepts the Group C events and rejects an unknown one with 400.

## 9. Build order

1. DeepLink and AppRouter, `onOpenURL`/`onContinueUserActivity`, the library index and snapshot publisher, SubjectMatch, the App Intents and updated `RedPenShortcuts`, and Spotlight. All of this works in Playgrounds.
2. The widget extension and project.yml target: Due card (interactive), Exam countdown, Today, Control, and the CI checks.
3. The exam-day Live Activity, exam time picker and settings section.
4. Optional: a "Study sprint" Live Activity started from Due Today (cards left plus an elapsed timer, well under 8 h), and a Siri interactive snippet for answering a question inside Siri (iOS 26 `SnippetIntent`).

## 10. The owner's unavoidable publish-time steps (Group C)

1. **Signing.** If the release workflow signs with an App Store Connect API key and `-allowProvisioningUpdates`, Xcode's automatic signing should register `com.cramdown.app.widgets` and `group.com.cramdown.app` without the owner doing anything. **Only if the signing log says the App Group was not found**: at developer.apple.com, open Identifiers → App Groups → **+**, create `group.com.cramdown.app`, then tick App Groups on both App IDs (`com.cramdown.app` and `com.cramdown.app.widgets`) and assign that group. This is a one-time step of about 5 minutes.
2. **App Review notes** (paste into App Store Connect): "Widgets: long-press the Home Screen → + → Vignette. The Due card widget answers cards with its buttons. Live Activity: Settings → Your exam → set a date for today and a start time about 2 hours ahead; it appears on the Lock Screen. Siri: 'Quiz me on cardiology in Vignette' (the demo account's library includes a Cardiology set)."
3. **Privacy label:** no change needed for Group C (Data Not Collected).
4. Nothing else. The extension ships inside the app binary, there is no APNs key, there is no separate App Store Connect record, and widget screenshots are optional.

## 11. Things to avoid

- A new `SyncKind` (it would break older app versions).
- Push-started Live Activities.
- `LiveActivityIntent` used to force widget intents into the app process.
- Any network call, token or StoreKit use in the extension.
- Anything `@main` inside `ios/RedPen` apart from the app.
- A second `AppShortcutsProvider`.
- Loading `Store()` from queries that run in the extension.

Sources:
- [Forcing an AppIntent to run in the main app process (Zach Waugh)](https://zachwaugh.com/posts/forcing-appintent-to-run-in-main-app-process)
- [Apple forum: interactive widget intents](https://forums.developer.apple.com/forums/thread/732771)
- [Expo PR: iOS 26 scheduled Live Activity start](https://github.com/expo/expo/pull/50248)
- [Live Activities essentials, WWDC26](https://wwdc.ai/2026/223)
- [Apple forum: Live Activity max duration](https://developer.apple.com/forums/thread/797676)
- [Canopas: Live Activity guide (8h/12h, 4KB)](https://canopas.com/integrating-live-activity-and-dynamic-island-in-i-os-a-complete-guide)
- [What's new in App Intents (IndexedEntity), WWDC24](https://developer.apple.com/videos/play/wwdc2024/10134/)
- [Apple docs: supportedModes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)
- [Explore new advances in App Intents, WWDC25](https://developer.apple.com/videos/play/wwdc2025/275/)
- [Superwall: interactive snippets in iOS 26](https://superwall.com/blog/app-intents-interactive-snippets-in-ios-26)
- [Apple forum: AppIntents missing from Shortcuts in SPM](https://origin-devforums.apple.com/forums/thread/759160)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
