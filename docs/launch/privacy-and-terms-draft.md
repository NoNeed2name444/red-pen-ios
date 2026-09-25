# Vignette: privacy policy and terms of use (DRAFT for legal review)

Written 2026-09-24 against `preview/graph` at `effa18d` plus the working tree of that date. **This is a draft, not legal advice.** A lawyer who knows the seller's home country and the storefronts at launch must review it before it is published. Nothing here has been checked by a lawyer.

**How to use this file.**

- Part A is for the reviewer and the owner. It lists the decisions still open, the places where the code does not yet match the text, and the App Store Connect answers that must agree with the policy. It is **not** published.
- Parts B, C and D are the texts users see: the privacy policy (`/privacy`), the terms of use (`/terms`) and the education-only notice (`/medical`). Package **P1.8** (`implementation-plan.md`) copies them into `server/legal/content.js`, and those pages must match this file. **P6.1** reconciles any differences. Part E holds the short in-app texts that must say the same thing.
- `{{DOUBLE_BRACES}}` are filled in at build or deploy time. `{{PROCESSORS}}` is generated from the Worker's `env`, so the list always matches what is deployed (design F §2).
- Lines marked `[ship-gated: P…]` describe features in the implementation plan that the code does not have yet. Delete them from the published text if that package has not shipped. Guideline 2.3.1 and 5.1.1(i) both require the policy to describe the app as it is.
- Lines marked `[needs G#]` are only true once gap G# in §A2 is fixed. Fix the gap first, or change the line.
- The English text is the one that counts. The Arabic translation comes from the P5.7 translation run and must say that the English text prevails.

---

## Part A. Notes for the reviewer and the owner (not published)

### A1. Decisions for the lawyer

| # | Question | What the draft assumes | Why it matters |
|---|---|---|---|
| L1 | Who is the seller (individual or company), and where are they? | `{{SELLER}}`, `{{SELLER_COUNTRY}}` | It decides the governing law (C15), who the "controller" is under GDPR, UK GDPR and Egypt's PDPL, and what the EU Digital Services Act trader declaration shows. Guideline 5.1.1(ix) says apps in healthcare "should be submitted by a legal entity". This app is education, not healthcare, but if App Review disagrees, the fix is a company account (design F §5). |
| L2 | Minimum age | **18+** for the whole app | Google's Gemini API terms say "You must be 18 years of age or older to use the APIs". Vignette Cloud runs on Gemini, and the listing plan already overrides the age rating to 18+ (`app-store-listing.md` §1). One age for the whole app is simpler than "16+, but 18+ for cloud AI". |
| L3 | Is Egypt's PDPL (Law 151/2020) licensing needed? | Not addressed | The Executive Regulations were issued in November 2025, and the one-year grace period ends around **October 2026**, which is about launch time. They add licensing, a Data Protection Officer, and rules on cross-border transfers. Egypt is a main market (`pricing.md`). |
| L4 | Legal basis wording for the EEA and UK | Contract (account, sync, Pro), consent (cloud AI, telemetry, leaderboards, face tracking), legitimate interests (security, abuse limits) | Standard GDPR mapping. In the EEA, UK and Switzerland, only paid Gemini may serve users (see L5). |
| L5 | EEA, UK and Switzerland at launch | The app is available there, but Pro and the Exam Pass are **not** sold there until `PRO_PAYS=on` (`pricing.md` §6) | The Gemini API terms say: "You may use only Paid Services when making API Clients available to users in the European Economic Area, Switzerland, or the United Kingdom." The free tier of the app sends nothing to Gemini. |
| L6 | Liability cap and governing law | Placeholders in C14 and C15 | These depend on the seller's country and on consumer law in each storefront. |
| L7 | Should the TTS cache (C7 and B8) have an expiry? | "Kept until the cache is cleared" | The cache holds text that users typed or generated, as audio. It is not linked to anyone, but it is kept indefinitely today. |
| L8 | Is there a "sale" or "sharing" under US state laws (such as the CCPA)? | No. There are no ads, no data brokers and no cross-context advertising. | Confirm that the Gemini free tier, where Google may use content to improve its products, does not count as a "sale". The safest course is to switch to paid Gemini (`PRO_PAYS=on`) before selling in California at scale. |

### A2. Gaps between the code and this text (fix before publishing, or change the text)

Each gap names the file to change. Other jobs own those files, so this list is for them. This document changes no code.

