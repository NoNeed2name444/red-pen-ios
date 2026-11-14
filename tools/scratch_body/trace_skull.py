"""trace_skull.py <pages folder>: take the outlines of the skull off its three plates and store them, in page
pixels, in traces/skull.json (a few hundred points each; nothing but lines of a flat picture)."""
import json, os, sys
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tracing as trace, plates

folder = sys.argv[1]
out = {}
for name, tol in (("side", 42), ("front", 42), ("base", 42)):
    a = np.asarray(Image.open(os.path.join(folder, "p-%04d.jpg" % plates.PAGES[name])).convert("RGB"))
    d = np.abs(a.astype(np.int16) - trace.paper(a)).sum(-1)
    m = trace.silhouette(d > tol, close=5, open_=6)
    o = trace.outline(m, 6.0)
    out[name + "_silhouette_px"] = np.round(o, 1).tolist()
    print(name, len(o), "points")
json.dump(out, open(os.path.join(plates.HERE, "traces", "skull.json"), "w"))
