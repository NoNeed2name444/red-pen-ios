# -*- coding: utf-8 -*-
"""What makes a generated card or question bad, checked before you memorise it.

A generated deck fails in ways that are invisible while you are using it,
because every one of them makes you feel like you are doing well:

  * a question you can answer from the SHAPE of the options rather than the
    medicine. The longest option is the key; the key is the only one hedged
    with "may" while the distractors say "always"; the key repeats a word from
    the stem. You score highly, learn nothing, and find out in the exam;
  * a card carrying three facts, so "again" on any one of them re-drills all
    three and the interval never settles;
  * a cloze that blanks so much of the sentence there is nothing left to cue
    recall - or blanks a word nobody needs to know;
  * two cards asking the same thing in different words, which quietly doubles
    the workload of a topic you already know.

Nothing here rewrites a card. Each rule reports, with the card's id and a
reason a person can check. Generators are wrong often enough that a silent
auto-fix just moves the error somewhere harder to see.

The rules are the standard ones for writing multiple-choice items - cover the
options and the stem should still be answerable, keep the options homogeneous,
avoid absolutes, no "all of the above" - plus the ones that come from watching
what language models actually produce, which is where the length tell and the
repeated-stem-word tell come from.
"""
import re
from difflib import SequenceMatcher

ABSOLUTES = ("always", "never", "all patients", "every patient", "none", "exclusively")
HEDGES = ("may", "can", "sometimes", "often", "usually", "generally", "typically")
NONANSWERS = ("all of the above", "none of the above", "both a and b",
              "a and b", "all of these", "none of these")
# a stem that is only a topic gives nothing to answer
TOPIC_ONLY = re.compile(r"^[\w\s\-/]{0,60}$")
STOPWORDS = {"the", "a", "an", "of", "in", "is", "are", "to", "and", "or", "with",
             "for", "by", "on", "at", "as", "that", "this", "it", "be", "which",
             "what", "most", "best", "following", "patient", "next", "step"}
CLOZE = re.compile(r"\{\{c(\d+)::(.+?)(?:::.*?)?\}\}")


def terms(text):
    return {w for w in re.findall(r"[a-z]{4,}", (text or "").lower())
            if w not in STOPWORDS}


def _problem(out, card_id, rule, detail):
    out.append({"id": card_id, "rule": rule, "detail": detail})


def check_mcq(q):
    """One question. Returns a list of problems, empty if it is sound."""
    out = []
    qid = q.get("id")
    stem = (q.get("stem") or "").strip()
    options = [(o or "").strip() for o in q.get("options", [])]
    correct = q.get("correctIndex")

    if len(options) != 5:
        _problem(out, qid, "option-count", "%d options, expected 5" % len(options))
    if correct is None or not (0 <= correct < len(options)):
        _problem(out, qid, "no-key", "correctIndex %r" % correct)
        return out
    key = options[correct]
    others = [o for i, o in enumerate(options) if i != correct]

    if len(set(o.lower() for o in options)) != len(options):
        _problem(out, qid, "duplicate-option", "two options say the same thing")
    for o in options:
        if o.lower() in NONANSWERS:
            _problem(out, qid, "non-answer-option", o)

    # Cover the options: a stem that is just a topic cannot be answered without
    # reading them, which tests recognition rather than recall.
    if not stem.endswith("?") and TOPIC_ONLY.match(stem):
        _problem(out, qid, "stem-not-a-question", stem[:80])
    if len(stem.split()) < 6:
        _problem(out, qid, "stem-too-thin", "%d words" % len(stem.split()))

    # The length tell: a key noticeably longer than every distractor is the
    # single most reliable way to pass a generated question without knowing
    # anything, because the model elaborates the answer it believes.
    if others and len(key) > 1.6 * max(len(o) for o in others) and len(key) > 40:
        _problem(out, qid, "key-is-longest",
                 "key %d chars, longest distractor %d" % (len(key), max(len(o) for o in others)))

    # The hedge tell, in both directions.
    if any(h in key.lower() for h in HEDGES) and not any(
            any(h in o.lower() for h in HEDGES) for o in others):
        _problem(out, qid, "only-key-hedges", key[:80])
    if any(a in key.lower() for a in ABSOLUTES):
        _problem(out, qid, "absolute-in-key", key[:80])

    # The clang tell: a content word that appears in the stem and in the key
    # and nowhere else.
    shared = terms(stem) & terms(key)
    elsewhere = set().union(*[terms(o) for o in others]) if others else set()
    giveaway = shared - elsewhere
    if giveaway:
        _problem(out, qid, "stem-word-only-in-key", ", ".join(sorted(giveaway))[:80])

    why = (q.get("explanation") or "").strip()
    if not why:
        _problem(out, qid, "no-explanation", "")
    elif not (terms(key) & terms(why)):
        # an explanation that never mentions the answer is usually an
        # explanation of a different question
        _problem(out, qid, "explanation-misses-the-key", why[:80])
    return out