| # | Gap | Where | Suggested fix |
|---|---|---|---|
| G1 | **Sign in with Apple tokens are not revoked when an account is deleted.** Apple's account-deletion page says apps using Sign in with Apple "must revoke user tokens" through the REST API. The app sends only the identity token, never the authorisation code, so the server has nothing it could revoke. | `server/worker.js` `withApple`/`deleteAccount`, `ios/RedPen/Shared/SocialSignIn.swift` | Send the `authorizationCode` on sign-in, and exchange it for a refresh token that is stored encrypted. On `/account/delete`, call `https://appleid.apple.com/auth/revoke`. This needs a Sign in with Apple key, which can be the same `.p8` key type the owner already creates for App Store Connect. List that in the owner's steps. |
| G2 | **Background jobs survive account deletion.** `deleteAccount` wipes D1 and R2 but not the account's `GenerationJobs` Durable Object. | `server/worker.js`, `server/jobs.js` | Add a `/wipe` route to the Durable Object: `deleteAll()` plus `deleteAlarm()`. Call it from `deleteAccount`, the same way plan §3.1 runs `onAccountDelete`. |
| G3 | **The 7-day job expiry only runs while another job is running.** `alarm()` removes old jobs, but no alarm is set once every job has finished. An uncollected job's replies could stay until the account's next job. | `server/jobs.js` | When a job finishes, set an alarm for `updated + keepDays`. |
| G4 | **IP addresses are stored raw and never pruned.** `pair_attempts.ip` holds `cf-connecting-ip` and has no clean-up. | `server/pair.js`, `schema.sql` | Store a daily-rotating HMAC of the IP (the `ipKey` from design E §6), and prune rows older than 48 hours in the maintenance cron. This is already planned in P0.1 and P1.7. |
| G5 | **The paywall links to `https://redpen.app/terms` and `/privacy`,** which nobody is known to own. That breaks Schedule 2 §3.8(b) and guideline 3.1.2. | `ios/RedPen/Features/Paywall/PaywallView.swift` | Link to `{{BASE}}/terms` and `{{BASE}}/privacy`. Already P0.2. |
| G6 | **The app has no contact route.** 5.1.1(i) needs a way to reach you and 1.5 needs a working Support URL. | — | The `/support` form and `/support/message` (P1.8). |
| G7 | **No consent is asked before content goes to third-party AI** (guideline 5.1.2(i)). The recording gate names Google only for transcription. | `RecordingTermsView.swift`, `CloudGate` | `CloudAIConsentView` (P2.9), using the text in E1. |
| G8 | **The Settings text says "Vignette does not keep it"** about cloud requests. That is true for chat and transcription. It is not quite true for background jobs, which keep their results until the app collects them, for up to 7 days, and it hides that Google's free tier may keep content. | `ios/RedPen/Features/Support/ModelSettingsView.swift` line ~140 | Use E2. |
| G9 | **AI usage counters outlive the account.** `ai_usage` and `ai_cost` rows are keyed by the deleted account's id and kept on purpose, so a new account cannot restart the month. They hold no content, but they are pseudonymous. | `server/worker.js` `deleteAccount` | Keep them, but prune `ai_usage` after 35 days and `ai_cost` after 13 months in the maintenance cron. B8 says so. |
| G10 | **No `PrivacyInfo.xcprivacy` file.** The app uses `UserDefaults`, which is a required-reason API (reason `CA92.1`). | `ios/` | P3.1 (design F build step F7). |
| G11 | **Terms gate v2 has no education-only or patient-data point.** | `RecordingTermsView.swift` | Gate v3 (P2.9), using the text in E3. |

### A3. App Store Connect answers that must match this policy (owner, at publish time)

These are the only manual steps this document causes. They are the same as plan §6 and design F §9.

1. **Privacy Policy URL:** `{{BASE}}/privacy`, and `{{BASE}}/privacy?lang=ar` for the Arabic localisation. `{{BASE}}` is currently `https://redpen-auth.vv7sh4rnnw.workers.dev`.
2. **License agreement:** keep **Apple's Standard EULA**. Our Terms (Part C) add to it and do not replace it. The App Store description ends with the Terms and Privacy links, as Schedule 2 §3.8(b) requires for auto-renewing subscriptions.
3. **App Privacy ("nutrition label").** Tracking: **No**. Declare the following:

| Apple data type | Linked to the user? | Purpose | Why |
|---|---|---|---|
| Contact Info → Email Address, Name | Linked | App Functionality | Only if Sign in with Apple or Google provides them (B4.2) |
| Identifiers → User ID | Linked | App Functionality | Account id |
| Purchases → Purchase History | Linked | App Functionality | Transaction id, used to confirm Pro with Apple |
| User Content → Other User Content | Linked | App Functionality | Synced library; lecture text sent for cloud writing and checking; background jobs; `[ship-gated]` shared sets, class sets, group names, display names, error reports |
| User Content → Audio Data | Linked | App Functionality | Cloud transcription sends lecture audio through our server to Google. Declare it because Google's free tier may keep it. |
| User Content → Customer Support | Linked | App Functionality | `[ship-gated: P1.8]` support messages |
| Usage Data → Product Interaction | Linked | App Functionality | `[ship-gated: P1.2]` weekly counts for leaderboard opt-ins only |
| Diagnostics → Crash Data, Performance Data, Other Diagnostic Data | **Not linked** | Analytics, App Functionality | `[ship-gated: P1.7/P2.8]` opt-in only |
| Usage Data → Product Interaction | **Not linked** | Analytics | `[ship-gated: P1.7/P2.8]` opt-in usage counts |

   Not collected: location, contacts, health and fitness, financial info, browsing and search history, photos, sensitive info, advertising data, and face data. Face tracking never leaves the device, so under Apple's definition of "collect" it is not collected.
4. **Age rating:** answer honestly, then set 18+ (L2).
5. **Regulated medical device:** declare "not a regulated medical device" (design F §9).
6. **EU trader status (DSA):** declare it. A trader's address, phone and email are shown on EU product pages.

---

## Part B. Privacy Policy (published at `/privacy`)

> **Vignette Privacy Policy**
> Version {{PRIVACY_VERSION}} · Effective {{EFFECTIVE_DATE}}

### B1. The short version

