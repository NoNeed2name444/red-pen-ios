# Mechanical integration results, 6 October 2026

## INT-QBANK

The pilot sent up to eight items to `/accuracy/check`, whose existing limit is four. An offline reproduction with five otherwise valid candidates received HTTP 400 and dropped all five. Validation now sends chunks of four without changing identifiers, grading or review rules.

`node --require /tmp/redpen-offline-preload.cjs tests/question-bank/bank.test.mjs` passed. Nine valid candidates produce request sizes `4,4,1`, remain in source order despite reversed verdict responses, and retain score and source metadata. A second nine-item case preserves flagged, unsure and missing-verdict drop reasons, drops all four items from an HTTP 503 batch, then checks the final item; metrics report nine generated, two kept and seven dropped. All responses are fixtures; no provider was called.