def check_card(card):
    """One Anki card."""
    out = []
    cid = card.get("id")
    kind = card.get("kind", "qa")
    why = (card.get("why") or "").strip()

    if kind == "cloze":
        text = card.get("clozeText") or ""
        holes = CLOZE.findall(text)
        if not holes:
            _problem(out, cid, "cloze-without-a-deletion", text[:80])
            return out
        deleted = sum(len(h[1]) for h in holes)
        bare = CLOZE.sub(lambda m: m.group(2), text)
        if bare and deleted > 0.5 * len(bare):
            # nothing left to cue recall from
            _problem(out, cid, "cloze-swallows-the-sentence",
                     "%d of %d characters deleted" % (deleted, len(bare)))
        if len(set(h[0] for h in holes)) > 3:
            _problem(out, cid, "too-many-deletions",
                     "%d separate deletions" % len(set(h[0] for h in holes)))
        for _, hole in holes:
            if len(hole.split()) > 6:
                _problem(out, cid, "deletion-is-a-clause", hole[:60])
        return out

    front = (card.get("front") or "").strip()
    bullets = [b for b in (card.get("bullets") or []) if b and b.strip()]
    if not front:
        _problem(out, cid, "no-front", "")
    elif len(front.split()) < 3:
        _problem(out, cid, "front-too-thin", front)
    # One fact per card: the whole point of spaced repetition is that a single
    # "again" costs you one fact, not five.
    if len(bullets) > 4:
        _problem(out, cid, "too-many-facts", "%d bullets" % len(bullets))
    for b in bullets:
        if len(b.split()) > 30:
            _problem(out, cid, "bullet-is-a-paragraph", b[:60])
    if front and bullets and front.lower().rstrip("?") in " ".join(bullets).lower():
        _problem(out, cid, "front-appears-on-the-back", front[:60])
    if kind == "qa" and not bullets:
        _problem(out, cid, "no-answer", front[:60])
    if why and front and not (terms(front) | set().union(*[terms(b) for b in bullets])
                              if bullets else terms(front)) & terms(why):
        _problem(out, cid, "explanation-is-unrelated", why[:60])
    return out


def duplicates(items, key, threshold=0.86):
    """Pairs asking the same thing in different words.

    Measured on the QUESTION, not the answer: two cards with the same answer
    are often fine (many things cause anaemia), while two cards asking the same
    question are one card you will review twice forever.
    """
    found = []
    texts = [(it.get("id"), (key(it) or "").lower()) for it in items]
    for i in range(len(texts)):
        for j in range(i + 1, len(texts)):
            if not texts[i][1] or not texts[j][1]:
                continue
            score = SequenceMatcher(None, texts[i][1], texts[j][1]).ratio()
            if score >= threshold:
                found.append({"ids": [texts[i][0], texts[j][0]],
                              "rule": "near-duplicate", "detail": round(score, 3)})
    return found


def review(spec):
    """A whole set: {'mcq': [...]} and/or {'cards': [...]}."""
    problems = []
    questions = spec.get("mcq") or []
    cards = spec.get("cards") or []
    for q in questions:
        problems += check_mcq(q)
    for c in cards:
        problems += check_card(c)
    problems += duplicates(questions, lambda q: q.get("stem"))
    problems += duplicates(cards, lambda c: c.get("front") or c.get("clozeText"))
    return {"questions": len(questions), "cards": len(cards),
            "problems": problems, "clean": not problems}


if __name__ == "__main__":
    import json, sys
    spec = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "export/cards.json",
                          encoding="utf-8"))
    result = review(spec)
    for p in result["problems"]:
        print("%-28s %s" % (p["rule"], p.get("detail", "")))
    print(json.dumps({k: v for k, v in result.items() if k != "problems"}, indent=2))
