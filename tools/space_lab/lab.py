#!/usr/bin/env python3
"""Render the Space theme's bodies on Linux, from the real shader sources, so
their look can be judged and tuned before a Mac run.

    tools/space_lab/lab.py                    every body, at rest and dragged
    tools/space_lab/lab.py sun rocky          only these bodies
    tools/space_lab/lab.py --size 512 --out DIR

The shader modifiers (GraphShaderCatalog, through tools/shader_check.py's
stand-in for Metal) are compiled as C++ functions and run per pixel by a
small ray caster (scene.cpp) that places each body's pieces the way
GraphStyleKit and GraphStyleAnimator do: the body sphere (opaque, writing
depth), its disk or ring in the tilted frame, the lifted billboard glow,
beams and tails, all additive, and a few links. It is a stand-in, not
SceneKit: no bloom, no particles, no stars behind. Colours are converted
from SceneKit's linear space to sRGB as the screen shows them.

Writes <out>/<body>-<rest|dragged>.png and a labelled sheet.png. Needs
swiftc and clang++ (the Swift toolchain) and Python's PIL.
"""
import os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import shader_check  # noqa: E402

BODIES = ["blackHole", "sun", "rocky", "gasGiant", "pulsar", "comet"]


def metal(text):
    text = re.sub(r"\b(float|int|uint)([234])\(", r"mk_\1\2(", text)
    return re.sub(r"(?<![\w.])(\d+\.\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)(?![\w.])", r"\1f", text)


def shaders_header(work):
    out = [shader_check.HEADER]
    for name, entry, source in shader_check.dump(work):
        if entry != "surface":
            continue
        args, body, mode = [], [], "body"
        for line in source.split("\n"):
            s = line.strip()
            if s.startswith("#pragma arguments"):
                mode = "args"
                continue
            if s.startswith("#pragma body"):
                mode = "body"
                body = []
                continue
            if s.startswith("#pragma"):
                continue
            (args if mode == "args" else body).append(line)
        out.append(f"namespace sh_{name} {{")
        out.extend(metal(a) for a in args)
        out.append("void entry(SCNShaderSurface &_surface, const SCNNodeBuffer &scn_node, const SCNFrameBuffer &scn_frame) {")
        out.extend(metal(b) for b in body)
        out.append("}\n}")
    return "\n".join(out)


def main():
    args = sys.argv[1:]
    size, out = 420, os.path.join(os.getcwd(), "build", "space_lab")
    if "--size" in args:
        k = args.index("--size"); size = int(args[k + 1]); del args[k:k + 2]
    if "--out" in args:
        k = args.index("--out"); out = os.path.abspath(args[k + 1]); del args[k:k + 2]
    bodies = [a for a in args if a in BODIES] or BODIES
    os.makedirs(out, exist_ok=True)
    work = tempfile.mkdtemp()
    open(os.path.join(work, "shaders.h"), "w").write(shaders_header(work))
    exe = os.path.join(work, "lab")
    clang = shader_check.shutil.which("clang++") or "/opt/swift/usr/bin/clang++"
    built = subprocess.run([clang, "-O2", "-std=c++17", "-w", "-I", work, os.path.join(HERE, "scene.cpp"),
                            "-o", exe], capture_output=True, text=True)
    if built.returncode != 0:
        print(built.stderr[:4000])
        sys.exit("the lab did not build")
    from PIL import Image, ImageDraw
    tiles = []
    for b in bodies:
        for state in ("rest", "dragged"):
            ppm = os.path.join(work, f"{b}-{state}.ppm")
            subprocess.run([exe, b, state, str(size), ppm], check=True)
            png = os.path.join(out, f"{b}-{state}.png")
            Image.open(ppm).save(png)
            tiles.append((f"{b} {state}", png))
    cols = 4
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * size, rows * (size + 22)), (12, 12, 16))
    draw = ImageDraw.Draw(sheet)
    for k, (label, png) in enumerate(tiles):
        x, y = (k % cols) * size, (k // cols) * (size + 22)
        sheet.paste(Image.open(png), (x, y + 22))
        draw.text((x + 6, y + 5), label, fill=(230, 230, 230))
    sheet.save(os.path.join(out, "sheet.png"))
    print(os.path.join(out, "sheet.png"))


if __name__ == "__main__":
    main()
