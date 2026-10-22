# Depth fade in the 3D map, in every theme

The owner, 15 Oct (about 8:35 am Cairo): "u know how deep see videos or
cell 3d high quality videos have fade for far objects ? that's how i want
performance mode to be and also all other modes too to run smoother."

Earlier the same morning, for Performance only: "make things load based on
their depth to u: for example the most surfaced is loaded and the deepest
to u is faded until u turn and they load and others fade".

This is the owner's second exception to "no fading" (the first is the
small soft rim on buttons). It is a depth cue inside the map's 3D scene,
in all three themes (Space, Neurons, Performance). It is not an interface
fade: nothing fades over time, and buttons, cards, sheets and name pills
never fade.

## The look

Deep-sea footage and high-end cell animation: what is near the camera is
crisp, bright and saturated. With distance, things lose brightness,
contrast and saturation and dissolve into the scene's own background
colour, until they are gone. Nothing pops in or out.

1. Depth is distance along the camera's view (view-space z), not distance
   from the map's centre.
2. The tilt: each map's default view is pitched about the screen's horizontal
   axis by θ (Neurons 35°, Space 45°; Performance and plain graph stay at 0).
   The camera sits on the near (south) side at `middle + Rx(θ)·(cx, cy, D)` with
   orientation `Rx(θ)`. The default camera controller has `worldUp = (0, 0, 1)`,
   spinning horizontally like a turntable; vertical drag changes the tilt, kept
   within 10–75° by vertical-angle limits (U1). A double tap re-frames the default
   view (U9). Each Space body's own frame starts turned by `Rx(θ)`
   (GraphStyleKit.frame), always (on and off states), so the factory's disk
   lean is seen exactly as face-on (ruling 8, U6); the beams, tails and
   photon ring the animator poses in the world's frame follow it.
3. The bands follow the framing's reach R, replacing fixed P1/P2. Each framing
   records reach `R = (deepest/F) - 1`, clamped to [0.15, 1.0], and crisp reach
   `c = a·R` (whole view) or `R + 0.02` (fly-in, so flown systems are crisp).
   The span runs from `F·(1 + c)` to `F·(1 + c + (b - a)·R)`, with k = 1.
   The band follows F through glides and pinches. That is the Neurons'
   band. Space's is SpaceDepth's (GraphSpaceDepth.swift, design/integration
   fed0105, which won the merge on design/merge-graph): multiples of F,
   1.15 to 2.6 on High and 1.1 to 2.0 on Smooth, with k = 1.25.
4. Turning the map brings the far side forward and it sharpens, while the
   near side goes back and fades. This follows the camera continuously,
   with no timers.
5. See-through dissolution (no tint; ruling 5 asked it of Space). A body
   dissolves into whatever lies behind it (see-through). Additive light
   fades to nothing: `rgb × (1 - f)`. Blended materials fade as
   `rgba × (1 - f)`. Opaque materials are switched at install to blended with
   no depth write so they can dissolve. `depthTint` and the solid mode are
   removed. That is the Neurons, per pixel. Space keeps the later work the
   merge chose over ruling 5 (GraphSpaceDepthStage, which hands every Space
   shader `rpFade`): a body mixes toward the sky's near-black in linear
   light by f at its centre's depth, and its glows, corona, beams, links and
   disk go to `× (1 - f)`; it dissolves its last 15% by node opacity, and
   past the end it is not drawn, animated or picked. A body too small on
   screen to show its look is a point of its colour.
6. Bounded real depth: top clusters' z becomes `A·u(id)`, u in [-1, 1) from
   FNV-1a 64. A is the largest of {0.35, 0.25, 0.15, 0} × H passing the
   legibility rule in canonical views (projected discs overlap ≤ 15%, covered ≤ 15%).
7. Additive light (glows, halos, impulses, stars, link light) fades toward
   nothing: its contribution times (1 - f).
8. Name pills are interface, so they never half-fade. A pill shows only for
   bodies in the crisp zone (lingering until f = 0.04) or when chosen, living in
   `depthPill` outside the gate (Space: the crisp zone only, and the chosen
   body is always kept whole).
9. Increase Contrast (`contrast`): whole view a and b multiplied by 1.35, most
   is 0.6, and nothing is culled (Space: the start at 1.25 F, the fade
   stopping at 0.7). Reduce Motion: unchanged.

## Smoother

1. What is fully faded is not drawn. Everything past the band's end is
   culled (the camera's far plane, or a hide per chunk or per node), so
   the far half of a big map costs nothing.
2. Inside the band, detail drops: fewer segments, no inner parts, no glow,
   and links gathered into bundles. Every switch of detail happens where
   the object is already mostly faded (f of about 0.6 or more), with
   hysteresis, so nothing visibly pops. Plan 4e's rule still holds: detail
   changes by morphing, never by cross-fading opacity between levels.
3. The Graphics setting (GraphicsQuality) sets the band. A lower quality
   pulls the end in, so less is drawn; a higher one pushes it out. The
   frame budget (4c) may pull it in further on a slow device. The frame
   rate is never lowered: it stays at the screen's own rate (120 on
   ProMotion).
4. A tapped body must be visible. Bodies past the band's end can't be
   picked. Search, the filter and fly-to still reach any body, because
   flying to it brings it into the crisp zone.

## Proof, before the owner sees it

- Frame time and draw calls before and after, on the same Mac run and the
  same scene (each theme's largest preview library), at each Graphics
  level, given as numbers (74-depth-numbers; its Space ablation takes,
  `-graphDepthPerPixel`, now measure the plain fade, as Space has no
  per-pixel shader since the merge).
- Stills near and far (70-* pose-matched pairs with -stillSky -graphFreeze -graphDepthMeter),
  a recording of a slow turn (the far side sharpening as it comes forward), and
  before and after at true proportions.
- tools/depth_crops.py reads the 70-* pairs and 75-body-frames, verifying far and
  near brightness ratios and background patch uniformity.
- An independent reviewer, in a fresh context and not the builder, passes
  them against this page before anything goes to the owner.

### C2 Pass Rules

1. Far edge fades ≥ 0.7 on every High tier in the default view, and Space culls it.
2. A fly-in's framed points have f = 0 (all crisp).
3. Legibility rule: two crisp clusters' projected discs overlap by ≤ 15% of the smaller disc,
   and each cluster flown to is covered by nearer clusters by ≤ 15%.
4. Tilt stays within 10–75° during vertical drag; double tap re-frames the default
   view within 3° of the theme's default pitch (Neurons 35°, Space 45°).
5. GraphDepthProbe confirms node opacity on an additive plane and a solid plane at 0.5
   read 0.5 ± 0.1 of full; if additive check fails, Space glows get the per-pixel shader (on/glowpx).

Open since the merge (design/merge-graph, 22 Oct): Space's band is measured
from the focus, not the framing's reach, so in the tilted default view it
fades the far edge (1.24 to 1.32 times the focus's depth in graphdepth
D14's framings) only 0.03 to 0.07 on High and culls nothing: rule 1 is not
met for Space. Rule 5's check went with Space's gate fade, which the merge
dropped for the stage's. Both wait on the next Space step.

## Who builds it

- Performance: design/perf-million, together with the depth loading
  (D1 to D5).
- Space: design/space-bodies (GraphSpaceDepthStage, T0082, on
  design/integration fed0105 and e433ca1); the tilt and the meter from
  design/neurons-depth, merged on design/merge-graph (T0108).
- Neurons: design/neurons-depth, a new stream.

Graph3DView.swift changes stay small and additive, because the Space stream
is changing it too.
