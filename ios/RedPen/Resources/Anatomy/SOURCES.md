# The 3D anatomy atlas: sources, licences, credits

The anatomy atlas in the Sciences screens is drawn from these files (reader:
`Shared/Sciences/AnatomyAtlas.swift`). It has two bodies, a man and a
woman. Most meshes come from the Human Reference Atlas's male and female
reference organ sets; the skull from NIH 3D's skull of the Visible Human
Male; the ribs, shoulder girdle, arm bones, hip and back muscles, thyroid,
adrenals, oesophagus and stomach from two TotalSegmentator CT scans. All
are CC BY 4.0. The files here were made from the downloads below by
`tools/anatomy_atlas.py` and `tools/anatomy_gaps.py`, which say exactly how:

    python3 -I tools/anatomy_atlas.py --male 3d-vh-m-united.glb \
        --female 3d-vh-f-united.glb --crosswalk asct-b-3d-models-crosswalk.csv \
        --skull 3DPX-020591.glb --ct <folder holding s1803/ and s1764/>

The downloads themselves are not kept in the repository. The tool checks
each against the SHA-256 below, and the same inputs give the same bytes.

| File | What it holds |
|---|---|
| `anatomy.json` | The manifest: the sources, then each body's parts (44 male, 45 female) and their structures (932 and 966), each with a label, UBERON id (where the crosswalk's is right), tissue, group and whether it sits inside another |
| `male-<part>.atlas`, `female-<part>.atlas` | One part's meshes in one body, simplified and quantised (format: the tool's docstring) |

Most parts are in both bodies. Only the woman's are the breasts, ovaries,
uterine tubes, uterus, vagina and their ligaments; only the man's the
prostate, the vas deferens and seminal vesicles, the urethra, the hyoid and
the muscles of the larynx. The woman's sternum is her organ set's; the
man's, which his organ set lacks, is from his scan.

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

and for what was added to them (`ContentSources.nihSkullCredit` and
`ContentSources.totalSegmentatorCredit`, kept the same by the same test):

"3D skull: Skull and Eyes - Visible Human Male (NIH 3D, 3DPX-020591,
https://3d.nih.gov/entries/3DPX-020591), by kbrowne, NLM 3D: Anatomy, CC BY
4.0, from the Visible Human Male, courtesy of the U.S. National Library of
Medicine."

"3D ribs, sternum, shoulder girdle, humeri, hip and back muscles, thyroid,
adrenals, oesophagus and stomach: meshed from scans s1803 and s1764 of the
TotalSegmentator dataset v3.0.0, by Jakob Wasserthal et al.
(https://doi.org/10.5281/zenodo.22688904; Wasserthal et al., Radiology:
Artificial Intelligence 2023, https://doi.org/10.1148/ryai.230024), CC BY
4.0."

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
  was kept), so mirrored, each lies where its name says; and, as the Allen
  brain is larger than either body's skull holds, it is scaled down (0.92
  for the man, 0.91 for the woman) about a point midway between the foot of
  the medulla and the optic chiasm, by the least that puts it inside the
  skull's inner table. Labels corrected
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

### The skull: Skull and Eyes - Visible Human Male (NIH 3D, 3DPX-020591)

- Page: https://3d.nih.gov/entries/3DPX-020591 (no DOI)
- File: its GLB, SHA-256
  `031179f6942df5ca89e675e6eb75859a2e9751c6046bcadde083708974345a43`
- Licence: CC BY 4.0, stated on the entry.
- Credit: kbrowne, NLM 3D: Anatomy. Segmented from the Visible Human Male's
  CT, courtesy of the U.S. National Library of Medicine: the same man as
  the male body.
- Changes: split into its bones (the entry names thirteen; "Pareital" read
  as parietal), the paired ones cut at the midline into left and right;
  simplified to about 27,000 triangles a body; the eyes and teeth left
  out, as the bodies have their own. Placed on the man by a similarity fit
  of its eyes and upper teeth to the body's, and on the woman by a smooth
  warp fitted on her head's skin, upper neck vertebrae, eyes and teeth.
  Where the skull would come within 2.5 mm of the skin, seen from the
  brain, it is moved in, smoothly, by at most 5 mm; where the brain still
  presses on the vault's inner table it is eased out by at most 4 mm.