- **Most of Vignette works entirely on your iPhone or iPad.** Starting without an account sends nothing to us.
- **We keep only what a feature needs.** If you sign in, that is an account id and, if Apple or Google gives it to us, your name and email. With Pro sync, it is your study library. For cloud features, it is what you send, and only for as long as it takes to answer.
- **Cloud AI is optional and named.** When you use Vignette Cloud, your text or audio goes to **Google (Gemini)** or **Cloudflare (Workers AI)** to be processed. We ask before the first time `[needs G7]`, and you can say no and stay on the device.
- **No ads, no tracking, no selling data.** There are no third-party analytics or advertising kits in the app.
- **Delete everything from inside the app:** Account → Delete account.
- **Vignette is for study, not for patient care. Never enter information that could identify a real patient.**

### B2. Who we are

Vignette is made by **{{SELLER}}** ("we", "us"). {{SELLER}} is the controller of the personal data described here. To reach us, use {{BASE}}/support or, in the app, Settings → Help → Contact `[needs G6]`. `{{SELLER_ADDRESS}}` *(required if you are a trader under EU law, and in some other countries)*.

### B3. What stays on your device and never reaches us

These never leave your iPhone or iPad unless you choose to export or share them yourself:

- **Your lecture recordings** and the **pronunciations** the app learns. They are not synced, even with Pro.
- **Everything you create while you use the app without an account** ("Continue on this device"). There is no server account until you link a second device, buy Pro, or `[ship-gated]` join a class.
- **Work done by the on-device models.** This covers Apple's on-device model (Apple Intelligence), Gemma, Doctor-R1 and MedVAL once downloaded, text recognition in slides and PDFs, and the reading of PDF, Word and PowerPoint files.
- **Lecture transcription on this device.** The app requires on-device speech recognition for lectures, and refuses rather than send the audio anywhere.
- **Face tracking** for the optional "Pop-out with face tracking" effect. See B6.
- **Reading aloud with the phone's own voice.**
- **Your study history and analytics** (scores, mistakes, streaks, review schedule). With Pro sync, the review schedule is synced.
- **API keys you enter for your own provider.** They are kept in the device keychain and never synced or sent to us.

### B4. What we collect and why

#### B4.1 If you never sign in

Nothing. The app can still download models or reach Apple, as B5 explains, but it sends us nothing about you.

#### B4.2 Your account

An account is created when you sign in with Apple or Google, or when a device that started "on this device" needs one: to link a second device, to sync, or to use Pro.

| What | Where it comes from | Why |
|---|---|---|
| A random account id | We create it | To know which library is yours |
| Sign-in provider (Apple, Google or device) and that provider's id for you | Apple or Google | To recognise you when you sign in again |
| Email address | Only if Apple or Google gives it. Apple's "Hide My Email" gives a relay address. | Shown in your account screen. We do not send marketing email. |
| Name | Only if Apple (first sign-in only) or Google gives it | Shown in your account screen |
| Account creation time, and the time you last chose "sign out everywhere" | We record them | Security: sign-in sessions from before that time stop working |
| `[ship-gated: P0.1]` Which version of the terms you accepted, and whether you agreed to cloud AI, with times | You, in the app | To show that you agreed, and to ask again when the terms change |

A device account (from "Continue on this device") has **no name and no email**, only a random id.

**Linking a second device** uses an 8-character code that lasts ten minutes and works once. To stop anyone guessing codes, we count attempts per network address for one hour `[needs G4]`.

#### B4.3 Buying Pro or an Exam Pass

Apple handles payment. **We never see your card or Apple Account details.** We keep:

- the App Store **original transaction id** and plan;
- the time until which **Apple confirmed** the subscription is active;
- whether the purchase was real or a test ("Production" or "Sandbox").

We use these to unlock the cloud features on our server. Our server checks the transaction with Apple. `[ship-gated: P1.3]` Apple also sends our server notices about renewals, refunds and cancellations for purchases made in the app. We keep those notices to keep Pro correct.

#### B4.4 Sync between your devices (Pro)

With Pro, your library is kept on our server so it can follow you between your own devices:

- your **sets** and what they contain: questions, cards, notes, OSCE stations, book chapters, read-aloud scripts, and the **source text and slide pictures** you imported to make them;
- your **folders**;
- your **review schedule** (when each card is next due).

Nobody else can see your library. We do not read it for any other purpose, and we do not use it to train AI. Pictures are stored under your account, named by a fingerprint of their bytes. They are not shared between accounts. When Pro ends, the synced copy stays on the server, and syncing resumes if Pro comes back. Delete the account to remove it (B9).

#### B4.5 Vignette Cloud (Pro): writing, checking, transcription and natural voice

When **you choose** a cloud feature, what you send goes through our server to an AI provider (B5), and the answer comes back to you.

| Feature | What is sent | What we keep |
|---|---|---|
| **Writing and checking** (questions, cards, cases, OSCE stations, answer marking, "Check accuracy") | The instructions the app writes plus the part of your lecture or notes they need; for checking, the item and the lecture passage it came from | **Nothing** after the answer is returned. We count requests per day and, when we pay for AI, the estimated cost per month. |
| **Background writing** (keeps working after you leave the app) | Your lecture text and the app's instructions | The lecture and instructions are deleted as soon as the job finishes. The **results** are kept until the app collects them, which deletes them, and for **at most 7 days** `[needs G3]`. |
| **Evidence for checking** | Our server takes short search terms, such as a drug or topic name, from the item being checked and looks them up in **Europe PMC**, the **US National Library of Medicine (MedlinePlus)** and **openFDA**. | These services see only the search terms, and they come from our server, not from your device. Results are cached for a day. |
| **Cloud transcription** (Narrate) | Your lecture audio, in 10-minute pieces | **Nothing** after the transcript is returned |
| **Natural voice** (read aloud in a human-sounding voice) | The line of text to be read | The **audio of that line**, stored under a fingerprint of the voice and the words, so the same line is never paid for twice. It is **not linked to you or your account**. |

