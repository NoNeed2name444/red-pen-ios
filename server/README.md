# Red Pen auth

A Cloudflare Worker, a D1 database for documents and an R2 bucket for pictures.
It does two things: says who somebody is, and carries their own library between
their own devices.

## What it holds

An account row - id, provider, address if one was offered - and that account's
own sets, folders and review schedules as documents. Slide images live in R2
under the hash of their own bytes.

It is one student's material on one student's account. It is not shared with
anyone, nothing is read from it for any other purpose, and deleting the account
from inside the app takes the library and the pictures with it.

## How sync works

A revision counter per account. Every write takes the next number; a device asks
"what has happened since 47?" and gets a page of documents. A push says which
revision it was working from, and a document that has moved since is refused
with the server's copy attached so the device can merge and try again - per
document, so one stale deck cannot throw away nineteen good ones in the same
batch.

Conflicts are settled on the device, in `SyncMerge`, where the rule is that the
loser is kept as a visible copy rather than dropped. The server does not decide
whose work survives.

## The accuracy engine

`accuracy.js` checks questions, cards, cases, OSCE stations, textbook pages,
narrated facts and (when a student asks) their own notes. Each batch of up to
four items is shown with its lecture excerpt and free literature
(`evidence.js`: Europe PMC, MedlinePlus, openFDA) to two free checker models -
a third when they disagree, never the model that wrote the items - and every
call goes through `ai.js`'s free shares and neuron limits. `accuracy-rules.js`
adds deterministic checks (doses, lab values and units, key/explanation
contradictions), and `accuracy-model.js` combines everything into P(accurate)
and Verified / Check this / Flagged. Verdict signals are cached in
`accuracy_verdicts` by the hash of the item's content, so nothing is checked
twice unless edited. Reports go to `accuracy_reports` (deleted with the
account). The combiner's weights are trained for free by
`bench/train-accuracy.mjs` (`.github/workflows/accuracy-model.yml`) and served
from `accuracy_model`; before any training the bundled prior is used.

## Deploying it

    cd server
    npx wrangler d1 create redpen-auth        # put the id into wrangler.toml
    npx wrangler d1 execute redpen-auth --file=schema.sql --remote
    npx wrangler r2 bucket create redpen-blobs
    npx wrangler secret put SESSION_SECRET    # any long random string
    npx wrangler secret put GOOGLE_CLIENT_SECRET
    npx wrangler deploy

Then put the deployed URL into the app's `RED_PEN_AUTH_URL` build setting. Until
that is set, the app says sign-in is not configured rather than failing in a way
nobody can read.

## The two things the code cannot do for itself

**Sign in with Apple.** Needs the capability on the App ID in the Apple
Developer portal. `APPLE_BUNDLE_ID` here must match the app's bundle id exactly,
because every identity token is checked against it - a mismatch is the usual
reason a sign-in that looks right is refused.

**Google.** Create an OAuth client in the Google Cloud console with
`redpen://auth` as an authorised redirect. The client id goes in `[vars]` above
and in the app's `RED_PEN_GOOGLE_CLIENT_ID`; the secret goes in as a secret and
never into the app, because anything shipped inside an app can be read out of
it. That is why the app uses PKCE and the exchange happens here.

## What is deliberate

**A blob must hash to its own name.** An upload whose bytes do not match the
address it was sent to is refused. Without that check a caller could park
anything under any address, and every device that later asked for that picture
would get the wrong bytes for ever - because nothing re-fetches a blob it
believes it already has.

**Blobs are namespaced per account.** Sharing them by hash across accounts would
be cheaper, and would also mean an upload could tell you whether somebody else
has that exact file. Storage is not worth that.

**Apple and Google sign-ins with the same address make two accounts.** We cannot
prove they are the same person, and merging on an unverified claim is how an
account gets taken over.

**Deleting an account deletes the row.** Not a flag: the App Store requires the
account to be removable from inside the app, and a row marked deleted has not
been removed. Note this does not cancel an active subscription - only Apple can
do that, which is why the app says so before it deletes anything.

**The subscription row is a convenience, never the authority.** What unlocks the
app is StoreKit on the device. A server that overrules the App Store is a server
that locks paying people out when it has a bad day.
