# Vignette: ambassadors and referrals

Written 2026-09-24 against `preview/graph` (`effa18d`). This is one of the group G launch documents listed in `implementation-plan.md`. It covers four things:

- a student ambassador programme, with one ambassador per medical school;
- the referral programme's rules, as users and App Review will read them;
- the abuse controls behind both;
- a playbook for Telegram and WhatsApp groups that respects each group's own rules.

**Who uses this file:**

- **P1.4** (server): referrals, ambassadors, the `/r/` and `/a/` pages. See §11 for the gaps this file found.
- **P2.3** (app): `InviteFriendsView`, the invite sheet, the redeem-code button.
- **P2.5** (app): Owner tools → Ambassadors.
- **P3.2** (App Store Connect automation): the offer codes, from the seed block in §4.3.
- **P6.1** (metadata): the referral rules for `review-notes.txt`, from the copy blocks in §8.

As in `app-store-listing.md`, copy that must be used word for word sits in a fenced block after an HTML comment such as `<!-- field: referrals/rules.en.txt -->`.

**No challenges.** There is no "challenge a friend", no friend-versus-friend duel, no "tag a friend who…" and no competition with prizes anywhere in this programme. The owner rejected that idea. Ambassadors help classmates who ask. They never set up contests. The in-app "lookalike duels" are one student comparing two confusable conditions. They are unrelated to this, and ambassadors should call them "lookalike conditions" to avoid confusion.

---

## 0. Decisions at a glance

| Item | Decision | Why |
|---|---|---|
| Ambassadors | One per school: Cairo (Kasr Al Ainy), Ain Shams, Alexandria, Mansoura, Assiut, Zagazig, Tanta. In the Gulf, up to five campus reps in the first term. | This is the owner's brief. Five Gulf reps keeps the owner's weekly time small. |
| Gulf role | **Feedback and Arabic/English QA rep. No public promotion.** | The UAE has required an Advertiser Permit for paid *and unpaid* promotion since 1 Feb 2026. Saudi Arabia requires a Mawthooq licence for social-media advertising, and sponsorship counts. A student who gets free Pro in return for posts falls under both. (§6.4) |
| Egypt role | Feedback, QA, answering questions, **at most one** promotional post per group per month, and only with the admin's OK. | Egypt's data protection law (Law 151/2020) restricts direct electronic marketing without consent, and its executive regulations apply from 1 Nov 2026. So there are no unsolicited DMs, ever. |
| What ambassadors are rewarded for | **Tasks done** (feedback, QA, help sessions). Never installs, sign-ups or rank. | Paying per install invites spam, fake accounts and review manipulation (Guideline 5.6.3). Rewarding tasks keeps the incentive clean. |
| Rewards | Pro for the academic year (class access, zero cost), their school's free-month offer code to hand out, normal referral credits, an end-of-term gift of up to 90 days, a certificate and a reference letter, and early TestFlight builds. | No cash and no paid AI credits. Every reward runs on free models, so none of it costs the owner money. |
| Offer codes | One Apple offer per Egyptian school on the **monthly** product, plus one shared `amb-gulf` offer and one `amb-general` offer. Each has **custom codes**. | Apple allows 10 active offers per subscription product. This plan uses 9 and keeps 1 spare. |
| Offer terms | **Free for 1 month. Eligibility: new and expired subscribers. Auto-renew off** ("commitment-free"). | Classmates trust the ambassador, and "nothing renews unless you choose" protects that trust. Apple allows auto-renew off on free offers. |
| Referral rules | Exactly as in `config-defaults.json`: the friend gets 7 days; you get 30 days after the friend comes back on a later day (and at least 72 h later); at most 3 a month and 12 a year; one per Apple Account, ever. | Already built into P1.4. §8 has the user-facing copy. |
| Prices | **Ambassadors never quote a price.** The line to use is "The App Store shows your local price." | Prices change and differ by storefront. Quoting a wrong price outside the App Store is exactly the "referral" manipulation Apple added to 5.6.3. |
| Reviews and ratings | Ambassadors never ask anyone to rate or review the app, and they do not post App Store reviews themselves while in the role. | 3.2.2 and 5.6.3. An ambassador is compensated, so their review would be an incentivised review. |
| Official status | "Student ambassador", never "official", "partner" or "recommended by the faculty". No faculty or university logos. | No university has endorsed the app. Implying that it has would mislead students (2.3.1 applies to the listing; honesty applies everywhere). |

---

## 1. Market facts that shape the programme

| Fact | Number | What it means here |
|---|---|---|
| iOS share of mobile web traffic, **Egypt**, Aug 2026 | **11.99 %** (Android 88.01 %) | Most classmates in any Egyptian batch cannot install Vignette. Every post starts with "iPhone and iPad only", so Android users do not waste their time and admins are not annoyed. |
| iOS share, **Saudi Arabia**, Aug 2026 | **51.96 %** | The largest iPhone share among the target markets. Gulf reps are worth having even though they do no promotion. |
| iOS share, **UAE**, Aug 2026 | **22.46 %** | Moderate. |
| Payment methods for an Apple Account in Egypt | cards, Apple Account balance, **Vodafone carrier billing** | Many students have no card. Ambassadors can mention that the App Store accepts Vodafone billing and account balance. The free-month code avoids the question at first. |
| Carrier billing in the Gulf | KSA: Mobily, STC, Zain. UAE: du, Etisalat. Kuwait, Qatar, Bahrain and Oman: the main carriers. | Paying is easy in the Gulf. |

These are StatCounter web-traffic shares, not device ownership. Students are likely to own more iPhones than the national average, but the programme's targets (§9) assume the national figure.

---

## 2. Calendar for 2026/27 and the programme's phases

### 2.1 Dates

| Dates | Egypt (Supreme Council of Universities calendar) | Gulf and licensing | Programme |
|---|---|---|---|
| now to mid-Oct 2026 | Term 1 started Sat **19 Sep 2026** (15 weeks). | KSA's 1448 academic year started about **23 Aug 2026**. SMLE window **1–22 Oct**. | **Recruit** (§3). Candidates apply from inside the app (TestFlight before launch). |
| Launch (L) | | | Offer codes can only be *generated* once the app is Ready for Distribution and the subscription is approved (§4.2). Ambassadors start handing out codes on L. |
| **1–21 Nov 2026** | Term 1 **midterms**, in the first three weeks of November (varies by faculty). | SMLE window 1–24 Nov. | **Light weeks** (§5.2). No promotional posts. |
| Dec 2026 | Teaching ends Thu **31 Dec**. Pre-final revision. | SMLE window 1–24 Dec. | Revision-tip posts are welcome. This is the best time for help sessions. |
| **2–21 Jan 2027** | Term 1 **finals**. | | **Pause.** Ambassadors do nothing and post nothing. |
| 23 Jan – 4 Feb 2027 | Mid-year break. | EMLE has historically sat in **February** and September (check the Egyptian Health Council). | Term review, gift grants (§7), certificates, rotation to the "27" codes (§4.2). |
| 6 Feb 2027 | Term 2 starts. | | **Relaunch week**: the second promotional post of the year, with the admin's OK. |
| late Mar – early Apr 2027 | Term 2 midterms. | | Light weeks. |
| 20 May 2027 | Term 2 teaching ends. | | |
| May–Jun 2027 | Term 2 finals (by faculty). | | Pause. |
| Jul 2027 | | | End of the 2026/27 cohort. Certificates. Recruit the 2027/28 cohort. |

Medical faculties often run their own module or block exams within these windows. **Each ambassador enters their faculty's real exam weeks during onboarding (§5.1).** Those weeks override this table for that school.

**Exam tracks.** The app's exam tracks are General revision, USMLE, PLAB, MRCP(UK) and MRCS (`Shared/ExamTrack.swift`). There is **no EMLE or SMLE track**. Ambassadors must not claim "EMLE questions" or "SMLE questions". For faculty exams and EMLE revision they say: "use General revision on your own lectures." (§11 lists an EMLE/SMLE track as a product idea.)

### 2.2 Phases

1. **Pre-launch (TestFlight).** Ambassadors test builds and report problems. No promotion, because there is nothing to install yet.
2. **Term 1 after launch.** Codes go live. One introductory post per group, then help on request.
3. **Break review.** Rewards are given out, codes rotate, and ambassadors who went quiet are replaced.
4. **Term 2.** Relaunch week, then the same rhythm.
5. **Handover in July.** Each ambassador may nominate a successor. The owner decides.

