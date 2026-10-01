# Accuracy checker comparison: MedQA (USMLE)

2026-10-01T19:25 UTC · MedQA (USMLE) test questions, seed 20260924, up to 40 per model · MedVAL's rubric, the app's own checker prompt · evidence lookup off (each model's own judgement).

A good checker **passes** correct answers and **flags** wrong ones (risk 3–4). Percentages with 95% intervals; a wide interval means too few questions yet to be sure - results add up over runs.

| Model | Questions | Passes correct | Catches wrong (lecture right) | Catches wrong (lecture also wrong) | Balanced | Median time | Unreadable / failed |
|---|---|---|---|---|---|---|---|
| workers-ai:@cf/qwen/qwq-32b | 4 | 75% (3/4; 30%–95%) | 100% (3/3; 44%–100%) | 100% (2/2; 34%–100%) | 92% | 18.0 s | 2 / 45 |
| workers-ai:@cf/openai/gpt-oss-120b | 9 | 100% (9/9; 70%–100%) | 100% (9/9; 70%–100%) | 67% (6/9; 35%–88%) | 89% | 9.5 s | 0 / 45 |
| workers-ai:@cf/nvidia/nemotron-3-120b-a12b | 7 | 100% (7/7; 65%–100%) | 100% (7/7; 65%–100%) | 50% (3/6; 19%–81%) | 83% | 3.4 s | 0 / 45 |
| workers-ai:@cf/google/gemma-4-26b-a4b-it | 15 | 100% (15/15; 80%–100%) | 100% (9/9; 70%–100%) | 38% (5/13; 18%–64%) | 79% | 8.1 s | 8 / 75 |
| gemini:gemini-3.5-flash-lite | 40 | 100% (40/40; 91%–100%) | 100% (40/40; 91%–100%) | 35% (14/40; 22%–50%) | 78% | 1.2 s | 0 / 0 |
| gemini:gemma-4-31b-it | 40 | 100% (40/40; 91%–100%) | 100% (40/40; 91%–100%) | 35% (14/40; 22%–50%) | 78% | 43.3 s | 0 / 0 |
| workers-ai:@cf/meta/llama-4-scout-17b-16e-instruct | 6 | 50% (3/6; 19%–81%) | 100% (6/6; 61%–100%) | 83% (5/6; 44%–97%) | 78% | 7.7 s | 0 / 45 |
| gemini:gemini-3.5-flash | 8 | 100% (8/8; 68%–100%) | 100% (7/7; 65%–100%) | 14% (1/7; 3%–51%) | 71% | 8.7 s | 0 / 1 |
| gemini:gemini-3.1-pro-preview | 0 | — | — | — | 0% | — | 0 / 3 |

## Progress (the benchmark runs a part a day until every model has 40 questions)

- gemini:gemini-3.1-pro-preview: 0/40 questions, no progress today (limit reached or failing)
- gemini:gemini-3.5-flash: 7/40 questions, ~25 more day(s)
- gemini:gemini-3.5-flash-lite: 40/40 questions, done
- gemini:gemma-4-31b-it: 40/40 questions, done
- workers-ai:@cf/nvidia/nemotron-3-120b-a12b: 6/40 questions, no progress today (limit reached or failing)
- workers-ai:@cf/openai/gpt-oss-120b: 9/40 questions, no progress today (limit reached or failing)
- workers-ai:@cf/meta/llama-4-scout-17b-16e-instruct: 6/40 questions, no progress today (limit reached or failing)
- workers-ai:@cf/qwen/qwq-32b: 3/40 questions, no progress today (limit reached or failing)
- workers-ai:@cf/google/gemma-4-26b-a4b-it: 15/40 questions, no progress today (limit reached or failing)

**Not finished: the next part runs tomorrow.**

## Free limits met

- gemini:gemini-3.5-flash: [quota GenerateRequestsPerDayPerProjectPerModel-FreeTier=20; retry 8s]

## Notes

- gemini:gemini-3.1-pro-preview: stopped at today's cap of 3 calls
- gemini:gemini-3.5-flash: stopped: today's free limit reached [quota GenerateRequestsPerDayPerProjectPerModel-FreeTier=20; retry 8s]
- workers-ai:@cf/meta/llama-4-scout-17b-16e-instruct: stopped at today's cap of 45 calls
- workers-ai:@cf/nvidia/nemotron-3-120b-a12b: stopped at today's cap of 45 calls
- workers-ai:@cf/openai/gpt-oss-120b: stopped at today's cap of 45 calls
- workers-ai:@cf/qwen/qwq-32b: stopped at today's cap of 45 calls
- workers-ai:@cf/nvidia/nemotron-3-120b-a12b: 502: Provider 429: Workers AI: this account's share of today's free allowance is used.
- workers-ai:@cf/google/gemma-4-26b-a4b-it: 502: Provider 429: Workers AI: this account's share of today's free allowance is used.
- workers-ai:@cf/openai/gpt-oss-120b: 502: Provider 429: Workers AI: this account's share of today's free allowance is used.
- workers-ai:@cf/qwen/qwq-32b: 502: Provider 429: Workers AI: this account's share of today's free allowance is used.
- workers-ai:@cf/meta/llama-4-scout-17b-16e-instruct: 502: Provider 429: Workers AI: this account's share of today's free allowance is used.
- gemini:gemini-3.1-pro-preview: 502: Provider 403: gemini-3.1-pro-preview: To access this model, you must enforce Firebase App Check. Learn more: https://firebase.google.com/docs/ai-logic/app-check
