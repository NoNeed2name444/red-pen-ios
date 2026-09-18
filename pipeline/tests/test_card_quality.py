# -*- coding: utf-8 -*-
"""Every rule is here as the bad card it exists to catch, and a good one beside it.

A quality check that flags good cards is worse than none, because it gets
switched off. So each rule is tested twice: once on the failure, once on
something sound that must pass clean.
"""
import os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from card_quality import check_mcq, check_card, duplicates, review
import quiz_from_cards

failures = []


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label + (("  | " + str(detail)) if not ok else ""))
    if not ok:
        failures.append(label)


def rules(problems):
    return {p["rule"] for p in problems}


GOOD = {
    "id": "q1",
    "stem": "A 24-year-old woman has a facial rash that spares the nasolabial folds. "
            "Which finding would best support a diagnosis of SLE?",
    "options": ["Positive antinuclear antibody", "Elevated serum ferritin",
                "Positive rheumatoid factor", "Raised serum amylase",
                "Positive monospot test"],
    "correctIndex": 0,
    "explanation": "A positive antinuclear antibody is the entry criterion for SLE classification.",
}
check("a sound question passes clean", not check_mcq(GOOD), check_mcq(GOOD))

longest = dict(GOOD, id="q2", options=[
    "A positive antinuclear antibody test, which is the entry criterion and is "
    "present in almost every patient with the disease",
    "Ferritin", "Amylase", "Monospot", "Glucose"])
check("the longest option is caught", "key-is-longest" in rules(check_mcq(longest)),
      rules(check_mcq(longest)))

hedged = dict(GOOD, id="q3", options=[
    "Antinuclear antibody may be positive", "Ferritin is always elevated",
    "Rheumatoid factor is always positive", "Amylase is always raised",
    "Monospot is always positive"])
check("only the key hedging is caught", "only-key-hedges" in rules(check_mcq(hedged)),
      rules(check_mcq(hedged)))

clang = dict(GOOD, id="q4",
             stem="Which drug is the hydroxychloroquine-sparing agent of choice?",
             options=["Hydroxychloroquine dosing", "Ferritin", "Amylase", "Monospot", "Glucose"],
             correctIndex=0,
             explanation="Hydroxychloroquine dosing is weight based.")
check("a word shared only by stem and key is caught",
      "stem-word-only-in-key" in rules(check_mcq(clang)), rules(check_mcq(clang)))

nonanswer = dict(GOOD, id="q5", options=["Positive antinuclear antibody", "Ferritin",
                                         "Amylase", "Monospot", "All of the above"])
check("'all of the above' is caught",
      "non-answer-option" in rules(check_mcq(nonanswer)), rules(check_mcq(nonanswer)))

thin = dict(GOOD, id="q6", stem="SLE")
check("a topic is not a stem",
      {"stem-not-a-question", "stem-too-thin"} & rules(check_mcq(thin)) != set(),
      rules(check_mcq(thin)))

stray = dict(GOOD, id="q7", explanation="Aspirin is given after myocardial infarction.")
check("an explanation about something else is caught",
      "explanation-misses-the-key" in rules(check_mcq(stray)), rules(check_mcq(stray)))

# --- cards

GOOD_CARD = {"id": "c1", "kind": "qa", "front": "What does the malar rash spare?",
             "bullets": ["The nasolabial folds"],
             "why": "Sparing the nasolabial folds separates it from rosacea."}
check("a sound card passes clean", not check_card(GOOD_CARD), check_card(GOOD_CARD))

stuffed = dict(GOOD_CARD, id="c2", bullets=["One", "Two", "Three", "Four", "Five"])
check("a card carrying five facts is caught",
      "too-many-facts" in rules(check_card(stuffed)), rules(check_card(stuffed)))

swallowed = {"id": "c3", "kind": "cloze",
             "clozeText": "{{c1::Systemic lupus erythematosus is a multisystem autoimmune disease}}."}
check("a cloze that deletes the sentence is caught",
      "cloze-swallows-the-sentence" in rules(check_card(swallowed)),
      rules(check_card(swallowed)))

