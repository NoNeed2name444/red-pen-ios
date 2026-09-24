# Vignette: App Store listing (English and Arabic)

Written 2026-09-24 for the App Store (Xcode) build of `com.cramdown.app`. The Swift Playgrounds build has no listing.

**How to use this file.** Each copy-exact field sits in a fenced block right after an HTML comment such as `<!-- field: en-US/name.txt -->`. Package P6.1 (`docs/launch/implementation-plan.md`) turns those blocks into `docs/launch/metadata/<locale>/*.txt`, and P3.2 uploads them through the App Store Connect API. Everything outside the fenced blocks explains the choices and is not uploaded. The lengths in the check table (§11) were measured with Python: characters for every field, plus UTF-8 bytes for keywords.

**Features that do not exist yet.** Some lines depend on work that has not shipped. Those are marked `[ship-gated: P…]`. Delete them from the fenced block if that package has not landed when the build is submitted. Guideline 2.3.1 requires the listing to match the binary, and 2.3.12 requires What's New to describe real changes.

---

## 1. Decisions at a glance

| Item | Decision | Why |
|---|---|---|
| Localisations | **en-US** (primary), **en-GB**, **ar-SA** | Egypt, Saudi Arabia, the UAE, Jordan and Kuwait default to **English (U.K.)** and also support Arabic. Without an en-GB localisation, UK and Egyptian users see the en-US text. Adding one also gives a second 100-byte keyword field for the PLAB and MRCP audience. The US storefront indexes Arabic as well. |
| Name | `Vignette: Medical MCQs & OSCE` | 29 characters. The name carries the most search weight, and "Vignette" alone is probably taken. |
| Primary category | Education | Choosing Medical adds scrutiny and the medical-device questions (design F §9). |
| Secondary category | Reference | |
| Prices in metadata | Never | Guideline 2.3.7. Prices appear only on the paywall, which gets them from StoreKit. |
| "Anki" in name, subtitle or keywords | **No**, not even as "Anki alternative" | Apple's keyword help says "Names of other apps or companies aren't allowed", and 2.3.7 bans "popular app names". The same searches are reached with `flashcards`, `spaced repetition` and `apkg`. The description may say the app exports `.apkg` decks. |
| Exam names (USMLE, PLAB, MRCP, MRCS, UKMLA) | Allowed, because they describe real content | `ExamTrack.swift` writes questions in each exam's style, units and guidelines, and times them to that exam. The description carries a "not affiliated" line. Organisation names (NBME, FSMB, GMC) stay out of the keywords. |
| Friend challenges, duels, "compete with friends" | Not mentioned anywhere | The owner rejected them. The in-app "lookalike duels" are one student comparing two confusable conditions; the listing calls them "lookalike conditions side by side". |
| Age rating | Answer honestly (the computed result is **16+**), then **override to 18+** | See §9. The Gemini API terms forbid apps "directed towards or likely to be accessed by individuals under the age of 18". |

---

## 2. App name

Limit: 30 characters (guideline 2.3.7). Apple requires names to be unique.

| # | English (en-US and en-GB) | Chars | Notes |
|---|---|---|---|
| **A (recommended)** | Vignette: Medical MCQs & OSCE | 29 | Adds `medical`, `mcq` and `osce` to the ranked words, and says what the app is. |
| B | Vignette: Med School Qbank | 26 | "Qbank" is a word students search. Use it if A is refused as taken. |
| C | Vignette: Lectures to MCQs | 26 | Describes the core loop best, but ranks for fewer useful terms. |

| # | Arabic (ar-SA) | Chars | Notes |
|---|---|---|---|
| **A (recommended)** | Vignette: بنك أسئلة الطب | 24 | "بنك أسئلة" (question bank) is the phrase Arabic medical platforms use. "Vignette" stays in Latin letters, as the glossary requires (design F §4). |
| B | Vignette: أسئلة طب من محاضراتك | 30 | Says the lecture-to-questions idea. |
| C | Vignette: أسئلة طب و OSCE | 25 | Only if OSCE should be in the Arabic name. |

<!-- field: en-US/name.txt -->
```text
Vignette: Medical MCQs & OSCE
```

<!-- field: en-GB/name.txt -->
```text
Vignette: Medical MCQs & OSCE
```

<!-- field: ar-SA/name.txt -->
```text
Vignette: بنك أسئلة الطب
```

---

## 3. Subtitle (30 characters, no unverifiable claims, no other apps)

<!-- field: en-US/subtitle.txt -->
```text
Qbank made from your lectures
```

<!-- field: en-GB/subtitle.txt -->
```text
Revision Qs from your lectures
```

<!-- field: ar-SA/subtitle.txt -->
```text
حوّل محاضراتك لأسئلة وكروت
```

Alternatives:
- EN "Your lectures as exam questions" is 31 characters. It fits if "as" becomes "→", but Apple sometimes rejects symbols in subtitles.
- AR "محاضراتك صارت أسئلة امتحان" (26 characters) is friendlier to Egyptian readers.

---

## 4. Promotional text (170 characters, editable any time without review)

Promotional text is the only field that can change without a new build. Use it for the exam calendar.

<!-- field: en-US/promotional_text.txt -->
```text
Turn this week's lectures into exam-style questions, spaced-repetition cards and OSCE stations. Free on your iPhone, with no account and nothing leaving the device.
```

<!-- field: en-GB/promotional_text.txt -->
```text
Revising for PLAB, MRCP or finals? Turn your own lectures into exam-style questions, cards and OSCE stations. Free on your iPhone, with no account needed.
```

