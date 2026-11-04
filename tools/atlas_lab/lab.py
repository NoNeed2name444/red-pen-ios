#!/usr/bin/env python3
"""Render the anatomy atlas on Linux, with the atlas's real surface modifiers,
so the look of its bone and muscle can be judged and tuned before a Mac run.

    tools/atlas_lab/lab.py                        every view
    tools/atlas_lab/lab.py skull-front pelvis     only these views
    tools/atlas_lab/lab.py --atlas DIR --size 640 --out DIR --plain --flat

A Swift reader (dump.swift, built with the app's AnatomyAtlas.swift) reads
each view's parts the way the app does, welding each part's structures into
one surface, and a small rasteriser (scene.cpp) draws them with the bone and
muscle modifiers (AtlasShaders, through tools/shader_check.py's stand-in for
Metal) under a stand-in for the atlas's light (AtlasLight): the key, the fill,
the studio's grey bands and screen-space occlusion. It is a stand-in, not
SceneKit: close in light and tone, not exact.

--atlas reads another atlas folder (a fresh build) in place of the app's;
--plain draws without the surface modifiers (the tissue's colour alone);
--flat leaves out the occlusion; --coarse leaves out the fine grain (the
Graphics budget's shaderDetail 0). Writes <out>/<view>.png and a labelled
sheet.png. Needs swiftc and clang++ (the Swift toolchain) and Python's PIL.
"""
import os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, ".."))
import shader_check  # noqa: E402

ATLAS = os.path.join(ROOT, "ios", "RedPen", "Resources", "Anatomy")
SKELETON = "skull,hyoid,sternum,ribs,shoulders,arms,vertebral-column,pelvis,legs"
# name: (body, parts, structures to frame (parts of names, or all), the eye's
# direction from them (x the body's left, y up, z forward), margin)
VIEWS = {
    "skull-front": ("male", "skull", "all", "0,0.05,1", 1.15),
    "skull-side": ("male", "skull", "all", "-1,0.1,0.25", 1.15),
    "skull-woman": ("female", "skull", "all", "-0.55,0.1,0.85", 1.15),
    "skull-woman-front": ("female", "skull", "all", "0,0.05,1", 1.15),
    "skull-woman-side": ("female", "skull", "all", "-1,0.1,0.25", 1.15),
    "pelvis": ("male", "pelvis,legs,vertebral-column", "sacrum,ilium,ischium,pubis,coccyx", "0,0.25,1", 1.1),
    "pelvis-woman": ("female", "pelvis,legs,vertebral-column", "sacrum,hip_,coccyx", "0,0.25,1", 1.1),
    "thigh": ("male", "pelvis,legs,hip-muscles,knee-muscles", "femur_R,rectus_femoris_R", "-0.55,0.1,0.85", 1.05),
    "hip-back": ("male", "pelvis,legs,hip-muscles,vertebral-column", "gluteus", "-0.2,0.15,-1", 1.1),
    "knee": ("male", "legs,knee-muscles", "patella_R", "-0.45,0.1,1", 2.6),
    "cheek": ("male", "skull", "zygomatic_bone_R", "-0.6,0.1,0.8", 2.2),
    "glute": ("male", "pelvis,legs,hip-muscles", "gluteus_maximus_R", "-0.6,0.1,-0.8", 0.75),
    "spine": ("male", "vertebral-column,pelvis", "lumbar_vertebra", "-0.8,0.15,0.6", 1.1),
    "spine-back": ("male", "vertebral-column,pelvis", "lumbar_vertebra,sacrum,coccyx", "0,0.1,-1", 1.1),
    "spine-side": ("male", "vertebral-column,pelvis,skull", "vertebra", "-1,0.05,0", 1.05),
    "lumbar": ("male", "vertebral-column", "lumbar_vertebra_3", "-0.6,0.5,-0.6", 1.6),
    "coccyx": ("male", "pelvis,vertebral-column", "coccyx,sacrum", "0.15,-0.2,-1", 1.3),
    "neck": ("male", "vertebral-column", "cervical_vertebra", "-0.8,0.1,-0.6", 1.15),
    "ribs-back": ("male", "vertebral-column,ribs", "thoracic_vertebra_5,thoracic_vertebra_6,thoracic_vertebra_7", "-0.35,0.3,-1", 1.6),
    "coccyx-woman": ("female", "pelvis,vertebral-column", "coccyx,sacrum", "0.15,-0.2,-1", 1.3),
    "spine-woman-back": ("female", "vertebral-column,pelvis", "lumbar_vertebra,sacrum,coccyx", "0,0.1,-1", 1.1),
    "spine-woman-side": ("female", "vertebral-column,pelvis,skull", "vertebra", "-1,0.05,0", 1.05),
    "jaw": ("male", "skull,mouth", "mandible", "-0.5,0.0,0.85", 1.5),
    "skull-top": ("male", "skull", "parietal,frontal,occipital", "0.1,1,0.25", 1.1),
    "skeleton": ("male", SKELETON, "all", "0,0.05,1", 1.02),
}


