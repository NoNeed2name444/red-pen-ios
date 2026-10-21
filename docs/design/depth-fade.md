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
2. The band follows the focus. What the camera looks at (its orbit target,
   or the body it flew to) is always in the crisp zone, at every zoom. The
   fade starts behind the focus and reaches the background by the band's
   far end. Start and end are multiples of the camera's distance to its
   focus, so zooming in on a small note inside a cell looks the same at
   that scale.
3. Turning the map brings the far side forward and it sharpens, while the
   near side goes back and fades. This follows the camera continuously,
   with no timers.
4. One curve for all three themes:
   f = clamp((z - start) / (end - start), 0, 1) ^ k,
   with the colour mixed toward the background by f. This is SceneKit's
   own fog formula (fogStartDistance, fogEndDistance, fogDensityExponent),
   so the two SceneKit themes can use the built-in fog and Performance's
   Metal shader computes the same thing. Each theme tunes start, end and
   k for its look and pins them in a Foundation-only file, with Linux
   tests.
5. The fade colour is what lies behind:
   - Space: the sky's near-black.
   - Neurons: the tissue fluid (NeuronTissue's dark teal-navy).
   - Performance: the map's ground (GraphPerfScene.background).
   Where the background is not uniform (Space's sky, Neurons' glows), the
   fade colour must match what is behind each object closely enough that
   no grey veil appears. Check it against the darkest and the brightest
   parts of the background.
6. Additive light (glows, halos, impulses, stars, link light) fades toward
   nothing: its contribution times (1 - f). It never fades toward the
   fade colour, which would brighten it.
7. Name pills are interface, so they never half-fade. A pill shows only for
   bodies in the crisp zone, plus the chosen body, and comes and goes by
   the existing no-fade rules.
8. Increase Contrast (`contrast`): the fade starts later and stops short of
   the background, so far things stay distinguishable. Reduce Motion:
   unchanged, since the fade is not motion.

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
  level, given as numbers.
- Stills near and far, a recording of a slow turn (the far side sharpening
  as it comes forward), and before and after at true proportions.
- An independent reviewer, in a fresh context and not the builder, passes
  them against this page before anything goes to the owner.

## Who builds it

- Performance: design/perf-million, together with the depth loading
  (D1 to D5).
- Space: design/space-bodies, after its current step (that stream owns the
  Space shaders).
- Neurons: design/neurons-depth, a new stream.

Graph3DView.swift changes stay small and additive, because the Space stream
is changing it too.
