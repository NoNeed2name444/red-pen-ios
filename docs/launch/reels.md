# Vignette: launch reels (TikTok, Instagram Reels, YouTube Shorts)

Written 2026-09-24 against `preview/graph`. This is one of the group G launch documents listed in `implementation-plan.md`. Two packages consume it:

- **P3.2** builds `reel-footage.yml` and `ios/UITests/ReelFootageUITests.swift` from the shot lists below (Part C).
- **P6.1** reads the beat tables to produce caption overlays and `.srt` files. The table format is fixed so a script can parse it: `| t | Shot | On-screen EN | On-screen AR |`, where `t` is `start-end` in seconds.

There are ten reels, each 15 to 30 seconds long, and each comes in English and Egyptian Arabic. **None of them uses "challenge a friend", "tag a friend who…", duels between people or any other head-to-head framing.** The owner rejected that idea. Every reel is one student studying on their own. The call to action is always "save this for exam week" or "link in bio", never "send this to someone to beat".

---

## Part A. Rules every reel follows

These were checked against current sources (listed at the end). Several reels double as App Store app previews, so the stricter Apple rules apply to all ten. That way no reel needs a second edit.

| Rule | Why | What it means for the reels |
|---|---|---|
| **Length 15–30 s, 30 fps, portrait** | Apple app previews must be 15–30 s at 30 fps. Shorts and Reels allow up to 3 min, but a Reel longer than 3 min is not recommended to non-followers. | Every script fits 15–30 s, so one master works for the App Store and all three platforms. |
| **Only footage captured from the app** | Apple: previews "must show only content within the app itself", with no fingers, no over-the-shoulder shots and no device frames. | Screen recordings only. The one exception is the optional bus b-roll in reel 3, which is marked **social cut only**. |
| **No prices on screen, and nothing tied to a date** | Apple: no specific prices, and no seasonal or timely references in previews. | Prices appear nowhere, and "finals" wording stays generic. Dates go only in the social *caption*, never in the video. |
| **Disclose Pro** | Apple: if a preview shows features that need an in-app purchase or subscription, it must say so in the footage or the end frame. | The end card on every reel carries the Pro line (A.2), and each reel is marked Free or Pro below. |
| **No real teaching material, no real patients** | A lecture PDF is its author's copyright. The personal build's bundled lecture "is someone's teaching material" (`SampleLectures.swift`), and patient data must never appear. | Every reel uses the **reel demo lecture** (A.3) or the app's own drawn examples (the heart diagram in `OcclusionExample.swift`). All patients are fictional and labelled that way. |
| **Education only** | This is a medical-education app, not a clinical one (design F). | Every end card includes the line "For study, not clinical decisions" / «للمذاكرة بس، مش للقرارات الطبية». |
| **Apple names and the badge** | Apple's marketing guidelines: never translate "App Store", "iPhone", "iPad" or "Apple Pencil". Use one unmodified badge per layout, subordinate, at least 40 px, and never animated. Use the localized badge artwork Apple provides (Arabic exists). Put a trademark credit line at the end of any video that uses Apple trademarks. | Arabic text keeps `iPhone`, `iPad`, `App Store` and `Apple Pencil` in Latin script. The badge appears only on the last 2 s of the end card, after launch; before launch the card says "Coming soon". |
| **Status bar** | Apple: show full signal, full Wi-Fi and full battery. | CI uses `simctl status_bar override` (Part C). For iPhone recordings, charge to 100 % and use Wi-Fi, or use the "fill" crop, which removes the status bar. |
| **Hashtags** | Instagram has capped hashtags at **5 per post or Reel** since December 2025, counting caption and first comment together. | Each reel lists exactly 5. The same 5 are used on TikTok and Shorts. |
| **Search keywords** | TikTok indexes spoken words, on-screen text and the caption. Current practice is to put the keyword in all three, in the first seconds and the first caption line. | Each reel names a **keyword**. It appears in the first on-screen line, the first caption line and (where there is a voice-over) the first spoken sentence. |
| **Music** | TikTok business accounts can only use the Commercial Music Library, and that licence covers TikTok only. Instagram business accounts get the smaller Meta Sound Collection. | CI masters contain **no music**, only app audio or voice-over. Any music is added inside each platform's own editor from that platform's commercial library. Never bake a track from one platform into another platform's upload. |
| **Paid partners** | Paying an ambassador (offer codes, free months) counts as branded content. TikTok requires the content-disclosure toggle, and Instagram uses the Paid partnership label. | Ambassadors who repost these reels switch on the disclosure and add `#ad` / `#إعلان` (see `ambassadors-and-referrals.md`). |
| **Exam names** | USMLE, PLAB/MLA, MRCP(UK) and MRCS belong to their owners. | Reel 10's end card adds: "Not affiliated with any exam body." |

### A.1 Formats CI produces for every reel and language

