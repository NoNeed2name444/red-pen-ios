# The 3D anatomy atlas: sources, licences, credits

The anatomy atlas in the Sciences screens is drawn from these files (reader:
`Shared/Sciences/AnatomyAtlas.swift`). It has two bodies, a man and a
woman. Most meshes come from the Human Reference Atlas's male and female
reference organ sets. The skull is NIH 3D's scan of the Visible Human
Male's skull, teeth and all, fitted onto each body's own skull meshed from
its head CT (the Visible Human Project, U.S. National Library of Medicine:
the organ sets were made from the same man and woman), and split into the
bones that skull's are named after, NIH 3D's skull of the Visible Human
Male. The vertebrae, sacrum and coccyx are scans of one dry skeleton's
(KA 25). The ribs, shoulder girdle, arm, hand and foot bones, the woman's
hip bones, the hip and back muscles, thyroid, adrenals, oesophagus and
stomach come from five TotalSegmentator CT scans. All are CC BY 4.0 but the
Visible Human CT, which NLM gives under its Terms and Conditions. The eyes
and their muscles, and the gluteus maximus, are made anew to the measures
of public-domain textbooks (below). The
files here were made from the downloads below by `tools/anatomy_atlas.py`,
`tools/anatomy_gaps.py`, `tools/anatomy_skull.py`,
`tools/anatomy_limbs.py`, `tools/anatomy_elbows.py`,
`tools/anatomy_feet.py`, `tools/anatomy_bones.py`,
`tools/anatomy_eyes.py`, `tools/anatomy_gluteus.py`,
`tools/anatomy_apart.py` and `tools/anatomy_fibres.py`, which say exactly
how:

    python3 -I tools/anatomy_atlas.py --male 3d-vh-m-united.glb \
        --female 3d-vh-f-united.glb --crosswalk asct-b-3d-models-crosswalk.csv \
        --skull 3DPX-020591.glb \
        --ct <folder holding s1803/, s1764/, s1880/, s1831/ and s1767/> \
        --vhct <folder holding male/ and female/, the head CT's slices> \
        --vhskull vhm_skull_0-nih3d.glb --ka25 <folder holding KA 25's OBJ files>

The downloads themselves are not kept in the repository. The tool checks
each against the SHA-256 below, and the same inputs give the same bytes.

Every mesh is simplified the same way: piece by piece, by quadric
decimation, gently first, so the triangles stay well shaped and the
surface shades smoothly (the most aggressive setting alone leaves fans of
thin triangles that shade as spikes), and harder only where a gentle pass
stops short of the budget.

| File | What it holds |
|---|---|
| `anatomy.json` | The manifest: the sources, then each body's parts (44 male, 45 female) and their structures (1030 and 1064), each with a label, UBERON id (the crosswalk's where it is right, else the corrected label's own, if any), tissue, group and whether it sits inside another |
| `male-<part>.atlas`, `female-<part>.atlas` | One part's meshes in one body, simplified and quantised (format: the tool's docstring) |
| `male-<part>.fibres`, `female-<part>.fibres` | For a part of muscles, where each point of each skeletal muscle lies round the muscle (the same all along a fibre) and how far it is tendon, for the muscle shader (made from the meshes alone by `tools/anatomy_fibres.py`; format: its docstring) |

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

and for what was added to them (`ContentSources.visibleHumanCredit`,
`ContentSources.nihSkullCredit`, `ContentSources.nihSkullScanCredit`,
`ContentSources.ka25Credit` and `ContentSources.totalSegmentatorCredit`,
kept the same by the same test):