We also count how many cloud requests, transcription pieces and voice lines each account uses per day, so everyone stays within fair limits (C9).

#### B4.6 Using your own AI provider (advanced)

In Settings → Models → "Your own key" you can connect your own account with a provider, such as OpenAI, Anthropic (Claude), Google Gemini, OpenRouter or Hugging Face, or your own server on your home network. **Requests then go straight from your device to that provider, under your agreement with them.** They do not pass through us, and we never see your key.

#### B4.7 Error reports and support `[ship-gated: P1.8/P2.9]`

- **"Report an error"** on a question or card sends **that item only** (never the whole lecture), the reason you pick, and an optional note. The screen shows exactly what will be sent. We use it to fix content and the app, and we may send a correction back to you.
- **Support messages** hold what you write, plus an email address if you choose to give one.

#### B4.8 Sharing, classes and leaderboards `[ship-gated: P1.1/P1.2/P2.1/P2.2]`

- **Shared sets.** When you share a set, its content, title, subject and the display name you choose are published at a link. **Anyone with the link can see them.** Search engines are asked not to index the pages. The lecture text is left out unless you turn it on. "Stop sharing" takes the link down. Copies other people already imported stay on their devices.
- **Classes and study groups** hold the group name, who is a member and what their role is, and the sets added to the group. A lecturer sees how many members there are, but never a member list.
- **Leaderboards are off until you opt in** for a specific group. You choose a display name **for that group**; your account name is never used. Only two weekly numbers are uploaded: **questions and cards answered**, and **active days**. Accuracy and study time are never uploaded. "Hide me" removes you at once.
- **Reports and blocks** that you make about shared content or people are kept to moderate the service.

#### B4.9 Crash reports and usage counts (off unless you turn them on) `[ship-gated: P1.7/P2.8]`

In Settings → Privacy choices you can turn on either or both:

- **Crash and performance reports:** crash and hang reports, launch time, memory use, app version and build, device model, and iOS version. This data comes from Apple's MetricKit, and only if you also allow "Share With App Developers" in iOS Settings.
- **Usage counts:** daily counts of actions such as "quiz completed" or "cards reviewed", plus app language (English, Arabic or other), phone or iPad, and the week you started.

Both are **off by default** and are sent **without your account, without a device id, and without an IP address being stored**. They cannot be linked back to you, so we cannot look them up or delete them one person at a time. They are deleted on the schedule in B8 instead. Pro never depends on these settings. "See exactly what is sent" shows the data.

#### B4.10 Security and abuse prevention

Our server is on Cloudflare. Cloudflare sees your network address when your device connects, as every web service does. We use the address briefly to limit abuse, such as too many pairing codes or new accounts from one network. We store only counters, deleted after **48 hours** `[needs G4]`. When something fails, we log short technical error messages, never the content you sent.

### B5. Who else processes your data

We share data only with the service providers below, only to run the feature you are using, and never to advertise to you. They are bound by their own terms and privacy policies, and must protect the data at least as well as this policy does.

`{{PROCESSORS}}` is generated from the deployed configuration. The full possible list:

| Provider | What for | What it receives | Notes |
|---|---|---|---|
| **Cloudflare, Inc.** | Hosts our server, database (D1), file storage (R2), background jobs (Durable Objects) and **Workers AI**. Workers AI runs the backup text models and the natural voice: Deepgram Aura-2 and MeloTTS, **hosted by Cloudflare**. | Everything our server handles | Cloudflare states that it does not use customer content to train AI models or improve its services. |
| **Google LLC: Gemini, through Firebase AI Logic** | Vignette Cloud writing and checking, and cloud transcription | The text or audio of that request | **{{GEMINI_TIER_PARAGRAPH}}** (see below) |
| **Apple Inc.** | Sign in with Apple, App Store payments, subscription checks, crash reports (MetricKit, if you opt in); speech recognition for spoken answers on devices that cannot do it on the device | Your sign-in; the transaction; iOS audio for spoken answers when on-device recognition is unavailable | Governed by Apple's privacy policy |
| **Google LLC: Google Sign-In** | Only if you choose "Sign in with Google" | Your Google sign-in | Governed by Google's privacy policy |
| **Europe PMC (EMBL-EBI), US National Library of Medicine, US FDA (openFDA)** | Evidence for the accuracy checker | Short search terms only, sent from our server | Public services, no account |
| **Hugging Face, Inc.** | Downloading the optional on-device models (Gemma, Doctor-R1, MedVAL) | A normal download request from your device (network address, device type). **No study content.** | |
| **Novita AI** *(listed only if enabled)* | A medical writing model (Baichuan-M2) that goes first for Vignette Cloud | The text of that request | Novita states that it does not train on API content and does not keep it after answering. |

**`{{GEMINI_TIER_PARAGRAPH}}`, choose one at deploy time from `GEMINI_BILLING`/`PRO_PAYS`:**

- *While we use Google's free tier:* "Google provides this on its free tier. **On the free tier, Google may use what you send, and the answers, to improve its products, and human reviewers may read them.** That is why we ask you not to send personal or sensitive information, and never patient information. To avoid this, don't use Vignette Cloud: everything else works on your device."
- *Once we pay for Gemini:* "We pay Google for this service. Google does not use what you send to improve its products. It keeps it only briefly, to detect abuse."