<!-- field: ar-SA/promotional_text.txt -->
```text
حوّل محاضرات الأسبوع إلى أسئلة بأسلوب الامتحان وكروت مراجعة ومحطات OSCE. مجانًا على جهازك، بدون حساب، ولا يغادر شيء هاتفك.
```

### Seasonal rotation (swap the text through the API or the owner console, with no build needed)

| When | EN promotional text | AR promotional text | Anchor |
|---|---|---|---|
| Mid-Oct to early Nov 2026 | `MRCP Part 1 in January? Start now: turn your notes into best-of-five questions timed to the real paper, and see which topics you haven't covered yet.` | `عندك MRCP Part 1 في يناير؟ ابدأ الآن: أسئلة best-of-five من ملاحظاتك بتوقيت الامتحان الحقيقي، واعرف ما لم تذاكره بعد.` | MRCP Part 1 sitting on 20 Jan 2027; applications open 27 Oct and close 3 Nov 2026 |
| Late Oct to mid-Nov 2026 | `PLAB 1 this November? Timed 60-second questions in UK style (NICE, BNF, SI units), written from your own notes.` | `PLAB 1 في نوفمبر؟ أسئلة بتوقيت 60 ثانية بالأسلوب البريطاني (NICE وBNF ووحدات SI) من ملاحظاتك أنت.` | PLAB 1 runs four times a year (Feb, May, Aug, Nov). Check the date in GMC Online. |
| Dec 2026 to Jan 2027 | `Finals in January? Turn every lecture this term into questions and cards, and let spaced repetition bring back what you're about to forget.` | `امتحانات الترم في يناير؟ حوّل كل محاضرات الترم لأسئلة وكروت، والتكرار المتباعد يرجّع لك ما أوشكت على نسيانه.` | Egyptian faculties usually hold first-term exams in January. This is typical, not official, so check with the faculty. |
| Before each Egyptian licensing round | `Preparing for the licensing exam? Revise all six years from your own lectures, with gaps shown subject by subject.` | `بتستعد لامتحان مزاولة المهنة؟ راجع من محاضراتك أنت، واعرف الأجزاء الناقصة مادة مادة.` | The Egyptian Health Council's human-medicine practice exam. It has several rounds a year; 2026 rounds were announced for March and July. Check ehc.gov.eg. |
| May to July | `Second-term exams? Record the lecture, get the transcript in Arabic or English, and turn it into questions the same day.` | `امتحانات الترم التاني؟ سجّل المحاضرة، خد نصها بالعربي أو الإنجليزي، وحوّلها لأسئلة في نفس اليوم.` | Egyptian second-term exams, usually May to July. The transcription line applies only once Pro is live. |

USMLE Step 1 and Step 2 CK are booked year-round through Prometric, so there is no USMLE season line. The default en-US text covers it.

---

## 5. Keywords (100 bytes per locale, commas, no spaces after commas)

Rules followed:
- **Bytes, not characters.** Apple's help says "up to 100 bytes". Arabic letters take 2 bytes each in UTF-8, so the Arabic field holds about 50 letters.
- **Each keyword must be longer than two characters.**
- **Words already in the name, subtitle or developer name are not repeated.** Search already indexes them, and repeating a word adds no ranking.
- **Phrases form only within one localisation.** Each locale's words have to make sense together with its own name and subtitle.

<!-- field: en-US/keywords.txt -->
```text
usmle,step 1,step 2 ck,flashcards,spaced repetition,apkg,plab,mrcp,mrcs,anatomy,pharmacology,study
```
98 bytes. With the name and subtitle, this covers: usmle qbank, step 1 qbank, medical flashcards, spaced repetition, osce, mcq, plab, mrcp, apkg, anatomy mcq, pharmacology flashcards, med study, lectures.

<!-- field: en-GB/keywords.txt -->
```text
plab,ukmla,mrcp,mrcs,paces,usmle,qbank,finals,flashcards,spaced repetition,apkg,anatomy,pharmacology
```
100 bytes. This field serves the UK, Egypt, Saudi Arabia, the UAE, Jordan and Kuwait, because English (U.K.) is their default. It is the most important English field for Egyptian students, who mostly search exam names in Latin letters. `ukmla` is accurate because PLAB is the UKMLA route for international graduates.

<!-- field: ar-SA/keywords.txt -->
```text
مذاكرة,امتحان,اسئلة,كروت,طب,مزاولة,زمالة,اوسكي,مراجعة
```
98 bytes. Why these words:
- **مذاكرة**: the Egyptian word for studying (more common in Egypt than دراسة).
- **امتحان**: exam.
- **اسئلة**: questions, spelled without the hamza as it is usually typed. The name already has أسئلة with the hamza.
- **كروت**: Egyptian colloquial for cards.
- **طب**: medicine. The name has only الطب.
- **مزاولة**: from امتحان مزاولة المهنة, the licensing exam.
- **زمالة**: fellowship. The Egyptian Fellowship and Arab Board are the postgraduate exams.
- **اوسكي**: OSCE as students write it in Arabic.
- **مراجعة**: revision.

Arabic alternates, to swap in with a later version:
- **فلاش** (the "فلاش كارد" phrase, which Arabic med platforms use) or **تكرار** (spaced repetition as "تكرار متباعد") in place of مراجعة.
- **تشريح** (anatomy) or **فارما** (Egyptian slang for pharmacology) in place of زمالة, if the app turns out to rank for undergraduate searches rather than postgraduate ones.

Keywords can only change with a new app version. Review them at each update, using App Store Connect → App Analytics → Sources → App Store Search.

