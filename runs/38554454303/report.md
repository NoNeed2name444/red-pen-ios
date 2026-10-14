# The verification layer on hard questions

90 real questions (MedXpertQA 30, MedQA 30, CareQA Medicine 30), each checked with its true key and with a wrong key planted: 180 checks. Checkers: the live Worker's own (https://redpen-auth.vv7sh4rnnw.workers.dev). 92 batches sent, 2 rate-limit waits, 14 min.

| measure | what it means | result |
|---|---|---|
| accuracy | of the checks that gave a verdict (Verified or Flagged), the share that were right | 100.0% (27/27) |
| dependability | of the items marked Verified, the share that really were right | n/a (0/0) |
| errors caught | wrong keys not marked Verified | 100.0% (90/90) |
| right items Verified | correct questions passed | 0.0% (0/90) |
| right items Flagged | correct questions wrongly flagged | 0.0% (0/90) |
| Check this | left for a person (no verdict either way) | 85.0% |
| pass/fail accuracy | Verified only when right, not Verified when wrong, over every check | 50.0% |
| unchecked | no checker answered | 0 |
| source-proven | right items an official source states word for word | 0.0% (0/90) |
| wrong keys source-proven | false proofs; must be 0 | 0 |

## By source

| source | checks | accuracy | dependability | caught | right Verified | Check this |
|---|---|---|---|---|---|---|
| MedXpertQA | 60 | 100.0% | n/a | 100.0% | 0.0% | 91.7% |
| MedQA | 60 | 100.0% | n/a | 100.0% | 0.0% | 83.3% |
| CareQA Medicine | 60 | 100.0% | n/a | 100.0% | 0.0% | 80.0% |

## Each checker's own answers (its reliability as a witness)

| model | family | answered | right | blind solves right |
|---|---|---|---|---|
| claude-opus-5-5 | anthropic | 163 | 84.0% | 84.0% |
| gemini-3.5-flash-lite | google | 156 | 69.2% | 69.2% |
| @cf/nvidia/nemotron-3-120b-a12b | nvidia | 58 | 82.8% | 82.8% |
| @cf/openai/gpt-oss-120b | openai | 43 | 74.4% | 74.4% |
