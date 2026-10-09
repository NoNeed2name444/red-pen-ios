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

Last updated: 2026-10-09, 4:40 AM Cairo.

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
| wip/3d-neurons-m3 | "Plan: M3 joins personal" | M3, done: the cells, parts and notes, one membrane per cell, links as dendrites from both cells (round D); #20 found no freeze of the app's own, only XCTest unable to end it while the simulator's first boot settled, and the fix (0435184: boot during the build, wait for the Mac's load) was confirmed by run 37862852271, green; this commit is what personal took (section 3, step 7) |
| design/3d-overhaul | the same as wip | M1 (c122abb, Space), M2 (no Circuit, d4cff03) and the M3 code; the App build here is the compile check for the Mac-only files (GraphNeuronLook, GraphRibbons, GraphMotion, GraphThemeScene, GraphDeathScene, GraphHangReporter) |
| preview/3d-overhaul | 0435184 (run 37862852271, green: the confirming run of the freeze fix, step 6d); the commits after it change only this file | a push here makes screenshots (don't push here while a run is in progress: a push cancels it) |
| shots/3d-overhaul | 8dc9d3f (run 37862852271) | where design-preview.yml commits them |
| personal, claude/new-session-013tes5v | M3 (joined on 9 Oct at about 3:40 AM; before it, 3827785) and the port (section 3, step 9; joined at about 4:40 AM) | personal is the working branch; keep session branches equal to it |
| design/port-prework | the same as personal | the three fixes found only on design/prework-20261006 (step 9, done) |

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
  what i want from u. i only want what is marked in white", then "i mean
  black") and circled in black the big labelled neuron close-up on their
  board. The cells are redrawn after
  that close-up only (section 4, "The look"): no ringed orbs, no threads,
  no circuits. GraphNeuronLook only compiles on the Mac, so its App build
  on design/ is the check.
- The first close-up redraw (95c4b8d) was shot (preview run 37800861072,
  only=testNeurons). Next to the close-up it was off in four ways: the
  background a bright royal blue (the dome's 16 glows add 0.2 to 0.3 of
  blue to NeuronPalette.deep), the nucleus a ball with a dark gap before a
  teal rim, the dendrites short gold triangles (a linear taper and a gold
  base term drowning the glass edge), the axon a thin gold line. The cell
  body is redone (the mandala, swirling strokes, gold limb lobes, a thin
  white-blue rim: section 4, "The look"); then the dendrites and the
  background (step 6b, 24c0ebc).
- On a screenshot of 24c0ebc the owner marked (8 Oct, 7 PM; section 4,
  verbatim): the purple lights to be a nucleus (done), the links to be the
  cell's own dendrites prolonged, thick and flowing out of the body, with
  no oval ring (done: NeuronShaders.axon, NeuronLook.farHalf 0.38), and a
  cell's subfolders inside its nucleus when it opens, smaller (done:
  GraphNeurons.zones, openNucleus 0.6, partShare 0.1 to 0.22). Round B
  (98f6f18; App build 37815149897 green, preview run 37815161808) was
  shot and sent. On the iPad two tests failed before the map did
  anything: testNeuronsFlyIn ("Failed to terminate") and
  testNeuronsLegend ("Failed to launch"): the simulator, not the map.
  Watch for them in round C; the iPhone shots were all there.