### The rest of the skeleton, muscles and organs: TotalSegmentator dataset v3.0.0

- Record: https://zenodo.org/records/22688904,
  https://doi.org/10.5281/zenodo.22688904 (published 10 Sep 2026)
- File: `Totalsegmentator_dataset_v300.zip` (37,415,622,057 bytes, MD5
  `0728beea76475e92cdb3160e228265d1`, as the record lists it); only two
  scans' masks are read, s1803 (a man of 40) for the male body and s1764 (a
  woman of 32) for the female, the pair whose skeletons matched the bodies
  best among those judged. The manifest pins the masks used by the SHA-256
  of each scan's list of mask digests (`tools/anatomy_gaps.py`, `CT_SHA256`).
- Licence: CC BY 4.0, stated in the record's metadata.
- Credit: Jakob Wasserthal et al. *Dataset with segmentations of 117
  important anatomical structures in 1939 CT images*, v3.0.0. Zenodo.
  https://doi.org/10.5281/zenodo.22688904. The method: Wasserthal J, Breit
  H-C, Meyer MT, et al. TotalSegmentator: robust segmentation of 104
  anatomic structures in CT images. Radiology: Artificial Intelligence
  2023;5(5):e230024, https://doi.org/10.1148/ryai.230024.
- Use: the ribs and costal cartilages, the male body's sternum, the
  clavicles and scapulae, the humeri, gluteus maximus, medius and minimus,
  iliopsoas, the deep back muscles, the thyroid, the adrenals, the
  oesophagus and the stomach, in both bodies.
- Changes: each mask smoothed and meshed (marching cubes), simplified to
  the part's budget, and carried into its body by a smooth warp (thin-plate
  splines, fitted on the vertebrae, sacrum, hip bones, femurs, kidneys,
  liver, spleen, lungs, trachea, heart, brain, aorta and pancreas both
  have; the hip muscles by a closer warp of the pelvis). The rib cage is
  widened, smoothly around the chest's axis, until the organs sit inside
  it, but never past the skin, the shoulder girdle riding with it; each
  shoulder is then turned down about its sternoclavicular joint until the
  clavicle and scapula lie under the skin. Each humerus is scaled by the
  warp, its head set in the shoulder and its shaft laid along the skin's
  arm, epicondyles across it. Whatever still cut into an organ or bone is
  pushed out, smoothly, a few millimetres at a time.

### The labels: ASCT+B Tables to 3D Reference Object Library Mapping, v1.10

- File: https://cdn.humanatlas.io/digital-objects/ref-organ/asct-b-3d-models-crosswalk/v1.10/assets/asct-b-3d-models-crosswalk.csv
  (SHA-256 `54622d7ba5c8df15d8655c2af5ad6ebece45b74f61d894167e6fd9db9e66be06`)
- Licence: CC BY 4.0.
- Credit: Ellen M. Quardokus, Heidi Schlehlein, Bruce W. Herr II and Katy
  Börner. 2026. https://doi.org/10.48539/HBM626.BRWN.943.
- Use: each mesh's label and UBERON id. UBERON itself is CC BY 3.0
  (http://purl.obolibrary.org/obo/uberon.owl, header `dcterms:license`).

## What is not here yet, and why

- The forearm, hand and foot bones, in both bodies: neither the organ sets
  nor TotalSegmentator's masks have them. The CT volumes show the forearm;
  the CAD foot (Zenodo 5192130, CC BY 4.0) is admitted
  (docs/sciences/sources.md).
- Named muscles beyond the eye, larynx, rectus femoris, glutei, iliopsoas
  and the deep back muscles: no clean source has more.
- The pituitary and parathyroids: no clean mesh found yet.
- Peripheral nerves: no source passes the licence rule. Every rich set is
  derived from BodyParts3D or Z-Anatomy (CC BY-SA, refused by brief §23f) or
  is of unknown origin. They are to be drawn for the app itself.
- The man's sternum and the woman's hyoid, larynx muscles and urethra: the
  organ sets model them in one body only.
