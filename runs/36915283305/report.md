# The verification layer on hard questions

90 real questions (MedXpertQA 30, MedQA 30, CareQA Medicine 30), each checked with its true key and with a wrong key planted: 180 checks. Checkers: the live Worker's own (https://redpen-auth.vv7sh4rnnw.workers.dev). 90 batches sent, 0 rate-limit waits, 51 min.

| measure | what it means | result |
|---|---|---|
| accuracy | of the checks that gave a verdict (Verified or Flagged), the share that were right | 50.0% (10/20) |
| dependability | of the items marked Verified, the share that really were right | n/a (0/0) |
| errors caught | wrong keys not marked Verified | 100.0% (90/90) |
| right items Verified | correct questions passed | 0.0% (0/90) |
| right items Flagged | correct questions wrongly flagged | 11.1% (10/90) |
| Check this | left for a person (no verdict either way) | 84.4% |
| pass/fail accuracy | Verified only when right, not Verified when wrong, over every check | 50.0% |
| unchecked | no checker answered | 8 |

## By source

| source | checks | accuracy | dependability | caught | right Verified | Check this |
|---|---|---|---|---|---|---|
| MedXpertQA | 60 | 30.0% | n/a | 100.0% | 0.0% | 78.3% |
| MedQA | 60 | 50.0% | n/a | 100.0% | 0.0% | 90.0% |
| CareQA Medicine | 60 | 83.3% | n/a | 100.0% | 0.0% | 85.0% |

## Each checker's own answers (its reliability as a witness)

| model | family | answered | right | blind solves right |
|---|---|---|---|---|
| gemini-3.5-flash-lite | google | 160 | 66.9% | 66.9% |
| gemma-4-31b-it | google | 104 | 76.0% | 76.0% |
