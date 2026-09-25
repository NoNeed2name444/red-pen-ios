# Accuracy checker comparison: MedQA (USMLE)

2026-09-25T09:07 UTC · MedQA (USMLE) test questions, seed 20260924, up to 40 per model · MedVAL's rubric, the app's own checker prompt · evidence lookup off (each model's own judgement).

A good checker **passes** correct answers and **flags** wrong ones (risk 3–4). Percentages with 95% intervals; a wide interval means too few questions yet to be sure - results add up over runs.

| Model | Questions | Passes correct | Catches wrong (lecture right) | Catches wrong (lecture also wrong) | Balanced | Median time | Unreadable / failed |
|---|---|---|---|---|---|---|---|
| workers-ai:@cf/qwen/qwq-32b | 4 | 75% (3/4; 30%–95%) | 100% (3/3; 44%–100%) | 100% (2/2; 34%–100%) | 92% | 18.0 s | 1 / 0 |
| workers-ai:@cf/openai/gpt-oss-120b | 8 | 100% (8/8; 68%–100%) | 100% (8/8; 68%–100%) | 63% (5/8; 31%–86%) | 88% | 9.6 s | 0 / 0 |
| workers-ai:@cf/nvidia/nemotron-3-120b-a12b | 5 | 100% (5/5; 57%–100%) | 100% (5/5; 57%–100%) | 50% (2/4; 15%–85%) | 83% | 3.4 s | 0 / 0 |
| gemini:gemini-3.5-flash-lite | 40 | 100% (40/40; 91%–100%) | 100% (40/40; 91%–100%) | 35% (14/40; 22%–50%) | 78% | 1.2 s | 0 / 0 |
| gemini:gemma-4-31b-it | 40 | 100% (39/39; 91%–100%) | 100% (37/37; 91%–100%) | 35% (14/40; 22%–50%) | 78% | 42.3 s | 0 / 4 |
| gemini:gemini-3.5-flash | 3 | 100% (3/3; 44%–100%) | 100% (3/3; 44%–100%) | 33% (1/3; 6%–79%) | 78% | 7.9 s | 0 / 0 |
| workers-ai:@cf/meta/llama-4-scout-17b-16e-instruct | 6 | 50% (3/6; 19%–81%) | 100% (5/5; 57%–100%) | 80% (4/5; 38%–96%) | 77% | 7.2 s | 0 / 0 |
| workers-ai:@cf/google/gemma-4-26b-a4b-it | 14 | 100% (13/13; 77%–100%) | 100% (7/7; 65%–100%) | 0% (0/1; 0%–79%) | 67% | 10.0 s | 8 / 91 |
| gemini:gemini-3.1-pro-preview | 0 | — | — | — | 0% | — | 0 / 1 |

## Progress (the benchmark runs a part a day until every model has 40 questions)

- gemini:gemini-3.1-pro-preview: 0/40 questions, no progress today (limit reached or failing)
- gemini:gemini-3.5-flash: 3/40 questions, ~13 more day(s)
- gemini:gemini-3.5-flash-lite: 40/40 questions, done
- gemini:gemma-4-31b-it: 38/40 questions, ~1 more day(s)
- workers-ai:@cf/nvidia/nemotron-3-120b-a12b: 4/40 questions, ~8 more day(s)
- workers-ai:@cf/openai/gpt-oss-120b: 8/40 questions, ~4 more day(s)
- workers-ai:@cf/meta/llama-4-scout-17b-16e-instruct: 5/40 questions, ~7 more day(s)
- workers-ai:@cf/qwen/qwq-32b: 3/40 questions, ~11 more day(s)
- workers-ai:@cf/google/gemma-4-26b-a4b-it: 9/40 questions, ~4 more day(s)

**Not finished: the next part runs tomorrow.**

## Free limits met

- gemini:gemini-3.1-pro-preview: [quota GenerateContentInputTokensPerModelPerDay-FreeTier=?, GenerateContentInputTokensPerModelPerMinute-FreeTier=?; retry 59s]
- gemini:gemini-3.5-flash-lite: [quota GenerateRequestsPerMinutePerProjectPerModel-FreeTier=15; retry 54s]
- gemini:gemini-3.5-flash: [quota GenerateRequestsPerMinutePerProjectPerModel-FreeTier=5; retry 50s]

## Notes

- gemini:gemini-3.1-pro-preview: stopped: today's free limit reached [quota GenerateContentInputTokensPerModelPerDay-FreeTier=?, GenerateContentInputTokensPerModelPerMinute-FreeTier=?; retry 59s]
- workers-ai:@cf/nvidia/nemotron-3-120b-a12b: stopped at its share of today's neurons (~937 of 900)
- workers-ai:@cf/meta/llama-4-scout-17b-16e-instruct: stopped at its share of today's neurons (~934 of 900)
- gemini:gemini-3.5-flash: stopped at today's cap of 9 calls
- workers-ai:@cf/qwen/qwq-32b: stopped at its share of today's neurons (~950 of 900)
- workers-ai:@cf/openai/gpt-oss-120b: stopped at its share of today's neurons (~936 of 900)
- workers-ai:@cf/google/gemma-4-26b-a4b-it: 502: Provider 502: Workers AI sent back nothing usable.
- workers-ai:@cf/google/gemma-4-26b-a4b-it: 502: Provider 429: Workers AI: this account's share of today's free allowance is used.
- gemini:gemma-4-31b-it: 502: Provider 429: gemma-4-31b-it: Gemini Developer API is overloaded. Please try again later.
