# -*- coding: utf-8 -*-
"""Turn a deck you already have into questions, using the deck as the distractors.

This is the one idea worth taking from how other study apps work: a quiz built
from YOUR existing cards rather than generated fresh from the lecture. Two
things follow from it, and both matter more than they sound.

The first is alignment. A question generated separately from the lecture text
can test something you never made a card for, so a wrong answer tells you
nothing about your deck. A question built from card 14 tests card 14.

The second is the distractors, which are the hard part of writing a question.
Invented distractors are the reason generated questions are easy: a model asked
for four wrong answers produces four obviously wrong answers, and you learn to
pick the plausible one without knowing the medicine. Here the wrong answers are
the RIGHT answers to other cards in the same deck - real terms, from the same
lecture, at the same level of detail. Getting it right means telling apart
things that genuinely belong to the same topic, which is what the exam asks.

Nothing is invented and nothing is phrased by a model: every option is text a
card already contains, so a question can never be more wrong than the deck it
came from.

Two things this gets wrong if written naively, both caught by its own tests:

  * the explanation. A card's "why" is written to be read next to its answer,
    so it says "it lowers flares and damage accrual" - which, pasted under a
    question, never tells you WHAT lowers them. The answer is put in front of
    it. That is composition, not invention: both halves are the card's;
  * the giveaway word. "Which antibody is the entry criterion?" with an answer
    containing "antibody" and four distractors that do not is answerable
    without knowing anything. The builder checks its own output with the same
    rules that judge any other question, and drops what fails rather than
    shipping a question you can win by reading. A shorter honest quiz beats a
    complete flattering one.
"""
import random
import re
from difflib import SequenceMatcher

from card_quality import CLOZE, check_mcq, terms

OPTIONS = 5
# Two answers this alike cannot both be on one question: one of them would be
# defensibly correct, and an unfair question teaches you to distrust the deck.
TOO_ALIKE = 0.8
# Tells that make a question answerable without the medicine. A near-duplicate
# is not one of them - a deck about one topic repeats itself, and that is the
# deck's business, not the question's.
FATAL = {"key-is-longest", "only-key-hedges", "stem-word-only-in-key",
         "absolute-in-key", "duplicate-option", "non-answer-option",
         "stem-not-a-question", "stem-too-thin", "option-count", "no-key"}


def answer_of(card):
    """The single thing a card is asking you to produce."""
    kind = card.get("kind", "qa")
    if kind == "cloze":
        holes = CLOZE.findall(card.get("clozeText") or "")
        # the first deletion is the card's subject; later ones are detail
        return holes[0][1].strip() if holes else ""
    bullets = [b.strip() for b in (card.get("bullets") or []) if b and b.strip()]
    if len(bullets) == 1:
        return bullets[0]
    # a multi-fact card has no single answer, so it makes no question
    return ""


def stem_of(card):
    kind = card.get("kind", "qa")
    if kind == "cloze":
        text = card.get("clozeText") or ""
        first = CLOZE.search(text)
        if not first:
            return ""
        # the sentence with the answer blanked, which reads as a question -
        # every hole with the first one's number, as Anki hides a repeated c1
        # together; otherwise the second one shows the answer
        number = first.group(1)
        blanked = CLOZE.sub(lambda m: "______" if m.group(1) == number else m.group(0), text)
        return CLOZE.sub(lambda m: m.group(2), blanked).strip()
    return (card.get("front") or "").strip()


def explain(answer, why):
    """The card's reasoning, with the thing it is reasoning about named.

    Both halves come from the card. Nothing is written here that the card did
    not already say.
    """
    why = (why or "").strip()
    if not why:
        return answer
    if terms(answer) & terms(why):
        return why                      # it already names the answer
    return "%s — %s" % (answer, lower_first_word(why))


NAMED = {"disease", "syndrome", "sign", "triad", "test", "reflex", "phenomenon",
         "criteria", "score", "classification", "law", "node", "palsy", "ulcer",
         "fracture", "tumour", "tumor", "manoeuvre", "maneuver", "lesion"}


