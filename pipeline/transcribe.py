# -*- coding: utf-8 -*-
"""Feed the recogniser whole windows; use VAD only to label speakers.

This module exists because of one measured mistake. The pipeline used to slice
audio at every pause and transcribe each speech region separately, which seemed
reasonable - it gave per-region timestamps and speaker labels for free. It also
cost the recogniser more than half its accuracy, and the reason is worth stating
plainly.

Cohere Transcribe Arabic is a Conformer encoder-decoder with a native window of
about thirty seconds. Given a whole window of Egyptian medical speech it writes
what it hears in Arabic letters - including English terms, spelled phonetically
- and repair.py turns those into the real terms. Given a two-second fragment it
has no context to work with, so it GUESSES, and it guesses in English:

    slice output : "al Melorange da Acute", "Phenomenal", "Spillers", "Squidrish"
    window output: mekocutinius ... elmarar reesh ... akyout ... reversibl

The second looks worse and is far better: every one of those is a phonetic
spelling that repair fixes exactly. The first looks like English and cannot be
fixed, because "Squidrish" is a confident wrong word rather than a misspelling.

Measured on the same 30 s clip (run 35303516265):

    whole window      0 English / 74 Arabic words  ->  8/8 terms after repair
    silence-cut 30 s  byte-identical to the above  ->  8/8 terms after repair
    VAD slices (24)   3/8 raw                      ->  5/8 terms after repair

The two window strategies produced byte-identical output on every window tested,
which also answers the consistency question: the model is deterministic, and
segmentation was the only thing making results move.
"""
import numpy as np

SR = 16000
# The model's native window. Going longer does not help and risks truncation
# inside the decoder; going shorter is exactly the mistake this module exists to
# undo.
WINDOW = 30.0
# How far back from a window edge to hunt for a quiet moment.
SEARCH = 3.0
FRAME = 0.1


def window_bounds(wav, sr=SR, window=WINDOW, search=SEARCH):
    """Split audio into ~`window`-second spans that end in the quietest nearby
    moment, so a window boundary never falls in the middle of a word.

    Returns [(start_seconds, end_seconds), ...] covering the whole file.
    """
    total = len(wav) / sr
    bounds, pos = [], 0.0
    frame = int(FRAME * sr)
    while pos < total:
        end = min(pos + window, total)
        if end < total:
            lo, hi = int(max(pos, end - search) * sr), int(end * sr)
            segment = wav[lo:hi]
            if len(segment) > frame:
                quietest, best = None, None
                for i in range(0, len(segment) - frame, frame // 2):
                    level = float(np.abs(segment[i:i + frame]).mean())
                    if quietest is None or level < quietest:
                        quietest, best = level, i
                if best is not None:
                    end = (lo + best) / sr
        if end <= pos:                     # never stall on a degenerate window
            end = min(pos + window, total)
        bounds.append((pos, end))
        pos = end
    return bounds


def transcribe_windows(wav, recognise, sr=SR, **kwargs):
    """Recognise the whole file, one window at a time.

    `recognise` takes a float32 array and returns text. Results are joined with
    spaces rather than newlines: a window boundary is an artefact of how the
    model is fed, not something the speaker did, so it must not become a
    paragraph break in the transcript.
    """
    pieces = []
    for start, end in window_bounds(wav, sr, **kwargs):
        chunk = wav[int(start * sr):int(end * sr)]
        if len(chunk) < int(0.2 * sr):
            continue
        text = (recognise(chunk) or "").strip()
        if text:
            pieces.append(text)
    return " ".join(pieces)


def speech_regions(wav, sr=SR):
    """Short-time energy VAD, kept for SPEAKER LABELLING ONLY.

    These regions are never used to slice audio for the recogniser. They exist
    so a diariser can say which stretches belong to someone other than the
    lecturer, which is what Step 1 rule 4 needs and all it needs.
    """
    win, hop = int(0.030 * sr), int(0.010 * sr)
    if len(wav) < win:
        return []
    n = 1 + (len(wav) - win) // hop
    frames = np.lib.stride_tricks.as_strided(
        wav, shape=(n, win), strides=(wav.strides[0] * hop, wav.strides[0])).copy()
    db = 20 * np.log10(np.sqrt((frames ** 2).mean(axis=1) + 1e-12) + 1e-12)
    floor, ceil = np.percentile(db, 10), np.percentile(db, 90)
    threshold = floor + 0.35 * max(ceil - floor, 6.0)

    voiced, regions, start = db > threshold, [], None
    for i, is_voiced in enumerate(voiced):
        t = i * hop / sr
        if is_voiced and start is None:
            start = t
        elif not is_voiced and start is not None:
            if t - start >= 0.30:
                regions.append((max(0.0, start - 0.25), t + 0.25))
            start = None
    if start is not None:
        regions.append((max(0.0, start - 0.25), len(wav) / sr))

    merged = []
    for region in regions:
        if merged and region[0] - merged[-1][1] <= 0.05:
            merged[-1] = (merged[-1][0], region[1])
        else:
            merged.append(region)
    return merged
