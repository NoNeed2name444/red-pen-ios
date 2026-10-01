# Vignette pricing plan

Written 2026-09-24 against `preview/graph` at `effa18d`. This is one of the group G launch documents listed in [`implementation-plan.md`](implementation-plan.md). Package **P6.1** turns §5 of this file into `docs/launch/pricing.json`. Where this file and design B §8 disagree, **this file wins**, as the plan says. Prices never appear in App Store metadata (guideline 2.3.7). They appear only on the paywall, which reads them from StoreKit.

Exchange rates used for the arithmetic, from the week of 15–24 Sep 2026: 1 USD = 52.13 EGP = 95.98 INR = 277.1 PKR = 3.75 SAR = 3.6725 AED; 1 GBP = 1.3228 USD. Every "net" figure below means after the tax included in the price and after Apple's 15% commission (Small Business Program).

---

## 1. Decisions at a glance

| Question | Decision |
|---|---|
| What is free | Everything that runs on the phone or iPad and costs the owner nothing per use: on-device question writing (Apple's model), cards and spaced repetition, OSCE practice, analytics, on-device transcription, exports, share links and classes within the plan's limits. **Also PDF, Word and PowerPoint import** (a change, see §3). |
| What is Pro | Everything that costs money per use: Vignette Cloud (writing, checking, background jobs), cloud transcription, the natural voice, and sync. Also two premium on-device perks with no running cost: the medical models on the device (Doctor-R1, MedVAL) and occlusion cards made from labelled diagrams. |
| Products | `com.redpen.pro.monthly`, `com.redpen.pro.yearly` (auto-renewing, one group "Vignette Pro", level 1) and `com.redpen.pass.exam3m`, a non-renewing 3-month Exam Pass (92 days, stacks). |
| US base prices | $4.99 a month, $34.99 a year, $12.99 for the Exam Pass. |
| Trial | 1 week free, on the yearly plan only, in every storefront. None on monthly or on the pass. Trial users get the free models only, so a trial costs the owner $0. |
| Regional prices | See §5: Egypt EGP 99 / 699 / 249; Gulf around the US level; UK £4.99 / £29.99 / £10.99; India ₹199 / ₹1,299 / ₹499; Pakistan Rs 550 / 3,600 / 1,400. |
| UK, EEA, Switzerland | App available. **Subscriptions and pass not offered there** until paid Gemini is switched on (`PRO_PAYS=on`), because Google's terms forbid serving users there from the free Gemini quota (§6). |
| Exam season | List prices never go up. Seasons are handled with offer codes, win-back offers and the pass (§8). |
| Group licences | "Class access", created by the owner. At launch they are used only for free pilots with free models (cost $0). A paid price list is ready for when a school asks (§9). |
| Break-even | The one fixed cost is Apple's $99 a year. Covering it takes 4 US or Gulf annual subscribers, 10 Egyptian ones, or about 5 at the expected mix (§10). |
| Owner's money at risk | None before `PRO_PAYS=on`. After that, only once the four fixes in §11 are in (the most urgent: `GEMINI_PRICES` in `wrangler.toml` understates Gemini 3.5 Flash by 5 times). |

---

## 2. What each feature costs to run

Sources: `server/ai.js`, `server/tts.js`, `server/jobs.js`, `server/sync.js`, `server/wrangler.toml`, `ios/RedPen/Shared/LLM/MedicalGenerate.swift`, `HostedLLMClient.swift` (`promptBudgetChars` = 40,000), plus the current price pages cited in §14.

### 2.1 Limits the server already enforces per Pro account

| Limit | Value | Where |
|---|---|---|
| Cloud chat requests | 400 a day (`AI_DAILY_LIMIT`; owner 3,000) | `ai.js` `chat()` |
| Largest prompt / largest reply | 60,000 characters / 2,000 tokens (a job step can ask for up to 8,000) | `ai.js`, `jobs.js` `checkSpec` |
| Cloud transcription | 36 ten-minute chunks a day, about 6 hours (`TRANSCRIBE_DAILY`) | `ai.js` `transcribeChunk` |
| Natural voice | 300 lines a day, at most 1,500 characters each; Aura-2 limited to 2,500 characters a day **for everyone together** (`TTS_FREE_DAILY_CHARS`); after that MeloTTS | `tts.js` |
| Background jobs | 3 running, 20 kept, 200 prompts, 1,000 items, 7 days before an uncollected job is dropped | `jobs.js` `LIMITS` |
| Sync | 50,000 documents; 1.9 M characters per document | `sync.js` |
| Paid spending (only when `PRO_PAYS=on`) | each account gets an equal share of `revenue × COST_SHARE − MONTHLY_BILLS`; the owner key is capped at $20 a month | `ai.js` `budget()`, `wallet()`, `canPay()` |
| Planned fair shares of the free quota (P1.5) | per account per day: 3.5 Flash 4, Flash-Lite 60, Gemma 150, Workers AI 80 | `config-defaults.json` `freeShare` |

### 2.2 The price of one question, per model

The shape of a cloud MCQ job today: each writer call asks for 4 questions and carries up to 40,000 characters of lecture, about 11.5k input tokens. It has `max_tokens` = 3,800, and I assume 2.5k tokens of output plus 2k of thinking. Each question then gets a checker call: about 12k tokens in (the nearest lecture pages plus the evidence found), 0.9k out plus 1k thinking, and a small call that picks search terms. Current list prices, in $ per million tokens:

| Model | Input / output | Writing, per question | Checking, per question | **Per checked question** | A 40-question lecture set |
|---|---|---|---|---|---|
| Gemini 3.1 Pro (preview) | 2.00 / 12.00 | $0.019 | $0.051 | **$0.070** | $2.82 |
| Gemini 3.5 Flash | 1.50 / 9.00 | $0.014 | $0.038 | **$0.053** | $2.11 |
| Gemini 3.5 Flash-Lite | 0.30 / 2.50 | $0.004 | $0.009 | **$0.013** | $0.51 |
| Baichuan-M2-32B on Novita | 0.07 / 0.07 | $0.0002 | $0.001 | **$0.001** | $0.05 |
| Nemotron 3 on Workers AI | 0.50 / 1.50 | $0.002 | $0.008 | **$0.011** | $0.42 |
| Gemma 4 (Gemini API) | free tier only | $0 | $0 | **$0** | $0 |

Other cloud features:

| Feature | Cost | Note |
|---|---|---|
| Cloud transcription, per lecture hour | Flash-Lite about $0.07; Flash about $0.31 | 32 audio tokens a second is 115k tokens an hour, plus about 15k tokens of timed transcript. Flash's audio price may be higher than its text price, so check `GEMINI_AUDIO_PRICES`. |
| Natural voice, Aura-2 | $0.03 per 1,000 characters | A 150-card commute session read aloud (about 45k characters) costs $1.35. Every line is cached in R2, so a repeat costs nothing. |
| Natural voice, MeloTTS | $0.0002 per audio minute | An hour costs about 1 cent. |
| Sync, share links, classes | $0 on the free plans | D1 free plan: 5 M rows read and 100k written a day. Design D estimates about 35k cloud calls a day before writes run out. |
| Workers AI free allowance | 10,000 neurons a day for the **whole account** | One 4-question Nemotron call uses about 860 neurons, and today's 2,500 Aura-2 characters use about 6,800. So the free Workers AI allowance is mainly the voice. |

### 2.3 What that means for pricing

1. **Before `PRO_PAYS=on`, Pro costs the owner $0 in cash.** It runs on Google's free per-project quota (the worker logs 20 a day for 3.5 Flash and 500 for Flash-Lite; Gemma 4 has the most), Gemma, and Workers AI's free neurons. The limit is capacity, not money. At about 2.25 requests per checked question, Flash-Lite's 500 a day is roughly **220 checked questions a day across all users**, and Gemma takes the rest. Once more than about 50 people use the cloud on a given day, quality slides toward Gemma. That is the signal to switch paid models on from revenue.
2. **After `PRO_PAYS=on`, the model order decides whether Pro is worth its price.** A US annual subscriber brings $2.48 a month net, and the default `COST_SHARE` of 0.6 gives them about $1.49 a month of paid calls. That buys about **21 checked questions a month on 3.1 Pro, 28 on 3.5 Flash, 116 on Flash-Lite, or about 158 with Baichuan writing and Flash-Lite checking**. An Egyptian annual subscriber ($0.83 a month net, so about $0.50 to spend) gets about 39 Flash-Lite or 53 Baichuan-plus-Flash-Lite questions. After that, the free Gemma chain takes over. So the paid order must be cheap-first (§11), with 3.1 Pro kept for the explicit "syllabus check" `prefer`. The `wrangler.toml` comment puts 3.1 Pro first, and that would use a month's budget in about 20 questions.
3. **The natural voice cannot be an unlimited paid perk.** A daily 300-line allowance at Aura-2 prices can cost more a day than a subscriber pays in a month. Keep paid Aura-2 inside each account's wallet as the code does, and describe the perk as "a natural reading voice" with no promise of which engine.
4. **Cloud transcription must use Flash-Lite first once it is paid.** Six hours a day on Flash would cost about $1.85 a day.

---

## 3. Free and Pro

The rule: **if it costs the owner money per use, it is Pro. If it costs nothing, it is free, unless it is a clear premium perk that makes Pro worth buying without the cloud.** Guideline 3.1.2(c) asks the paywall to say what the price buys. The paywall, the App Store description and the server gates must therefore list the same features.

| Feature | Free | Pro | Running cost | Gate today |
|---|---|---|---|---|
| Write MCQs, cards, OSCE stations and cases on the device (Apple's model) | ✓ | ✓ | $0 | none |
| Review: spaced repetition, Due today, MCQ practice, OSCE timer, commute mode with the phone's voice, draw from memory, reasoning tools | ✓ | ✓ | $0 | none |
| Import PDF, Word and PowerPoint handouts | ✓ **(change)** | ✓ | $0 | Code: not gated. Paywall and listing: listed as Pro. |
| On-device transcription (Narrate) | ✓ | ✓ | $0 | none |
| Keyword syllabus coverage, analytics, exports (.apkg, PDF) | ✓ | ✓ | $0 | none |
| Share links and classes (group A), within the plan's limits | ✓ | ✓ | about $0 (D1) | server limits |
| Medical models on the device (Doctor-R1, MedVAL) | | ✓ | $0 | `LocalLLMService.needsPro` |
| Occlusion cards from labelled diagrams | | ✓ | $0 | paywall text only; P2.3 must gate it |
| Vignette Cloud: writing, accuracy checking, background jobs, AI syllabus check | | ✓ | §2.2 | server `proGate` |
| Cloud transcription (Arabic and English) | | ✓ | §2.2 | server `proGate` |
| Natural reading voice | | ✓ | §2.2 | server `proGate` |
| Sync between iPhone and iPad | | ✓ | about $0 | server `SYNC_IS_PRO` |

**Why import becomes free.** The listing's promise is "turn your own lectures into questions, free". Without import, a free user has no easy way to get a lecture into the app, and the free path cannot show what the app does. Import costs nothing to run. The reasons to upgrade are quality (Gemini writing plus the checker), cloud transcription and the second device. If the owner prefers the current split, keep it, but then P2.3 must gate import in code, because the code does not gate it today. In either case, P2.3 (paywall perks) and P6.1 (the "VIGNETTE PRO" block of `app-store-listing.md`) must move together.

**Nothing cloud-based is free**, not even a small taste. The trial is the taste, and it runs on free models only.

---

## 4. Products, base prices and why

| Product | ID | Type | US price | Per month | Against monthly |
|---|---|---|---|---|---|
| Pro Monthly | `com.redpen.pro.monthly` | auto-renewing, P1M | $4.99 | $4.99 | — |
| Pro Yearly, 1-week free trial | `com.redpen.pro.yearly` | auto-renewing, P1Y | $34.99 | $2.92 | 42% less |
| Exam Pass, 3 months | `com.redpen.pass.exam3m` | non-renewing, 92 days, stacks | $12.99 | $4.33 | 13% less; nothing renews |

Why these numbers:

- **The market for these users is cheaper than the category median.** RevenueCat's 2026 Education medians are $9.99 a month and $44.99 a year. But Vignette's first markets are Egypt, Pakistan, India and the Gulf, and its product works on the student's own lectures rather than being a curated question bank. For comparison, question banks cost: UWorld Step 1 $439 for 90 days, AMBOSS about $15 a month or $360 a year, Quesmed from about £14.99 a month, and Pastest £30–60 for 3–6 months. $4.99 sits well below all of them. Vignette is a companion to a question bank, not a replacement, and the price should say so.
- **Yearly is the default.** 59% of Education subscriptions sold are annual (RevenueCat 2026). The paywall lists yearly first, with the trial (plan P2.3).
- **The pass earns more per month than yearly.** US net is $3.68 a month against $2.48 a month for yearly, and it sells to people who would never start a renewing subscription in the eight weeks before PLAB. It must not be much cheaper than three months of the monthly plan, or it takes monthly buyers.
- **The Small Business Program is worth 15 points on every sale.** Apply before the first sale, so that no sale is charged at 30%.

---

## 5. Prices by storefront (source for `pricing.json`)

Rule for P3.2's `appstore-setup.yml`: base storefront USA. For each territory listed, use the **nearest App Store price point at or below the target**. Other territories keep Apple's equalised price from the US base. The prices are set manually, so Apple's tax and exchange-rate updates will not move them. Review Egypt and Pakistan every January (§12).

| Storefront | Tax in the price | Monthly | Yearly (1-week trial) | Exam Pass | Net a month: monthly / yearly / pass |
|---|---|---|---|---|---|
| United States (base) | none (tax added at checkout) | $4.99 | $34.99 | $12.99 | $4.24 / $2.48 / $3.68 |
| Saudi Arabia | 15% VAT | SAR 19.99 | SAR 139.99 | SAR 49.99 | $3.94 / $2.30 / $3.28 |
| United Arab Emirates | 5% VAT | AED 18.99 | AED 129.99 | AED 44.99 | $4.19 / $2.39 / $3.31 |
| Qatar, Kuwait, Bahrain, Oman | per App Store Connect | QAR 18.99 in Qatar; elsewhere the US tier in whatever currency App Store Connect shows | same pattern | same pattern | about US level |
| Egypt | 14% VAT | EGP 99 | EGP 699 | EGP 249 | $1.42 / $0.83 / $1.19 |
| India | 18% GST | ₹199 | ₹1,299 | ₹499 | $1.49 / $0.81 / $1.25 |
| Pakistan | check in App Store Connect | Rs 550 | Rs 3,600 | Rs 1,400 | $1.69 / $0.92 / $1.43 (before any tax Apple deducts) |
| United Kingdom | 20% VAT | £4.99 | £29.99 | £10.99 | $4.68 / $2.34 / $3.43 |

**Held at launch:** the subscriptions and the pass are **not available** in the UK, the 27 EU states, Iceland, Liechtenstein, Norway and Switzerland until `PRO_PAYS=on` (§6). The prices above for the UK are stored ready. The app itself is available there, with the free features. Holding the EU also defers the EU trader-status question (plan §6 step 9).

For P6.1, a block to copy into `pricing.json`:

```json
{
  "group": "Vignette Pro",
  "base": "USA",
  "rule": "nearest price point at or below target; unlisted territories use Apple equalisation from USA",
  "products": {
    "monthly": { "id": "com.redpen.pro.monthly", "type": "autoRenewable", "period": "P1M", "level": 1 },
    "yearly":  { "id": "com.redpen.pro.yearly",  "type": "autoRenewable", "period": "P1Y", "level": 1,
                 "introOffer": { "mode": "freeTrial", "duration": "P1W", "territories": "all" } },
    "pass":    { "id": "com.redpen.pass.exam3m", "type": "nonRenewing", "days": 92 }
  },
  "billingGracePeriodDays": 16,
  "prices": {
    "USA": { "currency": "USD", "monthly": 4.99,  "yearly": 34.99,  "pass": 12.99 },
    "SAU": { "currency": "SAR", "monthly": 19.99, "yearly": 139.99, "pass": 49.99 },
    "ARE": { "currency": "AED", "monthly": 18.99, "yearly": 129.99, "pass": 44.99 },
    "QAT": { "currency": "QAR", "monthly": 18.99, "yearly": 129.99, "pass": 44.99 },
    "EGY": { "currency": "EGP", "monthly": 99,    "yearly": 699,    "pass": 249 },
    "IND": { "currency": "INR", "monthly": 199,   "yearly": 1299,   "pass": 499 },
    "PAK": { "currency": "PKR", "monthly": 550,   "yearly": 3600,   "pass": 1400 },
    "GBR": { "currency": "GBP", "monthly": 4.99,  "yearly": 29.99,  "pass": 10.99 }
  },
  "unavailableUntilProPays": ["GBR", "CHE", "ISL", "LIE", "NOR", "EU27"]
}
```

`EU27` is shorthand for the 27 EU member states. P6.1 expands it into their territory codes.

---

## 6. The UK and Europe: a hard rule from Google's terms

Google's Gemini API Additional Terms say: *"You may use only Paid Services when making API Clients available to users in the European Economic Area, Switzerland, or the United Kingdom."* Firebase AI Logic's Gemini Developer API falls under them. Until `PRO_PAYS=on` puts the Firebase project on the Blaze plan, every Gemini and Gemma call the worker makes is an unpaid-service call. So:

1. **Pro is not sold in the UK, the EEA or Switzerland at launch** (§5). This costs less than it seems. Most PLAB 1 candidates sit it abroad: Cairo, Karachi, Islamabad, Indian cities and others. They buy on their home storefronts.
2. **Server rule for the P1.5 implementer:** when `request.cf.country` is in the UK, the EEA or Switzerland, skip the unpaid Gemini and Gemma sources. That covers someone with an Egyptian Apple Account studying in London. Before `PRO_PAYS=on`, such a request gets Workers AI or a clear "not available in your region yet" message.
3. **Once `PRO_PAYS=on`**, agents open these storefronts through the API. UK accounts get paid models from the first request, which the UK price covers: $2.34 a month net on yearly, so about $1.40 to spend, or about 110 Flash-Lite questions a month.
4. The terms also require users to be 18 or older, which matches the age rating in plan §6 step 8. On the unpaid tier, Google may use inputs to improve its products, and human reviewers may read them. That makes "your lectures are never used to train Google's models" an honest Pro benefit **only after** `PRO_PAYS=on`. Do not claim it before.

---

## 7. Trial and offers

| Tool | Setting | Why |
|---|---|---|
| Introductory offer | Yearly only: **free for 1 week**, new subscribers, all storefronts where Pro is sold | Education's most common trial is 5–9 days (50.3%). Median trial-to-paid is 36%. Apple allows one introductory offer per customer per subscription group, so a trial on monthly would not add a second one. It would only pull people away from yearly. |
| Longer trial test | In Egypt, from 20 Sep to 31 Oct 2027 (the start of the academic year, not an exam season), schedule a **2-week** trial as the storefront's "future" intro offer | Longer trials convert better (17–32 days: 42.5% against 25.5% for under 4 days). But a month-long trial would cover a whole exam cram, so test 2 weeks when no exam is near. Apple allows one current and one future intro offer per storefront. |
| Billing grace period | 16 days, for all renewals | Matches `Entitlement.billingGrace`. Revenue is kept if the payment recovers. |
| Offer codes | Ambassadors: "1 month free" on yearly (new and lapsed customers), one offer per large school (`amb-<slug>`), and `amb-general` for the rest. Offer codes now also work on the non-renewing Exam Pass. | Apple allows 10 active offers per product and 1 M codes per app per quarter. Hand codes out; **never charge for them** (§9). |
| Win-back offers | Lapsed yearly: 50% off the first year. Lapsed monthly: 1 month at 50%. Start them 6 weeks before each season in §8. | Apple shows them itself, in the app, in Subscription settings and on the App Store, with no extra code (iOS 18 and later). |
| Referral days (group B) | Friend: 7 days; referrer: 1 month; at most 3 a month and 12 a year | Stored as `pro_grants` with **free models only**, so they cost $0. |
| Price rises | Never in an exam season. When a rise is needed, keep existing subscribers on their price (Apple allows this without limit). | Guidelines 2.3.1 and 5.6 on trust. It also avoids the opt-in sheet that lapses people who don't respond. |

Trial and grant accounts must never count as revenue. B's `paid_until` has to exclude free-trial periods (`offerDiscountType` FREE_TRIAL) as well as sandbox purchases. Otherwise `budget()` counts trial users as paying and gives paid models away. Flagged for P1.3 and P1.5.

---

## 8. Exam-season calendar (October 2026 to September 2027)

The pattern: **the pass and offer codes 8–10 weeks before a sitting; win-back offers 6 weeks before; the yearly plan and the trial at the start of the academic year.** Promotional text (which can change without an app update) carries the season line, with no price (see `app-store-listing.md` §5).

| When | Who | Exam or season | What to push |
|---|---|---|---|
| Oct 2026 | Pakistan | PMDC NRE-I, 11 Oct 2026 | Pass (Pakistan). Launch month: trial on yearly everywhere. |
| Nov 2026 | Worldwide PLAB | PLAB 1, mid-November 2026 (the last sitting with 4 international dates a year) | Pass, ambassadors' offer codes in Egypt, Pakistan and India |
| Nov–Dec 2026 | Pakistan | NRE-II, 28–29 Nov and 5–6 Dec 2026 | Pass |
| Dec 2026 – Jan 2027 | Egypt | First-term university finals | Pass in Egypt; win-back from 1 Dec |
| Jan 2027 | India (foreign graduates) | FMGE December session, 9 Jan 2027 (tentative) | Pass in India |
| Feb 2027 | UK, Egypt | PLAB 1 February 2027: **UK only**, with no international sitting. EMLE (Egypt) also usually has a sitting around February (check with the Egyptian Health Council). | Quiet internationally. EMLE push in Egypt. |
| Every month | Saudi Arabia | SMLE: 11 testing windows a year at Prometric | No seasonal spike. Keep yearly at the front. |
| Mar–Jun 2027 | US students and IMGs | USMLE Step 1: testing all year, peak after the preclinical years | Pass (US storefront) |
| May 2027 | Worldwide PLAB | PLAB 1, May 2027. From 2027 the GMC runs **3 international sittings a year** and closes Alexandria, Dhaka, Chennai and Accra. | Pass; tell Egyptian users the Alexandria venue is closing |
| May–Jul 2027 | Egypt | Second-term finals (the semester ends around late May; medical faculties run into July) | Biggest Egyptian season: pass, win-back, ambassadors |
| Jun–Aug 2027 | US and IMG applicants | Step 2 CK before ERAS: MyERAS submissions from early September, programmes read from late September | Pass (US) |
| Jun–Jul 2027 | Pakistan, India | NRE sessions (dates to be announced); FMGE June session | Pass |
| Aug–Sep 2027 | India, worldwide | NEET PG (the 2026 exam was 30 Aug); PLAB 1 August | Pass |
| From about 20 Sep 2027 | Egypt, Gulf, Pakistan | New academic year | **Yearly plan and trial**, and the 2-week trial test in Egypt (§7) |

Re-check the next year's dates each July. The GMC, PMDC and NBEMS all say their dates can change.

---

## 9. Group licences ("class access")

What they are (plan R1): the owner attaches a licence to a class. Anyone who joins with the class code takes a seat while seats remain. A licence has `seats`, `endsAt` (at most 400 days), `paidModels` and `monthlyBudgetUsd`.

**Launch policy (no manual work, $0 risk):**
- Licences are created only as **free pilots**: the review licence (5 seats, 30 days), the ambassadors' group, and a student society trial of up to 30 days. All of them have `paidModels = 0`, so they use free models only and cost $0.
- The app never mentions buying for a group, never shows a price for it and never links to one (guideline 3.1.1 and the anti-steering rules). Pro is always available by in-app purchase too, which is what guideline 3.1.3(b) needs.

**Price list for when a school, faculty or society asks** (invoiced by the owner outside the app; optional and never automatic):

| Region | Per seat per year | Minimum | Semester (5 months) | Compared with a student's own yearly plan |
|---|---|---|---|---|
| Egypt | EGP 350 | 30 seats (EGP 10,500) | EGP 210 | half |
| Pakistan, India | US$5 equivalent (Rs 1,400 / ₹480) | 30 seats | 60% of the year | about half |
| Gulf, US, UK | US$15 (SAR 56, AED 55, £11) | 20 seats | 60% of the year | about 57% less |

- **Paid models on a licence:** switch `paidModels` on only when the licence is paid. Set `monthlyBudgetUsd` to **50% of the licence's monthly value**. There is no Apple commission, but the cash arrives by bank transfer, so keep the same margin as §10.
- **Do not sell Apple offer codes** as the delivery method. Apple presents offer codes for promotions, partnerships and referrals. Charging a school per code is untested at App Review, so B's `GROUP_DELIVERY = "offer-codes"` fallback is for sponsored, unpaid pilots only.
- The risk is ranked "Medium, the main one" in design B §5, and the Review Notes text there covers it.

---

## 10. Break-even

### 10.1 Fixed costs

| Cost | Per year | Per month | Status |
|---|---|---|---|
| Apple Developer Program | $99 | $8.25 | needed; individuals cannot get a fee waiver (only non-profits, accredited schools and governments can, and only if they sell nothing) |
| Cloudflare (Workers, D1, R2, Durable Objects, Workers AI) | $0 | $0 | free plans. Move to Workers Paid ($5 a month) only when D1's 100k writes a day or the 10k neurons a day become the limit; then add `cloudflare-workers:5` to `MONTHLY_BILLS`. |
| GitHub Actions (macOS builds) | $0 | $0 | The repository is public (checked 24 Sep 2026), so hosted runners are free. If it ever goes private: 2,000 free minutes, and macOS minutes count 10 times. |
| Firebase / Gemini | $0 | $0 | Spark plan (free tier) until `PRO_PAYS=on` |
| Domain | $0 | $0 | the `workers.dev` address is used |
| **Total** | **$99** | **$8.25** | matches `MONTHLY_BILLS = "apple-developer:8.25,github-actions:0,cloudflare-workers:0"` |

### 10.2 Subscribers needed to cover $99 a year (paid AI off)

| Storefront | Yearly subscribers | Monthly subscribers kept all year | Exam Passes a year |
|---|---|---|---|
| United States | 4 | 2 | 9 |
| United Kingdom (after the hold) | 4 | 2 | 10 |
| Saudi Arabia / UAE | 4 | 2 | 10 |
| Egypt | 10 | 6 | 28 |
| India | 11 | 6 | 27 |
| Pakistan | 9 | 5 | 24 |

**The expected mix.** Plans: 60% yearly, 25% monthly, 15% pass. Storefronts: 50% Egypt, 15% Gulf, 7.5% India, 7.5% Pakistan, 20% US and elsewhere. That blends to about **$1.73 net per paying user per month ($20.8 a year)**. So **5 paying users cover the $99**. At Education's median download-to-paid rate (2.3% by day 35), that takes about 220 downloads; in Egypt alone, about 350.

### 10.3 With paid AI on

`budget()` spends at most `revenue × COST_SHARE − fixed`. The owner therefore always keeps at least `revenue × (1 − COST_SHARE)`, **plus** the fixed bills, which are taken out first. Paid calls start only once `0.6 × revenue > $8.25`, that is, above about $13.75 a month of revenue. With the settings in §11 (`COST_SHARE = 0.5` for the first quarter, blended net $1.50):

| Paying users | Revenue a month (at $1.73) | Budget computed (at $1.50, × 0.5, − $8.25) | Owner keeps at least |
|---|---|---|---|
| 10 | $17.30 | $0 (paid calls stay off) | $17.30 |
| 50 | $86.50 | $29.25 | $57.25 |
| 300 | $519 | $216.75 | $302.25 |
| 1,000 | $1,730 | $741.75 | $988.25 |

That guarantee holds only if the worker's own cost estimates are right and its revenue figure is not inflated. Hence §11.

---

## 11. Server settings (for the P1.5 implementer; repository edits, not owner work)

**Now (launch, `PRO_PAYS=off`):**
- Keep `PRO_PAYS = "off"`, `TTS_FREE_DAILY_CHARS = "2500"` and the limits in §2.1.
- Add the UK, EEA and Switzerland rule from §6.2.

**Before anyone sets `PRO_PAYS=on`: four fixes.**
1. **Correct `GEMINI_PRICES`.** It says `gemini-3.5-flash:0.30/2.50` and `gemini-3.5-flash-lite:0.10/0.40`. Google's current prices are **1.50/9.00** and **0.30/2.50**. With the old numbers, the wallet would believe Flash costs about a fifth of what it does, and actual spend could reach several times the cap. New value: `gemini-3.1-pro-preview:2.00/12.00,gemini-3.5-flash:1.50/9.00,gemini-3.5-flash-lite:0.30/2.50,baichuan/baichuan-m2-32b:0.07/0.07`. Set `GEMINI_AUDIO_PRICES` from Google's page on the day paid models go live.
2. **Put the cheapest model first:** `PAID_MODELS = "gemini-3.5-flash-lite,gemini-3.5-flash,gemma-4-31b-it"`, `PAID_TRANSCRIBE_MODELS = "gemini-3.5-flash-lite,gemini-3.5-flash"`. 3.1 Pro is used only when a request `prefer`s it (the syllabus check), and still out of the wallet.
3. **Keep the revenue figure conservative:** `PRO_NET_MONTHLY_USD = "1.50"` until a month of real proceeds by storefront is visible in the owner's billing summary, then use the real blend. Count only paying, Production, non-trial subscriptions and passes (see §7).
4. **Keep a one-month cash float:** `COST_SHARE = "0.5"` for the first quarter. Apple pays about 45 days after the end of each fiscal month, while Google bills the card monthly. Turn `PRO_PAYS` on only after the first Apple payment has arrived, so the owner never pays Google before Apple has paid the owner. Keep `globalDailyUsd` at or below one thirtieth of the month's computed budget.

**Optional:** a Novita key (`NOVITA_API_KEY` repository secret) makes Baichuan-M2 the writer at $0.07 per million tokens. That cuts the cost of a checked question from about $0.013 to about $0.009 with Flash-Lite checking, and it keeps writer and checker as different models (`checkerOrder`). Novita is prepaid, so top it up only from Apple payouts.

---

## 12. Owner's unavoidable steps

App Store Connect and Apple only. Everything else (the subscription group, the products, the prices per territory, the introductory offer, the grace period, the availability holds and the IAP review screenshots) is done by agents through the App Store Connect API (plan P3.2 `appstore-setup.yml`). Every step works on an iPhone or iPad. **Never paste a key into chat.**

1. **Enrol in the Apple Developer Program**, $99 a year, in the Apple Developer app.
2. **App Store Connect → Business:** accept the **Paid Apps Agreement**, add the bank account and complete the tax form (W-8BEN for an individual outside the US). Products do not load, even in the sandbox, until this is active.
3. **Apply for the App Store Small Business Program** (a one-time form on the developer website). Do it before the first sale, so no sale is charged at 30%.
4. **First submission:** on the version page, **attach the monthly and yearly subscriptions and the Exam Pass**. Apple requires the first subscription to be submitted with an app version. Then submit.
5. **Only if the setup run reports a refused API call:** do that one item by hand in App Store Connect. Likely candidates are the IAP review screenshot upload and the billing grace period switch.
6. **Once a year, in January:** agents propose any Egypt and Pakistan price change, with existing subscribers kept on their price. The owner only approves the proposal.

**Optional, not App Store Connect, not needed for launch:** the Firebase Blaze plan with a Google Cloud budget alert, which switches paid models and the UK/EEA storefronts on; a Novita top-up; Cloudflare Workers Paid. Each of these is paid for from Apple proceeds, and none happens before the first payout.

---

## 13. App Review and consumer rules this plan relies on

| Rule | How the plan complies |
|---|---|
| 3.1.1: unlock only with in-app purchase | All three products are IAP. Class access is acquired outside the app, the same Pro is sold in the app, and the app shows no price or link for groups (3.1.3(b)). |
| 3.1.2(a): renewing subscriptions last at least 7 days, give ongoing value and work on all the user's devices | Monthly and yearly. The cloud service and sync are the ongoing value. The server restores Pro on every signed-in device. |
| 3.1.2(c): say what the price buys | The paywall lists the Pro perks from §3 and names the daily cloud allowance (the plan's `usage.showAllowance` screen) without promising a number that later changes. |
| Non-renewing pass: restorable, clearly one-off | "One payment, never renews" and a visible end date in Account (design B §5). |
| 2.3.7: no prices in metadata | Prices appear only on the paywall, from StoreKit. |
| No fake urgency or pass guarantees | No countdowns and no "pass PLAB" claims. Seasons use real Apple offers only. |

---

## 14. Sources

Code (this repository): `server/ai.js`, `server/tts.js`, `server/jobs.js`, `server/sync.js`, `server/wrangler.toml`, `ios/RedPen/RedPen.storekit`, `ios/RedPen/Features/Paywall/PaywallView.swift`, `ios/RedPen/Shared/LLM/MedicalGenerate.swift`, `ios/RedPen/Shared/LLM/HostedLLMClient.swift`, `docs/launch/designs/B-monetisation.md`, `docs/launch/designs/D-cost-intelligence.md`, `docs/launch/config-defaults.json`, `docs/launch/implementation-plan.md`, `docs/launch/app-store-listing.md`.

Prices and platform terms:
- [Google: Gemini API pricing (3.1 Pro, 3.5 Flash, 3.5 Flash-Lite, Gemma 4; free-tier data use)](https://ai.google.dev/gemini-api/docs/pricing)
- [Google: Gemini API rate limits (per project; Tier 1 needs billing)](https://ai.google.dev/gemini-api/docs/rate-limits)
- [Google: Gemini API Additional Terms (Paid Services only for EEA/CH/UK users; 18+; unpaid-service human review)](https://ai.google.dev/gemini-api/terms)
- [Firebase AI Logic pricing (Spark free tier, Blaze for paid, budgets)](https://firebase.google.com/docs/ai-logic/pricing)
- [Cloudflare: Workers AI pricing (10,000 free neurons a day, $0.011 per 1,000; Aura-2, MeloTTS, Nemotron)](https://developers.cloudflare.com/workers-ai/platform/pricing/)
- [Novita: Baichuan-M2-32B ($0.07 per million tokens in and out)](https://novita.ai/models/model-detail/baichuan-baichuan-m2-32b) and [Requesty listing](https://www.requesty.ai/models/novita/baichuan-baichuan-m2-32b)
- [GitHub: 2026 pricing changes for Actions](https://resources.github.com/actions/2026-pricing-changes-for-github-actions/) and [free minutes and multipliers](https://cicdcalculator.com/github-actions-free-tier)

Apple:
- [App Review Guidelines (2.3.7, 3.1.1, 3.1.2, 3.1.3(b))](https://developer.apple.com/app-store/review/guidelines/)
- [Auto-renewable subscriptions: offer codes, win-back, promotional offers, grace period, price increases](https://developer.apple.com/app-store/subscriptions/)
- [Introductory offers: trial lengths, one per group, one current and one future per storefront](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/)
- [Offer codes for every IAP type, 10 active offers, 1 M codes a quarter (MacRumors, Oct 2025)](https://www.macrumors.com/2025/10/29/apple-developer-app-store-updates/) and [Apple news](https://developer.apple.com/news/?id=gf6mgrs6)
- [Setting subscription availability by territory](https://www.developer.apple.com/help/app-store-connect/manage-subscriptions/set-availability-for-an-auto-renewable-subscription)
- [App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/) and [RevenueCat on the 15% rate](https://www.revenuecat.com/blog/engineering/small-business-program)
- [Apple: Egypt 14% VAT; auto-renewable subscriptions not auto-adjusted](https://developer.apple.com/news/?id=9o2nwe38)
- [9to5Mac: App Store tax and price changes, Aug–Sep 2026](https://9to5mac.com/2026/08/27/apple-announces-app-store-price-changes-in-four-countries/)
- [App Store tax handling by territory (India GST, Gulf VAT)](https://appsops.store/blog/app-store-tax-vat-gst-territories)
- [Apple Developer Program fee waivers (organisations only)](https://developer.apple.com/help/account/membership/fee-waivers/)
- [Apple payment timing (within 45 days of fiscal month end)](https://www.revenuecat.com/blog/growth/apple-fiscal-calendar-year-payment-dates)

Benchmarks and competitor prices:
- [RevenueCat: State of Subscription Apps 2026, Education](https://www.revenuecat.com/state-of-subscription-apps-2026-education) and [trends summary (trial length vs conversion)](https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026)
- [AMBOSS pricing, 2026](https://www.iatrox.com/blog/why-amboss-costs-what-it-costs-honest-breakdown); [UWorld Step 1 pricing, 2026](https://www.quantaprep.com/blog/is-uworld-worth-it-2026); [PLAB question bank prices, 2026](https://www.iatrox.com/blog/best-plab-1-question-bank-2026)

Exam dates:
- [GMC: changes to international PLAB 1 locations (3 sittings a year, Alexandria closing, 2027)](https://www.gmc-uk.org/news/news-archive/changes-to-international-exam-locations) and [MedRevisions: PLAB 1 2026 dates](https://www.medrevisions.com/about-plab-news/plab-1-exam-dates-2026-schedule)
- [ERAS 2027 timeline (MyERAS from 2 Sep 2026, review from 23 Sep 2026)](https://www.joinleland.com/library/a/eras-residency-timeline)
- [PMDC 2026 NRE dates](https://www.dentalnews.pk/03-Apr-2026/pmdc-neb-nre-2026-exam-dates-full-schedule-eligibility)
- [NBEMS 2026 calendar: NEET PG 30 Aug 2026, FMGE 9 Jan 2027](https://www.pw.live/news/nbems-revised-exam-calendar-2026-neet-pg-ss-fmge-dates)
- [SMLE 2026 testing windows](https://www.canadaqbank.com/blog/2025/12/15/smle-exam-dates-2026-scheduling-eligibility-preparation-guide/)
- [EMLE (Egypt) sittings](https://emle.academy/faqs/)
- [Egyptian university academic calendar (Ahram Online)](https://english.ahram.org.eg/News/547257.aspx)

Exchange rates, week of 15–24 Sep 2026:
- [Wise: USD/EGP](https://wise.com/us/currency-converter/usd-to-egp-rate/history), [USD/PKR](https://wise.com/us/currency-converter/usd-to-pkr-rate/history), [USD/INR](https://wise.com/us/currency-converter/usd-to-inr-rate/history), [GBP/USD](https://wise.com/us/currency-converter/gbp-to-usd-rate/history)
