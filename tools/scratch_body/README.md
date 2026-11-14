# The from-scratch body (tools/scratch_body)

The owner's order of 12 and 13 November: a full anatomy model built with no imported 3D model, from references only.
Everything here is computed. No mesh, scan or segmentation is read. Outlines and measures are read off the plates of
Gray's Anatomy, 20th edition, 1918 (public domain), and off its text, and each module's opening lines name the figures
and pages it follows.

So far: the skull, the upper and lower teeth and the lower jaw of the man, at half a millimetre. Not yet: the neck and
down, the muscles, the woman, the place in the app.

## How it is made

- A solid is a field of distances on a grid (`sdf.Field`): shapes are added and cut with soft joins, then the surface is
  meshed. The skull's left half is built and mirrored (`skull2.whole`); what must differ between the sides (the septum's
  bow, the midline sutures' wander, the grain and pits) goes on afterwards.
- Head frame, millimetres: origin midway between the two porions, the Frankfurt plane at y = 0, x to the body's left,
  y up, z forward.
- A relief is a height map laid on a surface (`relief.Map`, `relief.Slab`): the face, the base's under side, the palate,
  the pterygoid plates and the jaw's two faces are maps through points read off a plate.
- The surface's grain, pores and pits are `surface.roughen`; a suture on the midline wanders by `surface.wander_line`.
- `bones.py` tells the skull's bones apart (each its own part, the face's bones marked off by their sutures).

| Module | What it holds | Plates (Gray 1918) |
| --- | --- | --- |
| `skull2.py` | the skull: vault, face, orbits, cheek, base, cavity, the whole build | Fig. 187, 188, 189, 190, 196 |
| `base.py`, `foramina.py`, `occiput.py` | the under side of the base, its openings, the back of the head | Fig. 187, 194 |
| `temporal.py` | the side of the head: ear hole, arch, mastoid, styloid | Fig. 137, 188; p. 139 |
| `palate.py` | the roof of the mouth and the floor of the nose | Fig. 187 |
| `nose.py` | the septum and the scrolls | Fig. 187, 190, 195, 196; p. 194 |
| `pterygoid.py` | the two pterygoid plates, the hook, the pyramidal process | Fig. 189, 187, 147; pp. 151, 168 |
| `teeth.py`, `teeth2.py` | every tooth, kind by kind, crowns and roots | Fig. 1002 |
| `mandible4.py` (on `mandible.py`, `2`, `3`) | the lower jaw as one bone | Fig. 188, 176, 177, 190; pp. 172 to 174 |
| `surface.py`, `view.py` | grain and pits; the pictures | |
| `plates.py`, `landmarks.py`, `tracing.py` | the plates' scales and the points read off them | |

## Running it

The working scripts are in `dev/`. They write under `$SCRATCH_OUT` (default `/tmp/scratch_body_out`): fields and built
heads in `sb/`, pictures in `look/`. Gray's pages for the side-by-side pictures are expected in `gray1918/pages/`
(rendered from the 1918 edition's scan with `pdftoppm -r 300`, one page a file, `p-0186.jpg` for page 186).

```
python3 dev/try_skull.py 0.5 skull28 --teeth --jaw    # the whole head at 0.5 mm: about 5 minutes, 13 GB of memory
python3 dev/close.py skull28 palate                   # close pictures: face, base, ear, nose, ptery, palate, palcorner, maxilla
python3 dev/look_face.py skull28                      # the lower face beside Gray's front view
python3 dev/save_field.py 0.5 f05b                    # the skull's field alone (for sections and the bone split)
python3 dev/look_back.py f05b --field                 # the choanae and pterygoid plates, the skull behind them cut away
python3 dev/pt_cuts.py f05b                           # upright sections through the same region
python3 dev/try_bones.py f05b --mesh                  # the bones told apart
SCRATCH_SUPER=2 python3 dev/close.py skull28 face     # any picture drawn at twice the size and brought down
```

`make.py` is the older entry (bones as files with a manifest); it has not been brought up to the current modules.

## Checks the build prints

- upper teeth against the skull's bone and lower teeth against the jaw's: the least clearance, and how many points lie
  inside (0 at 0.5 mm in the build of 14 November);
- the lower jaw against the skull: least clearance 1.24 mm, at the joint (the aim is about 2);
- every opening of the base with its place and size, every relief with how far it lies from the points it was read from.

## What is known to be wrong or missing (14 November)

- The plates are a millimetre and more thick where real ones are half that: a sheet cannot be thinner than three cells
  of the grid.
- The jaw agrees with Gray's two plates, but it is a square jaw: its angle is about 112 degrees, the low end of the
  110 to 120 Gray gives for the adult (p. 177), and its lower border lies 16 degrees off the Frankfurt plane, where the
  orthodontists' norm is about 25 (Tweed's Frankfort-mandibular angle). Gray's front view is drawn from about 8 degrees
  above; seen dead level the jaw's sides look upright.
- The side of the head: the ear hole's rim is too even and the root of the cheek's arch is a lump.
- The orbit's fissures, the molars' crowns, the cranial floor and the temporal lines are plain or absent; the upper jaw
  is solid (no sinus).
- The bone split has not been run on the reshaped pterygoid region; the jaw is not yet one of its parts.
- Mesh checks (`check_mesh.py`, `check_parts.py`) have not been run on the current build.
