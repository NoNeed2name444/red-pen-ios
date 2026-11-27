# MUSCLES: the head's muscles that attach to the skull or the mandible (Gray 1918)

Source: Gray, *Anatomy of the Human Body*, 20th ed. (1918), public domain. "p." is the printed page, and "Fig." is the plate.
Every fact below was read on that page. Words in quotation marks are Gray's own. Where Gray gives no fact for a column, the
cell says **not in Gray**. Thicknesses, fascicle widths and tendon lengths in `muscles.py` are therefore the builder's choice,
fitted to the plates. They are not Gray's.

Muscle pages: Myology pp. 378–388.
- Fig. 378, the head, face and neck: p. 379.
- Fig. 379, orbicularis oculi from behind: p. 381.
- Figs. 380 and 381, the cheek and the orbicularis oris: p. 384.
- Fig. 382, the temporalis: p. 386.
- Fig. 383, the pterygoids: p. 387.

Bone pages: Osteology pp. 134–184.
- Fig. 137, the temporal bone: p. 139.
- Fig. 157, the maxilla: p. 158.
- Fig. 176, the mandible from the side: p. 172.
- Fig. 177, the mandible from inside: p. 173.
- Fig. 188, the skull from the side: p. 182.

Built in `muscles.py`: the masseter (superficial and deep) and the temporalis, both sides (shape T-muscle-1, surface and look T-muscle-2). The other rows are ledger only.

Where the built bone and Gray's plates disagree, the plate wins:
- The temporalis' upper margin is Fig. 382's outline (registered on the vault). It is not the scratch skull's inferior temporal
  line, which was traced on another skull's plate (Fig. 188) and runs 6–15 mm off the muscle.
