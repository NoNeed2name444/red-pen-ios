# Mechanical integration results, 6 October 2026

## INT-QBANK

The pilot sent up to eight items to `/accuracy/check`, whose existing limit is four. An offline reproduction with five otherwise valid candidates received HTTP 400 and dropped all five. Validation now sends chunks of four without changing identifiers, grading or review rules.

`node --require /tmp/redpen-offline-preload.cjs tests/question-bank/bank.test.mjs` passed. Nine valid candidates produce request sizes `4,4,1`, remain in source order despite reversed verdict responses, and retain score and source metadata. A second nine-item case preserves flagged, unsure and missing-verdict drop reasons, drops all four items from an HTTP 503 batch, then checks the final item; metrics report nine generated, two kept and seven dropped. All responses are fixtures; no provider was called.

## INT-TTS

The MeloTTS cache was read after the daily-line reservation. With zero free Aura characters and a one-line cap, the original offline reproduction returned `200,429,429` for the same cached line. Both existing model caches are now checked before reserving usage; existing Aura audio remains preferred and uncached synthesis follows the existing Aura-then-Melo path.

`node --require /tmp/redpen-offline-preload.cjs server/tests/tts.test.mjs` passed against real in-memory SQLite and fixture AI/R2. Three identical Melo requests return HTTP 200 with `miss,hit,hit`, one synthesis call and one daily usage entry. Audio bytes and model/cache headers are checked; a separate case proves Aura remains preferred when both caches exist. Existing allowance, account isolation, paid-budget and provider-failure cases pass. No live provider was called and no Worker was deployed.
