# -*- coding: utf-8 -*-
"""What counts as a studyable claim, and what counts as covering one.

The rule that matters most is the negative one: a card ABOUT the topic must not
count as a card about the claim. Without that, a deck of ten vague cards
reports full coverage of a lecture it barely touched, which is worse than no
measurement at all.
"""
import os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from coverage import facts, is_studyable, report

failures = []


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label + (("  | " + str(detail)) if not ok else ""))
    if not ok:
        failures.append(label)


SOURCE = """
SLE is classified at 10 points or more on the EULAR criteria.
A positive antinuclear antibody is the entry criterion.
The malar rash spares the nasolabial folds.
Hydroxychloroquine lowers mortality and is given to every patient.
Mycophenolate mofetil is used for lupus nephritis induction.
Okay so, you know, let us move on now.
Anti-double-stranded DNA is the most specific antibody.
"""

found = facts(SOURCE)
texts = " | ".join(f["text"] for f in found)
check("the claims are found", len(found) == 6, "%d: %s" % (len(found), texts))
check("filler is not a claim", "let us move on" not in texts, texts)
check("a number makes a clause studyable", is_studyable("Classified at 10 points"))
check("a relation makes a clause studyable",
      is_studyable("The rash spares the folds"))
check("two technical terms make a clause studyable",
      is_studyable("Mycophenolate mofetil for nephritis induction"))
check("chatter is not studyable", not is_studyable("okay so now we go on"))
check("a bare topic is not studyable", not is_studyable("lupus"))

# a deck that genuinely covers three of the claims
cards = [
    {"front": "How many points classify SLE on the EULAR criteria?",
     "bullets": ["10 points or more"], "why": ""},
    {"front": "What does the malar rash spare?",
     "bullets": ["The nasolabial folds"], "why": ""},
    {"front": "Which drug lowers mortality in SLE?",
     "bullets": ["Hydroxychloroquine, given to every patient"], "why": ""},
]
out = report(SOURCE, cards=cards)
check("the covered claims are counted", out["covered"] == 3,
      "%d covered, uncovered: %s" % (out["covered"], out["still_to_cover"]))
check("what is missing is listed", len(out["still_to_cover"]) == 3,
      out["still_to_cover"])
check("the entry criterion is known to be missing",
      any("entry criterion" in line for line in out["still_to_cover"]),
      out["still_to_cover"])
check("coverage is a fraction of the claims, not of the cards",
      out["studyable_claims"] == 6 and out["coverage"] == 0.5, out)

# THE rule: a card about the topic is not a card about the claim
vague = [{"front": "Tell me about SLE", "bullets": ["It is an autoimmune disease"], "why": ""},
         {"front": "What is lupus?", "bullets": ["A multisystem disease"], "why": ""}]
vagueOut = report(SOURCE, cards=vague)
check("vague cards cover nothing", vagueOut["covered"] == 0,
      "%d covered" % vagueOut["covered"])

# a question covers a claim exactly as a card does
questions = [{"stem": "Which antibody is the entry criterion for SLE?",
              "options": ["Antinuclear antibody", "b", "c", "d", "e"],
              "correctIndex": 0,
              "explanation": "A positive antinuclear antibody is the entry criterion."}]
qOut = report(SOURCE, questions=questions)
check("a question covers a claim too", qOut["covered"] == 1,
      qOut["still_to_cover"])

# an empty deck is honest about it rather than dividing by zero
empty = report(SOURCE)
check("an empty deck covers nothing and says so",
      empty["covered"] == 0 and empty["coverage"] == 0.0
      and len(empty["still_to_cover"]) == 6, empty)
check("an empty source is not an error", report("")["coverage"] is None)

# the same claim said twice is one claim, not two cards' worth of work
repeated = SOURCE + "\nThe malar rash spares the nasolabial folds."
check("a repeated claim is counted once", len(facts(repeated)) == len(found),
      len(facts(repeated)))

print("\nALL COVERAGE TESTS PASS" if not failures
      else "\n%d COVERAGE TEST FAILURE(S)" % len(failures))
sys.exit(1 if failures else 0)
