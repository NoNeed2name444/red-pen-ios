# Mechanical integration results, 6 October 2026

## INT-QBANK

The pilot sent up to eight items to `/accuracy/check`, whose existing limit is four. An offline reproduction with five otherwise valid candidates received HTTP 400 and dropped all five. Validation now sends chunks of four without changing identifiers, grading or review rules.

`node --require /tmp/redpen-offline-preload.cjs tests/question-bank/bank.test.mjs` passed. Nine valid candidates produce request sizes `4,4,1`, remain in source order despite reversed verdict responses, and retain score and source metadata. A second nine-item case preserves flagged, unsure and missing-verdict drop reasons, drops all four items from an HTTP 503 batch, then checks the final item; metrics report nine generated, two kept and seven dropped. All responses are fixtures; no provider was called.

## INT-TTS

The MeloTTS cache was read after the daily-line reservation. With zero free Aura characters and a one-line cap, the original offline reproduction returned `200,429,429` for the same cached line. Both existing model caches are now checked before reserving usage; existing Aura audio remains preferred and uncached synthesis follows the existing Aura-then-Melo path.

`node --require /tmp/redpen-offline-preload.cjs server/tests/tts.test.mjs` passed against real in-memory SQLite and fixture AI/R2. Three identical Melo requests return HTTP 200 with `miss,hit,hit`, one synthesis call and one daily usage entry. Audio bytes and model/cache headers are checked; a separate case proves Aura remains preferred when both caches exist. Existing allowance, account isolation, paid-budget and provider-failure cases pass. No live provider was called and no Worker was deployed.

## INT-COMMUTE

Spoken MCQs updated the session counts and `StudyLog` but omitted the shared answer history. `CommuteModeView` already owns the current `Store`; it now passes that same instance into `CommuteSession`, which keeps a weak reference and calls the existing `recordAnswer` contract after its existing grading calculation. The playlist preserves the library question UUID, and spoken choices index the original option list. `Store.recordAnswer` already rejects questions absent from the MCQ library. Skip, repeat, pause and unavailable-microphone paths return before the new call. No grading, schema or display copy changed.

The existing `tools/make_swiftpm.py` assembled `core`, `core1` and `core2` sequentially with exit 0; the latter two include the spoken modes. `git diff --check` passed and the sole `session.load` caller was updated. Swift is unavailable in this Linux workspace, so neither Swift compilation nor microphone-driven answer persistence is claimed as tested here. The existing Mac preview build must confirm compilation; on-device verification must check that a spoken right/wrong answer updates the same saved history as the ordinary quiz, while skipping or listening without a microphone adds no answer event.

## INT-PREVIEW

The existing design-preview publisher created an unrelated root commit for every run and force-pushed it, contrary to the repository's never-force-push rule. It now checks the exact destination ref, fetches an existing head as the next commit's parent, stages the current artifacts and uses an ordinary push. Only a missing branch starts a new history; other remote errors stop publication. The existing graph, iPhone tour and iPad jobs and their tests are unchanged. `preview/prework-20261006` publishes to `shots/prework-20261006`; `preview/graph` keeps its existing `design-preview` destination.

`python3 tests/workflows/design_preview_test.py` passed two offline tests executing the actual workflow publisher against local bare Git remotes. For both destination mappings, the second publication has the first head as its parent, both commits remain reachable, stale payload files disappear, and the README records the new source. An unavailable remote fails before creating a replacement commit. Payloads in this test are synthetic fixtures, not screenshots. YAML parsing and `bash -n` on the publication step passed. Real screenshots require the existing Mac simulator workflow and must be tied to its source SHA and run ID before delivery.