def lower_first_word(text):
    """"Lowers flares" -> "lowers flares"; "ACE", "CT" and "Addison disease" keep their capitals."""
    word = re.match(r"[^\W\d_]*", text).group(0)
    if not word or not word[0].isupper():
        return text
    if word == "A":
        return "a" + text[1:]
    if len(word) < 2 or not word[1].islower():
        return text                     # an acronym, or "I"
    rest = text[len(word):]
    if rest.startswith("'s") or rest.startswith("\u2019s"):
        return text                     # an eponym
    following = re.match(r"[ -]*([^\W\d_]*)", rest).group(1).lower()
    if following in NAMED:
        return text
    return text[0].lower() + text[1:]


def alike(a, b):
    return SequenceMatcher(None, a.lower(), b.lower()).ratio()


def pick_distractors(answer, stem, pool, want):
    """Other cards' answers, nearest first, minus any that could also be right.

    Nearest first is deliberate. The useful wrong answer is the one you have to
    think to reject; a distractor from a different topic is free marks. A
    distractor sharing the stem's own vocabulary is better still, because it
    denies the question the shortcut of matching words.
    """
    stem_words = terms(stem)
    scored = []
    for other in pool:
        if not other or other.lower() == answer.lower():
            continue
        similarity = alike(answer, other)
        if similarity >= TOO_ALIKE:
            continue                      # could be marked correct too
        scored.append((len(terms(answer) & terms(other)),
                       len(terms(other) & stem_words), similarity, other))
    scored.sort(key=lambda s: (-s[0], -s[1], -s[2]))
    chosen, seen = [], set()
    for _, _, _, other in scored:
        if other.lower() in seen:
            continue
        # never two distractors that are near-twins of each other either
        if any(alike(other, c) >= TOO_ALIKE for c in chosen):
            continue
        chosen.append(other)
        seen.add(other.lower())
        if len(chosen) == want:
            break
    return chosen


def build(cards, seed=0, options=OPTIONS):
    """Returns (questions, skipped) - skipped says WHY, so a thin deck explains itself."""
    rng = random.Random(seed)
    answers = [answer_of(c) for c in cards]
    pool = [a for a in answers if a]
    questions, skipped = [], []

    for card, answer in zip(cards, answers):
        cid = card.get("id")
        stem = stem_of(card)
        if not answer:
            skipped.append({"id": cid, "why": "no single answer to ask for"})
            continue
        if not stem or len(stem.split()) < 3:
            skipped.append({"id": cid, "why": "nothing to make a stem from"})
            continue
        distractors = pick_distractors(answer, stem, pool, options - 1)
        if len(distractors) < options - 1:
            # Padding with invented text is exactly the failure this avoids.
            skipped.append({"id": cid, "why": "only %d usable distractors in this deck"
                                              % len(distractors)})
            continue
        choices = distractors + [answer]
        rng.shuffle(choices)
        question = {
            "id": "quiz-%s" % cid,
            "fromCard": cid,
            "stem": stem if stem.endswith("?") or "______" in stem
                    else stem.rstrip(".") + "?",
            "options": choices,
            "correctIndex": choices.index(answer),
            "explanation": explain(answer, card.get("why")),
        }
        # It must survive the same judgement as any other question. Anything
        # here is a question that can be answered without the medicine, and a
        # deck this small often cannot supply a distractor that fixes it.
        tells = sorted({p["rule"] for p in check_mcq(question)} & FATAL)
        if tells:
            skipped.append({"id": cid, "why": "gives itself away (%s)" % ", ".join(tells)})
            continue
        questions.append(question)
    return questions, skipped


if __name__ == "__main__":
    import json, os, sys
    spec = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "export/cards.json",
                          encoding="utf-8"))
    questions, skipped = build(spec.get("cards", []))
    print(json.dumps({"made": len(questions), "skipped": skipped},
                     ensure_ascii=False, indent=2))
    os.makedirs("results", exist_ok=True)
    json.dump({"mcq": questions}, open("results/quiz-from-cards.json", "w"),
              ensure_ascii=False, indent=2)
