// The Terms of use and the Privacy policy, served as plain pages: the App
// Store wants both reachable from the app, and the paywall links here.
//
// Written from what the code does, file by file, and to be changed with it:
// a new provider, a new kind of data kept or a new retention period means
// this page changes in the same commit.
//
// Routes (worker.js): GET /terms, GET /privacy.

export const UPDATED = '1 October 2026';

const page = (title, body) => `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} - Stethoscore</title>
<style>
  :root { color-scheme: light dark; --ink: #14171c; --paper: #f7f8fa; --muted: #5b6573; --rule: #dde2e8; }
  @media (prefers-color-scheme: dark) { :root { --ink: #e8ecf1; --paper: #0a1628; --muted: #9aa7b8; --rule: #22324a; } }
  body { margin: 0; background: var(--paper); color: var(--ink); font: 17px/1.55 -apple-system, system-ui, sans-serif; }
  main { max-width: 680px; margin: 0 auto; padding: 32px 16px 64px; }
  h1 { font-size: 28px; margin: 0 0 4px; } h2 { font-size: 19px; margin: 28px 0 8px; }
  p, li { margin: 0 0 10px; } ul { padding-left: 20px; }
  .muted { color: var(--muted); font-size: 15px; } hr { border: 0; border-top: 1px solid var(--rule); margin: 28px 0; }
</style></head>
<body><main>
<h1>${title}</h1>
<p class="muted">Stethoscore. Last updated ${UPDATED}.</p>
${body}
<hr>
<p class="muted">Questions: use Contact us in the app's Settings. <a href="/terms">Terms of use</a> · <a href="/privacy">Privacy policy</a></p>
</main></body></html>`;

export const TERMS = page('Terms of use', `
<h2>What Stethoscore is</h2>
<p>Stethoscore is a study aid for students. It turns the material you give it into questions, cards, textbook pages, cases and OSCE stations, and helps you review them.</p>
<p><strong>It is not a medical tool.</strong> Never use it to diagnose, treat or prescribe for anyone, or to make any decision about a real patient's care or your own health. In an emergency, call your local emergency number.</p>

<h2>AI content can be wrong</h2>
<p>Much of what Stethoscore shows is written by AI models. It is checked, but checking cannot catch everything: content can be wrong, out of date or dangerous. Verify everything against current guidelines, your university's teaching and qualified clinicians before you rely on it.</p>

<h2>Your material</h2>
<p>You keep the rights to what you bring in: lectures, notes, recordings and pictures. Only bring in material you are allowed to use, and only record lectures when the people recorded have agreed. You are responsible for what you bring in and for how you use what Stethoscore makes from it.</p>

<h2>Your account</h2>
<p>You can use Stethoscore with an Apple or Google sign-in, or on one device without an account. You can delete your account at any time in the app; what that removes is described in the Privacy policy.</p>

<h2>Pro</h2>
<p>Some features need a Pro subscription, bought through the App Store. Apple handles payment, renewal and cancellation: manage or cancel it in your Apple Account's subscriptions. Free features have daily limits, which may change.</p>

<h2>Fair use</h2>
<p>Do not attack, overload or misuse the service, try to reach other people's data, or use it to make content that is unlawful or harmful. Accounts that do may be limited or closed.</p>

<h2>No guarantee</h2>
<p>Stethoscore is provided as it is. It is built by a small team and may have faults, change, or be unavailable at times. As far as the law allows, we are not liable for any loss arising from its use, including any decision made on the strength of its content.</p>

<h2>Changes</h2>
<p>These terms may change as the app does. The date at the top says when they last did.</p>
`);

export const PRIVACY = page('Privacy policy', `
<p>Stethoscore keeps your study material on your device. What leaves it, and why, is listed here. There are no ads, no tracking across apps and no selling of data.</p>

<h2>On your device</h2>
<p>Your library, progress, notes and lecture recordings are stored on your device, and are included in your device's own backups.</p>

<h2>Your account</h2>
<ul>
<li><strong>Apple or Google sign-in:</strong> the sign-in's identifier, and the email and name it shares, if any.</li>
<li><strong>On this device only:</strong> nothing about you is kept on our server. If you later link another device, an anonymous account is made for your library to sync through, with no name or email.</li>
<li><strong>Pro:</strong> the App Store's record of your subscription, checked with Apple.</li>
</ul>

<h2>Sync (Pro)</h2>
<p>With sync on, your sets, folders, review schedule, pictures and the pronunciations you have taught it are stored on our server so your other devices can fetch them. They are your own: nobody else can read them.</p>

<h2>AI features</h2>
<p>When you make a set, ask for a check, transcribe a lecture or have text read aloud in the cloud, the text, pictures or audio needed for that request are sent to an AI model and the answer comes back. The models are run by:</p>
<ul>
<li><strong>Google</strong> (Gemini and Gemma models, through Firebase), which also transcribes lecture audio.</li>
<li><strong>Cloudflare Workers AI</strong>, for some models and for read-aloud voices.</li>
</ul>
<p>We will update this page before any other provider is used. On-device models, where you choose them, send nothing.</p>
<p>A generation that runs while the app is closed is kept on our server until the app collects it, for at most seven days. Lines read aloud in the cloud are kept for up to 60 days so the same line is not paid for twice.</p>
<p>To check a question, the terms in it (a drug name, a topic) are looked up in public medical sources: Europe PMC, MedlinePlus and openFDA. Nothing about you is sent with them.</p>

<h2>What you send us</h2>
<ul>
<li><strong>Question reports:</strong> the item you report and your note, used to improve the checks, kept for up to 120 days.</li>
<li><strong>Contact us:</strong> your message, kept for up to 120 days.</li>
<li><strong>Crash and failure reports:</strong> what went wrong, the app version and the device model, with anything that could identify you taken out on the device and again on the server; never your notes, questions, recordings, name or email. On unless you turn them off in Settings; kept for up to 90 days.</li>
</ul>

<h2>Deleting your account</h2>
<p>Deleting your account in the app removes it at once, with your synced library and pictures, lines read aloud, generations, reports, messages and crash reports; a nightly pass removes anything still arriving. Kept afterwards: the sign-in's identifier, linked to your subscription, so that signing in again keeps your purchase, with no name or email, for up to 365 days; and counts that hold nothing about you, such as how many cloud requests were used in a month.</p>

<h2>Where it is kept</h2>
<p>Our server runs on Cloudflare. Requests travel encrypted.</p>

<h2>Children</h2>
<p>Stethoscore is made for university students and is not directed at children.</p>

<h2>Changes</h2>
<p>This policy changes with the app. The date at the top says when it last did.</p>
`);

/// GET /terms and GET /privacy, or null for any other path.
export function legalPage(path) {
  const html = path === '/terms' ? TERMS : path === '/privacy' ? PRIVACY : null;
  if (!html) return null;
  return new Response(html, {
    headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'public, max-age=3600' },
  });
}
