#!/usr/bin/env python3
"""Build a Red Pen flashcard deck as a PDF.

One question alone on a page, its answer on the very next page, so nothing is
spoiled while you test yourself. Pages carry the mode's own colour, the contents
index is made of real clickable links, and a picture is held back to the answer
page when it would give the answer away.

Where this runs
---------------
Not on the phone. iOS cannot execute Python, so the app builds its decks with
the Swift exporter (ios/RedPen/Shared/DeckPDF.swift), which produces the same
layout natively. This script is for everywhere else: a Mac, a server, or CI,
where it can be pointed at a folder of exported sets and left to run
unattended - which is what makes rebuilding a whole term's decks one command
rather than an afternoon.

Input is whatever the app's "Share as JSON" produces: one StudySet per file.

    python3 tools/deck_pdf.py sets/*.json --out decks/
    python3 tools/deck_pdf.py sets/ --out decks/ --combine "Internal Medicine"

Requires: playwright (`pip install playwright && playwright install chromium`)
and, for the link check, pypdf.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import html
import json
import re
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

# ---------------------------------------------------------------- the palette

# The mode tints, kept in step with the app's Theme.swift and DeckPalette.swift.
# One base colour per mode; everything else is derived, so a mode added later
# cannot end up with a palette nobody chose.
TINTS = {
    "mcq": (0.78, 0.16, 0.16),      # pen red
    "anki": (0.31, 0.36, 0.86),     # indigo
    "book": (0.10, 0.55, 0.50),     # teal
    "qa": (0.90, 0.49, 0.13),       # amber
    "osce": (0.20, 0.62, 0.35),     # green
    "narrate": (0.55, 0.32, 0.80),  # violet
}

MODE_LABEL = {"mcq": "MCQ", "anki": "Anki", "book": "Textbook",
              "qa": "Cases", "osce": "OSCE", "narrate": "Narrate"}


class Palette:
    def __init__(self, rgb):
        self.r, self.g, self.b = (min(1.0, max(0.0, c)) for c in rgb)

    @property
    def luminance(self):
        return 0.2126 * self.r + 0.7152 * self.g + 0.0722 * self.b

    def shade(self, amount=0.22):
        keep = 1 - amount
        return Palette((self.r * keep, self.g * keep, self.b * keep))

    def tint(self, amount=0.86):
        return Palette((self.r + (1 - self.r) * amount,
                        self.g + (1 - self.g) * amount,
                        self.b + (1 - self.b) * amount))

    @property
    def carries_white_text(self):
        """Whether white text can be read on this colour.

        Amber in particular is bright enough that white on it is close to
        unreadable in print, where there is no backlight to carry it. Measured
        rather than eyeballed, because "it looked fine on my screen" is how a
        printed page ends up illegible.
        """
        return self.luminance < 0.5

    @property
    def bar(self):
        return self if self.carries_white_text else self.shade(0.38)

    @property
    def hex(self):
        return "#%02X%02X%02X" % (round(self.r * 255), round(self.g * 255),
                                  round(self.b * 255))


# ------------------------------------------------------- the spoiler decision

STOP_WORDS = {
    "this", "that", "these", "those", "with", "from", "into", "which", "what",
    "when", "where", "there", "their", "them", "then", "than", "have", "been",
    "being", "does", "will", "would", "could", "should", "about", "above",
    "after", "before", "between", "because", "while", "also", "other", "each",
    "most", "more", "less", "some", "such", "only", "over", "under", "both",
    "figure", "image", "picture", "diagram", "slide", "page", "label",
    "labelled", "labeled", "shown", "show", "shows", "following",
    "patient", "case", "question", "answer", "true", "false", "none",
}

SPOILER_THRESHOLD = 0.34


def _singular(word: str) -> str:
    if word.endswith("ies") and len(word) > 4:
        return word[:-3] + "y"
    if word.endswith("ses") and len(word) > 4:
        return word[:-2]
    if word.endswith("s") and not word.endswith("ss") and len(word) > 4:
        return word[:-1]
    return word


def content_words(text: str) -> set[str]:
    folded = unicodedata.normalize("NFKD", text or "")
    folded = folded.encode("ascii", "ignore").decode().lower()
    out = set()
    for part in re.split(r"[^a-z0-9]+", folded):
        if len(part) >= 4 and part not in STOP_WORDS:
            out.add(_singular(part))
    return out


def giveaway(image_text: str, question: str, answer: str) -> set[str]:
    """The words in a picture that give the answer away.

    The comparison is against what the ANSWER says that the QUESTION does not.
    That qualifier is the whole trick: a kidney diagram captioned "kidney", on a
    question that already says kidney, reveals nothing; the same diagram
    captioned "membranous nephropathy" reveals everything.
    """
    shown = content_words(image_text)
    if not shown:
        return set()
    told = content_words(answer) - content_words(question)
    if not told:
        return set()
    revealed = shown & told
    if not revealed:
        return set()
    # For a short answer one word IS the answer, so any overlap counts.
    if len(told) <= 3:
        return revealed
    return revealed if len(revealed) / len(told) >= SPOILER_THRESHOLD else set()


def placement(image_text: str, question: str, answer: str) -> str:
    """Where a picture goes.

    Deliberately biased towards holding back. The two ways of being wrong cost
    very different amounts: a picture needlessly moved overleaf is a small
    annoyance, and a spoiled question is a card that can never test anything
    again.
    """
    return "answer" if giveaway(image_text, question, answer) else "question"


# ------------------------------------------------------------------- the deck

@dataclass
class Card:
    topic: str
    kind_label: str
    question: list          # list of block dicts
    answer: list
    subject: str
    mode: str
    number: int = 0
    image: str | None = None       # data URI
    image_text: str = ""           # what was read out of it, if anything
    image_side: str = "question"
    source: str | None = None


def _text(t):
    return {"type": "text", "text": t}


def _bullet(text, lead=None):
    return {"type": "bullet", "lead": lead, "text": text}


def _option(letter, text, correct):
    return {"type": "option", "letter": letter, "text": text, "correct": correct}


def _note(label, text):
    return {"type": "note", "label": label, "text": text}


def plain_of(blocks) -> str:
    out = []
    for b in blocks:
        if b["type"] == "note":
            out.append(b["label"])
        out.append(b.get("lead") or "")
        out.append(b.get("text") or "")
    return " ".join(x for x in out if x)


# A clinical stem almost always opens the same way, and those opening words say
# nothing about what the card is for.
STEM_OPENER = re.compile(
    r"^(a|an|the)\s+(\d+[\s-]*(year|month|week|day)[\s-]*old\s*)?"
    r"(man|woman|male|female|boy|girl|child|infant|patient|lady|gentleman)?\s*"
    r"(who\s+)?(presents?|presenting|attends?|is\s+brought|was\s+brought|comes?|reports?)?\s*"
    r"(to\s+(the\s+)?\w+\s*)?(with|complaining\s+of|of)?\s*",
    re.IGNORECASE)


def topic_from(text: str) -> str:
    """A short label for the contents index.

    Two things this must not do.

    It must not give the answer away. The index is read before the cards, so a
    label taken from the answer would hand the student the diagnosis for every
    card in one convenient list. Labels come from the QUESTION side only.

    It must not be the same for every card. Clinical stems open almost
    identically - "A 24-year-old man presents with..." - so taking the first
    few words collapses a whole deck into a single index row, which is the same
    as having no index at all. The opening clause is stripped first, and what
    is left is what the card is actually about.
    """
    cleaned = re.sub(r"\*\*(.+?)\*\*", r"\\1", text or "").replace("\n", " ").strip()
    if not cleaned:
        return "Untitled"

    # The ask is the last question in the stem: "Which congenital heart lesion
    # best explains this finding?" That sentence says what the card is for
    # without saying what the answer is, and it differs from card to card,
    # which is exactly what the opening clause of a clinical vignette does not.
    asks = re.findall(r"([^.?!]*\?)", cleaned)
    candidate = asks[-1].strip() if asks else ""
    if len(candidate.split()) < 3:
        candidate = STEM_OPENER.sub("", cleaned, count=1).strip(" ,.;:")
    if len(candidate.split()) < 2:
        candidate = cleaned

    # Openers that are pure scaffolding carry no meaning into an index row.
    candidate = re.sub(r"^(which|what|who|how|why|when|where)\s+(of\s+the\s+following\s+)?"
                       r"(is|are|was|were|would|will|does|do|did|best|most)?\s*",
                       "", candidate, count=1, flags=re.IGNORECASE)
    candidate = candidate.strip(" ,.;:?\u2018\u2019\u201c\u201d'\"")
    words = candidate.split() or cleaned.split()
    label = " ".join(words[:8])
    label = label[:1].upper() + label[1:]
    return label[:62] + "\u2026" if len(label) > 64 else label


def letter_for(i: int) -> str:
    return chr(65 + i) if 0 <= i < 26 else str(i + 1)


def split_book(markdown: str):
    """Pages at `#` / `##` headings; anything before the first is Introduction."""
    pages, title, body = [], "Introduction", []

    def flush():
        text = "\n".join(body).strip()
        if text:
            pages.append((title, text))

    for line in (markdown or "").split("\n"):
        if re.match(r"^#{1,2}\s+", line):
            flush()
            body.clear()
            title = re.sub(r"^#{1,2}\s+", "", line).strip()
            body.append(line)
        else:
            body.append(line)
    flush()
    return pages


def cards_for(study_set: dict) -> list[Card]:
    """Every mode reduced to question/answer pairs.

    Mirrors DeckBuilder.swift. Keeping the two in step matters: a deck built
    here and one built on the phone should be the same deck.
    """
    mode = study_set.get("kind", "mcq")
    subject = study_set.get("subject") or MODE_LABEL.get(mode, "Red Pen")
    images = study_set.get("images") or []
    out: list[Card] = []

    def picture(index):
        if index is None or index >= len(images):
            return None
        raw = images[index]
        return raw if raw.startswith("data:") else "data:image/png;base64," + raw

    if mode == "mcq":
        for q in study_set.get("questions", []):
            options = q.get("options", [])
            correct = q.get("correctIndex", 0)
            answer = [_option(letter_for(i), o, i == correct)
                      for i, o in enumerate(options)]
            if (q.get("explanation") or "").strip():
                answer.append(_note("Why", q["explanation"]))
            out.append(Card(
                topic=topic_from(q.get("stem", "")),
                kind_label="MCQ",
                question=[_text(q.get("stem", ""))] +
                         [_option(letter_for(i), o, False) for i, o in enumerate(options)],
                answer=answer, subject=subject, mode=mode,
                image=picture(q.get("imageIndex")), source=q.get("source")))

    elif mode == "qa":
        for c in study_set.get("qaCards", []):
            out.append(Card(
                topic=c.get("topic") or topic_from(c.get("stem", "")),
                kind_label="CASE" if c.get("type") == "case" else "RECALL",
                question=[_text(c.get("stem", ""))],
                answer=[_bullet(a) for a in c.get("answer", [])],
                subject=subject, mode=mode))

    elif mode == "osce":
        for checklist in study_set.get("osceChecklists", []):
            steps = checklist.get("steps", [])
            for i, step in enumerate(steps):
                question = [_text("You are starting this station. What is the first step?"
                                  if i == 0 else "What comes next?")]
                for done in steps[max(0, i - 3):i]:
                    question.append(_bullet(done))
                out.append(Card(topic=checklist.get("title", "Station"),
                                kind_label="STEP", question=question,
                                answer=[_bullet(step, lead=f"Step {i + 1}")],
                                subject=subject, mode=mode))

    elif mode == "book":
        for title, body in split_book(study_set.get("bookMarkdown", "")):
            out.append(Card(topic=title, kind_label="PAGE",
                            question=[_text(f"What do you remember about “{title}”?")],
                            answer=[_text(body)], subject=subject, mode=mode))

    elif mode == "narrate":
        for i, seg in enumerate(study_set.get("narrateSegments", [])):
            out.append(Card(topic=f"Line {i + 1}", kind_label="LINE",
                            question=[_text("Read this aloud, then check yourself.")],
                            answer=[_text(seg.get("text", ""))],
                            subject=subject, mode=mode))

    elif mode == "anki":
        # Anki exports as .apkg from the app - its schedule and occlusion masks
        # do not survive paper. Printed here only if explicitly asked for.
        for c in study_set.get("cards", []):
            answer = [_bullet(b) for b in c.get("bullets", [])]
            if (c.get("why") or "").strip():
                answer.append(_note("Why", c["why"]))
            out.append(Card(topic=topic_from(c.get("front", "")),
                            kind_label="IMAGE" if c.get("type") == "occlusion" else "RECALL",
                            question=[_text(c.get("front", ""))], answer=answer,
                            subject=subject, mode=mode,
                            image=picture(c.get("imageIndex")), source=c.get("source")))

    return out


def index_rows(cards: list[Card]):
    """One row per topic, consecutive cards collapsed into a range.

    Grouped rather than listed card by card, because an index of six hundred
    single entries is one nobody can use.
    """
    rows = []
    for card in cards:
        if rows and rows[-1]["topic"] == card.topic and rows[-1]["last"] == card.number - 1:
            rows[-1]["last"] = card.number
        else:
            rows.append({"topic": card.topic, "subject": card.subject,
                         "first": card.number, "last": card.number})
    for row in rows:
        row["range"] = (str(row["first"]) if row["first"] == row["last"]
                        else f"{row['first']}–{row['last']}")
    return rows


# ---------------------------------------------------------------- reading OCR

def read_image_text(data_uri: str) -> str:
    """What a picture says, if anything can be read out of it.

    Optional: without an OCR engine every picture reads as empty, which leaves
    it with the question - the same answer this gives for a photograph or a
    trace. So a missing dependency makes the deck no worse than one built
    without pictures in mind, it simply stops catching the labelled diagrams.
    """
    try:
        import io
        from PIL import Image  # type: ignore
        import pytesseract  # type: ignore
    except ImportError:
        return ""
    try:
        payload = data_uri.split(",", 1)[1]
        image = Image.open(io.BytesIO(base64.b64decode(payload)))
        return pytesseract.image_to_string(image)
    except Exception:
        return ""


# ------------------------------------------------------------------ the HTML

CSS = """
@page { size: A4; margin: 0 }
* { box-sizing: border-box; -webkit-print-color-adjust: exact; print-color-adjust: exact }
body { margin: 0; color: #1a1a1a;
       /* Nunito is the rounded face; ui-rounded picks up SF Pro Rounded when a
          Mac or an iPad opens the file, and the rest is an ordinary fallback so
          a machine with neither still prints something sane. */
       font-family: Nunito, ui-rounded, "SF Pro Rounded", "Hiragino Maru Gothic ProN",
                    Quicksand, -apple-system, "Helvetica Neue", Arial, sans-serif }