| File | Size | Use |
|---|---|---|
| `NN-slug-LANG-social.mp4` | 1080×1920, H.264 High, 30 fps, AAC 48 kHz stereo | TikTok, Reels, Shorts. The app screen is centred ("fit") and the captions are burned in. |
| `NN-slug-LANG-fill.mp4` | 1080×1920 | The same, with the screen scaled to the full width and the status bar and home indicator cropped away. Use it when the app UI is simple enough to survive the crop (reels 2, 4, 8). |
| `NN-slug-LANG-preview.mp4` | **886×1920**, 30 fps, 10–12 Mbps VBR, AAC 256 kbps stereo | App Store app preview (iPhone 6.9"/6.5"/6.1" all take 886×1920). Captions are burned in; the end card has no badge. |
| `NN-slug-LANG-cover.jpg` | 1080×1920 | The cover frame: the hook text over the most striking frame. |
| `NN-slug-LANG.srt` | n/a | Caption file for YouTube, and for TikTok or Instagram when burned-in text is off. |

### A.2 The shared end card (last 3 s of every reel)

| | EN | AR (Egyptian) |
|---|---|---|
| Line 1 (large) | **Vignette** | **Vignette** |
| Line 2 | Study app for medical students, on iPhone and iPad | تطبيق مذاكرة لطلبة الطب، على iPhone و iPad |
| Line 3 (small), only on Pro reels | Some features need Vignette Pro (subscription). | بعض المميزات محتاجة Vignette Pro (اشتراك). |
| Line 3 (small), on free reels | Free to download. Vignette Pro is an optional subscription. | التحميل ببلاش. Vignette Pro اشتراك اختياري. |
| Line 4 (small) | For study, not clinical decisions. | للمذاكرة بس، مش للقرارات الطبية. |
| Badge, last 2 s, after launch only | Apple's black "Download on the App Store" badge | Apple's Arabic "Download on the App Store" badge (Apple's artwork, never one we make) |
| Before launch | Coming soon to iPhone and iPad | قريب على iPhone و iPad |
| Credit (tiny, bottom) | iPhone, iPad and Apple Pencil are trademarks of Apple Inc., registered in the U.S. and other countries. App Store is a service mark of Apple Inc. | Same text, in English (Apple's credit lines are not translated) |

The brand name stays **Vignette** in Latin script in Arabic too, matching `CFBundleDisplayName`. If P5.7 decides on an Arabic display name, use that one here.

### A.3 The reel demo lecture (needed by reels 1, 4, 6, 9 and 10)

- A lecture PDF that the repository owns outright, written for the reels. Title: "Heart failure: Lecture 7". The lecturer is fictional ("Dr. N. Example"), and there are 20 slides.
- Aim for about **12,800–13,000 characters of text**. `MCQCoverage.suggestedCount` proposes `characters / 320` questions, so this length makes the app itself propose **40**. The "40 questions" number is then the app's own suggestion, not something forced for the video.
- Include **3 labelled diagrams**, drawn in code the same way `OcclusionExample` draws the heart: the heart's chambers, the Frank–Starling curve and the RAAS pathway. The occlusion reel then shows real diagram-finding on real labels.
- Include **2 slides saved as images**, so the "Read 20 pages, 2 by OCR" status is real.
- P3.2 generates it with a small script into `docs/launch/reel-assets/demo-lecture.pdf`, and CI copies it into the simulator. On a phone, the owner downloads it from the `reels` release and opens it with "Open in Vignette". No typing is needed.

### A.4 Honest editing

- Time compressed for pacing (generation, checking, transcription) is labelled with a small **"sped up"** / «متسرّع» tag in the corner while the compression lasts.
- Numbers on screen are whatever the app actually produced in that run. P3.2's test asserts on them: if the run made 38 questions, the caption says 38.
- Voices that are not the app's own (the "student" answering in reels 3 and 7 when made by CI) are labelled **"demo voice"** / «صوت تجريبي».

---

## Part B. The ten reels

Legend: **Free** means the reel shows features anyone can use. **Pro** means it shows Vignette Pro features, so the end card uses the Pro line. **Footage** says where the best take comes from:

- **CI**: fully automatic, silent video plus optional voice-over.
- **iPhone**: the owner's own screen recording, needed when real device audio, the microphone or tilt is the point.

Every reel can be made by CI alone (Part C), so the owner never *has* to record anything.

---

### Reel 1: Lecture PDF → 40 checked questions (hero reel, App Store preview #1)

- **Plan:** Pro (PDF reading, Vignette Cloud writing and checking)
- **Length:** 28 s
- **Footage:** CI (sped-up generation segment)
- **Keyword:** EN "lecture PDF to MCQs" / AR «أسئلة MCQ من المحاضرة»

**Hooks (first 2 s)**

- **TikTok:** spoken, and shown as text: "Lecture PDF to MCQs: I gave it 20 slides, it wrote 40 questions and checked every one against the slides."
- **Instagram:** cover text: "20 slides in → 40 exam questions out"
- **Shorts title:** "Lecture PDF → 40 MCQs, each checked against your slides"
- **AR hook (all platforms):** «محاضرة 20 سلايد ← 40 سؤال MCQ.. وكل سؤال متراجع على السلايدز»

| t | Shot | On-screen EN | On-screen AR |
|---|---|---|---|
| 0.0-2.5 | Library → New set → Lecture PDF; the file picker shows `Heart failure – Lecture 7.pdf` | Lecture PDF to MCQs | أسئلة MCQ من المحاضرة |
| 2.5-5.5 | `LecturePDFSection` status: "Read 20 pages, 2 by OCR, 3 labelled diagrams. 40 questions suits this much material." | It reads every slide, even the photographed ones | بيقرا كل السلايدز.. حتى المتصوّرة |
| 5.5-8.0 | The count field already shows 40; the button reads "Make 40 questions" | It picks the number for you: 40 for this lecture | وبيقترح العدد: 40 سؤال على قد المحاضرة |
| 8.0-12.5 | Progress "Writing 12 of 40 questions…" → "Checking 31 of 40" (**sped up** tag) | Writes 40 single-best-answer questions… | بيكتب 40 سؤال single best answer… |
| 12.5-15.0 | Progress finishes; the set appears in the Library | …and checks each one against YOUR lecture | …وبيراجع كل سؤال على محاضرتك إنت |
| 15.0-19.5 | Quiz: tap an answer → the `quiz-checked` state with the explanation | Explanation for every answer | شرح لكل إجابة |
| 19.5-24.0 | Tap the question's citation → the source viewer opens on slide 6 | Tap the source: it opens the exact slide | دوس على المصدر.. يفتحلك السلايد نفسها |
| 24.0-25.0 | "Check accuracy" sheet showing the verdict for this question | Checked for accuracy | متراجع على الدقة |
| 25.0-28.0 | End card (Pro) | (A.2) | (A.2) |

- **Voice-over (optional, EN, Aura "pandora" via `/tts`):** "Lecture PDF to MCQs. Twenty slides in, forty exam questions out, and every one is checked against the slides it came from. Tap the source and you're on the slide."
- **Caption EN:** "Lecture PDF to MCQs in one go: Vignette reads the slides (OCR too), suggests how many questions the lecture needs, writes them, and checks each against your own lecture. Every question links back to its slide. Save this for exam week."
- **Caption AR:** «حوّل أي محاضرة PDF لأسئلة MCQ: Vignette بيقرا السلايدز (حتى المتصوّرة)، بيقترح عدد الأسئلة، بيكتبها، وبيراجع كل سؤال على المحاضرة بتاعتك. وكل سؤال بيوديك للسلايد اللي جه منها. احفظ الفيديو ده لأسبوع الامتحانات.»
- **Hashtags (5):** `#medstudent #mcq #lecturenotes #studytok #طالب_طب`
- **App Store preview version:** the same master without the voice-over. Keep the text lines. The end card has no badge.

---

### Reel 2: Your notes as a galaxy of black holes (App Store preview #3)

- **Plan:** Free
- **Length:** 20 s
- **Footage:** iPhone preferred, because the Space view tilts with the phone (the `GraphSim` tilt rig) and the simulator cannot tilt. CI works too, using drag-to-turn.
- **Keyword:** EN "mind map for med school notes" / AR «ماب للنوتس»

**Hooks**

- **TikTok:** "Mind map for med school notes, except every note is a black hole."
- **Instagram:** cover text: "My anatomy notes… as black holes"
- **Shorts title:** "My med school notes as a 3D galaxy of black holes"
- **AR hook:** «نوتس التشريح بتاعتي.. بس كل نوتة ثقب أسود»

| t | Shot | On-screen EN | On-screen AR |
|---|---|---|---|
| 0.0-2.0 | Space view already open, dark mode, slowly turning: black spheres with photon rings and tilted accretion disks | Mind map for med school notes | ماب للنوتس بتاعة الكلية |
| 2.0-5.0 | Cut to Ideas: type "Femoral ring: medial to femoral vein" into the bottom capture field → Return | Throw in an idea the second you have it | ارمي الفكرة أول ما تيجي في دماغك |
| 5.0-8.0 | List view: drag it into the "Femoral" folder | Sort it later, into folders | رتّبها بعدين في فولدرات |
| 8.0-9.0 | Tap the floating List / Board / **Space** switcher | Then open Space | وبعدين افتح الـ Space |
| 9.0-14.0 | Space: zoom into the Inguinal and Femoral clusters; plasma threads between linked notes | Every note is a black hole. Every link, a stream of plasma. | كل نوتة ثقب أسود.. وكل ربط خيط بلازما |
| 14.0-17.0 | Tap a black hole: its name pill appears; turn the space by hand (tilt the phone on iPhone) | Folders become clusters you can turn in your hand | الفولدرات بتبقى مجرّات تلفّها بإيدك |
| 17.0-20.0 | End card (free) | (A.2) | (A.2) |

- **Sound:** none from the app. Add an ambient track from the platform's commercial library at post time (optional).
- **Caption EN:** "A mind map for med school notes: dump ideas as they come, sort them into folders later, then open Space: every note becomes a black hole and every link a stream of plasma. Free in Vignette."
- **Caption AR:** «ماب للنوتس: اكتب الفكرة أول ما تيجي، رتّبها في فولدرات بعدين، وافتح الـ Space: كل نوتة ثقب أسود وكل ربط خيط بلازما. ببلاش في Vignette.»
- **Hashtags (5):** `#medstudent #anatomy #mindmap #studyaesthetic #كلية_الطب`
- **Note:** use the example folders (Inguinal, Femoral) that `NoteExamples.swift` seeds from the example material, **not** the owner's own notes.

---

### Reel 3: Commute mode, revising without touching the phone

- **Plan:** Free with the phone's voice. The "Natural cloud voice" needs Vignette Cloud, so if the reel uses it, the end card uses the Pro line.
- **Length:** 25 s
- **Footage:** **iPhone strongly preferred**, because the point is real audio (the app reading and the student answering). CI version: silent video plus voice-over (Part C.4).
- **Keyword:** EN "hands-free flashcards" / AR «مراجعة في المواصلات»

**Hooks**

- **TikTok:** "Hands-free flashcards: I revised 30 cards on the bus without touching my phone."
- **Instagram:** cover text: "Revising on the commute, phone in my pocket"
- **Shorts title:** "Hands-free flashcards: revise on the commute with the phone locked"
- **AR hook:** «راجعت 30 كارت في الميكروباص.. من غير ما ألمس الموبايل»

| t | Shot | On-screen EN | On-screen AR |
|---|---|---|---|
| 0.0-2.5 | Commute mode setup: "Cards due today: 30 ready to read aloud" | Hands-free flashcards | مراجعة في المواصلات |
| 2.5-5.0 | Tap Start; the player appears | It reads today's due cards out loud | الموبايل بيقرالك الكروت اللي عليك النهارده |
| 5.0-10.0 | Audio: the app reads a card; pause; the student says the answer; the app says it was right. Screen shows the card and the result. | You answer out loud | إنت بتجاوب بصوتك |
| 10.0-14.0 | Next card: an MCQ read as A to E; the student says "C" | MCQs too: just say the letter | والـ MCQ كمان: قول الحرف بس |
| 14.0-17.0 | The student says "repeat"; the card is read again | Say "skip", "repeat" or "I don't know" | قول skip أو repeat أو I don't know |
| 17.0-20.0 | Lock the screen: audio carries on (the iPhone recording keeps capturing sound; the video shows the lock state) | Keeps going with the screen locked | بيكمّل والموبايل مقفول في جيبك |
| 20.0-22.0 | Due today count drops from 30 to 12 | Right = Good, wrong = Again. It counts as your review. | صح = Good، غلط = Again.. وبتتحسب مراجعة عادي |
| 22.0-25.0 | End card | (A.2) | (A.2) |

- **Social cut only (optional):** 1.5 s of b-roll through a bus or microbus window before 0.0, filmed on the phone. This shot is **not** allowed in the App Store preview (no filmed people or devices), so the preview master starts at 0.0.
- **Caption EN:** "Hands-free flashcards: Commute mode reads your due cards and questions aloud, listens to your answer and rates it for you, even with the phone locked in your pocket. Headphone play/pause works too."
- **Caption AR:** «مراجعة في المواصلات: Commute mode بيقرالك الكروت والأسئلة اللي عليك، يسمع إجابتك ويقولك صح ولا غلط، والموبايل مقفول في جيبك. وزرار السماعة play/pause شغال كمان.»
- **Hashtags (5):** `#medstudent #anki #flashcards #studyhacks #مذاكرة`
- **Recording note:** answer in English, which is what the cards are in. Where the iPhone can, speech recognition runs on the device (`NSSpeechRecognitionUsageDescription`). Recognition quality in a real bus is part of the demo, so film in a quiet place first.

---

### Reel 4: Image occlusion cards made for you (App Store preview #2)

- **Plan:** Pro to find diagrams in a lecture; the built-in heart example is free to study.
- **Length:** 18 s
- **Footage:** CI
- **Keyword:** EN "image occlusion" / AR «image occlusion كروت»

**Hooks**

- **TikTok:** "Image occlusion without making a single card by hand."
- **Instagram:** cover text: "Stop cutting boxes over diagrams"
- **Shorts title:** "Image occlusion cards, made automatically from your lecture's diagrams"
- **AR hook:** «بطّل تعمل كروت image occlusion بإيدك»

| t | Shot | On-screen EN | On-screen AR |
|---|---|---|---|
| 0.0-2.5 | Demo lecture slide with the labelled heart diagram | Image occlusion, made for you | image occlusion من غير مجهود |
| 2.5-5.0 | "Finding diagrams 14 of 20…" (**sped up**) | It finds the labelled diagrams in your lecture | بيدوّر على الرسومات اللي عليها labels |
| 5.0-7.5 | The offer: "3 labelled diagrams → occlusion cards" | Every label becomes a card | كل label بيبقى كارت |
| 7.5-11.5 | Card: all labels covered with opaque covers, one highlighted to guess; "Superior vena cava" (two lines) has one cover | One cover per label, even two-line labels | غطا لكل label.. حتى لو سطرين |
| 11.5-14.5 | Reveal: "Right atrium" | Hide all, guess one | بيخبّي الكل.. وإنت تخمّن واحدة |
| 14.5-18.0 | End card (Pro) | (A.2) | (A.2) |

- **Caption EN:** "Image occlusion without the scissors: Vignette finds the labelled diagrams in your lecture, reads the labels and makes one card per label, even the two-line ones. Try it on the built-in heart diagram."
- **Caption AR:** «image occlusion من غير قص ولزق: Vignette بيلاقي الرسومات اللي عليها labels في المحاضرة، ويعمل كارت لكل label حتى لو سطرين. جرّبها على رسمة القلب اللي جوه الأبلكيشن.»
- **Hashtags (5):** `#medstudent #anatomy #imageocclusion #anki #طالب_طب`
- **Note:** diagram labels stay left-to-right in the Arabic UI (plan P5.7 checks this). Only the captions are right-to-left.

---

### Reel 5: Draw it from memory, then lay the real one over it

- **Plan:** Free
- **Length:** 22 s
- **Footage:** iPhone (finger) or iPad (Apple Pencil) screen recording. CI can do it too: the UI test drags a path with `XCUICoordinate`, but a human drawing looks better.
- **Keyword:** EN "active recall anatomy drawing" / AR «ارسم من دماغك»

**Hooks**

- **TikTok:** "Active recall, anatomy drawing: draw the heart from memory, then see what you missed."
- **Instagram:** cover text: "Draw it blind. Then check."
- **Shorts title:** "Active recall: draw the heart from memory, then overlay the real diagram"
- **AR hook:** «ارسم القلب من دماغك.. وبعدين شوف غلطت فين»

| t | Shot | On-screen EN | On-screen AR |
|---|---|---|---|
| 0.0-2.0 | Draw recall: blank canvas; the figure's title is hidden | Active recall: draw it from memory | ارسم من دماغك |
| 2.0-9.0 | Drawing the chambers and vessels (**sped up** ×4) | No picture. No title. Just you. | من غير صورة ولا اسم |
| 9.0-10.5 | Tap Compare | Then: Compare | وبعدين Compare |
| 10.5-15.0 | The original over the drawing at half strength; the slider fades between them | The real diagram, laid over yours | الرسمة الأصلية فوق رسمتك |
| 15.0-18.5 | The label list: tick 7 of 11 | Tick what you got | علّم على اللي جبته صح |
| 18.5-19.0 | Attempts list | Every attempt is kept | كل محاولة بتتحفظ |
| 19.0-22.0 | End card (free) | (A.2) | (A.2) |

- **Caption EN:** "Active recall at its hardest: draw a diagram from a blank page, then lay the real one over yours and tick the labels you got. Finger or Apple Pencil."
- **Caption AR:** «أصعب active recall: ارسم الرسمة من ورقة فاضية، وبعدين حط الأصلية فوق رسمتك وعلّم على اللي جبته. بصباعك أو بالـ Apple Pencil.»
- **Hashtags (5):** `#medstudent #activerecall #anatomy #ipadnotes #كلية_الطب`
- **Note:** use the heart figure (ours). The brachial plexus is a better hook, but it needs a figure the repository owns. Add one to the demo lecture if P3.2 has time, and swap the hook to "Draw the brachial plexus from memory".

---

### Reel 6: Explain it back, out loud

- **Plan:** Pro when the marking runs on Vignette Cloud (a writer model on the device also works).
- **Length:** 26 s
- **Footage:** iPhone with the microphone on (real speech). The CI version feeds a typed explanation through the same marking path (Part C.3).
- **Keyword:** EN "Feynman technique for med school" / AR «اشرحها كأنك بتدرّسها»

**Hooks**

- **TikTok:** "Feynman technique for med school: explain it like you're teaching it, and it tells you what you missed."
- **Instagram:** cover text: "Explain it. Get marked against your lecture."
- **Shorts title:** "Feynman technique: explain a topic out loud, get marked against your lecture"
- **AR hook:** «اشرحها كأنك بتدرّسها.. وهو يقولك نسيت إيه»

| t | Shot | On-screen EN | On-screen AR |
|---|---|---|---|
| 0.0-2.5 | Explain it back: pick "Compensatory mechanisms in heart failure" | The Feynman technique, marked | اشرحها كأنك بتدرّسها |
| 2.5-10.0 | Speaking; the live transcript fills in (**sped up** after 3 s) | Explain it out loud, as if teaching it | اشرح بصوتك كأنك بتشرح لحد |
| 10.0-13.0 | Marking… then the score | Marked against the lecture it came from | بيتصحّح على المحاضرة نفسها |
| 13.0-18.0 | The three lists: covered, missed (e.g. "natriuretic peptides"), wrong | What you covered, what you missed, what was wrong | غطّيت إيه، نسيت إيه، وغلطت في إيه |
| 18.0-20.0 | The tip line | Plus one tip for next time | ونصيحة للمرة الجاية |
| 20.0-23.0 | Tap "turn the gaps into cards" → 3 new cards | Gaps → cards, in one tap | اللي نسيته يبقى كروت بدوسة |
| 23.0-26.0 | End card (Pro) | (A.2) | (A.2) |

- **Caption EN:** "The Feynman technique, marked: explain a topic out loud and Vignette marks it against your lecture: covered, missed, wrong. The gaps become flashcards in one tap."
- **Caption AR:** «اشرح الموضوع بصوتك وVignette يصحّحه على المحاضرة بتاعتك: غطّيت إيه، نسيت إيه، وغلطت في إيه. واللي نسيته يتحوّل كروت بدوسة واحدة.»
- **Hashtags (5):** `#medstudent #feynmantechnique #studytips #activerecall #طالب_طب`

---

### Reel 7: An OSCE patient who talks back

- **Plan:** Pro when the patient runs on Vignette Cloud (a writer model on the device also works).
- **Length:** 30 s
- **Footage:** iPhone with the microphone and app audio on. The app gives examiner and patient different voices (Aura "pandora" and "draco" in `tts.js`), so the audio carries the reel. CI version: typed questions plus voice-over.
- **Keyword:** EN "OSCE practice" / AR «تدريب OSCE»

**Hooks**

- **TikTok:** "OSCE practice with a patient who actually answers back."
- **Instagram:** cover text: "History-taking practice. Out loud. Against the clock."
- **Shorts title:** "OSCE practice: a talking patient, a timer, and a marked checklist"
- **AR hook:** «OSCE مع عيّان بيرد عليك»

| t | Shot | On-screen EN | On-screen AR |
|---|---|---|---|
| 0.0-2.5 | Spoken station: "Chest pain, history (PLAB 2, 8 minutes)" | OSCE practice, out loud | تدريب OSCE بصوتك |
| 2.5-4.0 | Tag in the corner for the whole reel | Fictional patient, for practice only | مريض افتراضي.. للتدريب بس |
| 4.0-12.0 | Student: "When did the pain start?" → patient (draco voice): "About two hours ago, while I was climbing the stairs." → student: "Does it go anywhere?" → patient answers | You ask. The patient answers. | إنت بتسأل.. والعيّان بيرد |
| 12.0-16.0 | Timer visible, counting down (**sped up** between questions) | Against the clock, like the real station | بالوقت زي الامتحان بالظبط |
| 16.0-24.0 | End → the examiner's marks: checklist items ticked or missed ("Asked about radiation: yes", "Risk factors: missed") | Then the examiner marks you on the checklist | وفي الآخر الممتحن يصحّحلك على الـ checklist |
| 24.0-27.0 | Earlier attempts listed | Every attempt kept, so you can see yourself improve | كل محاولة متسجّلة.. تشوف نفسك بتتحسن |
| 27.0-30.0 | End card (Pro) | (A.2) | (A.2) |

- **Caption EN:** "OSCE practice with a patient who talks back: take the history out loud, against the clock, then get marked on the station's checklist. Fictional patients, for practice only."
- **Caption AR:** «تدريب OSCE مع عيّان بيرد عليك: خُد الـ history بصوتك وبالوقت، وبعدين اتصحّح على الـ checklist. المرضى افتراضيين، للتدريب بس.»
- **Hashtags (5):** `#osce #plab #medstudent #clinicalskills #كلية_الطب`

---

### Reel 8: Diagnose at clue 2?

- **Plan:** Free to play the cases in a set; writing new cases uses a writer model.
- **Length:** 20 s
- **Footage:** CI (it is all taps)
- **Keyword:** EN "clinical reasoning practice" / AR «تشخيص من الـ clues»

**Hooks**

- **TikTok:** "Clinical reasoning practice: could you diagnose this at clue 2?"
- **Instagram:** cover text: "Clue 1 of 6. Diagnose now or wait?"
- **Shorts title:** "Clinical reasoning: diagnose from as few clues as you dare"
- **AR hook:** «تقدر تشخّص من تاني clue؟»

| t | Shot | On-screen EN | On-screen AR |
|---|---|---|---|
| 0.0-3.0 | Clue case: "Clue 1 of 6"; "Worth 1.83 if right" | Clinical reasoning, one clue at a time | التشخيص.. clue ورا clue |
| 3.0-7.0 | Reveal clue 2: "Worth 1.67 if right" | The earlier you commit, the more it's worth | كل ما تشخّص بدري.. السؤال يستاهل أكتر |
| 7.0-11.0 | Four diagnoses shown; hold on them for 2 s | Four options. Commit when you're sure. | 4 اختيارات.. اختار لما تبقى متأكد |
| 11.0-14.0 | Commit → right; all clues shown | (pause, no text) | |
| 14.0-17.0 | "How it went last time" line on the case list | Just you and the case. No rush. | إنت والحالة بس.. على راحتك |
| 17.0-20.0 | End card (free) | (A.2) | (A.2) |

- **Caption EN:** "Clinical reasoning practice: clues appear one at a time, and the earlier you commit to the right diagnosis, the more it's worth. Solo practice, at your own pace."
- **Caption AR:** «الـ clues بتظهر واحدة واحدة، وكل ما تشخّص صح بدري السؤال يستاهل أكتر. تدريب لوحدك وعلى راحتك.»
- **Hashtags (5):** `#medstudent #clinicalreasoning #usmle #diagnosis #طالب_طب`
- **Note:** show the case list, not a leaderboard or any other person. The "Worth" numbers are whatever `ClueCaseView` shows for that case: 1 + (clues left ÷ clues), shown to two decimals.

---

### Reel 9: Record the lecture, follow the transcript word by word

- **Plan:** Pro (transcribing a recorded lecture is a Pro perk on the paywall)
- **Length:** 24 s
- **Footage:** iPhone with app audio on. **Use a recording the owner makes of himself reading the demo lecture.** Never use a real lecturer's voice without their permission (`RecordingTermsView`).
- **Keyword:** EN "lecture transcription" / AR «تفريغ المحاضرة»

**Hooks**

- **TikTok:** "Lecture transcription on your phone, and every word lights up as it plays."
- **Instagram:** cover text: "Replay the lecture. Watch every word light up."
- **Shorts title:** "Lecture transcription that follows the audio word by word"
- **AR hook:** «سجّل المحاضرة.. وخد التفريغ، وكل كلمة بتنوّر وهي بتتقال»

| t | Shot | On-screen EN | On-screen AR |
|---|---|---|---|
| 0.0-2.5 | Narrate: import the recording | Lecture transcription | تفريغ المحاضرة |
| 2.5-5.5 | Transcribing… (**sped up**) | Transcribed on the phone, in English or Arabic | التفريغ على الموبايل.. عربي أو إنجليزي |
| 5.5-12.0 | Player: audio plays, the current word is lit, the transcript scrolls | Every word lights up as it's said | كل كلمة بتنوّر وهي بتتقال |
| 12.0-15.0 | Scrub back and change speed: the highlight stays in step | Scrub, speed up: it stays in sync | رجّع أو سرّع.. بيفضل مظبوط |
| 15.0-19.0 | `narrate-fixing`: tap a misheard word → Fix word sheet → correct it | Misheard word? Fix it in a second | كلمة اتسمعت غلط؟ صلّحها في ثانية |
| 19.0-21.0 | Small line | Only record where your lecturer allows it | سجّل بس لو الدكتور موافق |
| 21.0-24.0 | End card (Pro) | (A.2) | (A.2) |

- **Caption EN:** "Lecture transcription: record the lecture (with your lecturer's OK), get the transcript on your phone, and replay it with every word lighting up as it's said. Fix any misheard word in a tap."
- **Caption AR:** «سجّل المحاضرة (بإذن الدكتور)، خد التفريغ على الموبايل، ورجّعها وكل كلمة بتنوّر وهي بتتقال. وأي كلمة اتسمعت غلط تصلّحها بدوسة.»
- **Hashtags (5):** `#medstudent #lecture #transcription #studywithme #مذاكرة`

---

### Reel 10: What the exam covers that your library doesn't

- **Plan:** Free for the keyword check (instant and offline). The AI check and "questions on the gaps" use a writer model, which is Pro on Vignette Cloud.
- **Length:** 22 s
- **Footage:** CI
- **Keyword:** EN "USMLE Step 1 study plan" (or "PLAB 1") / AR «الـ gaps في مذاكرتك»

**Hooks**

- **TikTok:** "USMLE Step 1 study plan: what does the exam cover that you haven't studied yet?"
- **Instagram:** cover text: "Your gaps, topic by topic"
- **Shorts title:** "See what USMLE or PLAB covers that your notes don't (then fill the gaps)"
- **AR hook:** «الـ USMLE بيسأل في إيه.. وإنت لسه ما ذاكرتوش؟»

| t | Shot | On-screen EN | On-screen AR |
|---|---|---|---|
| 0.0-2.5 | Coverage: choose the exam (USMLE, PLAB, MRCP, MRCS) | Find your gaps before the exam does | اعرف الـ gaps بتاعتك قبل الامتحان |
| 2.5-7.0 | Area list, e.g. Cardiovascular: subtopics tagged covered, thin or not covered | Every topic: covered, thin, or not covered | كل topic: متغطّي، خفيف، أو مش متغطّي |
| 7.0-11.0 | One subtopic where keywords and AI disagree: the AI verdict with a note of what the keywords thought | Two opinions side by side: keywords and AI | رأيين جنب بعض: الكلمات والـ AI |
| 11.0-15.0 | Tap "make questions on the gaps" → generation starts (**sped up**) | Questions on the gaps, in one tap | أسئلة على الـ gaps بدوسة واحدة |
| 15.0-18.0 | Small line under the list | A rough map of likely gaps, not what the exam will ask | ده تقريب للـ gaps المحتملة.. مش اللي هييجي في الامتحان |
| 18.0-22.0 | End card (Pro) plus "Not affiliated with any exam body." | (A.2) | (A.2) + «مالناش علاقة بأي جهة امتحانات.» |

- **Caption EN:** "USMLE Step 1 or PLAB study plan: Vignette checks your library against a condensed version of the exam's public outline and shows every topic as covered, thin or not covered, then writes questions on the gaps. It's a rough guide, not a prediction of what the exam will ask. Not affiliated with any exam body."
- **Caption AR:** «Vignette بيقارن مذاكرتك بملخص للـ outline الرسمي للامتحان (USMLE أو PLAB أو MRCP أو MRCS)، ويوريك كل topic متغطّي ولا خفيف ولا مش متغطّي، ويكتب أسئلة على الـ gaps. ده دليل تقريبي مش توقّع للامتحان. مالناش علاقة بأي جهة امتحانات.»
- **Hashtags (5):** `#usmle #plab #medstudent #step1 #طالب_طب`
- **Fact to keep straight:** Step 1 has been pass/fail since January 2022, so never say "boost your Step 1 score". Say "pass Step 1" or "cover Step 1".

---

### B.11 When to post (social captions only; never in the video)

| Window | Why | Reels to lead with |
|---|---|---|
| Launch week (whenever P6.2 ships) | First impression | 1 (hero), 4, 2 |
| Egyptian universities: term started **19 Sep 2026**, midterms in the **first three weeks of November 2026** | Midterm cramming | 1, 4, 3 |
| First-term finals, **2–21 January 2027** | The peak of exam season | 1, 8, 5, 3 |
| Second term starts **6 February 2027**; end-of-year exams **late May to June** (each faculty sets its own dates) | Clinical years: OSCEs | 7, 6, 9 |
| EMLE (Egyptian licensing exam for graduates, **February and September** sittings) | Graduates and interns | 10 (switch the keyword to "EMLE" in the caption only; the app has no EMLE blueprint, so say "general revision", not "EMLE coverage") |
| All year | Evergreen | 2, 5 and 10 (USMLE/PLAB) |

Cadence: 3 posts a week, the same reel on all three platforms on the same day. Use the English cut on YouTube Shorts and the Arabic cut on TikTok and Instagram for the Egyptian audience, with the other language reposted 3–4 days later. Pin reel 1 on each profile.

---

## Part C. Capturing the footage

### C.1 Path 1 (default, zero owner steps): CI simulator recording, spec for P3.2

`reel-footage.yml` runs on `macos-latest` (the same image rule as `walkthrough.yml`: iOS 26 needs the newest Xcode) and follows the pattern `walkthrough.yml` already uses. The difference is that a UI test drives the taps, so each reel plays its beats on cue.

**Inputs:** `reels` (`all`, or ids like `1,4,8`), `languages` (`en,ar`), `appearance` (`dark` by default; reel 2 is always dark), `voiceover` (`off` or `on`).

**Steps, for each reel and each language:**

1. **Pick the simulator.** Use the newest available "Pro Max" iPhone:
   ```sh
   xcrun simctl list devices available -j | python3 -c '...pick newest iPhone *Pro Max*...'
   ```
   Its 1320×2868 screen scales to 886 px wide for the App Store preview size with a 5-px crop.
2. **Start clean and make the status bar Apple-compliant:**
   ```sh
   xcrun simctl erase "$UDID"
   xcrun simctl boot "$UDID"
   xcrun simctl bootstatus "$UDID" -b
   xcrun simctl status_bar "$UDID" override --time "9:41" --batteryLevel 100 --batteryState charged \
     --cellularMode active --cellularBars 4 --wifiBars 3
   xcrun simctl ui "$UDID" appearance dark
   xcrun simctl addmedia "$UDID" docs/launch/reel-assets/demo-lecture.pdf   # or copy into the app container
   ```
3. **Record and drive** (the recorder needs SIGINT, not a plain kill, or the MP4 index is never written; `walkthrough.yml` already learned this):
   ```sh
   T_REC=$(python3 -c 'import time; print(time.time())')
   xcrun simctl io "$UDID" recordVideo --codec=h264 --mask=black --force "raw/$ID-$LANG.mp4" &
   REC=$!
   sleep 2
   TEST_RUNNER_VIGNETTE_REELS=1 TEST_RUNNER_REEL_LANG="$LANG" \
     xcodebuild test-without-building -xctestrun "$XCTESTRUN" \
       -destination "id=$UDID" -only-testing:"RedPenUITests/ReelFootageUITests/test_reel$ID" \
     | tee "raw/$ID-$LANG.log"
   kill -INT $REC; wait $REC || true
   ```
   The `TEST_RUNNER_` prefix is how `xcodebuild` passes environment variables to the test runner. The test calls `XCTSkipUnless(ProcessInfo.processInfo.environment["VIGNETTE_REELS"] == "1")`, so `app-build` never runs it (plan §W0).
4. **Beat timing.** The UI test prints `REEL-T0 <unix time>` the moment the first beat's screen is on display, then prints `REEL-BEAT <n> <unix time>` as it reaches each beat. It holds each beat for the duration in the tables above. The simulator shares the Mac's clock, so post-processing trims at `T0 − T_REC` and re-times the captions from the logged beat times rather than trusting the table blindly.
5. **Language:** `app.launchArguments += ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_EG"]` for Arabic takes. Arabic footage only makes sense after W5 (localisation). Until then, Arabic reels use the English UI with Arabic captions, which is normal for Egyptian medical students, who study in English.
6. **Pro state:** use the StoreKit test configuration (`RedPen.storekit`) in the simulator. **Never** use the owner flag or owner key, so no Owner tools and no "personal build" wording ever reach the frame.
7. **Real content, not mocks:**
   - Reels 1, 6, 10 (and 4's diagram offer) run the real generation and check through the deployed Worker. They use the owner key derived from `AI_API_KEY` exactly as `live-tests.yml` does (`printf 'cramdown-owner:%s' "$AI_API_KEY" | shasum -a 256`), so no new secret is needed and nothing is typed by the owner.
   - The generated set is saved as a fixture (`reel-assets/generated/<id>.json`). A later re-record replays it and does not spend the free allowance again.
   - The test asserts the numbers it shows (A.4).
8. **Voice reels (3, 6, 7) in the simulator:** there is no microphone input, and Commute mode has no text box. The UI test needs a reel-only hook, compiled only in the UI-test configuration, that feeds scripted answers ("C", "repeat", a typed explanation, typed history questions) into the same session objects (`CommuteSession`, the explain-back marker, `SpokenStationSession`). **Flag for P3.2 / W0:** this hook belongs in P0.4's screen seams (it is an app file); P3.2's file list contains only UI tests.
9. **Audio in CI:** `simctl io recordVideo` records **video only**. The simulator's sound is not captured, a limitation that goes back years. For `voiceover=on`:
   - fetch each spoken line from the Worker's `/tts` with the same owner key: narrator "pandora", patient "draco" and a third voice for the demo student;
   - place the MP3s at the logged beat times with `ffmpeg -itsoffset`, and label the student voice "demo voice" (A.4);
   - the lines are cached in R2 and stay within `TTS_FREE_DAILY_CHARS`, so re-runs cost nothing.
10. **Artifacts:** `raw/*.mp4` and `raw/*.log` go to an upload artifact for job 2.

**Job 2 (`ubuntu-latest`, post-processing):**

1. Install the tools: `sudo apt-get install -y ffmpeg fonts-noto-core fonts-noto-ui-core` and `pip install pillow arabic-reshaper python-bidi` (the same stack as the plan's `tools/screenshots/caption.py`).
2. Render the caption PNGs: one transparent 1080×1920 PNG per beat per language.
   - Text sits in the band from y = 250 to y = 560, with x from 60 to 940.
   - That keeps clear of the platforms' UI: roughly the top 150–200 px (TikTok's username and sound label), the right 120 px (like/comment/share icons) and the bottom 250–300 px (caption and CTA).
   - Use a rounded dark pill at 80 % opacity under white text. The font is Noto Sans for English and Noto Sans Arabic for Arabic, shaped with arabic-reshaper and python-bidi, right-aligned.
3. Build the cuts:
   ```sh
   # trim to the first beat and keep 30 fps
   ffmpeg -ss "$OFFSET" -i raw.mp4 -t "$DUR" -vf fps=30 -an trimmed.mp4

   # App Store preview: 886x1920, H.264 High, silent stereo track if there is no voice-over
   ffmpeg -i trimmed.mp4 -f lavfi -i anullsrc=r=48000:cl=stereo \
     -vf "scale=886:-2:flags=lanczos,crop=886:1920,format=yuv420p" \
     -c:v libx264 -profile:v high -level 4.0 -b:v 11M -maxrate 12M -bufsize 24M \
     -c:a aac -b:a 256k -shortest NN-slug-LANG-preview.mp4

   # social "fit": app centred on the brand background, captions over it
   ffmpeg -i trimmed.mp4 -i cap_1.png -i cap_2.png ... \
     -filter_complex "[0]scale=-2:1920,pad=1080:1920:(ow-iw)/2:0:color=0x0B0B0F[b]; \
                      [b][1]overlay=enable='between(t,0,2.5)'[v1]; [v1][2]overlay=enable='between(t,2.5,5.5)'[v2]; ..." \
     -c:v libx264 -profile:v high -crf 18 -r 30 -pix_fmt yuv420p -c:a aac -b:a 192k NN-slug-LANG-social.mp4

   # social "fill": full width, status bar and home indicator cropped
   #   ... -vf "scale=1080:-2,crop=1080:1920:0:(ih-1920)/2" ...
   ```
4. Build the `.srt` from the beat table plus the logged beat times, and the cover JPG from the hook beat's middle frame with the hook text.
5. Publish to the `reels` GitHub release through `publish.yml`. The release notes carry each reel's caption and hashtags in both languages, ready to copy.

### C.2 Path 2 (optional, better for reels 2, 3, 5, 7 and 9): iPhone or iPad screen recording

Use this only when the owner *wants* their own device audio, voice or the tilt effect. CI still does all the editing: the owner records, and never edits.

1. **One time:** Settings → Control Center, and add the **Screen Recording** control if it is not already there.
2. **Before each take:**
   - Turn on **Do Not Disturb** (Control Center), so no banner appears mid-take. The recording indicator itself cannot be hidden. The "fill" cut crops the status bar away.
   - Charge to 100 % and use Wi-Fi, so the status bar is clean if the "fit" cut is used.
   - Set Settings → Display & Brightness → Dark (reel 2), keep the default text size, and turn off Bold Text.
   - **Arabic takes (after W5):** Settings → Apps → Vignette → Language → العربية. This switches only this app, not the phone.
   - Content: only the demo lecture (open `demo-lecture.pdf` from the `reels` release with "Open in Vignette"), the built-in examples, and the fictional OSCE station. Never real notes, and never a real lecture or recording.
3. **Sound:** in Control Center, **touch and hold** the Screen Recording button, turn **Microphone** on for reels 3, 6 and 7 (your answers), and make sure the app's own audio is recorded (on recent iOS versions this menu shows the audio sources). Test once: if the app's speech recognition and the recorder compete for the microphone, your voice may be missing from the file. In that case, record with the microphone off and let CI add the voice-over.
4. **Record:** tap Record, wait for the 3-second countdown, and close Control Center. Play the beats in order, holding each for about its table duration; extra length is fine, because CI trims. To stop, tap the red indicator at the top and then Stop. The file goes to Photos.
5. **Hand it to CI without editing:**
   - In Photos → Share → **Save to Files**, into the folder the project's existing phone bridge already uploads from.
   - If there is none, upload it as a release asset named `take-NN-LANG.mp4` on the `reels-takes` draft release, from the GitHub website on the phone.
   - `reel-footage.yml` (input `from_take=NN`) then runs job 2 on the take instead of a simulator recording.
   - Beat times come from `scene` detection (`ffmpeg -vf "select='gt(scene,0.3)',showinfo"`) matched in order to the beats. P3.2 writes a check that fails loudly when the counts differ, instead of placing captions wrongly.
6. **iPad (reel 5 with Apple Pencil):** the iPad screen is 4:3. CI crops a 9:16 window centred on the canvas (`crop=ih*9/16:ih`), so draw in the middle of the canvas.

### C.3 What cannot be captured, and what to do

| Shot | Problem | Fix |
|---|---|---|
| Tilt parallax (reel 2) | The simulator has no motion sensors | iPhone take, or a CI drag-to-turn |
| Microphone speech (reels 3, 6, 7) | The simulator has no microphone input | iPhone take, or the reel-only scripted-answer hook plus voice-over (C.1 step 8) |
| Any sound in CI | `recordVideo` records no audio | `/tts` voice-over muxed by ffmpeg (C.1 step 9) |
| Screen locked (reel 3) | The lock screen cannot be recorded from inside the app, and the iPhone recording only shows the lock screen | Keep it to 1.5 s, with audio carrying on over a black frame labelled "screen locked" |
| Live Activity or widget shots | Not in the Playgrounds build, and not in the simulator until P3.1 lands | Do not use them in any reel until the App Store build exists. Apple also forbids showing the Home Screen with third-party content. |

### C.4 App Store previews: which reels, and how they get there

- **Previews:** reels **1, 4 and 2**, in that order (Apple allows up to three app previews per device size and language). Arabic previews go on the Arabic localisation after W5.
- **Rules:** use the 886×1920 masters from C.1, with no finger footage, no b-roll, no voice-over naming a date, the Pro line on the end card and no badge. Set the poster frame at 5 s, which is Apple's default and falls on the "40 questions suits this material" beat in reel 1.
- **Upload:** P3.2's App Store Connect API client uploads them with the screenshots (`appPreviewSets` / `appPreviews`, using the same key as the screenshots). If P3.2 does not cover previews, uploading the three files in App Store Connect → the version page → Previews and Screenshots is the only manual step, and it is optional. The app can be submitted without previews.

---

## Part D. Owner checklist for the reels

**Automatic (no owner action):**

- demo lecture, generation, recording, captions and all cuts;
- EN and AR versions;
- the `reels` release with the captions and hashtags ready to copy;
- the App Store previews, if P3.2 includes them.

**Unavoidable only if the owner wants the reels posted.** None of these is an App Store Connect step, and none is required for launch:

1. Create the TikTok, Instagram and YouTube accounts (a Creator or Business account is fine; mind the music rule in Part A).
2. Posting: on the phone, download from the `reels` release → Save to Photos → post, pasting the caption from the release notes. **Automated posting is deliberately not built.** It would need platform API tokens, and TikTok's posting API needs an audited app. Keys and tokens never go in code or chat.

**App Store Connect (only if P3.2 does not automate previews):** upload the three preview files (C.4). Optional.

---

## Sources

- Apple, App preview specifications (15–30 s, 30 fps, 886×1920 for iPhone 6.9"/6.5"/6.1", H.264 10–12 Mbps, AAC 256 kbps stereo, 500 MB): https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications/
- Apple, App previews guidance (footage only from the app; no fingers, people or device frames; no prices or timely references; disclose IAP and subscriptions): https://developer.apple.com/app-store/app-previews/
- Apple, Upload app previews and screenshots (up to three previews per device size and language): https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/
- Apple, Marketing resources and identity guidelines (badge use in video, localized badges, "App Store" and product names untranslated, status bar and notification rules, trademark credit at end of video): https://developer.apple.com/app-store/marketing/guidelines/
- Apple Support, Record the screen on your iPhone (Control Center, touch and hold for Microphone, saved to Photos): https://support.apple.com/en-us/102653
- Apple Support, Do Not Disturb on iPhone: https://support.apple.com/en-us/105112
- Instagram @creators, 5-hashtag limit (December 2025): https://www.threads.com/@creators/post/DSalXGPCWM4/new-hashtag-guidance-starting-today-instagram-will-allow-up-to-hashtags-in-a ; summary: https://later.com/blog/ultimate-guide-to-using-instagram-hashtags/
- YouTube Help, three-minute Shorts (square or vertical; Content ID change from 24 Sep 2026): https://support.google.com/youtube/answer/15424877?hl=en
- Instagram Reels length and recommendation cut-off at 3 min: https://metricool.com/instagram-reels-length/
- TikTok safe zones for 1080×1920: https://zeely.ai/blog/tiktok-safe-zones/
- TikTok search keywords (spoken, on-screen, caption): https://blog.hootsuite.com/tiktok-seo/ ; https://almcorp.com/blog/tiktok-seo/
- TikTok Commercial Music Library for business accounts: https://ads.tiktok.com/help/article/commercial-music-library?lang=en ; https://www.soundstripe.com/blogs/tiktok-music-library-explained
- Instagram business accounts and the Meta Sound Collection: https://tripepismith.com/insights/music-in-reels-business-accounts/
- TikTok content disclosure for branded and paid content: https://ads.tiktok.com/help/article/about-the-content-disclosure-setting-for-creators ; https://www.tiktok.com/legal/page/global/bc-policy/en
- Egyptian university calendar 2026/27 (start 19 Sep 2026; midterms in November; first-term exams 2–21 Jan 2027; second term 6 Feb 2027): https://www.dostor.org/5709416 ; https://www.cairo24.com/2494284
- Egyptian end-of-year university exams in May–June: https://www.elwatannews.com/news/details/8262804
- EMLE held in February and September: https://en.wikipedia.org/wiki/Egyptian_Medical_Licensing_Examination ; https://emle.academy/faqs/
- USMLE Step 1 pass/fail only from 26 Jan 2022: https://www.usmle.org/usmle-step-1-transition-passfail-only-score-reporting
- `simctl io recordVideo` records no audio, and its options: https://github.com/lionheart/openradar-mirror/issues/19330 ; https://sarunw.com/posts/take-screenshot-and-record-video-in-ios-simulator/
- In-repo facts: `ios/RedPen/Shared/MCQCoverage.swift` (`suggestedCount` = characters ÷ 320), `Features/Library/LecturePDFSection.swift`, `Features/Examples/OcclusionExample.swift`, `Features/Notes/Graph3DView.swift` / `GraphLook.swift` (black holes), `Features/Voice/CommuteModeView.swift`, `Features/Reasoning/ClueCaseView.swift` ("Worth … if right"), `Shared/Coverage/Syllabus.swift`, `Features/Paywall/PaywallView.swift` (Pro perks), `server/tts.js` (Aura-2 voices, free daily allowance), `.github/workflows/walkthrough.yml` and `live-tests.yml`.
