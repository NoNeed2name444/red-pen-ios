# -*- coding: utf-8 -*-
"""The judging rules, tested without loading a four-billion-parameter model.

What matters here is not what MedGemma says - that is measured separately, on
real slides - but what is DONE with what it says. A rule that quietly accepts a
wrong card is worse than no check at all, so the cases below are the ones that
decide whether a card gets flagged.
"""
import os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from medgemma_check import agreement, verdict, words, stem

failures = []


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label + (("  | " + str(detail)) if not ok else ""))
    if not ok:
        failures.append(label)


check("the same answer agrees with itself",
      verdict("renal artery", "renal artery")[0] == "agree")
check("wording may differ where the identity does not",
      verdict("the renal artery", "renal arteries")[0] == "agree",
      verdict("the renal artery", "renal arteries"))

# the case this whole file exists for: one word apart, opposite meaning
check("artery is not vein",
      verdict("renal vein", "renal artery")[0] == "disagree",
      verdict("renal vein", "renal artery"))
check("a shared modifier is not agreement",
      verdict("left atrium", "left ventricle")[0] == "disagree",
      verdict("left atrium", "left ventricle"))

check("a hedge is never agreement", verdict("UNSURE", "renal artery")[0] == "unsure")
check("a polite hedge is also a hedge",
      verdict("I cannot tell from this image", "renal artery")[0] == "unsure",
      verdict("I cannot tell from this image", "renal artery"))
check("saying nothing is not agreement", verdict("", "renal artery")[0] == "unsure")
check("a card with no answer cannot be confirmed",
      verdict("renal artery", "")[0] in ("unsure", "disagree"),
      verdict("renal artery", ""))

# positional words are the ones a model volunteers whatever it sees, so they
# must not be able to carry a match on their own
check("position words alone prove nothing",
      verdict("left upper region", "left upper lobe")[0] == "disagree",
      verdict("left upper region", "left upper lobe"))
check("the stopwords really are dropped", words("the area of the structure") == [])
check("plurals meet, but short words are left alone",
      stem("arteries") == "artery" and stem("veins") == "vein" and stem("gas") == "gas",
      (stem("arteries"), stem("veins"), stem("gas")))

check("agreement is measured against the card, not the model",
      # the model naming extra structures must not dilute a correct card
      agreement("renal artery and renal vein", "renal artery") == 1.0,
      agreement("renal artery and renal vein", "renal artery"))
check("a card naming more than the model saw is not confirmed",
      agreement("artery", "renal artery hilum") < 0.5,
      agreement("artery", "renal artery hilum"))

print("\nALL MEDGEMMA RULE TESTS PASS" if not failures
      else "\n%d MEDGEMMA RULE TEST FAILURE(S)" % len(failures))
sys.exit(1 if failures else 0)