"3D skull: each body's own, meshed from the Visible Human Project's CT of
the male and female heads
(https://www.nlm.nih.gov/research/visible/visible_human.html). Courtesy of
the U.S. National Library of Medicine."

"3D skull: Skull and Eyes - Visible Human Male (NIH 3D, 3DPX-020591,
https://3d.nih.gov/entries/3DPX-020591), by kbrowne, NLM 3D: Anatomy, CC BY
4.0, from the Visible Human Male, courtesy of the U.S. National Library of
Medicine."

"3D skull and teeth: Visible Human Male Skull (NIH 3D, 3DPX-012260,
https://3d.nih.gov/entries/3DPX-012260), by kbrowne, NLM 3D: Anatomy, CC BY
4.0, from the Visible Human Male, courtesy of the U.S. National Library of
Medicine."

"3D vertebrae, sacrum and coccyx: 3D model of the entire set of vertebrae
of human vertebral column (KA 25), by Natalya Prilepskaya, Ruslan Belyaev
and Alexander Kuznetsov, Department of Anthropology, Lomonosov Moscow State
University (https://doi.org/10.6084/m9.figshare.11879133.v2), CC BY 4.0."

"3D ribs, sternum, shoulder girdle, arm, hand and foot bones, the woman's
hip bones, the hip and back muscles, thyroid, adrenals, oesophagus and
stomach: meshed from scans
s1803, s1764, s1880, s1831 and s1767 of the TotalSegmentator dataset v3.0.0, by
Jakob Wasserthal et al.
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
  thymus lobes); the list is in the tool, `CORRECTED`. The ilium, ischium
  and pubis, which the crosswalk calls compact bone tissue, are named as
  the bones they are, with their own UBERON ids (`CORRECTED_UBERON`).
  Once the scanned spine is in (`tools/anatomy_bones.py`), each nucleus
  pulposus is named for the disc it lies in (the organ set names each a
  level down, two of them the wrong way round), the fourth lumbar disc,
  left with none, is given its neighbour's, laid into it; a disc is laid
  under the fifth lumbar vertebra, where the organ set has none (see KA
  25 below); and the rectum and the vessels about the sacrum are eased out
  of the scanned sacrum and coccyx (also there). The eyes and their
  muscles are made anew where the organ set put them (below). The ends
  of the vessels, ducts and gut, where the organ set cuts one open as it
  meets the next, are closed as a cut tube is, open and hollow
  (`tools/anatomy_apart.py`): where the organ set draws a tube with its
  lumen, the two rims of its wall are joined by a ring; where it draws
  only the outside, the end is given a wall as thick as its tissue's (an
  artery's an eighth of its radius, a vein's a fourteenth, a gut's 3 mm,
  none under 0.35 mm) and a lumen running in along the tube, sealed out
  of sight; a branch's mouth, cut out of a curved wall, is closed by a
  smooth sheet. A dome over each end was tried first and read as a solid
  stump. In the pelvis (from just
  above the iliac crests to below the ischial tuberosities) each
  structure is eased out of what it passes into: the organs and the gut
  off the bones and the discs, the vessels off those and off the organs
  (only a duct, or a vessel in its own organ, runs through one, as in the
  body), the ducts off all of these, each by a few millimetres at most
  and by a field smooth along the structure, so none is stretched or
  torn; and the hip muscles, which the vessels and organs lie against,
  grooved where they lie.

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
- Changes: as for the man (about 380,000 triangles in all), and the female
  liver's bare area kept, since its capsule is open there. The placenta,
  which the organ set places outside the body, is left out. Labels
  corrected where the crosswalk's was wrong for this mesh: the inferior
  pulmonary veins and round ligaments with their sides swapped, two liver
  segments, the left anterior descending artery, the dural sheaths, the
  ilia (called compact bone tissue there; each is the ilium alone, with
  no pubis or ischium, so the atlas shows her scan's whole hip bones in
  their place, below) and the fat of each breast; the sixth lumbar
  vertebra the Visible Human Female has is named as the normal variant it
  is. Once the scanned spine is in, the vessels about the sacrum are eased
  out of it (see KA 25 below); her eyes and the structures of her pelvis
  as the man's.

### The skull: the Visible Human Project's head CT (NLM)

- Page: https://www.nlm.nih.gov/research/visible/visible_human.html;
  files at https://data.lhncbc.nlm.nih.gov/public/Visible-Human/
  (`Male-Images/PNG_format/radiological/normalCT/`, and for the woman
  `Female-Images/PNG_format/radiological/normalCT/` with its headers in
  `normalCTHeaders/`).