- The masseter's insertion fills Fig. 176's ring (registered on the jaw's outline). The deep portion fills the upper half; the
  superficial fills the lower half, the angle and the hind border. Where the ring overhangs the built jaw, by up to 3.6 mm at
  the angle, it is drawn in onto the bone.

## Surface, tendon, attachments and look (T-muscle-2)

The shape is the accepted T-muscle-1 build (outlines, fibre angles, clearances), now on the bone of commit 6168272. What
T-muscle-2 adds, and where each number comes from (Gray: the plate; meatRef: the 43-photo measurement file
`meatRef/analysis.md`, its ids; spec: `musTex/spec.md`; [C]: the builder's choice, not measured):
- Field: each fibre sample stands for its own volume, shared trilinearly among the grid's cells, blurred 0.6 mm and read off
  through the inverse of the blurred step. The old cell-occupancy field aliased the samples against the grid into rings like
  wood grain (G2). Where the fan spreads, a sample is split over its own cell. A twisted cell counts at least half its box.
- Mesh: marching cubes, then cut twice (edges about 0.12 mm). The fibre coordinates are fitted by local linear least
  squares (about 1 mm). Averaging over mesh edges bends them in the grid's pattern, and that drew zigzags into the grooves.
- Strands, in three levels: lumps 8-25 mm [C]; bundles with a median of 3.4 mm, lognormal sigma 0.6, 0.3x to 3x (meatRef
  T1/a, VH); fascicle grooves 1.3 mm (spec [D]).
  - The septum groove is 0.18 of the bundle's width (meatRef G4).
  - Each groove runs about 3 strand widths and then lapses for about 1, so strands merge and split every 2-2.5 widths (D01).
  - Sideways wander is about 5 % of the spacing (D01).
  - Groove depths are the spec's [C].
- Colour:
  - flesh #C9595B (temporalis) and #CB5F5D (masseter superficial), from living muscle (D06, D11); the deep masseter a shade
    darker [C];
  - bundles L* sd about 2 (VH), with streaks along the fibres;
  - tendon #EEE0D4, Gray's glistening white only warmed, with faint fibres to the coronoid (repair F6; meatRef's living
    #EFC1B4, D11, read too pink beside Fig. 382);
  - perimysium seam #BA8E7E (B08).
  - Grooves darken the linear albedo x0.5 in the renderer (C2: x0.47-0.55, D01, B12). The stored colour stays the tissue's own.
- Tendon:
  - temporalis: Fig. 382's own white (not-red pixels inside the traced outline, largest piece), with a ramp of about 6.5 mm,
    about 6 % of the fibres' length (meatRef d, D14), and gentle tongues;
  - below the arch, the fibres' own share all round the coronoid;
  - masseter: the aponeurosis, ramp 14 % of the fibre length (about 6 mm): G7's 25 %-per-0.5 mm cap wins over meatRef d's
    6 % on this short muscle.
  - The share is eased on the mesh (about 2.4 mm within a part, then about 1.5 mm across the deep and superficial parts),
    and so is the film band (about 2.4 mm), so no colour step is left on one face.
- Attachments:
  - every attached margin is thinned to nothing toward the bone over the last 6 mm (fleshy) or 4 mm (tendinous);
  - a film colour (#D6BCAA, periosteum and fascia [C]) fades from muscle into bone over about 3.5 mm on the muscle, and the
    bone takes it on over 2.5 mm;
  - a tendon's striation runs on into the bone's surface for 3 mm.
  - At the bone end of a tendon there is no visible gap, only a thin pale connective band (meatRef e: VH femur, B01, B02).
    Clean bone shows rough, frayed tendon tags where tendons were cut (C07). Gray marks the masseter's insertion as "rough,
    oblique ridges" (p. 174). The spec's enthesis sources are ultrastructural only (A1.10).
- Renderer (`shaded()`):
  - wrap diffuse with a red tint;
  - an anisotropic GGX lobe that is rougher along the fibres than across. Highlights run ALONG the strands, 2-3 long,
    untinted (meatRef T5/f). This overturns the spec's across-fibre stretch.
  - a wet clear coat;
  - striation finer than the mesh as a normal tilt;
  - crimp on the tendon;
  - screen-space occlusion.
  - `matte=True` is the plain matte look on the interpolated vertex colour.
- The masseter is never pulled within 0.45 mm of the temporalis.
- After the pull, anything more than about 1.5 mm from an attachment's trace is pushed out to 0.36 mm off the bone (where
  the bone is thin and its gradient fails, the spot is first relaxed into its neighbours). The masseter is kept 0.36 mm off
  the temporalis as built (its mesh, not only its field). Last check: clearances L 0.329/0.313/0.36, R 0.357/0.358/0.45 mm.

## T-muscle-2 repair 1 (bone of 11c34da)
- Masseter (F1): the superficial part is a flat-topped quadrilateral (Fig. 378), its front and hind borders standing and a
  firm edge at the angle. Its origin ends at z 35, so the deep part shows behind it near the joint. The aponeurosis sends
  four to six soft-sided tendinous slips down to different depths. The two parts' fields join in a soft union (k 1.2 mm),
  and the share and colour are blurred in space (1.0 and 0.8 mm) after the muscle is pulled onto the bone.
- Texture (F2):
  - bundles: lognormal sigma 0.75, tone sd 0.13 bundle to bundle (R2 >= 0.12 asked; meatRef's L* sd about 2 is
    overruled here);
  - striation tilt halved;
  - the wet coat follows the shape, not the striation, and is drawn out along the strands like the tissue lobe
    (flesh_aniso 0.22, coat_rough 0.27): a broad sheen, no needle glints.
- Attachments (F3):
  - margins thinned over 8 mm (fleshy) and 4.5 mm (tendinous), flatter near the line;
  - the film is measured in space from the attached line (a straight 3.4 mm ramp);
  - the renderer's occlusion is lifted along an attachment, so no shadow line.
  - "Attached" is stored only where the margin lies within 1 mm of the bone. The temporalis's front margin over the
    zygomatic bone is free (Gray p. 386).
- Ring (F4): in the side view, 3.6-5 mm of flesh is kept before the tendon at the front margin, and the tendon is brought to
  about 3 mm from the hind margin low down (Fig. 382 shows 1.3 mm).
- B2 (F5): measured on the square inside the round patch (it was all NaN).

## T-muscle-2 repair 2 (bone of 11c34da)
- J1 (the owner's direction, which replaced the freeze): the temporalis is built from this skull's features, not from
  Fig. 382's outline. Its origin's margin is the temporal fossa's own boundary (`fossa_outline`):
  - the frontal bone's temporal crest;
  - the inferior temporal line, as built in temporal.py (traced from Fig. 188);
  - the supramastoid crest;
  - the arch's level;
  - the cheek bone's hind border.
  The margin is drawn in 0-0.3 mm. Fig. 382 is only a likeness check now; repair 1's plate outline left up to 24 mm of bare
  fossa below the line (coverage 77 %). Coverage is measured by `sc/fos.py`: a fossa point counts when the muscle lies
  within 1.2 mm of it, or over it within 15 mm outward.
- J2: the masseter's insertion is found on the built jaw (`ramus_area`), not taken from Fig. 176. It is bounded by:
  - the notch's lowest level;
  - the hind border to the angle;
  - the lower border;
  - the ramus' anterior border, carried on down the oblique line.
  Fig. 176's ring (A1) only checks it: mean 2.8 / 4.3 mm apart, left side. The origins were already found on the bone
  (`lower_border`, `arch_frame`).
- J3: the flesh bases are about x(0.80, 0.65, 0.59), now (161, 58, 54), (150, 52, 48) and (162, 62, 55). The tendon is a
  warm pale grey (143, 130, 119); PALE, SEPTUM and FILM are darkened to match. `sc/lstar.py` measures the side view's
  L* for bone, flesh and tendon.
- Masseter look (H1, Fig. 378):
  - The superficial part's aponeurosis is drawn on the sheet itself (`set_tendon`, kind "tongues"): a 2 mm strip along the
    origin, and four pale tongues spread along the arch. Each has its own length (13-22 mm) and a root 4.5-6 mm wide, and
    narrows to a point. The tendon share is smoothed less (40 and 24 rounds, a 0.5 mm blur) so the tongues stay apart.
  - The origin ends at z 39, so the deep part shows behind the hind border as its own steeper triangle.
  - The outer face is flattened front to back: its bow over the chord is capped softly (0.3 mm plus 5 % of the rest),
    and no layer comes within 2 mm of the deep layer.
  - The thickness rises over a longer ramp in the upper half (exponent 1.3), and keeps a firm edge at the angle.
- Masseter origin (H2): `largest_piece` keeps one connected piece; loose slivers are dropped.
- Edges (H3): `tidy_edges` slides the bone line along the bone and eases its height, by at most 0.4 mm on the masseter and
  0.2 mm on the temporalis.
- Margin tails (H4):
  - `ease_tails`: on the outer face within 3 mm of an attached edge, the height over the bone is at most 0.45 x the edge
    distance. Off the attachments (more than 1.6 mm from them, as A4 counts) the floor is 0.31 mm.
  - The masseter's film fades over 2.4 mm (it was 3.4 mm). After the tidy, the film and colour are blurred in space over
    0.6 mm where the film fades.
  - B6 now reads the fade on the outer face by straight distance from the attached line, using medians, so it is no
    longer NaN.
- Gloss (H5): a muscle may carry its own coat per vertex (`coat`, `coat_rough`). The masseter has 0.8 / 0.3. Muscles
  without these keep the common coat.
- `pick_patch` falls back to a looser second pass, because the tongues leave fewer clean rounds.
- Clearances: `keep_clear` is the last step of `surface()` for both muscles. Off the attachments (A4's 1.6 mm), any vertex
  within 0.33 mm of the bone, or of the other muscle, is stepped out. The edge tidy and the tail ease had brought some
  down to 0.12-0.21 mm.
- Colour steps: `ease_colour_steps` is the very last step of `surface()`. Where two facing points 0.35-0.65 mm apart differ
  by more than 0.2 of the red-white difference per 0.5 mm (B7's own measure), the colour and film are blended toward
  their 0.8 mm blur. This is not done where the film is full, so the attached line keeps the film's colour. With the J3
  palette the red-white difference itself halved (0.73 to 0.39), so B7 is twice as strict as before.

## Muscles of mastication (mandibular nerve, p. 387)

| Muscle | Origin (bone, mark) | Insertion | Route: over, under, between | Fibres and architecture | Nerve; action | Source |
|---|---|---|---|---|---|---|
| Masseter, superficial | "by a thick, tendinous aponeurosis from the zygomatic process of the maxilla, and from the anterior two-thirds of the lower border of the zygomatic arch" (p. 385). The zygomatic bone's "postero-inferior or zygomatic border affords attachment by its rough edge to the Masseter" (p. 166). | "into the angle and lower half of the lateral surface of the ramus" (p. 385). The angle has "rough, oblique ridges ... for the attachment of the Masseter laterally" (p. 174). The ringed area is shown on Fig. 176 (p. 172). | Covered by the masseteric fascia, "attached to the lower border of the zygomatic arch" (p. 385). It "partly" conceals the deep portion "in front" (p. 386). | "downward and backward" (p. 385). Origin by an aponeurosis (p. 385). Pennation and insertion tendon: not in Gray. | Mandibular nerve; "raise the mandible against the maxillae with great force" (p. 387). | Fig. 378 p. 379; text pp. 385–386; Fig. 176 p. 172 |
| Masseter, deep | "from the posterior third of the lower border and from the whole of the medial surface of the zygomatic arch" (p. 386). The arch's inferior border "has attached to it some fibers of the Masseter"; the medial surface "affords attachment to the Masseter" (p. 139). | "the upper half of the ramus and the lateral surface of the coronoid process" (p. 386). The coronoid's lateral surface "affords insertion to the Temporalis and Masseter" (p. 174). | "partly concealed, in front, by the superficial portion; behind, it is covered by the parotid gland" (p. 386). Lies lateral to the temporalis tendon (by position: the tendon passes medial to the arch, p. 183). | "downward and forward"; "much smaller, and more muscular in texture" (p. 386). "The fibers of the two portions are continuous at their insertion" (p. 386). | As above. | Fig. 378 p. 379; text p. 386; p. 139 |
| Temporalis | "the whole of the temporal fossa (except that portion of it which is formed by the zygomatic bone) and ... the deep surface of the temporal fascia" (p. 386). The inferior temporal line "indicates the upper limit of the muscular origin" (p. 134). The supramastoid crest "limits the origin" (p. 139). Also the frontal bone's area below the temporal line (p. 136) and the great wing's temporal portion above the infratemporal crest (p. 150). | "the medial surface, apex, and anterior border of the coronoid process, and the anterior border of the ramus ... nearly as far forward as the last molar tooth" (p. 386). The upper part of the grooved triangle on the coronoid's medial surface (p. 174). | Lies on the fossa floor under the temporal fascia (p. 386). Its tendon "passes deep to the zygomatic arch" (p. 386) and "medial to" it (p. 183). Its lower part lies in the infratemporal fossa (p. 184). | "broad, radiating": a fan. "Its fibers converge as they descend, and end in a tendon" (p. 386). The fascia's "deep surface" gives origin to "the superficial fibers" (p. 386). | Mandibular nerve; raises the mandible. "The mandible is retracted by the posterior fibers of the Temporalis" (p. 387). | Fig. 382 p. 386; text p. 386; pp. 134, 136, 139, 150, 174, 183 |
| Lateral pterygoid, upper head | "from the lower part of the lateral surface of the great wing of the sphenoid and from the infratemporal crest" (p. 386). The infratemporal surface "together with the infratemporal crest, affords attachment" (p. 150). | "a depression in front of the neck of the condyle ... and ... the front margin of the articular disk" (p. 387). The neck's anterior surface "presents a depression for the attachment" (p. 174). | "extends almost horizontally between the infratemporal fossa and the condyle" (p. 386). | "short, thick ... somewhat conical"; fibres "horizontally backward and lateralward" (pp. 386–387). Tendon: not in Gray. | Mandibular nerve; "draw forward the condyle and articular disk so that the mandible is protruded"; helps to open the mouth; with the medial pterygoid of the same side, moves the jaw side to side (p. 387). | Fig. 383 p. 387; text pp. 386–387; p. 150 |
| Lateral pterygoid, lower head | "from the lateral surface of the lateral pterygoid plate" (p. 386; also p. 151). | As the upper head (p. 387). | As the upper head. | As the upper head. | As the upper head. | Fig. 383 p. 387; pp. 151, 180 |
| Medial pterygoid | "the medial surface of the lateral pterygoid plate and the grooved surface of the pyramidal process of the palatine bone", with "a second slip of origin from the lateral surfaces of the pyramidal process of the palatine and tuberosity of the maxilla" (p. 387). Also the pterygoid fossa (p. 151), the tuberosity's "few fibers" (p. 159) and the pyramidal process (p. 168). | "by a strong tendinous lamina, into the lower and back part of the medial surface of the ramus and angle ... as high as the mandibular foramen" (p. 387). A "rough surface" behind the mylohyoid groove (p. 173), and the angle's medial ridges (p. 174). | Lies in the pterygoid fossa (p. 151). Its relation to the lateral pterygoid: not in Gray's text (drawn in Fig. 383). | "thick, quadrilateral"; fibres "downward, lateralward, and backward"; inserted by a "strong tendinous lamina" (p. 387). | Mandibular nerve; raises the mandible with great force; helps the lateral pterygoid to protrude (p. 387). | Fig. 383 p. 387; pp. 151, 159, 168, 173, 174 |

## Facial muscles with a bony attachment (facial nerve)

Gray's facial muscles with no attachment to bone are listed at the end.

| Muscle | Origin (bone, mark) | Insertion | Route: over, under, between | Fibres and architecture | Nerve; action | Source |
|---|---|---|---|---|---|---|
| Occipitalis | "by tendinous fibers from the lateral two-thirds of the superior nuchal line of the occipital bone, and from the mastoid part of the temporal" (p. 379). The mastoid's outer surface gives attachment to the Occipitalis (p. 141). | "the galea aponeurotica" (p. 379). | Over the occipital bone; the planum occipitale "is covered by the Occipitalis" (p. 185). | "thin and quadrilateral" (p. 379). | Posterior auricular branch of the facial nerve; "draw the scalp backward" (p. 380). | Fig. 378 p. 379; pp. 379–380 |
| Frontalis (with the galea) | "It has no bony attachments" (p. 379). The galea is attached "to the external occipital protuberance and highest nuchal lines" (p. 380). | Joins the galea "below the coronal suture" (p. 379). | Its fibres blend with the Procerus, the Corrugator and the Orbicularis oculi (p. 379). | Thin, quadrilateral; fibres "directed upward" (p. 379). | Temporal branches of the facial nerve; "raise the eyebrows" and wrinkle the forehead (p. 380). | Fig. 378 p. 379; pp. 379–380 |
| Orbicularis oculi | "the nasal part of the frontal bone, ... the frontal process of the maxilla in front of the lacrimal groove", and the medial palpebral ligament (p. 380). The lacrimal part arises "from the posterior crest and adjacent part of the orbital surface of the lacrimal bone" (p. 380; p. 164). | Palpebral part: "the lateral palpebral raphe". Orbital part: "a complete ellipse" (p. 380). | Spreads "over the temple, and downward on the cheek" (p. 380). The lacrimal part passes "behind the lacrimal sac" (p. 380). | Concentric curves; the palpebral part "thin and pale", the orbital "thicker"; the lacrimal part "about 6 mm. in breadth and 12 mm. in length" (p. 380). | Facial nerve; "the sphincter muscle of the eyelids" (p. 381). | Figs. 378 p. 379 and 379 p. 381; pp. 380–381 |
| Corrugator | "the medial end of the superciliary arch" (p. 381). | "the deep surface of the skin, above the middle of the orbital arch" (p. 381). | "beneath the Frontalis and Orbicularis oculi"; passes "between the palpebral and orbital portions of the Orbicularis oculi" (p. 381). | "small, narrow, pyramidal"; fibres "upward and lateralward" (p. 381). | Facial nerve; "draws the eyebrow downward and medialward" (p. 382). | Fig. 378 p. 379; pp. 381–382 |
| Procerus | From fascia over "the lower part of the nasal bone" (p. 382). The nasal bone is "covered by the Procerus and Compressor nasi" (p. 156). | "the skin over the lower part of the forehead between the two eyebrows" (p. 382). | Its fibres decussate with the Frontalis (p. 382). | "small pyramidal slip"; arises "by tendinous fibers" (p. 382). | Facial nerve; "draws down the medial angle of the eyebrows" (p. 382). | Fig. 378 p. 379; p. 382 |
| Nasalis, transverse part | "the maxilla, above and lateral to the incisive fossa" (p. 382; p. 158). | A "thin aponeurosis" on the bridge of the nose (p. 382). | not in Gray | Fibres "upward and medialward" (p. 382). | Facial nerve; "depresses the cartilaginous part of the nose" (p. 382). | Fig. 378 p. 379; pp. 158, 382 |
| Depressor septi | "the incisive fossa of the maxilla" (p. 382; p. 158). | "the septum and back part of the ala" (p. 382). | "between the mucous membrane and muscular structure of the lip" (p. 382). | Fibres "ascend" (p. 382). | Facial nerve; draws the ala down, "constricting the aperture of the nares" (p. 382). | Fig. 378 p. 379; pp. 158, 382 |
| Dilatator naris posterior | "the margin of the nasal notch of the maxilla" and the lesser alar cartilages (p. 382; p. 158). | "the skin near the margin of the nostril" (p. 382). | "partly beneath the Quadratus labii superioris" (p. 382). | not in Gray | Facial nerve; enlarges the nares (p. 382). | Fig. 378 p. 379; pp. 158, 382 |
| Quadratus labii superioris | Angular head: "the upper part of the frontal process of the maxilla". Infraorbital head: "the lower margin of the orbit immediately above the infraorbital foramen", partly maxilla and partly zygomatic bone. Zygomatic head: "the malar surface of the zygomatic bone immediately behind the zygomaticomaxillary suture" (p. 383; pp. 158, 161, 166). | The ala and the skin of the nose; the upper lip (p. 383). | The infraorbital head inserts "between the angular head and the Caninus" (p. 383). | "a broad sheet"; the angular head runs "obliquely downward and lateralward"; the zygomatic head runs "downward and medialward" (p. 383). | Facial nerve; "the proper elevator of the upper lip" (p. 383). | Fig. 378 p. 379; p. 383 |
| Caninus | "the canine fossa, immediately below the infraorbital foramen" (p. 383; p. 158). | "the angle of the mouth" (p. 383). | Intermingles there with the Zygomaticus, Triangularis and Orbicularis oris (p. 383). | not in Gray | Facial nerve; raises the angle of the mouth (p. 383, in the Actions line). | Figs. 378 p. 379 and 380 p. 384; p. 383 |
| Zygomaticus | "the zygomatic bone, in front of the zygomaticotemporal suture" (p. 383), from "a slight elevation" below the zygomaticofacial foramen (p. 164). | "the angle of the mouth" (p. 383). | not in Gray | "descending obliquely with a medial inclination" (p. 383). | Facial nerve; "draws the angle of the mouth backward and upward" (p. 383). | Fig. 378 p. 379; pp. 164, 383 |
| Mentalis | "the incisive fossa of the mandible" (p. 383; p. 172). | "the integument of the chin" (p. 383). | "at the side of the frenulum of the lower lip" (p. 383). | "small conical fasciculus"; it "descends" (p. 383). | Facial nerve; "raises and protrudes the lower lip" (p. 383). | Fig. 378 p. 379; pp. 172, 383 |
| Quadratus labii inferioris | "the oblique line of the mandible, between the symphysis and the mental foramen" (p. 383; p. 172). | "the integument of the lower lip" (p. 383). | "continuous with the fibers of the Platysma" at its origin (p. 383). | "small quadrilateral"; runs "upward and medialward"; "Much yellow fat is intermingled" (p. 383). | Facial nerve; "draws the lower lip directly downward and a little lateralward" (p. 383). | Fig. 378 p. 379; pp. 172, 383 |
| Triangularis | "the oblique line of the mandible" (p. 383; p. 172). | "by a narrow fasciculus, into the angle of the mouth" (p. 383). | Continuous with the Platysma, the Orbicularis oris and the Risorius (p. 383). | Fibres "converge" (p. 383). | Facial nerve; "depresses the angle of the mouth" (p. 383). | Figs. 378 p. 379 and 380 p. 384; pp. 172, 383 |
| Buccinator | "the outer surfaces of the alveolar processes of the maxilla and mandible, corresponding to the three molar teeth", and the pterygomandibular raphe (p. 384). On the maxilla, p. 161. On the mandible, "the outer lip of the superior border" (p. 173). On the coronoid's grooved triangle, "the lower part" (p. 174). | The Orbicularis oris, at the angle of the mouth (p. 384). | Covered by the buccopharyngeal fascia. A "large mass of fat" (the suctorial pad) "separates it from the ramus of the mandible, the Masseter, and a small portion of the Temporalis". "The parotid duct pierces the Buccinator opposite the second molar tooth" (p. 384). | "thin quadrilateral". The fibres "converge toward the angle of the mouth, where the central fibers intersect" (p. 384). | Facial nerve; "compress the cheeks" (p. 385). | Fig. 380 p. 384; pp. 161, 173, 174, 384 |
| Orbicularis oris, incisive bands | Upper band: "the alveolar border of the maxilla, opposite the lateral incisor tooth" (p. 385; p. 158). Lower band: "the mandible, lateral to the Mentalis" (p. 385). The mandible's incisive fossa gives "a small portion" (p. 172). | The other muscles at the angle of the mouth (p. 385). | not in Gray | "numerous strata"; the lip's own fibres are "oblique" (pp. 384–385). | Facial nerve; "the direct closure of the lips" (p. 385). | Fig. 381 p. 384; pp. 384–385 |
| Platysma | From the fascia over the Pectoralis major and Deltoideus (p. 388). | "some being inserted into the bone below the oblique line, others into the skin" (p. 388; p. 172). | Its fibres "cross the mandible" (p. 388). | "a broad sheet"; fibres "obliquely upward and medialward" (p. 388). | Cervical branch of the facial nerve; "depresses the lower jaw" (anterior part) and draws down the lip (p. 388). | Fig. 378 p. 379; p. 388 |

Gray's facial muscles with no bony attachment, listed for completeness:
- Frontalis (p. 379);
- Dilatator naris anterior (p. 382);
- Risorius, which "arises in the fascia over the Masseter" (p. 385);
- the alar part of the Nasalis (p. 382).

## Bone marks on the scratch skull and jaw (snapshot a9a6e13, LEDGER.md states)

Present (built):
- the temporal lines (superior and inferior);
- the supramastoid crest;
- the zygomatic arch, lower border and medial surface;
- the temporal and infratemporal fossae;
- the lateral and medial pterygoid plates and the hamulus;
- the pyramidal process; the maxillary tuberosity;
- the canine fossa; the nasal notch; the frontal process of the maxilla;
- the zygomatic bone's malar surface;
- the ramus with its angle ridges; the coronoid process;
- the mylohyoid line; the oblique line; the mandible's incisive fossa;
- the pterygoid fovea of the condyle's neck;
- the alveolar processes.

Present only as plain bone with no relief of its own (marked "plain" in LEDGER):
- the infratemporal crest;
- the maxilla's incisive fossa;
- the superciliary arch;
- the great wing's temporal surface.

Missing:
- the anterior lacrimal crest, the lacrimal groove and the posterior lacrimal crest. These are needed for the Orbicularis oculi's
  origin and its lacrimal part.
- The coronoid's medial temporal crest and grooved triangle exist only as a relief in mandible4. There is no named mark for the
  temporalis' medial insertion and the buccinator's upper fibres, so `muscles.py` places them along the coronoid border it finds.
- The angle's "rough, oblique ridges" (p. 174) are built as relief, but they do not bound an area. The masseter's insertion is
  therefore taken from Fig. 176's ringed area, not from a bone mark.