- The owner then asked (8 Oct, 8:35 PM; section 4, verbatim) for a cell's
  dendrites and body to be one surface, not stitched pieces (#14), and for
  links to be dendrites, not axons, extended to join two cells so that
  their surfaces run on into each other (#15). Both are done (section 3,
  step 6c) and are round C.
- The owner's two red lines join Cardiology to Examples, but the sample
  notes had no link between those folders, so the map could not draw one.
  GraphPreview now links Groin hernia to Atrial fibrillation (a hand link;
  both test mirrors follow), so the closed map has a third process, from
  Examples into Cardiology (NeuronHierarchyTests T2).
- The wip App build (run 37781812785, 5909600) ran the whole UI suite on a
  simulator after its compile (design/ branches skip it), then hit its
  60-minute limit (61 minutes, cancelled during clean-up). app-build.yml
  now allows 90, so personal's full run can finish. Two map tests failed:
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
- Round C (3a21e75): App build 37829324782 and preview run 37829333699,
  both green; the shots were sent (8 Oct, about 10:40 PM). Two things
  still showed: the soma's crisp rim across each tube's mouth (#17, done
  in 91aedd2) and, once a cell is opened, links from its parts and notes
  crossing its membrane to reach other cells (graph-14, 15, 20: #18, done
  in 86791b6). Both are round D.
- Round D (86791b6) compiled on the Mac (App build 37838831104, at
  c8ec409) and was shot (preview run 37838122205, only=testNeurons):
  graph-11, 20, 21 and 22 show #17 and #18 right (the rims open at the
  tube mouths; links from an opened cell leave from its membrane). The run
  went red on a freeze, not on the map's look:
  - iPad testNeuronsLegend: "Failed to get matching snapshots: Timed out
    while evaluating UI query" after 404 s; then testNeuronsLookMenu:
    "Failed to terminate com.cramdown.app";
  - iPhone testNeuronsFlyIn passed, but graph-14 and graph-15 are the same
    picture: the screen stopped changing.
  It comes and goes, and it is older than #17 and #18: round B's iPad
  failed the same way ("Failed to terminate", then "Failed to launch"),
  and round C's iPad testNeuronsAtRest took 285.6 s. Ruled out by reading
  the code: the flown-cell ping-pong, GraphSim's locks (main never holds
  GraphSim.lock while it touches SceneKit), the render thread's label work,
  the frame fence, GraphPerfRenderer and NebulaBaker, the GraphQuality and
  GraphLineStyleLive locks, the shaders' loops (all bounded: 3, 3 or 1,
  and 5), and the style and neuron probes (their snapshots run in the
  detached rebuild tasks, never on main). Left: the app stuck in the
  kernel or the GPU ("Failed to terminate" means even SIGKILL did not end
  it), the simulator's SpringBoard or backboardd hung, or a stalled VM GPU.
  So the next run samples the app's threads while it freezes (step 6d,
  #20).
- That run (37846299540, 2428ffd: AtRest, FlyIn and Legend three times
  each) was red only because of the sampler. `sample` holds the app still
  while it reads it, and the samples crawled (89 s on the iPad and about
  4 minutes on the iPhone, for 2 s asked), so twice the test's SIGTERM
  came while the app was held and the test gave up ("Failed to
  terminate": the iPad's Legend #1 and the iPhone's Legend #3). No freeze
  of the app's own was caught, and XCTest attached no diagnostics. The
  slow samples and AtRest's 68.5 s (against 32.9) point at a Mac short of
  memory. So the next run touches nothing: the app reports where its
  main and render threads are stuck (GraphHangReporter, in its own log),
  and hang_watch.sh only notes thread states and the Mac's memory (step
  6d).
