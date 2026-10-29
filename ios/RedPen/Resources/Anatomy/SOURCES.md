# The 3D anatomy atlas: sources, licences, credits

The anatomy atlas in the Sciences screens is drawn from these files (reader:
`Shared/Sciences/AnatomyAtlas.swift`). Every mesh comes from the Human
Reference Atlas's male reference organ set, which is CC BY 4.0. The files
here were made from the downloads below by `tools/anatomy_atlas.py`, which
says exactly how:

    python3 -I tools/anatomy_atlas.py --glb 3d-vh-m-united.glb \
        --crosswalk asct-b-3d-models-crosswalk.csv

The downloads themselves are not kept in the repository. The tool checks
both against the SHA-256 below, and the same inputs give the same bytes.

| File | What it holds |
|---|---|
| `anatomy.json` | The manifest: 32 parts and their 863 structures, each with a label, UBERON id (where the crosswalk's is right), tissue, group and whether it sits inside another |
| `<part>.atlas` | One part's meshes, simplified and quantised (format: the tool's docstring) |

The credit the app shows (Settings, Sources; `ContentSources.hraCredit`,
kept the same as this by a test):

"3D anatomy: 3D Reference Organ Set for Male, v1.10, by Kristen Browne and
Heidi Schlehlein, HuBMAP Human Reference Atlas
(https://doi.org/10.48539/HBM833.WZWN.425), CC BY 4.0, made from the Visible
Human Male, courtesy of the U.S. National Library of Medicine; labels from
the ASCT+B Tables to 3D Reference Object Library Mapping, v1.10, by Ellen M.
Quardokus, Heidi Schlehlein, Bruce W. Herr II and Katy Börner
(https://doi.org/10.48539/HBM626.BRWN.943), CC BY 4.0."

## Sources

### The meshes: 3D Reference Organ Set for Male, v1.10

- Page: https://humanatlas.io/3d-reference-library
- File: https://cdn.humanatlas.io/digital-objects/ref-organ/united-male/v1.10/assets/3d-vh-m-united.glb
  (241,633,636 bytes, SHA-256 `fae3ac193835e9e24cd13a0d0f11e6788183b290b0691b9b83ec81d907d94581`)
- Licence: Creative Commons Attribution 4.0 International (CC BY 4.0),
  https://creativecommons.org/licenses/by/4.0/ (stated in the release's
  metadata, https://cdn.humanatlas.io/digital-objects/ref-organ/united-male/v1.10/graph.json).
- Credit: Kristen Browne and Heidi Schlehlein. 2026. *3D Reference Organ Set
  for Male, v1.10*. HuBMAP Human Reference Atlas.
  https://doi.org/10.48539/HBM833.WZWN.425. Made from the Visible Human
  Male, courtesy of the U.S. National Library of Medicine (Spitzer et al.
  1996; Ackerman 1998). The brain is from the Allen human brain reference
  atlas (Ding et al. 2016), relicensed by HRA under CC BY 4.0 from v1.3
  of the brain model; the large intestine is from colonoscopy data by Arie
  Kaufman (Stony Brook University).
- Changes: each structure simplified to a triangle budget per part (about
  334,000 triangles in all, from 6.9 million), positions quantised to 16
  bits, normals left to the app. Surface patches lying on another structure
  (landmarks, impressions) and the spongy bone inside the pelvis are left
  out, as are the omentum and abdominal fat. The brain is mirrored left to
  right about its own middle: in the organ set every structure named left
  sits on the body's right (the Allen atlas's x axis was kept), so mirrored,
  each lies where its name says. Labels corrected where the crosswalk's was
  wrong for the mesh, among them three pairs whose sides are swapped (the
  renal arteries, the ends of the vas deferens, the thymus lobes); the list
  is in the tool, `CORRECTED`.

### The labels: ASCT+B Tables to 3D Reference Object Library Mapping, v1.10

- File: https://cdn.humanatlas.io/digital-objects/ref-organ/asct-b-3d-models-crosswalk/v1.10/assets/asct-b-3d-models-crosswalk.csv
  (SHA-256 `54622d7ba5c8df15d8655c2af5ad6ebece45b74f61d894167e6fd9db9e66be06`)
- Licence: CC BY 4.0.
- Credit: Ellen M. Quardokus, Heidi Schlehlein, Bruce W. Herr II and Katy
  Börner. 2026. https://doi.org/10.48539/HBM626.BRWN.943.
- Use: each mesh's label and UBERON id. UBERON itself is CC BY 3.0
  (http://purl.obolibrary.org/obo/uberon.owl, header `dcterms:license`).

## What is not here yet, and why

- The arm, hand, foot, skull and ribs: the reference organ set has none.
  CC BY 4.0 candidates were found (docs/sciences/sources.md): the NLM skull
  and eyes of the Visible Human (NIH 3D 3DPX-020591) and TotalSegmentator's
  CT masks (Zenodo, CC BY 4.0, with ten named muscles).
- Named muscles beyond the eye, larynx and rectus femoris: the only clean
  source is TotalSegmentator's ten.
- Peripheral nerves: no source passes the licence rule. Every rich set is
  derived from BodyParts3D or Z-Anatomy (CC BY-SA, refused by brief §23f) or
  is of unknown origin. They are to be drawn for the app itself.