---

## 3. Recruiting

### 3.1 Who to pick

| Must | Why |
|---|---|
| Uses an iPhone or iPad daily | They have to use the app to give real feedback. |
| **18 or over** | The age rating is 18+ (Gemini API terms, `app-store-listing.md` §9), and the ambassador agreement is a commitment. |
| Year 2 to final year, not in their internship year | Has lectures to test with, and time. |
| Active and trusted in their batch, but **not an influencer**: no public account with more than 5,000 followers used for promotion | Egypt's Law 180 of 2018 lets the media regulator treat personal accounts with more than 5,000 followers like media outlets. Peer trust matters more than reach anyway. |
| Writes clear Arabic **and** English | Arabic QA is a weekly task. |
| Agrees to the rules in §5.4 | |

**Nice to have:**
- is a group admin or class rep (though admins still need the other admins' agreement before posting);
- is preparing for USMLE, PLAB or MRCP (those tracks exist);
- has run study circles.

**Avoid:**
- anyone who sells notes or "summaries" commercially;
- anyone who already represents a competing study app (conflict of interest);
- more than one ambassador per school.

### 3.2 Where to recruit (all pull, no cold DMs)

1. **Inside the app.** A support message whose first line is `Ambassador application: <school>` goes to `POST /support/message`, and the owner sees it in Owner tools → Support. This also shows that the applicant has an iPhone or iPad. Before launch, the path is the TestFlight public link. (Both routes arrive in P1.8/P2.9. §11 asks for a subject prefix filter.)
2. **The recruitment post (§3.3) in the owner's own channels.** These are the app's Telegram channel and its WhatsApp Channel, if the owner makes them (optional). Friends of early users can forward it.
3. **Student activity clubs** (for example the medical students' scientific societies at each faculty). Only with the club's permission, and only in the club's own "opportunities" or "announcements" slot.

Never post the recruitment message in a batch group without the admin's OK (§6). Never message students individually.

### 3.3 The recruitment message

<!-- field: ambassadors/recruit.en.txt -->
```text
Vignette is looking for ONE student ambassador at {Faculty}.

Vignette is a new iPhone and iPad app that turns your own lectures into exam-style MCQs, spaced-repetition cards and OSCE stations. It is for studying, not for clinical decisions.

What you'd do (about 90 minutes a week in term, less near exams, nothing during finals):
• use it on your own lectures and tell us what works and what doesn't
• check the Arabic
• help classmates who ask about it

What you'd get:
• Vignette Pro free for the academic year
• a free-month code for your classmates
• a certificate and a reference letter that describes your work

What you'd never do: spam groups, ask anyone for App Store reviews, or share lecture files.

You need an iPhone or iPad, to be 18 or over, and to be in Year 2 or above. Vignette is not affiliated with {University}.

To apply: open Vignette → Settings → Help → Contact us, and start your message with "Ambassador application: {Faculty}". Tell us your year, the groups you're active in, and one thing you'd change about how your batch revises. Deadline: {date}.
```

<!-- field: ambassadors/recruit.ar-EG.txt -->
```text
Vignette بيدوّر على سفير واحد بس في {الكلية}.

Vignette تطبيق جديد على iPhone وiPad بيحوّل محاضراتك إنت لأسئلة MCQ بنفس ستايل الامتحان، وكروت مراجعة متباعدة، ومحطات OSCE. التطبيق للمذاكرة بس، مش للقرارات الطبية.

هتعمل إيه (حوالي ساعة ونص في الأسبوع وقت الدراسة، أقل قبل الامتحانات، وولا حاجة وقت الفاينال):
• تستخدمه على محاضراتك وتقولنا إيه اللي شغال وإيه اللي محتاج يتصلح
• تراجع الترجمة العربي
• تساعد زمايلك اللي يسألوا عنه

هتاخد إيه:
• Vignette Pro ببلاش طول السنة الدراسية
• كود شهر مجاني لزمايلك
• شهادة وخطاب توصية بيوصف شغلك

عمرك ما هتعمل: سبام في الجروبات، أو تطلب من حد تقييم على App Store، أو تنشر ملفات المحاضرات.

لازم يكون معاك iPhone أو iPad، وسنك ١٨ سنة أو أكبر، وتكون في سنة تانية أو أكبر. Vignette مالوش علاقة رسمية بـ{الجامعة}.

عشان تقدّم: افتح Vignette ← الإعدادات ← المساعدة ← تواصل معانا، وابدأ رسالتك بـ "Ambassador application: {الكلية}". اكتب سنتك، والجروبات اللي إنت نشيط فيها، وحاجة واحدة نفسك تغيّرها في طريقة مذاكرة دفعتك. آخر ميعاد: {التاريخ}.
```

<!-- field: ambassadors/recruit.ar-Gulf.txt -->
```text
يبحث Vignette عن ممثل طلابي واحد في كلية الطب بـ{الجامعة}.

Vignette تطبيق جديد على iPhone وiPad يحوّل محاضراتك إلى أسئلة MCQ بأسلوب الامتحان، وبطاقات مراجعة متباعدة، ومحطات OSCE. التطبيق للدراسة فقط، وليس لاتخاذ قرارات طبية.

المهام (حوالي ساعة ونصف أسبوعياً أثناء الفصل، وأقل قبل الامتحانات، ولا شيء أثناء النهائيات):
• استخدام التطبيق على محاضراتك وإرسال ملاحظاتك
• مراجعة النصوص العربية والإنجليزية
• مساعدة زملائك إذا سألوا عنه

لا يتضمن الدور أي نشر إعلاني على وسائل التواصل الاجتماعي.

المقابل: Vignette Pro مجاناً طوال العام الدراسي، وشهادة وخطاب توصية يصف عملك.

الشروط: جهاز iPhone أو iPad، والعمر ١٨ سنة فأكثر، والدراسة في السنة الثانية أو ما بعدها. Vignette غير مرتبط رسمياً بـ{الجامعة}.

للتقديم: افتح Vignette ← الإعدادات ← المساعدة ← تواصل معنا، وابدأ رسالتك بـ "Ambassador application: {الجامعة}".
```

### 3.4 Selection (about 10 minutes per school for the owner)

1. Shortlist up to three applicants per school from Owner tools → Support.
2. Send each shortlisted applicant the same two questions through the support reply:
   - "A group admin says no app posts. What do you do?" The right answer: respect it, and only answer if someone asks.
   - "A classmate asks if Vignette can replace the department's notes. What do you say?" The right answer: no. It works on your own lectures, and the source is one tap away.
3. Pick one. Keep the runner-up as a backup for the break review.

---

## 4. Roster, offer codes and attribution

### 4.1 Roster

| Slug (`ambassadors.id`) | School | Offer (`offer_ref`) | Custom code, term 1 | Custom code, term 2 | Redemption cap per code | Campaign token (`ct`) |
|---|---|---|---|---|---|---|
| `cairo` | Cairo University, Kasr Al Ainy Faculty of Medicine | `amb-cairo` | `KASR26` | `KASR27` | 300 | `amb-cairo` |
| `ain-shams` | Ain Shams University Faculty of Medicine | `amb-ain-shams` | `AINSHAMS26` | `AINSHAMS27` | 300 | `amb-ain-shams` |
| `alexandria` | Alexandria University Faculty of Medicine | `amb-alexandria` | `ALEXMED26` | `ALEXMED27` | 300 | `amb-alexandria` |
| `mansoura` | Mansoura University Faculty of Medicine | `amb-mansoura` | `MANSOURA26` | `MANSOURA27` | 300 | `amb-mansoura` |
| `assiut` | Assiut University Faculty of Medicine | `amb-assiut` | `ASSIUT26` | `ASSIUT27` | 300 | `amb-assiut` |
| `zagazig` | Zagazig University Faculty of Medicine | `amb-zagazig` | `ZAGAZIG26` | `ZAGAZIG27` | 300 | `amb-zagazig` |
| `tanta` | Tanta University Faculty of Medicine | `amb-tanta` | `TANTA26` | `TANTA27` | 300 | `amb-tanta` |
| `gulf` | *(pool row that carries the shared offer)* | `amb-gulf` | none | none | n/a | n/a |
| `gulf-ksu` … up to 5 reps | e.g. King Saud University, King Abdulaziz University, Imam Abdulrahman Bin Faisal University, UAE University, University of Sharjah, Kuwait University, Qatar University, Sultan Qaboos University, Arabian Gulf University | **none** (`offer_ref` is UNIQUE, so the pool row holds it) | `KSU26` etc. | `KSU27` etc. | 100 | `amb-gulf-ksu` |
| `general` | anyone else (the owner's channels, other schools) | `amb-general` | `VIGNETTE26` | `VIGNETTE27` | 500 | `amb-general` |

**Gulf schools, in order of priority.** Saudi schools come first because iOS has the highest share there: King Saud University, King Abdulaziz University, Imam Abdulrahman Bin Faisal University, Alfaisal University, King Saud bin Abdulaziz University for Health Sciences. After them: UAE University, University of Sharjah, Mohammed Bin Rashid University, Kuwait University, Qatar University, Sultan Qaboos University, Arabian Gulf University. Take the first five good applicants, with no more than one per school.

**Why Gulf reps have no offer of their own.** In `schema/unified-tables.sql`, `ambassadors.offer_ref` is `UNIQUE`, and a transaction carries the offer's *reference name*, never the code a student typed. So the server can only attribute redemptions per offer. Gulf redemptions are therefore counted per rep in App Store Connect (per-code counts), and on the server through each rep's referral link and campaign token. Gulf reps hand out codes only when a friend asks. They never post them (§6.4).

### 4.2 Offer settings (App Store Connect, created by P3.2 through the API)

| Setting | Value |
|---|---|
| Product | `com.redpen.pro.monthly` (group "Vignette Pro") |
| Reference name | `amb-<slug>` as in §4.1 |
| Customer eligibility | **New** and **Expired** (not Existing) |
| Offer | **Free, 1 month** |
| Auto-renew after the offer | **Off**. If the API cannot set this, create it with auto-renew on and flag the difference in the run summary. Ambassadors must then say "renews unless you cancel in Settings" instead of "nothing renews". |
| Combine with introductory offer | No. The intro offer is on the yearly product only. |
| Code type | Custom codes as in §4.1. One-time-use codes are not needed. |
| Redemption cap | as in §4.1, per batch |
| Expiry | "26" codes: **5 Feb 2027**. "27" codes: **31 Jul 2027**. Apple allows up to 6 months from creation, so create the "27" codes on or after 1 Feb 2027. |
| Territories | all |

**Apple facts that change how ambassadors explain the code:**

- **Custom codes are redeemed through a link or inside the app. They cannot be typed into the App Store's own "Redeem Gift Card or Code" screen.** So the instructions are always:
  - tap the link on the ambassador's page (`/a/<slug>`), which opens `https://apps.apple.com/redeem?ctx=offercodes&id=<appStoreId>&code=<CODE>`; or
  - open Vignette → Account → **Redeem code** (P2.3's `RedeemOfferCodeButton`) and type it there.
- Each Apple Account can redeem **one code per offer**. A student who used `KASR26` cannot use `KASR27`, because both belong to `amb-cairo`. That is intended.
- **Deactivating an offer is permanent and invalidates all of its codes.** To replace an ambassador, keep the offer, point the ambassador row at the new person, and create a new custom code. Deactivate the offer only if the code itself has been abused, and then create `amb-<slug>-2`, which uses the spare offer slot.
- Codes can only be *generated* once the app is Ready for Distribution and the product is approved. New codes can take up to an hour to work.
- Apple allows 10 active offers per subscription product. The monthly product uses 9: seven Egyptian schools, `amb-gulf` and `amb-general`. The tenth slot is kept for `billing.licenceOfferCodes` or referral fallbacks (`implementation-plan.md` §7) or for an `-2` replacement. **No other campaign may use a monthly-product offer slot without freeing one first.** Exam-season or win-back offers go on the yearly product.

### 4.3 Seed block for Owner tools and the P3.2 offer queue

P2.5's Owner tools → Ambassadors reads this list, and so does `/owner/ambassadors/upsert` with "create the offer automatically" switched on. `name` and `accountId` are filled in when a person is appointed. They are personal data, so they never go into the repository.

<!-- field: ambassadors/seed.json -->
```json
{
  "product": "com.redpen.pro.monthly",
  "offer": { "mode": "free", "period": "P1M", "eligibility": ["new", "expired"], "autoRenew": false, "stackWithIntro": false },
  "terms": [
    { "id": "2026-t1", "suffix": "26", "expires": "2027-02-05" },
    { "id": "2026-t2", "suffix": "27", "expires": "2027-07-31", "createOnOrAfter": "2027-02-01" }
  ],
  "rows": [
    { "id": "cairo",      "school": "Cairo University (Kasr Al Ainy)",  "offerRef": "amb-cairo",      "codeStem": "KASR",     "cap": 300, "ct": "amb-cairo" },
    { "id": "ain-shams",  "school": "Ain Shams University",             "offerRef": "amb-ain-shams",  "codeStem": "AINSHAMS", "cap": 300, "ct": "amb-ain-shams" },
    { "id": "alexandria", "school": "Alexandria University",            "offerRef": "amb-alexandria", "codeStem": "ALEXMED",  "cap": 300, "ct": "amb-alexandria" },
    { "id": "mansoura",   "school": "Mansoura University",              "offerRef": "amb-mansoura",   "codeStem": "MANSOURA", "cap": 300, "ct": "amb-mansoura" },
    { "id": "assiut",     "school": "Assiut University",                "offerRef": "amb-assiut",     "codeStem": "ASSIUT",   "cap": 300, "ct": "amb-assiut" },
    { "id": "zagazig",    "school": "Zagazig University",               "offerRef": "amb-zagazig",    "codeStem": "ZAGAZIG",  "cap": 300, "ct": "amb-zagazig" },
    { "id": "tanta",      "school": "Tanta University",                 "offerRef": "amb-tanta",      "codeStem": "TANTA",    "cap": 300, "ct": "amb-tanta" },
    { "id": "gulf",       "school": "Gulf schools (pool)",              "offerRef": "amb-gulf",       "codeStem": null,       "cap": 0,   "ct": null },
    { "id": "general",    "school": "General",                          "offerRef": "amb-general",    "codeStem": "VIGNETTE", "cap": 500, "ct": "amb-general" }
  ],
  "gulfReps": { "offerRef": "amb-gulf", "maxReps": 5, "cap": 100, "ctPrefix": "amb-gulf-" }
}
```

### 4.4 Attribution without tracking

| Signal | Where it comes from | What it counts |
|---|---|---|
| Offer redemptions per school | `transaction.offerIdentifier` = `amb-<slug>` → `apple_subscriptions.first_offer_id` → `/owner/ambassadors/stats` | exact, per offer |
| Redemptions per custom code (Gulf reps) | App Store Connect → offer codes | per code, inside App Store Connect |
| Store visits and first downloads per ambassador | App Store **campaign links**: `https://apps.apple.com/app/apple-store/id<appStoreId>?pt=<providerToken>&ct=amb-<slug>&mt=8` | impressions, page views, first downloads within 24 h, subscriptions. A metric appears only once it reaches 5 or more; campaigns appear after 24 h; `ct` is at most 30 characters. |
| Referral rewards | the ambassador account's rows in `referrals` | `referralsRewarded` in the stats |
| Still using it | `activeNow` and `converted` in the stats | counts only |

The owner never sees who redeemed or who was referred, only counts and short hashes (design B §3.4). There are no tracking pixels and no third-party link shorteners. Ambassadors always share the `/a/<slug>` page or their `/r/<code>` link, never a bit.ly-style link.

---

## 5. Running the programme

### 5.1 Onboarding (week 0, about 45 minutes for the ambassador and 10 for the owner)

1. **Owner:**
   - adds the ambassador in Owner tools → Ambassadors (slug, school, and their Vignette account, found from their support message);
   - adds them to the **"Ambassadors 2026/27"** class, which carries an owner-created class-access licence: seats = number of ambassadors + 2, ends **31 Jul 2027**, `paid_models = 0`;
   - their Pro starts at once and runs on free models, so it costs nothing.
2. **Ambassador:**
   - reads and accepts the agreement (§5.4) by replying "I agree" to the support thread (there is no signature to store);
   - enters their faculty's real exam weeks for the year in the same thread;
   - joins the private ambassador team chat.
3. **Ambassador:** joins **TestFlight** from the link in the team chat, so they get builds early (Apple allows up to 10,000 external testers).
4. **Ambassador:** checks their `/a/<slug>` page on their phone:
   - the school name;
   - the code;
   - "Redeem in the App Store";
   - the non-affiliation line (§8.4).
5. **Ambassador:** runs through the app once on their own lecture:
   - generate MCQs;
   - do a card review;
   - open one OSCE station;
   - tap **Check accuracy** once;
   - tap **Report an error** once, on anything that looks off.

**The team chat.** A private Telegram group is recommended, because members do not see each other's phone numbers. It has:
- the owner and the ambassadors, and nobody else;
- a pinned copy of §5.4 and §6;
- the rule that nobody forwards anything from it.

### 5.2 Weekly tasks

| Kind of week | Time | Tasks |
|---|---|---|
| **Teaching week** | ≤ 90 min | **T1 Use** (20 min): run this week's own lecture through one feature you haven't tried. **T2 Feedback** (10 min): one support message starting `[amb-<slug>] week N`, covering what confused you, what broke and what you'd cut. **T3 Accuracy** (15 min): **Check accuracy** on 3 items you studied, and **Report an error** on any that are wrong. **T4 Help** (20 min, spread across the week): answer classmates' questions about the app within 24 h, using §6.3. Forward anything you can't answer to the team chat. **T5 Arabic** (15 min, from P5.7): review 20 Arabic strings in the review list (design F marks them `needs_review`). Until P5.7 lands, note Arabic problems you see in the app in T2. **T6 Post** (optional, 10 min): at most one post in a group where the admin allows it (§6). Never more than one per group per month, including the introduction. |
| **Midterm or module-exam week** | ≤ 20 min | T2 only, plus T4 if someone asks. No posts. |
| **Pre-final revision** (the 2–3 weeks before finals) | ≤ 60 min | T1–T4. Optional: one **help session**, 30 min in person or on a call, where classmates who already use the app bring their own lecture and you show them Due today, OSCE timing and Commute mode. No lecture files are passed around. |
| **Finals** | 0 | Nothing. Study. The weekly message is not expected. |
| **Break** | ≤ 45 min, once | The term review form (§7.2) and a successor note if you are leaving. |

**The weekly check-in** is the T2 support message. Its first line is `[amb-cairo] week 7`, followed by:

```text
Helped: <number of classmates you answered>
Posts: <0 or 1, with the group type, not its name>
Sessions: <0 or 1>
Best thing this week: <one line>
Worst thing this week: <one line>
Arabic issues: <any>
```

The owner reads these in Owner tools → Support. Optionally, a weekly digest can be generated automatically (§10).

### 5.3 Things ambassadors can say about the app

These are true in the App Store build as described in `app-store-listing.md`. Lines marked there as `[ship-gated]` must wait until the feature has shipped.

- It turns *your* lectures into single-best-answer MCQs with an explanation for every option, spaced-repetition cards, OSCE stations and patient cases.
- The free version writes questions on the device, and nothing leaves the phone. There are no ads and no tracking.
- Cloud features ask your permission first and name their providers.
- It exports decks as `.apkg` files and prints sets as PDF. (Say "exports `.apkg` decks". Do not describe it as an alternative to any named app.)
- It has exam tracks for USMLE, PLAB, MRCP(UK) and MRCS, plus General revision for faculty exams.
- Every question has **Check accuracy**. AI can be wrong, and the source is one tap away.

**Never say:**
- "accurate", "verified", "100 %" or "better than [anything]";
- any accuracy number without the `/accuracy` link;
- "use it on the wards" or "for patients";
- "EMLE questions" or "SMLE questions";
- "works on Android";
- "official", "approved by the faculty" or "the doctors recommend it";
- any price.

### 5.4 The ambassador agreement (plain language; accepted by replying "I agree")

<!-- field: ambassadors/agreement.en.txt -->
```text
Vignette student ambassador — 2026/27

1. You're a volunteer, not an employee or agent. You can stop any time by telling us. We can end the role any time.
2. You get: Vignette Pro for the academic year while you're an ambassador; your school's free-month code to give to classmates who ask; your normal invite rewards; an end-of-term gift of up to 90 days of Pro when you've done most weekly tasks; a certificate and a reference letter on request. No cash, and nothing tied to how many people install.
3. Always say you're a Vignette student ambassador and get Pro for free when you talk about the app in a group or post.
4. Never: ask anyone to rate or review Vignette; post an App Store review yourself while an ambassador; message people who didn't ask; add anyone to a group; post where the admins say no; post more than once a month in any group; quote a price; call Vignette "official" or linked to your university; use university or faculty logos.
5. Never share lecture files, slides, recordings or anyone's notes, and never post patient information or photos. Vignette works on each student's own material.
6. Vignette is for studying, not clinical decisions. Say so if anyone asks about using it with patients.
7. Gulf ambassadors: no promotional posts on any social media, because UAE and Saudi rules require a permit or licence for that. Feedback, Arabic/English review and answering friends who ask are fine.
8. Codes are free and must stay free. Selling or trading a code ends the role.
9. We only see counts, never who used your code. Don't collect classmates' names, numbers or emails for us.
10. If you break rules 4, 5 or 8 on purpose, the role ends at once and the Pro from the role stops. Invite rewards you've already earned stay yours.
```

<!-- field: ambassadors/agreement.ar.txt -->
```text
سفير Vignette الطلابي — ٢٠٢٦/٢٠٢٧

١. إنت متطوع، مش موظف ولا وكيل. تقدر توقف في أي وقت وتبلغنا، واحنا كمان نقدر ننهي الدور في أي وقت.
٢. هتاخد: Vignette Pro طول السنة الدراسية طول ما إنت سفير؛ كود الشهر المجاني بتاع كليتك تديه لزمايلك اللي يطلبوه؛ مكافآت الدعوات العادية؛ هدية آخر الترم لحد ٩٠ يوم Pro لو عملت أغلب مهام الأسبوع؛ شهادة وخطاب توصية لو طلبت. مفيش فلوس، ومفيش حاجة مربوطة بعدد اللي نزّلوا التطبيق.
٣. دايماً قول إنك سفير Vignette وبتاخد Pro ببلاش لما تتكلم عن التطبيق في جروب أو بوست.
٤. ممنوع: تطلب من حد يقيّم أو يكتب ريفيو لـ Vignette؛ تكتب ريفيو على App Store بنفسك طول ما إنت سفير؛ تبعت رسايل لناس ما طلبتش؛ تضيف حد لجروب؛ تنشر في جروب الأدمن رافض فيه؛ تنشر أكتر من مرة في الشهر في أي جروب؛ تقول سعر؛ تقول إن Vignette "رسمي" أو ليه علاقة بجامعتك؛ تستخدم لوجو الجامعة أو الكلية.
٥. ممنوع تنشر ملفات محاضرات أو سلايدات أو تسجيلات أو مذكرات حد، وممنوع أي بيانات أو صور مرضى. Vignette بيشتغل على مادة كل طالب بتاعته هو.
٦. Vignette للمذاكرة، مش للقرارات الطبية. قول كده لو حد سأل عن استخدامه مع المرضى.
٧. سفراء الخليج: ممنوع أي بوست ترويجي على السوشيال ميديا، لأن قوانين الإمارات والسعودية بتطلب تصريح أو ترخيص لده. الملاحظات والمراجعة والرد على صحابك اللي يسألوا مسموح.
٨. الأكواد مجانية ولازم تفضل مجانية. بيع أو تبادل كود بينهي الدور.
٩. احنا بنشوف أرقام بس، عمرنا ما بنعرف مين استخدم كودك. ما تجمعش أسامي أو أرقام أو إيميلات زمايلك عشاننا.
١٠. لو كسرت البند ٤ أو ٥ أو ٨ عن قصد، الدور بينتهي فوراً والـ Pro اللي من الدور بيقف. مكافآت الدعوات اللي كسبتها قبل كده بتفضل ليك.
```

---

## 6. Telegram and WhatsApp group playbook

### 6.1 The rules underneath

- **WhatsApp** forbids "repeated unwanted contact" and bulk or automated messaging, and it can suspend accounts or revoke invite links. Groups hold up to 1,024 members. Communities hold up to 2,000 people in total, and only admins post in their announcement group. Channels are one-way.
- **Telegram** forbids using the service "to send spam or scam users". Admins who run giveaways are responsible for following the law. **Vignette runs no giveaways and no contests** (this also keeps it clear of Guideline 5.3).
- **Egypt's Law 151/2020**: unsolicited electronic marketing needs prior consent, and from 1 Nov 2026 it also needs a licence. So: **no DMs to people who did not ask, no contact lists, no broadcast lists.**
- **Each group's own rules win.** Many batch groups ban ads, and official faculty groups are announcement-only.

### 6.2 What to do by group type

| Group type | Default | What an ambassador may do |
|---|---|---|
| **Official faculty or department announcement group or channel** | Never post. | Nothing. Do not ask the admin. |
| **Batch group** (دفعة) run by students | Ask the admins first. | With the admins' written OK: one introduction post (§6.3 P1) that term, then only answer when asked. Use the "apps" or "resources" topic if the group has topics. Respect slow mode. Never pin, @all, or mention everyone. |
| **Subject or study-resources channel** (lecture recordings, notes) | Ask the admins first. | With their OK: one post in the pre-final revision window (P2). Never ask them to host Vignette sets, and never post lecture files. |
| **Student club** (scientific society, activities) | Use their process. | A help session (§5.2), if the club runs sessions. The club announces it, not the ambassador. |
| **Small circle of friends** (fewer than about 20 people, who all know you) | Normal conversation. | Mention it naturally with the disclosure line. No template blasts. |
| **Group where you're an admin** | You still need a second admin's OK. | The same as a batch group. Label the post as coming from an ambassador. |
| **Any group in the Gulf** | Do not post. | Answer only when someone asks for an app recommendation (P3–P6). No promotional posts at all (§6.4). |

**If an admin says no,** reply "No problem, thanks", and never post there. If someone in that group later asks about study apps, answer in the thread with the disclosure line, or offer to reply privately **only if they ask you to**.

**If a post is removed,** do not repost it. Note it in the weekly check-in.

**Before any post,** check the exam calendar. There are no posts during midterm or module weeks or during finals.

### 6.3 Message bank

Every promotional post ends with the disclosure line. Answers to questions include it the first time in each thread.

<!-- field: ambassadors/posts.en.txt -->
```text
P1 — Introduction (once per group per term, only with the admins' OK)
Admins OK'd this one post. If you revise on an iPhone or iPad: Vignette turns your own lecture into exam-style MCQs with an explanation for every option, spaced-repetition cards and OSCE stations. The free version runs on the phone and nothing leaves it. For studying, not clinical decisions. Our faculty's free-month code and how to redeem it: {https://…/a/slug}. iPhone and iPad only, sorry Android friends.
(I'm a Vignette student ambassador — I get Pro for free.)

P2 — Revision-window post (pre-finals only, with the admins' OK)
Revision tip that works for me: after each lecture, do 10 questions on it the same day, then only the ones you got wrong two days later. I use Vignette on iPhone for this (it writes the questions from the lecture and brings back the misses). Free-month code for our faculty: {https://…/a/slug}. For studying, not clinical decisions.
(I'm a Vignette student ambassador — I get Pro for free.)

P3 — "Does it work on Android?"
No, only iPhone and iPad for now.

P4 — "Is it free? How much is Pro?"
The free version works on the phone with no account. Pro is a subscription; the App Store shows your local price before you pay. Our faculty's code gives one free month, and nothing renews unless you choose. It redeems from the link or in Vignette → Account → Redeem code (not in the App Store's gift-card screen).

P5 — "Is it accurate? Can I trust it?"
It's AI, so it can be wrong. Every question has "Check accuracy", which compares it with your lecture pages, and "Report an error". Use it to revise your own lectures, not as a source of truth, and never for patient decisions. The method and numbers are at {https://…/accuracy}.

P6 — "Can you send me Dr X's lecture / the Vignette questions for it?"
I can't share lecture files. Everyone uses their own copy: add it in Vignette and it writes the questions for you.
```

<!-- field: ambassadors/posts.ar-EG.txt -->
```text
P1 — تعريف (مرة واحدة في الترم لكل جروب، وبعد موافقة الأدمنز بس)
الأدمنز وافقوا على البوست ده. لو بتذاكر على iPhone أو iPad: Vignette بيحوّل محاضرتك إنت لأسئلة MCQ بستايل الامتحان مع شرح لكل اختيار، وكروت مراجعة متباعدة، ومحطات OSCE. النسخة المجانية شغالة على الموبايل وولا حاجة بتطلع منه. للمذاكرة بس، مش للقرارات الطبية. كود الشهر المجاني لكليتنا وطريقة استخدامه: {https://…/a/slug}. iPhone وiPad بس، معلش يا جماعة الأندرويد.
(أنا سفير Vignette في الكلية وباخد Pro ببلاش.)

P2 — بوست فترة المراجعة (قبل الفاينال بس، وبعد موافقة الأدمنز)
نصيحة مراجعة نفعتني: بعد كل محاضرة حل عليها ١٠ أسئلة في نفس اليوم، وبعد يومين حل اللي غلطت فيهم بس. أنا بستخدم Vignette على الـ iPhone للموضوع ده (بيكتب الأسئلة من المحاضرة وبيرجّعلك اللي غلطت فيه). كود شهر مجاني لكليتنا: {https://…/a/slug}. للمذاكرة بس، مش للقرارات الطبية.
(أنا سفير Vignette في الكلية وباخد Pro ببلاش.)

P3 — "شغال على أندرويد؟"
لأ، iPhone وiPad بس دلوقتي.

P4 — "ببلاش؟ الـ Pro بكام؟"
النسخة المجانية شغالة على الموبايل من غير أكونت. الـ Pro اشتراك، والـ App Store بيعرضلك السعر بعملتك قبل ما تدفع. كود كليتنا بيدي شهر مجاني، ومفيش تجديد إلا لو إنت اخترت. بيتفعّل من اللينك أو من Vignette ← الحساب ← Redeem code (مش من شاشة كروت الهدايا في App Store).

P5 — "دقيق؟ أقدر أثق فيه؟"
ده ذكاء اصطناعي فممكن يغلط. كل سؤال فيه "Check accuracy" بيقارنه بصفحات محاضرتك، وفيه "Report an error". استخدمه تراجع بيه محاضراتك، مش كمرجع نهائي، وعمره ما يكون لقرارات مع مرضى. الطريقة والأرقام هنا: {https://…/accuracy}.

P6 — "ابعتلي محاضرة دكتور فلان / أسئلة Vignette بتاعتها"
مقدرش أبعت ملفات محاضرات. كل واحد بيستخدم نسخته: ضيفها في Vignette وهو يكتبلك الأسئلة.
```

<!-- field: ambassadors/posts.ar-Gulf.txt -->
```text
(للرد فقط عند السؤال — لا منشورات ترويجية)
P3 — لا، التطبيق متاح على iPhone وiPad فقط حالياً.
P4 — النسخة المجانية تعمل على الجهاز بدون حساب. Pro اشتراك، ويعرض App Store السعر بعملتك قبل الدفع.
P5 — هو ذكاء اصطناعي وقد يخطئ. في كل سؤال زر "Check accuracy" للمقارنة مع صفحات محاضرتك، وزر "Report an error". للدراسة فقط وليس لقرارات مع مرضى. التفاصيل: {https://…/accuracy}
P6 — لا أستطيع مشاركة ملفات المحاضرات. كل طالب يضيف نسخته في Vignette ويكتب له الأسئلة.
(أنا ممثل طلابي لـ Vignette وأحصل على Pro مجاناً.)
```

### 6.4 Short videos and personal accounts

- **Egypt.** Posting on your own TikTok, Instagram or YouTube is optional, and only with the platform's disclosure switched on: TikTok's "Disclose commercial content" toggle, Instagram's Paid partnership label. Add `#ad` / `#إعلان`. Free Pro counts as "something of value" on both platforms. Use the ready reels from `reels.md`, which have no prices, no dates and no challenges. Accounts used for this should stay under 5,000 followers (§3.1).
- **UAE.** Since 1 Feb 2026, promotional content from inside the UAE, **paid or unpaid**, needs an Advertiser Permit from the UAE Media Council. The permit is free for the first three years, but fines run from AED 5,000 upward. **Gulf reps do not post.**
- **Saudi Arabia.** The Mawthooq licence covers advertising on social media, and "sponsorship is considered an advertisement". **Gulf reps do not post.**
- **Everywhere.** No stitched or dueted "who scores higher" formats, no "tag a friend" prompts, and no leaderboard screenshots presented as a competition.

This is a practical reading of public sources, not legal advice. When in doubt, don't post.

---

## 7. Rewards

### 7.1 The ladder (none of it costs the owner money)

| Reward | Mechanism | Who | Limit | Cost |
|---|---|---|---|---|
| Pro while an ambassador | Class access: the "Ambassadors 2026/27" licence, `paid_models = 0`, ends 31 Jul 2027 | ambassador | one seat each | none (free models) |
| Free month for classmates | The school's **offer code** (§4) | classmates who ask; new and expired subscribers | 1 per Apple Account per offer; 300 per code per term | none from the owner (Apple fulfils it). Cloud use during the free month must stay on free models (see §11, gap 1). |
| Invite credits | Normal **referral** programme (§8): 30 days per friend who returns | ambassador (like any user) | 3 a month, 12 a year | none (free models) |
| Invite credits banked | Because the licence already gives the ambassador Pro, their referral months are **banked** and start when the role ends. They lapse after 12 months (`bankedCreditDays` 365). | ambassador | as above | none |
| End-of-term gift | `/owner/grants/gift`, up to 90 days | ambassadors who sent at least 70 % of the weekly check-ins in teaching weeks | at most 20 gifts a month in total (`giftsPerMonth`) | none |
| Early builds | TestFlight external group | ambassador | n/a | none |
| Certificate | A PDF: "Vignette Student Ambassador, {school}, 2026/27". It lists the weeks active, feedback items, Arabic strings reviewed and help sessions. | ambassadors active for at least one full term | n/a | none |
| Reference letter | A short factual letter from the owner describing the work. Agents draft it from the check-ins, and the owner reads and signs it. | on request, at least one full term | n/a | about 10 min of owner time |

**Not offered:** cash, commissions, per-install or per-redemption bonuses, prizes for rank, raffles and giveaways, gift cards, or "top ambassador" competitions. The last two are contests (5.3) and would push ambassadors towards spam.

### 7.2 Term review (in the break, about 20 minutes for the owner in total)

1. Agents compile, per ambassador:
   - the check-ins sent;
   - the feedback items and error reports tagged with their slug;
   - the stats from `/owner/ambassadors/stats`.
2. The owner ticks one box per person: **keep**, **keep with a note**, or **replace with runner-up**.
3. Gifts go out through Owner tools → Gift to those who qualify.
4. P3.2 creates the "27" custom codes from the seed (§4.3).

---

## 8. Referral programme

### 8.1 Mechanics, mapped to the config

| Rule | Config key (`config-defaults.json`) | Value |
|---|---|---|
| Programme on or off | `flags.billing.referrals` | on |
| Days of Pro for the new friend (a welcome grant) | `referralRefereeDays` | 7 |
| Days of Pro for the inviter | `referralRewardDays` | 30 |
| The friend must claim within this many days of creating their account | `referralClaimWindowDays` | 7 |
| Hold before the inviter's reward | `referralHoldHours` | 72 |
| The friend must also come back on a later day | built into `settleReferrals` (`last_seen_day > claim_day`) | n/a |
| Cap per inviter per calendar month | `referralMaxPerMonth` | 3 |
| Cap per inviter per rolling year | `referralMaxPerYear` | 12 |
| Claims per hour per network (hashed IP key) | `referralClaimsPerHour` | 3 |
| Banked credit lapses after | `bankedCreditDays` | 365 |
| Code format | 7 characters from the `pair.js` alphabet | e.g. `K7M2Q9X` |
| One referral per Apple Account, ever | `referrals.app_transaction_id UNIQUE` | survives account deletion, with the ids nulled |
| Pending referrals that never qualify | void after 30 days, reason `inactive` | n/a |

**Edge cases** (the app's copy must match these):

- **Already subscribed.** The inviter's month is banked and starts when the paid subscription ends.
- **The friend also used a school code.** The friend's 7 days are banked behind the free month. Both work, and they don't stack at the same time.
- **Swift Playgrounds build.** The claim fails with `not_eligible`, and the app says "Invites work in the App Store version". Showing your own code still works.
- **Family Sharing** is off, so one Apple Account means one person.
- **Account deletion.** The deleted person's pending referrals are voided. Rewards already earned by the other side stay.

### 8.2 Rules shown in the app (InviteFriendsView) and on the terms page

<!-- field: referrals/rules.en.txt -->
```text
Invite friends
• Share your code or link. A friend who is new to Vignette and enters it within 7 days of starting gets 7 days of Pro.
• When they come back on another day (and at least 72 hours have passed), you get 1 free month of Pro.
• Up to 3 rewards a month and 12 a year. One reward per Apple Account, ever. Your own accounts don't count.
• If you already have Pro, your free month waits and starts when your current Pro ends. Unused months lapse after 12 months.
• Months from invites unlock the same Pro features. Cloud features follow the fair-use limits shown in the app.
• No cash value; not transferable. We never ask for ratings or reviews, and inviting is never required to use Vignette.
• Invites work in the App Store version of Vignette. Abuse, such as fake accounts, voids rewards.
```

<!-- field: referrals/rules.ar.txt -->
```text
ادعُ أصدقاءك
• شارك الكود أو الرابط. الصديق الجديد على Vignette الذي يُدخله خلال ٧ أيام من بدايته يحصل على ٧ أيام من Pro.
• عندما يعود في يوم آخر (وبعد مرور ٧٢ ساعة على الأقل)، تحصل على شهر Pro مجاني.
• حتى ٣ مكافآت في الشهر و١٢ في السنة. مكافأة واحدة لكل Apple Account مدى الحياة. حساباتك الأخرى لا تُحتسب.
• إذا كان لديك Pro بالفعل، ينتظر شهرك المجاني ويبدأ عند انتهاء Pro الحالي. الأشهر غير المستخدمة تنتهي بعد ١٢ شهراً.
• أشهر الدعوات تفتح مزايا Pro نفسها. الميزات السحابية تتبع حدود الاستخدام العادل الظاهرة في التطبيق.
• بلا قيمة نقدية وغير قابلة للتحويل. لا نطلب أبداً تقييماً أو مراجعة، والدعوة ليست شرطاً لاستخدام Vignette.
• الدعوات تعمل في نسخة App Store من Vignette. إساءة الاستخدام، مثل الحسابات الوهمية، تُلغي المكافآت.
```

### 8.3 The share message (`ShareLink(message:)` in InviteFriendsView)

This is plain and personal, with no challenge and no urgency.

<!-- field: referrals/share.en.txt -->
```text
I revise with Vignette on iPhone: it turns lectures into MCQs, cards and OSCE stations. With my code you get 7 days of Pro: {link}
```

<!-- field: referrals/share.ar.txt -->
```text
بذاكر بـ Vignette على الـ iPhone: بيحوّل المحاضرات لأسئلة MCQ وكروت ومحطات OSCE. بالكود بتاعي هتاخد ٧ أيام Pro: {link}
```

### 8.4 Text for the `/a/<slug>` page (P1.4, `invitepage.js`)

The page never names the ambassador (their name is personal data and is not needed). It never shows a price.

<!-- field: ambassadors/page.en.txt -->
```text
Vignette at {School}
Your faculty's student ambassador code: {CODE}
One free month of Vignette Pro for new and returning subscribers. Nothing renews unless you choose.
[Redeem in the App Store]
Or open Vignette → Account → Redeem code and type {CODE}.
iPhone and iPad only. For studying, not clinical decisions.
Vignette is not affiliated with or endorsed by {University}.
```

<!-- field: ambassadors/page.ar.txt -->
```text
Vignette في {الكلية}
كود سفير كليتك: {CODE}
شهر مجاني من Vignette Pro للمشتركين الجدد والعائدين. لا يتجدد إلا إذا اخترت ذلك.
[استخدم الكود في App Store]
أو افتح Vignette ← الحساب ← Redeem code واكتب {CODE}.
iPhone وiPad فقط. للدراسة، وليس لاتخاذ قرارات طبية.
Vignette غير تابع لـ{الجامعة} ولا تعتمده.
```

If the offer was created with auto-renew **on** (§4.2 fallback), replace "Nothing renews unless you choose." with "Renews at the price shown in the App Store unless you cancel in Settings." and use the matching Arabic: «يتجدد بالسعر الظاهر في App Store ما لم تلغِه من الإعدادات».

### 8.5 The line for App Review (P6.1 → `review-notes.txt`)

<!-- field: referrals/review-note.en.txt -->
```text
Invite friends: a friend who is new to Vignette and enters an invite code within 7 days gets 7 days of Pro; the inviter gets 1 free month after the friend returns on another day (72-hour hold), capped at 3 per month and 12 per year, one reward per Apple Account (checked with a verified AppTransaction). There is no cash value, inviting is never required, and ratings or reviews are never requested. Student ambassadors hand out Apple offer codes (free month) created in App Store Connect; they are volunteers rewarded with Pro time, never per install, and their agreement forbids requesting or writing reviews.
```

---

## 9. Anti-abuse

### 9.1 Referral abuse

| Threat | Control already in P1.4 | Signal to watch | Response |
|---|---|---|---|
| Self-referral with a second account on the same Apple Account | Referrer and referee `app_transaction_id` must differ (409 `self_referral`) | n/a | automatic |
| Self-referral with a second Apple Account and device | 72 h hold, the "return on a later day" rule, and caps of 3 a month and 12 a year | the same referrer hitting the monthly cap three months running, with referees who never come back after the reward | Nothing to do: the maximum gain is 12 free-model months a year. If the pattern is blatant, void the pending rows (owner tool) and give no gift. |
| Code dumped on coupon sites | caps, one reward per Apple Account | many `capped` rows for one referrer | Nothing to do (the caps absorb it). If needed, rotate the code (§11, gap 5). |
| Scripted claims | 3 claims per hour per IP key, claims only inside the App Store build (verified AppTransaction), 7-day window | spikes of `bad_code` | automatic (rate limit) |
| Farming Pro time to resell | not transferable, attached to an account | n/a | the terms forbid it; void rewards |
| Emulators and sideloading | AppTransaction must verify for the bundle and the environment | 422 `not_eligible` counts | automatic |
| Cost to the owner | Referral and welcome Pro run on free models only (`wallet()` returns null) | n/a | no money at risk |
| Kill switch | `flags.billing.referrals` in remote config (the owner console) | n/a | turn it off. Existing credits are honoured. |

### 9.2 Ambassador abuse

| Threat | Prevention | Detection | Response |
|---|---|---|---|
| Spam: many posts, unsolicited DMs, adding people to groups | the agreement (§5.4), the playbook (§6), rewards that do not depend on installs | complaints through `/support` or the team chat; a post count in the check-ins that doesn't match reality | step 1, then step 2 of the ladder below |
| Asking for reviews or ratings, or writing incentivised reviews | the agreement, rule 4 | App Store reviews that mention codes or ambassadors (read weekly by agents from the App Store Connect API or the public reviews RSS) | step 3, at once |
| Selling codes | codes are public and free; the redemption cap per code | the code appears on marketplaces | step 3, plus a new custom code for that school |
| Fake "ambassadors" | the only real list is the set of live `/a/<slug>` pages, and a page exists only while `active = 1` | complaints | answer with the real page link |
| Misrepresentation ("official", "for patients", accuracy claims, prices) | §5.3 | complaints, spot checks | step 2, then step 3 |
| Sharing lecture files, patient information or photos | rule 5 | reports | step 3; also a moderation report if it happened inside Vignette shares (`/moderation/report`) |
| Posting in the Gulf without a permit or licence | rule 7 | spot checks | ask them to delete it; step 2 |
| Collecting classmates' personal data | rule 9 | check-ins that mention "lists" | step 2; they delete the data |
| Farming accounts to inflate numbers | nothing is rewarded per install; the stats are counts only | redemptions with near-zero `activeNow` after 14 days | a conversation; no reward is lost because none depends on it |

**Ladder:**

1. A private note in the team chat.
2. A written warning by support reply, and the post removed.
3. The role ends:
   - their seat comes off the licence (`/owner/licences/remove-seat`);
   - the ambassador row is set to `active = 0`, which takes the page down;
   - the successor keeps the school's offer with a new custom code (§4.2).

Referral rewards already earned stay. Removing earned rewards needs evidence of fake accounts.

### 9.3 Code hygiene

- A redemption cap on every custom code (§4.1). Raise it only by adding another batch (for example `KASR26B`), never by removing the cap.
- Every code has an expiry (§4.2), so a leaked code dies with the term.
- One redemption per Apple Account per offer, across terms.
- An offer is deactivated only for a compromised code, and then replaced with `amb-<slug>-2` in the spare slot.
- Ambassadors share the `/a/<slug>` page, not the bare code, so the non-affiliation and no-renewal lines always travel with it.

---

## 10. Measuring it (owner time: about 10 minutes a week)

| Metric | Source | Starting target per Egyptian school per term (a guess; recalibrate after 4 weeks) |
|---|---|---|
| Offer redemptions | `/owner/ambassadors/stats` → `redemptions` | 40 |
| Still using the app 14 days later | `activeNow` | 50 % of redemptions |
| Converted to paid | `converted` | Watch only; no target until there are 2 terms of data |
| Referral rewards through the ambassador | `referralsRewarded` | Watch only |
| Weekly check-ins sent | Owner tools → Support, tagged `[amb-<slug>]` | at least 70 % of teaching weeks |
| Feedback items that led to a fix | the team chat and commits | 2 or more |
| Arabic strings reviewed (after P5.7) | the review list | 20 a teaching week |
| Complaints about spam | `/support` | 0 |

The Gulf target is 15 redemptions per rep per term, with feedback weighted more heavily than redemptions.

**The weekly digest (optional, built by agents, with no owner step).** A scheduled workflow such as `ambassador-digest.yml` can derive `OWNER_KEY` the same way `worker-deploy.yml` does. It would call `/owner/ambassadors/stats` and `/owner/support/list`, then write a one-screen summary to the workflow run's step summary:

- counts per school;
- which ambassadors missed their check-in;
- any support messages that mention spam.

The owner reads it in the GitHub app. It is not in `package-files.tsv` yet, so add it as a small package after P1.4 and P1.8.

---

## 11. Gaps found while writing this (hand these to the named packages)

1. **Free offer months can reach paid models (P1.3 and P1.5).** `implementation-plan.md` defines `paying` as "an active Production subscription or pass". A free offer-code month, and the 1-week intro trial, are active Production subscriptions at price 0. When `PRO_PAYS` is switched on later, those students would spend owner money.
   - **Fix:** treat a transaction whose `offerDiscountType` is `FREE_TRIAL`, or whose `price` is 0, as `paying: false` until the first paid renewal (`converted_at`).
   - This matters less while `PRO_PAYS` is off, but it must land before it is switched on.
2. **Gulf reps and the `UNIQUE offer_ref` column (P1.4 and P2.5).** Several reps share `amb-gulf`, so only the pool row may carry `offer_ref`. Owner tools must allow `offerRef` to be empty. `/owner/ambassadors/stats` should show the pool row's redemptions under "Gulf (all reps)".
3. **Custom codes are not accepted by the App Store's own redeem screen (P2.3 and P1.4).** The in-app **Redeem code** button and the `/a/` page's redemption link are the only ways in. Both must exist before ambassadors start. The paywall and Account copy should say "Have a code from your faculty? Redeem it here."
4. **Campaign links (P1.4).** `/a/<slug>`'s App Store link should carry `pt=<providerToken>&ct=amb-<slug>&mt=8`. `providerToken` is a public value shown in App Store Connect → App Analytics. Store it in remote config (`appStore.providerToken`) so no code change is needed.
5. **Referral code rotation (P1.4, optional).** There is no route to rotate a user's own referral code. Add `POST /referrals/rotate` (at most once a month), which keeps past rows attributed.
6. **The `/a/` page's non-affiliation line (P1.4).** Add the §8.4 text, including "not affiliated with or endorsed by {University}". Add a `university` field to the ambassador row, or derive it from `school`.
7. **Support subject filter (P2.5 and P1.8).** Owner tools → Support should filter messages whose first line starts with `[amb-` or `Ambassador application:`, so check-ins and applications do not bury real support.
8. **EMLE and SMLE tracks (product idea, not in the plan).** Both are large MCQ exams for this audience: EMLE is 100 questions in 3 hours, and SMLE is computer-based. A track would need each exam's blueprint (SCFHS publishes an SMLE blueprint) and must not claim affiliation. Until one exists, ambassadors must not mention either exam as supported.

---

## 12. Owner's steps for this programme

**App Store Connect** (the unavoidable part, done at or after launch). If P3.2's automation works, nothing here is extra. The owner steps in `implementation-plan.md` §6 already cover the agreement, the products and the first submission. Only in these cases:

1. **If the API refuses to create an offer or a custom code** (the run summary names it): App Store Connect → the app → Subscriptions → Vignette Pro → Monthly → Offer Codes → Create. Use the §4.2 settings and the §4.1 name and code. About 3 minutes per school.
2. **If the API cannot set "auto-renew off"**, decide whether to keep auto-renew on. If so, tell the agents, and they switch the page and post copy (§8.4).
3. **Optional:** copy the campaign **provider token** from App Store Connect → App Analytics → Campaigns → Generate link, into Owner tools → Config → `appStore.providerToken`. This is a public value, not a secret.

**Human-only work that cannot be automated:**

| When | What | Time |
|---|---|---|
| Recruitment (October) | Read applications, ask the two questions, pick one per school, add them in Owner tools and to the Ambassadors class | about 10 min per school |
| Each week in term | Read the digest or check-ins, reply in the team chat | about 10–20 min |
| Each break | Keep or replace, gift, and sign the reference letters that were asked for | about 20 min + 10 min per letter |

No keys, tokens or personal details go into this file, the repository or chat. Ambassadors' names and accounts live only in D1, entered through Owner tools.

---

## Sources

- Apple, App Review Guidelines (3.1.1, 3.1.2(a), 3.2.2, 4.5.4, 5.1.1, 5.3, 5.6.3): https://developer.apple.com/app-store/review/guidelines/
- Apple, set up subscription offer codes (eligibility, custom codes up to 64 characters, 10 active offers per SKU, 1M codes per quarter, 6-month expiry, auto-renew option, redemption methods, up to 1 hour to activate, Ready for Sale requirement): https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes
- Apple, create offer codes for in-app purchases (non-renewing subscriptions supported; iOS 16.3+ for in-app redemption): https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases
- Apple, implementing offer codes in your app: https://developer.apple.com/documentation/storekit/implementing-offer-codes-in-your-app
- RevenueCat, offer code redemption URL format: https://www.revenuecat.com/blog/engineering/create-and-track-offer-codes-ios-app
- Appbot, Apple offer codes guide: https://appbot.co/blog/apple-offer-code/
- Apple, App Analytics campaign links (pt/ct/mt, `ct` up to 30 characters, 5-user threshold, 24 h delay): https://developer.apple.com/help/app-store-connect/view-app-analytics/manage-campaigns/
- Apple, payment methods for an Apple Account by country (Egypt: Vodafone billing; Gulf carriers): https://support.apple.com/en-us/111741
- Apple Server Library, `JWSTransactionDecodedPayload` (`offerDiscountType`, `price`, `offerType`): https://apple.github.io/app-store-server-library-node/interfaces/JWSTransactionDecodedPayload.html
- Apple Developer Forums, identifying free-trial transactions: https://developer.apple.com/forums/thread/732203
- iMore, the 2021 guideline update adding "referrals" to discovery fraud: https://www.imore.com/apple-aims-prevent-fraud-and-scams-its-latest-app-store-review-guidelines
- StatCounter, mobile OS share, Egypt: https://gs.statcounter.com/os-market-share/mobile/egypt · Saudi Arabia: https://gs.statcounter.com/os-market-share/mobile/saudi-arabia · UAE: https://gs.statcounter.com/os-market-share/mobile/united-arab-emirates
- Youm7, the Supreme Council of Universities' 2026/27 calendar (term 1 starts 19 Sep 2026; finals 2–21 Jan 2027; break to 4 Feb): https://www.youm7.com/story/2026/5/28/تعرف-على-موعد-الدراسة-فى-الجامعات-العام-الجديد-2026-2027/7431053
- Khalf El Hadth, the 2026/27 calendar's term 2 (starts 6 Feb 2027; midterms late Mar to early Apr; teaching ends 20 May; finals May–June): https://khalfelhadth.com/136900
- Wikipedia, the Egyptian Medical Licensing Examination (held in February and September): https://en.wikipedia.org/wiki/Egyptian_Medical_Licensing_Examination · ExamCure, EMLE format (100 MCQs, 3 hours): https://www.examcure.com/egypt-healthcare-exams
- Apple, TestFlight (up to 10,000 external testers through a public link): https://developer.apple.com/testflight/
- SCFHS, professional licensure exam dates (2026 windows): https://scfhs.org.sa/en/Mumares/SPLE/DATES · SMLE blueprint 2026: https://scfhs.org.sa/sites/default/files/2026-05/Saudi%20Medical%20Licensure%20Examination%20(SMLE)%20Blueprint_2026_0.pdf
- CanadaQBank, SMLE testing windows in 2026: https://www.canadaqbank.com/blog/2025/12/15/smle-exam-dates-2026-scheduling-eligibility-preparation-guide/
- The Saudi Electronic University's 1448 academic calendar: https://seu.edu.sa/en/academic-calendar/1448/ · Mdares, the start of the 1448 year: https://mdares.ai/sa-en/calendar/events/academic-year-start-1448
- WhatsApp Messaging Guidelines (no bulk or automated messaging, no repeated unwanted contact; enforcement): https://www.whatsapp.com/legal/messaging-guidelines
- WhatsApp group and community limits: https://gsmarena.com/whatsapp_unveils_communities_feature_raises_group_limit_to_1024_participants-news-56392.php · https://inviter.co/blog/whatsapp-community-member-limit · WhatsApp Channels: https://www.whatsapp.com/channels
- Telegram Terms of Service (no spam or scams; giveaway responsibility): https://telegram.org/tos
- Middle East Briefing, the UAE Advertiser Permit from 1 Feb 2026 (paid and unpaid; fines): https://www.middleeastbriefing.com/news/uae-influencers-must-obtain-advertiser-permit-under-new-media-law/ · Gulf News: https://gulfnews.com/uae/new-uae-law-advertiser-permit-now-mandatory-for-influencers-and-creators-for-social-media-1.500427938
- Saudipedia, the Mawthooq licence (sponsorship counts as advertising): https://saudipedia.com/en/what-is-the-mawthooq-license · Arab News: https://www.arabnews.com/node/2176661/media
- ITIF, Egypt's content regulation (Law 180/2018, the 5,000-follower threshold): https://itif.org/publications/2025/06/09/egypt-content-moderation-regulation/
- Egypt's Law 151/2020 executive regulations (direct electronic marketing, compliance by Nov 2026): https://www.tamimi.com/law_update_articles/from-policy-to-practice-egypt-issues-executive-regulations-of-the-personal-data-protection-law/ · https://www.kennedyslaw.com/en/thought-leadership/article/2026/egypt-s-personal-data-protection-law-the-compliance-countdown-has-begun/
- TikTok, the commercial content disclosure setting: https://ads.tiktok.com/help/article/about-the-content-disclosure-setting-for-creators · the Branded Content Policy: https://www.tiktok.com/legal/page/global/bc-policy/en
- Instagram, the Paid partnership label: https://help.instagram.com/1109894795810258 · the Branded Content Policies: https://help.instagram.com/1695974997209192
- Internal: `docs/launch/designs/B-monetisation.md` §3.3, §3.4, §7 and §8; `docs/launch/implementation-plan.md` §0, P1.4, §6 and §7; `docs/launch/config-defaults.json`; `docs/launch/schema/unified-tables.sql`; `docs/launch/app-store-listing.md`; `docs/launch/reels.md`; `ios/RedPen/Shared/ExamTrack.swift`.