**Why "Anki alternative" is not in any field.** The request listed it, but Apple's keyword help says "Names of other apps or companies aren't allowed", 2.3.7 bans "popular app names", and plan §7 lists it as a known risk. A rejection here delays launch, and the app can lose the whole keyword field. The same intent is covered by:
- `flashcards` and `spaced repetition` in the keywords;
- `apkg` (a file format, not a brand) in the keywords;
- this sentence in the description: "Export any deck as an .apkg file".

---

## 6. Description (4,000 characters, plain text)

The en-GB description uses the en-US text unchanged. P6.1 must add a `metadata/en-GB/` folder: its file list today has only en-US and ar-SA. Copy the en-US description, release notes and URLs into it, and take the name, subtitle, keywords and promotional text from the en-GB blocks. The text avoids words whose US and UK spellings differ.

<!-- field: en-US/description.txt -->
```text
Vignette turns your own lectures into exam questions.

Drop in a lecture and get single-best-answer questions with an explanation for every option, spaced-repetition cards, OSCE stations and patient cases you can interview. Everything comes from your material, not someone else's question bank, so you revise exactly what you were taught.

Built for medical students, and for doctors preparing for USMLE Step 1 and Step 2 CK, PLAB 1 and 2, MRCP(UK) and MRCS.

WRITTEN FOR YOUR EXAM
Pick your exam and the questions follow its style: US units and guidelines for USMLE; SI units, NICE and the BNF for PLAB and MRCP. Timed mode and OSCE stations run at your exam's real pace.

STUDY MODES
• MCQ: exam-style vignettes with an explanation for each option.
• Cards: spaced repetition that brings each card back just before you'd forget it. Basic, cloze and image-occlusion cards.
• Due today: one list of everything waiting for review.
• OSCE: checklist stations with a timer. Practise them out loud.
• Cases: take a history from a patient who answers, then see your consultation marked against an OSCE checklist.
• Narrate: record a lecture and follow the transcript word by word, in Arabic or English.

WAYS TO MAKE IT STICK
• Commute mode: hear your due cards and questions and answer out loud, hands-free.
• Explain it back: explain a topic aloud and see what you missed, compared with the lecture.
• Draw from memory: sketch a diagram, then lay the real one over it. Works with a finger or Apple Pencil.
• Clinical reasoning: lookalike conditions side by side, clue-by-clue cases and disease scripts.

KNOW WHERE YOU STAND
• Syllabus coverage: see which parts of your exam's syllabus you haven't covered, and fill the gaps in one tap.
• Analytics: an estimated score range, your recurring mistakes, and a ranked list of what to study next.

ACCURACY YOU CAN CHECK
Tap Check accuracy on any question, card, station or case to compare it with the matching lecture pages. Cloud-written questions pass a medical checking model before you see them. AI can still be wrong, so the source is always one tap away.

YOURS TO KEEP
Export any deck as an .apkg file, or print sets as PDF. No account is needed to start.

PRIVATE BY DEFAULT
The free version writes questions on your iPhone or iPad with Apple's on-device model, and nothing leaves the device. There are no ads and no tracking. Cloud features ask for your permission first, and they name the providers they use (Google Gemini and Cloudflare Workers AI).

VIGNETTE PRO
• Read PDF, Word and PowerPoint handouts.
• Medical models on the device (Doctor-R1 and MedVAL) where your device has the memory.
• Vignette Cloud: Google's Gemini writes and checks questions, stations and cases on any device, even after you close the app.
• Turn labelled diagrams into occlusion cards.
• Cloud transcription of recorded lectures, in Arabic or English, and a natural reading voice.
• Your library synced between your iPhone and iPad.

Pro is an auto-renewable subscription, monthly or yearly. Payment is charged to your Apple Account at confirmation of purchase. It renews automatically unless you cancel at least 24 hours before the end of the current period. Manage or cancel any time in Settings > Apple Account > Subscriptions.
[ship-gated: P2.3] An Exam Pass gives three months of Pro for one payment and never renews.

FOR EDUCATION ONLY
Vignette is a study tool for medical education. It is not medical advice and must not be used for diagnosis, treatment or patient care. Do not enter information that could identify a patient.

USMLE is a program of the FSMB and NBME. PLAB is run by the GMC. MRCP(UK) and MRCS are run by the Royal Colleges. Vignette is not affiliated with or endorsed by any of them.

Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://redpen-auth.vv7sh4rnnw.workers.dev/privacy
Support: https://redpen-auth.vv7sh4rnnw.workers.dev/support
```