### B6. Face tracking (optional, off by default)

"Pop-out with face tracking" (Settings → Look and feel) uses the front **TrueDepth camera through Apple's ARKit** to work out where your head is, so the 3D effect lines up with your eyes. It works like this:

- It is **off until you turn it on**, and iOS asks for camera permission first.
- Only the **position of your head**, as a few numbers per video frame, is used, in memory, to draw the effect. **No image, video, face geometry or face measurement is saved, sent to us, or sent to anyone else.**
- The camera is off whenever the effect isn't showing, and whenever a voice, recording or drawing screen is open.
- Face data is **never** used to identify you, or for marketing, advertising or data mining.

You can turn it off in the app, or remove camera access in iOS Settings → Vignette.

### B7. Health information and patients

Vignette is a study tool for medical students. **It is not for patient care, and it is not a medical record.**

- **Do not enter anything that could identify a real patient**, such as names, dates, record numbers, photos or rare details, in notes, recordings, questions or reports.
- Vignette does not ask for or use your own health information.
- Recordings should include only people who agreed (C6).

### B8. How long we keep things

| Data | Kept for |
|---|---|
| Account (id, provider, email, name) and purchase record | Until you delete the account |
| Synced library and pictures (Pro) | Until you delete them, or delete the account. Deleting a set leaves a small marker (its id and type, **no content**) so your other devices delete it too. |
| Pairing codes | 10 minutes, or until used |
| Cloud writing, checking and transcription requests | Not kept by us after the answer. For Google's free tier, see B5. |
| Background job input (lecture text, instructions) | Deleted when the job finishes |
| Background job results | Until the app collects them, and at most 7 days `[needs G3]` |
| Natural-voice audio cache | Not linked to anyone. Kept until the cache is cleared `{{TTS_CACHE_DAYS — see A1 L7}}`. |
| Daily and monthly AI usage counters | 35 days (daily) and 13 months (monthly), including after account deletion. They hold only counts. `[needs G9]` |
| Network-address abuse counters | 48 hours `[needs G4]` |
| `[ship-gated]` Error reports | Your account is removed from them when you delete it. They are deleted 1 year after being resolved. |
| `[ship-gated]` Support messages | 1 year. Deleted when you delete your account. |
| `[ship-gated]` Shared sets | Until you stop sharing, delete your account, or we remove them after a report |
| `[ship-gated]` Leaderboard weekly numbers | 8 weeks |
| `[ship-gated]` Crash and usage data (not linked to you) | Raw reports 8 days; crash samples 90 days; crash counts 180 days; daily totals 400 days |
| `[ship-gated]` Saved results for re-use ("generated before" cache) | 180 days, or until you delete your account |

We may keep something longer only if the law requires it, for example tax records for purchases. Apple keeps those for App Store purchases.

### B9. Your choices and rights

- **Delete your account:** Account → Delete account. This deletes your account, your synced library and pictures, your pairing codes and your purchase record from our server straight away `[needs G1, G2]`. The copy on your device stays until you delete the app. **Deleting does not cancel a subscription.** Cancel it first in Account → Manage, or in iOS Settings → Apple Account → Subscriptions, or Apple keeps billing.
- **Sign out everywhere:** Account → Sign out everywhere ends every session on every device, which helps if you lose one.
- **Stop cloud AI:** choose "This phone only" or "On this device" in Settings → Models, or withdraw cloud AI consent in Settings `[ship-gated: P2.9]`.
- **Stop sharing, leave a group, or "Hide me" on a leaderboard** `[ship-gated]`.
- **Turn crash reports and usage counts off** in Settings → Privacy choices `[ship-gated]`.
- **Camera, microphone and speech recognition:** iOS Settings → Vignette.

Depending on where you live, including under the EU and UK GDPR, Egypt's Personal Data Protection Law (No. 151 of 2020), Saudi Arabia's PDPL and US state privacy laws, you may have the right to **access, correct, delete or export** your data, to **object** to or **restrict** some processing, and to **withdraw consent** at any time without affecting what was done before. To use these rights, contact us (B2). We reply within **30 days**. You can also complain to your data protection authority.

### B10. Age

Vignette is for university students and graduates. **You must be 18 or older to use it.** Some of the AI services it relies on require that. We do not knowingly collect data from anyone under 18. If you believe a child has given us data, contact us and we will delete it.

### B11. Where your data is processed

Our providers run services in many countries, including the United States and the European Union. Cloudflare serves requests from the data centre nearest to you. When data leaves your country, we rely on the protections the law provides for such transfers, such as standard contractual clauses where they apply. `{{LAWYER: confirm transfer mechanism for Egypt PDPL and Saudi PDPL}}`

### B12. Security

Connections are encrypted (HTTPS). Sign-in sessions are signed, and they can be cancelled from any device. Keys for our AI providers stay on our server and never reach the app. Your own API keys stay in your device's keychain. No system is perfectly secure. If a breach affects you, we will tell you as the law requires.

### B13. What we don't do

- No advertising, no ad networks, and no tracking across apps or websites. The app does not use Apple's advertising identifier.
- No selling or renting of personal data.
- No third-party analytics or crash kits in the app.
- No use of your library, recordings or reports to train AI models by us.
- No marketing email.

### B14. Changes

When this policy changes, we update the version and date above. If a change matters, the app tells you and, where the law requires, asks you again. Earlier versions are available on request.

### B15. Contact

{{SELLER}} · {{BASE}}/support `{{SELLER_ADDRESS}}`

---

