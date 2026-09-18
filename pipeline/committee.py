# -*- coding: utf-8 -*-
"""Run several recognisers over the SAME windows, so their words can be voted on.

Identical windowing is the part that matters. Two engines given different
segmentations produce transcripts that cannot be lined up word for word, and
the whole method depends on lining them up - so every engine here is fed the
exact spans transcribe.window_bounds chooses, one at a time.

Feeding whole windows is also what keeps Whisper honest. Run over long audio it
decodes conditioned on its own previous output and can spiral - on this lecture
it produced "Stable Diffusion", "DALL-E 3" and "BRCA1", none of which were said.
Given a single thirty-second window with that conditioning off, it is a useful
second opinion: on the reference window it got seven of the eight terms
phonetically right.
"""
import json, os, sys, time
import numpy as np, soundfile as sf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from transcribe import transcribe_windows, SR

COHERE = "NAMAA-Space/cohere-transcribe-arabic-07-2026-int8"
WHISPER = "openai/whisper-large-v3-turbo"
QWEN = "Qwen/Qwen3-ASR-1.7B-hf"


def _pipe(model, **kw):
    from transformers import pipeline
    return pipeline("automatic-speech-recognition", model=model, device=-1, **kw)


def _text(result):
    if isinstance(result, dict):
        return (result.get("text") or "").strip()
    return str(result).strip()


def cohere():
    asr = _pipe(COHERE)
    return lambda chunk: _text(asr({"raw": chunk, "sampling_rate": SR}))


def whisper():
    asr = _pipe(WHISPER)
    gen = {"language": "ar", "task": "transcribe", "condition_on_prev_tokens": False}

    def run(chunk):
        try:
            return _text(asr({"raw": chunk, "sampling_rate": SR}, generate_kwargs=gen))
        except TypeError:
            return _text(asr({"raw": chunk, "sampling_rate": SR}))
    return run


def qwen():
    asr = _pipe(QWEN)
    return lambda chunk: _text(asr({"raw": chunk, "sampling_rate": SR}))


ENGINES = {"cohere": cohere, "whisper-turbo": whisper, "qwen3-asr": qwen}


def main():
    shard = int(os.environ["SHARD"])
    shards = int(os.environ["SHARDS"])
    pad = float(os.environ.get("PAD", "10"))
    wanted = [e.strip() for e in os.environ.get("ENGINES", "cohere,whisper-turbo,qwen3-asr").split(",") if e.strip()]

    wav, _ = sf.read("job/full.wav", dtype="float32")
    if wav.ndim > 1:
        wav = wav.mean(axis=1)
    total = len(wav) / SR
    span = total / shards
    core_start, core_end = shard * span, min((shard + 1) * span, total)
    start = max(0.0, core_start - (pad if shard else 0.0))
    end = min(total, core_end + (pad if shard < shards - 1 else 0.0))
    piece = wav[int(start * SR):int(end * SR)]

    out = {"shard": shard, "shards": shards, "total_seconds": round(total, 2),
           "start": round(start, 2), "end": round(end, 2),
           "core_start": round(core_start, 2), "core_end": round(core_end, 2),
           "pad": pad, "engines": {}, "seconds": {}, "errors": {}}

    for name in wanted:
        t0 = time.time()
        try:
            recognise = ENGINES[name]()
            out["engines"][name] = transcribe_windows(piece, recognise)
        except Exception as exc:
            # One engine failing must not cost the run the others: a committee
            # of two still votes, and the error is recorded rather than hidden.
            out["errors"][name] = "%s: %s" % (type(exc).__name__, exc)
            out["engines"][name] = ""
        out["seconds"][name] = round(time.time() - t0, 1)
        print("%-14s %6.1fs  %5d words %s" % (name, out["seconds"][name],
                                              len(out["engines"][name].split()),
                                              out["errors"].get(name, "")))

    os.makedirs("out", exist_ok=True)
    json.dump(out, open("out/shard-%d.json" % shard, "w"), ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