<!-- field: ar-SA/description.txt -->
```text
Vignette يحوّل محاضراتك أنت إلى أسئلة امتحان.

أضف محاضرتك واحصل على أسئلة MCQ بأسلوب الامتحان مع شرح لكل اختيار، وكروت مراجعة بالتكرار المتباعد، ومحطات OSCE، وحالات مرضية تسأل فيها المريض فيجيبك. كل شيء مكتوب من محاضراتك، لا من بنك أسئلة لشخص آخر، فتراجع بالضبط ما درسته.

مصمَّم لطلاب كليات الطب في مصر والعالم العربي، وللأطباء المستعدين لـ USMLE Step 1 وStep 2 CK وPLAB 1 و2 وMRCP(UK) وMRCS.

مكتوب بأسلوب امتحانك
اختر امتحانك فتُكتب الأسئلة بأسلوبه: الوحدات والإرشادات الأمريكية لـ USMLE، ووحدات SI وإرشادات NICE وBNF لـ PLAB وMRCP. وضع التوقيت ومحطات OSCE بسرعة امتحانك الحقيقي.

أوضاع المذاكرة
• MCQ: أسئلة حالات بأسلوب الامتحان مع شرح لكل اختيار، وملخص لما يجب أن تصلحه.
• الكروت: تكرار متباعد يعيد لك كل كارت قبل أن تنساه مباشرة. كروت عادية وCloze وإخفاء أجزاء الصور (Image Occlusion).
• مراجعة اليوم: قائمة واحدة بكل ما ينتظر المراجعة.
• OSCE: محطات بقائمة تقييم ومؤقت، وتقدر تتدرب عليها بصوتك.
• الحالات: خذ التاريخ المرضي من مريض يرد عليك، ثم تُقيَّم مقابلتك بقائمة OSCE.
• Narrate: سجّل المحاضرة وتابع نصها كلمة بكلمة، بالعربية أو الإنجليزية.

طرق تثبّت المعلومة
• وضع المواصلات: التطبيق يقرأ لك الكروت والأسئلة المطلوبة اليوم ويسمع إجابتك، بدون ما تلمس الشاشة.
• اشرحها بصوتك: اشرح الموضوع بصوت عالٍ، وشوف ما غطيته وما فاتك وما أخطأت فيه مقارنة بالمحاضرة.
• ارسم من الذاكرة: ارسم الشكل ثم ضع الأصل فوقه. بإصبعك أو بـ Apple Pencil.
• الحالات المتشابهة جنبًا إلى جنب، وحالات تُكشف معلومة بمعلومة، وملخصات الأمراض، لتقوية التفكير الإكلينيكي.

اعرف مستواك
• تغطية المنهج: اعرف أي أجزاء منهج امتحانك لم تذاكرها بعد، واصنع أسئلة عليها بلمسة.
• التحليلات: درجة تقديرية، وأخطاؤك المتكررة، وقائمة مرتبة بما تذاكره بعد ذلك.

دقة يمكنك التحقق منها
اضغط Check accuracy على أي سؤال أو كارت أو محطة أو حالة لمقارنته بصفحات المحاضرة المطابقة. الأسئلة المكتوبة سحابيًا يفحصها نموذج تحقق طبي قبل أن تراها. الذكاء الاصطناعي قد يخطئ، لذلك المصدر دائمًا على بُعد لمسة.

ملكك بالكامل
صدّر أي مجموعة كروت كملف ‎.apkg أو اطبع المجموعات كملف PDF. لا تحتاج حسابًا لتبدأ.

خصوصيتك أولًا
النسخة المجانية تكتب الأسئلة على جهازك بنموذج Apple الموجود على الجهاز، ولا يغادر شيء هاتفك. لا إعلانات ولا تتبع. الميزات السحابية تطلب إذنك أولًا وتذكر الجهات التي تستخدمها (Google Gemini وCloudflare Workers AI).

Vignette Pro
• قراءة ملفات PDF وWord وPowerPoint.
• نماذج طبية على الجهاز (Doctor-R1 وMedVAL) إذا كانت ذاكرة جهازك تكفي.
• Vignette Cloud: نموذج Gemini من Google يكتب ويفحص الأسئلة والمحطات والحالات على أي جهاز، ويستمر في الكتابة بعد إغلاق التطبيق.
• تحويل الرسومات المعنونة إلى كروت إخفاء أجزاء الصور.
• تفريغ المحاضرات المسجلة سحابيًا بالعربية أو الإنجليزية، وصوت قراءة طبيعي.
• مزامنة مكتبتك بين iPhone وiPad.

Pro اشتراك يتجدد تلقائيًا، شهريًا أو سنويًا. يُخصم المبلغ من حساب Apple عند تأكيد الشراء، ويتجدد تلقائيًا ما لم تلغِه قبل نهاية الفترة الحالية بـ 24 ساعة على الأقل. يمكنك الإدارة أو الإلغاء في أي وقت من الإعدادات > حساب Apple > الاشتراكات.
[ship-gated: P2.3] تذكرة الامتحان (Exam Pass): ثلاثة أشهر من Pro بدفعة واحدة، ولا تتجدد أبدًا.

للتعليم فقط
Vignette أداة مذاكرة للتعليم الطبي. ليس نصيحة طبية ولا يُستخدم للتشخيص أو العلاج أو رعاية المرضى. لا تُدخل أي معلومات قد تكشف هوية مريض.

USMLE برنامج تابع لـ FSMB وNBME، وPLAB يديره GMC، وMRCP(UK) وMRCS تديرهما الكليات الملكية. Vignette غير تابع لأي منها ولا معتمد منها.

شروط الاستخدام: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
سياسة الخصوصية: https://redpen-auth.vv7sh4rnnw.workers.dev/privacy?lang=ar
الدعم: https://redpen-auth.vv7sh4rnnw.workers.dev/support
```

Notes on the description:
- **Links.** The `/privacy` and `/support` pages come from P1.8. Today the paywall links to `redpen.app`, which is not known to be owned; that is launch blocker 3 in the plan. Do not submit until the Worker pages return 200 (P6.2 step 6). The Apple EULA link satisfies the "functional link to the terms of use" rule for subscriptions in guideline 3.1.2. When P1.8 ships `/terms`, add it as a line.
- **Pro list.** It matches the perks in `Features/Paywall/PaywallView.swift`, plus sync and background generation, which the server gates as Pro (`server/jobs.js`, `server/sync.js`).
- **Free version.** "Nothing leaves the device" is true only for the free, on-device path; that is why the sentence is worded exactly as it is. Before submission, confirm that "No account is needed to start" (the local sign-in on `preview/graph`) is in the App Store build.
- **Later additions.** Once they ship, add widgets, the Live Activity and Siri (P3.1), and share links and classes (P2.1/P2.2), each as one line under YOURS TO KEEP. Never describe leaderboards as contests or challenges.