def metal(text):
    text = re.sub(r"\b(float|int|uint)([234])\(", r"mk_\1\2(", text)
    return re.sub(r"(?<![\w.])(\d+\.\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)(?![\w.])", r"\1f", text)


def shaders_header(work):
    """The atlas's surface modifiers as C++: namespace sh_<name>, its
    arguments as globals, its body as entry()."""
    out = [shader_check.HEADER]
    for name, entry, source in shader_check.dump(work):
        if entry != "surface" or not name.startswith("atlas"):
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


def build(work):
    swiftc = shutil.which("swiftc") or "/opt/swift/usr/bin/swiftc"
    clang = shutil.which("clang++") or "/opt/swift/usr/bin/clang++"
    # top-level code builds only from a main.swift
    shutil.copy(os.path.join(HERE, "dump.swift"), os.path.join(work, "main.swift"))
    reader = os.path.join(work, "reader")
    done = subprocess.run([swiftc, "-O", os.path.join(work, "main.swift"),
                           os.path.join(ROOT, "ios", "RedPen", "Shared", "Sciences", "AnatomyAtlas.swift"),
                           "-o", reader], capture_output=True, text=True)
    if done.returncode != 0:
        print((done.stdout + done.stderr)[:4000])
        sys.exit("the reader did not build")
    open(os.path.join(work, "shaders.h"), "w").write(shaders_header(work))
    exe = os.path.join(work, "lab")
    done = subprocess.run([clang, "-O2", "-std=c++17", "-w", "-I", work, os.path.join(HERE, "scene.cpp"),
                           "-o", exe], capture_output=True, text=True)
    if done.returncode != 0:
        print(done.stderr[:4000])
        sys.exit("the lab did not build")
    return reader, exe


def main():
    args = sys.argv[1:]
    size, out, atlas = 560, os.path.join(ROOT, "build", "atlas_lab"), ATLAS

    def option(flag):
        if flag in args:
            k = args.index(flag)
            value = args[k + 1]
            del args[k:k + 2]
            return value
        return None

    def switch(flag):
        if flag in args:
            args.remove(flag)
            return True
        return False

    size = int(option("--size") or size)
    out = os.path.abspath(option("--out") or out)
    atlas = os.path.abspath(option("--atlas") or atlas)
    plain, flat, coarse = switch("--plain"), switch("--flat"), switch("--coarse")
    views = [a for a in args if a in VIEWS] or list(VIEWS)
    os.makedirs(out, exist_ok=True)
    from PIL import Image, ImageDraw
    with tempfile.TemporaryDirectory() as work:
        reader, exe = build(work)
        tiles = []
        for v in views:
            body, parts, frame, eye, margin = VIEWS[v]
            dump = os.path.join(work, f"{v}.dump")
            subprocess.run([reader, atlas, body, dump, parts], check=True, capture_output=True)
            ppm = os.path.join(work, f"{v}.ppm")
            run = subprocess.run([exe, dump, ppm, str(size), str(size), eye, str(margin), frame,
                                  "0" if flat else "1", "0" if coarse else "1", "1" if plain else "0"],
                                 capture_output=True, text=True)
            if run.returncode != 0:
                print(run.stderr)
                sys.exit(f"{v} did not render")
            png = os.path.join(out, f"{v}.png")
            Image.open(ppm).save(png)
            print(f"{v}: {run.stdout.strip()}")
            tiles.append((f"{v} ({body})", png))
    cols = min(3, len(tiles))
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