- The next run (37858247053, 5f8eb9f) found no freeze at all. Its one
  failure, the iPad's testNeuronsAtRest #2, was XCTest failing to end a
  healthy app: the app's own report had it drawing about 50 frames a
  second, main's longest step 3 to 4 ms, while XCTest's "Terminate" waited
  68 s. The Mac was the problem. The simulator first boots right after the
  build, and its first boot starts hundreds of its own services at once
  (widgets, News, Health, SpringBoard and more, 200 to 440 MB each) on a
  3-core, 7 GB runner: the load reached 773 on the iPad and 847 on the
  iPhone, free memory sat near 60 MB, swap reached 957 MB, and the app's
  launch added 633 MB of wired GPU memory on top. The tests sped up as it
  settled (the iPhone's AtRest 115.2, 90.7, then 33.0 s). So the simulator
  now boots during the build, and the tests wait (up to 10 minutes) for the
  Mac's load to come down (step 6d).
- The confirming run (37862852271, 0435184; shots 8dc9d3f) was green:
  AtRest, FlyIn and Legend three times each on the iPad and the iPhone, 18
  passes, and every app ended when asked. Booting beside the build slowed
  the build (8.5 to 14 minutes, from about 6), and after it the Mac took 5
  to 10 minutes to bring its 1-minute load under 40. The first AtRest was
  still slow (56.8 s on the iPad and 63.2 s on the iPhone, against 46.2
  and 26.9 s by the third) but well inside its limits. So M3 went to
  personal (step 7).

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
6. [x] Fetch shots/3d-overhaul and send the owner the Neurons shots (rounds
   B, C and D were sent; round D is the newest look): at rest,
   a cell opened with its parts and notes inside, and axons growing out of
   the cells. The preview flies into a cell (shots 14, 15) and then a part
   inside it (20 to 22). For a quick look first, dispatch only those:
   `gh workflow run design-preview.yml --ref preview/3d-overhaul -f only=testNeurons`
   (it cancels a running push-started run on the same branch).
7. [x] When CI is green, merge design/3d-overhaul into personal (no
   force-push), and bring the session branches up to personal. Done on 9
   Oct at about 3:40 AM: personal and claude/new-session-013tes5v
   fast-forwarded from 3827785 to this commit.
   - [x] app-build.yml's limit raised from 60 to 90 minutes first: the
     full run (compile, UI suite, accessibility) took 61 on wip.
   - [x] Then personal's App build runs the whole UI suite for the first
     time since M3. Done: run 37866071705 on 67f4714, green (9 Oct, 4:30
     AM). testHoldForOptions passed (20.3 s) and the UI suite said TEST
     SUCCEEDED; the accessibility step failed as it did before M3 (see
     section 2), and it is continue-on-error. What follows is kept for
     the next time a test there cannot end the app.
     testHoldForOptions was the one to watch: fixed in
     8a18676 but not run on the Mac since (the previews ran only=testNeurons).
     Read it with `tools/ci_status.py personal --wait`. Its simulator still
     boots inside `xcodebuild test`, as the preview's did before step 6d's
     fix, so its first tests run while that first boot settles. Left as it
     is: the map's tests come after ArabicUITests, DesignTourUITests and
     ExamplesUITests (about 14 minutes), past the 5 to 10 the Mac took to
     settle, and the suite passed that way before (App builds 37730791613
     and 37725355312). If a test there cannot end the app, give
     app-build.yml the preview's early boot and settle wait
     (design-preview.yml, "Build for testing" and "Take the pictures").
6a. [x] Redraw the cells after the owner's reference: purple-magenta
   somas, golden-amber dendrites, ringed orbs joined by threads. Rejected
   by the owner (8 Oct, 6 PM): they want only the circled close-up.
6b. [x] Redraw the cell after the circled close-up (section 4, "The look"):
   glass soma, deep-violet nucleus with a bright star, golden filament
   light, glass dendrites with golden light, beaded glass axon with a
   golden bouton, far blurred blue neurons and gold and blue bokeh behind.
   - [x] First pass (95c4b8d): compiled, shot, compared (section 2).
   - [x] The cell body redone after the comparison.
   - [x] The dendrites: long, thick glass trunks flowing out of the soma
     (start inside it, a flared taper, up to GraphNeurons.reach), a bright
     white-blue edge the whole way, gold streaks inside near the soma.
     Tried on Linux first with a numpy port of the shaders (looks v1 to
     v10); v9 won: six even planar tubes, no forks (forks cut flat).
   - [x] The background: a dark teal-navy (the close-up's (6,20,30) to
     (41,68,89)): NeuronPalette.deep and NeuronTissue's glow hues.
   - [x] The nucleus instead of the purple lights (the owner: "remove the
     lighting of the purple center and make it an nucleus instead of
     lights"): a solid shaded ball, chromatin, envelope, nucleolus.
   - [x] The links as the cell's own dendrites prolonged (the owner's
     marked screenshot): a thick glass tube (farHalf 0.38, nearHalf 0.23)
     flowing out of the body in a trumpet three times its width, its
     outline hidden over the soma, gold only near the sender, faint beads.
     Tried first in the numpy port (scratch axon_v1.py, look a2).
   - [x] A cell's subfolders inside its nucleus, smaller: opening swells
     the nucleus from 0.435 R to 0.6 R (its chromatin thinned, nucleolus
     gone); the parts float inside it (within 0.54 R), the notes in the
     cytoplasm round it (0.64 R to 0.8 R); partShare 0.1 to 0.22.
   - [x] A link between the two big cells in the sample map, where the
     owner drew two lines: Groin hernia to Atrial fibrillation.
   - [x] App build on design/ (37815149897, green) and round B shots
     (only=testNeurons, run 37815161808), sent.
6c. [x] One surface per cell, and links as dendrites joining two cells (the
   owner, 8 Oct, 8:35 PM; section 4).
   - [x] #14, the soma and its dendrites as one closed mesh
     (GraphNeuronMembrane): the zero set of one distance field (the soma
     smoothly united, k = 0.3, with round cones along each dendrite),
     meshed by surface nets and pulled onto the surface, normals from the
     field's gradient, so the glass edge runs unbroken round the cell.
     NeuronShaders.membrane and membraneSway draw it; the suite
     "membrane" checks it closed, in one piece, on the surface, facing out.
   - [x] #15, a link as one straight dendrite from cell to cell
     (GraphLinkBridge, NeuronShaders.bridge): it flares into both cells
     the same way (the same smooth minimum, seen in the plane square to
     the view: tangent to each disc at the join, its own width past the
     flare), with no myelin, bouton, synapse or sender-only gold; as thick
     as its smaller cell allows (nearBridge 0.09, farBridge 0.12, times
     the width step); impulses run its whole length and light the second
     cell as before. Straight, because an arch would tilt the tube at the
     join. Falls back to the axon and arbor, then the plain link, if a
     shader fails on the device. The suite "bridge" checks the outline.
   - [x] Round C: the App build on design/ (37829324782) and the shots
     (preview run 37829333699, only=testNeurons), green and sent.
   - [x] #17, the soma's rim hidden across each tube's mouth: a cell that
     carries links gets its own copy of the membrane material with up to
     four mouths (rpMouth0 to 3: the direction in the cell's own frame and
     the half width h/r plus the blend), and the rim fades where a mouth
     meets it. GraphLinkMouths picks a cell's widest four; GraphSim calls
     the look's GraphLinkMouthKeeper (NeuronMouths) each frame, which
     writes only values that moved. The suite "bridge" checks the mouths
     (B12, B13). Compiled on the Mac: App build 37835162580.
   - [x] #18, a link that leaves an opened cell starts on the cell, so
     its tube joins the cell's membrane instead of crossing it to a part
     or note inside (GraphNeurons.processes: across cells each end is the
     cell holding it, or the free note itself; inside one cell the deepest
     shown bodies, as before). NeuronHierarchyTests T2 checks it: no
     process crosses a membrane, opened or not, and links inside an
     opened cell still join its notes with their own dyes.
   - [x] Round D (#17 and #18): App build 37838831104 (green) and preview
     run 37838122205 (only=testNeurons): graph-11, 20, 21, 22 show both
     right. The run was red on the freeze (section 2, step 6d).
   - [x] Send the owner round D's shots (graph-11, 20, 21, 22 and the
     OpenInTurn recording, under 30 MiB), saying plainly that the app
     sometimes freezes in the tests and that it is being chased (6d).
6d. [x] #20, the freeze: find and fix what now and then freezes the app in
   the map's UI tests (section 2, round D). It blocks the merge into
   personal (step 7).
   - [x] tools/hang_watch.sh, run by design-preview.yml for the iphone-graph
     and ipad parts, and design-preview.yml's new input `repeat` (each test
     up to that many times, stopping at its first failure). Its first form
     (2428ffd) sampled the app (`sample`, spindump) and so held it still
     (below). It now only looks: every 2 s each app thread's state and CPU
     time (threads.txt: U is stuck in the kernel, T held) and any process
     that samples or reports on others (others.txt); every 10 s the Mac's
     memory, swap, load, busiest processes and SimMetalHost's threads
     (host.txt); when each app process came and went (launches.txt); after
     the tests the simulator's log for the app (sim-log.txt), the Mac's GPU
     lines and any crash or hang reports. They go up as the artifacts
     hang-iphone-graph and hang-ipad (kept 7 days, never pushed to the
     public shots branch).
   - [x] One run of the three tests that froze, three times each (run
     37846299540, 2428ffd; shots 48787e9). Red only on the sampler: the
     iPad's testNeuronsLegend #1 (69 s) and the iPhone's #3 (98.9 s)
     "Failed to terminate", each while `sample` held the app (iPad pid
     27799: SIGTERM at 21:41:26.674, its sample ran 21:39:59 to about
     21:41:28; iPhone pid 28174: SIGTERM at 21:45:26.777, its sample ran
     21:41:36 to 21:45:27). The rest passed: on the iPad AtRest 68.5,
     32.9 and 53.3 s, FlyIn 34.0, 32.4 and 33.5 s.
   - [x] Read it. No freeze of the app's own was caught, and XCTest
     attached no diagnostics (shots-ipad holds only the pictures,
     logs/ipad.log and a recording). An app without a SIGTERM handler
     outlives SIGTERM only while it is held (T) or in an uninterruptible
     kernel wait (U), never in a deadlock of its own. Left to suspect:
     memory (a 7 GB, 3-core runner; the iPad at High quality, msaa 4, HDR,
     bloom, DOF, about 2064×2752; 576 shaders recompiled each launch on the
     iPad and 405 on the iPhone; SimMetalHost's command queues reached 60
     and 30 deep), the probes' offscreen SCNRenderers (NeuronProbe,
     GraphShaderProbe, GraphStyleProbe) and their `static let` runs
     (dispatch_once), SceneKit's lock held through shader compiles,
     NebulaBaker's waitUntilCompleted, and GraphFrameFence's per-frame
     marker buffer (makeCommandBuffer blocks with 64 in flight).
   - [x] GraphHangReporter (the design preview only, `-graphPreview`): the
     app watches its own main thread (through a run-loop observer, so the
     tests' wait for an idle app is untouched) and the map's render thread
     (each frame). When either has been still for 3 s it logs (category
     "hang") each one's state and stack, named, again every 15 s while it
     lasts (at most 12 times), with every other thread the 1st and 4th
     time; while all is well, a line every 30 s with frames drawn, main's
     longest step, memory and paging. Swift names come mangled: demangle
     them with `/opt/swift/usr/bin/swift-demangle`. Its first Mac build
     failed (App build 37856034906, 8ce4459): the iOS 26 SDK hands the
     run-loop observer's block plain CFOptionFlags, so it now takes either
     type.
   - [x] The same three tests three times each again (run 37858247053,
     5f8eb9f; shots f4023db):
     `gh workflow run design-preview.yml --ref preview/3d-overhaul -f only='testNeuronsAtRest|testNeuronsFlyIn|testNeuronsLegend' -f repeat=3`
     Then fetch the artifacts into a new empty directory:
     `gh api repos/noneed2name444/red-pen-ios/actions/runs/<run>/artifacts`
     for the ids, `gh api repos/noneed2name444/red-pen-ios/actions/artifacts/<id>/zip > hang.zip`.
     Red only on the iPad's testNeuronsAtRest #2 (73.7 s, "Failed to
     terminate", GraphPreviewUITests.swift:117). The rest passed: iPad
     AtRest 79.8; FlyIn 51.9, 38.2, 32.3; Legend 45.2, 19.7, 21.2. iPhone
     AtRest 115.2, 90.7, 33.0; FlyIn 46.2, 43.2, 13.8; Legend 31.5, 14.7,
     16.7.
   - [x] Read them: `grep 'com.cramdown.app:hang'` in sim-log.txt for the
     app's own reports (the "alive" lines and, in a freeze, the stuck
     threads' stacks); threads.txt for U or T rows; host.txt for swap and
     memory pressure at the time; others.txt for anything that sampled the
     app; launches.txt for which process ran how long. Found:
     - the app never froze: the iPad app XCTest could not end kept
       drawing (about 48 frames a second, main's longest step 3 to 4 ms)
       right up to its SIGTERM; the iPhone's only "hang" reports were two
       stalls of main at launch (3.4 s each, in the Swift runtime's type
       lookups under an accessibility query, while paging), over in
       seconds;
     - XCTest asked to end it at 23:27:27 (0.24 s into the test's tear
       down) and the request stalled; the app got SIGTERM only at
       23:28:39.85, after the test had given up (68.2 s);
     - the Mac: the simulator booted at 23:21:49, right after the build,
       and its first boot was still settling when the tests began (23:26:07):
       load 291 before the app, 773 on the iPad (23:28:53) and 847 on the
       iPhone (23:28:55), down to 183 by 23:35; free memory near 60 MB,
       5 to 8 GB squeezed into 2 to 2.6 GB of compressor, swap 700 to
       957 MB; the app's launch added 633 MB of wired memory (its GPU
       buffers at High quality). The busiest: the simulator's own services
       (FitnessIntelligenceSnapshotService, healthd, News widgets,
       IntentsExtension, chronod, WidgetRenderer, SpringBoard, each 200 to
       440 MB) and both diagnosticd at 20 to 40% CPU. XCTest's own screen
       recording (VTEncoderXPCService) was light, about 7%.
     - the watch itself added to it: `pgrep -f` and `ps -o command` read
       every process's memory, and it stalled through the whole wait
       (23:26:36 to 23:28:42 on the iPad), so threads.txt has nothing from
       then; elsewhere U shows only around launches (paging in), never T.
   - [x] The fix (no change to the app, so the pictures stay true):
     design-preview.yml boots the simulator in the background as the build
     starts, and before the tests waits, up to 10 minutes, for the Mac's
     1-minute load to drop under 40 (printing it each minute: "load ..."
     lines in the Take the pictures log); hang_watch.sh finds the app and
     the GPU host by name (`pgrep -x`, `ucomm`), never reading the other
     processes' memory.
   - [x] One confirming run of the same three tests three times each (run
     37862852271, 0435184; shots 8dc9d3f): green. iPad AtRest 56.8, 70.2,
     46.2; FlyIn 21.1, 21.3, 31.7; Legend 25.3, 14.9, 18.9. iPhone AtRest
     63.2, 60.9, 26.9; FlyIn 26.9, 17.6, 15.1; Legend 21.9, 14.0, 14.2. The
     "load" lines: the iPad's went from 135 to 39 in 4 min 43 s, the iPhone
     graph part's from 104 to 40 in 7 min 46 s, the iPhone tour part's from
     186 to 34 in 9 min 48 s (nearly the 10-minute cap), so 40 stays. If a
     test ever fails to end the app again, give the simulator's build of
     the map a lighter load (30 frames a second, 2× MSAA under
     `#if targetEnvironment(simulator)`).
8. [x] #33, the neumorphic app, is not this session's: another session is
   making it (the owner, 8 Oct, 4:16 PM: "anotger session is already making
   the neumorphic part"). Leave it alone here.
9. [x] Port the three real fixes the branch sweep (section 5, #7) found
   only on design/prework-20261006, on design/port-prework (from 67f4714):
   - [x] The question bank's check in batches of four (from 696192f02):
     pipeline.mjs sent eight candidates per /accuracy/check, which
     server/accuracy.js refuses past BATCH = 4 (400), so every pilot
     candidate came back "not checked". The bank test now holds it to
     BATCH, with nine candidates (4, 4, 1), and a failed middle batch
     leaves the rest checked.
   - [x] The voice cache (after a0b70fb00, done differently): a line kept
     from MeloTTS used to cost one of the day's lines each time it played,
     and past TTS_DAILY_LIMIT it was refused though it costs nothing. Now
     it gives that line back, and plays after the day's lines run out.
     Aura-2 still comes first (the prework played a kept MeloTTS line
     before trying Aura-2, so a line once read by MeloTTS could never move
     up to Aura-2). server/tests/tts.test.mjs: five of the new checks fail
     on the old code. Live only after a Worker deploy, which needs the
     owner's word.
   - [x] Commute mode's answers into history (from 7b32b0640): an MCQ
     answered by voice in commute mode moved the review schedule but never
     reached Store.recordAnswer, so streaks, weak spots and the stats
     missed it. CommuteSession keeps a weak reference to the store and
     records each answer as the board does.
   - [x] Preflight, push design/port-prework, CI green (the App build
     there only compiles), then fast-forward personal and
     claude/new-session-013tes5v to it once personal's own App build on
     67f4714 (step 7) is done. Done: preflight OK; on 22f16f3, App build
     37867652715 and Server tests 37867652555 green; personal and the
     session branch fast-forwarded to this commit on 9 Oct at about 4:40
     AM, after step 7's run. Not ported: INT-PREVIEW (the shots
     branches keep only the latest run, by design) and the rest of that
     branch (another agent's prework/medical-assistant scaffold, PARTIAL
     or BLOCKED by its own notes).

## 4. M3: the Neurons rebuild

### What the owner asked (verbatim, newest first)

> also the dendrites and the cell surface should be one entity not multiple stitched things
> don't use axons as connections use dendrites and extend them
> make the tube connected both ways so the 2 cell surfaces connected become continuous

(8 Oct, 8:35 PM.) Done in step 6c: GraphNeuronMembrane (#14) and
GraphLinkBridge (#15).

> these should be the connections and the encircled purple lights should turn to a nucleus instead of lights and the nucleus should have the subfolders when the folder opens. the oval encirclement should be removed and replaced by the prolonged dendrites of the cell folder.

With a screenshot of the app (24c0ebc's look) marked up: a thick tube
drawn flowing out of a cell as the connection, the purple lights circled,
an oval round a cell crossed out.

> i mean black
> axons and connections should be part of the gooey cell body just like the image. also subfolders should be smaller parts
> let's remove neurons too it's wasting lots pf resources
> don't remove the neurons yet tell i tell u
> remove the lighting of the purple center and make it an nucleus instead of lights.

Neurons stays until the owner says otherwise; one preview run per round.

> it's completely different from what i want from u. i only want what is marked in white

With a picture of their design board, the big labelled neuron close-up at
the top right circled in black (the owner: "i mean black"; "Neuron cell
body / Dendrites / Axon / Synapse"). Only that close-up is the target now; not the phone screens'
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
  are smaller folders. A cell's parts float inside its nucleus, which
  swells to hold them when the cell opens; its notes float in the
  cytoplasm round it (GraphNeurons.zones). Parts are small (partShare 0.1
  to 0.22 of what holds them), a note smaller than any part beside it.
  Notes are the smallest things: a page is a vesicle, an idea a granule.
  Free notes are receptors (gold) and drifters (pale ice).
- What a container holds is drawn inside it, and only once it is opened. The
  planner emits children only for opened containers; `input.open` lists them.
- Links are dendrites joining two cells (the owner, 8 Oct, 8:35 PM): one
  straight glass tube that flares out of one cell's body and into the
  other's the same way, so the two surfaces run on into each other. Its
  width follows the smaller cell. (Before that they were the sender's
  axon, ending in a synapse; that is now only the fallback.)

### The look (after the circled close-up, 8 Oct, 6 PM)

What the cells are now, and where (each shader's doc says the same):
- Soma (NeuronShaders.soma): a dark violet glass ball
  (NeuronPalette.interior (0.2,0.07,0.46) darkening toward the edge, .heart
  (0.52,0.24,0.98) at the middle, a touch of the dye, tint A); at its
  middle a solid nucleus (shaded from the upper left, no glow: mottled
  chromatin, a lavender envelope with pores, a nucleolus in tint B),
  0.435 R at rest, swelling to 0.6 R when the cell opens to hold its parts
  (chromatin thinned, nucleolus gone); short strokes swirling round it,
  violet near it and gold toward the edge; a few sparkles in depth. At the limb golden filament
  light in lobes that blaze in places, white-hot on their crests, with
  golden glints (tint C, NeuronLook.sparkle (1,0.88,0.6)); then a thin
  white-blue glass rim, a faint violet sheen inside it and a wet highlight.
- Dendrites (NeuronArbor, NeuronShaders.arbor): a cell's crown is six (seven
  on high) thick glass tubes in the plane facing the camera (arborTurn
  spins it about z, tips it up to 0.2 rad), each from 0.75 R inside the
  soma, 0.3 R thick, narrowing only to 0.7 of that, its base flared into a
  trumpet (+0.5·(1-t)^4; the trumpets together the glass body round the
  soma), up to 1.85 R (GraphNeurons.reach 1.9). Shading: an even white-blue
  edge the whole way, a faint violet body, gold streaks running along
  inside (filament noise stretched along the tube, drifting out on the
  clock), gold particles drifting out, tint A (the golden
  (1,0.74,0.36)·0.88 + dye·0.12) at the base, golden sparkles in arbor
  space; faded in over s 0 to 0.12 so the flared start ring (it reaches
  1.1 R) never shows as a flat white wedge past the soma's rim, and out
  over s 0.6 to 1 so a dendrite runs on into the dark; hidden over the
  soma's middle (smoothstep 0.8 to 0.97 R off the view ray).
- Halo (NeuronShaders.halo): one faint, gold-leaning glow ((1,0.74,0.36)·0.7
  + NeuronPalette.glow·0.3), brightest at the membrane, reaching only a
  little way in, fading softly out with no seam.
- Membrane (GraphNeuronMembrane, NeuronShaders.membrane, membraneSway): a
  cell's soma and dendrites are one closed glass mesh, so its white-blue
  edge runs unbroken from the body round every dendrite and back (the
  owner: "one entity not multiple stitched things"). The soma shader
  still draws the inside; the membrane carries the edge, the dendrites'
  gold and particles, and sways with the soma's wobble. Smaller cells and
  the plain fallback keep the sphere and tubes.
- Bridge (GraphLinkBridge, NeuronShaders.bridge): a link as one dendrite
  between two cells, flared into each body by the membrane's own blend
  (k = 0.3 R), worked out in the plane square to the view: tangent to the
  cell's disc at the join, its own width past the flare. Glass like the
  dendrites, a white-blue edge, gold filaments strongest near both cells,
  no myelin, bouton or synapse; impulses amber in a warm orange halo, run
  end to end. nearBridge 0.09, farBridge 0.12 (times the width step of
  the smaller cell). Straight: an arch would tilt it at the join.
- Axon (the fallback, when the bridge shader fails; NeuronShaders.axon): one of the sender's dendrites prolonged (the
  owner's marked screenshot): a thick glass tube (NeuronLook.farHalf 0.38,
  about half a top cell's radius), flowing out of the body in a trumpet
  three times its width from under the membrane (its outline hidden over
  the soma), a white-blue glass edge, dark violet glass inside, golden
  filaments and glow only near the sender, faint myelin beads, golden
  sparks in it; a golden bouton with golden-white vesicles, a cyan cleft and
  transmitter, golden sparks spraying round the synapse. Impulses amber in
  a warm orange halo (NeuronPalette.impulseHalo (1,0.58,0.22)).
- Background (NeuronTissue): dark teal-navy (NeuronPalette.deep
  (0.02,0.05,0.085), the close-up's darkest) under soft teal, blue and
  violet glows peaking near (0.06,0.17,0.25); 28 far neurons blurred out of
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
  - inner 0.8, openNucleus 0.6, nucleusRoom 0.9, room 0.05, wobble 0.015,
    fill 0.22, cellDrift 0.012, reach 1.9, sheetGap 2.8.
  - zones: in a cell the parts within nucleusRoom·openNucleus·R, the notes
    from openNucleus·R (plus the room) to inner·R, the notes' zone shrunk
    at least as much as the parts'; in a part all within inner·R.
  - cellSphere = clamp(0.34+0.035·log2(1+count), 0.34, 0.6);
    partShare = clamp(0.1+0.03·log2(1+count), 0.1, 0.22).
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
  - arbor: rpClock, rpMotion, rpProbe, rpDetail, rpTintA (its sway: rpSway,
    rpWobble); its material is clocked and swaying.
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
  design/port-asr-bench. red-pen-ios's branches were swept on 9 Oct (the
  GitHub compare API against personal; local counts mislead, because the
  clone is shallow):
  - in personal: every gaps/* and wip/* lane, design/lanes-*,
    merge/lanes-ui and the design/port-* branches;
  - aahp/*: another session's (aahp/personal 13 ahead, aahp/red-pen is
    main plus one). Leave them alone;
  - main (8 ahead): the 23 Sep workflow_dispatch entries, which run on
    personal; on main by design. claude/new-session-eskvv8 holds only
    those and merges;
  - cursor/neuron-circuit-perf-d39a (6) and cursor/ideas-map-quality-40a2
    (4): Cursor's 3D, dropped (#18). design/codex-fixes (3): never merge;
  - design/prework-20261006 (22): Cursor's 6, 696192f02 and 15
    "pre-work:" commits from another agent's 6 to 7 Oct run, mostly a
    separate scaffold under prework/medical-assistant/. Its three real
    fixes are section 3, step 9.
  Still to check: Chat-me's branches.
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
  is merged (e094da0). Done for red-pen-ios: every gaps/* and wip/* lane
  is in personal (the 9 Oct sweep, #7). perf-core-backup and
  neuron-circuit-redesign are recorded (5360fb1, ac66667); a11y, l10n and
  audio came through design/lanes-ui; growth-p0-1 and growth-p0-2a through
  design/lanes-growth; wip/3d-neurons-m3, M3's own branch, joined on 9 Oct
  (67f4714).
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