---

## 7. What's New (template, 4,000 characters; guideline 2.3.12 requires real changes to be listed)

First release:

<!-- field: en-US/release_notes.txt -->
```text
Welcome to Vignette. Turn your lectures into exam-style questions, spaced-repetition cards, OSCE stations and patient cases, on your iPhone and iPad. Tell us what to build next from Settings > Support.
```

<!-- field: ar-SA/release_notes.txt -->
```text
أهلًا بك في Vignette. حوّل محاضراتك إلى أسئلة بأسلوب الامتحان وكروت بالتكرار المتباعد ومحطات OSCE وحالات مرضية، على iPhone وiPad. قل لنا ماذا نبني بعد ذلك من الإعدادات > الدعم.
```

Template for later versions. Keep the order: what students can now do, then what got better, then fixes. Never use "bug fixes" alone when a feature changed.

```text
NEW
• [Outcome first: "Make questions from a photo of the whiteboard."] [Where: Library > New set.]
IMPROVED
• [Measured change: "Cards open twice as fast in large decks."]
FIXED
• [Student-visible symptom: "Arabic transcripts no longer drop the last sentence."]
```

```text
الجديد
• [النتيجة أولًا: "اصنع أسئلة من صورة السبورة."] [المكان: المكتبة > مجموعة جديدة.]
تحسينات
• [تغيير قابل للقياس: "الكروت تفتح أسرع بمرتين في المجموعات الكبيرة."]
إصلاحات
• [ما كان يلاحظه الطالب: "نص المحاضرة العربي لم يعد يُسقط الجملة الأخيرة."]
```

---

## 8. Screenshot captions (8, in order)

Rules:
- The first three screenshots show in search results, so they carry the promise.
- Each caption is an outcome for the student, with a short proof line under it.
- There are no prices, no "best", no "#1" and no pass guarantees (2.3.7 and 2.3.8).
- Every image must show the app in use, not a title card (2.3.3).
- Use sample content only; no real patient data.
- The images are **iPhone 6.9"** and **iPad 13"**, in English and Arabic, made by `StoreScreenshotsUITests` driving the `-uiPreviewScreen` screens. `caption.py` draws the captions (P3.2).
- In the Arabic images, MCQ and card content stays in English, because that is how Egyptian faculties teach. Only the caption is Arabic, and occlusion stays left-to-right (P5.7).

| # | Preview screen | EN headline | EN proof line | AR headline | AR proof line |
|---|---|---|---|---|---|
| 1 | `new` (a lecture being turned into a set) | Your lecture, now a Qbank | Questions, cards and stations from your own notes | محاضرتك صارت بنك أسئلة | أسئلة وكروت ومحطات من ملاحظاتك أنت |
| 2 | `quiz-checked` | Learn why the other four are wrong | An explanation for every option | اعرف لماذا الاختيارات الأخرى خاطئة | شرح لكل اختيار |
| 3 | `anki-revealed` | Remember it on exam day | Spaced repetition brings each card back just in time | تذكّرها يوم الامتحان | التكرار المتباعد يعيد كل كارت في وقته |
| 4 | `occlusion-example` | Label any diagram from memory | Image occlusion for anatomy, pathways and slides | سمِّ أجزاء أي رسمة من ذاكرتك | إخفاء أجزاء الصور للتشريح والمسارات والشرائح |
| 5 | `osce-revealed` | Walk into your OSCE rehearsed | Timed stations with the full checklist | ادخل الـ OSCE وأنت متدرّب | محطات بمؤقت وقائمة تقييم كاملة |
| 6 | **new screen needed:** `case-chat` (a Cases interview in progress) | Take a history. The patient answers. | Then see what you missed, marked like an OSCE | خذ التاريخ المرضي والمريض يرد عليك | ثم اعرف ما فاتك بتقييم مثل الـ OSCE |
| 7 | `narrate-finished` | Missed the lecture? Read it. | Recordings become transcripts, Arabic or English | فاتتك المحاضرة؟ اقرأها | التسجيل يتحول لنص بالعربي أو الإنجليزي |
| 8 | **new screen needed:** `analytics` (next steps and score range), or `summary` until then | Know exactly what to study next | Your gaps, ranked against the exam syllabus | اعرف بالضبط ماذا تذاكر بعد ذلك | نقاط ضعفك مرتبة حسب منهج الامتحان |

Screen notes:
- `case-chat` and `analytics` are not in today's list in `.github/workflows/ios-preview.yml`, so P3.2's screenshot UI test has to add them. Until then, use `qa-revealed` for #6 and `summary` for #8.
- Caption #7 is a Pro feature (cloud transcription). On-device transcription also exists (`LectureTranscriber`, on-device only), so the caption holds either way.
- On iPad, #4 and the drawing recall screen show best in landscape.

<!-- captions: P6.1 builds metadata/screenshot-captions.json from the table above -->

---

## 9. Age rating questionnaire answers

These are the answers to the questionnaire as it stands after Apple's 2025 update; submissions have been blocked without them since 31 Jan 2026. Each answer is based on what the app contains.

