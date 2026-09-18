# -*- coding: utf-8 -*-
"""Turn a deck you already have into questions, using the deck as the distractors.

This is the one idea worth taking from how other study apps work: a quiz built
from YOUR existing cards rather than generated fresh from the lecture. Two
things follow from it, and both matter more than they sound.

The first is alignment. A question generated separately from the lecture text
can test something you never made a card for, so a wrong answer tells you
nothing about your deck. A question built from card 14 tests card 14.

The second is the distractors, which are the hard part of writing a question.
Invented distractors are the reason generated questions are easy: a model
asked for four wrong answers produces four obviously wrong answers, and you
learn to pick the plausible one without knowing the medicine. Here the wrong
answers are the RIGHT answers to other cards in the same deck - real terms,
from the same lecture, at the same level of detail. Getting it right means
telling apart things that genuinely belong to the same topic, which is what
the exam asks.

Nothing is invented and nothing is phrased by a model: every option is text a
card already contains, so a question can never be more wrong than the deck it
came from. Cards whose answers are too similar to tell apart are skipped
rather than turned into a question with two right answers.
"""
import random, re
from difflib import SequenceMatcher

from card_quality import CLOZE, terms

OPTIONS = 5
# Two answers this alike cannot both be on one question: one of them would be
# defensibly correct, and an unfair question teaches you to distrust the deck.
TOO_ALIKE = 0.8


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
        # the sentence with the answer blanked, which reads as a question
        blanked = text[:first.start()] + "______" + text[first.end():]
        return CLOZE.sub(lambda m: m.group(2), blanked).strip()
    return (card.get("front") or "").strip()


def alike(a, b):
    return SequenceMatcher(None, a.lower(), b.lower()).ratio()


def pick_distractors(answer, pool, want, rng):
    """Other cards' answers, nearest first, minus any that could also be right.

    Nearest first is deliberate. The useful wrong answer is the one you have to
    think to reject; a distractor from a different topic is free marks.
    """
    scored = []
    for other in pool:
        if not other or other.lower() == answer.lower():
            continue
        similarity = alike(answer, other)
        if similarity >= TOO_ALIKE:
            continue                      # could be marked correct too
        shared = len(terms(answer) & terms(other))
        scored.append((shared, similarity, other))
    scored.sort(key=lambda s: (-s[0], -s[1]))
    chosen, seen = [], set()
    for _, _, other in scored:
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
        distractors = pick_distractors(answer, pool, options - 1, rng)
        if len(distractors) < options - 1:
            # Padding with invented text is exactly the failure this avoids.
            skipped.append({"id": cid, "why": "only %d usable distractors in this deck"
                                              % len(distractors)})
            continue
        choices = distractors + [answer]
        rng.shuffle(choices)
        questions.append({
            "id": "quiz-%s" % cid,
            "fromCard": cid,
            "stem": stem if stem.endswith("?") or "______" in stem
                    else stem.rstrip(".") + "?",
            "options": choices,
            "correctIndex": choices.index(answer),
            # the card's own reasoning, not a new explanation: if the card was
            # right the question is right, and if it was wrong you see the same
            # wrong thing twice rather than two different wrong things
            "explanation": (card.get("why") or "").strip() or answer,
        })
    return questions, skipped


if __name__ == "__main__":
    import json, sys
    spec = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "export/cards.json",
                          encoding="utf-8"))
    questions, skipped = build(spec.get("cards", []))
    print(json.dumps({"made": len(questions), "skipped": skipped},
                     ensure_ascii=False, indent=2))
    json.dump({"mcq": questions}, open("results/quiz-from-cards.json", "w"),
              ensure_ascii=False, indent=2)
