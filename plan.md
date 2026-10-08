# What to continue

The running plan for this repo: what is in progress, what comes next, and how
to pick it up. Read it right after CLAUDE.md at the start of every session.

Keep it current. Tick a step when it's done, add new requests and tasks as
they come, and commit this file with the work it describes. When a session's
context runs low, update "State" and "Next steps", commit and push, then start
the next session with: "Read CLAUDE.md and plan.md, then continue from Next
steps."

This is the short, running list. The full roadmap and the app-state handoff
stay in the Chat-me repo (NoNeed2name444/chat-me, branch personal):
docs/architecture/handoff/context.md (wins on app state) and plan.md (its §3d
is the 3D map's hierarchy). Both repos are public, so never put the owner's
files, images or anything private in either.

Last updated: 2026-10-08, 6:15 PM Cairo.

## 1. Working with the owner

- The owner has only an iPhone and an iPad. Anything that needs a Mac (the app
  build, screenshots, recordings) runs in GitHub Actions.
- Give times in Cairo time: `TZ=Africa/Cairo date '+%I:%M %p'`. When the owner
  asks how long is left, give an ETA, and say early if it slips.
- Post only when something lands or fails. When a "hasn't heard from you"
  reminder comes, answer with a few words of status and keep working.
- Don't idle-wait, and don't ask what you can settle yourself: make the
  sensible choice and say what you chose.
- Send screenshots of every visual change with SendUserFile. No zip files.
- Macaly is dropped: never mention it, its connector or its auth notices, and
  don't relay any other connector's auth notices either.

## 2. State

| Branch | Head | What it holds |
|---|---|---|
| wip/3d-neurons-m3 | the close-up redraw ("Neurons: the cell redrawn after the circled close-up") | M3 in progress; the Linux suites pass on the redraw; 8a18676 (the look before it) compiled on the Mac (App build run 37793822496, green) |
| design/3d-overhaul | the wip head once pushed | M1 (c122abb, Space), M2 (no Circuit, d4cff03) and the M3 code; the redraw's App build here is the compile check for GraphNeuronLook (far neurons, CoreImage blur) |
| preview/3d-overhaul | 44e42e7 (the look the owner rejected) | a push here makes screenshots (don't push here while a run is in progress: a push cancels it) |
| shots/3d-overhaul | d608991 | where design-preview.yml commits them |
| personal, claude/new-session-013tes5v | 3827785 | personal is the working branch; keep session branches equal to it |

- M3 is being continued in the cloud session "M3 Neurons rebuild, continued",
  started 2026-10-08 at about 4 PM Cairo. Check its branch before starting
  the same steps elsewhere.
- wip/3d-neurons-m3 holds:
  - the new planner, roles, states, touch model and legend, with their tests.
    The Linux suites anatomy, labels, linklength, neuronlook, neurons, shaders
    and touch pass.
  - ad91f10: the start of the GraphNeuronLook.swift rewrite (its header and
    the new NeuronCellKind).
  - af94d88, from the new session: "Neurons: grow cells from the soma, open
    containers in place". It finishes GraphNeuronLook and changes the
    shaders, GraphRibbons (a width step, so links taper from a thick base)
    and GraphThemeScene (only the plan's links are drawn, so closed cells
    never show what they hide).
  - 5909600, from the new session: "Neurons: open a cell by flying in, grow
    its insides out of it" (Graph3DView, GraphMotion, GraphDeathScene,
    GraphThemeScene).
  - Whether the app builds is for their App builds to say. Run 37781421602
    (af94d88) was cancelled, superseded by run 37781812785, which builds
    5909600 and so covers both.
  - The preview fly path: `-graphPreviewFly Examples,Inguinal` flies in to
    each folder in turn, waiting for each to appear (a part is only on the
    map once its cell has opened). testNeuronsFlyIn opens Examples (shots
    14, 15); the new testNeuronsOpenInTurn opens Examples, then Inguinal
    inside it (shots 20 to 22). testNeuronsAtRest now checks the summary
    for "cell" (the old "regions" and "glia" are gone).
- Swift tests on design/3d-overhaul (run 37784371979) went red at 4:37 PM
  with all 71 suites passing: the same commit was tested on design/ and
  preview/ at once, and both runs force-pushed their logs to the
  swift-tests branch at the same moment ("cannot lock ref"). The log
  pushes now retry once (swift-tests.yml); b02e48a's run (37786312064)
  passed.
- The owner rejected the 44e42e7 look ("it's completely different from
  what i want from u. i only want what is marked in white") and circled the
  big labelled neuron close-up on their board. The cells are redrawn after
  that close-up only (section 4, "The look"): no ringed orbs, no threads,
  no circuits. GraphNeuronLook only compiles on the Mac, so its App build
  on design/ is the check.
- The wip App build (run 37781812785, 5909600) ran the whole UI suite on a
  simulator after its compile (design/ branches skip it), then hit its
  60-minute limit. Two map tests failed:
  - testNeuronsAtRest, on the old "regions" check (fixed in 6847330);
  - testHoldForOptions: in Neurons, "Heart failure" is inside the closed
    Cardiology cell, so there was nothing to hold. The test now flies in to
    Cardiology first and names the theme when it fails. It failed on
    personal's 3827785 too (run 37757846270), perhaps in Space as well.
  - The accessibility tests fail on personal as well ("no example mcq set
    in the library"); that step is continue-on-error and not the map's.
- Shot 13 ("landscape") is portrait on the iPhone because the iPhone app
  is portrait-only (project.yml); only the iPad turns.
- app-build.yml runs on every push to personal and design/**. Keep work in
  progress on wip/3d-neurons-m3 until the app compiles. To compile-check it
  there, dispatch the build:
  `gh workflow run app-build.yml --ref wip/3d-neurons-m3`, then
  `python3 tools/ci_status.py wip/3d-neurons-m3 --wait`.
  SceneKit files can't be type-checked on Linux, so this is the only compile
  check for GraphNeuronLook, GraphThemeScene, Graph3DView and GraphSim.
- Promised: screenshots of the new Neurons look around 10:30 PM Cairo,
  2026-10-08 (moved from 9 PM).

## 3. Next steps

Steps 1 to 4 are in af94d88 and 5909600: the suites pass (preflight, 4:22
PM) and the app compiles (run 37781812785's Build step, 4:25 PM).

1. [x] Finish GraphNeuronLook.swift (design A in section 4).
2. [x] Do the soma and axon shaders (B, C) and the ribbon writer's width steps
   (D). Run the suites: `--only shaders,neuronlook,neurons,linklength,touch,labels,anatomy,death`.
3. [x] Do GraphThemeScene (E). Commit and push to wip, dispatch app-build
   there, and fix what fails.
4. [x] Open cells from the view (F), and animate openings and closings in
   GraphSim (G). Run the suites and app-build again.
5. [x] Run preflight. Then push to design/3d-overhaul and preview/3d-overhaul
   (both fast-forwards) and watch CI.
6. [ ] Fetch shots/3d-overhaul and send the owner the Neurons shots: at rest,
   a cell opened with its parts and notes inside, and axons growing out of
   the cells. The preview flies into a cell (shots 14, 15) and then a part
   inside it (20 to 22). For a quick look first, dispatch only those:
   `gh workflow run design-preview.yml --ref preview/3d-overhaul -f only=testNeurons`
   (it cancels a running push-started run on the same branch).
7. [ ] When CI is green, merge design/3d-overhaul into personal (no
   force-push), and bring the session branches up to personal.
6a. [x] Redraw the cells after the owner's reference: purple-magenta
   somas, golden-amber dendrites, ringed orbs joined by threads. Rejected
   by the owner (8 Oct, 6 PM): they want only the circled close-up.
6b. [ ] Redraw the cell after the circled close-up (section 4, "The look"):
   glass soma, deep-violet nucleus with a bright star, golden filament
   light, glass dendrites with golden light, beaded glass axon with a
   golden bouton, far blurred blue neurons and gold and blue bokeh behind.
   Code and Linux suites done; next: App build on design/, then step 6.
8. [x] #33, the neumorphic app, is not this session's: another session is
   making it (the owner, 8 Oct, 4:16 PM: "anotger session is already making
   the neumorphic part"). Leave it alone here.

## 4. M3: the Neurons rebuild

### What the owner asked (verbatim, newest first)

> it's completely different from what i want from u. i only want what is marked in white

With a picture of their design board, the big labelled neuron close-up at
the top right circled in white ("Neuron cell body / Dendrites / Axon /
Synapse"). Only that close-up is the target now; not the phone screens'
ringed orbs and threads.

> continue also animate the progressive openings and remove circuits entirely

The Circuit theme is gone (d4cff03). The animated openings are step 4 (F, G).

> also make the neuron hierarchy: cells the main folder - subfolders are cell parts - smaller parts are are smaller folders - notes are the smallest things in cells etc.also remove all circuits
> u can start building the cells from scratch using my image as arefrence
> also make links seamless parts of the cells that come out of it rather than separate parts.
> i didn't say around it i meant inside it and they only load when u open the cell folder etc

> the 3d space parts look separated and the glow is separate / also bare in mind that curcuits need an overhaul + neurons don't look even 1% close to what i showed u in images nor the hierarchy

The Space part is done (M1).

### The reference image

The owner's Neurons reference can't be kept in either repo, since both are
public. It shows:
- a big purple-magenta soma with a bright white-violet nucleus;
- golden-amber branching dendrites, thick at the base and tapering;
- one thick, beaded amber axon (about a fifth of the soma's diameter at its
  base, tapering) that leaves the soma and ends in a synapse on a cyan cell;
- phone screenshots of glowing spheres with rings, joined by fine glowing
  lines, on deep blue.

If the owner attaches it again, look at it before judging the screenshots.

The circled close-up (8 Oct, 6 PM), the only target now:
- the soma a glass sphere; inside it a deep-violet nucleus with a bright
  violet-white star at its middle, radial spokes and violet sparkles;
- golden-orange filament light hugging the nucleus, unevenly bright, with
  golden sparkles; then the clear glass envelope, its edge white-blue;
- glass dendrites with golden light inside near their bases;
- the axon a beaded glass tube with golden-white light inside, ending in a
  golden bouton against the next cell's blue glass bulb, golden sparks
  round the synapse;
- behind: dark navy, far blurred blue neuron networks, gold and blue bokeh.

### The hierarchy

- A cell is a main folder. A part is a folder inside it, and smaller parts
  are smaller folders. Notes are the smallest things: a page is a vesicle,
  an idea a granule. Free notes are receptors (gold) and drifters (pale ice).
- What a container holds is drawn inside it, and only once it is opened. The
  planner emits children only for opened containers; `input.open` lists them.
- Links are the cells' axons. Each grows out from under its sender's
  membrane, swells into a hillock, tapers, and ends in one synapse on its
  target. Its width follows the sender's size.

### The look (after the circled close-up, 8 Oct, 6 PM)

What the cells are now, and where (each shader's doc says the same):
- Soma (NeuronShaders.soma): inside 0.66 of the radius the nucleus, deep
  violet (NeuronPalette.interior (0.2,0.07,0.46)) brightening to violet at
  its heart (.heart (0.52,0.24,0.98)), touched by the dye (tint A, 16%);
  radial spokes and twinkling violet sparkles in it; a violet-white star at
  its middle (rpNucleus its size); a crisp glassy rim round it. Outside it,
  golden filament light hugging the nucleus, unevenly bright, with golden
  sparkles (tint C, NeuronLook.sparkle (1,0.88,0.6)); then the clear glass,
  its edge white-blue, and a wet highlight.
- Dendrites (NeuronShaders.arbor): glass, a white-blue edge, golden light
  inside near the soma (tint A, the golden (1,0.74,0.36)·0.88 + dye·0.12)
  cooling to blue-violet further out, faint spiralling strands, golden
  sparkles in arbor space; hidden over the nucleus so the middle stays
  clear.
- Halo (NeuronShaders.halo): one faint, gold-leaning glow ((1,0.74,0.36)·0.7
  + NeuronPalette.glow·0.3), brightest at the membrane, reaching only a
  little way in, fading softly out with no seam.
- Axon (NeuronShaders.axon): a glass tube, white-blue at its edges,
  golden-white light down its middle (NeuronLook.fibre (1,0.8,0.45), tract
  (1,0.72,0.38)), brighter at each node between the myelin's beads, golden
  sparks in it; a golden bouton with golden-white vesicles, a cyan cleft and
  transmitter, golden sparks spraying round the synapse. Impulses amber in
  a warm orange halo (NeuronPalette.impulseHalo (1,0.58,0.22)).
- Background (NeuronTissue): deep navy glows; 28 far neurons blurred out of
  focus in blue, cyan and violet (NeuronBokeh.farCells, NeuronArt.farNeuron:
  six tapering, forking branches, CoreImage-blurred); gold and blue bokeh
  (NeuronBokeh.tones). The orbs, threads and motes are gone.

### Decided design: implement this

Paths: N = ios/RedPen/Features/Notes, T = ios/RedPen/Tests. Line numbers are
approximate.

**A. N/GraphNeuronLook.swift** (finish the rewrite; read the file first)
- Half widths as statics, since init can't read instance properties:
  `static let nearHalf: Float = 0.1`, `static let farHalf: Float = 0.16`,
  `var linkHalfWidth: Float { Self.nearHalf }`,
  `var farHalfWidth: Float { Self.farHalf }`. init passes them as `half:`.
- `let linkTrim: Float = 0.9`, so each axon starts at 0.72 of the cell's size,
  under the membrane.
- arbor = `GraphLinkArbor(membrane: 1.25, share: 0.3)` when
  `support.has("axon")`, and `var farArbor: GraphLinkArbor? { arbor }`.
- Both axon materials are a single fibre (rpBundle 0): change
  `axonMaterial(bundle:…)` to
  `axonMaterial(base: SIMD3<Float>, bold:, lively:, budget:, support:, half:)`.
- Colours:
  - fibre (1.0, 0.62, 0.24) and tract (1.0, 0.55, 0.2), for amber axons as in
    the reference;
  - dendrite (arbor) tint = membrane·0.45 + (1, 0.8, 0.5)·0.55, golden.
- Add `private(set) var openings: [NeuronOpening] = []`,
  `private var holding: Set<Int> = []` and `private func learn(_ plan: ThemePlan)`.
  learn computes slotOf and holding (the indices that are some body's parent)
  when `slotsFor != plan.bodies.count`. slot() and makeBody call it.
- Add `private static var wasOpen: Set<UUID> = []` (removeAll when it passes
  4096). It remembers which containers were open in the last build.
- slot(): a region's slot as now, else
  `body.role == NeuronRole.drifter.rawValue ? 6 : 5`.
- membrane(): just the dye.
- shape(): only receptor and drifter change with state (pacemaker → .bipolar,
  migrating → .receptor, engulfing → .drifter). Every other kind keeps its own.
- makeBody:
  - role defaults to .granule; `idea = kind == .part || kind == .granule`;
    `inner = body.parent >= 0`; `open = kind.holds && holding.contains(index)`.
  - Containers get their own soma: `ownSoma(id:slot:kind:state:idea:open:)`
    makes a per-node copy of the sphere with a makeSoma material.
    - Let `was = wasOpen.contains(id)`, then update wasOpen.
    - If `lively && was != open && support.has("soma")`, set rpOpen to
      `was ? 1 : 0` and append `NeuronOpening(from: was ? 1 : 0, to: open ? 1 : 0)`.
      Otherwise set rpOpen to its target at once.
  - Other kinds use the shared somaGeometry.
  - Make an arbor node only `if kind.branches`.
  - Halo: `standing = (budget.haze && !inner) || state != .resting`. The glow
    is unchanged.
  - `if lively { Self.move(state, inner: inner, soma:, arbor:, size:, random:) }`.
  - `thinnable = body.kind == .note && state == .resting`.
- move():
  - Take up from `arbor?.simdOrientation ?? soma.simdOrientation`.
  - Inner bodies never translate: migrating becomes a gentle pulse to s·1.04
    (rise 1.4 s, fall 2.2 s).
  - Engulfing with no arbor scales the soma 0.9↔1.04.
  - The pacemaker and releasing arbor loops run only when there is an arbor.
- arborTurn: receptor and bipolar point along the axis; others turn at random.
- makeSoma also sets rpOpen 0 and rpFill to kind.fill. makeArbor's key is
  `"m\(slot)-\(idea ? 1 : 0)"`.
- NeuronArbor.branches. Each branch starts at 0.9 of the radius, and the tips
  stay within reach.
  - cell: 8 dendrites (9 if rich) on Fibonacci directions with 0.3 jitter;
    length 0.48+0.07·unit, thick 0.2, 2 side branches (+1 if rich).
  - receptor: a leading process (0,1,0), length 0.42, thick 0.2, with a fan of
    4 twigs 0.12 long from its tip (r0 0.06, r1 0.03); and a back process
    (0,-1,0), 0.3 long, thick 0.14.
  - drifter: 12 Fibonacci processes, length 0.2+0.05·unit, thick 0.09.
  - bipolar: (0,1,0.1), 0.25 long, thick 0.2; (0,-1,-0.1), 0.22 long, thick
    0.18; and two short ones, 0.12 long, thick 0.12.
  - part, vesicle, granule: none.
  - Update the doc comments.
- `nonisolated struct NeuronOpening { let material: SCNMaterial; let from: Float; let to: Float }`.
- NeuronImpulses:
  - Add openings, `openedAt: Float = -1` and `settled` (true when there are no
    openings). The init becomes `init(glows:swaying:openings:rate:bursts:)`,
    and ticker() passes `openings: openings`.
  - In tick, after rpSway and BEFORE the guard
    `last >= 0, time > last, time - last < 1`, call ease(time).
  - ease starts at the first time it sees (and restarts if time < openedAt).
    It sets t = clamp((time − openedAt)/0.9, 0, 1) and k = smoothstep(t), then
    rpOpen = from + (to − from)·k on each opening. It is settled once t ≥ 1.

**B. Soma shader** (N/GraphNeuronShaders.swift, about 48–136). Add `float rpOpen;`
and `float rpFill;` to the soma's surface modifier only, then change four lines to:
```
float3 rp_nc = rp_c + (rp_ax * 0.18 + rp_ay * 0.07) * (1.0 - rpOpen);
float rp_nr = max(rp_R * rpNucleus * (1.0 - 0.45 * rpOpen), 0.0001);
rp_dot = rp_dot * step(0.45, rp_gh) * rpDetail * (1.0 - rpOpen);
rp_col = rp_col + rp_inner * ((0.07 + 0.3 * rp_deep) * rpFill * (1.0 - 0.65 * rpOpen));
```
Keep the strings NeuronLookTests N5 looks for, and document rpOpen and rpFill.

**C. Axon shader** (about 349–558). Replace the decode with:
```
float rp_code = floor(rp_uv.x / 64.0);
float rp_dE = rp_uv.x - rp_code * 64.0 - 1.0;
float rp_wk = floor(rp_code / 32.0);
float rp_seed = rp_code - 32.0 * rp_wk;
float rp_hw = rpHalf * 0.12 * exp(rp_wk * 0.300105);
```
The shader already has `uint rp_h` (a hash), which is why the half width is
`rp_hw`.
- Use rp_hw instead of rpHalf in rp_fw, rp_We, both uses in rp_W, and rp_lane.
- Hillock: `float rp_hill = 1.0 + 1.5 * exp(-rp_along / (3.0 * rp_hw));`.
- Fade: `rp_col = rp_col * smoothstep(0.0, 2.0 * rp_hw, rp_along);`.
- Doc comment: u = (width step * 32 + seed) * 64 + 1 + the distance from the
  END, and a single fibre.

**D. Ribbon writer** (N/GraphRibbons.swift)
- `static let themeSeeds: Int = 32`, and themeSeed is mod 32: 8 width steps
  times 32 seeds, so the code stays under 256.
- Add `static func widthStep(radius r: Float) -> Int`:
  w = clamp(r/0.3, 0.12, 1), then k = round(log(w/0.12)/0.300105), clamped to 0...7.
- Add `static func stepWidth(_ k: Int) -> Float`, which is 0.12·exp(k·0.300105).
- In fill():
  - `let step = seeded ? Self.widthStep(radius: radius[link.a]) : 0`
  - `code = seeded ? step * Self.themeSeeds + Self.themeSeed(link.seed) : styled`
  - `let h: Float = seeded ? halfWidth * Self.stepWidth(step) : halfWidth`
  - `var width: Float = h`, and `arbor.halfWidth(dEnd: along, r: membrane, h: h)`
- The width follows only the sender's radius. Don't plumb ThemeLink.width in.

**E. N/GraphThemeScene.swift**
- Add `var linkTrim: Float { get }` to GraphThemeLook, defaulting to
  GraphShape.linkTrim. With the universe looks (about 231–238), set
  `universe.trims = [Float](repeating: look.linkTrim, count: GraphNodeStyle.allCases.count)`.
- Check that the edges loop (about 199–209) uses the plan's links.
- busiestRelay (about 288–301) picks the depth-0 cell with the most links.
- Fix the comments at about 16 and 34: radius times the look's linkTrim.
- zNear (0.05 now, about 218) becomes adaptive,
  clamp(distance·0.05, 1e-5, 0.05), so flying into a tiny inner note doesn't
  clip it.

**F. N/Graph3DView.swift.** Relevant places: rebuildTheme about 890–917;
universeInput about 931–946 (it sets no anatomy and no open); `.flyIn(id)` at
about 332 and 492, handled about 2139; fly(to:animated:) about 1858;
recentre() about 1734; `case .open(let id)` about 448.
- Fill the input's anatomy.
- Keep an open set. Flying into a container sets it to that container and its
  ancestors; recentring clears it. Rebuild the theme when it changes.

**G. GraphSim: animate the openings and closings**
- Fresh children start at their parent's position and grow out, staggered by
  min(0.05 + order·0.035, 0.7) seconds.
- When a cell closes, bodies still in the store but gone from the plan fold
  back into their parent instead of playing the death animation. Read
  GraphDeath first.

### Code facts

- NeuronRole (N/GraphNeurons.swift, about 40–70): cell 0 (rank 7), part 1 (6),
  home 2 (7), vesicle 3 (5), granule 4 (3), drifter 5 (1), receptor 6 (6).
  - isContainer: cell, part, home. isFree: drifter, receptor.
- The planner:
  - emitContainer's role is `!hasFolders ? .home : (depth == 0 ? .cell : .part)`,
    and its region is the top cell's index.
  - Children are emitted only when `opened[c]`.
    `shown[c] = p < 0 || (shown[p] && opened[p])`;
    `opened[c] = shown[c] && (!hasFolders || wanted.contains(id))`, with
    `wanted = Set(input.open)`.
  - Links: one per pair of shown bodies, kind 5 within a region and 6
    between; `a` is the sender.
- GraphNeurons constants:
  - inner 0.8, nucleus 0.22, room 0.05, wobble 0.015, fill 0.22, cellDrift
    0.012, reach 1.9, sheetGap 2.8.
  - cellSphere = clamp(0.34+0.035·log2(1+count), 0.34, 0.6);
    partShare = clamp(0.22+0.06·log2(1+count), 0.22, 0.45).
  - Note share: a page 0.07+0.003·level, an idea 0.05+0.002·level.
  - Free spheres: receptor 0.16, drifter 0.12 (+0.03 for a page).
  - Sheet pitch (2 + sheetGap·spacing)R, 4.8R at spacing 1.
  - Arbor tips stay within reach (1.9 radii) for cells and receptors, and
    about 1.15 for drifters and bipolar cells. LinkLengthTests needs
    0.94·(2 + 0.8·sheetGap) ≥ 2·reach + 0.11.
- ThemeBody: id, kind, role, parent, sphere, depth, region, count, links,
  words, rank, seed, orbit, home, axis, title, label.
  ThemeLink: a, b, kind, centre, tag, width.
  ThemePlan: bodies, links, envelope, systems, regions, summary.
- NeuronState: resting 0, firing 1, releasing 2, pacemaker 3, migrating 4,
  engulfing 5.
  - Containers always rest.
  - A note takes its folder's choice, then the main choice, then its natural
    state (receptor → migrating, drifter → engulfing).
- NeuronPalette:
  - dyes green, cyan, pink, amber, violet; receptor (1,0.84,0.48); drifter
    (0.62,0.8,0.98);
  - interior (0.2,0.07,0.46), heart (0.52,0.24,0.98), nucleus (0.82,0.36,1);
  - impulse (1,0.72,0.30), impulseHalo (1,0.58,0.22).
- Ribbon writer:
  - fill() is about 291–356. `u0 = Float(code*64+1)`; with an arbor,
    `width = arbor.halfWidth(dEnd: along, r: membrane, h: halfWidth)`.
  - path() is about 378–403. trimA = min(radius[a]·trim, length·0.45); with
    an arbor, trimB = min(endTrim(membrane: radius[b]·arbor.membrane), length·0.45).
  - Only GraphThemeScene writes seeded links, and the theme scene now serves
    only Neurons, so the seeded encoding is free to change.
  - GraphDeathScene (about 148) makes a writer with no trims.
- GraphMotion:
  - GraphUniverseLooks (about 100–130) has `trims: [Float] = []`, halfWidth,
    farHalfWidth, seeded, arbor, farArbor and ticker.
  - The writers are set up at about 575–595 with `trims: universeLooks?.trims ?? []`.
- GraphLinkArbor (N/GraphSynapse.swift, about 40–100): membrane 1.25, share 0.3.
  halfWidth(dEnd:r:h:) ramps from h to wide; also endTrim.
- GraphLook: linkHalfWidth 0.18, linkTrim 1.35.
- Node style codes: blackHole 0, rocky 1 (theme bodies), gasGiant 2, comet 3,
  pulsar 4, sun 5.
- Shader arguments:
  - soma: rpClock, rpMotion, rpProbe, rpDetail, rpNucleus, rpState, rpTintA/B/C.
  - axon: rpClock, rpMotion, rpProbe, rpDetail, rpRate, rpBurst, rpBundle,
    rpHalf, rpTintA/B/C.
- Tests that must keep passing:
  - ShaderSourceTests:
    - brackets balance;
    - rp_ names are declared before use and never twice in a scope;
    - every argument used is declared, and every declared one is used;
    - no GLSL or HLSL spellings, and no vector made from a bare number;
    - the surface ends with `_surface.diffuse` using rpProbe;
    - a material's geometry and surface modifiers never declare the same
      argument.
  - NeuronLookTests N5:
    - soma and halo contain "float rpState;", and the halo "rpState > 0.5" …
      "rpState > 4.5";
    - the soma contains "float3(0.2, 0.07, 0.46)" and "float3(0.52, 0.24, 0.98)";
    - soma and halo contain "rp_t / 1.5";
    - plus the palette tests.
  - NeuronHierarchyTests T10 call the NeuronImpulse functions with raw seeds,
    so the seed change doesn't touch them.
  - No test pins themeSeeds, rpHalf, the hillock or the 0.04 fade.

## 5. After M3

The #n numbers are task numbers carried over from earlier sessions. "Finding
n" is from Chat-me's docs/architecture/audit/stethoscore-unverified-findings.md.

### #33: the neumorphic app (another session's)

> also make the app be neumorphic in every way

> anotger session is already making the neumorphic part

Another session is doing this (the owner, 8 Oct). Don't start it here; what
follows is the brief as it stood.

- Re-skin the shared surfaces and controls as soft extruded and inset
  shapes, in light and dark: backgrounds, cards, buttons, toggles, segmented
  controls, fields, lists, the dock, sheets and progress.
- Keep text contrast. Keep the 3D map's translucent glass tiles (the owner
  asked for glass instead of green).
- Do #17 (V4: every other screen on the Ward language, meaning settings,
  sheets, paywall, onboarding, the Ideas 2D board, empty and error states,
  iPad layouts) in the same pass, so each screen is restyled once.
- Work on a design/ branch. Send screenshots of every changed screen, and
  merge into personal only when CI is green.

### Other open work

- #4, Tasks 5 to 5d and the §3c migration (Chat-me plan.md): done except
  Task 5 steps 4 and 5, which need a Jev key and Pro money. The 5b pilot
  runs on qbank/run.
- #7, sweep all four repos and every branch for missed work: the extra
  repos are done, and their ports went to design/port-transcription,
  design/port-content-quality, design/port-ocr-sources and
  design/port-asr-bench. Still to check: red-pen-ios's branches, Chat-me and
  the gaps.
- #8, the owner's design targets (docs/design/targets-2026-10-01.md): V1 to
  V3 and V6 are done. V4 is #17 (above), V5 is #18.
- #18, V5, the 3D map from the owner's boards and Chat-me plan §3d: M1 to M3
  are its current part. After M3, take Space toward the photoreal level of
  the owner's first board.
- #21, VT2, the verification layer end to end with real models: blocked.
  GitHub Models was retired on 30 Jul 2026, so it needs AI_API_KEY and the
  owner's word to deploy (the live Worker), or a free provider key
  (BENCH_API_KEY, BENCH_BASE_URL, BENCH_VOTERS). The harness
  (tools/verification-bench/layer.mjs) and verification-bench.yml are ready.
- #23, RR, the clean-up of the four repositories:

  > review and merge the gaps and wip branches and merge cleanups

  The owner keeps Chat-me 28bdcf3 and transcribe 7e2ae3a. design/cleanup-2
  is merged (e094da0). Left: review and merge the gaps/* and wip/* lanes.
  perf-core-backup and neuron-circuit-redesign are recorded (5360fb1,
  ac66667); a11y, l10n and audio are on design/lanes-ui; growth-p0-1 and
  growth-p0-2a are on design/lanes-growth. wip/3d-neurons-m3 is M3's own
  branch, not one of these lanes.
- #26, VT3, the verification layer to 99.999% on what it commits to:

  > i didn't say 99.999% just by them agreeing i meant they need to be PROVEN 99.999% right

  > force the 99.999% dependency even if it takes a lot of time to make

  - Verified needs three model families solving blind, all on the key, no
    dissent, no voter flag, no sensor hit, and evidence for oath items.
    Flagged needs a severe sensor plus a low p, or three blind families on
    one other answer with none on the key. Everything else is "Check this".
  - server/proof.js proves claims against the evidence (SP1 to SP3 are
    done: a mutation bench of 320k+ cases with no false proof).
  - Measure on the live Worker and report lower bounds honestly: proving
    99.999% takes about 300,000 verdicts with no error.
- Still standing from earlier:

  > make the translucent glass look instead of green

  > cursor redesign doesn't look good make it urself from those images plus the hierarchy changes i gave u in plan

  The 3D map was rebuilt from the owner's boards and Chat-me plan §3d, with
  Cursor's 3D dropped (#18). Check new 3D work against both asks.

### The owner's answers of 2 Oct

> 1- don't want 2- the cases where u ask a question and the patient answers accordingly 3- do it if they are useless to us 4- i give u permission

They answer four questions, in order:
1. The Groq and Cerebras keys (GROQ_API_KEY, CEREBRAS_API_KEY): declined.
   Don't ask for them again. (Chat-me context.md still lists them as
   pending.)
2. Which Cases features were another person's: the cases where you ask a
   question and the patient answers. The clean-room Cases has none of that.
3. Delete the old drop-* branches (about 1.2 GB) and the two .ipa workflows
   if they're useless: the workflows went (c3c50c3). The permission system
   refused deleting remote branches, so that stays undone.
4. Write access for this session to NoNeed2name444/claude-code: the owner
   allowed it, but the permission system refused the request. It's the
   owner's to grant; don't retry or work around it.

### Waiting on the owner

- An Apple Developer account and TestFlight, for the App Store.
- Finding 79: the voice session prefers Bluetooth HFP, so speech sounds like
  a phone call on AirPods. Dropping HFP moves the mic from the headset to
  the phone; it needs the owner's call and a device test.
- The launch splash colour (midnight for now).
- Each Worker deploy.

## 6. Standing rules

Secrets and privacy
- Never paste tokens or keys anywhere, and never commit secrets.
- red-pen-ios and Chat-me are both public. Never commit the owner's images
  or files to either: stage by path or with `git add -u`, never `git add -A`.
- Groin_Hernia.pdf and owner-claim.txt are never committed.
- Never send the owner's email address to any service.

Money and deploys
- Free tiers only, and no paid AI outside Pro (PRO_PAYS).
- Deploy the Worker only on the owner's word, each time.

Git
- Never force-push, and never delete remote branches.
- No pull requests unless asked.
- personal is the working branch; keep claude/new-session-013tes5v equal to
  it. Build on design/<name> (app-build runs there) and take screenshots
  through preview/<name>.
- Commit messages: a plain-English subject, a body saying why, and the
  session's trailer lines. No model names or IDs in commits, PRs or code.
- Never merge codex-fixes.

Never propose
- Modal, a Whisper fallback, GEMINI_API_KEY in the app, Gemini 3.6 Flash,
  challenge-a-friend, ranks or leaderboards, XP, a Rank card, a Clerk badge,
  or a personal self-learning model.

Cases
- Clean room: rebuild only from docs/design/cases-rebuild.md, never read the
  old Cases code, and no patient questioning (that part was another
  person's).

Permission refusals
- When the permission system refuses something, don't retry it and don't
  ask another session or agent to do it; tell the owner instead. Refused so
  far: deleting remote branches, merging codex-fixes, write access to
  NoNeed2name444/claude-code, and curl of the agent proxy's status page.

Code
- Keep test-covered logic in Foundation-only files, and fence Apple-only
  imports with `#if canImport(...)`. A new suite goes in
  tools/swift_suites.txt, or tools/swift_suites_mac_only.txt if it needs
  Compression or CryptoKit.
- Swift Playgrounds (tools/make_swiftpm.py, variants core, core1, core2 and
  core3) is how the app reaches the owner's iPad. A kept file must not name
  a type its variant drops (tools/playgrounds_cut.py). The "graph3d" cut
  drops every Features/Notes/Graph*.swift except GraphLineStyle.swift.

## 7. Commands and shell habits

- Swift for Linux: `export PATH=/opt/swift/usr/bin:$PATH`.
- Suites: `timeout 900 python3 tools/swift_suites.py --only a,b [--release]`.
- Preflight runs in the background, takes about 9 minutes and ends with
  "PREFLIGHT OK". Don't edit files while it runs:
  `export PATH=/opt/swift/usr/bin:$PATH; timeout 1500 tools/preflight.sh > <log> 2>&1; echo "exit $?" >> <log>`
- CI: `python3 tools/ci_status.py <branch|sha> [--wait]` (exit 0 green, 1
  failed, 2 running). Read a few lines, never whole logs.
- What a push runs: app-build.yml on personal and design/** (or by
  dispatch); design-preview.yml on preview/**, committing shots to
  shots/<name>; swift-tests on every branch but claude/** (path-filtered);
  server-tests on server/** changes (not claude/**); swiftpm-check on
  personal and design/lanes.
- Push with retries, and if it's rejected as behind,
  `git pull --rebase origin <branch>` and push again:

```
for d in 2 4 8 16 0; do git push origin HEAD:refs/heads/<branch> 2>&1 | tail -n 1; rc=${PIPESTATUS[0]}; [ $rc -eq 0 ] && { echo pushed; break; }; [ $d -eq 0 ] && { echo "push failed"; break; }; sleep $d; done
```

- gh: GraphQL is blocked here (403), so `gh repo view --json` and the like
  fail. Use REST: `gh api repos/<owner>/<repo>/...`.
- Chat-me (/home/user/chat-me, branch personal): push with git; the gh
  contents API refuses writes (403).
- A stop hook won't let a turn end with uncommitted or untracked files or
  unpushed commits.
- The shell's working directory can change between calls: start every
  command with `cd /absolute/path && ...`.
- Never use a bare `git stash`; the stash is shared with other sessions. Make
  a WIP commit instead.
- Don't grep or find across /root/.claude or .claude/worktrees; they're
  huge. Search a known path.
- `pkill -f <pattern>` can match its own shell; kill by process ID.
- No foreground sleep: run long jobs in the background and get notified.
- Keep edits small: a short python replace that asserts the old text occurs
  once, and write big files in appended chunks, to stay under the output
  limit.
