# The 3D anatomy atlas: sources, licences, credits

The anatomy atlas in the Sciences screens is drawn from these files (reader:
`Shared/Sciences/AnatomyAtlas.swift`). It has two bodies, a man and a
woman, and every mesh comes from the Human Reference Atlas's male and female
reference organ sets, which are CC BY 4.0. The files here were made from
the downloads below by `tools/anatomy_atlas.py`, which says exactly how:

    python3 -I tools/anatomy_atlas.py --male 3d-vh-m-united.glb \
        --female 3d-vh-f-united.glb --crosswalk asct-b-3d-models-crosswalk.csv

The downloads themselves are not kept in the repository. The tool checks
each against the SHA-256 below, and the same inputs give the same bytes.

| File | What it holds |
|---|---|
| `anatomy.json` | The manifest: the sources, then each body's parts (33 male, 35 female) and their structures (865 and 900), each with a label, UBERON id (where the crosswalk's is right), tissue, group and whether it sits inside another |
| `male-<part>.atlas`, `female-<part>.atlas` | One part's meshes in one body, simplified and quantised (format: the tool's docstring) |

Most parts are in both bodies. Only the woman's are the breasts, ovaries,
uterine tubes, uterus, vagina and their ligaments, and (as the organ sets
stand) the sternum; only the man's the prostate, the vas deferens and
seminal vesicles, the urethra, the hyoid and the muscles of the larynx.

The credit the app shows (Settings, Sources; `ContentSources.hraCredit`,
kept the same as this by a test):

"3D anatomy: 3D Reference Organ Sets for Male and for Female, v1.10, by
Kristen Browne and Heidi Schlehlein, HuBMAP Human Reference Atlas
(https://doi.org/10.48539/HBM833.WZWN.425 and
https://doi.org/10.48539/HBM637.DWBM.744), CC BY 4.0, made from the Visible
Human Male and Female, courtesy of the U.S. National Library of Medicine;
labels from the ASCT+B Tables to 3D Reference Object Library Mapping, v1.10,
by Ellen M. Quardokus, Heidi Schlehlein, Bruce W. Herr II and Katy Börner
(https://doi.org/10.48539/HBM626.BRWN.943), CC BY 4.0."

## Sources

### The man: 3D Reference Organ Set for Male, v1.10

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
  373,000 triangles in all, from 6.9 million), piece by piece and with its
  open edges kept where they are, so pieces that meet stay sealed (the
  lung's segments, the femur and its cartilage); positions quantised to 16
  bits, normals left to the app. Stray debris (pieces under a thousandth of
  their structure's surface), surface patches lying on another structure
  (landmarks, impressions) and the spongy bone inside the pelvis are left
  out; the patches that close the femur's lower end are folded back into
  the femur, and the spleen's diaphragmatic surface kept. The brain is
  mirrored left to right about its own middle: in the organ set every
  structure named left sits on the body's right (the Allen atlas's x axis
  was kept), so mirrored, each lies where its name says. Labels corrected
  where the crosswalk's was wrong for the mesh, among them three pairs whose
  sides are swapped (the renal arteries, the ends of the vas deferens, the
  thymus lobes); the list is in the tool, `CORRECTED`.

### The woman: 3D Reference Organ Set for Female, v1.10

- Page: https://humanatlas.io/3d-reference-library
- File: https://cdn.humanatlas.io/digital-objects/ref-organ/united-female/v1.10/assets/3d-vh-f-united.glb
  (SHA-256 `95f0c3d2f918582608692ca1139e8bdb18c147a16470e9ee9af8b276bd77c422`)
- Licence: CC BY 4.0, stated in the release's metadata
  (https://cdn.humanatlas.io/digital-objects/ref-organ/united-female/v1.10/).
- Credit: Kristen Browne and Heidi Schlehlein. 2026. *3D Reference Organ Set
  for Female, v1.10*. HuBMAP Human Reference Atlas.
  https://doi.org/10.48539/HBM637.DWBM.744. Made from the Visible Human
  Female, courtesy of the U.S. National Library of Medicine; the brain is
  the same Allen human brain reference atlas.
- Changes: as for the man (about 385,000 triangles in all), and the female
  liver's bare area kept, since its capsule is open there. The placenta,
  which the organ set places outside the body, is left out. Labels
  corrected where the crosswalk's was wrong for this mesh: the inferior
  pulmonary veins and round ligaments with their sides swapped, two liver
  segments, the left anterior descending artery, the dural sheaths, the
  hip bones and the fat of each breast; the sixth lumbar vertebra the
  Visible Human Female has is named as the normal variant it is.

### The labels: ASCT+B Tables to 3D Reference Object Library Mapping, v1.10

- File: https://cdn.humanatlas.io/digital-objects/ref-organ/asct-b-3d-models-crosswalk/v1.10/assets/asct-b-3d-models-crosswalk.csv
  (SHA-256 `54622d7ba5c8df15d8655c2af5ad6ebece45b74f61d894167e6fd9db9e66be06`)
- Licence: CC BY 4.0.
- Credit: Ellen M. Quardokus, Heidi Schlehlein, Bruce W. Herr II and Katy
  Börner. 2026. https://doi.org/10.48539/HBM626.BRWN.943.
- Use: each mesh's label and UBERON id. UBERON itself is CC BY 3.0
  (http://purl.obolibrary.org/obo/uberon.owl, header `dcterms:license`).

## What is not here yet, and why

- The arm, hand, foot, skull and ribs, in both bodies: the reference organ
  sets have none. CC BY 4.0 candidates were found (docs/sciences/sources.md):
  the NLM skull and eyes of the Visible Human (NIH 3D 3DPX-020591) and
  TotalSegmentator's CT masks (Zenodo, CC BY 4.0, with ten named muscles).
- Named muscles beyond the eye, larynx and rectus femoris: the only clean
  source is TotalSegmentator's ten.
- Peripheral nerves: no source passes the licence rule. Every rich set is
  derived from BodyParts3D or Z-Anatomy (CC BY-SA, refused by brief §23f) or
  is of unknown origin. They are to be drawn for the app itself.
- The man's sternum and the woman's hyoid, larynx muscles and urethra: the
  organ sets model them in one body only.