## Part C. Terms of Use (published at `/terms`)

> **Vignette Terms of Use**
> Version {{TERMS_VERSION}} · Effective {{EFFECTIVE_DATE}}

### C1. These terms and Apple's licence

These terms are between you and **{{SELLER}}**. They **add to** Apple's Licensed Application End User License Agreement (the "Standard EULA"), which licenses the app to you. If the two conflict about the licence itself, Apple's Standard EULA wins. Apple is not responsible for Vignette or for supporting it. By using Vignette, you agree to these terms and to our Privacy Policy.

### C2. Who can use Vignette

You must be **18 or older**. Vignette is meant for medical students and others studying medicine.

### C3. Education only: not medical advice

**Vignette is a study tool. It does not give medical advice, and it must not be used to diagnose, treat or manage any patient or to make clinical decisions.** See the full Education-Only Notice (Part D). In short:

- Questions, cards, cases, explanations, "patient" replies, OSCE marking, transcripts and accuracy checks are **generated by AI** from the material you provide. They **can be wrong, incomplete or out of date, even after they have been checked.**
- The accuracy figures we publish (`{{BASE}}/accuracy`) are **measurements on exam-style questions, not a guarantee** about any single answer.
- Always check against current guidelines, your university's teaching and qualified clinicians. In real clinical situations, follow your supervisors and local protocols.
- Vignette is not affiliated with or endorsed by any exam body (USMLE/NBME/FSMB, PLAB/UKMLA/GMC, MRCP, MRCS or others). Exam names describe the style of practice only.

### C4. No patient information

Do not enter, record, upload or share anything that could identify a real patient. You are responsible for following your university's rules and the law on patient confidentiality.

### C5. Your material and your rights to it

- **Only add material you own or have the right to use**: your own notes, material your university gave you to study from, or content whose licence allows it. Do not upload other people's paid courses, question banks or copyrighted books that you have no right to copy.
- You keep all rights in your material. You give us a limited licence to store, copy, process and send it **only** to run the features you use, as the Privacy Policy explains. This includes sending it to the AI providers listed there when you use cloud features. `[ship-gated]` When you share a set publicly or with a group, you also let the people you share it with view and import it. This lasts until you stop sharing, but copies already imported stay with them.
- What the AI produces for you from your material is yours to use for your own study. We make no claim to it.

### C6. Recordings

Only record, upload or transcribe a lecture, talk or conversation when **everyone who can be heard has agreed**, and when your university's rules and your country's law allow it. You are responsible for your recordings and for what you do with their transcripts. Vignette has no part in, and does not approve of, recording anyone without consent.

### C7. Acceptable use

Do not:

- use Vignette for patient care, or present its output as professional medical advice;
- break the law, or infringe anyone's copyright, privacy or other rights;
- `[ship-gated]` share content that is offensive, harassing or sexual, that contains personal data about other people, or that infringes copyright; or use display names or group names that impersonate someone or are offensive;
- try to get around limits, payments or security; send automated requests to our server outside the app; reverse-engineer our server; or use Vignette Cloud to run requests that are not for your own study;
- resell or give access to your account or Pro to others, except through features we provide, such as `[ship-gated]` class access.

We may remove content and suspend or close accounts that break these rules. `[ship-gated: P1.1]` Shared content can be reported from the share page or the app. Content reported by several people may be hidden automatically until we review it, which we aim to do within 24 hours.

### C8. Copyright complaints `[ship-gated: P1.1/P1.8]`

If you believe shared content infringes your copyright, report it at {{BASE}}/support (reason: copyright). Include the link, what the work is and how to contact you. We remove infringing content, and we close the accounts of people who infringe repeatedly.

### C9. Pro, the Exam Pass and payments

- **Free features** run on your device and stay free.
- **Pro** (monthly or yearly subscription) adds Vignette Cloud, cloud transcription, the natural voice, sync between your devices, and the premium on-device models. The yearly plan may start with a free trial. The **Exam Pass** is a one-time purchase that gives Pro for **92 days**, does **not** renew, and adds to any time you already have. Prices are shown in the app before you buy.
- **Apple handles billing.** Payment is charged to your Apple Account when you confirm the purchase. **Subscriptions renew automatically unless you turn off auto-renew at least 24 hours before the end of the current period.** Your account is charged for renewal within 24 hours before the period ends. Manage or cancel in iOS Settings → Apple Account → Subscriptions. **Refunds are handled by Apple** under its policies. If a free trial is offered, any unused part of it ends when you buy a subscription.
- **Fair-use limits.** Cloud features have daily limits per account, shown in the app. Examples today: about 400 cloud requests, 6 hours of cloud transcription and 300 natural-voice lines a day. They also have a monthly budget. When a limit is reached, the feature pauses until it resets, and the on-device features keep working. The limits protect the service for everyone. They may change, but not in a way that removes what you paid for.
- **The models behind Vignette Cloud may change.** We choose the providers and may switch between them, for example when one is busy, to keep the service running. The Privacy Policy always lists them.
- **Deleting your account does not cancel your subscription** (Privacy Policy B9).
- `[ship-gated: P1.4]` **Class access and referral rewards** follow the rules shown where you get them. Class access is given by the school or lecturer and ends when you leave the class or its access ends. Rewards have no cash value.

### C10. Third-party services

Vignette relies on Apple, Cloudflare, Google and the other services named in the Privacy Policy. If you connect your own AI provider (B4.6), your use of it is between you and that provider, under their terms.

### C11. Availability and changes