- Files: the head's 291 slices of each body's normal CT, 1 mm apart from
  the top of the head down 290 mm, each a PNG with its scanner header: the
  man's `cvm1006f` to `cvm1296f` (`.png` and `.txt`), the woman's
  `cvf1001f.png` to `cvf1291f.png` with `c_vf1001.txt` to
  `c_vf1291.txt`; 582 files a body (73,323,233 and
  72,374,045 bytes), pinned by the SHA-256 of each body's list of file
  digests (`tools/anatomy_skull.py`, `VH_SHA256`).
- Terms: NLM's Terms and Conditions
  (https://www.nlm.nih.gov/databases/download/terms_and_conditions.html,
  which replaced the NLM Data License in July 2019): no charges, usage fees
  or royalties; NLM acknowledged as the source with the words "Courtesy of
  the U.S. National Library of Medicine"; no endorsement by NLM implied;
  what is made from the data says it may not reflect NLM's most current
  version of it.
- Credit: Courtesy of the U.S. National Library of Medicine.
- Changes (`tools/anatomy_skull.py`): the slices put on one grid (0.5 mm
  across, 1 mm down), each by its own pixel size and centre, a few corrupt
  pixels replaced and the dental fillings' streaks flattened; the bone
  (over 150 HU, joined to bone over 600 HU, inside the head) meshed;
  placed in its body first by the head's skin, then by the bone itself,
  laid on the NIH 3D model already fitted to that body (below); the
  model's jaw then fitted on its own (it is the one bone that moves) and
  the whole model bent onto the CT's thick bone (where the two match,
  moved by the difference, spread smoothly). The CT's bone is kept
  wherever it covers the model's surface or is 2 mm thick or more (but not
  beside the teeth, which would make their sockets' thin walls count as
  thick); where
  it is thinner and broken into lace or missing (the orbits' walls, the
  sinuses', which at 1 mm break up) the model's bone stands in; and the
  face's bones (the maxillae, zygomatic, nasal, lacrimal, ethmoid and
  palatine bones and the vomer, whose plates are too thin for a 1 mm CT)
  are the model's whole: for the man his own, segmented from the same CT,
  for the woman the man's, carried onto her. Blended over about a
  millimetre; thin specks far from the model left out. The surface
  smoothed without shrinking (Taubin's method, ten rounds), so the grid's
  steps go and the bone's own relief stays. Each surface point named by
  the nearest of the model's bones, the CT's teeth left out (the scanned
  skull below brings its own), the whole simplified to 80,000 triangles a body, and
  the borders between bones smoothed. Then, as before, kept under the
  skin and the brain sized to it. This skull is not drawn itself: it sets
  each body's skull's size, shape and place, and names its bones, for the
  scan of the same man's skull that takes its place (3DPX-012260, below).

### The skull's model and names: Skull and Eyes - Visible Human Male (NIH 3D, 3DPX-020591)

- Page: https://3d.nih.gov/entries/3DPX-020591 (no DOI)
- File: its GLB, SHA-256
  `031179f6942df5ca89e675e6eb75859a2e9751c6046bcadde083708974345a43`
- Licence: CC BY 4.0, stated on the entry.
- Credit: kbrowne, NLM 3D: Anatomy. Segmented from the Visible Human Male's
  CT, courtesy of the U.S. National Library of Medicine: the same man as
  the male body.
- Changes: the eyes left out, as the bodies have their own, and the
  teeth, as the scanned skull (3DPX-012260, below) has its own;
  placed on the man by a similarity fit of its eyes and upper teeth to the
  body's, and on the woman by a smooth warp fitted on her head's skin,
  upper neck vertebrae, eyes and teeth; then bent onto each body's own CT
  skull (above), whose bones it names (the entry names thirteen;
  "Pareital" read as parietal), whose thinnest plates it gives, and whose
  face's bones it gives whole. The
  skull's paired bones are cut at the midline into left and right. Where
  the skull would come within 2.5 mm of the skin, seen from the brain, it
  is moved in, smoothly, by at most 5 mm; where the brain still presses on
  the vault's inner table it is eased out by at most 4 mm.

### The skull's bone and teeth: Visible Human Male Skull (NIH 3D, 3DPX-012260)

- Page: https://3d.nih.gov/entries/3DPX-012260 (no DOI)
- File: `vhm_skull_0-nih3d.glb` (69,588,212 bytes, SHA-256
  `5520142d71db2fda58c6f7fb2ceefcac9f97a47aaaede40064d5741e2e363d9a`)
- Licence: CC BY 4.0, stated on the entry.
- Credit: kbrowne, NLM 3D: Anatomy. The 3D print file of the Visible Human
  Male's skull, segmented from his CT, courtesy of the U.S. National
  Library of Medicine: the same man as the male body, his skull whole and
  closed, the teeth in their sockets.
- Changes (`tools/anatomy_bones.py`): eight triangles of debris left out;
  the cranium and the mandible simplified gently to 90,000 and 16,000
  triangles; each placed on the body's own skull from its CT (above) by
  the similarity that best lays it there (within 4.3 mm on average on the
  man, 4.9 mm on the woman, where the CT's thin bone differs most; the
  mandible within 1.8 and 2.5 mm); for the woman, bent onto her skull by
  a field smooth through space (from 20 mm down to 8 mm), so her skull's
  size and shape are taken and the scan's detail kept; turned to the
  body's plane of symmetry, and its sides evened out by a smooth field
  (the man's cranium's halves from 1.5 to 1.2 mm apart on average, his
  mandible's from 2.3 to 1.1 mm; the woman's from 1.7 to 1.2 and 1.9 to
  1.1 mm), the teeth keeping their own shapes. The teeth are
  found by their height above each jaw's biting surface (a crown and the
  little root a dry skull shows, by place in the arch) and put in place of
  the organ sets' tooth rows, under the same names; the bones are split
  along the scan's own sutures and folds into the CT skull's bones (the
  names 3DPX-020591 gives), the two sides alike, the woman's split the
  man's.

