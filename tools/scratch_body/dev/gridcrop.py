"""gridcrop.py <page jpg> <x0> <y0> <x1> <y1> <zoom> <out>: a crop of a plate with a labelled pixel grid (page pixels), for reading points off."""
import os
import sys
from PIL import Image, ImageDraw, ImageFont
p, x0, y0, x1, y1, zoom, out = sys.argv[1], *[int(a) for a in sys.argv[2:6]], float(sys.argv[6]), sys.argv[7]
step = int(sys.argv[8]) if len(sys.argv) > 8 else 50
im = Image.open(p).convert("RGB").crop((x0, y0, x1, y1))
im = im.resize((int(im.size[0] * zoom), int(im.size[1] * zoom)), Image.LANCZOS)
d = ImageDraw.Draw(im, "RGBA")
try: f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 13)
except OSError: f = ImageFont.load_default()
for x in range((x0 // step + 1) * step, x1, step):
    X = (x - x0) * zoom; d.line([(X, 0), (X, im.size[1])], fill=(0, 90, 255, 70 if x % (2 * step) else 120), width=1)
    if x % (2 * step) == 0: d.text((X + 2, 2), str(x), fill=(0, 60, 200, 255), font=f); d.text((X + 2, im.size[1] - 16), str(x), fill=(0, 60, 200, 255), font=f)
for y in range((y0 // step + 1) * step, y1, step):
    Y = (y - y0) * zoom; d.line([(0, Y), (im.size[0], Y)], fill=(0, 90, 255, 70 if y % (2 * step) else 120), width=1)
    if y % (2 * step) == 0: d.text((2, Y + 2), str(y), fill=(0, 60, 200, 255), font=f); d.text((im.size[0] - 40, Y + 2), str(y), fill=(0, 60, 200, 255), font=f)
im.save(out, quality=90); print(out, im.size)