We work to keep Vignette running, but we do not promise it will always be available or error-free. We may change or stop features. If we stop a paid feature for good, we will tell you in the app and point you to Apple for refunds where they apply.

### C12. Ending

You can stop using Vignette and delete your account at any time. We may suspend or end your access if you seriously or repeatedly break these terms. Where it is reasonable, we tell you first.

### C13. Warranty

Vignette is provided **"as is" and "as available"**. To the extent the law allows, we make no warranty that it is accurate, complete, fit for a particular purpose or uninterrupted. This matters especially for AI-generated medical content (C3). Nothing in these terms limits rights you have as a consumer that cannot legally be limited.

### C14. Limitation of liability

To the extent the law allows, we are not liable for indirect or consequential losses, for lost data you did not keep elsewhere, or for **any decision about a patient's care or your own health based on Vignette**. Our total liability to you is limited to **{{LIABILITY_CAP — e.g. the amount you paid us in the 12 months before the claim}}**. We do not limit liability for death or personal injury caused by our negligence, for fraud, or for anything else the law does not allow us to limit.

### C15. Governing law

{{LAWYER: governing law and courts, depending on the seller's country (A1 L1, L6). Keep the mandatory consumer protections of the user's country of residence.}}

### C16. Changes to these terms

We may update these terms. The app shows you the new version, and important changes are asked again before you continue. If you do not agree, stop using Vignette and delete your account.

### C17. Contact

{{SELLER}} · {{BASE}}/support

---

## Part D. Education-Only Notice (published at `/medical`, linked from the app)

> **Vignette is for learning medicine, not for practising it.**

1. **What Vignette is.** Vignette helps medical students revise. It turns your own lectures and notes into practice questions, flashcards, cases and OSCE practice, and it helps you test yourself.
2. **What it is not.** It is not a medical device. It is not a source of medical advice. It is not a tool for diagnosing, treating or managing patients, or for deciding doses or other care. It is not a substitute for a doctor, a pharmacist, current guidelines or your university's teaching.
3. **AI makes mistakes.** Content is written by AI models from the material you provide. It can be wrong, and it can repeat mistakes or outdated content from your source. The accuracy checker compares items with your lecture and with public sources such as Europe PMC, MedlinePlus and FDA drug labels. It reduces errors but does not remove them. Our published accuracy figures are measurements on exam-style questions, not a promise about any single answer.
4. **Check before you rely on it.** Confirm anything important against current national guidelines (for example NICE, BNF or your country's equivalent), your teaching and qualified clinicians. Before making any medical decision, including about your own health, talk to a doctor.
5. **Keep patients anonymous.** Never enter information that could identify a real patient.
6. **In an emergency,** call your local emergency number. Vignette cannot help in an emergency.
7. **Found an error?** Use "Report an error" in the More menu of any question or card `[ship-gated: P2.9]`, or contact us at {{BASE}}/support.

---

## Part E. Short in-app texts (must match Parts B to D)

### E1. Cloud AI consent sheet (before the first cloud request; guideline 5.1.2(i)) `[G7]`

> **Use Vignette Cloud?**
> To write, check, transcribe or read aloud in the cloud, what you send (lecture text, your answers, or lecture audio) goes through Vignette's server to **Google (Gemini)** or **Cloudflare (Workers AI)**{{, or Novita}}. {{FREE_TIER: On Google's free tier, Google may use it to improve its products, and human reviewers may read it.}} Vignette doesn't keep it after answering, except background jobs, which are kept until collected (up to 7 days).
> • You must be 18 or older.
> • Never include information that identifies a real patient.
> **[Allow cloud AI]** **[Keep everything on this device]**
> You can change this any time in Settings → Models. · Privacy Policy

The two buttons have equal weight. The sheet never appears at launch, only when a cloud feature is first used.

### E2. Settings → Models, Vignette Cloud row (replaces the current text) `[G8]`

