# What the from-scratch skull has, detail by detail

Written by `dev/ledger.py`; change the rows there, not here. The names are Gray's (Anatomy, 20th edition, 1918,
public domain), and the page beside each is where a search of the book's text finds it.

- **built**: a shape of its own, read from a plate and looked at in a picture
- **plain**: there, but only as part of a larger traced form
- **missing**: not there

Of 144 details: 89 built, 19 plain, 36 missing.


## Frontal (4 of 13 built)

| Detail | State | Where, or what is lacking | Gray, page |
| --- | --- | --- | --- |
| frontal eminence | plain | the braincase's traced outline (skull2.braincase) | 135 |
| superciliary arch | plain | the face's relief through traced points (skull2.face); no arch of its own | 135 |
| glabella | plain | a point of the traced profile (landmarks.py) | 135 |
| supraorbital margin | built | skull2.orbit_margin: the orbit's rim as traced | 135 |
| supraorbital notch or foramen | built | a shallow notch cut in the orbit's upper rim, 5 mm wide (skull2.build) | 136 |
| zygomatic process | built | its hind edge is the temporal crest traced on Fig. 188 (temporal.FRONTAL_CREST), the fossa hollowed behind it (temporal.fossa_front); the suture below it is in the split (bones.py) | 136 |
| temporal line | built | temporal.lines_relief: the crest on the frontal bone, traced on Fig. 188 | 136 |
| nasal part and nasal spine | missing | the nasal bones meet the frontal bone on a plain wall | 136 |
| orbital plate (roof of the orbit) | plain | the orbit's funnel (skull2.build) | 137 |
| fossa for the lacrimal gland | missing |  | 137 |
| trochlear fovea | missing |  | 137 |
| frontal sinus | missing | the bone is solid | 135 |
| inside: frontal crest, foramen cecum, sagittal sulcus | missing | the cranial cavity is one smooth hollow | 136 |

## Parietal (1 of 4 built)

| Detail | State | Where, or what is lacking | Gray, page |
| --- | --- | --- | --- |
| parietal eminence | plain | the braincase's traced outline | 133 |
| superior and inferior temporal lines | built | temporal.lines_relief: two low lines over the parietal, traced on Fig. 188; they still read as a very regular arc | 134 |
| parietal foramen | missing |  | 134 |
| inside: grooves for the middle meningeal vessels, sagittal sulcus | missing | the cranial cavity is one smooth hollow | 134 |

## Occipital (10 of 13 built)

| Detail | State | Where, or what is lacking | Gray, page |
| --- | --- | --- | --- |
| external occipital protuberance | built | occiput.py | 129 |
| highest nuchal line | missing |  | 129 |
| superior nuchal line | built | occiput.py: the traced strip, a broad low swell | 130 |
| median nuchal line (external occipital crest) | built | occiput.py | 185 |
| inferior nuchal line and the muscles' areas | built | occiput.py: the four areas the plate rings, sunk, with the lips between them | 130 |
| foramen magnum | built | foramina.py: the plate's own outline | 129 |
| condyles | built | foramina.condyles: the facet's traced kidney, the sloping inner side | 131 |
| condyloid fossa and canal | built | foramina.py: the hollow behind the condyle, the canal's mouth | 131 |
| hypoglossal canal | built | foramina.py | 129 |
| jugular process and jugular notch | plain | the base's relief (base.py); the jugular foramen is built | 131 |
| pharyngeal tubercle | built | foramina.py: pressed in with the base's small relief | 132 |
| basilar part | built | base.py: heights from the sagittal section (Fig. 194) | 129 |
| inside: cruciate eminence, internal protuberance, grooves for the sinuses, the four fossae | missing | the cranial cavity is one smooth hollow | 130 |

## Temporal (16 of 20 built)

| Detail | State | Where, or what is lacking | Gray, page |
| --- | --- | --- | --- |
| squama | plain | the braincase's wall; its suture is cut | 138 |
| zygomatic process and its roots | built | skull2.cheek, temporal.py; the root over the joint is still a lump | 138 |
| supramastoid crest | built | temporal.relief | 139 |
| suprameatal triangle and spine | built | temporal.relief | 139 |
| articular tubercle | built | base.py: the slope from the socket's roof to the tubercle's crest | 139 |
| mandibular fossa | built | base.py, base.socket_cut | 139 |
| postglenoid process | built | temporal.ear_hole: the small process between the ear hole and the socket | 145 |
| petrotympanic fissure | missing |  | 139 |
| external acoustic meatus | built | temporal.ear_hole; its rim is too even | 139 |
| tympanic part | built | temporal.py: the thick rough lip round the ear hole | 138 |
| mastoid process | built | skull2.build, on its traced outline | 141 |
| mastoid notch (digastric) and occipital groove | built | skull2.build | 141 |
| mastoid foramen | missing | finer than the grid: as a pit it came out as a crater | 140 |
| styloid process and its sheath (vaginal process) | built | temporal.py | 138 |
| stylomastoid foramen | built | foramina.py | 141 |
| carotid canal | built | foramina.py | 141 |
| jugular fossa | built | foramina.py: the hollow and the opening | 143 |
| inferior tympanic and mastoid canaliculi, cochlear aqueduct | built | foramina.py: three small mouths where the plate places them | 144 |
| petrous part, under surface | built | base.py | 141 |
| inside: internal acoustic meatus, arcuate eminence, tegmen, sigmoid sulcus | missing | the cranial cavity is one smooth hollow | 140 |