.page { width: 210mm; height: 297mm; overflow: hidden; page-break-after: always;
        display: flex; flex-direction: column; position: relative }
.bar { height: 12mm; flex: 0 0 auto; display: flex; align-items: center;
       justify-content: space-between; padding: 0 16mm; color: #fff;
       font-size: 8pt; font-weight: 800; letter-spacing: .14em }
/* A page of pure white with one coloured strip reads as a form. The ground
   carries the faintest wash of the mode's colour instead, which is enough to
   tell two decks apart on a desk without touching how the text prints. */
.page { background: var(--paper) }
.page::after { content: ""; position: absolute; left: 0; right: 0; top: 12mm;
               height: 1.1mm; background: linear-gradient(90deg,
               var(--accent), var(--soft)) }
.body { flex: 1 1 auto; padding: 9mm 16mm 0; display: flex; flex-direction: column;
        overflow: hidden }
.topic { font-size: 19pt; font-weight: 700; margin: 0 0 2mm; text-wrap: balance }
.sub { font-size: 8.5pt; color: #4a4a4a; margin: 0 0 3mm }
.chip { display: inline-block; font-size: 7pt; font-weight: 800; letter-spacing: .1em;
        padding: 1.6mm 3.6mm; border-radius: 3mm; background: var(--accent) !important;
        color: #fff !important }
.rule { height: .3mm; margin: 4mm 0 5mm }
.content { flex: 1 1 auto; overflow: hidden; background: #fff; border-radius: 4mm;
           padding: 6mm 7mm; box-shadow: 0 0 0 .25mm var(--soft) }
.q { font-size: 13.5pt; font-weight: 600; line-height: 1.55; color: #121212 }
.a { font-size: 13.5pt; line-height: 1.55; color: #121212 }
ul { margin: 0; padding: 0; list-style: none }
li { margin-bottom: 2.2mm; padding: 2mm 3mm 2mm 7mm; position: relative;
     background: var(--wash); border-radius: 2.4mm }
li::before { content: ""; position: absolute; left: 3mm; top: 3.6mm; width: 2mm;
             height: 2mm; border-radius: 50%; background: var(--accent) }
.lead { font-weight: 700; color: var(--deep) }
b, strong { color: var(--deep) }
/* The opening phrase of a bullet, up to its colon or dash: what the line is
   about, which is what the eye should land on first. */
.key { font-weight: 700; color: var(--deep) }
/* Every letter sits in a badge of exactly the same size, whatever the letter
   and however many lines the option runs to. The old treatment drew a box
   around the glyph itself, so a wide letter got a wide box and a narrow one a
   narrow box, and the column looked accidental. */
.opt { margin-bottom: 2.2mm; padding: 1.6mm 3mm 1.6mm 11mm; position: relative;
       border-radius: 2.4mm }
.opt .letter { position: absolute; left: 3mm; top: 1.4mm; width: 6.2mm; height: 6.2mm;
               border-radius: 50%; background: var(--soft); color: var(--deep);
               font-weight: 800; font-size: 10.5pt; display: flex;
               align-items: center; justify-content: center }
.opt.correct { font-weight: 700; background: var(--soft) }
.opt.correct .letter { background: var(--accent); color: #fff }
.note-label { font-size: 9pt; font-weight: 800; letter-spacing: .1em;
              color: var(--deep); margin-bottom: 1mm }
.note-text { font-size: 12pt; color: #2b2b2b }
.why { background: var(--wash); border-radius: 2.6mm; padding: 3mm 4mm; margin-top: 4mm;
       border-left: 1.2mm solid var(--accent) }
figure { margin: 0 0 5mm; text-align: center }
figure img { max-width: 100%; max-height: 95mm; object-fit: contain }
.answer figure img { max-height: 80mm }
.mark { position: absolute; right: 12mm; bottom: 14mm; font-size: 132pt;
        font-weight: 700; line-height: 1; user-select: none }
.foot { flex: 0 0 auto; height: 12mm; display: flex; align-items: center;
        justify-content: space-between; padding: 0 16mm; font-size: 8.5pt; color: #4a4a4a }
.foot .next { font-weight: 800; letter-spacing: .08em }
.foot .n { font-weight: 800; color: #fff; background: var(--accent); border-radius: 3mm;
            padding: .8mm 2.6mm }
.src { font-size: 8pt; color: #555; font-style: italic; margin-top: 3mm }

.cover .hero { height: 78mm; padding: 18mm 16mm 0; color: #fff }
.cover .hero .mode { font-size: 9pt; font-weight: 700; letter-spacing: .2em;
                     opacity: .85 }
.cover .hero h1 { font-size: 27pt; margin: 4mm 0 0; text-wrap: balance }
.cover .facts { padding: 12mm 16mm; display: flex; gap: 18mm }
.cover .facts .k { font-size: 7.5pt; font-weight: 700; letter-spacing: .12em;
                   color: #4a4a4a }
.cover .facts .v { font-size: 17pt; font-weight: 800; color: var(--deep) }
.cover .facts > div { background: #fff; border-radius: 3mm; padding: 4mm 6mm;
                      box-shadow: 0 0 0 .25mm var(--soft) }
.cover .note { margin-top: auto; padding: 0 16mm 16mm; font-size: 10pt; color: #4a4a4a }

.toc h2 { font-size: 16pt; margin: 0 0 5mm }
.cols { flex: 1 1 auto; display: flex; gap: 8mm; overflow: hidden }
.col { flex: 1 1 0; overflow: hidden }
.row { display: flex; justify-content: space-between; gap: 3mm; padding: 1.6mm 2.4mm;
       font-size: 10.5pt; color: #1a1a1a; text-decoration: none; border-radius: 1.8mm }
.row:nth-child(odd) { background: var(--wash) }
.row .n { font-variant-numeric: tabular-nums; font-weight: 800; color: var(--deep) }
.row .t { overflow: hidden; text-overflow: ellipsis; white-space: nowrap }
.sec { font-size: 7.5pt; font-weight: 800; letter-spacing: .1em; margin: 4mm 0 1.5mm }
"""


def esc(text) -> str:
    return html.escape(str(text or ""))


def inline(text: str) -> str:
    """`**bold**` only - everything else stays the characters somebody typed.

    Not a Markdown pass. Medical writing is full of underscores, brackets and
    leading numbers, and a full reader turns "T_max_" into italics and eats the
    underscores.

    Marked terms are set in the deck's colour by the stylesheet. That is the
    whole reason marking survives into print: a page in one uniform grey gives
    the eye nowhere to land, and what the student marked while writing the set
    is a decision already made about what matters - better than this code
    guessing which words look important.
    """
    return re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", esc(text))


# "Fixed splitting of S2: the classic finding" - the part before the colon says
# what the line is about.
LEAD_IN = re.compile(r"^([^:\u2013\u2014]{3,60})(:|\s\u2013|\s\u2014)\s+")


def with_key(text: str) -> str:
    """Colours a line's own lead-in, for cards that carry no marked terms.

    Without this, a set written without any marking prints as an undifferentiated
    block, which is exactly the page that is hard to revise from. With it, every
    line still has one thing the eye reaches first.
    """
    rendered = inline(text)
    if "<b>" in rendered:
        return rendered
    match = LEAD_IN.match(text or "")
    if not match:
        return rendered
    head, mark = match.group(1), match.group(2).strip()
    rest = (text or "")[match.end():]
    return (f'<span class="key">{esc(head)}</span>{esc(mark)} ' + inline(rest))


def answer_phrase(blocks) -> str:
    """The thing the card is actually testing, as the answer states it.

    On a card with no marked terms there is nothing for the stylesheet to
    colour, and an explanation then prints as a wall of one grey. The correct
    option is the one phrase on the page that is certainly the point, so its
    occurrences in the reasoning are what get picked out. This is used on the
    answer side ONLY - doing it on a question page would be the spoiler this
    whole layout exists to prevent.
    """
    for b in blocks:
        if b["type"] == "option" and b.get("correct"):
            return (b.get("text") or "").strip(" .")
    return ""


def emphasise(html_text: str, phrase: str) -> str:
    """Marks a phrase where it appears in already-escaped HTML."""
    if not phrase or len(phrase) < 4 or "<b>" in html_text:
        return html_text
    pattern = re.compile(re.escape(esc(phrase)), re.IGNORECASE)
    return pattern.sub(lambda m: f"<b>{m.group(0)}</b>", html_text)


def render_blocks(blocks, answer_side: bool) -> str:
    out, bullets = [], []

    def flush():
        if bullets:
            out.append("<ul>" + "".join(bullets) + "</ul>")
            bullets.clear()

    for b in blocks:
        kind = b["type"]
        if kind == "bullet":
            lead = f'<span class="lead">{inline(b["lead"])}</span>' if b.get("lead") else ""
            joiner = ": " if lead and b.get("text") else ""
            bullets.append(f"<li>{lead}{joiner}{with_key(b.get('text'))}</li>")
            continue
        flush()
        if kind == "text":
            out.append(f"<p>{inline(b['text'])}</p>")
        elif kind == "option":
            cls = "opt correct" if b["correct"] else "opt"
            out.append(f'<div class="{cls}"><span class="letter">{esc(b["letter"])}'
                       f'</span>{inline(b["text"])}</div>')
        elif kind == "note":
            body = with_key(b["text"])
            if answer_side:
                body = emphasise(body, answer_phrase(blocks))
            out.append(f'<div class="why"><div class="note-label">'
                       f'{esc(b["label"]).upper()}</div>'
                       f'<div class="note-text">{body}</div></div>')
    flush()
    return "\n".join(out)


def page_head(card: Card, pal: Palette, left: str, total: int) -> str:
    """The coloured bar, darker on an answer page.

    Two pages of a card are deliberately laid out identically, which left
    nothing to tell them apart at a glance in a stack of printed sheets. The
    depth of the bar is that signal: same hue, so the deck still reads as one
    thing, but a question and an answer are never mistaken for each other.
    """
    fill = pal.bar.shade(0.3) if left.lower() == "answer" else pal.bar
    return f"""
  <div class="bar" style="background:{fill.hex}">
    <span>{esc(left).upper()}</span><span>CARD {card.number}</span>
  </div>"""


def card_pages(card: Card, pal: Palette, total: int) -> str:
    """A question page and its answer page.

    The anchor sits on the heading inside the page, NOT on the page element
    itself: an element whose top edge is exactly on the page-break boundary can
    resolve to the PREVIOUS page, which would land a tapped index row on the
    previous card's answer - the one spoiler this whole layout exists to avoid.
    """
    dark, light = pal.shade(0.10).hex, pal.tint(0.80).hex
    chip_bg, chip_fg = pal.tint(0.84).hex, pal.shade(0.28).hex
    sub = f"{MODE_LABEL.get(card.mode, card.mode)} · Question {card.number} of {total}"
    figure = (f'<figure><img src="{card.image}"></figure>'
              if card.image else "")

    def heading(anchor: str = ""):
        ident = f' id="{anchor}"' if anchor else ""
        return f"""
    <div{ident}>
      <h1 class="topic" style="color:{dark}">{esc(card.topic)}</h1>
      <p class="sub">{esc(sub)}</p>
      <span class="chip" style="background:{chip_bg};color:{chip_fg}">{esc(card.kind_label)}</span>
      <div class="rule" style="background:{pal.tint(0.62).hex}"></div>
    </div>"""

    q_fig = figure if card.image_side == "question" else ""
    a_fig = figure if card.image_side == "answer" else ""
    src = f'<div class="src">{esc(card.source)}</div>' if card.source else ""

    return f"""
<section class="page" style="--accent:{pal.hex};--soft:{pal.tint(0.88).hex};--deep:{pal.shade(0.34).hex};--paper:{pal.tint(0.975).hex};--wash:{pal.tint(0.93).hex}">
  {page_head(card, pal, card.subject, total)}
  <div class="body">
    {heading(f"c{card.number}")}
    {q_fig}
    <div class="content q">{render_blocks(card.question, False)}</div>
  </div>
  <div class="mark" style="color:{light}">Q</div>
  <div class="foot"><span>Question {card.number} of {total}</span>
    <span class="next" style="color:{pal.shade(0.18).hex}">ANSWER OVERLEAF ›</span></div>
</section>
<section class="page answer" style="--accent:{pal.hex};--soft:{pal.tint(0.88).hex};--deep:{pal.shade(0.34).hex};--paper:{pal.tint(0.975).hex};--wash:{pal.tint(0.93).hex}">
  {page_head(card, pal, "Answer", total)}
  <div class="body">
    {heading()}
    {a_fig}
    <div class="content a">{render_blocks(card.answer, True)}{src}</div>
  </div>
  <div class="mark" style="color:{light}">A</div>
  <div class="foot"><span>{esc(card.subject)} · Answer {card.number}</span><span></span></div>
</section>"""


def build_html(title: str, cards: list[Card], pal: Palette) -> str:
    total = len(cards)
    rows = index_rows(cards)
    subjects = sorted({c.subject for c in cards})
    breakdown = "".join(
        f'<div><div class="k">{esc(s).upper()}</div>'
        f'<div class="v">{sum(1 for c in cards if c.subject == s)}</div></div>'
        for s in subjects)

    pages = "".join(card_pages(c, pal, total) for c in cards)
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><title>{esc(title)}</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700;800&display=swap">
<style>{CSS}</style></head>
<body>
<section class="page cover" style="--accent:{pal.hex};--soft:{pal.tint(0.88).hex};--deep:{pal.shade(0.34).hex};--paper:{pal.tint(0.975).hex};--wash:{pal.tint(0.93).hex}">
  <div class="hero" style="background:linear-gradient(135deg,{pal.bar.hex},{pal.bar.shade(0.4).hex})">
    <div class="mode">{esc(MODE_LABEL.get(cards[0].mode, 'RED PEN')).upper()}</div>
    <h1>{esc(title)}</h1>
  </div>
  <div class="facts">
    <div><div class="k">CARDS</div><div class="v">{total}</div></div>
    <div><div class="k">PAGES</div><div class="v">{total * 2 + 2}</div></div>
    {breakdown}
  </div>
  <div class="note">Every question sits alone on a page, with its answer overleaf
    — so nothing is spoiled while you test yourself.</div>
</section>
<div id="toc-target"></div>
{pages}
<script id="index-data" type="application/json">{json.dumps(rows)}</script>
<script>{INDEX_JS}</script>
</body></html>"""


# The index is paginated in the browser, not in Python: only the browser knows
# how tall a row is once it has been laid out, and guessing is how an index ends
# up cut off at the page edge.
INDEX_JS = r"""
(function () {
  const rows = JSON.parse(document.getElementById('index-data').textContent);
  const target = document.getElementById('toc-target');
  const accent = getComputedStyle(document.querySelector('.page')).getPropertyValue('--accent');
  let page = null, cols = null, col = null;

  function newPage() {
    page = document.createElement('section');
    page.className = 'page toc';
    // The contents page inherits the deck's colour variables from a card page,
    // since it is built here rather than in Python and has none of its own.
    const styled = document.querySelector('.page[style]');
    if (styled) page.setAttribute('style', styled.getAttribute('style'));
    page.innerHTML = '<div class="bar" style="background:' +
      document.querySelector('.bar').style.background +
      '"><span>CONTENTS</span><span></span></div>' +
      '<div class="body"><h2>Contents</h2><div class="cols"></div></div>' +
      '<div class="foot"><span></span><span></span></div>';
    target.parentNode.insertBefore(page, target);
    cols = page.querySelector('.cols');
    newCol();
  }
  function newCol() {
    if (cols.children.length >= 3) { newPage(); return; }
    col = document.createElement('div');
    col.className = 'col';
    cols.appendChild(col);
  }
  newPage();
  for (const row of rows) {
    const a = document.createElement('a');
    a.className = 'row';
    a.href = '#c' + row.first;
    a.innerHTML = '<span class="t">' + row.topic.replace(/[<&]/g, '') +
                  '</span><span class="n">' + row.range + '</span>';
    col.appendChild(a);
    // Back the row out and move on if it overflowed its column.
    if (col.scrollHeight > col.clientHeight) { col.removeChild(a); newCol(); col.appendChild(a); }
  }

  // Auto-fit, decided ONCE for the whole deck rather than card by card.
  //
  // Fitting each card on its own is what made the deck look unfinished: a card
  // with three lines was set at full size and the next one at two thirds of it,
  // so the type changed size every time a page was turned. One scale per side
  // - the smallest any card on that side needs - keeps every question page
  // identical to every other, which is the only way a deck reads as one thing.
  //
  // It still has to be a scale rather than a free-for-all: every card is
  // exactly two pages, and one answer spilling onto a third would print every
  // later question opposite the previous card's answer.
  const ladder = [1, .94, .88, .82, .76, .7, .64];
  const BASE = { q: 13.5, a: 13.5 };
  const picked = {}, stubborn = {};

  for (const side of ['q', 'a']) {
    const blocks = [...document.querySelectorAll('.content.' + side)];
    let chosen = ladder[0], failed = 0;
    for (const step of ladder) {
      failed = 0;
      for (const content of blocks) {
        content.style.fontSize = (step * BASE[side]) + 'pt';
        content.style.lineHeight = 1.55 - (1 - step) * 0.3;
        if (content.scrollHeight > content.clientHeight) failed++;
      }
      chosen = step;
      if (!failed) break;
    }
    // Settle on the step that was chosen, since the loop may have moved past it.
    for (const content of blocks) {
      content.style.fontSize = (chosen * BASE[side]) + 'pt';
      content.style.lineHeight = 1.55 - (1 - chosen) * 0.3;
    }
    picked[side] = chosen;
    stubborn[side] = failed;
  }

  window.__fit = { scale: picked, stubborn: stubborn.q + stubborn.a };
})();
"""


# ---------------------------------------------------------------- rendering

async def render(html_text: str, out: Path) -> dict:
    """HTML to PDF through headless Chromium.

    Chromium rather than weasyprint or wkhtmltopdf for two reasons: real CSS
    page control, and - the one that matters here - it converts `href="#c42"`
    into a genuine internal PDF link when it prints, with no link rectangles to
    compute by hand.
    """
    from playwright.async_api import async_playwright

    out.parent.mkdir(parents=True, exist_ok=True)
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page()
        await page.set_content(html_text, wait_until="networkidle")
        fit = await page.evaluate("window.__fit || {scale: {}, stubborn: 0}")
        await page.pdf(path=str(out), width="210mm", height="297mm",
                       print_background=True, margin={"top": "0", "bottom": "0",
                                                      "left": "0", "right": "0"})
        await browser.close()
    return fit


def add_outline(path: Path, title: str, cards: list[Card]) -> None:
    """Metadata and a bookmark outline, without breaking the links.

    `PdfWriter(clone_from=reader)` rather than looping `add_page` over the
    reader: the loop silently drops the catalog's /Dests entries, and every
    link in the index is left dangling with nothing to tell you it happened.
    """
    try:
        from pypdf import PdfReader, PdfWriter
    except ImportError:
        return
    reader = PdfReader(str(path))
    writer = PdfWriter(clone_from=reader)
    writer.add_metadata({"/Title": title, "/Creator": "Red Pen"})
    front = len(reader.pages) - len(cards) * 2
    seen = {}
    for i, card in enumerate(cards):
        if card.subject not in seen:
            seen[card.subject] = writer.add_outline_item(card.subject, front + i * 2)
        writer.add_outline_item(f"{card.number}. {card.topic}", front + i * 2,
                                parent=seen[card.subject])
    with path.open("wb") as handle:
        writer.write(handle)


def check(path: Path, cards: list[Card]) -> list[str]:
    """Pairing and links, checked on the file about to be handed over.

    Run AFTER the outline step, not before: that step is exactly what breaks
    the links when done wrong, so a check that ran only before it would pass
    while the delivered file was broken.
    """
    problems: list[str] = []
    try:
        from pypdf import PdfReader
    except ImportError:
        return ["pypdf not installed - pairing and links unverified"]

    reader = PdfReader(str(path))
    # Whitespace is stripped before matching. A PDF text extractor returns
    # glyphs in draw order, not reading order, so the watermark sitting over
    # the footer splits "Answer 11" into "Answer 1 1" - a check that matched on
    # the text as-is would report a perfectly good page as broken.
    pages = [re.sub(r"\s+", "", (p.extract_text() or "")).upper()
             for p in reader.pages]
    front = len(pages) - len(cards) * 2
    if front < 1:
        return [f"page count {len(pages)} cannot hold {len(cards)} cards"]

    for i, card in enumerate(cards):
        q, a = front + i * 2, front + i * 2 + 1
        if "ANSWEROVERLEAF" not in pages[q]:
            problems.append(f"card {card.number}: page {q + 1} is not a question page")
        if f"ANSWER{card.number}" not in pages[a]:
            problems.append(f"card {card.number}: page {a + 1} is not its answer")

    # Every destination, not a sample: eyeballing a few says nothing about the rest.
    try:
        # pypdf reports these with a leading slash; Chromium writes them
        # without one. Looking for only one spelling reports every link as
        # missing, which is a check that always "fails" and so tells you nothing.
        raw = reader.named_destinations
        dests = {k.lstrip("/"): v for k, v in raw.items()}
        index = {p.indirect_reference.idnum: n for n, p in enumerate(reader.pages)}
        # Only the cards the index actually links to: rows collapse a run of
        # cards on one topic into a single row, so a deck of eleven steps across
        # two stations has two links, not eleven. Demanding one per card
        # reports nine failures that are not failures.
        wanted = {row["first"] for row in index_rows(cards)}
        for i, card in enumerate(cards):
            if card.number not in wanted:
                continue
            name = f"c{card.number}"
            if name not in dests:
                problems.append(f"index link {name} has no destination")
                continue
            landed = index.get(dests[name].page.idnum)
            if landed != front + i * 2:
                problems.append(f"index link {name} lands on page "
                                f"{(landed or 0) + 1} but card {card.number} "
                                f"is on page {front + i * 2 + 1}")
    except Exception as error:                      # noqa: BLE001
        problems.append(f"link check could not run: {error}")
    return problems


# -------------------------------------------------------------------- driving

def load_sets(paths: list[str]) -> list[dict]:
    files: list[Path] = []
    for raw in paths:
        p = Path(raw)
        files.extend(sorted(p.glob("*.json")) if p.is_dir() else [p])
    out = []
    for f in files:
        try:
            out.append(json.loads(f.read_text()))
        except Exception as error:                  # noqa: BLE001
            print(f"  ! {f.name}: {error}", file=sys.stderr)
    return out


async def build(study_sets: list[dict], title: str, out: Path,
                with_ocr: bool) -> int:
    cards: list[Card] = []
    for s in study_sets:
        cards.extend(cards_for(s))
    if not cards:
        print("nothing to build", file=sys.stderr)
        return 1
    for i, card in enumerate(cards, start=1):
        card.number = i
        if card.image:
            card.image_text = read_image_text(card.image) if with_ocr else ""
            card.image_side = placement(card.image_text,
                                        plain_of(card.question),
                                        plain_of(card.answer))

    pal = Palette(TINTS.get(cards[0].mode, TINTS["mcq"]))
    fit = await render(build_html(title, cards, pal), out)
    add_outline(out, title, cards)
    problems = check(out, cards)

    held = sum(1 for c in cards if c.image_side == "answer")
    print(f"{out}")
    print(f"  {len(cards)} cards, {len(cards) * 2 + 2} pages")
    scale = fit.get("scale") or {}
    if scale:
        print(f"  set at {round(13.5 * scale.get('q', 1), 1)}pt questions, "
              f"{round(13.5 * scale.get('a', 1), 1)}pt answers"
              + (f" - {fit['stubborn']} card(s) still tight" if fit.get("stubborn") else ""))
    if held:
        print(f"  {held} picture(s) held back to the answer page")
    if not with_ocr and any(c.image for c in cards):
        print("  ! pictures were not read (--no-ocr), so none could be held back")
    for problem in problems:
        print(f"  ! {problem}")
    return 1 if problems else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("sets", nargs="+", help="exported .json sets, or folders of them")
    parser.add_argument("--out", default="decks", help="where to write the PDFs")
    parser.add_argument("--combine", metavar="TITLE",
                        help="one deck from every set, under this title")
    parser.add_argument("--no-ocr", action="store_true",
                        help="skip reading pictures; nothing can then be held back")
    args = parser.parse_args()

    study_sets = load_sets(args.sets)
    if not study_sets:
        print("no sets found", file=sys.stderr)
        return 1

    out_dir = Path(args.out)
    if args.combine:
        return asyncio.run(build(study_sets, args.combine,
                                 out_dir / (safe(args.combine) + ".pdf"),
                                 not args.no_ocr))
    worst = 0
    for s in study_sets:
        title = s.get("name") or "Red Pen deck"
        worst |= asyncio.run(build([s], title, out_dir / (safe(title) + ".pdf"),
                                   not args.no_ocr))
    return worst


def safe(name: str) -> str:
    return re.sub(r'[/\\:?%*|"<>]', "-", name).strip() or "deck"


if __name__ == "__main__":
    raise SystemExit(main())