> Google's Gemini, with Cloudflare's models taking over when it is busy. Your text is sent to Google or Cloudflare to answer. {{FREE_TIER: On Google's free tier Google may use it to improve its products.}} Vignette keeps nothing except unfinished background jobs, for up to 7 days.

### E3. Terms gate v3: the "Read this before you start" screen `[G11]` (in the app: `RecordingTermsView`, `RecordingTerms.version = 3`)

Shown once per account after sign-in; cannot be dismissed; the agree button counts down five seconds.

> **Read this before you start**
>
> *(red box)*
> **Vignette is a study aid for students. It is NOT a medical tool.**
> **Never use it to diagnose, treat or prescribe for anyone, or to make any decision about a real patient's care or your own health.**
> **AI content can be wrong, out of date or dangerous, even after it has been checked.** Verify everything against current guidelines, your university's teaching and qualified clinicians before you rely on it.
> In an emergency, call your local emergency number.
>
> - **No patient information. Ever.** Never enter, record, upload or photograph anything that could identify a real patient: names, dates, record numbers, images or rare details.
> - **Record people only with their consent.** Recording someone without their permission can be illegal. Only record, upload or transcribe a lecture, talk or conversation when the lecturer and everyone who can be heard have agreed, and your university's rules and the law allow it. You alone are responsible for your recordings and their transcripts.
> - **Only add sources you have the right to use.** Your own notes, material your university gave you to study from, or content whose licence allows it. Never upload other people's paid courses, question banks or copyrighted books.
> - **Misuse ends your account.** Using Vignette for patient care, recording people without consent, uploading material you have no right to, or breaking the law can get your account suspended or closed. You are solely responsible for how you use the app; Vignette has no part in, and does not approve of, any misuse.
> - **No warranty, no liability.** Vignette is provided as is, with no promise that anything in it is accurate or complete. To the extent the law allows, Vignette and its makers accept no liability for any decision, harm or loss that comes from relying on it.
> - **Cloud transcription.** When you choose cloud transcription, the audio is sent to Google (Gemini) to be transcribed. Choose "This phone only" to keep it on your device.
>
> By tapping "I understand and agree" you confirm you have read all of this and accept full responsibility for how you use Vignette.
>
> **[I understand and agree]**

Not yet on the screen: the **18 or older** point (C2); add it here and bump the version again when the age rule is final.

### E4. Privacy choices ask card `[ship-gated: P2.8]`

> **Help make Vignette better?** Send anonymous crash reports and usage counts. They are not linked to you or your account. Pro never depends on this. **[Send anonymously]** **[No thanks]** · See exactly what is sent

### E5. Leaderboard opt-in `[ship-gated: P2.2]`

> **Join this group's leaderboard?** Pick a name for this group only. Only two numbers are shared each week: questions and cards answered, and days active. Your accuracy and study time are never shared. You can hide yourself any time.

### E6. Report an error sheet `[ship-gated: P2.9]`

> This sends only this question and your note, not your lecture. Don't include patient details.

### E7. Delete account confirmation (already in the app; keep it)

> Deleting removes your account, your synced library and its subscription record from our server. The copy on this phone stays. It does not cancel an active subscription. Do that in Manage first, or Apple will keep billing.

---

## Sources

Code read for this draft (at `effa18d` plus the working tree of 2026-09-24):

- `server/worker.js`, `sync.js`, `ai.js`, `jobs.js`, `tts.js`, `evidence.js`, `pair.js`, `tokens.js`, `schema.sql`, `wrangler.toml`, `.github/workflows/worker-deploy.yml`
- `ios/project.yml`: usage strings, background modes, URL scheme
- `ios/RedPen/Shared/HeadTracker.swift`, `LectureTranscriber.swift`, `Voice/VoiceListener.swift`, `LLM/HostedLLMClient.swift`, `LLM/CloudJobs.swift`
- `ios/RedPen/Models/SyncDoc.swift`, `Persistence/AccountStore.swift`, `SyncEngine.swift`, `SyncPush.swift`, `Keychain.swift`
- `Features/Auth/AccountView.swift`, `SignInView.swift`, `Features/Account/RecordingTermsView.swift`, `Features/Support/ModelSettingsView.swift`, `Features/Paywall/PaywallView.swift`
- Plans: `docs/launch/implementation-plan.md` (P0.1, P1.1–P1.8, P2.8, P2.9), `designs/A-share-loops.md` §A3 and §5.6, `designs/E-quality-insight.md` §1, §2.3, §5 and §6, `designs/F-trust-legal-arabic.md` §2 and §5, `pricing.md`, `app-store-listing.md`

External sources:

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): 1.4.1, 3.1.2, 5.1.1(i), 5.1.1(v), 5.1.1(ix), 5.1.2(i), 5.1.2(vi)
- [Apple: Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/): Sign in with Apple token revocation, subscription notice
- [Apple: App privacy details](https://developer.apple.com/app-store/app-privacy-details/): the definition of "collect", data types, "linked", optional disclosure
- [Apple: Licensed Application End User License Agreement (Standard EULA)](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)
- [Apple Developer Program License Agreement, Schedule 2 (PDF)](https://developer.apple.com/support/downloads/terms/schedules/Schedule-2-and-3-English.pdf) and [RevenueCat on Schedule 2 §3.8(b)](https://www.revenuecat.com/blog/engineering/schedule-2-section-3-8-b): required subscription disclosures and links
- [Apple: requiresOnDeviceRecognition](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)
- [App Store Review Guidelines History: Face ID, ARKit and privacy policies](https://www.appstorereviewguidelineshistory.com/articles/2017-09-15-face-id-arkit-privacy-policies/) and [iMore: ARKit face tracking](https://www.imore.com/arkits-face-tracking-fud)
- [Gemini API Additional Terms of Service](https://ai.google.dev/gemini-api/terms) (last modified 2026-04-28): 18+, free-tier use and human review, paid-tier data use, EEA/UK/CH paid only, no clinical use or medical advice
- [Firebase AI Logic: data governance](https://firebase.google.com/docs/ai-logic/data-governance)
- [Cloudflare Workers AI: data usage](https://developers.cloudflare.com/workers-ai/platform/data-usage/) and [Deepgram Aura-2 on Workers AI](https://developers.cloudflare.com/workers-ai/models/aura-2-en/) (Cloudflare-hosted partner model, $0.03 per 1,000 characters)
- [Novita AI terms of service](https://novita.ai/legal/terms-of-service) and [Novita FAQ](https://novita.ai/docs/guides/faq): no training, zero retention
- [Kennedys: Egypt's PDPL compliance countdown (2026)](https://www.kennedyslaw.com/en/thought-leadership/article/2026/egypt-s-personal-data-protection-law-the-compliance-countdown-has-begun/), [Al Tamimi: Egypt issues PDPL Executive Regulations](https://www.tamimi.com/law_update_articles/from-policy-to-practice-egypt-issues-executive-regulations-of-the-personal-data-protection-law/), [DLA Piper: data protection laws in Egypt](https://www.dlapiperdataprotection.com/?t=law&c=EG)