good_cloze = {"id": "c4", "kind": "cloze",
              "clozeText": "SLE is classified at {{c1::10}} points on the EULAR/ACR criteria."}
check("a sound cloze passes clean", not check_card(good_cloze), check_card(good_cloze))

empty_cloze = {"id": "c5", "kind": "cloze", "clozeText": "Somebody removed the braces"}
check("a cloze with no deletion is caught",
      "cloze-without-a-deletion" in rules(check_card(empty_cloze)),
      rules(check_card(empty_cloze)))

pair = [{"id": "d1", "front": "What does the malar rash spare?"},
        {"id": "d2", "front": "What does a malar rash spare?"}]
check("two cards asking one thing are caught",
      duplicates(pair, lambda c: c.get("front")), duplicates(pair, lambda c: c.get("front")))
distinct = [{"id": "d3", "front": "What does the malar rash spare?"},
            {"id": "d4", "front": "Which drug lowers mortality in SLE?"}]
check("different questions are left alone",
      not duplicates(distinct, lambda c: c.get("front")))

# --- quiz built from the deck

DECK = [
    {"id": "k1", "kind": "qa", "front": "Which drug lowers mortality in SLE?",
     "bullets": ["Hydroxychloroquine"], "why": "It lowers flares and damage accrual."},
    {"id": "k2", "kind": "qa", "front": "Which antibody is the entry criterion for SLE?",
     "bullets": ["Antinuclear antibody"], "why": "Required before points are counted."},
    {"id": "k3", "kind": "qa", "front": "Which antibody is most specific for SLE?",
     "bullets": ["Anti-double-stranded DNA"], "why": "Specific, and tracks nephritis."},
    {"id": "k4", "kind": "qa", "front": "Which drug is used for lupus nephritis induction?",
     "bullets": ["Mycophenolate mofetil"], "why": "As effective as cyclophosphamide."},
    {"id": "k5", "kind": "qa", "front": "Which test monitors disease activity in SLE?",
     "bullets": ["Complement C3 and C4"], "why": "They fall in active disease."},
    {"id": "k6", "kind": "qa", "front": "Which skin sign spares the nasolabial folds?",
     "bullets": ["The malar rash"], "why": "Sparing separates it from rosacea."},
]
questions, skipped = quiz_from_cards.build(DECK, seed=1)
check("a question is built from each card", len(questions) == len(DECK),
      (len(questions), skipped))

first = questions[0]
check("the key is the card's own answer",
      first["options"][first["correctIndex"]] == "Hydroxychloroquine", first)
answers = {c["bullets"][0] for c in DECK}
check("every option came from the deck, none invented",
      all(set(q["options"]) <= answers for q in questions))
check("the card's own reasoning is carried over",
      first["explanation"].startswith("It lowers flares"), first["explanation"])
check("no question repeats an option",
      all(len(set(q["options"])) == len(q["options"]) for q in questions))

# the questions it writes must themselves survive the quality rules
built = review({"mcq": questions})
allowed = {"near-duplicate"}   # six cards on one topic do resemble each other
check("the generated questions pass the quality rules",
      not (rules(built["problems"]) - allowed), built["problems"])

thin_deck = DECK[:2]
_, why_not = quiz_from_cards.build(thin_deck, seed=1)
check("a thin deck refuses rather than inventing distractors",
      len(why_not) == 2 and all("distractors" in s["why"] for s in why_not), why_not)

multi = [{"id": "m1", "kind": "qa", "front": "Describe SLE",
          "bullets": ["Multisystem", "Autoimmune", "Relapsing"]}]
_, why_not = quiz_from_cards.build(multi + DECK, seed=1)
check("a multi-fact card makes no question",
      any(s["id"] == "m1" for s in why_not), why_not)

print("\nALL CARD QUALITY TESTS PASS" if not failures
      else "\n%d CARD QUALITY TEST FAILURE(S)" % len(failures))
sys.exit(1 if failures else 0)