| Section | Question | Answer | Reason |
|---|---|---|---|
| In-app controls | Parental Controls | No | |
| | Age Assurance | No | |
| Capabilities | Unrestricted Web Access | No | Links open specific pages (sources, legal) in Safari. There is no in-app browser. |
| | User-Generated Content | **No today. Yes once P2.1 or P2.2 ships** (shared sets, class sets, display names). | Today every set is private to its account (`schema.sql`: "Nothing here is shared with anybody else"). |
| | Social Media | No | |
| | Messaging and Chat | No | Cases is a chat with an AI patient, not with other people. Say so in the review notes. |
| | Advertising | No | |
| Mature themes | Profanity or Crude Humor | None | |
| | Horror/Fear Themes | None | |
| | Alcohol, Tobacco, or Drug Use or References | **Infrequent** | Pharmacology and substance-use topics are taught as clinical content. This alone gives 13+. |
| Medical or wellness | **Medical or Treatment Information** | **Frequent** | The whole app is medical teaching content. **This gives 16+**, and it also triggers the regulated-medical-device declaration. |
| | Health or Wellness Topics | Yes | Gives 9+, below the result anyway. |
| Sexuality or nudity | Mature or Suggestive Themes | None | |
| | Sexual Content or Nudity | None | Sample content has no nudity. Anatomy slides a student imports are their own private content. If shared sets ship with public browsing, revisit this answer. |
| | Graphic Sexual Content and Nudity | None | |
| Violence | Cartoon or Fantasy / Realistic / Prolonged Graphic / Guns | None | Trauma is taught as clinical content, not depicted. |
| Chance | Gambling, Simulated Gambling, Loot Boxes | No / None / No | |
| | Contests | None | The planned leaderboards have no prizes and no "win" wording (plan §7, rule 5.3). |

**Computed rating: 16+.** Then choose **Override to Higher Age Rating → 18+**, for two reasons:
1. The Gemini API terms say you "will not use the Services as part of a[n] ... application ... that is directed towards or is likely to be accessed by individuals under the age of 18". Vignette Cloud uses Gemini through Firebase AI Logic.
2. The cloud-AI consent in plan P2.9 already asks the user to confirm they are 18 or older.

The cost is that a few 17-year-old first-year students in Egypt cannot download the app. The alternative is to keep 16+ and rely on the in-app 18+ gate before any cloud feature. That is defensible but weaker against the Gemini terms, so it is the owner's call; the plan's default is 18+.

**Regulated medical device status** is required because of the Frequent answer. Answer "Not a regulated medical device" for the US, the UK and the EEA.

---

## 10. App Privacy ("nutrition label") answers, from the code

Sources read:
- `server/schema.sql`, `server/worker.js`, `server/sync.js`, `server/jobs.js`, `server/tts.js`, `server/pair.js`, `server/ai.js`, `server/evidence.js`;
- every `URLSession` caller in `ios/RedPen`, plus `Info.plist` usage strings in `ios/project.yml`.

Apple's definition: data is **collected** when it leaves the device and stays available longer than it takes to serve the request in real time. On-device processing is not collection.

**Tracking: No.**
- There are no ad or analytics SDKs, and no IDFA or IDFV is read or sent (grep: no `advertisingIdentifier`, `identifierForVendor` or `MetricKit` today).
- The only third-party package is `LocalLLMClient`, which runs models on the device.

### 10.1 What the current code collects

For each type the answer is: **Data Linked to You**, purpose **App Functionality**, not used for tracking.