## Sphenoid (5 of 16 built)

| Detail | State | Where, or what is lacking | Gray, page |
| --- | --- | --- | --- |
| body: sella turcica, dorsum sellae, clinoid processes | missing | the cranial cavity is one smooth hollow | 147 |
| sphenoidal sinuses | missing | the body is solid | 147 |
| rostrum | missing | the vomer's wings are there; the beak they clasp is not | 149 |
| small wings | plain | the orbit's roof behind; not shaped | 147 |
| optic foramen | plain | a round tube (skull2.build) | 147 |
| superior orbital fissure | plain | a slit (skull2.build), not its true shape | 150 |
| great wings: temporal and orbital surfaces | plain | the wall behind the orbit; marked off in the split | 148 |
| infratemporal crest | plain | base.py: the crest the wing turns up at | 150 |
| foramen rotundum | missing |  | 150 |
| foramen ovale | built | foramina.py: the plate's leaf | 150 |
| foramen spinosum and the spine | built | foramina.py, base.py | 150 |
| lateral pterygoid plate | built | pterygoid.py; thicker than the real one (the grid's limit) | 150 |
| medial pterygoid plate and hamulus | built | pterygoid.py | 151 |
| pterygoid fossa and scaphoid fossa | built | pterygoid.py | 149 |
| pterygoid canal | missing |  | 150 |
| vaginal process | missing |  | 149 |

## Ethmoid (2 of 8 built)

| Detail | State | Where, or what is lacking | Gray, page |
| --- | --- | --- | --- |
| cribriform plate and crista galli | missing | the roof of the nose is solid; the cranial cavity smooth | 153 |
| perpendicular plate | built | nose.septum | 153 |
| labyrinth and its cells | plain | a solid block between the orbits | 153 |
| lamina papyracea | plain | the orbit's inner wall; marked off in the split | 155 |
| superior nasal concha | missing |  | 153 |
| middle nasal concha | built | nose.conchae | 154 |
| uncinate process and bulla | missing |  | 154 |
| anterior and posterior ethmoidal foramina | missing |  | 154 |

## Nasal (1 of 1 built)

| Detail | State | Where, or what is lacking | Gray, page |
| --- | --- | --- | --- |
| the bone and its borders | built | the face's relief; marked off in the split (bones.py) | 156 |

## Lacrimal (0 of 2 built)

| Detail | State | Where, or what is lacking | Gray, page |
| --- | --- | --- | --- |
| the bone | plain | a plate of the orbit's inner wall; marked off in the split | 163 |
| posterior lacrimal crest, lacrimal sulcus, hamulus | missing |  | 164 |

## Maxilla (11 of 16 built)

| Detail | State | Where, or what is lacking | Gray, page |
| --- | --- | --- | --- |
| infraorbital foramen | built | skull2.build | 157 |
| infraorbital groove and canal | missing | the foramen is a short tube; no groove on the orbit's floor | 159 |
| canine fossa | built | skull2 (face relief) | 158 |
| canine eminence and the swellings over the roots | built | skull2: the tooth-bearing process | 158 |
| incisive fossa (above the incisors) | plain |  | 158 |
| anterior nasal spine | built | skull2.build: a three-cornered blade | 158 |
| nasal notch (the opening's rim) | built | skull2.aperture_rim, traced | 158 |
| frontal process | built | skull2 (face relief) | 157 |
| anterior lacrimal crest and lacrimal groove | missing | no canal for the tear duct | 161 |
| zygomatic process | built | skull2 (face relief); its suture is in the split | 158 |
| maxillary tuberosity | built | skull2.build | 158 |
| alveolar canals on the back of the jaw | missing |  | 158 |
| alveolar process and the sockets | built | teeth.py: every tooth's own socket | 161 |
| palatine process | built | palate.py | 162 |
| incisive foramen and canals | built | palate.py | 162 |
| maxillary sinus | missing | the bone is solid | 158 |

## Zygomatic (4 of 6 built)

| Detail | State | Where, or what is lacking | Gray, page |
| --- | --- | --- | --- |
| malar surface | built | skull2.cheek | 164 |
| zygomaticofacial foramen | built | a small oblique hole on the cheek surface (skull2.build) | 164 |
| frontosphenoidal process | built | skull2.cheek: a plate 5 to 6 mm thick, its hind border traced on Fig. 188 (ZYG_SIDE), hollowed behind along the orbit's outer wall | 164 |
| temporal process and the arch | built | skull2.cheek, at the usual breadth of 133 mm | 166 |
| orbital surface and its foramina | missing | the surface is there; the foramina are not | 165 |
| zygomaticotemporal foramen | missing |  | 164 |

## Palatine (6 of 8 built)

| Detail | State | Where, or what is lacking | Gray, page |
| --- | --- | --- | --- |
| horizontal part | built | palate.py | 167 |
| posterior nasal spine | built | palate.py | 167 |
| palatine crest | built | palate.py |  |
| greater palatine foramen and groove | built | palate.py | 162 |
| lesser palatine foramina | built | palate.py | 168 |
| pyramidal process | built | pterygoid.py | 168 |
| vertical part | plain | the hind part of the nose's side wall; marked off in the split | 166 |
| orbital and sphenoidal processes, sphenopalatine foramen | missing |  | 167 |

## Inferior nasal concha (1 of 2 built)

| Detail | State | Where, or what is lacking | Gray, page |
| --- | --- | --- | --- |
| the scroll | built | nose.conchae | 169 |
| lacrimal, ethmoidal and maxillary processes | missing |  | 169 |

## Vomer (2 of 3 built)

| Detail | State | Where, or what is lacking | Gray, page |
| --- | --- | --- | --- |
| the plate and its free hind border | built | nose.septum | 170 |
| alae | built | nose.septum: a leaf seen from below | 170 |
| nasopalatine groove | missing |  | 170 |

## Mandible (16 of 17 built)

| Detail | State | Where, or what is lacking | Gray, page |
| --- | --- | --- | --- |
| symphysis and mental protuberance | built | mandible4.py | 172 |
| mental tubercle | built | mandible4.py | 172 |
| incisive fossa | built | mandible4.py | 172 |
| mental foramen | built | mandible4.py | 172 |
| oblique line | built | mandible4.py | 172 |
| mental spines | built | mandible4.py | 172 |
| digastric fossa | built | mandible4.py | 173 |
| mylohyoid line | built | mandible4.py | 173 |
| hollows for the sublingual and submaxillary glands | built | mandible4.py | 173 |
| alveolar border and the sockets | built | teeth.py | 173 |
| ramus: ridges for the masseter and the medial pterygoid | built | mandible4.py | 173 |
| mandibular foramen and lingula | built | mandible4.py | 173 |
| mylohyoid groove | built | mandible4.py | 173 |
| coronoid process and mandibular notch | built | mandible4.py | 172 |
| condyloid process: head, neck, the hollow for the lateral pterygoid | built | mandible4.py | 174 |
| angle | built | mandible4.py: a round turn, about 118 degrees | 174 |
| mandibular canal | missing | inside the bone | 173 |

## Whole skull (10 of 15 built)

| Detail | State | Where, or what is lacking | Gray, page |
| --- | --- | --- | --- |
| sutures of the vault: coronal, sagittal, lambdoidal, squamosal | built | skull2.sutures, traced on Fig. 188 and checked over the plate (dev/plate_lines.py); toothed as Gray describes them, meeting at bregma and lambda | 178 |
| sutures round the great wing and the mastoid | built | skull2.sutures | 182 |
| sutures of the face | plain | walls in the split (bones.py); not cut into the one-piece skull | 186 |
| sutures of the palate | built | palate.py |  |
| orbit: margin and four walls | built | skull2.build | 183 |
| inferior orbital fissure | plain | a slit, not its true shape | 184 |
| nasolacrimal canal | missing |  | 188 |
| temporal fossa | built | bounded by the temporal lines and the frontal crest (temporal.lines_relief), hollowed behind the cheek bone and the crest (temporal.fossa_front) | 178 |
| infratemporal fossa | built | base.py, pterygoid.py | 180 |
| pterygomaxillary fissure and pterygopalatine fossa | built | pterygoid.py | 184 |
| choanae | built | left between the plates, the vomer, the body and the palate | 180 |
| foramen lacerum | built | foramina.py | 181 |
| jugular foramen | built | foramina.py | 181 |
| inside of the skull: the three fossae and their markings | missing | the cranial cavity is one smooth hollow | 190 |
| diploe and the bone's inner structure | missing |  | 132 |
