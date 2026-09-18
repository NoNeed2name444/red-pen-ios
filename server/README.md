# Red Pen auth

A Cloudflare Worker with a D1 database behind it. It exists for one reason: a
phone cannot send an email. Apple and Google sign-in need no server at all; a
verification code has to come from something that can reach a mail provider and
remember what it sent.

## What it knows about anybody

An account id, which provider proved it, an address if one was offered, and the
plan the App Store confirmed. That is the whole schema - see `schema.sql`.

Decks, cards, questions, recordings, transcripts and learned pronunciations stay
on the phone and are never uploaded. There is nothing here to lose in a breach
beyond a list of addresses, and that is deliberate: the app promises on its own
empty screen that study material stays on the device, and a server holding it
would make that a lie.

## Deploying it

    cd server
    npx wrangler d1 create redpen-auth        # put the id into wrangler.toml
    npx wrangler d1 execute redpen-auth --file=schema.sql --remote
    npx wrangler secret put SESSION_SECRET    # any long random string
    npx wrangler secret put GOOGLE_CLIENT_SECRET
    npx wrangler secret put RESEND_API_KEY
    npx wrangler deploy

Then put the deployed URL into the app's `RED_PEN_AUTH_URL` build setting. Until
that is set, the app says sign-in is not configured rather than failing in a way
nobody can read.

## The three things the code cannot do for itself

**Sign in with Apple.** Needs the capability on the App ID in the Apple
Developer portal. `APPLE_BUNDLE_ID` here must match the app's bundle id exactly,
because every identity token is checked against it - a mismatch is the usual
reason a sign-in that looks right is refused.

**Google.** Create an OAuth client in the Google Cloud console with
`redpen://auth` as an authorised redirect. The client id goes in `[vars]` above
and in the app's `RED_PEN_GOOGLE_CLIENT_ID`; the secret goes in as a secret and
never into the app, because anything shipped inside an app can be read out of
it. That is why the app uses PKCE and the exchange happens here.

**Email.** Any provider with an HTTP API will do; `sendEmail` in worker.js is
written against Resend and is about ten lines to repoint. The sending domain has
to be verified with the provider, or the codes go to spam - which looks exactly
like a broken sign-in.

## What is deliberate

**Codes are stored hashed**, with the session secret as a pepper. A database
somebody can read should not hand over live sign-in codes, and verifying never
needs the original back.

**Five tries, then the code is dead.** Six digits is a few thousand guesses from
a stranger's account, and a worker will happily serve a few thousand guesses.

**Requesting a code always answers the same way**, whether or not the address
has an account. Anything else turns the sign-in form into a way of finding out
who has one.

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
