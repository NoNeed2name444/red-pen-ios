# The verification layer on hard questions

15 real questions (MedXpertQA 5, MedQA 5, CareQA Medicine 5), each checked with its true key and with a wrong key planted: 30 checks. Checkers: the live Worker's own (https://redpen-auth.vv7sh4rnnw.workers.dev). 15 batches sent, 0 rate-limit waits, 4 min.

| measure | what it means | result |
|---|---|---|
| accuracy | of the checks that gave a verdict (Verified or Flagged), the share that were right | 100.0% (7/7) |
| dependability | of the items marked Verified, the share that really were right | n/a (0/0) |
| errors caught | wrong keys not marked Verified | 100.0% (15/15) |
| right items Verified | correct questions passed | 0.0% (0/15) |
| right items Flagged | correct questions wrongly flagged | 0.0% (0/15) |
| Check this | left for a person (no verdict either way) | 76.7% |
| pass/fail accuracy | Verified only when right, not Verified when wrong, over every check | 50.0% |
| unchecked | no checker answered | 0 |

## By source

| source | checks | accuracy | dependability | caught | right Verified | Check this |
|---|---|---|---|---|---|---|
| MedXpertQA | 10 | 100.0% | n/a | 100.0% | 0.0% | 90.0% |
| MedQA | 10 | 100.0% | n/a | 100.0% | 0.0% | 70.0% |
| CareQA Medicine | 10 | 100.0% | n/a | 100.0% | 0.0% | 70.0% |

## Each checker's own answers (its reliability as a witness)

| model | family | answered | right | blind solves right |
|---|---|---|---|---|
| @cf/openai/gpt-oss-120b | openai | 28 | 82.1% | 82.1% |
| gemini-3.5-flash-lite | google | 27 | 81.5% | 81.5% |
| @cf/nvidia/nemotron-3-120b-a12b | nvidia | 16 | 87.5% | 87.5% |
