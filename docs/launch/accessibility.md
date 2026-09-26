# Stethoscore: accessibility and the App Store labels

Written 2026-09-26 for the App Store (Xcode) build of `com.cramdown.app`. It covers gap #9 in the gap analysis.

The App Store shows **Accessibility Nutrition Labels** on the product page. Apple lets an app claim a label only if people can finish the app's **common tasks** with that feature on. For Stethoscore the common tasks are:

- opening the library and a set;
- answering a question set;
- reviewing flashcards (reveal, rate, undo);
- working through an OSCE station or a case;
- checking Mission Control and the exam plan;
- changing Settings.

The table says which labels to claim and why. Section 3 lists what has still not been checked.

---

## 1. Labels

| Label | Claim? | What the app does |
|---|---|---|
| **VoiceOver** | Yes, once the check in §3 passes | Every control in the common tasks has a label, and a value or hint where one helps. Headers are marked as headers. Custom swipes and long presses are also VoiceOver actions: crossing out an option, burying or suspending a card, fixing a narrated word, dismissing a note. Results are announced as they happen: "Correct." or "Incorrect. The answer is C: …"; "Rated Good, back in 4 days"; the revealed card, step or case answer. Undo stays on screen until the next rating while VoiceOver is on, instead of disappearing after 5 seconds. |
| **Larger Text** | Yes | All app text uses Dynamic Type. The big numbers (score, countdown, pairing code, calculator) use `scaledFont`: the same size as before at the default setting, and they scale from there. At the accessibility sizes: the dock becomes one button that opens a list of sections, the view switcher opens a list, tiles go one across, the card ratings go one per row, and quiz options, card faces, OSCE steps and Mission Control lines wrap instead of cutting off. |
| **Dark Interface** | Yes | The whole app is dark by default: the night-sky backdrop, and "Always night sky" in Settings. It also follows the system's dark mode. |
| **Differentiate Without Colour Alone** | Yes | Right and wrong answers carry a tick or a cross, and with the setting on also the words "Right" / "Your pick" and a thicker border on the chosen option. On the study calendar, each day is one of five steps, and with the setting on each step is also a dot that grows with the step. Coverage shows its status as a word, plus a full, half or dashed circle with the setting on. The accuracy badge always shows a symbol and a word. The exam day in the due chart has a flag. |
| **Sufficient Contrast** | Yes, based on Increase Contrast | With Increase Contrast or Reduce Transparency on, every glass surface becomes a solid surface with a visible edge (`accessibleGlass`), and the backdrop's nebula drops to half strength with more ink behind the text. Text on the default glass sits over a darkened column of sky. |
| **Reduced Motion** | Yes | Reduce Motion stops the sky and every pop-out (`SpaceQuality.still`). The card flip, rise-in, rings and score animations were already turned off by it. Slides and zooms now become plain fades (`slideFade`, `growFade`), the dock's moving capsule jumps instead of travelling, and the listening waveform stays still. |
| **Voice Control** | Not claimed yet | It probably works, because every control has a visible name or label. It has not been checked. |
| **Captions** / **Audio Descriptions** | Not applicable | The app has no video. Narrated lectures show their text as it is read. |

The Ideas 3D map (`Features/Notes`, `Shared/Space`) is handled in a separate lane and is not part of these claims. It is not one of the common tasks listed above.

---

## 2. Where it lives

- `Shared/AccessibilitySupport.swift`: `scaledFont`, `Announce`, `Motion`, the `slideFade`/`growFade` transitions, `minimumHitTarget` and `GridItem.tiles`.
- `Shared/LiquidGlass.swift`: `accessibleGlass`. Every glass surface outside the map goes through it.
- `Shared/AccessibilityText.swift`: the words VoiceOver says (`SpokenText`) and the calendar's five steps (`HeatLevel`). The Linux suite `accessibility` checks them (`Tests/AccessibilityTextTests.swift`).
- `ios/UITests/AccessibilityUITests.swift`: at the largest text size (AX5), it walks the library, every section, a quiz, a card, Settings and the exam plan. It checks each control it needs is there, can be pressed, and fits inside the window. Then it runs Xcode's `performAccessibilityAudit()` on the library, the quiz, the revealed card and Settings.
  - The audit skips **colour contrast**. The audit samples one frame, and the drifting sky behind Liquid Glass changes from frame to frame.
  - Two narrow cases are let through, each with a comment in the test: the system navigation bar truncating its own title, and capped symbols.

Hit targets are at least 44 × 44 points: the Undo chip, the accuracy badge, Study Lens chips, the tag remove button and the photo-card answer rows were raised to 44.

---

## 3. What has not been checked yet

Nothing here has run on a device or a simulator yet. The Linux toolchain can only parse SwiftUI.

Before ticking the labels in App Store Connect, both of these must be done:

1. **The UI test run.** `AccessibilityUITests` runs with the rest of the UI tests in the "App build" workflow. Both tests must pass. If the audit reports an issue, fix it rather than adding it to the ignore list.
2. **A VoiceOver pass on the iPhone.** Turn it on with Settings → Accessibility → VoiceOver, or triple-click the side button if the Accessibility Shortcut is set. Then:
   - open a set;
   - answer one question and listen for "Correct." or "Incorrect…";
   - review three cards, including Undo;
   - step through one OSCE station.

   Also try Larger Text at the largest size (Settings → Accessibility → Display & Text Size → Larger Text).

Labels are set in App Store Connect, in the app's accessibility section, or through the API, as the launch checklist says. Claim only the rows marked **Yes** above.