| Data type | Where in the code | Collected when |
|---|---|---|
| Contact Info → **Name** | `worker.js upsert()`: `display_name` from Apple's `fullName` or Google's `name` claim | Only with Sign in with Apple or Google. The device account stores none. |
| Contact Info → **Email Address** | `worker.js upsert()`: `email` from the Apple or Google token (may be Apple's private relay address) | Same as Name |
| Identifiers → **User ID** | `accounts.id` and the provider `subject` | Any account, including a device account |
| Purchases → **Purchase History** | `accounts.original_transaction_id`, `plan`, `expires_at`, `verified_until`, `apple_env` | Subscribers |
| User Content → **Other User Content** | Several paths, listed after this table | Pro, or when a cloud feature is used |
| User Content → **Photos or Videos** | `/blobs/*` stores slide and diagram images from lectures under the image's hash (`BlobRefs.swift`, `sync.js`) | Pro sync, only while R2 is enabled. **Declare it anyway**, so the label stays true when R2 is switched on. |
| User Content → **Audio Data** | `/transcribe/chunk`: lecture audio in 10-minute chunks, forwarded to Gemini. The free-tier Gemini terms let Google keep inputs for human review. | Pro cloud transcription only |
| Usage Data → **Product Interaction** | `ai_usage` (cloud requests per account per day), `ai_cost` (estimated spend per month), TTS daily line counts | Pro or cloud use |

Other User Content comes from these paths:
- the synced library in `docs` (sets, folders, review schedule, learned pronunciations);
- lecture text and prompts in cloud generation jobs (`jobs.js`, kept up to 7 days);
- text sent for accuracy checks, syllabus-coverage checks and the Cases patient (`/v1/chat/completions`), forwarded to Gemini, Workers AI, Novita or Hugging Face;
- lines read aloud (`/tts`, cached in R2 by hash).

### 10.2 Not collected (answer "No")

- **Location, Health & Fitness, Financial Info, Contacts, Browsing History, Search History, Sensitive Info, Device ID, Diagnostics.** Payment is handled entirely by Apple.
- **Camera.** Pop-out face tracking runs in ARKit on the device and nothing is recorded or sent (`NSCameraUsageDescription`).
- **Microphone and speech.**
  - `LectureTranscriber` forces on-device recognition.
  - `VoiceListener` uses on-device recognition where the device supports it.
  - Neither is developer collection.
- **Hosted models the student adds with their own API key** (OpenAI, Anthropic, OpenRouter, Groq, Gemini, their own server). Requests go straight from the device to the provider the student chose and never reach Vignette's servers, so they are not Vignette's collection. The privacy policy should still mention them.
- **Model downloads from Hugging Face** are downloads only.
- **IP addresses.** `pair_attempts` stores the IP per hour to rate-limit device accounts and pairing codes. Apple has no IP category and this is security use, so the label does not include it. The privacy policy must mention it.

### 10.3 Add these rows when the planned packages ship (plan §6)

| Package | Add to the label |
|---|---|
| P1.8 / P2.9 support form and error reports | User Content → **Customer Support**. Linked. App Functionality. |
| P2.1 / P2.2 shares, classes, display names, opt-in leaderboards | Already covered by Other User Content and Product Interaction (linked). Add **Name** if display names can be real names. |
| P2.8 opt-in telemetry | Usage Data → Product Interaction, **Not Linked**, Analytics. Diagnostics → Crash Data, Performance Data and Other Diagnostic Data, **Not Linked**, App Functionality and Analytics. |

### 10.4 Gaps found in the code (for the server job to fix; this file changes no code)

1. **`pair_attempts` rows are never deleted.** Nothing removes old hours, so hashed-hour IP rows pile up indefinitely, while the policy draft (design F) promises "rate-limit counters 48 h". The fix is a cron cleanup or a delete-on-write of old hours.
2. **`/account/delete` does not clear stored jobs.** It wipes `docs`, `sync_state`, blobs, `pair_codes` and the account row, but not the account's Durable Object jobs, which hold lecture text for up to 7 days. The policy must either say "generation jobs expire within 7 days" or the delete must clear them.
3. **`ai_usage` and `ai_cost` survive deletion on purpose** (a comment in `worker.js` explains why). They hold only the account id, now orphaned, plus counts. The policy should say so.
4. **The paywall's Terms and Privacy links go to `https://redpen.app/…`**, which is not known to exist. This is a rejection under 3.1.2 until P0.2 or P1.8 moves them to the Worker pages.

---

## 11. Length check (measured with Python on this file)

| Field | en-US | en-GB | ar-SA | Limit |
|---|---|---|---|---|
| Name | 29 | 29 | 24 | 30 characters |
| Subtitle | 29 | 30 | 26 | 30 characters |
| Keywords | 98 B | 100 B | 98 B (53 characters) | 100 bytes |
| Promotional text (default) | 164 | 154 | 122 | 170 characters |
| Seasonal promotional texts (§4) | 111–149 | same as en-US | 84–117 | 170 characters |
| Description | 3,953 (3,861 without the ship-gated line) | same as en-US | 3,438 (3,343) | 4,000 characters |
| What's New (first release) | 201 | same as en-US | 176 | 4,000 characters |

P6.1's `test_metadata.py` should run the same checks: characters for every field, UTF-8 bytes for keywords, no "Anki" in the name, subtitle or keywords, no prices, and no `[ship-gated` marker left in an uploaded file.

---

## 12. Price context (never in metadata; set in App Store Connect by P3.2)

These come from design B §8, adjusted by plan P2.3. Pick the nearest of Apple's 800 price points per currency.

| Storefront | Monthly | Yearly (1-week free trial) | Exam Pass, 3 months, non-renewing [P2.3] |
|---|---|---|---|
| USA (base) | $4.99 | $34.99 | $12.99 |
| UK | £4.99 | £29.99 | £10.99 |
| Egypt (EGP, 14% VAT included in the price) | EGP 99 | EGP 699 | EGP 249 |
| Saudi Arabia / UAE | SAR 19.99 / AED 18.99 | SAR 139.99 / AED 129.99 | SAR 49.99 / AED 44.99 |

Other notes:
- The Small Business Program cuts Apple's commission to 15%.
- The owner pays for no AI credits. `PRO_PAYS` stays `off`, and Vignette Cloud runs on free allowances until revenue exists (`wrangler.toml`). The listing therefore promises no usage amounts.
- Never raise list prices in exam season. Use the trial and offer codes instead.

---

## 13. Owner's unavoidable App Store Connect steps for the listing

Agents upload everything else through the App Store Connect API (P3.2): name, subtitle, keywords, description, promotional text, What's New, screenshots, categories, age-rating answers, subscriptions and prices. **Do not paste any key into chat.** Every step can be done on an iPhone or iPad, in Safari or the App Store Connect app.

1. **Create the app record** (the API cannot do this).
   - Where: Apps → + → New App.
   - Platform: iOS. Name: `Vignette: Medical MCQs & OSCE` (if it is refused as taken, use option B from §2).
   - Primary language: English (U.S.). Bundle ID: `com.cramdown.app`. SKU: `vignette-ios`.
2. **App Privacy** (web only). Answer "Yes, we collect data" and "No tracking", then enter the rows in §10.1 exactly.
   - Privacy Policy URL: `https://redpen-auth.vv7sh4rnnw.workers.dev/privacy`.
   - For the Arabic localisation, use the same URL with `?lang=ar`.
3. **Age rating.**
   - Check the answers the agents set (§9).
   - Choose **Override to Higher Age Rating → 18+**.
4. **Regulated medical device declaration:** "Not a regulated medical device" for the US, the UK and the EEA.
5. **EU Digital Services Act trader status.** Declare it; a subscription seller is probably a trader, so Apple shows an address, phone and email in the EU. Alternatively, tell the agents to leave out EU storefronts at launch.
6. **App Review information.** Enter your own contact name, phone and email; agents never store them. The notes and demo are pre-filled from `review-notes.txt` (P6.1).
7. **First submission.**
   - Attach the in-app purchases to the version (Apple requires the first subscription to go with a version).
   - Check that the en-GB and Arabic localisations are present.
   - Press **Submit for Review**.

These business steps come before the steps above: the Developer Program, the Team API key as GitHub secrets, the Paid Apps agreement with bank and tax details, and the Small Business Program. They are in `implementation-plan.md` §6, steps 1–5.

---

## 14. Risks and checks before submitting

- **2.3.7 keywords.**
  - No app or company names are used. Exam names are backed by `ExamTrack`.
  - If Review objects to an exam name anyway, remove that keyword in the next version rather than arguing.
- **1.4.1 medical.**
  - The education-only wording appears in the description, and the category is Education.
  - Keep the accuracy numbers out of the listing unless they link to `/accuracy` (plan P6.1).
- **5.1.2(i) third-party AI.** The description names Gemini and Workers AI. The in-app consent (P2.9) must name the same providers and must come before the first upload.
- **2.3.1 accuracy of the listing.** Remove every `[ship-gated]` line whose package has not shipped. Screenshot #6 and #8 need the new preview screens.
- **Arabic rendering.** P3.2's caption renderer must use `arabic-reshaper` and `python-bidi`. Check that "OSCE" and "Qbank" inside Arabic captions are not reversed.

---

## Sources

- [Apple: App Store Connect, platform version information (keywords "up to 100 bytes"; "Names of other apps or companies aren't allowed"; promotional text 170; description 4,000)](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [Apple: App Review Guidelines (2.3.1, 2.3.3, 2.3.7 names ≤ 30 and no app names or prices, 2.3.8, 2.3.12, 3.1.2, 5.1.2(i))](https://developer.apple.com/app-store/review/guidelines/)
- [Apple: App Store localizations by storefront (Egypt, Saudi Arabia and UAE default to English (U.K.) with Arabic)](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations/)
- [aso.dev: cross-localization (phrases form within one localisation; no boost from repetition)](https://aso.dev/metadata/cross-localization/)
- [AsoBeast PR #110: keyword field counted in UTF-8 bytes](https://github.com/AsoBeast/asobeast/pull/110)
- [Appfigures: keyword optimisation in App Store Connect](https://appfigures.com/resources/guides/keyword-optimization-app-store-connect)
- [Apple: age ratings values and definitions (Medical or Treatment Information Frequent → 16+)](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)
- [Apple: updated age ratings in App Store Connect](https://developer.apple.com/news/?id=ks775ehf)
- [PTKD: 2025 age rating overhaul, override to a higher rating](https://ptkd.com/journal/app-store-age-ratings-2025-update)
- [Apple: regulated medical device status (developer news)](https://developer.apple.com/news/?id=nyqbfz1y)
- [Apple: App privacy details (definition of "collect", data types, linked data, third-party partners)](https://developer.apple.com/app-store/app-privacy-details/)
- [Gemini API Additional Terms (18+, no clinical use, unpaid-tier human review)](https://ai.google.dev/gemini-api/terms)
- [Apple: Egypt 14% VAT (price and tax update, July 2023)](https://developer.apple.com/news/?id=9o2nwe38)
- [Apple: App Store pricing upgrades (800 price points per currency, per-storefront prices)](https://developer.apple.com/news/?id=dbrszv62)
- [GMC: when and where to take PLAB 1](https://www.gmc-uk.org/registration-and-licensing/join-our-registers/plab/plab-1-guide/when-and-where-can-i-take-plab-1)
- [MedRevisions: PLAB 1 2026 dates (12 Feb, 21 May, 13 Aug, November)](https://www.medrevisions.com/about-plab-news/plab-1-exam-dates-2026-schedule)
- [StudyMRCP: MRCP Part 1 2027 dates (20 Jan 2027; applications 27 Oct to 3 Nov 2026)](https://studymrcp.com/blog/mrcp-part-1-exam-dates-upcoming-part-1-exam-dates-in-2027/)
- [Egyptian Health Council: practice (licensing) exam](https://www.ehc.gov.eg/ar/practice-exam)
- [Aswan University: Supreme Council of Universities decision on the human-medicine practice exam](https://med.aswu.edu.eg/news/decision-of-the-supreme-council-of-universities-regarding-the-dates-of-the-examination-to-practice-the-profession-of-human-medicine/)
- [Wikipedia: Egyptian Medical Licensing Examination](https://en.wikipedia.org/wiki/Egyptian_Medical_Licensing_Examination)
- Arabic terms used by Arabic medical-study platforms ("بنك أسئلة", "فلاش كاردس", "تكرار متباعد"): [MedPal](https://medpaledu.com/), [YourMedPass FAQ](https://yourmedpass.com/faq), [Dr Issam: Anki flash-card guide in Arabic](https://drissam.com/%D8%B4%D8%B1%D8%AD-%D8%AA%D8%B7%D8%A8%D9%8A%D9%82-%D8%A7%D9%86%D9%83%D9%8A-%D9%84%D8%B9%D9%85%D9%84-%D8%A7%D9%84%D9%81%D9%84%D8%A7%D8%B4-%D9%83%D8%A7%D8%B1%D8%AF/)
- Repository files read: `ios/project.yml`, `ios/RedPen/RedPen.storekit`, `Features/Paywall/PaywallView.swift`, `Shared/Entitlement.swift`, `Shared/ExamTrack.swift`, `Shared/Brand.swift`, `Shared/ApkgExporter.swift`, `Shared/BlobRefs.swift`, `Shared/LectureTranscriber.swift`, `Shared/Voice/*`, the feature folders, `server/*.js`, `server/schema.sql`, `server/wrangler.toml`, `docs/launch/implementation-plan.md` and designs B and F.
