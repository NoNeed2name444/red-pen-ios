# The 206 bones in the atlas

Every bone of the standard adult skeleton (206: Gray's Anatomy, 1918, Osteology, public domain; OpenStax Anatomy and Physiology 2e, chapters 7 and 8, CC BY 4.0) against the atlas's structures, in both bodies. Made from the built atlas's manifest (anatomy.json) by matching each bone's structure name; tools/anatomy_bone_audit.py measures each one's shape.

Status: present (one structure is that bone), present as several structures (the bone cut into named parts), merged (the bone is part of a structure that holds others too), missing (no structure), duplicated (one bone drawn twice, or a mesh used for two bones).

| Body | Present | Merged | Missing | Duplicated | Total |
|---|---|---|---|---|---|
| male | 182 | 18 | 6 | 0 | 206 |
| female | 180 | 18 | 7 | 1 | 206 |

- Male, missing or merged: left inferior nasal concha, right inferior nasal concha, left malleus, right malleus, left incus, right incus, left stapes, right stapes, left scaphoid, right scaphoid, left lunate, right lunate, left triquetrum, right triquetrum, left pisiform, right pisiform, left trapezium, right trapezium, left trapezoid, right trapezoid, left capitate, right capitate, left hamate, right hamate.
- Female, missing or merged: left inferior nasal concha, right inferior nasal concha, left malleus, right malleus, left incus, right incus, left stapes, right stapes, hyoid bone, left scaphoid, right scaphoid, left lunate, right lunate, left triquetrum, right triquetrum, left pisiform, right pisiform, left trapezium, right trapezium, left trapezoid, right trapezoid, left capitate, right capitate, left hamate, right hamate.

## Every bone

| # | Region | Bone | Male | Female |
|---|---|---|---|---|
| 1 | Skull: cranium | frontal bone | present: `NLM_frontal_bone` | present: `NLM_frontal_bone` |
| 2 | Skull: cranium | left parietal bone | present: `NLM_parietal_bone_L` | present: `NLM_parietal_bone_L` |
| 3 | Skull: cranium | right parietal bone | present: `NLM_parietal_bone_R` | present: `NLM_parietal_bone_R` |
| 4 | Skull: cranium | left temporal bone | present: `NLM_temporal_bone_L` | present: `NLM_temporal_bone_L` |
| 5 | Skull: cranium | right temporal bone | present: `NLM_temporal_bone_R` | present: `NLM_temporal_bone_R` |
| 6 | Skull: cranium | occipital bone | present: `NLM_occipital_bone` | present: `NLM_occipital_bone` |
| 7 | Skull: cranium | sphenoid bone | present: `NLM_sphenoid_bone` | present: `NLM_sphenoid_bone` |
| 8 | Skull: cranium | ethmoid bone | present: `NLM_ethmoid_bone` | present: `NLM_ethmoid_bone` |
| 9 | Skull: face | left nasal bone | present: `NLM_nasal_bone_L` | present: `NLM_nasal_bone_L` |
| 10 | Skull: face | right nasal bone | present: `NLM_nasal_bone_R` | present: `NLM_nasal_bone_R` |
| 11 | Skull: face | left maxilla | present: `NLM_maxilla_L` | present: `NLM_maxilla_L` |
| 12 | Skull: face | right maxilla | present: `NLM_maxilla_R` | present: `NLM_maxilla_R` |
| 13 | Skull: face | left lacrimal bone | present: `NLM_lacrimal_bone_L` | present: `NLM_lacrimal_bone_L` |
| 14 | Skull: face | right lacrimal bone | present: `NLM_lacrimal_bone_R` | present: `NLM_lacrimal_bone_R` |
| 15 | Skull: face | left zygomatic bone | present: `NLM_zygomatic_bone_L` | present: `NLM_zygomatic_bone_L` |
| 16 | Skull: face | right zygomatic bone | present: `NLM_zygomatic_bone_R` | present: `NLM_zygomatic_bone_R` |
| 17 | Skull: face | left palatine bone | present: `NLM_palatine_bone_L` | present: `NLM_palatine_bone_L` |
| 18 | Skull: face | right palatine bone | present: `NLM_palatine_bone_R` | present: `NLM_palatine_bone_R` |
| 19 | Skull: face | left inferior nasal concha | merged: `NLM_maxilla_L` | merged: `NLM_maxilla_L` |
| 20 | Skull: face | right inferior nasal concha | merged: `NLM_maxilla_R` | merged: `NLM_maxilla_R` |
| 21 | Skull: face | vomer | present: `NLM_vomer` | present: `NLM_vomer` |
| 22 | Skull: face | mandible | present: `NLM_mandible` | present: `NLM_mandible` |
| 23 | Ear ossicles | left malleus | missing | missing |
| 24 | Ear ossicles | right malleus | missing | missing |
| 25 | Ear ossicles | left incus | missing | missing |
| 26 | Ear ossicles | right incus | missing | missing |
| 27 | Ear ossicles | left stapes | missing | missing |
| 28 | Ear ossicles | right stapes | missing | missing |
| 29 | Hyoid | hyoid bone | present: `VH_M_hyoid` | missing |
| 30 | Vertebral column | cervical vertebra 1 (atlas) | present: `VH_M_cervical_vertebra_1` | present: `VH_F_cervical_vertebra_1` |
| 31 | Vertebral column | cervical vertebra 2 (axis) | present: `VH_M_cervical_vertebra_2` | present: `VH_F_cervical_vertebra_2` |
| 32 | Vertebral column | cervical vertebra 3 | present: `VH_M_cervical_vertebra_3` | present: `VH_F_cervical_vertebra_3` |
| 33 | Vertebral column | cervical vertebra 4 | present: `VH_M_cervical_vertebra_4` | present: `VH_F_cervical_vertebra_4` |
| 34 | Vertebral column | cervical vertebra 5 | present: `VH_M_cervical_vertebra_5` | present: `VH_F_cervical_vertebra_5` |
| 35 | Vertebral column | cervical vertebra 6 | present: `VH_M_cervical_vertebra_6` | present: `VH_F_cervical_vertebra_6` |
| 36 | Vertebral column | cervical vertebra 7 | present: `VH_M_cervical_vertebra_7` | present: `VH_F_cervical_vertebra_7` |
| 37 | Vertebral column | thoracic vertebra 1 | present: `VH_M_thoracic_vertebra_1` | present: `VH_F_thoracic_vertebra_1` |
| 38 | Vertebral column | thoracic vertebra 2 | present: `VH_M_thoracic_vertebra_2` | present: `VH_F_thoracic_vertebra_2` |
| 39 | Vertebral column | thoracic vertebra 3 | present: `VH_M_thoracic_vertebra_3` | present: `VH_F_thoracic_vertebra_3` |
| 40 | Vertebral column | thoracic vertebra 4 | present: `VH_M_thoracic_vertebra_4` | present: `VH_F_thoracic_vertebra_4` |
| 41 | Vertebral column | thoracic vertebra 5 | present: `VH_M_thoracic_vertebra_5` | present: `VH_F_thoracic_vertebra_5` |
| 42 | Vertebral column | thoracic vertebra 6 | present: `VH_M_thoracic_vertebra_6` | present: `VH_F_thoracic_vertebra_6` |
| 43 | Vertebral column | thoracic vertebra 7 | present: `VH_M_thoracic_vertebra_7` | present: `VH_F_thoracic_vertebra_7` |
| 44 | Vertebral column | thoracic vertebra 8 | present: `VH_M_thoracic_vertebra_8` | present: `VH_F_thoracic_vertebra_8` |
| 45 | Vertebral column | thoracic vertebra 9 | present: `VH_M_thoracic_vertebra_9` | present: `VH_F_thoracic_vertebra_9` |
| 46 | Vertebral column | thoracic vertebra 10 | present: `VH_M_thoracic_vertebra_10` | present: `VH_F_thoracic_vertebra_10` |
| 47 | Vertebral column | thoracic vertebra 11 | present: `VH_M_thoracic_vertebra_11` | present: `VH_F_thoracic_vertebra_11` |
| 48 | Vertebral column | thoracic vertebra 12 | present: `VH_M_thoracic_vertebra_12` | present: `VH_F_thoracic_vertebra_12` |
| 49 | Vertebral column | lumbar vertebra 1 | present: `VH_M_lumbar_vertebra_1` | present: `VH_F_lumbar_vertebra_1` |
| 50 | Vertebral column | lumbar vertebra 2 | present: `VH_M_lumbar_vertebra_2` | present: `VH_F_lumbar_vertebra_2` |
| 51 | Vertebral column | lumbar vertebra 3 | present: `VH_M_lumbar_vertebra_3` | present: `VH_F_lumbar_vertebra_3` |
| 52 | Vertebral column | lumbar vertebra 4 | present: `VH_M_lumbar_vertebra_4` | duplicated, the same scanned bone as her third lumbar vertebra (KA 25's third, used twice): `VH_F_lumbar_vertebra_4` |
| 53 | Vertebral column | lumbar vertebra 5 | present: `VH_M_lumbar_vertebra_5` | present: `VH_F_lumbar_vertebra_5` |
| 54 | Vertebral column | sacrum | present: `VH_M_sacrum` | present: `VH_F_sacrum` |
| 55 | Vertebral column | coccyx | present: `VH_M_coccyx` | present: `VH_F_coccyx` |
| 56 | Thoracic cage | sternum | present: `TS_sternum` | present, as 2 structures: `VH_F_manubrium`, `VH_F_sternum` |
| 57 | Thoracic cage | left rib 1 | present: `TS_rib_1_L` | present: `TS_rib_1_L` |
| 58 | Thoracic cage | right rib 1 | present: `TS_rib_1_R` | present: `TS_rib_1_R` |
| 59 | Thoracic cage | left rib 2 | present: `TS_rib_2_L` | present: `TS_rib_2_L` |
| 60 | Thoracic cage | right rib 2 | present: `TS_rib_2_R` | present: `TS_rib_2_R` |
| 61 | Thoracic cage | left rib 3 | present: `TS_rib_3_L` | present: `TS_rib_3_L` |
| 62 | Thoracic cage | right rib 3 | present: `TS_rib_3_R` | present: `TS_rib_3_R` |
| 63 | Thoracic cage | left rib 4 | present: `TS_rib_4_L` | present: `TS_rib_4_L` |
| 64 | Thoracic cage | right rib 4 | present: `TS_rib_4_R` | present: `TS_rib_4_R` |
| 65 | Thoracic cage | left rib 5 | present: `TS_rib_5_L` | present: `TS_rib_5_L` |
| 66 | Thoracic cage | right rib 5 | present: `TS_rib_5_R` | present: `TS_rib_5_R` |
| 67 | Thoracic cage | left rib 6 | present: `TS_rib_6_L` | present: `TS_rib_6_L` |
| 68 | Thoracic cage | right rib 6 | present: `TS_rib_6_R` | present: `TS_rib_6_R` |
| 69 | Thoracic cage | left rib 7 | present: `TS_rib_7_L` | present: `TS_rib_7_L` |
| 70 | Thoracic cage | right rib 7 | present: `TS_rib_7_R` | present: `TS_rib_7_R` |
| 71 | Thoracic cage | left rib 8 | present: `TS_rib_8_L` | present: `TS_rib_8_L` |
| 72 | Thoracic cage | right rib 8 | present: `TS_rib_8_R` | present: `TS_rib_8_R` |
| 73 | Thoracic cage | left rib 9 | present: `TS_rib_9_L` | present: `TS_rib_9_L` |
| 74 | Thoracic cage | right rib 9 | present: `TS_rib_9_R` | present: `TS_rib_9_R` |
| 75 | Thoracic cage | left rib 10 | present: `TS_rib_10_L` | present: `TS_rib_10_L` |
| 76 | Thoracic cage | right rib 10 | present: `TS_rib_10_R` | present: `TS_rib_10_R` |
| 77 | Thoracic cage | left rib 11 | present: `TS_rib_11_L` | present: `TS_rib_11_L` |
| 78 | Thoracic cage | right rib 11 | present: `TS_rib_11_R` | present: `TS_rib_11_R` |
| 79 | Thoracic cage | left rib 12 | present: `TS_rib_12_L` | present: `TS_rib_12_L` |
| 80 | Thoracic cage | right rib 12 | present: `TS_rib_12_R` | present: `TS_rib_12_R` |
| 81 | Pectoral girdle | left clavicle | present: `TS_clavicle_L` | present: `TS_clavicle_L` |
| 82 | Pectoral girdle | right clavicle | present: `TS_clavicle_R` | present: `TS_clavicle_R` |
| 83 | Pectoral girdle | left scapula | present: `TS_scapula_L` | present: `TS_scapula_L` |
| 84 | Pectoral girdle | right scapula | present: `TS_scapula_R` | present: `TS_scapula_R` |
| 85 | Upper limb | left humerus | present: `TS_humerus_L` | present: `TS_humerus_L` |
| 86 | Upper limb | right humerus | present: `TS_humerus_R` | present: `TS_humerus_R` |
| 87 | Upper limb | left radius | present: `TS_radius_L` | present: `TS_radius_L` |
| 88 | Upper limb | right radius | present: `TS_radius_R` | present: `TS_radius_R` |
| 89 | Upper limb | left ulna | present: `TS_ulna_L` | present: `TS_ulna_L` |
| 90 | Upper limb | right ulna | present: `TS_ulna_R` | present: `TS_ulna_R` |
| 91 | Upper limb: carpus | left scaphoid | merged: `TS_carpal_bones_L` | merged: `TS_carpal_bones_L` |
| 92 | Upper limb: carpus | right scaphoid | merged: `TS_carpal_bones_R` | merged: `TS_carpal_bones_R` |
| 93 | Upper limb: carpus | left lunate | merged: `TS_carpal_bones_L` | merged: `TS_carpal_bones_L` |
| 94 | Upper limb: carpus | right lunate | merged: `TS_carpal_bones_R` | merged: `TS_carpal_bones_R` |
| 95 | Upper limb: carpus | left triquetrum | merged: `TS_carpal_bones_L` | merged: `TS_carpal_bones_L` |
| 96 | Upper limb: carpus | right triquetrum | merged: `TS_carpal_bones_R` | merged: `TS_carpal_bones_R` |
| 97 | Upper limb: carpus | left pisiform | merged: `TS_carpal_bones_L` | merged: `TS_carpal_bones_L` |
| 98 | Upper limb: carpus | right pisiform | merged: `TS_carpal_bones_R` | merged: `TS_carpal_bones_R` |
| 99 | Upper limb: carpus | left trapezium | merged: `TS_carpal_bones_L` | merged: `TS_carpal_bones_L` |
| 100 | Upper limb: carpus | right trapezium | merged: `TS_carpal_bones_R` | merged: `TS_carpal_bones_R` |
| 101 | Upper limb: carpus | left trapezoid | merged: `TS_carpal_bones_L` | merged: `TS_carpal_bones_L` |
| 102 | Upper limb: carpus | right trapezoid | merged: `TS_carpal_bones_R` | merged: `TS_carpal_bones_R` |
| 103 | Upper limb: carpus | left capitate | merged: `TS_carpal_bones_L` | merged: `TS_carpal_bones_L` |
| 104 | Upper limb: carpus | right capitate | merged: `TS_carpal_bones_R` | merged: `TS_carpal_bones_R` |
| 105 | Upper limb: carpus | left hamate | merged: `TS_carpal_bones_L` | merged: `TS_carpal_bones_L` |
| 106 | Upper limb: carpus | right hamate | merged: `TS_carpal_bones_R` | merged: `TS_carpal_bones_R` |
| 107 | Upper limb: metacarpus | left first metacarpal | present: `TS_first_metacarpal_L` | present: `TS_first_metacarpal_L` |
| 108 | Upper limb: metacarpus | right first metacarpal | present: `TS_first_metacarpal_R` | present: `TS_first_metacarpal_R` |
| 109 | Upper limb: metacarpus | left second metacarpal | present: `TS_second_metacarpal_L` | present: `TS_second_metacarpal_L` |
| 110 | Upper limb: metacarpus | right second metacarpal | present: `TS_second_metacarpal_R` | present: `TS_second_metacarpal_R` |
| 111 | Upper limb: metacarpus | left third metacarpal | present: `TS_third_metacarpal_L` | present: `TS_third_metacarpal_L` |
| 112 | Upper limb: metacarpus | right third metacarpal | present: `TS_third_metacarpal_R` | present: `TS_third_metacarpal_R` |
| 113 | Upper limb: metacarpus | left fourth metacarpal | present: `TS_fourth_metacarpal_L` | present: `TS_fourth_metacarpal_L` |
| 114 | Upper limb: metacarpus | right fourth metacarpal | present: `TS_fourth_metacarpal_R` | present: `TS_fourth_metacarpal_R` |
| 115 | Upper limb: metacarpus | left fifth metacarpal | present: `TS_fifth_metacarpal_L` | present: `TS_fifth_metacarpal_L` |
| 116 | Upper limb: metacarpus | right fifth metacarpal | present: `TS_fifth_metacarpal_R` | present: `TS_fifth_metacarpal_R` |
| 117 | Upper limb: phalanges | left proximal phalanx of thumb | present: `TS_proximal_phalanx_of_thumb_L` | present: `TS_proximal_phalanx_of_thumb_L` |
| 118 | Upper limb: phalanges | right proximal phalanx of thumb | present: `TS_proximal_phalanx_of_thumb_R` | present: `TS_proximal_phalanx_of_thumb_R` |
| 119 | Upper limb: phalanges | left distal phalanx of thumb | present: `TS_distal_phalanx_of_thumb_L` | present: `TS_distal_phalanx_of_thumb_L` |
| 120 | Upper limb: phalanges | right distal phalanx of thumb | present: `TS_distal_phalanx_of_thumb_R` | present: `TS_distal_phalanx_of_thumb_R` |
| 121 | Upper limb: phalanges | left proximal phalanx of index finger | present: `TS_proximal_phalanx_of_index_finger_L` | present: `TS_proximal_phalanx_of_index_finger_L` |
| 122 | Upper limb: phalanges | right proximal phalanx of index finger | present: `TS_proximal_phalanx_of_index_finger_R` | present: `TS_proximal_phalanx_of_index_finger_R` |
| 123 | Upper limb: phalanges | left middle phalanx of index finger | present: `TS_middle_phalanx_of_index_finger_L` | present: `TS_middle_phalanx_of_index_finger_L` |
| 124 | Upper limb: phalanges | right middle phalanx of index finger | present: `TS_middle_phalanx_of_index_finger_R` | present: `TS_middle_phalanx_of_index_finger_R` |
| 125 | Upper limb: phalanges | left distal phalanx of index finger | present: `TS_distal_phalanx_of_index_finger_L` | present: `TS_distal_phalanx_of_index_finger_L` |
| 126 | Upper limb: phalanges | right distal phalanx of index finger | present: `TS_distal_phalanx_of_index_finger_R` | present: `TS_distal_phalanx_of_index_finger_R` |
| 127 | Upper limb: phalanges | left proximal phalanx of middle finger | present: `TS_proximal_phalanx_of_middle_finger_L` | present: `TS_proximal_phalanx_of_middle_finger_L` |
| 128 | Upper limb: phalanges | right proximal phalanx of middle finger | present: `TS_proximal_phalanx_of_middle_finger_R` | present: `TS_proximal_phalanx_of_middle_finger_R` |
| 129 | Upper limb: phalanges | left middle phalanx of middle finger | present: `TS_middle_phalanx_of_middle_finger_L` | present: `TS_middle_phalanx_of_middle_finger_L` |
| 130 | Upper limb: phalanges | right middle phalanx of middle finger | present: `TS_middle_phalanx_of_middle_finger_R` | present: `TS_middle_phalanx_of_middle_finger_R` |
| 131 | Upper limb: phalanges | left distal phalanx of middle finger | present: `TS_distal_phalanx_of_middle_finger_L` | present: `TS_distal_phalanx_of_middle_finger_L` |
| 132 | Upper limb: phalanges | right distal phalanx of middle finger | present: `TS_distal_phalanx_of_middle_finger_R` | present: `TS_distal_phalanx_of_middle_finger_R` |
| 133 | Upper limb: phalanges | left proximal phalanx of ring finger | present: `TS_proximal_phalanx_of_ring_finger_L` | present: `TS_proximal_phalanx_of_ring_finger_L` |
| 134 | Upper limb: phalanges | right proximal phalanx of ring finger | present: `TS_proximal_phalanx_of_ring_finger_R` | present: `TS_proximal_phalanx_of_ring_finger_R` |
| 135 | Upper limb: phalanges | left middle phalanx of ring finger | present: `TS_middle_phalanx_of_ring_finger_L` | present: `TS_middle_phalanx_of_ring_finger_L` |
| 136 | Upper limb: phalanges | right middle phalanx of ring finger | present: `TS_middle_phalanx_of_ring_finger_R` | present: `TS_middle_phalanx_of_ring_finger_R` |
| 137 | Upper limb: phalanges | left distal phalanx of ring finger | present: `TS_distal_phalanx_of_ring_finger_L` | present: `TS_distal_phalanx_of_ring_finger_L` |
| 138 | Upper limb: phalanges | right distal phalanx of ring finger | present: `TS_distal_phalanx_of_ring_finger_R` | present: `TS_distal_phalanx_of_ring_finger_R` |
| 139 | Upper limb: phalanges | left proximal phalanx of little finger | present: `TS_proximal_phalanx_of_little_finger_L` | present: `TS_proximal_phalanx_of_little_finger_L` |
| 140 | Upper limb: phalanges | right proximal phalanx of little finger | present: `TS_proximal_phalanx_of_little_finger_R` | present: `TS_proximal_phalanx_of_little_finger_R` |
| 141 | Upper limb: phalanges | left middle phalanx of little finger | present: `TS_middle_phalanx_of_little_finger_L` | present: `TS_middle_phalanx_of_little_finger_L` |
| 142 | Upper limb: phalanges | right middle phalanx of little finger | present: `TS_middle_phalanx_of_little_finger_R` | present: `TS_middle_phalanx_of_little_finger_R` |
| 143 | Upper limb: phalanges | left distal phalanx of little finger | present: `TS_distal_phalanx_of_little_finger_L` | present: `TS_distal_phalanx_of_little_finger_L` |
| 144 | Upper limb: phalanges | right distal phalanx of little finger | present: `TS_distal_phalanx_of_little_finger_R` | present: `TS_distal_phalanx_of_little_finger_R` |
| 145 | Pelvic girdle | left hip bone | present, as 3 structures: `VH_M_pubis_compact_bone_L`, `VH_M_ilium_compact_bone_L`, `VH_M_ischium_compact_bone_L` | present: `TS_hip_L` |
| 146 | Pelvic girdle | right hip bone | present, as 3 structures: `VH_M_pubis_compact_bone_R`, `VH_M_ilium_compact_bone_R`, `VH_M_ischium_compact_bone_R` | present: `TS_hip_R` |
| 147 | Lower limb | left femur | present: `VH_M_femur_L` | present: `VH_F_femur_L` |
| 148 | Lower limb | right femur | present: `VH_M_femur_R` | present: `VH_F_femur_R` |
| 149 | Lower limb | left patella | present: `VH_M_patella_L` | present: `VH_F_patella_L` |
| 150 | Lower limb | right patella | present: `VH_M_patella_R` | present: `VH_F_patella_R` |
| 151 | Lower limb | left tibia | present: `VH_M_tibia_L` | present: `VH_F_tibia_L` |
| 152 | Lower limb | right tibia | present: `VH_M_tibia_R` | present: `VH_F_tibia_R` |
| 153 | Lower limb | left fibula | present: `VH_M_fibula_L` | present: `VH_F_fibula_L` |
| 154 | Lower limb | right fibula | present: `VH_M_fibula_R` | present: `VH_F_fibula_R` |
| 155 | Lower limb: tarsus | left talus | present: `TS_talus_L` | present: `TS_talus_L` |
| 156 | Lower limb: tarsus | right talus | present: `TS_talus_R` | present: `TS_talus_R` |
| 157 | Lower limb: tarsus | left calcaneus | present: `TS_calcaneus_L` | present: `TS_calcaneus_L` |
| 158 | Lower limb: tarsus | right calcaneus | present: `TS_calcaneus_R` | present: `TS_calcaneus_R` |
| 159 | Lower limb: tarsus | left navicular | present: `TS_navicular_L` | present: `TS_navicular_L` |
| 160 | Lower limb: tarsus | right navicular | present: `TS_navicular_R` | present: `TS_navicular_R` |
| 161 | Lower limb: tarsus | left cuboid | present: `TS_cuboid_L` | present: `TS_cuboid_L` |
| 162 | Lower limb: tarsus | right cuboid | present: `TS_cuboid_R` | present: `TS_cuboid_R` |
| 163 | Lower limb: tarsus | left medial cuneiform | present: `TS_medial_cuneiform_L` | present: `TS_medial_cuneiform_L` |
| 164 | Lower limb: tarsus | right medial cuneiform | present: `TS_medial_cuneiform_R` | present: `TS_medial_cuneiform_R` |
| 165 | Lower limb: tarsus | left intermediate cuneiform | present: `TS_intermediate_cuneiform_L` | present: `TS_intermediate_cuneiform_L` |
| 166 | Lower limb: tarsus | right intermediate cuneiform | present: `TS_intermediate_cuneiform_R` | present: `TS_intermediate_cuneiform_R` |
| 167 | Lower limb: tarsus | left lateral cuneiform | present: `TS_lateral_cuneiform_L` | present: `TS_lateral_cuneiform_L` |
| 168 | Lower limb: tarsus | right lateral cuneiform | present: `TS_lateral_cuneiform_R` | present: `TS_lateral_cuneiform_R` |
| 169 | Lower limb: metatarsus | left first metatarsal | present: `TS_first_metatarsal_L` | present: `TS_first_metatarsal_L` |
| 170 | Lower limb: metatarsus | right first metatarsal | present: `TS_first_metatarsal_R` | present: `TS_first_metatarsal_R` |
| 171 | Lower limb: metatarsus | left second metatarsal | present: `TS_second_metatarsal_L` | present: `TS_second_metatarsal_L` |
| 172 | Lower limb: metatarsus | right second metatarsal | present: `TS_second_metatarsal_R` | present: `TS_second_metatarsal_R` |
| 173 | Lower limb: metatarsus | left third metatarsal | present: `TS_third_metatarsal_L` | present: `TS_third_metatarsal_L` |
| 174 | Lower limb: metatarsus | right third metatarsal | present: `TS_third_metatarsal_R` | present: `TS_third_metatarsal_R` |
| 175 | Lower limb: metatarsus | left fourth metatarsal | present: `TS_fourth_metatarsal_L` | present: `TS_fourth_metatarsal_L` |
| 176 | Lower limb: metatarsus | right fourth metatarsal | present: `TS_fourth_metatarsal_R` | present: `TS_fourth_metatarsal_R` |
| 177 | Lower limb: metatarsus | left fifth metatarsal | present: `TS_fifth_metatarsal_L` | present: `TS_fifth_metatarsal_L` |
| 178 | Lower limb: metatarsus | right fifth metatarsal | present: `TS_fifth_metatarsal_R` | present: `TS_fifth_metatarsal_R` |
| 179 | Lower limb: phalanges | left proximal phalanx of great toe | present: `TS_proximal_phalanx_of_great_toe_L` | present: `TS_proximal_phalanx_of_great_toe_L` |
| 180 | Lower limb: phalanges | right proximal phalanx of great toe | present: `TS_proximal_phalanx_of_great_toe_R` | present: `TS_proximal_phalanx_of_great_toe_R` |
| 181 | Lower limb: phalanges | left distal phalanx of great toe | present: `TS_distal_phalanx_of_great_toe_L` | present: `TS_distal_phalanx_of_great_toe_L` |
| 182 | Lower limb: phalanges | right distal phalanx of great toe | present: `TS_distal_phalanx_of_great_toe_R` | present: `TS_distal_phalanx_of_great_toe_R` |
| 183 | Lower limb: phalanges | left proximal phalanx of second toe | present: `TS_proximal_phalanx_of_second_toe_L` | present: `TS_proximal_phalanx_of_second_toe_L` |
| 184 | Lower limb: phalanges | right proximal phalanx of second toe | present: `TS_proximal_phalanx_of_second_toe_R` | present: `TS_proximal_phalanx_of_second_toe_R` |
| 185 | Lower limb: phalanges | left middle phalanx of second toe | present: `TS_middle_phalanx_of_second_toe_L` | present: `TS_middle_phalanx_of_second_toe_L` |
| 186 | Lower limb: phalanges | right middle phalanx of second toe | present: `TS_middle_phalanx_of_second_toe_R` | present: `TS_middle_phalanx_of_second_toe_R` |
| 187 | Lower limb: phalanges | left distal phalanx of second toe | present: `TS_distal_phalanx_of_second_toe_L` | present: `TS_distal_phalanx_of_second_toe_L` |
| 188 | Lower limb: phalanges | right distal phalanx of second toe | present: `TS_distal_phalanx_of_second_toe_R` | present: `TS_distal_phalanx_of_second_toe_R` |
| 189 | Lower limb: phalanges | left proximal phalanx of third toe | present: `TS_proximal_phalanx_of_third_toe_L` | present: `TS_proximal_phalanx_of_third_toe_L` |
| 190 | Lower limb: phalanges | right proximal phalanx of third toe | present: `TS_proximal_phalanx_of_third_toe_R` | present: `TS_proximal_phalanx_of_third_toe_R` |
| 191 | Lower limb: phalanges | left middle phalanx of third toe | present: `TS_middle_phalanx_of_third_toe_L` | present: `TS_middle_phalanx_of_third_toe_L` |
| 192 | Lower limb: phalanges | right middle phalanx of third toe | present: `TS_middle_phalanx_of_third_toe_R` | present: `TS_middle_phalanx_of_third_toe_R` |
| 193 | Lower limb: phalanges | left distal phalanx of third toe | present: `TS_distal_phalanx_of_third_toe_L` | present: `TS_distal_phalanx_of_third_toe_L` |
| 194 | Lower limb: phalanges | right distal phalanx of third toe | present: `TS_distal_phalanx_of_third_toe_R` | present: `TS_distal_phalanx_of_third_toe_R` |
| 195 | Lower limb: phalanges | left proximal phalanx of fourth toe | present: `TS_proximal_phalanx_of_fourth_toe_L` | present: `TS_proximal_phalanx_of_fourth_toe_L` |
| 196 | Lower limb: phalanges | right proximal phalanx of fourth toe | present: `TS_proximal_phalanx_of_fourth_toe_R` | present: `TS_proximal_phalanx_of_fourth_toe_R` |
| 197 | Lower limb: phalanges | left middle phalanx of fourth toe | present: `TS_middle_phalanx_of_fourth_toe_L` | present: `TS_middle_phalanx_of_fourth_toe_L` |
| 198 | Lower limb: phalanges | right middle phalanx of fourth toe | present: `TS_middle_phalanx_of_fourth_toe_R` | present: `TS_middle_phalanx_of_fourth_toe_R` |
| 199 | Lower limb: phalanges | left distal phalanx of fourth toe | present: `TS_distal_phalanx_of_fourth_toe_L` | present: `TS_distal_phalanx_of_fourth_toe_L` |
| 200 | Lower limb: phalanges | right distal phalanx of fourth toe | present: `TS_distal_phalanx_of_fourth_toe_R` | present: `TS_distal_phalanx_of_fourth_toe_R` |
| 201 | Lower limb: phalanges | left proximal phalanx of little toe | present: `TS_proximal_phalanx_of_little_toe_L` | present: `TS_proximal_phalanx_of_little_toe_L` |
| 202 | Lower limb: phalanges | right proximal phalanx of little toe | present: `TS_proximal_phalanx_of_little_toe_R` | present: `TS_proximal_phalanx_of_little_toe_R` |
| 203 | Lower limb: phalanges | left middle phalanx of little toe | present: `TS_middle_phalanx_of_little_toe_L` | present: `TS_middle_phalanx_of_little_toe_L` |
| 204 | Lower limb: phalanges | right middle phalanx of little toe | present: `TS_middle_phalanx_of_little_toe_R` | present: `TS_middle_phalanx_of_little_toe_R` |
| 205 | Lower limb: phalanges | left distal phalanx of little toe | present: `TS_distal_phalanx_of_little_toe_L` | present: `TS_distal_phalanx_of_little_toe_L` |
| 206 | Lower limb: phalanges | right distal phalanx of little toe | present: `TS_distal_phalanx_of_little_toe_R` | present: `TS_distal_phalanx_of_little_toe_R` |

## Bone structures that are none of the 206

The woman's sixth lumbar vertebra is her own column's (a normal variant: 25 vertebrae above the sacrum), drawn with KA 25's fifth; the great toe's two sesamoids are one structure a side. The right hand and foot of each body are the mirror images of the left (the man's) or the left of the right (the woman's), as scanned: not counted as duplicated.

- Male: `TS_sesamoid_bones_of_the_great_toe_L` (left sesamoid bones of the great toe); `TS_sesamoid_bones_of_the_great_toe_R` (right sesamoid bones of the great toe).
- Female: `VH_F_lumbar_vertebra_6` (sixth lumbar vertebra (a normal variant)); `TS_sesamoid_bones_of_the_great_toe_L` (left sesamoid bones of the great toe); `TS_sesamoid_bones_of_the_great_toe_R` (right sesamoid bones of the great toe).

