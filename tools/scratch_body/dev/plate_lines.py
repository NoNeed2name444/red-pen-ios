"""plate_lines.py x0 y0 x1 y1 zoom out: the sutures as traced (plates.SUTURES_SIDE) drawn over Gray's side view (Fig. 188), with
the page's pixel grid, to check each traced line against the plate's own and to read better points off it."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import plates
from PIL import Image, ImageDraw
S = os.environ.get("SCRATCH_OUT", "/tmp/scratch_body_out")
x0, y0, x1, y1 = [int(a) for a in sys.argv[1:5]]; z = float(sys.argv[5]); out = sys.argv[6]
im = Image.open(S + "/gray1918/pages/p-0182.jpg").convert("RGB"); d = ImageDraw.Draw(im)
col = [(255, 120, 0), (0, 170, 0), (200, 0, 200), (0, 90, 255), (0, 170, 170), (255, 0, 0), (120, 60, 0), (255, 0, 140)]
for c, (k, v) in zip(col, plates.SUTURES_SIDE.items()):
    d.line([tuple(p) for p in v], fill=c, width=2)
    for p in v:
        d.ellipse([p[0] - 4, p[1] - 4, p[0] + 4, p[1] + 4], outline=c, width=2)
c = im.crop((x0, y0, x1, y1)).resize((int((x1 - x0) * z), int((y1 - y0) * z)), Image.LANCZOS); d = ImageDraw.Draw(c)
for gx in range((x0 // 100 + 1) * 100, x1, 100):
    d.line([((gx - x0) * z, 0), ((gx - x0) * z, c.size[1])], fill=(120, 160, 255), width=1); d.text(((gx - x0) * z + 3, 3), str(gx), fill=(0, 40, 200))
for gy in range((y0 // 100 + 1) * 100, y1, 100):
    d.line([(0, (gy - y0) * z), (c.size[0], (gy - y0) * z)], fill=(120, 160, 255), width=1); d.text((3, (gy - y0) * z + 3), str(gy), fill=(0, 40, 200))
c.save(out, quality=88); print(out, c.size)