### The vertebrae, sacrum and coccyx: KA 25 (figshare)

- Page: https://doi.org/10.6084/m9.figshare.11879133.v2 (version 2,
  published 4 Dec 2021)
- Files: the OBJ of each bone used (C1 to C7, T1 to T6, T8 to T13, L1 to
  L5, Sacrum, Coccyx1 and Coccyx2-4: 27 files, 1,755,781,322 bytes), each
  checked against the MD5 the item lists (`tools/anatomy_bones.py`,
  `KA25_MD5`); the manifest pins them by the SHA-256 of that list. The
  textures are not used.
- Licence: CC BY 4.0, stated on the item.
- Credit: Natalya Prilepskaya, Ruslan Belyaev and Alexander Kuznetsov.
  2020. *3D model of the entire set of vertebrae of human vertebral column
  (KA 25)*. figshare. https://doi.org/10.6084/m9.figshare.11879133.v2.
  One dry skeleton of the Department of Anthropology, Lomonosov Moscow
  State University, scanned with an Artec Space Spider at 0.15 mm.
- Changes (`tools/anatomy_bones.py`): each bone simplified (first to
  60,000 triangles, then gently to a triangle per 2.5 mm² of its placed
  surface, as the skull's, and never under 1,000) and placed on the
  organ set's own vertebra by the similarity that best lays it there
  (scaled by 1.04 to 1.23; within 1.4 to 2.6 mm on average, the sacrum
  within 4.25 mm on the man and 3.55 mm on the woman). The skeleton has thirteen thoracic vertebrae, so the
  bodies' seventh to twelfth are its eighth to thirteenth; the woman has
  six lumbar vertebrae (the Visible Human Female's normal variant), so her
  third and fourth are both its third. The coccyx's two pieces (its first
  segment, and the second to fourth fused) were scanned with the sacrum,
  in its frame, so the sacrum's similarity places them on its tip. The
  sacrum is then seated by its joints, the coccyx carried with it: the
  man's, which that fit laid 32 mm under his fifth lumbar vertebra (his
  organ set has no disc there), is moved, not turned, until S1's top lies
  11 mm under the vertebra's lower endplate, centred under it; in both
  bodies it is widened evenly across the body (by 1.137 in the man, 1.149
  in the woman) and moved sideways, then bent by a field smooth through
  space (10 mm), so its auricular surfaces lie 2.5 mm from the ilia. The
  woman's sacrum still crossed her hip bones at the back of its joints
  (145 of its points), so it is then drawn out of them there
  (`tools/anatomy_apart.py`): each point inside marched out along the
  surface's inward normal, the moves spread smoothly over 4 mm, until it
  lies a joint's width (1 mm) off them (moved by up to 4.2 mm, no points
  left). The man's crosses his organ set's ilia (276 of its points)
  and is left as it is: drawn out, some of its edges would stretch past
  1.5 times their length (wanted: his hip bones from his own CT, as the
  woman's are from hers). Where the last lumbar vertebra's facets and the
  sacrum's then ran into each other (by up to 6 mm in the man), the
  sacrum is pushed out of the vertebra, then the vertebra out of the
  sacrum, each by a field smooth over 6 mm, to a joint's width (1 mm).
  KA 25's lumbar bodies are flatter than the man's (L3 to L5 2 to 5.5 mm
  shorter), so the spaces between his placed vertebrae came out up to
  18.4 mm, where his organ set's discs are 7 to 14 mm: where a space is more
  than 2 mm taller than the mean of the body's lumbar discs, the vertebrae
  are stretched along the column, each endplate moved out along its
  vertebra's axis, each vertebra by at most 15% of its height (the last
  one's lower endplate held, as the sacrum is seated by it): his spaces
  now 8.3 to 12.8 mm. A disc is laid under the man's fifth lumbar vertebra,
  where his organ set has none (the one above carried into the space),
  and then every disc of both bodies is made anew between the scanned
  bones above and below it: its faces on their endplates, its wall from
  rim to rim, its nucleus pulposus a lens within it. The organ sets'
  discs, fitted to their own vertebrae, overhung the scanned bodies by up
  to 7 mm in front and stood up to 4 mm off them. The hip
  and back muscles, and the gut and vessels about the sacrum, are then
  moved out of the new bones by the field that pushes the
  TotalSegmentator parts out of what they cut into, here spread over
  15 mm by the surface each point stands for, each round's pull scaled
  alike, so a muscle the widened sacrum runs into slides off it without a
  crease; the gut and vessels off the sacrum, coccyx, last lumbar
  vertebra and the disc under it, each patch a bone runs into sliding off
  it one way, from the bone to the soft part about it (the man's rectum,
  its back wall eased forward along the sacrum's curve), and what is
  still inside a bone then pushed out. An organ set's mesh by the sacrum
  is coarse (the man's rectum has triangles up to four centimetres
  across, one through the coccyx's tip), so where a bone meets one the
  mesh is cut finer there (its edges split); a part of the gut a bone
  meets is first cut finer wherever the field reaches it, each new point
  then moved along its normal to where the surface through the old points
  bends least, so the old triangles' edges leave no creases. The gut and
  vessels near the seat move as one, so a vein stays joined to the next.
  With the hip bones
  as they are (the man's lean 8.5 degrees forward of Gray's erect
  posture, the woman's 3), the man's pelvic inlet and outlet then lie at
  61 and 15 degrees to the horizontal in that posture (Gray's: 50 to 60,
  and about 15), the woman's at 52 and 8.

### The rest of the skeleton, muscles and organs: TotalSegmentator dataset v3.0.0

- Record: https://zenodo.org/records/22688904,
  https://doi.org/10.5281/zenodo.22688904 (published 10 Sep 2026)
- File: `Totalsegmentator_dataset_v300.zip` (37,415,622,057 bytes, MD5
  `0728beea76475e92cdb3160e228265d1`, as the record lists it); five scans
  are read: s1803 (a man of 40) for the male body and s1764 (a woman of 32)
  for the female, the pair whose skeletons matched the bodies best among
  those judged, their masks; for the forearms and hands the CT itself of
  s1764 and of s1880 (a man of 37), as s1803's hands lie outside its field
  of view; for the elbows the CT of s1764 and of s1831 (a man of 33), as
  s1880's olecranon lies outside its; and for the feet the CT of s1764 and
  of s1767 (a man of 56), as s1803's and s1880's scans end above the
  toes. The manifest pins the files used by the SHA-256 of each scan's
  list of file digests
  (`tools/anatomy_gaps.py`, `CT_SHA256`).
- Licence: CC BY 4.0, stated in the record's metadata.
- Credit: Jakob Wasserthal et al. *Dataset with segmentations of 117
  important anatomical structures in 1939 CT images*, v3.0.0. Zenodo.
  https://doi.org/10.5281/zenodo.22688904. The method: Wasserthal J, Breit
  H-C, Meyer MT, et al. TotalSegmentator: robust segmentation of 104
  anatomic structures in CT images. Radiology: Artificial Intelligence
  2023;5(5):e230024, https://doi.org/10.1148/ryai.230024.
- Use: the ribs and costal cartilages, the male body's sternum, the
  female body's hip bones, the clavicles and scapulae, the humeri, the radius, ulna, carpal bones (as
  one structure), metacarpals and phalanges of each forearm and hand, the
  tarsal bones, metatarsals, phalanges and the great toe's two sesamoids
  (as one structure) of each foot, gluteus medius and minimus, iliopsoas,
  the deep back muscles, the thyroid, the adrenals, the oesophagus and the
  stomach, in both bodies. The scan's gluteus maximus is carried through
  the build, then replaced by one made from its attachments (below): the
  scan's is an oval pad over the buttock that stops short of the femur.
- Changes: each mask smoothed and meshed (marching cubes), simplified to
  the part's budget, and carried into its body by a smooth warp (thin-plate
  splines, fitted on the vertebrae, sacrum, hip bones, the femurs' tops
  and the centres of their heads, kidneys, liver, spleen, lungs, trachea,
  heart, brain, aorta and pancreas both have; the hip muscles by a closer
  warp of the pelvis). The woman's organ set has only the ilium of each
  hip bone, so her scan's whole hip bones take their place: each fitted
  by a similarity (scaled x1.08 and x1.05, turned 8 degrees) to her ilium,
  the scan's cut at the same height above its femoral head, and to the
  centre of her femoral head (within 4 mm on the ilium and 1.4 mm at the
  head), which keeps each bone whole (a warp fitted on the ilium alone
  tips the pubis back); the two pubic bodies are then brought together at
  the midline (by 8 and 17 mm), the rami eased smoothly, nothing 7 cm away
  moving. The rib cage is
  widened, smoothly around the chest's axis, until the organs sit inside
  it, but never past the skin, the shoulder girdles riding with it, each
  clavicle's inner end carried as the sternum beside it is. Each side's
  clavicle and scapula are one rigid piece, both sides at one scale and
  first set as mirror images about the upper thoracic spine's midline;
  each girdle is then settled on the trunk, turned and moved a little
  about its sternoclavicular joint: the joint as near the sternum as the
  scan's is to its own, the clavicle and the acromion a few millimetres
  under the skin, the scapula clear of the ribs, the clavicle rising
  gently from the sternum and the scapula's medial border near upright, as
  in the resting posture, and the two sides kept close to mirror images
  of each other. Each humerus is scaled by the
  warp and its shaft laid along the skin's arm, epicondyles across it, its
  head set on the glenoid as the scan's sits on its own (the scan's
  shoulder joint carried onto the body's scapula by the similarity that
  best lays the scan's scapula, about the glenoid, over the body's).
  Whatever still cut into an organ or bone is
  pushed out, smoothly, a few millimetres at a time; once the scanned
  vertebrae, sacrum and coccyx are in (`tools/anatomy_bones.py`), the hip
  and back muscles are pushed out of them again the same way. Each rib is
  then seated on the scanned spine (`tools/anatomy_ribs.py`, after Gray's
  Anatomy, 1918, public domain): the scan's ribs stop at the transverse
  processes, so each has its neck and head drawn out of its last 30 mm to
  its joint on the vertebral bodies, the second to the ninth at the disc
  above their own vertebra, the first and the last three on their own,
  1.5 mm off the bone; its back end first eased out of any process it ran
  into and brought to the level of its own process's tip, the move fading
  along the rib so its sides and front stay where the cage has them. The
  lungs and organs the ribs then met are moved out of them, the airways
  and vessels in the lungs carried along; each point of a lung moved
  level, the shortest way into the chest's cavity at its own height, so
  the lungs keep their height (moved the shortest way in any direction,
  their tops were driven 18 to 20 mm down by the vertebrae above them),
  and what a first smooth move leaves in a rib moved again over a
  shorter reach. The dataset segments
  no bone below the humerus, so the forearm and hand bones are found in
  the CT by density (`tools/anatomy_limbs.py`): the bone traced along each
  finger, the fingers named by where their metacarpals lie (the thumb's
  farthest from the other four), the joints read from the CT straightened
  along each finger and from where the brightest bone in each
  cross-section dips, each bone grown from seeds by a random walk, and a
  bone the walk left with a tunnel through it closed; the leads and a clip
  lying on the skin left out by their density. One arm per body is
  scanned (the man's left, from s1880; the woman's right, from s1764); the
  other side is its mirror image. The hand scans cut the elbow short
  (s1880's olecranon lies outside its field of view), so each elbow is
  found whole in a scan that holds it (`tools/anatomy_elbows.py`: the
  man's left in s1831, the woman's right in her own s1764): its humerus,
  and the upper 150 mm of its radius and ulna, told apart from the humerus
  by a watershed on the CT. The man's is carried onto s1880's forearm by
  the similarity that best lays its radius and ulna over s1880's, its
  radius then turned to lie as s1880's does; each forearm bone is the
  elbow scan's above a band in its upper shaft and the hand scan's below
  it, their surfaces blended across the band. The elbow scan's humerus
  then takes the place of the body's: laid over it, its head on the
  body's glenoid as the body's head was (its centre moved along the
  glenoid's normal by as much as the two heads' radii differ), its shaft
  lengthened or shortened (by at most 20%; the head and the condyles as
  they are) so that the elbow divides the arm from
  shoulder to the skin's wrist as the scans' arm does. The forearm's shaft
  is stretched likewise, its ends as they are, to reach the skin's wrist
  from the elbow's flexion axis (through the centres of the trochlea and
  the capitulum), and the wrist is brought onto the skin's by the turns
  the joints allow: the shoulder's, about the humerus's long axis and
  swung a little about the head's centre, and the elbow's, about its
  flexion axis, never more than 5 degrees past straight. The CT's mask
  fills much of the olecranon fossa, whose floor is thin bone, so the
  fossa is deepened, smoothly, until the olecranon lies 1 mm clear of the
  humerus. The forearm is turned so the knuckles lie across as the
  skin's do, and each finger laid along the skin's, joint by joint, its
  length from the skin's finger; a finger whose tip still lay outside the
  skin is shortened, by at most 15%.
  Forearm, hand and fingers are sized to the skin within 15% (fingers
  10%). The carpal bones stay one structure: at the scans' 1.5 mm they are
  not told apart reliably. The feet are found the same way
  (`tools/anatomy_feet.py`) in the CT of one foot per body (the woman's
  right, from s1764; the man's left, from s1767), the other side its
  mirror image: the bone traced along each toe's ray, the joints read
  along it, the tarsal bones grown from seeds along each metatarsal's line
  and the tibia's axis, the great toe's two sesamoids found below its
  metatarsal head, and each bone closed until it is one piece without
  tunnels. Each foot is set on the body's own tibia and fibula at the
  ankle (the scan's leg bones fitted to them, within 6 mm), sized to the
  skin's foot (the man's x0.96 and x0.97, the woman's x1.12 and x1.05),
  turned and sized along its axes within bounds (by up to 15%) until its
  bones lie inside the skin, then each toe bent at its joints and, where
  the skin's toe is shorter than the scan's bones, shortened, by at most
  20%. The skin's feet are those of bodies lying down: the heel pad
  spreads, so the skin reaches 2 to 4 cm behind the heel bone.

### The labels: ASCT+B Tables to 3D Reference Object Library Mapping, v1.10

- File: https://cdn.humanatlas.io/digital-objects/ref-organ/asct-b-3d-models-crosswalk/v1.10/assets/asct-b-3d-models-crosswalk.csv
  (SHA-256 `54622d7ba5c8df15d8655c2af5ad6ebece45b74f61d894167e6fd9db9e66be06`)
- Licence: CC BY 4.0.
- Credit: Ellen M. Quardokus, Heidi Schlehlein, Bruce W. Herr II and Katy
  Börner. 2026. https://doi.org/10.48539/HBM626.BRWN.943.
- Use: each mesh's label and UBERON id. UBERON itself is CC BY 3.0
  (http://purl.obolibrary.org/obo/uberon.owl, header `dcterms:license`).

### Made to measure: the eyes and the gluteus maximus

- Sources: Henry Gray, *Anatomy of the Human Body*, 20th edition, revised
  by Warren H. Lewis (Lea & Febiger, 1918), its text on the eye and its
  figures 869 to 883, and on the gluteus maximus; Frederic Henry Gerrish
  (ed.), *A Text-book of Anatomy by American Authors* (1902), figure 349,
  which draws the gluteus maximus's outline and attachments on the
  bones; both in the public domain. The gluteus maximus's volume is
  checked against what MRI measures in living adults (Belzunce et al.,
  BMJ Open Sport Exerc Med 2023;9:e001672: median 770 cm³ in the men, 621
  in the women).
- Use: measures and descriptions only: nothing of these is shipped, and
  no mesh or image is copied. The shapes were looked at against the
  reference index's images (`docs/sciences/anatomy-references.json`),
  never traced.
- The eyes (`tools/anatomy_eyes.py`), each in the frame of its organ
  set's eyeball (the centre and radius of its sclera, its optical axis
  through its cornea): the sclera, cornea, the angle's meshwork and
  Schlemm's canal, the choroid, retina and ora serrata, the optic disc,
  macula and fovea, the iris with its pupil, the lens, the ciliary body
  with its processes and the zonule, the aqueous and vitreous, and the
  bulbar and palpebral conjunctiva, each to the textbook's measures; each
  with its own colour, see-through or not, in the manifest. The four recti
  from the common tendinous ring to flat tendons on the spiral of
  Tillaux, the superior oblique through its trochlea, the inferior
  oblique from the orbit's floor around the eyeball, none entering the
  eyeball, the optic nerve or another muscle.
- The gluteus maximus (`tools/anatomy_gluteus.py`), on each body's own
  bones: its corners on the iliac crest, the coccyx, over the greater
  trochanter and at the gluteal tuberosity's lower end; laid on what lies
  under it, thickest through its belly (42 mm in the man, 36 in the
  woman, scaled by the femur), at least 6 mm under the skin, smooth over
  what lies under it; its volume 790 and 775 cm³ (left and right) in the man and 558 and
  556 in the woman.

## What is not here yet, and why

- The carpal bones one by one: at the scans' 1.5 mm they are not told
  apart reliably (the tarsals, larger, are).
- Named muscles beyond the eye, larynx, rectus femoris, glutei, iliopsoas
  and the deep back muscles: no clean source has more.
- The pituitary and parathyroids: no clean mesh found yet.
- Peripheral nerves: no source passes the licence rule. Every rich set is
  derived from BodyParts3D or Z-Anatomy (CC BY-SA, refused by brief §23f) or
  is of unknown origin. They are to be drawn for the app itself.
- The man's sternum and the woman's hyoid, larynx muscles and urethra: the
  organ sets model them in one body only.
