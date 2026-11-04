# The 3D anatomy atlas: sources, licences, credits

The anatomy atlas in the Sciences screens is drawn from these files (reader:
`Shared/Sciences/AnatomyAtlas.swift`). It has two bodies, a man and a
woman. Most meshes come from the Human Reference Atlas's male and female
reference organ sets; the skull from each body's own head CT (the Visible
Human Project, U.S. National Library of Medicine: the organ sets were made
from the same man and woman), its bones named after, and its face and
thinnest plates drawn from, NIH 3D's skull of the Visible Human Male; the ribs,
shoulder girdle, arm, hand and foot bones, the woman's hip bones, the hip
and back muscles, thyroid, adrenals, oesophagus and stomach from five
TotalSegmentator CT scans. All are CC BY 4.0 but the Visible Human CT,
which NLM gives under its Terms and Conditions. The files here were made
from the downloads below by `tools/anatomy_atlas.py`,
`tools/anatomy_gaps.py`, `tools/anatomy_skull.py`,
`tools/anatomy_limbs.py`, `tools/anatomy_elbows.py` and
`tools/anatomy_feet.py`, which say exactly how:

    python3 -I tools/anatomy_atlas.py --male 3d-vh-m-united.glb \
        --female 3d-vh-f-united.glb --crosswalk asct-b-3d-models-crosswalk.csv \
        --skull 3DPX-020591.glb \
        --ct <folder holding s1803/, s1764/, s1880/, s1831/ and s1767/> \
        --vhct <folder holding male/ and female/, the head CT's slices>

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
`ContentSources.nihSkullCredit` and `ContentSources.totalSegmentatorCredit`,
kept the same by the same test):

"3D skull: each body's own, meshed from the Visible Human Project's CT of
the male and female heads
(https://www.nlm.nih.gov/research/visible/visible_human.html). Courtesy of
the U.S. National Library of Medicine."

"3D skull: Skull and Eyes - Visible Human Male (NIH 3D, 3DPX-020591,
https://3d.nih.gov/entries/3DPX-020591), by kbrowne, NLM 3D: Anatomy, CC BY
4.0, from the Visible Human Male, courtesy of the U.S. National Library of
Medicine."

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
  is.

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
  the nearest of the model's bones, the CT's teeth left out (the organ
  sets' are kept), the whole simplified to 80,000 triangles a body, and
  the borders between bones smoothed. Then, as before, kept under the
  skin and the brain sized to it.

### The skull's model and names: Skull and Eyes - Visible Human Male (NIH 3D, 3DPX-020591)

- Page: https://3d.nih.gov/entries/3DPX-020591 (no DOI)
- File: its GLB, SHA-256
  `031179f6942df5ca89e675e6eb75859a2e9751c6046bcadde083708974345a43`
- Licence: CC BY 4.0, stated on the entry.
- Credit: kbrowne, NLM 3D: Anatomy. Segmented from the Visible Human Male's
  CT, courtesy of the U.S. National Library of Medicine: the same man as
  the male body.
- Changes: the eyes and teeth left out, as the bodies have their own;
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
  (as one structure) of each foot, gluteus maximus, medius and minimus,
  iliopsoas, the deep back muscles, the thyroid, the adrenals, the
  oesophagus and the stomach, in both bodies.
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
  pushed out, smoothly, a few millimetres at a time. The dataset segments
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
