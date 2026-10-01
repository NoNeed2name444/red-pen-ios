# The verification layer on hard questions

90 real questions (MedXpertQA 30, MedQA 30, CareQA Medicine 30), each checked with its true key and with a wrong key planted: 180 checks. Voters: github:openai/gpt-4.1, github:deepseek/DeepSeek-V3-0324, github:meta/Llama-4-Maverick-17B-128E-Instruct-FP8, github:mistral-ai/mistral-medium-2505, github:microsoft/Phi-4. 360 model calls, 0 rate-limit waits, 1 min.

| measure | what it means | result |
|---|---|---|
| accuracy | of the checks that gave a verdict (Verified or Flagged), the share that were right | n/a (0/0) |
| dependability | of the items marked Verified, the share that really were right | n/a (0/0) |
| errors caught | wrong keys not marked Verified | 100.0% (90/90) |
| right items Verified | correct questions passed | 0.0% (0/90) |
| right items Flagged | correct questions wrongly flagged | 0.0% (0/90) |
| Check this | left for a person (no verdict either way) | 0.0% |
| pass/fail accuracy | Verified only when right, not Verified when wrong, over every check | 50.0% |
| unchecked | no checker answered | 180 |

## By source

| source | checks | accuracy | dependability | caught | right Verified | Check this |
|---|---|---|---|---|---|---|
| MedXpertQA | 60 | n/a | n/a | 100.0% | 0.0% | 0.0% |
| MedQA | 60 | n/a | n/a | 100.0% | 0.0% | 0.0% |
| CareQA Medicine | 60 | n/a | n/a | 100.0% | 0.0% | 0.0% |

## Each checker's own answers (its reliability as a witness)

| model | family | answered | right | blind solves right |
|---|---|---|---|---|
