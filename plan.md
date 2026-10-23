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

Last updated: 2026-10-14 (session branch claude/repo-branch-status-check-4k6js8).

## 1. Working with the owner

- The owner has only an iPhone and an iPad. Anything that needs a Mac (the app
  build, screenshots, recordings) runs in GitHub Actions.
- Give times in Cairo time: `TZ=Africa/Cairo date '+%I:%M %p'`. When the owner
  asks how long is left, give an ETA, and say early if it slips.
- Post only when something lands or fails. When a "hasn't heard from you"
  reminder comes, answer with a few words of status and keep working.
- Don't idle-wait, and don't ask what you can settle yourself: make the
  sensible choice and say what you chose.
- Keep GitHub's free machines busy (the owner, 14 Oct: "make sure to always
  use the free macs and machines in github so they don't stay free or failed
  in background"): up to 5 macOS runners and the Linux ones at once. While a
  run works, do the next independent step and dispatch independent runs
  together. Read every failure at once and fix it, or re-run once if it died
  before any test ran. Cancel superseded runs so they don't hold a Mac.
- Send screenshots of every visual change with SendUserFile. No zip files.
- Macaly is dropped: never mention it, its connector or its auth notices, and
  don't relay any other connector's auth notices either.
- The stethoscope art (app icon, launch mark) is private since 21 Oct: only plain stand-ins live here; never commit it, it is added to the built app at download.

## 2. State

| Branch | Head | What it holds |
|---|---|---|
| wip/3d-neurons-m3 | "Plan: M3 joins personal" | M3, done: the cells, parts and notes, one membrane per cell, links as dendrites from both cells (round D); #20 found no freeze of the app's own, only XCTest unable to end it while the simulator's first boot settled, and the fix (0435184: boot during the build, wait for the Mac's load) was confirmed by run 37862852271, green; this commit is what personal took (section 3, step 7) |
| design/3d-overhaul | the same as wip | M1 (c122abb, Space), M2 (no Circuit, d4cff03) and the M3 code; the App build here is the compile check for the Mac-only files (GraphNeuronLook, GraphRibbons, GraphMotion, GraphThemeScene, GraphDeathScene, GraphHangReporter) |
| preview/3d-overhaul | 66791a5 (run 37879552679, green: the preview of the map lighter, section 3, step 14); the commits after it change only this file and docs/chatgpt-tasks.md | a push here makes screenshots (don't push here while a run is in progress: a push cancels it) |
| shots/3d-overhaul | 04b044e (run 37879552679) | where design-preview.yml commits them |
| personal, claude/new-session-013tes5v | M3 (joined on 9 Oct at about 3:40 AM; before it, 3827785), the port (section 3, step 9; joined at about 4:40 AM; its App build, 37870387509, green), the claim gate's direction check (step 10; joined at about 4:55 AM) and the map lighter with the app's words for the direction finding (step 13; joined at about 6:35 AM; its App build, 37879541559, green) and the Worker's dose rule (step 17; joined at about 8:15 AM), then the loop's tasks 1 and 3 (step 15) and the Worker's swapped-term rule (step 18; joined together at about 10:50 AM; Server tests 37900489984 green on 695ca2f), then step 20's GAP 2, GAP 1, GAP 3, Row 4, Row 18, Row 91 and Row 1 (design/launch-gaps; joined at about 11:05 AM; App build, Server tests and Swift tests green on 512d48d), then step 19's re-pin of the Worker to Chat-me 746a7d7 (design/map-lighter; joined at about 11:37 AM as 809ddac; Server tests 37906094562 green), then step 21's three-letter comparison side (design/map-lighter 4a68424; joined at about 11:57 AM as a2a144f; Server tests 37908408628 green), then step 20's Row 17, library pictures as blob references, and the preview screens signin and account-deleted (design/launch-gaps; joined at about 12:20 PM; App build, Server tests and Swift tests green on e45ebc4), then steps 22 to 24: short swapped terms, the map's cancelled-rebuild race and swapped routes (design/map-lighter 252bbe3; joined at about 3:45 PM with step 26; App build 37913421797 green on 382a950, Server tests 37928627326 on 252bbe3) | personal is the working branch; keep session branches equal to it |
| claude/medical-assistant-orchestration-javb9y | equal to personal (d16846d): personal 537ccc4 plus the neumorphic app (#33, tasks T0018 to T0032) and the #33 follow-ups (no fading, blue control edges, cut lines, the home grid band with its rounded opening, no strip or glow under floating controls); personal fast-forwarded to b74dd06 at about 5:58 PM and to d16846d at about 7:05 PM, each with App build, Swift tests and iOS preview green | keep equal to personal |
| aahp/personal | T0033's cece1a4 on T0032 (4ef98ff) | the design loop's branch (#33, tasks T0018 to T0033); its CI runs read-only and publishes nothing; cece1a4 is kept out of the session branch |
| design/port-prework | 5d0edcd (in personal) | the three fixes found only on design/prework-20261006 (step 9, done) |
| design/claim-direction | c0f61e8 (in personal) | the claim gate's direction check (#24, section 3, step 10) |
| design/launch-gaps | GAP 2, GAP 1, GAP 3, Row 4, Row 18, Row 91 and Row 1 (section 3, step 20), then Row 17 (library pictures as blob references) and the preview screens signin and account-deleted, all in personal; the screenshots of GAP 1, GAP 2 and Row 1 taken in one ios-preview.yml run (37910253540, green, on e45ebc4; sent to the owner at about 12:35 PM): signin light and dark, account-deleted and library-loading light; their dark shots caught the simulator mid-launch (no crash report), worth one more run of just those two if wanted. Step 20 is done | the launch checklist's open gaps and the audit's open rows (#35, section 3, step 20), each merged into personal once preflight and CI are green |
| design/map-lighter | c9c7d7f (in personal): the map lighter (#28, section 3, step 13) and the app's words for the direction finding (step 10); then plan commits and the Worker's dose rule (#33, step 17: server/ and this file, so Server tests only); then the loop's tasks 1 and 3 (8b529c4, 2d35c18: step 15; App build 37891118222, Server tests 37891118204 and Swift tests 37891118199, green) and the Worker's swapped-term rule (#34, step 18: server/, docs/ and this file; Server tests 37900489984 green), all in personal; then the Worker's re-pin to Chat-me 746a7d7 (step 19: server/ and this file; Server tests 37904982081 green on f5ebba9; in personal as 809ddac); then step 21, a three-letter side of a comparison (4a68424: server/ only; Server tests 37907873352 green; in personal); then steps 22 to 24 (e372ec0 and 252bbe3, server/ only; 382a950, ForceLayout3D.swift: App build 37913421797 green; in personal) | the App build here (37878253817, green) is the compile check for the Mac-only files it touches (Graph3DView, IdeasView, GraphLook, GraphNodeShaders, GraphNeuronLook, GraphThemeScene, GraphUniverseScene, GraphMotion) |

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
- Shot 13 ("landscape") was portrait on the iPhone while the iPhone app
  was portrait-only. Since T0138 the iPhone turns too (Portrait,
  LandscapeLeft, LandscapeRight; never upside down; project.yml, held by
  DevicePostureTests), so the shot turns from the next run.
- T0138 (iPhone and the foldable iPhone): [x] iPhone landscape both ways;
  [x] DevicePosture (posture x orientation, hinge band, panes; stand-in
  band from `-uiPreviewPosture folded|open|half` with
  `-uiPreviewOrientation portrait|landscapeLeft|landscapeRight`); [x]
  modeScreen/wardScreen/wardForm, home and Ideas keep to one side of the
  band, the study deck splits across it (StudyBarHost); [x] the frame's
  corner from the display, not the idiom; [x] iphone-duo.yml (discovery,
  duo, iphones) and ios-preview.yml's `orientation` pass;
  [x] RotationStateUITests. Waiting on CI: GitHub's images (23 Oct) have
  no foldable iPhone simulator and no hinge API in any SDK (macos-latest:
  Xcode 26.x; xcode-27 preview: 27.0, 27.1 RC, 27.2 beta, iOS 27.0
  runtime only), no iPhone SE; the Duo's corner radii are unknown, so the
  duo job fails loudly until an image has one. Left: quiz options on the
  controls side of a half-open fold (the deck is there; the options still
  scroll with the stem), the dock on its own side of the fold at home,
  and the inline navigation title, which the system centres on an
  upright band.
- app-build.yml runs on every push to personal and design/**. Keep work in
  progress on wip/3d-neurons-m3 until the app compiles. To compile-check it
  there, dispatch the build:
  `gh workflow run app-build.yml --ref wip/3d-neurons-m3`, then
  `python3 tools/ci_status.py wip/3d-neurons-m3 --wait`.
  SceneKit files can't be type-checked on Linux, so this is the only compile
  check for GraphNeuronLook, GraphThemeScene, Graph3DView and GraphSim.
- android-personal.yml (T0115c) builds the owner-keyed APK on a design/integration push whose message has `[personal apk]` (or by dispatch) and uploads it only encrypted (artifact personal-apk-encrypted, 1 day): decrypt apk.key.enc with the private key (`openssl pkeyutl -decrypt -inkey private.pem -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256`), then the APK with `openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass file:apk.key`.
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
8. [x] #33, the neumorphic app, was made on aahp/personal by another
   session (the owner, 8 Oct, 4:16 PM: "anotger session is already making
   the neumorphic part"). The owner's word of 9 Oct ("i give u
   permission") moves it into personal: it is on the session branch
   claude/medical-assistant-orchestration-javb9y, and personal moves up to
   it once its preview run is checked; section 5, #33 and its follow-ups.
   Done: personal reached d16846d on 9 Oct with App build, Swift tests and
   iOS preview green (section 5, #33 follow-ups, item 11).
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
     AM, after step 7's run. Personal's own App build on it (37870387509,
     5d0edcd) green at about 5:20 AM: the UI suite said TEST SUCCEEDED,
     28 of 28 (the map's 21 among them); the accessibility step failed as
     before (two tests: no example mcq or anki set in the library, no
     Mixed quiz tile), continue-on-error. Not ported: INT-PREVIEW (the shots
     branches keep only the latest run, by design) and the rest of that
     branch (another agent's prework/medical-assistant scaffold, PARTIAL
     or BLOCKED by its own notes).
10. [x] #24, the claim gate reads which way a sentence goes, on
    design/claim-direction (from 5d0edcd). The Worker's claim gate
    (server/claims.js) caught a flipped negation, dose, frequency or
    percentage, but not a sentence turned around: a card's "Statin therapy
    is associated with a reduced risk of new-onset diabetes", written from
    a lecture's "a modestly increased risk", went through. Chat-me's
    50-claim benchmark
    (tests/test_adversarial_50_benchmark.py on verification-layer-adversarial-50
    and -commercial-accuracy-v1: 40 true claims, each with the passage it
    came from, and 10 false ones, mostly true ones turned around) showed
    it: the gate gave 0 of the 10 a hard finding. C's evidence model
    (evidence_model.py on verification-layer-commercial-accuracy-v1, at
    030ed8c) reads a direction axis and caught 8 of 10; personal's Chat-me
    verifier passes 4 of them (F02 to F05) as SUPPORTED (step 11).
    - [x] turnedAround() in claims.js, after C's direction axis but not a
      port of it: two axes (raises or lowers, higher or lower, above or
      below; high or low, common or rare, minimal), one such word on an
      axis or the sentence says no way on it ("increase the dose to reduce
      side effects"); a part or thing such a word names (the lower limb,
      the greater trochanter, the common bile duct, minimal change disease,
      "see below") is not a way; every other word stays the same, short
      names and numbers too (LDL is not HDL, men are not women), a measure
      being any measure (a higher rate, a lower risk); and what a
      comparison is against does not swap sides. A negated sentence is
      left to the negation check. The finding is hard ("direction"), and
      the sentence turned around never backs the item it contradicts.
      Left out: C's third class, "neutral" (no change, unchanged,
      noninferior, no difference), against a sentence that goes one way.
    - [x] tests/claims.test.mjs: nine sentences turned around and nine
      that are not (one-sided comparisons, swapped sides, hyphenated
      names, "Lower doses" and "Higher doses", upper and lower motor
      neuron); the nine fail on the old gate. The benchmark (run from
      scratch, not committed: it is Chat-me's): 6 of 10 false claims get
      a hard finding (F01, F02, F04, F05, F06, F09), 0 of 40 true ones.
      Out of its reach: F03 (its passage says no way), F07 and F08
      ("unfounded": what the evidence is, not which way), F10
      ("coadministered" against "coadministration": 3 of 7 words). The
      ordinary batch takes no longer (about 2.4 ms warm).
    - [x] Preflight, push, CI green, then personal and the session branch.
      Done: preflight OK; Server tests 37871595207 green on aff3e44;
      personal and claude/new-session-013tes5v fast-forwarded to this
      commit on 9 Oct at about 4:55 AM. Server and plan only, so it
      started no App build and left personal's running one (step 9's
      port, 37870387509) alone.
    - [x] The app's own words for it, with the next batch of ios/ work (it
      starts a Mac run): AccuracyAssessment.holdReason("direction"), "Says
      the other way from its own lecture.", and "direction" in claimHolds'
      doc (AccuracyLedger.swift). Done with step 13's push on
      design/map-lighter; the accuracy suite checks the words.
    - Live only after a Worker deploy, which needs the owner's word.
11. [x] Chat-me (the owner attached it to this session with push on 9 Oct
    at about 7:00 AM, after an earlier refusal): port the 50-claim benchmark
    into personal's evals, so the verifier is held to it, and give
    personal's verifier C's direction axis, so F02 to F05 stop passing as
    SUPPORTED; and correct the verifier README's `app.main:app` to
    `api.main:app`. C itself can't be merged as it stands (section 5, #7).
    Done in Chat-me d17635d (personal, 9 Oct, about 7:20 AM; its Python CI
    green):
    - evals/suites/adversarial_50.py runs the 50 claims through the whole
      pipeline, each with its own passage as two sources from two families;
      tests/unit/test_adversarial_50_benchmark.py holds it: no false claim
      supported, and at least the 15 true ones it supports today.
    - agents/specialists/verification_agent/direction.py, read per atom in
      `_atomic_alignment`: the change axis (increases, lower) and the amount
      axis (high, rare), as in the Worker's turnedAround; part names
      (lower limb, common bile duct, low-dose) and cut-offs ("below 30"
      against "< 30") say no way, and a swapped comparison reads the same
      way. A wrong-way reading abstains (UNKNOWN), never contradicts (22f
      fail-safe brief; ACCEPTANCE_GATES.md), since curriculum and question
      validation take an independent CONTRADICTS outright.
    - F02 also needed the multilingual normaliser to swap whole words:
      Spanish "reduce" turned English "reduced" into "reducesd".
    - Result: 10 of 10 false claims no longer supported (F02 to F05 were
      SUPPORTED); 15 of 40 true ones kept, the same 15; no other verdict
      moved; 184 tests pass.
    - The README's quick start runs from the repository root
      (`api.main:app`), and its commercial-use note points at the NOTICE
      beside it (docs/COMMERCIAL_USE.md never existed).
12. [x] #27, the 3D map's audit findings left from before M3, checked
    against the code after it (Chat-me personal:
    docs/architecture/audit/stethoscore-verified-findings.md, rows 107 to
    115; 108, the aliased wiki link, was fixed before):
    - 107, real in part: the map's signature (Graph3DView) was worked out
      on every redraw of the screen around it, and counted every note's
      words each time. The editor saves half a second after typing
      pauses; a full rebuild came only when a name, folder, link or size
      step changed, as the audit found. Step 13.
    - 109, real: a still map drew at the screen's full rate, and went on
      under the sheets over it. Step 13.
    - 110, real: every rebuild made SceneKit text for every body's name
      on the main thread, though only the hovered, pressed or chosen
      one's ever shows. Step 13.
    - 111, real but small: GraphSim holds its lock while it writes to the
      nodes. Left until a frame trace shows it costs a frame.
    - 112, real: a shader probe that fails once (with the app in the
      background, say) turns the shaders off until the app is quit.
      Step 13.
    - 113, fixed already (41e90a5: the map refits when its size changes).
    - 114, real: a layout the map no longer wanted ran to the end. Step 13.
    - 115, not a fault: a new feature (a card set's source note), left for
      the roadmap.
13. [x] #28, the 3D map lighter, on design/map-lighter (from 84fcf66; the
    owner: the map is "wasting lots pf resources"):
    - [x] 109: the frame rate follows what the map is doing (GraphPace): a
      lively map draws at its full rate while touched and for 3 s after,
      then 60, and 30 after 20 s untouched; a still one at 60 at most while
      touched and for 3 s after, then 20; 20 under a sheet (the map's own,
      and the Ideas screen's over it: Graph3DView's `covered`, which the
      Playgrounds stand-in, tools/playgrounds_stubs/graph3d.swift, takes
      too). Suite graphics, G7a to G7u.
    - [x] 114: a newer change cancels the layout it supersedes (GraphWork,
      the loop's check). Suite forcelayout (new).
    - [x] 107: the notes' part of the signature as one hash, a note's words
      counted again only when its text changes (GraphShapeKey). Suite
      shapekey (new).
    - [x] 110: names made the first time they show (GraphLabelNode, an
      empty holder that GraphSim, in GraphMotion, fills when its name
      first goes up).
    - [x] 112: a shader check's answer is kept only when it can be
      trusted: every shader passed, or the app was in front, in one visit,
      from its start to its end (GraphProbeMemo; suite probememo, 18
      checks; 12 planted bugs, all caught). The main thread builds with the
      answer it has and never waits behind a check; the map checks and
      builds again when the app comes back with an answer not kept, or
      when a build ends in front with one (Graph3DView.recheckShaders). A
      check still running is not "unsure", so the app's arrival at launch,
      mid-check, does not build the map twice.
    - [x] Preflight, push, App build green, then personal and the session
      branch. Done: preflight OK (76 of 76 Swift suites, every server
      test, the four Playgrounds packages); App build 37878253817 and
      Swift tests 37878253831 green on c9c7d7f; personal and
      claude/new-session-013tes5v fast-forwarded on 9 Oct at about
      6:35 AM. That push runs personal's own App build (the whole UI
      suite).
    - Left: 111 (section 3, step 12). NoteStore.allEdges(), which the
      signature asks for on every redraw, is already kept until a note
      changes (its edgeCache), so it needs nothing.
14. [x] #29, one preview run for step 13: preview/3d-overhaul
    fast-forwarded to personal's tip. Check 45-1 and 45-2 (names over
    bright bodies: names are now made the first time they show), that the
    shaders are on, and a cell's opening and closing; send the owner the
    name shots. Done: run 37879552679 on 66791a5 green (45 tests passed,
    none failed; shots on shots/3d-overhaul at 04b044e). The names on 45-1
    and 45-2 read on iPhone and iPad (the iPad's "Heart failure" pill is a
    little lower in contrast, still legible); the shaders are on (the sun's
    corona, the gas giant's bands, the neurons' glass and glow); cells are
    closed at rest and open in turn (Examples, then Inguinal inside it).
    The four name shots went to the owner at about 7:25 AM. personal's own
    App build on the map lighter (37879541559) is green too.
15. [ ] #30, the owner's "give repetitive tasks to chatgpt through the
    loop": docs/chatgpt-tasks.md lists four tasks (two wrong labels, rows
    40 and 34; a re-check of 31 audit rows; the on-device recogniser's
    lupus list, row 74; then fixes from the re-check, one area at a time),
    each clear of the files personal changed and of the neumorphic work.
    - [x] Pick rows still open on aahp/personal (d7da19a); most rows the
      audit lists as open turned out fixed (the doc names them).
    - [x] Queue them, one at a time; this session sends them ("u send the
      packets not me", 9 Oct, about 6:55 AM). The owner attached the loop's
      repository to this session with push at about 7:00 AM. Task 1 (the
      two labels) went in as the loop's turn 55 at 7:02 AM and was approved
      at turn 57 (7:23 AM; aahp/personal 7358ef8): the account header's Pro
      chip shows a real subscription, the personal build hides "Restore
      purchases", and the Mixed tile reads "20 across all your sets". The
      loop's note for the owner: no preview shot shows the Mixed tile or
      the Account page; an Account screen in the preview would show rows
      34 and 40. Task 2 (the re-check, a report only) went in as turn 58
      at 7:26 AM and was approved at turn 60 (7:31 AM): of its 31 rows, 26
      are fixed, 1, 17 and 91 are open, and 4 and 18 partly
      (docs/chatgpt-tasks.md, task 4, has what is left). The packets for
      tasks 1 to 3 are in the session's scratchpad and went to the owner,
      kept out of this repository (the loop's format is private); a new
      session rebuilds them from docs/chatgpt-tasks.md in the format of the
      loop's last task commit.
    - The loop is shared: another session queued its own task at turn 61
      (7:33 AM), and it was still in review at turn 64 (8:02 AM). Never
      overwrite or start another session's task. Task 3 goes in once that
      one is approved, under the next free task number, with the turn
      after the approval, the approving commit as its base and
      aahp/personal's tip as its target base; then run the loop's worker.
      The same for each task after it.
    - Task 3 (the recogniser's words) went in as turn 66 at 8:19 AM, its
      result came back at 8:21 AM, and it was approved at turn 67 (8:43 AM;
      aahp/personal 4ef98ff; Server tests, Swift tests and the iOS preview
      green, 36 shots, none changed beyond capture noise). The loop's note
      for the owner: on book-light, the Back label wraps onto two lines,
      as it did before this change.
    - Task 4's first area (Spotlight's failed index or delete calls, row
      4) went in as turn 68 at 8:49 AM. The loop's reviewer hit its rate
      limit; the task was run again and approved at turn 69 (10:20 AM;
      aahp/personal cece1a4). The launch-gaps session fixed row 4 too
      (design/launch-gaps b0ebd11, in AppIntents.swift, more fully; its
      plan's step 17). So when aahp/personal is merged into personal (the
      design session's merge, which the owner approved), launch-gaps'
      AppIntents.swift stays; take from this task only
      `SpotlightPlan.send` (Shared/Platform/AppLink.swift) and its
      PlatformTests, if they are wired in, never its AppIntents.swift hunk
      over b0ebd11. This session does not bring it over itself.
    - Row 91 is not queued: it no longer applies (launch-gaps' finding:
      the job spec has carried no check since 1 Oct, and a question counts
      as checked only on two or more blind votes from three model families
      with a source proof). So none of this session's tasks is in the loop
      now; its next task is the design session's. New repetitive tasks go
      in the same way.
    - [x] Review each result when it comes back, then bring it into
      personal. Not by merging aahp/personal: it also carries other
      sessions' loop tasks (the neumorphic restyling and frame clearance,
      in Theme.swift, Shared/Ward/* and files personal changed since, such
      as GraphLegend, NoteEditorView and CommuteModeView), which are
      theirs to bring in. So each approved task of this session's comes
      over on its own as one commit with a plain-English message: tasks 1
      and 3 on 9 Oct at about 8:55 AM (from 7358ef8 and 4ef98ff; only
      their own lines, none of the other sessions' edits to the same
      files), as 8b529c4 and 2d35c18 on design/map-lighter (App build
      37891118222, Server tests 37891118204 and Swift tests 37891118199,
      green); they join personal with step 18.
16. [x] #32, Chat-me's verifier.yml swift-test job (macOS,
    clients/ios/MedicalVerifierCore) has been red since at least d504978
    (1 Oct), with the same four failures on 28bdcf3 (7 Oct) and d17635d,
    so they are older than step 11: AdvancedClaimReasoningTests
    testTemporalScopeMustBePreserved; CrossPlatformConformanceTests
    testSharedConformanceVectors (weight_based_arithmetic gives
    SOURCE_UNSUPPORTED where the shared vectors say VALIDATED);
    MedicalVerifierCoreTests testDailyDoseEquivalenceIsSupported
    (sourceUncertain, not validated) and
    testWeightBasedArithmeticIsEquivalentOnlyWithExplicitWeight
    (sourceUnsupported, not validated). Reproduce them on Linux with
    /opt/swift if the package is Foundation-only, fix, push to Chat-me's
    personal. Done in Chat-me 4fe8af6 (9 Oct, about 7:45 AM; Medical
    Verifier CI 37885203716 green, the first green run since at least
    d504978). The cross-platform conformance doc holds a release while
    Python and iOS disagree, and the Task 4 audit puts MedicalVerifierCore
    in the app (recommendation d). Three causes:
    - the question check's dose pattern had lost its backslashes, so
      "500 mg" never matched and a dose answer read as not answering the
      question (Python had its own form of it: it looked for the unit
      among words of four letters or more, so "mg" was never seen);
    - Swift lacked Python's rule that a dose written another way with the
      same daily total ("500 mg twice daily" for "1000 mg daily") is the
      same dose;
    - Swift's relation anchors had no past tense ("increased",
      "reduced"), so a time marker before the verb was missed.
    The package's Linux run (CryptoKit shimmed) passes all 44 Swift tests;
    185 Python tests pass.
17. [x] #33, found in step 16: that same-total rule skipped every other
    check, so "Warfarin 1000 mg is given daily" was validated against
    "Aspirin 500 mg is given twice daily", in Python and in Swift, and an
    answer that added "with food" (or, on Swift, "for 7 days") passed too.
    - [x] Chat-me a4152d5 (9 Oct, about 7:55 AM; Medical Verifier CI
      37885973407 green): the rule now holds only when every other word of
      four letters or more in the claim is in the evidence too; words that
      only say how much, how often or how a dose is given (dose, daily,
      twice, every, hours, given, take and the like) may still change.
      Python's verify and semantic guard and Swift's SemanticGuard share
      the list, and three shared vectors pin it (corpus 1.4): the same drug
      stays VALIDATED; another drug, or an added course, is
      SOURCE_UNSUPPORTED. The five honest rewordings (twice daily, a
      concentration, weight-based, every 8 hours, "should be given") stay
      VALIDATED, and the 50-claim benchmark is unchanged. 191 Python tests
      and 47 Swift tests pass. Known limit: a drug the evidence names, but
      not as the one being dosed, still counts as kept.
    - [x] The Worker (server/claims.js, ported from Chat-me 2f4fd4e, step
      9) had the same rule, and its claim gate skips an item that any near
      lecture sentence supports. So a lecture with "Amoxicillin 500 mg
      three times daily" and "Ibuprofen 500 mg twice daily" let a card's
      "Amoxicillin 1000 mg daily" through: the ibuprofen sentence has the
      same daily total. doseRewordingKeepsTerms is a port of a4152d5's rule
      with its word list, in verify and semanticWarnings. The audit makes
      the shared vectors the Worker's regression corpus (Task 4 audit,
      recommendation e), so tests/claims.test.mjs keeps them at 2f4fd4e and
      lists the one vector this changes on purpose (10 mL of a 5 mg/mL
      solution twice daily against "The daily dose is 100 mg.": "solution"
      is not in the evidence, so the verifier now abstains), with the later
      Python's answers. It also holds four of a4152d5's cases (the same
      drug, another drug, a condition added, a course added) with that
      Python's answers, and two gate cases where another drug's sentence
      with the same daily total used to hide the dose and frequency
      findings. The new checks fail on the old gate; 88 pass on the new
      one. The ordinary batch takes no longer (about 2.5 ms warm).
    - [x] Preflight, push design/map-lighter, Server tests green, then
      personal and the session branch (server and plan only: no App
      build). Live only after a Worker deploy, which needs the owner's
      word. Done: preflight OK; Server tests 37887435889 green on
      a06955a; personal and claude/new-session-013tes5v fast-forwarded to
      it on 9 Oct at about 8:15 AM.
18. [x] #34, a swapped drug name passes: Chat-me's verify and the Worker's
    say SUPPORTS for "Amoxicillin treats otitis media." against
    "Ibuprofen treats otitis media.", for "Amoxicillin is used for otitis
    media." against "Ibuprofen is used for otitis media.", and for
    "Amoxicillin 500 mg twice daily for otitis media." against "Ibuprofen
    500 mg twice daily for otitis media.". Where no relation is
    recognised, the atomic subject check never runs ("Warfarin increases
    bleeding risk." against "Aspirin …" is rightly UNKNOWN,
    atomic_subject_mismatch). In the gate it is the same hole as step 17:
    a near sentence about another drug supports the item and hides what
    its own drug's sentence would find. Fix it in Chat-me first (Python,
    the Swift twin and a shared vector; abstain, never contradict, per the
    22f fail-safe brief), then port it to the Worker like step 17.
    - [x] Chat-me 746a7d7 (9 Oct, about 10:15 AM; Medical Verifier CI
      37897988851 green): once every other check has passed, the verifier
      lines the claim up against its evidence word by word, and if all
      that differs is a run of up to two content words on each side,
      neither another form of the same word nor a known alias, it abstains
      (Python UNKNOWN with atomic_term_substituted; Swift
      SOURCE_UNSUPPORTED). Shared vectors 1.5 pin a swapped drug, a
      swapped outcome and a rewording that must still pass. 199 Python and
      52 Swift tests pass; the 50-claim benchmark is unchanged.
    - [x] The Worker: termSubstituted (server/claims.js) is a port of it,
      in verify just before SUPPORTS. The one shared vector it changes on
      purpose is in DEPARTURES with 746a7d7's answer: "Lithium is
      dangerous in renal failure." against "… harmful …" now abstains (a
      true synonym, which the fail-safe brief accepts). The test adds 15
      pairs with 746a7d7's answers: 7 abstain (another drug, another
      outcome, induces for inhibits, cardiovascular for all-cause
      mortality, whose warfarin was stopped) and 8 still pass (haemorrhage
      and hemorrhage, Crohn's and Crohn, paracetamol and acetaminophen,
      "and requires" for "requiring", an added "in adults", two-sentence
      evidence, an extra clause, the same sentence). And 6 gate cases: a
      lecture sentence about another drug no longer hides an item's dose,
      frequency or negation finding; a card that only swaps the drug is a
      soft finding (atomic_term_substituted, beside the verdict, changing
      nothing); two clean items stay clean. The new checks fail on the
      old gate; 109 pass on the new one. On the probe pairs and the shared
      vectors the port gives 746a7d7's answers but for the two step 19
      re-pins. Timing is within the machine's noise (an ordinary batch
      about 2.6 ms warm before and after; the check is about 0.13 ms of
      it, and the worst batch never reaches it).
    - [x] Preflight, push design/map-lighter, Server tests green, then
      personal and the session branch (with step 15's tasks 1 and 3).
      Live only after a Worker deploy, which needs the owner's word.
      Done: preflight OK; Server tests 37900489984 green on 695ca2f;
      personal and claude/new-session-013tes5v moved to it on 9 Oct at
      about 10:50 AM.
19. [x] Re-pin the Worker's port to Chat-me personal. Measured on 9 Oct:
    besides step 17's vectors, the port still has two behaviours Chat-me
    dropped in d17635d (step 11). Its multilingual replace is not
    whole-word, so Spanish "reduce" turns English "reduces" into
    "reducess" inside its double-negation facts, and it has no direction
    axis, so "Ibuprofen reduces bleeding risk with warfarin." against
    "… increases …" abstains as atomic_object_mismatch, where Chat-me now
    says atomic_relation_mismatch. And "Metoprolol reduces heart rate."
    against "… lowers …" abstains as atomic_object_mismatch, where Chat-me
    746a7d7 says atomic_term_substituted (both abstain): the replace makes
    the claim "reducess heart rate", whose object reads "s heart"; the
    whole-word replace brings it in line. Port both, then regenerate
    tests/claim-vectors.json from Chat-me personal: bench/claim-vectors.py
    needs the module paths d504978 moved (agents/specialists/
    verification_agent/ for app/verification/), and the test's pinned
    commit and counts, the bench's docstring and claims.js's header move
    with it. DEPARTURES then empties.
    - [x] Done on design/map-lighter: Chat-me 746a7d7's whole-word
      multilingual replace and its direction.py are ported (directions(),
      and directionEntailed() at the end of atomPairCheck, so a claim
      whose way differs from its evidence abstains as UNKNOWN,
      atomic_direction_mismatch or atomic_direction_not_entailed). In the
      gate these are soft findings, and a sentence the gate already finds
      turned around is not reported a second time. tests/claim-vectors.json
      is made from 746a7d7 (125 pairs, the 41 shared vectors v1.5, 15
      which-way pairs); DEPARTURES is empty; 122 checks pass. The port
      gives 746a7d7's answers on the 43 probe pairs, the 103 vector pairs
      and Chat-me's 50-case benchmark, where verify alone now passes 19 of
      40 true claims and none of the 10 false ones (before: 3 false
      claims passed, the SGLT2 and statin ones that only reverse the
      way). Timing is within the machine's noise. One quirk shared with
      Python: a comparison's side under four letters ("than in men") is
      not read, so "Gout is less common in women than in men." against
      "... more common in men than in women." abstains as a direction
      mismatch (soft); fix it in Chat-me first, then port.
    - [x] Preflight, push design/map-lighter, Server tests green, then
      merge into personal (merge origin/personal first, keep both sides'
      lines here) and the session branch: personal and the session branch
      at 809ddac, Server tests 37906094562 green. Live only after a Worker
      deploy, which needs the owner's word.
20. [x] #35, the owner's "look for upgrades - unfinished work - half-backed
    features in the stethoscore app for u to make" (9 Oct, about 7:30 AM):
    the launch checklist's open gaps (docs/launch/launch-checklist.md
    section 1.3) and the audit's rows still open, built on
    design/launch-gaps. Clear of step 15's loop tasks (rows 34, 40, 74 and
    the re-check), steps 16 to 19 (another session's), the neumorphic work
    and the map. Order: what Linux and node can check first; the screens
    last, in one preview run.
    - [x] GAP 2: no "Sign in with Google" door in a build without a Google
      client id (AuthRules.googleClientID, GoogleSignIn.isConfigured; the
      cloud blocker then names only Apple). Checked by the account suite
      (macOS CI); its screenshot goes with GAP 1's.
    - [x] GAP 1: after an Apple-linked account is deleted, the sign-in
      screen gives the steps from Apple's support article 102571 (Settings
      > your name > Sign in with Apple > Stethoscore > Delete), in English
      and Arabic (AuthProvider.listedInSettingsAfterDeletion,
      AccountStore.appleStepsDue). Checked by the gates suite; its
      screenshot goes in the preview run with GAP 2's.
    - [x] GAP 3: the server already cleared a deleted account's
      generation jobs (worker.js forgetEverything calls jobs.js /wipe) and
      pruned pair_attempts nightly. What was left was the privacy policy,
      which now says tries are counted against the IP address and kept
      for at most three days (limits.js ATTEMPTS_KEEP_HOURS, checked by
      legal.test.mjs). The policy goes live with the next Worker deploy,
      on the owner's word.
    - [x] Row 4: Spotlight failures are no longer swallowed
      (Shared/AppIntents.swift): a refused batch or removal leaves nothing
      confirmed and is sent again at the next library change or launch; a
      refused clear keeps what Spotlight holds counted, so the next update
      with the toggle off asks again; both are recorded as failure reports
      (app area). Compiled by the mac App build.
    - [x] Row 18: the schedule (Persistence/ReviewStore.swift) is written
      a second after the last rating, encoded off the main thread, and
      flushed when the app leaves the foreground. A schedule that could not
      be read at launch (a prewarm before the first unlock) is never
      written over; it is read again once the app is in front and merged
      with anything taken in meanwhile. Sync waits for the schedule as well
      as the library before any bookmark (SyncEngine.savedHere), and skips
      encoding and hashing a deck whose records the server already holds
      (SyncEngine.packedSchedules; the payload's bytes unchanged, checked
      on Linux against the old packing). The library's write failure now
      reaches the failure reports under a key (library.write_failed) rather
      than "unknown". Compiled by the mac App build.
    - [x] Row 91 no longer applies: there are no cloud generation verdicts
      left to seed the accuracy ledger from. Since the verification layer
      (1 Oct) the app's job spec carries no check (Shared/LLM/CloudJobs.swift,
      Spec); the server runs the checker only for a job that asks for one
      (server/jobs.js), which only builds from before then do, and nothing
      but the citations reads those replies. One checker's reply could not
      count in the ledger anyway: it saw the key, and a question counts as
      checked only on two or more blind votes, from three model families,
      with a source proof (AccuracyLedger.isChecked).
    - [x] Row 1: the library is read off the main thread at launch
      (Store(inBackground:), Persistence/Store.swift). Nothing is written
      before it is in: a flush asked for meanwhile waits for it, and a set or
      folder added meanwhile is kept on top of what was read. A library that
      could not be read (a prewarm before the first unlock) is never written
      over; it is read again once the app is in front. The launch splash
      stays up until the library is read, 2 s at most, then goes (no fade) onto a
      screen saying it is opening (LibraryLoadingView, preview screen
      library-loading); no screen shows the library before it is in, and
      the examples, sync, a notification's answer, the second iPad window
      and Siri's queries wait for it (Siri reads the saved copy meanwhile).
      Checked by the storeload suite (macOS CI); its screenshot goes in the
      preview run with GAP 1's and GAP 2's.
    - [x] Row 17: the library file holds its pictures as blob references
      ("blob:<sha256>"), each picture a file in the picture cache
      (Application Support/RedPenBlobs; a test's or preview's library uses
      a "<stem>-pictures" folder beside it), so a rename or a rating no
      longer rewrites megabytes of base64. In memory a set still holds
      base64 (about 87 call sites read `.images`): Shared/LibraryPictures.swift
      packs as the file is written (on the write queue, the blob confirmed on
      disk before its reference is written; a picture whose blob cannot be
      written stays inline; a picture in two sets is one file) and fills in
      as it is read (a missing blob stays a reference, for sync to fetch).
      The migration: a file with any decodable inline picture is written
      again at launch. The picture folder is now in the phone's backup
      (BlobCache and LibraryPictures set isExcludedFromBackup false), since
      it is the only copy on the device. The sweep moved from SyncEngine (a
      main-actor sweep raced the write queue) into the Store, right after a
      library write lands, at most once a day, only with the library read
      whole; it keeps what the file names, what unread sets and the
      library's recovery copies mention, and anything from the last day.
      DeckExport fills a set's pictures before either export (Siri's
      savedLibrary now returns references). Recovery copies now hold
      references too, so their pictures stay on the device, not in the
      copy. A downgrade is acceptable: references survive as strings and
      sync restores them. BlobRefs and SyncMerge hash with a plain-Swift
      SHA-256 where CryptoKit is missing (FIPS 180 vectors), so the new
      pictures suite and the sync suite run on Linux; storeload (macOS)
      checks the migration, the rename, the failed blob write, the missing
      blob, the data: prefix, the shared picture and the sweep rules.
    - [x] The screenshots: one ios-preview.yml run (37910253540, green, on
      e45ebc4) with the new `screens` input: signin (GAP 2, no Google door),
      account-deleted (GAP 1, Apple's steps) and library-loading (Row 1),
      in light; signin in dark too. The dark account-deleted and
      library-loading shots caught the simulator mid-launch (no crash).
    - [x] No fade at launch either (the owner's "i don't want fading in the
      app", #33; the design session left LaunchSplash to this step): the
      splash is lifted at once after its 0.3 s hold, or as soon as a big
      library is read (2 s at most), with `.transition(.identity)` so no
      animation around it can fade it. Compiled by the mac App build; a
      still screenshot cannot show a transition.
21. [x] Taken by the session that did step 19 (9 Oct, 11:40 AM): the
    "men" quirk from step 19. A comparison's side shorter than four letters
    is not read, so "Gout is less common in women than in men." against
    "... more common in men than in women." abstains as a direction
    mismatch. Fixed first in Chat-me's direction.py (three-letter words
    count as a side unless they are function words like "the"), then
    ported to server/claims.js. Touches Chat-me's direction.py and its
    test, and here server/claims.js, its tests and claim-vectors.json:
    nothing of step 20's. No audit rows or loop tasks are taken; audit
    item 111 (step 12) stays left until a frame trace shows it costs a
    frame.
    - [x] Chat-me ff476bd on personal (its CI 37906556942 green; Python
      200 passed): three-letter words count as a side, except function
      words, so a shared "the" no longer makes two different comparisons
      read as one swapped. The Swift twin has no direction check.
    - [x] Ported on design/map-lighter, 4a68424 (Server tests 37907873352
      green): sideWords() in server/claims.js; the vectors made again
      from ff476bd with three new pairs (128 pairs); the old port fails
      four of their checks, the new one passes all 122. The 50-claim
      benchmark through verify gives Python's answer on every case (19
      of 40 true claims supported, none of the 10 false). Before, "Risk
      is higher in women than in the elderly." was supported by "Risk is
      lower in the young than in women."; now it abstains. Merged into
      personal as a2a144f (Server tests 37908408628 green); live only
      after a Worker deploy, on the owner's word.
22. [x] Taken by the session that did steps 19 and 21 (9 Oct, 12:02 PM): a
    swapped term under four letters still passes. Chat-me ff476bd and the
    Worker both answer SUPPORTS for "Statins lower LDL cholesterol."
    against "Statins lower HDL cholesterol.", "Tenofovir treats HIV
    infection." against "... HBV infection." and "Aspirin is used after
    MI." against "... after PE.": the swapped-term rule (746a7d7's known
    limit) and the overlap checks read only words of four letters or
    more. Fix it in Chat-me first (Python, and the Swift twin in
    MedicalVerifierCore, with a shared conformance vector, as 746a7d7
    did), keeping the 50-claim benchmark's answers; then port it to
    server/claims.js and make the vectors again. Touches Chat-me's
    verification_agent and MedicalVerifierCore, and here server/ only:
    nothing of step 20's.
    - [x] Chat-me 3df53cd (its CI 37909547536 green; Python 202 passed,
      Swift 54 on Linux, conformance 1.6): a word of three letters or
      fewer is a term unless it is a joining word or a short way of
      writing a dose; one route's two names (PO, orally), a short name
      and the two words it stands for (AF, atrial fibrillation) and a
      clotting factor and its activated form (Xa, activated factor X)
      are not swaps. The 50-claim benchmark is unchanged.
    - [x] Ported on design/map-lighter, e372ec0 (Server tests 37913421490
      green): 137 vector pairs, no earlier pair's answer changed, the old
      port fails six checks; the benchmark gives Python's answer on every
      case.
    - [x] Merged into personal with steps 23 and 24 (9 Oct, about 3:45
      PM), after the App build on 382a950 (37913421797) came back green.
      Live only after a Worker deploy, on the owner's word.
23. [x] Found by step 22's preflight: the forcelayout suite's F4f ("a
    rebuild cancelled before its job starts cancels it too") failed under
    load, twice in three runs. A real race in GraphWork.offMain
    (Features/Notes/ForceLayout3D.swift, step 13's audit row 114): the
    detached job could start and look before the cancel handler reached
    it; a stress run missed the cancel 187 times in 20,000. Fixed on
    design/map-lighter, 382a950: a rebuild already cancelled starts its
    job cancelled (none missed in 20,000; preflight 76 of 76 suites).
    Its App build (37913421797) and Server tests (37913421490) green;
    merged into personal with steps 22 and 24.
24. [x] Taken by the same session (9 Oct, 12:49 PM): a joining word next to a
    swapped route still hides it, so "Adrenaline 0.5 mg IV for
    anaphylaxis in adults." is backed by "Adrenaline 0.5 mg IM is given
    for anaphylaxis in adults." in Chat-me and in the Worker's gate (no
    finding at all). Dropping joining words from every swap costs four
    true claims of the 50-claim benchmark, so only routes: a claim and
    evidence that name different routes, and no route in common, are a
    swap whatever words stand around them. Chat-me first (Python, Swift,
    conformance 1.7), then server/claims.js.
    - [x] Chat-me cda5d2c (its CI 37913865434 green; Python 203 passed,
      Swift 55 on Linux, conformance 1.7): a claim and its evidence that
      each name a route, and no route in common, are a swap (Python
      UNKNOWN with atomic_term_substituted, Swift SOURCE_UNSUPPORTED).
      The route names also cover intrathecal, sublingual, rectal,
      topical, inhaled, intranasal and intradermal, each with its adverb.
      The 50-claim benchmark is unchanged.
    - [x] Ported on design/map-lighter, 252bbe3 (Server tests 37928627326
      green): 139 vector pairs; only the adrenaline pair's answer moves,
      in Python and in the port alike; the old port fails two of the new
      checks; the benchmark gives Python's answer on every case. Merged
      into personal with steps 22 and 23; live only after a Worker
      deploy, on the owner's word. Known limit, as in Chat-me: a claim
      naming two routes ("IV or IM") against evidence naming one of them
      is not a swap.
25. [x] Taken by the same session (9 Oct, 3:30 PM): no fading in the map
    (the owner's "i don't want fading in the app", #33). The design
    session ended the fades across about 40 screens (its 451713b, on
    claude/medical-assistant-orchestration-javb9y) and relayed that
    Graph3DView.swift is this line of work's; step 20 took LaunchSplash's
    out (ef6b17d). Graph3DView still fades four overlays: the flown
    region's name pill and a body's options menu (.opacity), the Link
    length bar and the peek card (.move(edge: .bottom) with .opacity).
    As in the rest of the app, the pill and the menu will simply appear
    (.identity), and the bar and the card slide without fading. It
    changes how the map looks, so it goes in one Mac run on
    design/map-lighter, whose App build is its compile check. The 3D
    scene's own effects (the black hole's last glow in GraphDeathScene)
    are not interface fades and stay.
    Done in design/map-lighter babed74 (App build 37933396423 green; the
    four transitions only, and the map's animations are already nil under
    Reduce Motion). Merged on top of personal be11a56 on 14 Oct on the
    session branch claude/repo-branch-status-check-4k6js8; the merged
    Graph3DView.swift is byte-for-byte the one that built. personal
    fast-forwards to it on the owner's word.
26. [x] Taken by the same session (9 Oct, 3:30 PM): the server tests'
    CPU budget checks read a wall clock, so a busy machine failed them:
    proof.test.mjs's cold start (one fresh process, 19 to 48 ms alone
    against 50) failed preflight here and for step 20's session, and with
    four cores busy even the best of three reached 57.6 ms;
    claims.test.mjs's warm median reached 8.5 ms against 8. Both now read
    process.cpuUsage() (the per-thread reading is too coarse here, in
    steps of about 4 ms), and the proof test takes the least of three
    fresh runs, as a89349d did for the claim test. With four cores busy
    the readings barely move; a real slowdown (8 ms more in each prove())
    still fails five of the six proof budget checks. design/map-lighter
    9cc61b1 (Server tests 37931566404 green), merged into personal with
    steps 22 to 24.
27. [ ] The UI suite's red of 15 Oct (App build 38684974986, bc611221),
    on design/ui-suite-fix. Not a freeze of the app's own: the tour
    (DesignTourUITests) timed out three times on one query on Ideas >
    Space (foldSwitcher, "ideasMode-list", line 626); then
    ExamplesUITests could not end the app and GraphPreviewUITests could
    not launch it. Read from the run's bundle (session log, the app's
    stdout and stderr):
    - xcodebuild starts the app with stdout and stderr on a terminal
      (/dev/ttys001) that only it drains, with OS_ACTIVITY_DT_MODE=YES,
      OS_ACTIVITY_MODE=info and NSUnbufferedIO. XCTest (Xcode 26.6)
      evaluates each query inside the app, on its main thread, and logs
      every accessibility lookup there: 52 MB over the tour, at 100 to
      540 KB/s.
    - xcodebuild fell behind the test runner (by up to 321 s, against
      under 1 s the rest of the run; silent 229 s after the tour ended).
      The app's console then filled, and its main thread moved about
      1 KB at a time (77 stalls of 0.3 to 7.7 s); one line waited 293 s
      and went through 20 ms after xcodebuild woke. The map kept
      turning: its render thread writes nothing. The terminate (sent
      05:28:29) and the next launch (05:29:41) reached xcodebuild only at
      05:33:49; the app was gone 4 s later. An earlier stall (05:23:08 to
      05:24:03) slowed the tour too, and it got through.
    - The same query took 14.3 s on 9 Oct's green run, 1.8 s on
      check/ward-polish and 0.18 s on check/perf-million: it depends on
      how fast xcodebuild drains the console. What kept xcodebuild busy is
      not in the logs (XCTest's spindump is not supported there).
    - Fix: every UI test launches the app with OS_ACTIVITY_MODE=disable
      and OS_ACTIVITY_DT_MODE=NO (XCUIApplication.keepTraceOffConsole(),
      ios/UITests/QuietConsole.swift, called before each launch), so
      XCTest's trace stays out of the console; the next largest console
      was GraphPreview's testStraightLines (25 MB). No step, check or
      picture changes. A still sky (-stillSky) would not have helped: the
      trace is the same with it, and the tour's pictures would change. A
      new UI test calls it too (the perf streams' testPerformanceMillion
      and GraphPerfProofUITests when they land). Merged into the
      integration build (design/merge-launch): its later launches,
      testBodyCloseUps, testIslandDeckFold and testIslandPushAndBack,
      call it as well.
    - The AX5 walk (AccessibilityUITests) failed the same day with "no
      example mcq/anki set" and "could not choose audio/ideas" (runs
      38689063193 and 38684974986): openSet() and choose() waited 8 s and
      5 s for the row before any swipe, but at AX5 the header fills the
      screen and the list makes a row only once it is scrolled to. Both
      now scroll to find it (scrollToFind: up to 6 swipes down the
      Sections sheet; up to 16 down the library, then 24 back up, as a
      section chosen again keeps the page below the sets), then wait for
      it to be pressable. Checks and messages unchanged.
    - [ ] Its check run: the two variables in the session log's launch
      environment, every test's console in the bundle small (the tour's
      52 MB down to a few KB), the suite green, and the AX5 walk past
      choose() and openSet().

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

### #33: the neumorphic app (on the session branch; personal next)

> also make the app be neumorphic in every way

> anotger session is already making the neumorphic part

> i give u permission (9 Oct, to move it into the main app)

Another session made it on aahp/personal with an automated review loop
(tasks T0018 to T0028, each checked on CI screenshots), then merged personal
into it: only swift-tests.yml clashed, and the merge keeps aahp's read-only
suites with separate publish jobs (skipped on aahp/ branches) and moves
personal's retry of a log push that loses a race into those jobs. The
session branch took that work up to T0032 (4ef98ff) and merged personal
in; personal moves up to it once a preview run is checked. The look: a retro
console press; soft raised controls that shade into a pressed state at 70%
depth; every button one height, as pills; no glow; ECG paper only in an
outer frame; faces the background colour with no outline. Restyle new
screens the same way. What follows is the brief as it stood.

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

### #33 follow-ups: the owner's asks of 9 Oct (in progress)

> some buttons look faded fix that

> i don't want fading in the app

> also the main page should have the grid from upwards till under the
> stethoscore word and under good morning preview

> the buttons are still faded and not visually distinct in borders also some
> ui elements overlap in the entire app. arrange the entire app ui.

The session makes UI changes itself; only heavy non-UI work goes to the
ChatGPT review loop. Work on the session branch, check the screens in an
ios-preview run (light and dark), send the owner marked full screens, then
move personal up.

1. No fading. Done in code; not yet seen in a preview run.
   - Disabled controls are a solid face at `.low`, not see-through.
   - `.opacity` transitions became `.identity`, `.slideIn(edge)` or
     `.growIn(scale, anchor:)` (AccessibilitySupport.swift; both are
     `.identity` under Reduce Motion). The study bar's folded button grows in
     from the bottom right, and its slab slides up.
   - The implicit fades (redone in full): views that come and go under an
     animation carry `.transition(.identity)` (the case ladder panel and the
     explain-back topic bar `.slideIn`), and words and symbols that change in
     place carry `.contentTransition(.identity)`; about 40 screens.
   - iOS 26's soft scroll edge is hidden on every page: WardMasthead puts
     `.scrollEdgeEffectHidden(true, for: .top)` and a solid base over the bar
     area (not `.hard`: it can't take a colour and flashes dark under a
     forced colour scheme).
   - Left alone on purpose: DrawRecallView's compare slider; decorative
     alphas (PhotonRing, StarLayers, AppBackdrop, ExamPlanView's fill tint,
     IdeaBoardView's line ink, MCQExamTools' 0.06 tint);
     `.contentTransition(.numericText())`; the audio volume fade; the case
     complaint's size change (CaseWardView, a type change).
   - Not touched, since other sessions own them: LaunchSplash.swift and
     Graph3DView.swift. Tell those sessions.
2. Clear button edges. Done in code. The owner's newest word overrides the
   brief's "faces the background colour with no outline".
   - A control (buttons, tappable chips, the dock, segmented controls, switch
     tracks, text fields, tappable row tiles) has a 1-pt edge in the ECG
     paper's blue (the owner: "make the line around the buttons match the
     grid color"): 0.85 in light, 0.65 in dark (about 3.3:1 on the base,
     tested in WardReliefTests; the grid's own strength would be about
     2:1), full under Increase Contrast.
   - Cards, slabs, status chips, pills and icon tiles have no edge, so what
     can be pressed stands apart; under Increase Contrast a card takes 0.35.
   - `control:` on wardRaised, wardInset, wardRelief, WardReliefFace and
     WardPressFace picks which. Faces stay matte, with no glow.
3. Overlaps. Done in code for what the last shots showed; check in the
   preview run, light and dark.
   - Where scrolled content is cut by a solid bar, a 1.5-pt line in the paper
     frame's edge ink marks the cut: always along the top of the bottom strip
     (wardBarBase), and at the top of what scrolls once it has scrolled
     (wardScrollTopEdge: wardForm, the folding study bar's host and the study
     screens' scroll views).
   - The open deck's fold chevron is a small pill with a control's edge.
   - Library (A3): Plan's 44-pt target no longer adds height, the header
     row's bottom inset is 0 and its top padding 4, and the strip keeps 8 pt
     above the dock with the New set row (24 without), so Start ward round
     ends above the strip.
   - Screens outside the preview set go into PreviewExtras first, so they
     can be seen. Keep the wording as it is, and keep New set in its thumb
     row.
4. The home page's grid band. Done in code: `WardPaper.lines(_:from:)` (with
   tests), WardPaperBand, HomeBandTrack and the masthead with its line once
   the band has scrolled under it. ECG paper from the top of the screen to
   just under the header, lined up with the frame; no grid under Increase
   Contrast. After CI, check x 12 to 16 pt (about 23 to 31 px) in the band
   rows; if the navigation stack clips there, draw those strips at SkyRoot.
5. T0034's side insets. Done in code; check its A1 to A9 in the same preview
   run. A9's exceptions include the library tiles at about 47 px.
6. First preview run (37913208989, on 114eeba; App build and Swift tests
   green): edges, the band and the library's strip are right, light and
   dark. Two fixes from it:
   - the bottom strip's cut line showed only at the screen's sides, since a
     flat slab from the strip's top covered it; wardBarBase now draws the
     line over the bar;
   - the OSCE station clock was a bare glyph and pill with no edge; it is a
     WardChipButtonStyle chip now (pressed in while it runs), and
     WardTimerPill takes `well: false` inside a button.
7. The owner, 9 Oct: "i don't want that island down that has new set button
   cuz it breaks page continuity". The library's New set and dock have no
   strip under them now; they float on the page's paper, and the list's
   end row is the dock's height plus 24 pt. The selection bar keeps its
   strip, and so do the study screens.
8. The owner, on the marked home screen: "i wanted the upper line removed
   and the lower red line replacing it with the roundedness of it and
   continuity with the rest of the grid line". On home the paper's opening
   now starts just under the header (WardPaperTop, set by HomeMasthead;
   `WardPaper.panel(width:height:top:)`, tested): no frame line at the
   top, no straight line under the band; the opening's top has the
   frame's corners and runs into the side lines, rises with the band as
   the list scrolls and is held at the bar's bottom. Pushed pages and
   search keep the frame's own opening.
9. The owner: keep the rows passing under New set and the dock, "but
   remove the glow around the deck and floating buttons". `.wardUnlit()`
   (WardSurfaces) draws Ward faces with no shade cast round them and no
   softened outline, keeping the face, its blue edge and the hollow when
   held or chosen; set on home's New set and dock (bar and rail), and
   reset inside the dock's sheet.
10. The owner: "turn the glow off in anything that might have text behind
    it at any point so visibility stays good". `.wardUnlit()` now also on
    every face that floats with no strip under it (a sweep of
    safeAreaInset and overlays): the folded study-bar button, the floating
    switcher, the generation card, the Saved to Ideas toasts, the note
    source chip, review Undo, the reader bar, the Ideas bar, board and map
    (set at IdeasView, since Graph3DView is another session's), New set's
    form dock, the selection bar over the map, the ward-round chip and
    panel, Narrate's fix toast, the import slip, Ward pocket's disclaimer
    and score, Study Lens's controls and answer bar, Draw from memory's
    compare panel and sign-in's doors. Bars on a solid strip keep their
    lights; sheets opened from the dock and the switcher reset it.
11. Done: CI green on b74dd06 (App build 37939012193, Swift tests
    37939008288, iOS preview 37939004451) and d16846d (App build
    37947903215, Swift tests 37944900082, iOS preview 37944896228); the
    shots were checked and sent to the owner (strip line, OSCE clock, blue
    edges, home's rounded opening, the unlit floating controls); personal
    is at d16846d.
12. Next: whatever the owner marks on the screens. Not yet seen in a
    preview shot: the unlit faces on screens outside the preview set (the
    map, the board, the reader, Study Lens, sign-in); add them to
    PreviewExtras if the owner asks to see them.

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
  - aahp/*: the design loop's (another session's). aahp/personal joined
    personal on 9 Oct (#33); aahp/red-pen is main plus one. Leave them
    alone;
  - main (8 ahead): the 23 Sep workflow_dispatch entries, which run on
    personal; on main by design. claude/new-session-eskvv8 holds only
    those and merges;
  - cursor/neuron-circuit-perf-d39a (6) and cursor/ideas-map-quality-40a2
    (4): Cursor's 3D, dropped (#18). design/codex-fixes (3): never merge;
  - design/prework-20261006 (22): Cursor's 6, 696192f02 and 15
    "pre-work:" commits from another agent's 6 to 7 Oct run, mostly a
    separate scaffold under prework/medical-assistant/. Its three real
    fixes are section 3, step 9.
  Chat-me's branches were swept on 9 Oct too (a read-only clone; push
  access to Chat-me was refused this session):
  - in personal: design/3c-migration, main, both claude/new-session-*
    branches, and medical-verifier-v0.1-commercial-safe (V), whose files
    §3c moved into api/, agents/, orchestration/ and governance/ (d504978);
  - prework/container-20261007 (2): the Dockerfile's entrypoint fix is in
    personal; its README fix is not (docs/architecture/verifier/README.md:26
    said `uvicorn app.main:app`, for `api.main:app`); fixed since (line 27
    now says `api.main:app`);
  - codex/build-native-ios-3d-anatomy-app (3, 26 to 28 Sep): Codex's
    separate AnatomyAtlas thorax app, not Stethoscore's; not ported;
  - verification-layer-adversarial-50 (A) and
    verification-layer-commercial-accuracy-v1 (C): never merged, and never
    runnable as they stand. Both split from V at ef94cb7 (27 Sep) and
    missed V's "Restore runtime foundation" commits of 28 Sep (6bdf4b6
    app/config.py, 60e17d1 app/models/claim.py, 89698f6
    app/retrieval/local.py, cd9c810 app/terminology/normalize.py), so their
    CI ran only test_evidence_model.py and test_reliability.py. What they
    hold that personal lacks is the 50-claim benchmark (both) and C's
    evidence model. Run against it (section 3, step 10):

    | Checker | False claims caught | True claims |
    |---|---|---|
    | personal's verifier | 6 of 10 (F02 to F05 SUPPORTED) | 15 of 40 supported |
    | C's evidence model, one passage each | 8 of 10 | 28 of 40 supported |
    | the Worker's gate before step 10 | 0 of 10 | 0 of 40 flagged |
    | the Worker's gate after step 10 | 6 of 10 | 0 of 40 flagged |

    Taken from them: step 10 here; step 11 is for Chat-me.
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
   allowed it; the permission system refused it twice, and the owner then
   attached the repository to this session themselves (9 Oct, about
   7:00 AM).

### The owner's answers of 14 Oct

> 1-wait for marks for now 2-use the api key from claude platform that has
> 100$ worth of api calls for max plan each month 3-what is that? 4-no apple
> de account 5-fix it and give it a human voice and natural tone depending on
> context 6- don't need those files no more

1. The screens: wait for the owner's marks (#33 follow-ups, item 12).
2. Claude as a checker family (#21, #26), on design/voice-claude:
   `claude:claude-opus-5-5` votes on the owner's checks only, within
   CLAUDE_MONTHLY_USD (90; ai.js askClaudeVoter, counted under
   "claude:owner" in ai_cost whatever PRO_PAYS says); students' checks never
   use it (votersFor). The deploy sets the ANTHROPIC_API_KEY secret. Live
   once the owner adds the repository secret ANTHROPIC_API_KEY and says to
   deploy; then run the verification bench (live mode) for the three-family
   numbers.
   - [x] 16 Oct, design/checks-cap: the owner split the key's 90 dollars into
     40 for these checks (CLAUDE_MONTHLY_USD "40", the proof ladder's share
     27) and 50 for Opus jobs. Review S-1016 hardened opus-job.yml: the run
     step ends in exec, so no process the model can read holds the key (R2);
     the push job takes the base from the work job's output, not the
     artifact (R3), checks each commit and its message, not the net diff
     (R4), and a budget with a second line no longer passes (R5).
   - [x] 16 Oct, design/claude-cap: a second way to Claude had no cap. The
     owner key's `use: 'claude:…'` pin on the chat route got an Anthropic
     source with no `paid` flag, and complete() holds money back only for
     Gemini and paid sources. chat() now refuses that pin with 400 before
     any spend or fetch (ai.test.mjs), so askClaudeVoter, under this cap,
     is the only way to Claude outside Pro's paid lane. Live with the next
     Worker deploy the owner has allowed.
   - [x] 16 Oct, design/paid-lane: Claude is in the paid lane only while PRO_PAYS is "on" (GEMINI_BILLING or a seen bill no longer open it for Claude), and the hold covers its thinking room; the Worker deploy waits for the owner's word.
   - [x] 16 Oct, design/paid-lane: the paid writer, Jev and the paid voice open only on PRO_PAYS (closing the wallet opened by GEMINI_BILLING or a seen bill), and an unpriced paid model is never asked; the Worker deploy waits for the owner's word. Review S-1016 (R1): a paid source joins only when GEMINI_PRICES itself names it (pricedIn); priceOf's Opus 5.5 default for an unnamed claude- model stays, for the Claude checks' hold. Once deployed, if a seen bill (gemini:billed) is set in D1, the owner's chats and Pro accounts that reached Claude and Novita on it get Gemini instead, as the rule wants.
   - [x] 22 Oct, T0116 (the owner: "Claude for my key only"): the owner key's writer (chat and jobs) gets Claude first even with PRO_PAYS "off", within OWNER_MONTHLY_USD (ownerClaudeWallet) and OWNER_DAILY_LIMIT, falling back to Gemini past the cap or without the key; every other caller unchanged (tests/owner-claude.test.mjs); the Worker deploy waits for the owner's word.
3. Explained in chat: a Worker deploy (the server going live) and the
   launch splash colour.
4. No Apple Developer account: no TestFlight or App Store for now; the
   Playgrounds zip stays the route.
   - 16 Oct, the owner: "when u finish give me a .ipa file". The IPA
     workflow (.github/workflows/ipa.yml, by hand: a source branch and
     Release or Debug) builds an unsigned .ipa, which the owner's
     sideloading app signs on install. The session sends it once this
     round's fixes are in personal, then deletes the run's artifact.
   - 16 Oct, the owner: "commit everything to main after this finishes and
     make out of it a new ipa of the full app". After this round, personal
     is merged into main and the .ipa is built from main (ipa.yml takes
     main as a source). Once on main, the three scheduled workflows run on
     their own: the proof ladder and diagnostics triage daily, the accuracy
     model weekly.
5. Finding 79, on design/voice-claude: no HFP (VoiceAccess: A2DP plus iOS
   26's high-quality Bluetooth recording), and VoiceTone: each line said in
   a tone for what it is (asking, listing, praise, correcting, explaining,
   alert, uneasy for a patient in pain or afraid), with verdicts in varied
   words. Needs a device test on AirPods once it reaches the iPad.
6. Groin_Hernia.pdf and owner-claim.txt are no longer needed; never ask
   for them.

### The owner's answers of 14 Oct, second round

> 1-wait more 2-deploy 3- i want the color to be seamless with the other ui
> home screen and if it isn't at least it becomes animated ( the color
> switching i mean) 5-give me an mp4 file i can hear now to see how it
> sounds like

- [x] Deployed (worker-deploy run 38552794025, design/voice-claude at
  89808a08): ANTHROPIC_API_KEY uploaded, Claude votes on the owner's checks.
  App build green on the same commit (the iOS 26 Bluetooth option compiles).
- [x] Launch splash on the home screen's base: LaunchBackground is the Ward
  base (0xE0E5EC / 0x2A2E35), LaunchLogo is drawn on a clear ground in a
  light and a dark version (tools/make_icon.py). Where the app's own light
  or dark differs from the phone's, LaunchSplash moves the colour across in
  0.25 s (a colour shift, not a fade). Check on the Mac build.
- [x] Voice sample: voice-sample.yml reads tools/voice_sample/lines.json in
  the natural cloud voice (live /tts) and the phone's voice with VoiceTone,
  as MP4s on the voice-samples branch.
- [x] Voice sample heard: the audio-only files (.m4a) play perfectly on the
  owner's phone; the MP4s played silent there, so the .m4a is the format to
  send (voice-sample.yml writes both).
- [x] Verification bench, live, with Claude (run 38554454303, 90 questions,
  180 checks): Claude answered 163 at 84.0% right, the best and steadiest
  witness (Gemini Flash Lite 156 at 69.2%, Nemotron 58 at 82.8%, gpt-oss 43
  at 74.4%). Every wrong key caught (90/90), no false Verified, but no right
  item Verified either (0/90) and 85% left as Check this.
- [ ] Next: why nothing reaches Verified. The two Workers AI checkers answer
  under a third of the checks, so three families rarely agree on one item;
  look at what Verified asks for (accuracy.js, accuracy-model.js) against
  this run's results.json before changing a threshold, and cite the brief
  any change follows.

### The owner's answers of 14 Oct, third round

> 1-2-3- continues 4- rebuild the space models from scratch from this image
> 5-ok 6-let the marks be the last task please 7- is there another way to
> have an opensource alt for jev? 8- also what did u do with the dna and
> islamic verification parts?why aren't u using them?and why didn't u
> implement them in the verification layer by how they function?

Google (Antigravity, Jules, Colab) is parked for now (owner, same day).
Order of work: 1 to 3, then 7 and 8 (server, checkable here), then 4 and 5,
with the marks on the screens last.

- [x] 1. Why nothing reaches Verified (the unchecked step above). Done on
  design/verify-mechanisms (merged 14 Oct): docs/verification/why-not-verified.md;
  88 of 90 right keys stop at the verbatim proof, which cannot read
  multi-sentence vignettes; only 36 of 90 got three checkers' answers.
  Nothing loosened. The proof route for vignettes is the owner's call.
- [ ] 2. #26, the 99.999% proof on the live Worker. Plan written
  (docs/verification/proof-plan.md): 99.999% needs 299,572 error-free
  Verified verdicts (about $5,400); staged 99.9% about $55, 99.99% about
  $540. Waits on a deploy, a target and its spend, and labels.
  The owner, 14 Oct (about 7 PM): "1-ok 2-99.999 3-make a deep search
  4-do both 5-do it 6-look for one": deploy ok (run from personal);
  target 99.999% within the existing caps (Claude $90/month, the rest
  free), climbed in stages; a deep search for the vignette proof route;
  a third free family and a wider Workers AI pool; labels from public
  gold sets (commercial licence, never from the checking models); an
  open NLI model as jev-standin's default. Running on
  design/verify-mechanisms; the search reports to this session.
  Vignette route (research: docs/verification/vignette-proof-research.md).
  The owner, 14 Oct (about 7:20 PM): "1-proven means the medical facts
  contained in the text is medically and clinically accurate by proven
  100% open source free for commercial use sources 2-choose the best
  option 3-ok 4-yes but add explanation to make users aware of the
  difference". So:
  - Proven: every medical fact in the item (findings-to-rule steps, each
    rule, each ruled-out option) backed word for word by a source whose
    licence allows commercial use; anything short stays at Check this.
  - Rule review (chosen for the owner): a rule enters only after two
    independent transcriptions agree exactly, its quote re-proves
    verbatim, and the source's worked examples pass as tests; it backs
    Verified only after the owner's one-tap sign-off (quote beside rule);
    until then it can back Checked only.
  - Sources: public-domain US federal guidelines and FDA labels first; a
    society guideline only with a licence recorded that allows commercial
    use; never StatPearls (non-commercial).
  - A Checked tier below Verified, with an in-app explanation of the
    difference.
  Built on design/vignette-proof and merged into personal (cdd74e81):
  checker, CDC rule set (3 admitted, 3 pending), Checked tier, benches B1 and
  B6. The owner turned VIGNETTE_ROUTE on, 14 Oct.
  - [x] Live: deployed on the owner's word ("u deploy the worker"), 15 Oct
    at about 8:12 am Cairo (Deploy the worker run 38685298818, from personal
    at bc611221, green). The same deploy took the keyless voters and the
    proof ladder's day-one fixes live; everything merged into personal up
    to bc611221 is live, including each step above marked "live only after
    a Worker deploy". The day's proof ladder run was started on personal
    right after it.
  Still to do:
  - [ ] Truly independent second transcription of each rule (both passes so
    far came from one session).
  - [ ] One-tap owner sign-off in the app plus an owner-only endpoint in D1.
    Optional and later (the owner, 16 Oct): a fully proven fact chain backs
    Checked without it; only Verified waits on it.
  - [ ] A real proposer, and the app sending proof packets (until then no
    item reaches Checked). This is T2 of the retrieval plan below.
  - [ ] Denial rules so two-step and contraindication can rule out options.
  - [ ] More sources (FDA labels, NIH; USPSTF stays out, the owner, 16 Oct);
    a weekly source-change check (tools/criteria/fetch-sources.mjs).
  - [ ] Benches B2 to B5.
- [ ] 3. Launch logo round 3 (Claude-Code T0036): the swirl back as one
  real, continuous tube.
- [ ] 4. #18, rebuild the Space node models from scratch from the owner's
  "Vignette - Space node styles" sheet (14 Oct; the owner's image, never
  committed: these repos are public). Six bodies, each shown at rest and
  dragged upwards, with its links:
  - Black hole (elevated): photon ring brighter on the approaching side
    (Doppler), lensed arcs, Keplerian streaks, an ISCO line; beams bend in,
    redden and flash on arrival. Dragged: the disc flares (it sheds no
    matter: its spark trail is off, rate 0).
  - Sun: granulation, limb darkening, corona, prominences and a flare;
    links run whiter and pulses leave as ejected plasma.
  - Rocky planet: day/night terminator from the light, city lights on the
    night side, sunlight, Fresnel air rim, a moon; pulses arrive as glints.
  - Gas giant: bands with jets, a storm, a ring with the planet's shadow on
    it and its own on the clouds; links light a bar on the ring.
  - Pulsar: tidy core, two sweeping beams, a wind nebula; its links ring in
    step with the beams.
  - Comet: nucleus, coma, ion and dust tails pointing away from the light;
    icy dust on its links. Dragged: the tails lengthen and shed dust.
  Links everywhere are warm, glowing beams. Today's code: Graph3DView.swift
  and GraphNodeStyles; rebuild the bodies, not the hierarchy (the
  "Decided design" above still holds). App-look work: batch into Mac runs.
  The owner (same day): "i want the models to be the same high quality" -
  the bodies must match the sheet's photoreal look, in real-time shaders
  (procedural granulation, lensing, atmosphere, ring shadows), judged on
  the iPad.
  - Status (21 Oct): the Space bodies merge landed on design/integration
    (2a62a68): Earth from NASA's public maps, a ray-traced black hole, and
    every rocky planet is now Earth (the desert and ice palettes are gone).
    The dragged black hole's spark trail is off (rate 0), so it no longer
    sheds matter as the sheet's wording above had it. Waiting for its Mac run.
- [ ] 4b. The Performance theme to 1,000,000 nodes with their links at 60
  frames a second or more (the owner, 14 Oct: "why didn't u make the
  performance nodes theme that can run 1million nodes and their connections
  at a 60 fps at least"). It exists (GraphPerf*, Metal) but was built to
  the 1 Oct target of 100,000 (targets §4), with demos of 100,000 and
  300,000; the only measurement is the simulator's (about 48 frames a
  second, iPad). Raise the target: GPU-only per-frame work (compute-shader
  layout, instanced points, compact 16-bit positions), links drawn in full
  only near the camera and as aggregated bundles or a density field
  farther out, a 1,000,000-node demo, and the frame readout's numbers from
  the owner's iPad as the proof.
- [ ] 4c. The Performance theme on very low-end phones and tablets,
  iOS and Android (the owner, 14 Oct). Every device keeps 60 frames a
  second by drawing what it can afford: the same 1,000,000-node map, with
  the level of detail (points drawn, links in full, glow) set from a
  measured frame budget; the full million in full detail on capable
  devices only. iOS 26 is the floor (ios/project.yml), so the oldest
  iPhones are the A13 ones.
- [ ] 4e. How 4b and 4c load the map: like Minecraft, only what is near
  you (the owner, 14 Oct: "it only loads what is near u (what shows on ur
  screen) and when u zoom out the texture quality falls down gradually and
  smoothly depending on how far u zoomed out"). The design:
  - Chunks: the map is cut into cubes in an octree; a chunk outside the
    screen (frustum) is neither drawn nor laid out. Chunks stream in and
    out with a per-frame budget, nearest first, so a fast pan never stalls
    a frame; a chunk not loaded yet shows its parent's summary.
  - Level of detail by on-screen size, not a few fixed steps: a node's
    detail (glow, shading, label, then a plain point) follows how many
    pixels it covers. Far away, a chunk becomes one summary point of its
    nodes (brightness = how many, colour = their mix), like distant
    terrain; links between far chunks become one bundle per chunk pair.
  - Smooth with no fading (the owner's rule): detail changes by
    continuous morphing (sizes, glow radius and bundle width
    interpolate with zoom; a summary point grows into its nodes, which
    move out from it), never by cross-fading opacity.
  - The frame budget from 4c sets how far each level reaches, so a slow
    phone switches to summaries sooner and a fast iPad later.
  - The frame rate is the screen's own, not 60 (the owner, 14 Oct: "i want
    it to run same as the monitor refresh rate"): 120 on ProMotion,
    90/120/144 on Android screens that have them (Surface.setFrameRate),
    60 elsewhere. Today GraphPerfMapView starts at 60 and the Smooth budget
    caps at 60 (GraphicsQuality.swift maxFPS); both go to the screen's
    maximum, and a slow device keeps the rate by cutting detail, never the
    rate. The budget is per frame at that rate (8.3 ms at 120 Hz). While
    nothing moves the screen may drop to its idle rate, as ProMotion does;
    any touch brings it back to full at once.
  - No visible loading delay, at almost no cost (the owner, 14 Oct):
    1. Every node's position and its chunk summaries stay in GPU memory
       on every device (a million nodes at 16 bytes is about 16 MB), so
       "loading" is only choosing detail, done on the GPU in the same
       frame: no disk, no waiting.
    2. The coarse level is always there: a chunk entering the screen
       already shows its summary point and refines from it (morphing),
       so nothing is ever empty or pops in.
    3. A guard band: chunks just outside the screen are prepared too,
       wider in the direction the camera is moving (its velocity),
       so a pan arrives at chunks already done.
    4. Recently seen chunks stay cached (least recently used goes first),
       so turning back is instant.
    5. Only the heavy extras (labels, glow textures) stream, on a
       background thread within a fixed slice of each frame.
  - [ ] Space (T0082, code done on design/integration fed0105, waiting
    for its Mac run). The stage is GraphSpaceDepthStage, and it reuses
    GraphPerfFrustum.of and GraphPerfLOD:
    - A body whose look (its disk, tail or beams) is all outside the
      frustum is neither drawn nor animated.
    - Each shader weighs its fine detail by the body's radius on screen,
      smoothstep from 8 to 32 points (rp_lod). This covers granulation,
      the lensed image and stars, clouds and city lights, ring shadows,
      and the moon and gas fbm octaves. It morphs and does not switch, and
      at full size it is bit-exact with the old look.
    - Under 1.5 points (3 when mostly faded) a body becomes an additive
      point in its colour, and it comes back at 2.25 (3.75). The gap is
      hysteresis.
- [ ] 4f. Depth fade in every map theme, like deep-sea footage and cell
  animation (the owner, 15 Oct, about 8:35 am: "u know how deep see videos
  or cell 3d high quality videos have fade for far objects ? that's how i
  want performance mode to be and also all other modes too to run
  smoother"). The spec is docs/design/depth-fade.md: near is crisp, far
  dissolves into the theme's own background along the view depth, the
  band follows the camera's focus, additive light fades to nothing, name
  pills never half-fade, what is fully faded is not drawn, detail drops
  only inside the band, and the Graphics setting sets how far it reaches.
  It is the owner's second exception to "no fading", and applies inside
  the 3D scene only.
  - [ ] Performance, on design/perf-million (with D1 to D5). The owner, 15
    Oct, before 4f: "for the performance mode u can make things load based
    on thier depth to u : for example the most surfaced is loaded and the
    deepest to u is faded until u turn and the y load and others fade etc."
    Linux tests: Tests/GraphPerfChunkTests.swift and GraphPerfBudgetTests.swift.
    - [x] D1 depth shells per cell: front, middle and back by the cell's fade
      f, with hysteresis; detail switches only where f is about 0.6 or
      more; a back cell opens at 3.2 times the split, a middle one at 1.7
      (GraphPerfChunkSettings; C17).
    - [x] D2 depth fog, 4f's one curve: f = clamp((z - start) / (end -
      start), 0, 1)^1.2 towards GraphPerfScene.background; the band follows
      the focus (1 to 1.4 times the camera's distance at High, 1.36 Smooth,
      1.32 Saver, and every level 1 to 1.46 inside the map, eased in from
      0.6 to 1.2 map radii); bundles and glows times 1 - f; past the end culled;
      Increase Contrast starts 15% later and stops at 0.6, culling nothing;
      the frame budget may pull the end in to 0.7 of the band, never the
      rate (GraphPerfDepth.swift, the node shader; C9, B6).
    - [x] D3 loading follows the turn: leaves wanted by depth and size, a
      body budget a frame, 0.2 s detail ramps, and opening or closing
      bounded to a quarter second end to end, so a half turn in a second
      swaps front and back detail within 15 frames of settling and no
      on-screen body's brightness moves more than a sixth of its range in a
      frame, at every level, from the edge (0.12 to 0.14), the whole map
      (0.04 to 0.05) and inside (0.15) (C10, C17, C18). A flick of a full
      turn a second steps 0.22 to 0.26, which the fog itself sets (a body
      at the screen's edge crosses the band that fast); a fade that lags
      the camera was tried and made it worse, so C18 reports it only.
    - [x] D4 a faded body is picked like any other, one past the band's end
      is not; choosing a note brings its leaf and its neighbours' to full
      detail, prepared first (C16, C19). With it, the selection: links
      hidden by default, the chosen note's own growing out to each
      neighbour while the rest steps back (GraphPerfFocus.swift).
    - [ ] D5 the proof on the Macs (design/perf-proof's tour): fps median 58
      or more and 1% low 50 or more over a 10 s turn and zoom, the GPU
      memory's peak, before and after at each Graphics level, near and far
      stills, the slow-turn recording, and the independent review.
      - 15 Oct, preview/perf-proof-1 (run 38724121848): every proof test
        timed out at "the million was not built within 15 minutes: 0 notes
        · 0 links, 0 fps", so the app's main thread was blocked, the known
        console stall. fly() now calls app.keepTraceOffConsole() (taken
        unchanged from design/ui-suite-fix, 0dbb1f74) before launch.
        Rerun as preview/perf-proof-2.
      - 23 Oct, T0150 (run 39932576764, design/integration): the same
        "0 notes · 0 links, 0 fps" for 15 minutes x3, with the main thread
        answering and the map empty with no label. It began with 47c13782:
        testPerformanceMillion passed on 7f5bc74d (run 38686619509: 73 s
        iPhone, 114 s iPad) and timed out on 47c13782 (run 38721234572,
        no tour). On Linux the same build is fine (the million in 28 s at
        -Onone, every step non-nil) and the renderer's planning settles in
        about 20 frames, so the stop is Metal-side: the million renderer
        not made (its shaders or a pipeline), its buffers not made, or
        frames stopping before they draw. Each of those returned silently
        (NSLog only, hidden by keepTraceOffConsole). Now each says
        "cannot draw: <reason>" on the map and first in the readout, and
        the proof's failure message quotes it (GraphPerfDrawFailure,
        GraphPerfDrawWatch, GraphPerfMillionMap.Outcome; P16, C20). Next
        Mac run: read the reason, then fix that step.
    - Merged (T0108, 22 Oct): design/perf-proof, with design/perf-million
      under it, and then design/perf-fade-band (D2's wider bands, 15 Oct)
      went into design/merge-graph, so the integration build has the
      million map; D5's proof is taken on that build.
  - [ ] Space, on design/space-bodies (after its current step). Code done
    (T0082, on design/integration fed0105), waiting for its Mac run:
    - The band (SpaceDepth.band, GraphSpaceDepth.swift) runs from 1.15x
      to 2.6x the focus's view depth on High, and from 1.1x to 2.0x on
      Smooth, with k 1.25. With Increase Contrast it starts at 1.25x and
      stops at 0.7.
    - Every Space shader gets rpFade. Bodies mix toward the sky's
      near-black in linear light, and glows, coronas, beams, links and the
      disk are multiplied by 1 - f.
    - A body past the end of the band is not drawn, animated or pickable.
      It dissolves its last 15% by node opacity.
    - Names show in the crisp zone only. The chosen body is always kept.
    - Tests: the spacedepth suite (D1 to D12).
    - Left for the Mac:
      - SceneKit compiles the shaders and the probes pass;
      - the link fade (_surface.position) works;
      - the look up close is unchanged and nothing pops;
      - the frame numbers below.
    - Merged with design/neurons-depth on design/merge-graph (T0108, 22
      Oct): this stage is Space's only depth fade. neurons-depth's own
      Space fade (each body's gate at 1 - f, its band on the framing's
      reach, the far plane at the band's end, the glow holders shrinking,
      the node-opacity probe) gave way to it. Its tilt (45°), meter and
      -graphDepthOff stay: -graphDepthOff leaves the stage out, and the
      meter counts what the stage draws and fades. U6 is kept by turning
      each body's own frame (GraphStyleKit.frame) rather than wrapping it
      in a tiltFrame node, which turned the beams, tails and photon ring
      the animator poses in the world's frame. VoiceOver finds no body
      past the band's end (testDepthGlide).
    - Open: in the tilted default view this band hardly fades the far
      edge, which lies at 1.24 to 1.32 times the focus's depth in graphdepth
      D14's framings: f 0.03 to 0.07 on High, 0.10 to 0.18 on Smooth, and
      nothing culled, where depth-fade.md's C2 rule 1 asks 0.7 and a cull.
      The next Space step decides.
  - [ ] Neurons, on design/neurons-depth (a new stream). Step 1 (15 Oct):
    the band's numbers and maths for both SceneKit themes, Foundation only
    (GraphDepthFade.swift, suite graphdepth), and SceneKit's fog on the
    Neurons scene toward black, its band on what the camera orbits each
    frame (GraphDepthKeeper.swift; Graph3DView hands over the camera
    controller in one line), the fluid's dome kept inside the fog's start.
    Step 2 (15 Oct): SceneKit's fog replaced by a fragment shader of our
    own on every material of the map (added by walking the built scene,
    no theme's shader files touched; pills and the backdrop left alone):
    depth along the view, the focus's depth found per pixel from the
    point looked at, so zooming and turning write nothing; light fades to
    nothing, see-through things go see-through, solid ones toward the
    background. Nothing past the end is drawn or picked (the far plane and
    a gate per body); pills show only in the crisp zone or when chosen;
    the Neurons' halo and dendrites shrink away once mostly faded and grow
    back (a quarter second, hysteresis); the shader is checked on the
    device first and, if it fails, the map is drawn as before and the
    meter says "fallback". A link chip's glide to a body past the end
    (Graph3DView's ease(to:glide:), GraphDepthGlide) brings it to the
    middle at the focus's depth instead of doing nothing. Suite graphdepth
    266 checks. Proof hooks: -graphDepthOff (before), -graphDepthMeter
    (SceneKit's statistics and the frame-time meter); preview tests
    testDepthBeforeAfter, testDepthTurnNeurons, testDepthTurnSpace,
    testDepthMeasure and testDepthGlide. The first Mac run read "no meter"
    for all 16 takes: GraphDepth.follow ran in makeUIView, before the view
    had a window, so the meter label went onto the SCNView, whose
    accessibilityElements (the bodies) hide it; it now waits for the window
    (GraphDepth.place). Next: the Mac's pictures,
    recordings and numbers, then tuning the band.
    The independent review of the first pictures (15 Oct): nothing fades.
    Both maps are flat sheets facing the camera (Neurons' rows at z = ±0.3
    of the biggest radius, Space's galaxy homes at z = 0, the default
    framing turning only about z), so everything sits at about the focus's
    depth, under every band's start: "after" is the same picture as
    "before" (whole-picture light 0.96 to 1.06 of it), nothing is culled,
    and Space's mean frame was 16 to 34 ms longer with the shader on (the
    simulator, one take each: indicative only). testDepthMeasure turned the
    map twice, back to face-on; it now turns once, so its pictures and
    numbers show the fade where a turn tilts the sheet. Proposed values,
    not applied: Neurons High end 1.6, Smooth 1.45; Space High end 1.9,
    Smooth 1.6; k 1.0 (GraphDepthFade.swift:70-75), which breaks D4e
    (end ≥ 2), a check whose premise the flat maps disprove. The owner
    decides how far things should fade on a flat map: tilt the default
    framing so the sheet recedes, fade by distance from the focus, or give
    the maps real depth. Nothing goes to the owner as done before that.
    The meter's numbers (neurons-depth-3, 67fe38c2, one turn, simulator):
    nothing is culled in any take (Neurons 4/4 whole, 9/9 near; Space
    35/35), and the shader costs time in Space: the iPhone's mean frame
    66.6 ms on against 44.9 off (High, whole), 61.7 against 40.9 (High,
    near), 60.9 against 45.3 and 50.4 against 39.5 (Smooth); the iPad's
    up to 80 against 40. Neurons is mixed (iPhone High near 37.5 against
    30.6; Smooth whole 21.4 against 23.6). As built, the fade neither
    shows on the flat maps nor makes anything smoother; it waits on the
    owner's choice above.
    Step 3 (16 Oct, T0057/T0062): depth completed with rulings and user requirements U1–U9:
    - U1: Graph3DView: worldUp (0,0,1) normal to the map, turntable horizontal drag, vertical drag limits keeping tilt within 10–75° (SceneKit elevation 15° to 80°).
    - θ = 0 keeps SceneKit's camera defaults.
    - U2: Bands follow reach R = (deepest/F) - 1 in [0.15, 1.0], crisp reach c = a·R (whole) or R + 0.02 (fly-in), span F·(1+c) to F·(1+c+(b-a)·R).
    - U3: Bounded real depth: cluster z = A·u(id) with FNV-1a 64, A from {0.35, 0.25, 0.15, 0} × H passing legibility rule (overlap/cover ≤ 15%).
    - U4: Space fades per body (gate opacity 1 - f in steps ≥ 1/255, hidden at f ≥ 1); Neurons stays per pixel.
    - U5: No tint: see-through dissolution, depthTint and solid mode removed, opaque materials switched to blended with no depth write.
    - U6: Space bodies sit in tiltFrame turned by Rx(θ) always (on and off) to preserve disk lean seen face-on.
    - U7: Faster by construction: Space culls far strip (High b=0.85, Smooth b=0.75; Neurons High b=1.05, Smooth b=0.90); glow holders shrink at f ≥ 0.62 via depthExtra node untouched by GraphSim.
    - U8: Probe checks node opacity on additive and solid planes at 0.5 reading 0.5 ± 0.1, read as linear light (the snapshot is sRGB); falls back to on/glowpx if additive check fails, and on/glowpx shades Space's added-light materials per pixel while see-through bodies stay on gate opacity.
    - U9: Double tap on empty map re-frames the default view via recentre(), which also ends a fly-in.
    Independent review (16 Oct, R-T0062): REPAIR, five items, all in: the glow fallback's two halves (R1, R2), the double tap during a fly-in (R3), and wording (R4, R5). Open for the owner: Space gets no real depth (A = 0 on all three Space sample maps), because the legibility rule takes each galaxy's whole reach as a sphere while the 45° pitch foreshortens the sheet; the choice is foreshortened discs, a smaller cluster radius, or spreading the galaxies.
    What the Mac proof must show: 70-* pose-matched pairs with -stillSky -graphFreeze -graphDepthMeter; 74-depth-numbers with ablation takes; 75-body-frames analyzed by tools/depth_crops.py; 72-*/73-* spin and tilt reads; 71-* lively stills without freeze.
    At the merge (T0108, 22 Oct) U4, U6's tiltFrame, U7's Space half and
    U8 gave way to Space's own stage (above); the Neurons are unchanged.
  - [ ] Frame time and draw calls before and after for each theme, at
    each Graphics level, and the independent review, before the owner
    sees it.
- [ ] 4d. A full Android app of Stethoscore (the owner chose it over a web
  map, 14 Oct): a large, separate project, planned after M3 and 4b. The
  owner has no Android device, so it is tested on CI emulators; its
  performance map shares 4b and 4c's design (Vulkan, GLES 3 as the low-end
  floor).
  Progress 14 Oct (android/kotlin 8f7b8ab4, CI green 38593087418): the 3D
  Ideas map on GLES 3 with 4e's chunks, LOD, morphing and refresh-rate
  pacing, a 1M-node demo, FSRS-5 with daily limits, and PDF deck export.
  Left: APKG import/export (needs zstd), Vulkan, widgets; out of scope so
  far: cloud generation, sign-in and sync, recording, billing. Small: on
  the 4-idea map the BNP label overlaps Pulmonary oedema, and the 1M demo
  header reads 0 ideas.
  The Android app now lives in android/ on design/integration (from 7e3a249).
  - UX Wave 1 on Android (W1-android, the owner 22 Oct: "use the same things
    from ios"; findings in the Android consistency sweep, section 7):
    - [x] Filled buttons as iOS .bigPrimary: QuizBigButton, CardsPrimaryButton
      and CaseButton's primary draw through WardButtonBox (raised capsule,
      words in the section's ink, never a fill; BigButtonPathsTest).
    - [x] Cases answers on WardOptionRow, as iOS (the owner 15 Oct: wrong
      fades, right takes the mode's colour); CaseOptionRow and its green and
      red are gone (CaseAnswerRowsTest).
    - [x] Home's grid as iOS HomeBand: from the window's top to 10 under the
      header (HomeFit.belowHeader), following it as the list scrolls, the
      plain base below; no fading (WardGroundBackground gridBottom;
      HomeBandTest).
    - [x] Home's dock as iOS's: the panel raised high on its rim, the chosen
      tab in a low hollow with the chosen edge, a held tab sinking into one,
      Chart Ink at rest and the section's ink chosen, outline glyphs at rest,
      no ripple (WardDockTest checks the source).
    - [x] The dock's row as iOS T0112: the five categories on the panel and
      Ideas on its own 56 pill, the bar at most 560 wide; the tabs take
      WardDock.tabWidths (water-filled, or every name shrunk alike to half at
      the least), so the full row stands at the default text size (WardDock,
      WardDockTest).
    - [x] One tone on Android (the owner 22 Oct, "there shouldn't be 2
      tones"; as iOS 90674e8): WardPalette surface and raised are the
      background pair (#E9EDF2 / #171C24); wells, relief, edges and rings
      unchanged. WardPaletteTest checks equality; OwnerAccepted.kt: 167
      entries take their new measured value, 19 that now pass are removed;
      no tolerance changed.
    - [x] The screenshots run's crash (39646961250, "Asking for intrinsic
      measurements of SubcomposeLayout layouts is not supported"): home's
      tile row (IntrinsicSize.Min) asked the Vitals tile's ThatFits, a
      SubcomposeLayout; ThatFits is now a plain Layout answering intrinsics
      (HomeTilesMeasureTest runs the textbook flow under Robolectric).
  - UX motion on Android (WM-android, T0124; the motion rows of the Android
    consistency sweep; iOS is the reference, as T0121 is on iOS):
    - [x] The motion named once (WardMotion in WardTokens.kt): platform.md's
      200 to 320 ms, iOS's ease-out and ease-in-out, springs critically
      damped so nothing passes its mark; and Remove animations (the animator
      duration scale at 0, as iOS's Reduce Motion) read by the theme for
      every surface (wardReduceMotion; WardTokensTest.theMotion).
    - [x] The literals become tokens: the switch's knob 0.2; a ring, groove,
      bar or score filling 0.3 (WardRing was 600 ms, the vitals ring and the
      results' score 900); the ward round's chip travelling 0.3 (its 0.85
      spring passed the corner). Kept as iOS keeps them: the spoken word's
      0.1, the working trace's 1.2 loop (now on iOS's ease-in-out) and the
      score ring's slow spring (iOS Q8) (WardMotionTest).
    - [x] Remove animations on every surface that moves: the press's shade
      and sink (a held control no longer sinks), the card's answer opening,
      the jumps and scrolls, the working trace standing whole
      (WardReduceMotionTest).
    - [x] The dock's hollow travels with the choice as iOS's does
      (StudyCategory.swift:748, 0.3 s): one hollow under the five tabs,
      simply there with animations off and back from Ideas; the dock's look
      is unchanged (WardDock.hollow, WardDockTest).
  - UX Wave 2 on Android (W2-android, T0122, 22 Oct: the components, iOS the
    reference one to one; rows in the Android consistency sweep; checked by
    WardKitPortTest):
    - [x] The quiz stand-ins are gone: quizFace, QuizChip, QuizTag, QuizCard
      and QuizSmallCaps give way to wardPressFace, WardChipButton, WardChip,
      WardCardFace and WardSmallCapsText (Questions, its summary, the exam
      tools, the chart quiz, the pocket).
    - [x] The Cases kit is the Ward kit's: WardCardFace, the avatar and clock
      pressed in (wardInset), WardChip, WardButtonBox, WardSegmented.
    - [x] wardUnlit as iOS (LocalWardUnlit): what floats over the page (the
      library's New set row over the dock, the Ideas board's bar) keeps its
      edges and drops its glow.
    - [x] WardStates as iOS (ui/ward/WardStates.kt: empty state, banner,
      groove, progress bar, filter chip); the library's and the mock's copies
      are gone. Of the 7 own empty states 4 moved (Cards, reader, library,
      mock); 3 stay, as iOS draws them its own way (the library's empty
      shelf, stats, insights). Of the 4 banners 3 moved; the narration's
      transcribing card stays (iOS: a content card with the ECG loader).
    - [x] One StudyActionBar on WardDeckSlab (ui/ward/WardDeck.kt) for the
      study screens and editors (21 decks in 17 files): open, on a strip in
      the page's wash whose top line curves into the paper frame's ring
      (WardEdgeStore); the fold band and round button where iOS folds it
      (Questions, Cards, the mock's sitting and results, OSCE, the reader,
      narration). The mock's, the reader's, the editors' and Cards' own bars
      are gone; the library's (LibraryStudyBar, on Stats and the shelves) is
      left, as the sweep's row does not name it.
    - [x] Waits draw the ECG trace (EcgLoader), never a spinner: the
      attending hint's wait and the Ideas map's build.
    - [x] No ripple: the theme gives WardPressIndication as LocalIndication,
      so a plain clickable sinks to WardPress.sinkScale and shades 0.04, as
      iOS PressableRowStyle, with the Ward focus ring from a keyboard
      (WardPressIndicationTest).
    - [ ] Left: the fold's motion and the press under Reduce Motion (T0124);
      Material's own buttons, menus and dialogs keep their ripple until
      Waves 3-4 and the owner's answer on native menus and dialogs.
  - UX Waves 3-4 on Android (T0123: chrome and polish, no motion; the
    Android consistency sweep's Waves 3-4 and the owner's answers of 22 Oct):
    - [x] The starting window's bars stand on ward_ground (light and night)
      instead of the off-palette #E0E5EC; from the first frame
      enableEdgeToEdge clears them, as before.
    - [x] Material's onPrimary is WardToken.onPrimary (white) at night as
      by day, so words on fills stay white (it was the night base); nothing
      else in the scheme changes (OwnerPaletteTest).
    - [x] The question screen's picture (StudyScreens' CardImage) covers an
      occlusion card's labels in OcclusionCovers' colours, as the card face,
      not a Care Blue literal; no screen passes it a card yet, so nothing
      drawn changes (OwnerPaletteTest).
    - [x] Wells take the page colour (the owner 22 Oct, "wells and sheets
      one tone"): WardControlStates.wellFill (WardToken.background) fills
      every Ward well - fields and search boxes, chips, pills, the timer,
      grooves, a switch's empty track, a chosen or held segment - and
      wardWellFill() hands it to screens (T0122 uses it); WardToken.well
      stays in the palette. Cards' progress groove, the Why note, a held
      rating button and the lab panel's units row were flat wells and are
      now inset ones. NarrateAudioBar's native slider keeps the palette's
      well (it draws no inset shadows). OwnerAccepted.kt: 44 values move
      (chip wells and chosen segments measure on the page colour), each
      marked "owner 22 Oct, wells and sheets one tone".
    - [x] T0123b: WardBanner, WardGroove and CaseInk.well take wellFill (inset, page colour); the narrate slider and Material's well slots keep WardToken.well (no inset shadow).
    - [x] Sheets, menus and dialogs are one tone (the owner 22 Oct; they stay
      Material's own, Android Q4): their containers were already the page
      colour by token (T0113), but Material's 1 dp tonal elevation laid
      black over every ModalBottomSheet (surfaceTint is clear), about 5%
      darker; the theme turns tonal elevation off (WardPaletteTest).
    - [x] Touch targets are 48 dp on Android (the owner 22 Oct; iOS keeps
      44): WardControlSize.target is 48 and the theme hands it to Material
      (LocalMinimumInteractiveComponentSize). The Ward button, chip, circle,
      switch, segmented control and text field wear
      minimumInteractiveComponentSize, so the touch area grows and the face
      keeps iOS's size (the circle stays 44, drawn at buttonSmall); the 44
      literals that were targets take the token, IconButtons lose their 44
      cap, and the three under 44 (the tag field's add, the lab units, OSCE's
      More options) reach 48; a dock tab is never under the target
      (WardTokensTest and WardDockTest pin 48). Drawn sizes that grow: a
      tag chip (50 to 54), the tag field (46 to 68: its add sits inside the
      well; iOS draws it 64) and the count field's well round its circles
      (44 to 48).
    - [x] One top bar for the sweep's seven: StudyTitleBar (ui/mock/MockKit.kt),
      iOS's inline title with Ward toolbar buttons. Back is a Ward circle;
      the title, in the headline face, stays in the bar's middle and takes
      the room the wider end leaves it. ScreenHeader (no inset inside its
      own column, its subtitle under it), ReaderNavBar, EditorTopBar and the
      quiz's and review's bars are it, ReaderBackButton is the circle, and
      More on the quiz and review bars is a circle (the review's empty More
      is a disabled one: it was faded to 40%). The exam card's header is a
      card's, as iOS ExamDashboardCard's, and stays.
    - [x] Settings on the Ward controls, as iOS SupportCenter's wardForm and
      ReviewSettingsSection: Night shift is a WardToggle row (the whole row
      toggles it), the scheduler a WardSegmented, the daily limits' minus
      and plus Ward circles (the minus a disabled circle at no limit), and
      New set's study modes Ward chip buttons, the chosen one pressed in.
    - [x] Home's search is a WardTextField, iOS's searchField: a Ward well
      with the magnifier in Biro Grey (WardTextField takes a leading glyph)
      and the body face, no longer Material's outlined field at 90% surface
      with a 30 dp radius; Settings beside it is a Ward circle, not an
      IconButton in a drawn ring. The gear stays filled (Android Q3).
    - [x] Type on WardType's faces: the sp literals (fontSize with 22 sp
      lines under them) are now faces with their own leading, at the same
      sizes, in the quiz, results, cards, settings, home, exam tools and
      Cases screens. One title role, one face: the empty and error titles
      (22, 23 and 20 bold) are WardType.title, settings' card titles
      WardType.title and their row labels the headline (18 was off the
      scale). As iOS: the card's front is the title (leading 25, not 26),
      the hint's words and the lab panel's values the body (16 and 14 mono
      were off), the lab values with even figures; the chart's words keep
      iOS's 3 points between lines and the Why note its 2. The small caps
      (cards' badge, Why / how, the due list, the vitals and lab headings)
      are WardSmallCaps (0.8 tracking, none at the accessibility sizes),
      not 1 or 1.2. Left: the display numerals at iOS's own scaled sizes
      (the plan's 40 and 36, the score ring's 38, the calculator's 40 to
      iOS's 44, the results ring's 30), the dock's autosizing names, the
      skip glyph's 7, and W2's stand-ins and empty state.
    - [x] The page gutter is WardSpace.gutter (16, not 20) and the gap
      between a page's sections WardSpace.section (24, not 20 or 22), as
      iOS's wardForm: home, settings, AI models, the quiz's empty page, the
      clinical fallback, Ideas' note page and its legend and name sheets, the
      shelf, the library sheets, By subject, New set, Guess first, the ward round's
      panel (a card's padding is the gutter too), the exam picker, the ward
      pocket, the credits and the plan, kit and symptom pages. Left as they
      are: the 20s over form rows (ReaderFormSection's header and footer,
      the exam picker's note, the vitals line, Ideas' and the syllabus'
      headings), which sit over the rows' words (the tile's 8 and its 12),
      as iOS's form headers do, and the other off-scale gaps, many of them
      copies of iOS's own (iOS's sweep leaves those to a screenshot review).
    - [x] The canon's own off-scale values: WardMonitorCard's default gap is
      WardSpace.m (18 before; its one caller already passed m, as iOS's
      VitalsParts), and wardField's 10 above and below stay, with a comment:
      iOS's wardField has the same 10.
    - [x] Radii from WardRadius where iOS names one: the Cards progress
      header (bar), its content card (card), the rating buttons (button),
      the lab and vitals panels (field), the undo chip (bar, iOS's
      PopTileStyle), and the board's cards and the occlusion picture (card;
      they were 14). Capsules where iOS draws Capsule(): the Cards companion
      button (it was 16), the reader's pager, the board's hint and the
      import slip. Left: radii iOS writes out itself (the book's 8, 10 and
      12, the mock's picture's 12, the narrate flow's 10, the stem
      highlight's 8), the two discs drawn at half their size (34 and 28),
      the native dialog's 28 (Android Q4), the section switcher's geometry,
      the Cases screens' 12s (the field radius already), and W2's stand-ins
      (the answer row, QuizCard, the calculator keys, the hint panel, the
      empty state's disc).
    - [x] Nothing faded by alpha where iOS draws it solid (the owner 9 Oct:
      disabled is solid Biro Grey, wardDisabledInk): a disabled rung on the
      Cases ladder (ink at 38% before), and the Cases screens' Use and Add
      when disabled (Material faded them to 38%); the board's link lines
      are Biro Grey, as iOS's, not 55% of it, and Bedtime's rule line Biro
      Grey, as iOS's, not ink at 85%. Home's search at 90% and the review's
      More at 40% went with the bars above. Kept, since iOS draws them so
      and no colour changes: the board card's 14% wash in its folder's tone,
      the stem highlighter's beam at 30% and its 6% grey, the analytics
      bars at 70%; W2's stand-ins keep theirs (QuizTag's and CaseKit's 12%).
- [x] 5. Merge design/voice-claude into personal (the owner said ok):
  personal fast-forwarded to a6aa7be4 (14 Oct, about 6:05 PM), which holds
  design/voice-claude and this plan.
- Running in parallel from personal a6aa7be4 (the owner, 14 Oct: "run what
  is left of the plan in parallel"), one writer per branch:
  design/verify-mechanisms (1, 8, 7, then 2's proof plan; no deploy),
  design/space-bodies (4), design/perf-million (4b, 4c, 4e on iOS),
  android/kotlin (4d: the same map on Android, then parity gaps). The logo
  stays on Claude-Code (T0037); the marks (6) wait for the owner.
- [x] 3b. Launch logo chosen (the owner, 14 Oct, after rounds 4 and 5 on
  Claude-Code, T0037 and T0038): "use the white in light mode and the grey
  in dark mode": design/launch-logo/candidates-5/02-white-flat.png for
  light and 06-slate-flat-dark.png for dark, both on the flat Ward base.
  The animated opening (design/launch-anim) uses this pair, with a real
  lub-dub (licence recorded, or synthesised) and an ECG drawn under the
  stethoscope in step with it, also when muted.
  - [ ] T0079 (21 Oct): the opening stands on home's own ground (Questions' wash and grid, WardGround), drawn live by WardGroundView with no neutral base until the hand-off, and LaunchPaper redrawn from the same numbers by tools/make_launch_ground.py; waits for the Launch recording.
- [ ] 9. Ward design pass (the owner, 14 Oct: "the iOS design is a bit
  cramped - lacks color difference for each mode and animations when
  switching colors - also when we removed the fade some buttons became too
  flat and lost their neumorphic shaping so u can add fade to the buttons
  but only a very small rim around the buttons enough to make them have
  neumorphism but doesn't affect elements behind them"). On
  design/ward-polish:
  - More room: spacing, padding and line height on a consistent scale.
  - Light and dark each get their own character, not one palette inverted.
  - The owner, 14 Oct (about 7:55 PM): "i also meant by modes not just
    light and dark i meant colors for the grid and the button rims in other
    modes like osce mcq cards ideas etc". Each section (Questions, Cards,
    Cases, OSCE, Audio, Textbook, Ideas) gets its own hue for the grid
    lines and button rims (light and dark versions), from its existing
    icon colour; switching sections shifts the colour, never fades.
  - First round (shots ward-r3): the mode switch was patchy (regions
    changed at different moments, grey films on search, dock and tab bar)
    and card text showed under the dock; the owner: "very bad". Fixing.
  - Switching light/dark animates the colours (a colour shift, no opacity).
  - The first exception to "no fading": a small soft rim on buttons only (a
    light highlight top-left and a shade bottom-right, a few points wide)
    that gives them their neumorphic shape and never darkens or blurs what
    lies behind or beside them. The second, since 15 Oct: the depth fade
    inside the 3D map (4f, docs/design/depth-fade.md).
  - Every control's states (design/ward-states): rest, held, disabled and
    chosen, the same in every section and mode. WardControlStates holds
    them as colour roles, Foundation only, and the wardstates suite checks
    all seven sections, light and dark (words 4.5:1 on their face; disabled
    told apart from enabled, and chosen from unchosen, by more than relief;
    no blue outside Questions). Disabled is Biro Grey, solid; chosen keeps
    a 2 pt accent edge, disabled too; held sinks. WardControls, PopTileStyle
    and its Playgrounds stand-in draw them; WardStatesGallery
    (`-uiPreviewScreen states -uiPreviewSection <section>`) shows every
    control in each state, shot by the Ward preview's states part. Done in
    code (7028b485, 35590f7b, then the gallery's switches without their
    words). The fade gate is fixed (ward-polish merged in, 15 Oct). Left:
    the gallery's pictures from the next Ward preview, then an independent
    review of code and pictures together.
  - The fade rule, loosened (the owner, 15 Oct, 6:25 PM Cairo: "loosen the
    no fade rule a bit"). Still banned: anything that looks washed out at
    rest (faded buttons, text or cards), and a visible fade lasting longer
    than 0.2 s used as a transition. Allowed, besides the buttons' rim and
    the Neurons depth fade (4f): iOS's own brief transitions (the status
    bar, sheet and alert dimming, the keyboard, menus), any change that
    settles within 0.2 s, and crossfades under Reduce Motion. The Ward
    preview's gate (tools/ward_frames_check.py) follows it: the status bar
    is measured and reported but never fails, and the content fails only
    when a faded stretch stays on screen longer than 0.2 s (a shorter one
    is reported as a brief dip, allowed).
  - [x] The Ward preview no longer hangs on a recording: ward-r15's phone
    job waited 80 minutes for simctl's recordVideo to stop and timed out.
    tools/ward_shots.sh stop_rec gives it 20 s after the stop signal, then
    kills it and logs a FAULT line, so a stuck recorder costs 20 s, not
    the run.
  - [x] Recordings start only once the app's screen is up: on a busy Mac,
    ward-states-2's mode-switch-quiz.mp4 (preview 38779814424) was 7 s of
    the system launch screen, so its "no switch" check failed. wait_up()
    in tools/ward_shots.sh asks the same launch-screen check as shoot()
    before record() and system_switch() start recording, every 3 s for
    up to 10 checks, then logs a FAULT line and records anyway.
  - [x] Home's fit faults (the publish gate, ward-r14 on): the Vitals streak
    is one line at its own width beside the ring (a Label drew it narrower than
    ViewThatFits judged); at large text a bed comes off the round when the cut
    would slice Start ward round; the preview waits for a slow first frame
    instead of relaunching it. Check A: HomeFitTests; confirm on a Mac run.
  - Independent review of design/ward-states (15 Oct) rejected it on seven
    blocking defects; fixing them smallest first (the 16 nits are out of
    scope):
    - [x] B6: Start's frame is written to LibraryView only at rest
      (HomeBandTrack.isAtRest), so a scroll step no longer re-runs the
      library's body (WardHome.swift onStartFrame).
    - [x] B1: no sliver under 12 pt of any row or part shows over home's
      cut. Rows and parts report their tops at rest (`wardPart`,
      WardPartBook: Practise tiles, set rows, headings, More rows, the card,
      each bed and its chip) and the cut moves up to any top it would
      sliver (HomeFit.settledCut, LibraryView.pageCutHeight); the probe
      checks them all against where the page really ends (HomeFit.faults
      parts/pageEnd) and faults if nothing was measured. HomeFitTests: the
      iPad at the default size (tiles 8 pt over the cut) and AX1 (the Due
      chip 4 pt over it).
    - [x] B3: a disabled switch's words go Biro Grey like every other
      disabled control (WardToggleFace); the states model's switch now has
      words (WardControlLook.words, wordsFace) and WardStatesTests checks
      them in every state, section and mode.
    - [x] B5: no blue outside Questions: the New chip (CaseKit, the bed chip)
      takes the section's accent (`.blue` tone); WardTone.info and
      Color.wardInfo are gone. tests/ward/accent-blue.test.mjs now asserts
      it (it asserted the opposite).
    - [x] B4: every ink a chip or pill wears clears 4.5:1 on its well, light
      and dark, with and without Increase Contrast (the inner shade
      included, WardRelief.insetGround): Resus ECG red, Discharge Green
      and Caution Amber are a shade darker in the light scheme (0xB6263A,
      0x116D50, 0x8C5200; the green also moved a little towards teal so the
      Textbook accent stays apart from it). WardPaletteTests holds the
      semantic inks, Biro Grey, Chart Ink, Theatre Blue and every section's
      accent on the well; the false promises in WardControls and WardHome
      now point at it.
    - [x] B7: the fade gate takes each mode's end state from frames at rest
      (on screen 0.5 s or more; the highest spread among them), not the
      last frame of a run on one side of brightness 120, which can be
      caught mid-crossfade. tests/ward/frames-check.test.mjs has three
      0.5 s crossfades that must fail (the old gate called them clean, end
      contrast 6.8) and the same switches in one step that must pass. Run on
      a real recording with fades (before2/mode-switch.mp4) the old gate said
      light 3.8 and passed; this one says light 31.3 and fails four fades.
    - [x] B2: the dock, the rail, the Ideas pill, the AX list button and
      FloatingSwitcher follow the states: chosen keeps the pressed-in hollow
      and adds the 2 pt accent edge (wardChosenEdge on the moving hollow),
      unchosen enabled items are in Chart Ink (Biro Grey is disabled's),
      held sinks with the Ward press (WardItemButtonStyle,
      WardPanelButtonStyle, not `.buttonStyle(.plain)`), the collapse
      chevron is in Chart Ink. Rings, shaping and Ideas' magenta stay.
      tests/ward/dock-states.test.mjs reads the sources for it; the pictures
      come from the next Ward preview.
      - [ ] T0079 (21 Oct): the chosen tab's ring is concentric with the dock (radius 24 less the 4 or 5 inset, continuous) and its name keeps clear of the ring's corners (WardDock, WardStatesTests); waits for the Ward preview.
      - [ ] T0103 (21 Oct): the study deck (quiz's How sure? dock and every .studyBar) is one tone: WardDeckSlab fills with the strip's wash, not the surface, so no inner panel shows; edge and relief kept; waits for shots/dock-one-tone.
    - [x] B3: AX1 home-fit sliver (run 38820624486): SwiftUI snapped the page
      frame to the 3x grid, up, so the end (682.67) fell below the chip's top
      (682.3). HomeFit.shown now settles the cut onto the pixel grid at or
      above itself (scale from displayScale); gate unchanged; HomeFitTests.
    - Second review (N1-N3):
      - [x] N1: set rows, the examples row and the More rows had lost their
        Ward tile because `.wardPart` wrapped the row after its list-row
        traits, so the List no longer read them. `wardPart` now comes before
        the traits (LibraryRows, LibraryCategory); no other List row had it
        the wrong way round. tests/ward/part-traits.test.mjs fails if a row
        trait sits before a `.wardPart` in a chain (it flags the old order).
      - [x] N3: a part's top is booked floored onto the pixel grid
        (wardBookedTop), not rounded to half a point: 682.78 at 3x books
        682.667, never 683. HomeFitTests.
      - [x] N2: a part whose view goes away leaves the book (onDisappear),
        and the book tells `changed` what it already holds the moment the
        page installs it, so an early publish is kept. The book's logic is
        WardPartLedger (Foundation-only, Shared/Ward/WardPartLedger.swift), tested for drop, clear and
        shared tops in HomeFitTests. The Mac run (ward-states-7) confirmed
        the drop only: nothing in it returned to a page, and the late-install
        replay cannot be told apart from a later publish.
    - Third review (REJECT on N4):
      - [x] N4: a part dropped when its view went away was never booked
        again (set() books only at rest, and onGeometryChange reports only
        changes), so after a page was pushed over home and popped the iPad's
        cut showed 8 pt of the Practise tiles again. The ledger now keeps
        each live part's latest sighting, booked at the next rest; a part
        hands its last frame back on onAppear (kept in a plain object, never
        view state); HomeBandTrack rebooks when the list comes to rest. A
        part that disappears at rest wholly below the cut is hidden by it,
        not gone: it keeps its entry and sighting, so the cut cannot fall
        back, show it and hide it again (a loop at rest). HomeFitTests.
      - [x] N5: a drop while the list moves no longer re-runs the page; the
        next rest publishes.
      - [x] The gate: on the library preview, -uiPreviewPushBack pushes the
        first set and comes back before the fit report, which flags any part
        lost on the way (tools/ward_shots.sh passes it on home's shots).
      - [x] Nit 1: the Practise tiles book their low lift's rim (3 pt).
        Nit 2: part-traits.test.mjs knows the other row traits and a `}.`
        line; server-tests.yml runs on the folders it reads.
      - [x] Confirmed on the next Ward preview, then the fourth review.
        Ward preview 8 (dfb9a921): every fit report says "fits" and "push
        and back: done" on every device and size but AX5 (phone and SE),
        where the push and back gave up at 2.5 s with no set to open; an
        AX5 launch takes about half a minute. The trip now waits up to 30
        s for its parts and a set, the report waits for the trip and the
        rest after its pop, and a trip that never ended says "not
        finished" apart from "no set to open". Preview only; the gate is
        unchanged. Ward preview 9 (53ca8795): all 21 reports say "fits"
        and "push and back: done". The fourth independent review (16 Oct)
        accepted it: N4 and N5 fixed, the gate would have caught N4, no
        new blocking defect.
      - [ ] The fourth review's nits, each with a Ward preview: the loop
        guard compares raw doubles (WardPartLedger.swift:104-105), so on a
        3x screen about 1 in 9 holders is not kept and could loop at rest
        if the cut hides its cell (slack as in onGrid, drop the maxY half,
        a 3x test); clear() leaves the cut nil until pageCut changes; kept
        entries go stale (prune those above the cut at each rebook); a
        self-topped holder ("More ways to practise") flashes once at the
        end of a scroll back; and the gate never proves a real push (FAULT
        unless the book lost parts between push and pop), its lost check
        goes by name, and a slow launch can shoot during the trip.
        16 Oct, design/ward-nits: all five fixed (1e-6 pt slack on the
        guard, entries above the cut pruned at each rebook, a hidden holder
        kept through the drop while moving, the cut kept on clear, and the
        report FAULTs unless home lost parts during the trip; the lost
        check already counted per name, unchanged, and no test pins it;
        ward_shots.sh waits for the trip before the shot). Four new
        homefit tests fail on 0d5a5472 and pass. Independent review (16
        Oct): the code passes (homefit 101 of 101; exactly the four new
        checks fail on 0d5a5472); its only repairs were this note's
        wording. Open for the next review: a row that slides below the cut
        while scrolling is now kept, and in a scratch simulation one later
        held the page's end 3 pt high; with no set to open, ward_shots.sh
        finishes but takes no library pictures. Ward preview 10 (2972ebdf):
        no screen errors, but the new FAULT came up at random (xxl light
        but not xxl dark; SE light and dark; AX5 SE), because the trip
        looked at the book once, 1.5 s after the push, and a busy Mac had
        not always covered home by then. The trip now watches the book up
        to 10 s for a part to leave and pops no sooner than 1.5 s in; the
        FAULT still stands if none leaves. Waits for its Ward preview.
        The check now counts drops (removed and kept below the cut) and
        prints them, waiting for the next Ward preview.
        shots/ward-nits-3: only AX5 SE light FAULTed (removed 0, kept 3,
        every face below the cut). Review U1 (16 Oct) ruled the rule wrong
        there, and its repair N-R1 is in: home counts as covered when a part
        leaves the book, or, when every face booked before the push lies at
        or below home's cut, when one goes away and is kept by it
        (HomeFit.pushCovered, six homefit checks). The integration preview
        (38938158628) FAULTed on AX1, iPad and Pro Max: every part kept, by
        a cut near the page's top (277.75 and 285.83, at rest 1020 and
        768), so home's cut collapses during the push and N-R1 still flags
        it. The report now logs each cut during the trip with the bar, the
        page's frame and the tops behind it, to find what collapses it.
        The preview also re-encodes a recording over 95 MB before
        publishing (shots/ward-island-1 lost every shot to a 134 MB one).
- [ ] 6. Last: the owner's marks on the screens.
- [x] 7. (Done 14 Oct: tools/jev-standin and jev-standin.yml; oath check 30 of
  30, 0 false alarms; NLI model is the TRIAGE_NLI_MODEL repo variable.) An open-source stand-in for Jev (§22a kept only Layer 7, the
  fail-closed oath check, and Layer 6's card/MCQ triage). Plan: Layer 7 from
  our own rules and server/proof.js; Layer 6 as an open cross-encoder or NLI
  model scoring each option, run in batch on GitHub Actions, with its
  thresholds tuned on our own labelled items (§22a: tune on a few hundred
  own labels).
- [x] 8. (Done 14 Oct: server/provenance.js and oath.js; dabt caught 38 of 38
  changed statements; a 3,000-case fuzz found no new false Verified.) The DNA (§16a) and Islamic (§17) briefs as working mechanisms, not
  only cited principles. In use today: independent witnesses (one family is
  one witness), the blind second pass (kinetic proofreading), a sensor per
  error type, retired practice (abrogation), holding back when unsure
  (tawaqquf), explained objections. Missing: each claim's chain (isnad:
  claim, passage, source, retrieval, checker), a source registry (rijal:
  type, date, edition, retraction, funding), shadh and tafarrud flags,
  common-link independence for sources, the conflict-of-interest rule, and
  dabt (numbers, units, population and negation copied faithfully).
- [x] 10. Palette direction 3 (the owner, 16 Oct; task T0055, on
  design/palette-3 from design/ward-states 53ca8795): the owner's neutrals,
  seven section colours, an indigo primary and faded wrong answers, keeping
  the design, every promise and the 0.076 separation gate. An independent
  judge's rulings:
  - Separation: the gate holds accents (words, glyphs, the right-answer
    mark), not fills, and stays whole. The fills are exactly the owner's;
    each section has its own word lightness inside the bands (0.36 to 0.55
    by day, 0.66 to 0.94 by night); OSCE turns -3 degrees (387D4D / 3D8253
    to 3D7C49 / 42814F, about 0.006 in OKLab); no meaning colour moves.
    Least gaps 0.078 by day (textbook/osce, textbook/success) and 0.084 by
    night (questions/danger).
  - tools/ward_accents.py: each row is (name, hue, light L, dark L, fill
    light, fill dark), Questions included; a pinned fill is checked (white
    4.6:1, hue within 2 degrees), never searched; FLOOR (0.07, 0.10), since
    no teal at hue 186 with 0.085 chroma reads 4.6:1 on the paler tiers.
  - Outside any section the look is Cards (WardSection.outside), not
    Questions, or every screen without a section would turn red. The
    default paper ink (5866E5 / A5B6FE) and the control edges follow it, so
    Theatre Blue leaves the app. Questions joins the table at hue 20: its
    ECG grid turns red at the paper's own strengths; the trace keeps the
    ECG red.
  - Two test pins moved: the 12-degree night-hue test is retired (the
    indigo is 8.7 degrees apart in the two modes), and the dark base floor
    goes from 0.015 to 0.010 (#171C24 is 0.0114).
  - Marking follows the owner's rule of 15 Oct ("the wrong should be faded
    and what is right gets the color of the mode used",
    docs/design/identity/routes.md on design/identity): in the quiz's and
    the Lens's option rows, right is in the section's accent, wrong is the
    faded row, struck through, with a small cross, in colours and never
    opacity. The Lens True/False verdict keeps its meaning colours; the
    other success and danger uses (about 30 files) are left as they are.
  - The night relief reads weaker on the darker ground (shade on the base
    1.12, was 1.29; lift-1 highlight against shade 1.28, floor 1.25; rim
    1.55, floor 1.3), and every test passes; the strengths are unchanged.
    If it looks flat in the pictures, that is for the owner.
  - Values, light / dark: background E9EDF2 / 171C24, surface EEF1F5 /
    242B35, raised F1F4F8 / 2E353F, well DDE2E8 / 090E15, hairline CFD7E2 /
    04070B, ink 232C39 / F1F4F8, inkSecondary 536171 / B8C2D0, primary
    5260BC / 5A68C5, primaryInk 4046C2 / A5B6FE, faded DDE2E8 / 353E4A,
    fadedInk 52606F / BEC8D3; AccentColor 5260BC / A5B6FE,
    LaunchBackground E9EDF2 / 171C24. Sections (hue; fill; accent; ink):
    questions 20, C03946 / CB3E4B, 970525 / D98888, C82D40 / F0777A; cards
    274, 5260BC / 5A68C5, 4046C2 / A5B6FE, 5866E5 / A5B6FE; textbook 186,
    227D75 / 258279, 065650 / 0FC8BA, 0E7C74 / 0FC8BA; cases 51, AC5A21 /
    B05C23, 783907 / F48C49, AC5102 / F48C49; osce 149, 3D7C49 / 42814F,
    024B1D / 5DC474, 01712E / 5DC474; audio 307, 8150AD / 8B57B8, 772FAB /
    CD99FE, 9853D0 / CD99FE; ideas 346, B23E86 / BA438E, 9E1071 / E97EBB,
    C74195 / E97EBB.
  - Left outside this task's files: comments naming Theatre Blue in
    WardControls, WardStates and WardSurfaces; tools/make_icon.py, whose
    notes name the old bases (the launch logo is not re-made here);
    LibraryView's `?? .questions` section fallback. The session's Mac run
    takes the pictures.
  - Done (16 Oct): `tools/ward_accents.py --check` up to date (least gaps
    0.078 by day, 0.084 by night); the ward suites and homefit, 7 of 7;
    tests/ward/*.test.mjs, all four; tools/preflight.sh, PREFLIGHT OK.
    design/ward-states had moved to afcbc0b1 (this file only, its step 5
    items), so this step sits after step 8 and the merge stays trivial.
  - Independent review (16 Oct): ACCEPT, no repairs. Ward preview
    38892166844: every device and the states sheets clean, no errors. Its
    pictures could not show the review's item 2 (Questions, C picked and B
    right: B pressed in the accent, C low on the faded face, and by night
    #353E4A reading as stepped back, not lifted), so the Ward preview now
    also shoots quiz-checked. If C reads as lifted, the owner decides.
    Follow-ups: 46 comment lines in 29 files still name Theatre Blue; the
    launch logo still draws "score" in Theatre Blue; the Lens sheet has no
    preview case.
  - Comments (21 Oct, T0070): the comments that named Theatre Blue now
    name the colour each control draws: the section's accent
    (Color.wardPrimaryInk, WardTone.blue, the primary button), a mode's own
    accent where the code draws one (StudySetKind.tint: ModeTile, New
    set's mode tiles, the reading drill's key words in Questions' accent).
    Comments only. Kept, as still true: WardPalette's note that there is no
    Theatre Blue any more and WardLookTests' "when they were Theatre Blue"
    (the past); Brand.mark, which is Theatre Blue (the launch logo is its
    own decision); WardPaletteTests' check label (test code).
  - [ ] The Lens sheet now has a preview screen, "lens" (PreviewExtras,
    LensSheetPreview): a sample nephrology MCQ, answered (A right, the
    rest faded), with its explanation, put straight into the model
    (LensModel.setPreviewAnswer), drawn at full height. The Ward preview
    shoots it on the phone, Pro Max and iPad, light and dark; waiting for
    that run.
  - [ ] Press depth (16 Oct, the owner on the checked quiz, light and dark:
    "the color here doesn't match the mode color", raised and pressed
    buttons read alike, and a wrong pick reads like a right one). Each
    waits for its Ward preview (quiz, quiz-checked, library, new, settings,
    sheet; phone, SE, Pro Max, iPad; light and dark):
    1. The right answer in the mode's colour: Color.ward fixed the section
       into a colour when a view's body ran, so the quiz rows, drawn while
       the app was still outside any section, kept Cards' indigo by day.
       Every Ward colour now reads the look as it is drawn (WardLookNow),
       the root hands the look at rest down as a trait so each is resolved
       again when a shift ends, and the paper reads it too.
    2. Raised and pressed apart: the rim stands at 2, 2.5, 3, 3 points with
       a crisp blur of 2 (reach 4 to 5, under the gap of 8) and a darker
       shade (0.9 by day, 0.85 at night); pressed in sinks the whole of its
       lift's lights (depth 1, was 0.7) with the inner shade a quarter
       stronger; the shade's glide takes 0.21 and 0.26 s (was 0.15 and
       0.18), so it starts in at the speed it had.
    3. A wrong pick against the right answer: it lies flat (no rim) on the
       faded face, ringed in the faded ink (3.70:1 or more on the face, the
       cards and the base); at night the face is a plain grey #40444B,
       1.46:1 lighter than the cards (was blue-grey #353E4A, 1.32:1), the
       faded ink 5.77:1 on it; by day as it was. The right answer keeps its
       section's ring, pressed in at the new depth.
    Done (16 Oct): the ward suites 4 of 4 and tools/preflight.sh,
    PREFLIGHT OK; on 33b60aea the new tests fail (wardrelief 3,269 of
    12,135 checks, wardpalette 2 of 206, wardlook does not build).
  - [ ] Mode tile rings (16 Oct, the owner on New set: "make each button ring
    has the color of its corresponding mode"). Each kind's tile on New set
    rings in its own mode's section ink (Questions red, Cards indigo,
    Textbook teal, Cases orange, OSCE green, Narrate purple), light and dark;
    waits for its Ward preview (new; phone, SE, Pro Max, iPad; light and dark).
  - [ ] Each mode's colour plain to see (21 Oct, the owner: "colors don't match
    the mode" and "the mode colors don't change"; task T0074): one mode, one
    colour on home and category pages with row icons taking the section on
    show; New set takes the chosen kind's section with mode tiles keeping
    their own glyph and accent name; ground matte base takes a linear-light
    wash of the section on show (0.06 day, 0.10 night) shifting with the
    look's glide, while the launch opening keeps the neutral base until
    hand-off; waits for its Ward preview.
  - Deck island continuity and rounded corners (the owner, 16 Oct; task
    T0065): any place with a line across the opening (quiz bottom deck,
    header line) turns down into the outer line along a circular arc
    tangent to both with the panel's corner radius, matching the iPhone
    corner radius, with deck slab top corners rounded to meet the arc.
    The Foundation geometry (`WardEdgeCorner`, `WardEdgeJoin`, `WardEdge`)
    is in and tested (`wardrelief` suite); its drawing is the next task.
    - T0066 draws every deck and scroll edge into the frame, with clipped
      island strips, base-filled header pockets and rounded slab tops.
      An iPad's frame, moved home opening and islands take its 18 pt
      corners, including in multitasking windows. Awaiting the Ward preview.
    - Review U1 (16 Oct): REPAIR I-R1, in: the fold button's icon grows
      with the text up to the largest size its 44 by 28 pill holds (xxxLarge),
      on every deck, and shows in the Large Content Viewer past that; the
      fixed 17 pt on a joined deck was an accessibility regression. The
      integration preview (38938158628) shows quiz, quiz-folded and
      quiz-scrolled joined into the frame on the phone and the iPad, with no
      doubled ink where the arcs meet the frame's line. Open, the owner's
      call: a joined deck's slab draws flat, its soft relief clipped to the
      slab (WardSurfaces.swift `face.clipShape(shape)`); keeping it means a
      relief mask past the slab by its reach, cut only by the island.
    - T0073: recordings of the island's motions (deck folding, push and back)
      added to GraphPreviewUITests.swift; wait for the Design preview with
      only=testIsland.
    - T0076 (21 Oct): testIslandPushAndBack's swipe from the screen's edge
      did not go back because the page stands 16 pt in from the window
      (SkyRoot), so a touch at the edge landed on the paper, outside the
      navigation stack and its edge pan (an app bug; the quiz's More menu in
      the recording was the test's next step, run after the failure). Now
      the paper's leading gutter hands its touches to the page (WardEdgeReach)
      and the test is unchanged. And, the owner: "only on the upper side":
      the scroll edge's line under a page's header and its turn-down into
      the frame are gone on every page (wardScrollTopEdge removed); the
      deck's line and join at the bottom and the frame's ring are unchanged.
      Waits for the Design preview with only=testIsland.

- [x] 11. The owner's 10-colour palette (21 Oct; task T0104, design/palette-genz): every accent remapped onto it by role and hue, neutrals kept, words on fills near-black where white fails; mapping in docs/design/palette-2026-10-21.md.
- [x] 12. The owner's hexes exactly, the earlier backgrounds (22 Oct; task T0107, design/vivid). The owner: the colours were not the ones sent, the backgrounds should not have changed, "don't improvise". Every section and meaning colour is now the owner's hex in every role and both modes (no shades; NoteTone, DeckPalette, AccentColor, the Anki red pen too), words on fills white again, and each section's wash pinned to its value before T0104 (WardSection.washes, pinned in WardLookTests), the launch pictures redrawn on it. The checks the exact colours fail stay failing (listed in the T0107 result); tools/ward_accents.py exits 1 on these fills, so the WardLook table is written by hand. Note in docs/design/palette-2026-10-21.md. The washes and the failing checks are superseded by 12a and 12b.
- [x] Follow-up to 12 (T0107 repair, 22 Oct): tools/make_launch_ground.py reads home's ground from WardLook.swift, so its --table is WardGround.home's, and the LaunchPaper pictures are redrawn with it; the core/core1 Playgrounds stand-in's occlusion "?" is white, as the app's (OcclusionFilter.swift).
- [x] 12a. The backgrounds as they were before the section wash (22 Oct; T0107 repair, design/vivid): the wash added on 21 Oct (73f09a7, the base mixed toward the section's fill) was never asked for, and the owner's phone build of 16 Oct has plain grey grounds, so every section's wash, home's ground and the launch ground are the plain base again, #E9EDF2 by day and #171C24 at night, as at ca4ddb4 (WardSection.wash returns it; pinned in WardLookTests). Grid lines, rims, rings and every colour are unchanged.
- [x] 12b. The owner's decision in the checks (22 Oct, about 3:44 AM Cairo, shown that the exact colours fail the readability checks: "STOP IMPROVISING DONT CHANGE THE COLORS I GAVE U"). Every check and threshold is kept; a case that falls short only because of the owner's colours, or the plain ground, passes only as itself on the owner's list at its measured value (within 0.01): ios/RedPen/Tests/OwnerAccepted.json for WardLookTests, WardPaletteTests, WardReliefTests, WardStatesTests and DeckTests, tests/ward/owner-accepted.json for accent-blue.test.mjs and tools/ward_accents.py --check. A case not listed, a moved value or a listed case no longer short fails. tests/ward/owner-palette.test.mjs pins the ten hexes in the page's roles.
- [ ] Follow-up to 12a and 12b (docs/, outside T0107's paths): docs/design/palette-2026-10-21.md's 22 Oct note still says each section's wash is pinned to its value before T0104 and that the failing checks stay failing; it should say the ground is the plain base and those checks pass on the owner's list.
- [x] 12c. One tone on iPhone (22 Oct; task T0113-ios). The owner, 22 Oct, circling home's ward-round card block: "there shouldn't be 2 tones"; 21 Oct, of the quiz dock: "one color not two color toned". Cards (.surface) and sheets, bars and panels (.raised) are the page colour, #E9EDF2 by day and #171C24 at night (WardPalette.table), on every screen; depth comes only from the relief, edges and rings, all unchanged. WardPaletteTests pins surface == raised == background in both modes. Wells (.well) are unchanged pending the owner's word (asked 22 Oct). The owner's lists hold the re-measured values: in OwnerAccepted.json 154 values moved and 19 cases removed because they now pass at night; in tests/ward/owner-accepted.json 8 moved, 5 removed, and 7 ward_accents ink cases renamed from "on the surface" to "on the background", the lowest ground now.
- [x] Follow-up to 12c: the owner's word on wells (fields, tracks, a chosen segment), which still sat a shade below the page. The owner, 22 Oct: yes, wells take the page colour too (T0120, below).
- 12d. Motion on iPhone (22 Oct; task T0121, UX Waves 3-4, the motion rows of the iOS consistency sweep). Canon: platform.md, 200 to 320 ms with an ease-out, no bounce, nothing fades, nothing loops but the trace; Motion.gentle and .slideIn / .growIn (AccessibilitySupport.swift).
  - [x] Reduce Motion everywhere: the 86 withAnimation, .animation and animated bindings in 39 files that ignored it go through Motion.gentle, so nothing moves under Reduce Motion. A bare withAnimation keeps the system's default curve.
  - [x] Bare .snappy (0.5 s) as .snappy(duration: 0.25): 57 sites in 23 files.
  - [x] Durations into 200 to 320 ms, each curve kept: the pop-out's settle 0.5 s, WardRing 0.6 s, the Vitals ring 0.9 s, the quiz summary's score 0.9 s and Narrate's scroll 0.45 s to 0.3 s; the Ideas map's panels 0.35 s to 0.3 s; the library's select tick 0.15 s to 0.2 s.
  - [x] OSCE review's Start over without the bounce: .easeOut(duration: 0.3) for the 0.35 s spring with a 0.15 bounce (the same spring as .snappy, so not that).
  - [x] Lens's looping "Answering…" bars as EcgLoader: LensShimmer (four bars swept by a light, 1.3 s forever) is gone; the card holds the trace and "Answering…", read out as "Answering".
  - Kept: FinishHero's aurora, ScoreRing's spring and RiseIn's staggered spring (owner question, iOS Q8); NarrateWordFlow's 0.1 s word highlight, which keeps up with the voice (its comment says so); the WardPress press curves; the scenes (sky, map). No .transition(.opacity) anywhere.
  - [ ] Mac run: the app build (Motion.gentle is main-actor only, so every site was checked to be in a view or a main-actor class), then a look at the quiz, the library and New set at the shorter durations.
- UX Waves 3-4 on iPhone, chrome and polish without motion (22 Oct; task T0120, from the 22 Oct iOS consistency sweep). The owner: "start all waves at once". Motion is T0121's and components T0119's; no colour, tone or wash changes but the owner's answer on wells.
  - [x] Stats and Vitals on wardForm(): the solid bar area (the 9 Oct no-fading rule), 56 pt rows, section spacing and the Ward controls. Stats keeps its inline title; Vitals keeps the app's one large title until the owner's word.
  - [x] Waits shown on their own take the working trace (EcgLoader) in place of the system spinner: the library loading under the splash, a second window before the library is read, and the 3D map while it is built. The small spinners inside buttons stay.
  - [x] The empty 3D map takes WardEmptyState, as every other empty page does, in place of the system's ContentUnavailableView.
  - [x] Wells in the one tone (the owner, 22 Oct, asked whether wells and sheets take the page colour: yes). WardPalette's .well is the base, #E9EDF2 by day and #171C24 at night, so every field (wardField, popField), track (WardGroove, a switch's off track), chip well and chosen segment shows as a well by its inset shade alone; WardPaletteTests pins well == background in place of the old soft step. The cases on a well are re-measured on the owner's lists ("owner 22 Oct, wells and sheets one tone"): in OwnerAccepted.json 59 values moved and 1 case is gone because it now passes; in tests/ward/owner-accepted.json 20 moved and 1 gone.
  - [x] Sheets in the one tone: each sheet the app draws already stands on the page colour (wardForm, wardScreen, modeScreen or presentationBackground) with its panels on .raised, the page colour since 12c, and its wells follow the line above. The system's own share sheet, document scanner, file and photo pickers, menus (30), context menus (17), confirmation dialogs (18), alerts (15) and search fields (8) take no background and stay as they are; the three .roundedBorder fields in Cases keep the system field until the owner picks the field API (iOS Q6).
  - [x] The paywall's Restore, Terms and Privacy are 44 points to press (minimumHitTarget), the words still footnote-sized.
  - [x] Mono numbers at the two Ward steps take WardType.obs (body) and .obsLarge (title2): the count field, the review, diagnostics and AI-model counts, the case score and its parts, the mock exam's question grid, the book's contents numbers and the calculator's keys, each keeping its weight. The other mono sizes wait on iOS Q4; the Lens option letter is a letter, not a number.
  - [x] Wells and pictures on WardRadius.field (12) in place of 6, 8 and 10: the book's table header and figures, a note's code block, the highlighter's phrases, the line being read aloud (its word marks concentric at 12 less their 5 point inset), the Lens outline of a found question, the readiness levers' pointer shape and the drawing attempts' thumbnails. The Lens "Answering" bars are the motion wave's; the chart marks' 3 and 4 stay, as a ring sector or a thin bar is no well.
  - [x] Text columns on readableColumn() (700, and the shared breathing room when the window has it) in place of 760, 700 and 640: the case list, ward, decision and debrief, a picture from a photo, explain-back, the duel and its summary and comparison, guess first, the bedtime review and the "How to reach it" example. The Lists that cap at 760 or 820 (the category shelves and pages, the library's category page) keep their caps, as the column's top room would stop a list short of its bar; bars, toasts, panels and empty states keep theirs, and the recording terms keep the 560 column their bar is cut to.
  - [x] The card face's kind label ("QUESTION", "FILL IN THE GAP") takes WardSmallCaps in its same primary ink, in place of its own copy of the small caps, so its letters close up at the accessibility sizes as every other small-caps label's do.
  - [x] One Ideas title pill (IdeasTitlePill, beside IdeasChrome): the screen's bar and the design preview's bar draw the same "Ideas" plate in place of two copies.
  - [ ] Follow-up (docs/, outside T0120's paths): docs/design/palette-2026-10-21.md still runs the light tiers from #DDE2E8 and names the night well #090E15; it should say the well is the page colour since 22 Oct. Android's WardPalette.kt well is T0123's.
  - [ ] Mac run: the app build and Ward previews of the pages above (phone, SE, Pro Max, iPad; light and dark).
  - Waiting on the owner: Vitals' large title; mono sizes other than body and title2; icon-square sizes; the onboarding, paywall and sign-in gutters (24). The sample pictures' colours stay (no colour changes).
- The iOS tour in stills (22 Oct; task T0126b, from the T0126a screen inventory of 128 rows). Previews only; the shipped app is unchanged.
  - [x] 130 `-uiPreviewScreen` names in tour order in tools/tour_screens.txt (name, inventory row, plain name): 107 new tour cases in PreviewExtras (fenced out of the Playgrounds packages), plus the screens that already had one. Cases use only the seeded store and the example seeders; a mock sitting and a case run are cleared first, and settings a still needs (exam, Ideas mode) are registered, never written.
  - [x] Hooks read PreviewLaunch.screen and only run under -uiPreviewScreen: First run's page, the app-lock shield, New set's Make step, the book's contents, the case's differential, the AI provider editor and the writing card.
  - [x] ios-preview's limit from 45 to 116 minutes: about 12 minutes of build and boot plus up to 37 s a screen for light and dark, with a quarter on top. The whole list is one dispatch, about 77 minutes typical.
  - Not stilled: the splash (owner's art), study tips (off in previews), the paywall (App Store products), twins and the spoken station (model output), Study Lens's live view (camera), a lecture page preview (a lecture PDF, which only a personal build seeds), Siri sheets (parked in previews), the iPad set window, the insight quiz (no answer history outside a personal build), the map legend (a tap inside the map).
  - [ ] Mac run: dispatch ios-preview with the list as `screens`, then read every still and fix the cases that come out wrong.

### The launch mark (design/launch-anim), 15 Oct

- The owner, correcting an earlier relay: "i meant only the diaphragm i want
  the jagged parts fixed in both". Decided: only the light mark's blue
  chest-piece ring stays. Still open: the two drawings' shapes, which stay
  as they are for now (not the owner's choice).
- [x] The grey tube by night (Claude-Code 33f282f: 06-grey-flat-dark for
  the launch, icon-dark for the icon) and clean cuts for both marks and
  both icon layers: tools/make_launch_logo.py reads the mark by its colour,
  the chrome's rim included, and draws the outline with sub-pixel coverage.
  tests/art/clean-edges.test.mjs (fails on fb24d0e0's art) and
  tests/art/no-blue-tube.test.mjs check every size.
- [ ] Sent back to be redrawn: the dark launch drawing's thin blue line
  where the grey tube meets the chest piece's stem (the day drawing has
  none); the blue-tube test allows only that line until it is fixed.
- [x] One master ECG (design/launch-ecg): ios/RedPen/Shared/Brand/EcgTrace.swift
  is one normal-sinus lead II beat at 60 a minute (PR 0.16, QRS 0.09, QT
  0.38 s by the tangent, Tp-e/QT about 0.2), runs of it at 55-68 a minute
  (where its QTc stays normal), its landmarks, its heart sounds (S1 20 ms
  after R, S2 on T's end, 0.36 s apart) and ECG paper (25 mm/s, 10 mm/mV)
  at any size, evenly sampled so equal windows pair point for point, every
  number cited in the file; suite ecgtrace. The heartbeat's lub-dub gap is
  now that 0.36 s (tools/make_heartbeat.py SYSTOLE, heartbeat.caf
  re-mastered: S1 0.0304 s, S2 0.3909 s, peak 29203 counts, -1.0 dBFS).
- [ ] The launch stream wires it in (lines as at design/launch-ecg):
  1. Done on design/launch-ecg: LaunchOpening.swift:43 HeartbeatSound.s2
     is 0.3909, the re-mastered file's S2.
  2. LaunchOpening.swift:79-89: S1 is heard EcgTrace.s1AfterR after R, so
     s2 = r + s1AfterR + (HeartbeatSound.s2 - HeartbeatSound.s1) and
     audioAt = r + s1AfterR - HeartbeatSound.s1, and the :79 comment ("the
     R peak, which is when S1 is heard") changes. With the lub at
     0.30 s (done), r is 0.28 and S2 lands 0.5 ms after T's end.
  3. LaunchOpening.swift:263-272 ecgHeight: EcgTrace.millivolts(at: t -
     (r - EcgTrace.time(of: .r))).
  4. LaunchOpening.swift:276-292 trace: EcgTrace.points. Decide the scale
     first: in LaunchSplash's 176 x 36 box (LaunchSplash.swift:271-272) one
     beat at paper scale is about 58 pt wide; fill the width with a window
     of about 2.4 s, or keep one beat across 176 pt with R about 90 pt tall.
  5. LaunchOpening.swift:365-368 and 376-414 (squiggle, morph) and
     WardVitals.swift:94-108 (EcgSquiggle): draw EcgTrace.points over
     windows of the same length and pair them by index.
  6. LaunchOpeningTests.swift: done on design/launch-ecg: :124 passes,
     :126 checks the file's 0.36 s, and :51 still bounds the opening at 1.7 s
     (the lub is now at 0.30 s, not 0.33 s, a 0.03 s trim: it is 1.6905 s). Still to do:
     :134 and :149-150 to S1 = R + 0.020; :139's "on S1"; :165 (full
     width) and :166 (R 30 pt) under paper scale; :246-272 (morph,
     squiggle). :135 and :140-146 hold.
  7. tools/swift_suites.txt:435: add $S/Brand/EcgTrace.swift to launchopening.
  8. tools/launch_film.py:41-45: :44's regex needs a literal r, and
     audioAt becomes r + 0.020 - s1.

- [x] A4, the opening's hand-off hold (final attempt, task launch-a4): the
  Launch recording 38723188012 on 446bbb36 measured gaps of 115 and 209 ms in
  the dark takes. Cause: the paper frame's Canvas redrew every frame from
  +0.73 s to +1.95 s, and the title's layer changed width as its letters
  spread. Fix: the paper at rest is one drawing that never changes during
  the hand-off (WardPaperRest), the cut is a Core Animation mask posed by a
  transform (WardPaperCutView), and the title draws one invisible box so its
  layer keeps one size (LetterSettle). Tick it when the push's Launch
  recording shows a gap of 100 ms or less in every light and dark take; if
  not, the next step is an advisor review, not more tuning.
  - Merged with the integration branch; awaits its Design preview and Launch recording.
  - Attempt 4 (a3f7477e, Launch recording 38768221249): dark 51 and 64 ms,
    light take 2 85 ms, but light take 1 303 ms at +1.22 s.
  - Advisor review (task T0046), applied here together with the owner's
    "remove the ring around the outer edge": the outer opening loses its ink
    outline (button rings, shadows and the chest-piece ring stay); one Core
    Animation paper sheet now runs from the warm-up frame through rest, so
    the mask and picture are composed before the reveal instead of first at
    +0.79 s; and the title draws its glyph slices at rest too, so slice
    drawing is warm before the first letter moves. The cause of the 303 ms
    take is a hypothesis until the recording shows it: if a take still
    holds over 100 ms, sample that cold take before any further change.
    The opening now ends on the ringless home with the same sheet, so
    there is no renderer swap at the end.
  - The advisor's fix (eb677f7c, Launch recording 38782361711): light 107
    and 85 ms, dark 96 and 91 ms. The 303 ms hold is gone, but light take 1
    still holds 107 ms, ending right as home goes still (+2.05 s). The
    recording now adds a third take, profiled with spindump (every thread's
    stack each 2 ms, not judged), and re-measures the two judged takes on
    the same code. Next: read what the main thread does in that take's
    longest hold, then fix that cause only.
  - The profiled recording (1a4fa025, 38785473364): light 117 ms at +0.94
    (35 refreshes, the Mac's load average 497) and 87 ms at +1.40 (load
    424); dark 50 ms at +1.56 and 126 ms at +1.03; the profiled take 69 ms
    at +1.62 (load 303). The holds now fall at a different moment each
    take. spindump came too late to show them: it attached 2 s after the
    app started and prints no time per stack. It does show the first frame
    (UIApplication's first commit, laying out the hosting view) taking
    about 139 of 820 samples on that busy Mac. The dark film was lost: the
    publish retry tried to check out the branch a second time, which git
    refuses while the first attempt's worktree holds it; the retry now
    works detached and pushes HEAD. Next: the advisor judges app or host
    before any change to the app.
  - The advisor's ruling: undetermined, leaning to the runner (the lost
    refreshes are spread through the window, and the light takes rank by
    load), though each long hold sits near an app event (just after the
    hand-off, or as home goes still). So, before any change to the app,
    each judged take now waits until the runner settles: the 1-minute load
    under 3 x its cores, read every 15 s, at most 5 minutes, with the load
    and "settled" or "unsettled" written beside each readout. The rule is
    fixed in advance and the same for every take, and the 100 ms gate is
    unchanged. The profiled take is gone (spindump can't time a hold). If a
    hold over 100 ms survives on a settled runner with full refreshes, it
    is the app's: then os_signpost intervals round the hand-off, read back
    with log show --signpost.
  - Diagnostics before any change to the app (no change to how the opening
    or home look or behave, the 100 ms gate unchanged): a recorded opening
    now also writes, after the old fields, `gaps=` (each gap over 50 ms:
    its end, length and the main thread's CPU time across it), `interval_ms=`
    and `marks=` (hand-off, home's first appearance, and the start..end of
    home's loads: due cards, the round's plan, the tiles; LaunchDiagnostics,
    WardHome). A gap with CPU near its length is the main thread working
    (the loads or drawing); with CPU near 0 it was waiting (the runner, or a
    lock). A control take with home's loads stood in for (since removed) ran
    after each judged one. The settle wait is replaced by a fixed 30 s sleep,
    and the timing file now has mdutil and the busiest processes round each
    launch.
  - Glows experiment (run 38812510377; the flags are removed again, see
    the next item): the control take after each judged one drew every Ward
    light as a 1-pt rim with no blur, three judged takes per mode. Gap in
    ms / refreshes, by take:

    | take | relief on | relief off |
    |---|---|---|
    | light | no readout; 42/62; 83/46 | 33/74; 48/59; 65/71 |
    | dark | 128/56; 54/61; 61/57 | 38/70; 33/73; 44/71 |

    All six relief-off takes passed with 59-74 refreshes, even at a higher
    runner load than the relief-on takes; relief-on failed twice (in the
    no-readout take the app still used 92% CPU 23 s after launch). So the
    per-frame blur of the relief lights is the cost: SwiftUI redraws every
    face's shadow blur each frame while home's parts change scale.
  - The ruling: draw the relief lights once, with the same look, instead of
    every frame. Done in this change (not yet seen in a recording):
    - [x] Each relief face is drawn by one drawing code (WardReliefDrawing,
      WardPressDrawing in WardSurfaces) that runs live or into an image
      (ImageRenderer, at the display scale, padded by the lights' reach;
      WardLightImages). A raised or inset face, and a press face at depth 0,
      show that image as a stretchable slice; the live drawing stays for a
      press in motion or held, a fill that is not a colour, a shape that is
      not a rounded rectangle, capsule or circle, and wardUnlit / flat faces.
    - [x] The slicing and the key are Foundation-only (WardLightSlice) with
      Linux tests (suite wardlightslice): reach per look, caps = pad + the
      corner's curve (1.53 x the radius, continuous) + reach, a capsule keyed
      by its height, a circle by its diameter, a side shorter than two caps
      and a core drawn whole and keyed by its size; the tests draw both with
      a Gaussian and check the stretched slice equals the larger drawing to
      within one 8-bit step, at every lift, raised and press.
    - [x] No image is made in the hand-off window (LaunchStage.handingOff,
      from the splash starting the opening until home is still): home is
      drawn whole under the splash (warm), which makes its styles; a style
      asked for in the window draws live and is made when it ends
      (WardLightImages.catchUp); the readout's marks show `relief-late` if
      that ever happens on a normal launch. A light/dark switch finds the
      other scheme's images made at rest (or makes them in the same frame);
      the swap is one step, no opacity.
    - [x] The experiment scaffolding is removed: `-uiPreviewStubHomeData`,
      HomeStandIn, homeDue, `-uiPreviewNoGlows`, and the workflow's control
      takes. Kept: three judged takes per mode, the fixed 30 s pause, the
      readout's gaps/cpu and marks (now also `relief` loads), the snapshots
      after each take, and the 100 ms gate as it was.
    - [x] Tick the item when the push's Launch recording shows 100 ms or
      less in every light and dark take. Check by eye that raised and inset
      faces, and buttons at rest, look as before (the image sits where the
      live face was; a Mac run was not possible here).
  - Ruling #4 (the judge, after run 38826276378, whose cached takes did no
    better than the live relief: light 106/57, 64/56, 55/48 ms/refreshes,
    dark 129/50, 66/43, 90/51; no `relief-late` mark, home's pictures
    identical before and after, so nobody could tell whether the cache drew
    at all): count, fix, then one decisive run.
    - [x] Count. The readout's last field counts every relief face on screen
      when home is still, once per take, by how it was drawn, and the images
      made before the hand-off: `relief=cached:12,live:plan@0x0:1 made=15/42ms`
      (`failed=N` after it if an image could not be drawn). Live tags:
      `shape` (uncovered shape), `fill` (not a colour, or no RGB), `plan@WxH`
      (no slice plan for that size), `failed` (render failed), `late` (asked
      for inside the hand-off), `press` (in motion or held), `none` (no
      lights to draw: flat, unlit, or lights not lit), `empty` (a box of no
      size), `off` (the relief-off take). WardReliefCensus (Foundation-only,
      tested), WardFaceToken, WardLitFace; LaunchStage.writeReadout.
    - [x] Fix. Covered now: a readiness ring's groove (WardAnnulus, the one
      shape on home that fell through as `shape`), and a circle in a box
      that is not square (drawn at its shorter side, in the middle, as live).
      A face smaller than its slices was already drawn whole at its own size
      (keyed by its pixels). A render that fails is no longer left live for
      good: it falls back to the renderer's CGImage, is tried again outside
      any face's drawing (three attempts) and counted in `failed=`. Not seen
      on a Mac: whether ImageRenderer ever fails here is for the run to say.
    - [x] The relief-off switch is back for the recording only
      (`-uiPreviewNoGlows`: every Ward light at radius 0 as a 1-pt rim, the
      ink edge and colours kept, drawn live, the cache bypassed). The Launch
      recording alternates, per mode, a cached take and a relief-off take,
      three of each. Cached readouts: film/handoff-$MODE.txt, gated as
      before; relief-off: film/handoff-$MODE-control.txt, not gated.
    - [x] The decisive run, and the decision rule, fixed in advance: a cached
      take counts only if every relief face with lights in the window drew
      from the cache (no `live:` tag but `none` and `empty`, no `failed=`);
      the relief-off takes must pass as in 38812510377 (59-74 refreshes, no
      gap over 100 ms) or the run is void. Three light and three dark
      counted passes (gap 100 ms or less, 55+ refreshes, same look) close
      the task and keep the cache. Otherwise the cache is reverted in one
      commit and the main-thread rule (narrower) is tried.
    - Closed by Launch recording 38837815702 on 52d7e26b (38835807482 before
      it was void: a relief-off light take at 102 ms / 66). Every cached take
      read `relief=cached:12`. Gap in ms / refreshes, by take:

      | take | cached | relief off |
      |---|---|---|
      | light | 37/74; 33/74; 55/59 | 34/73; 17/75; 74/56 |
      | dark | 40/66; 41/65; 51/55 | 17/75; 64/62; 47/63 |

      Same look: home's pictures on shots/relief-after-2 (the cache drawing)
      are byte-identical to shots/relief-after's (ca93de8b, where faces still
      fell back live), and differ from shots/relief-before only where those
      did (the date, and Start's edge under the dock). The cache stays; the
      relief-off take stays in the recording as its standing control.
- [x] Before design/launch-anim goes to personal: testDesignTour loses the
  app on its first attempt, at the dock switch (DesignTourUITests.swift:483;
  an assertion in UICollectionView's nested visible-cells update, called from
  SwiftUI's list), in all three Design previews of this branch (2465e89a,
  ca93de8b, 52d7e26b), and testStraightLines finds no examples banner
  (GraphPreviewUITests.swift:424) in all three. Neither fails on the Design
  previews of design/neurons-depth, which comes from personal. Root cause
  first, then the fix.
  Root cause (independent review): LaunchEntrance wrote its frame to view
  state from onGeometryChange for good once home was at rest, and it wraps
  whole groups of the list's rows, so each write redrew every row, which
  re-sized and moved them and wrote again: a loop from geometry to state to
  layout. The fix keeps the frame in a plain object (LaunchSpot), with a
  source check in LaunchOpeningTests. Tick when the Design preview of the
  fix passes the tour on its first attempt and testStraightLines finds the
  banner, and the Launch recording shows the readout and gate unchanged.
  The Design preview of that fix (6dd59b90, run 38846916363): the iPhone
  still loses the app after the dock's OSCE tab and still finds no banner
  (the iPad passed both, as it had before), and the Launch recording is
  unchanged. A second fix (183932ad: WardLightImages making a missing
  image on the next turn instead of inside a face's layout) made the iPad
  fail as well and changed the relief count from cached:12 to cached:11,
  so it is reverted.
  Root cause (a second independent review, 16 Oct): LibraryView put
  LaunchEntrance around modesSection and listBody, and each of those yields
  several Sections, so SwiftUI stacked every Section below the round card
  into one List row (the accessibility tree shows one cell from the set
  rows to examplesBanner, and the screenshots one tile with centred
  headings). On the iPhone that row is about five screens tall and its
  self-sizing never settles: the tour dies at the first accessibility
  snapshot after the dock switches page, and the swipes stall before the
  banner. On the iPad the row is short enough to settle. Fix 2's iPad
  failure was something else: a face switching from live to cached
  re-created the recording terms' agree button mid-tap, and the test kept
  tapping its corner, outside the capsule.
  The fix: the entrance comes off the two builders and goes on each row's
  own view (the set rows, each grid, the section headers, the build-session
  and examples buttons, the "Across the app" rows), never on a Section, a
  ForEach or a builder of several rows, with source checks in
  LaunchOpeningTests. Tick when one Design preview of it
  passes the iPhone tour on its first attempt (03-library-osce and
  04-library-audio), testStraightLines finds the banner, the accessibility
  tree shows one cell per row, the iPad passes both, and the Launch
  recording keeps every gap at 100 ms or less with the relief readout
  cached:18, live:empty:1, live:none:5, made=12 (each row now draws its own
  tile; the 16 Oct review set this readout). Recording: passed, run alone
  on eaac1d87 (38869778510, attempt 2): every gap 17-89 ms, controls
  included, and that readout on every take. A busier Mac had failed the
  first attempt with relief off too, so the runner, not the change, was at
  fault. Design preview 38869779008 (eaac1d87): the iPhone tour passed on
  its first attempt, with 03-library-osce and 04-library-audio not merged
  (the example set on its own tile, PRACTISE and TOOLS left-aligned, the
  iPhone's tools two across); testStraightLines found the banner on both
  devices; the iPad passed both. The accessibility tree is only published
  when a test fails, so those screenshots stand for "one cell per row".
  The iPad's testLinkLength failed once there (a simulator tap
  cancellation; a test-only follow-up, below).
- [ ] After that, from the same reviews, each with a Launch recording:
  WardRowTile's entrance only on home, not on the thirty other screens that
  use the row background; WardLightImages evicting its oldest images
  instead of clearing all 256 at once, and caching no size while it
  animates; and each live/cached switch (WardLitFace, WardPressRelief,
  WardReliefFace) as one structure with both layers and an opacity switch,
  so a face never becomes a new view, with a new accessibility node, in the
  middle of a tap.
- [ ] Test only: GraphPreviewUITests (about :357) taps the Look menu's item
  again when linkLengthBar has not appeared, the way the tour retries its
  taps; the iPad's one failure there was the simulator cancelling the tap.
- [x] Test only (T0105): the UI tests reach each section through the dock's
  buttons or, where it is one dockList button (iPhone 17 Pro, default size),
  through its list (UITests/LibraryDock), so the tour finds home again.
  Superseded by T0112: the dock is the row again and the UI tests require it.
- [x] T0112 (owner 22 Oct, "the tabs folded into one Questions button on a
  17 Pro are wrong"): the dock along the bottom is the full row (Questions,
  Cards, Cases, OSCE, Audio and Ideas) at every text size short of the
  accessibility ones, on every phone. Short of width, the five names shrink
  alike (to half at the least) and keep their side room from the chosen ring;
  the concentric corner stays (WardDock.form / tabWidths / showsList, tested
  in wardstates at 375 to 440 pt and all standard sizes). LibraryDock and the
  four suites that accepted the list button require the row again.
- [x] T0112 A1 (repair): home's page is no longer cut 12 pt above New set
  and the dock (the owner, 22 Oct: that band was wrong; it replaces the cut of
  14 Oct). The rows run on behind New set and the dock to the window's bottom
  edge, with nothing behind them but the page and no soft edge under them
  (no fading); the list's end row (HomeFit.endSpace: the bar's height and 24)
  lets the last tile scroll wholly clear above them (HomeFit.lastRowBottom).
  The preview's gate keeps the card and Start ward round 12 pt above the bar
  at the standard sizes (HomeFit.barLine) and drops the sliver checks, which
  were about the cut. Tested in homefit (model and source checks).
- [x] T0112-android: Android home is not cut either (HomeCutPage gone; New set and the dock float over the list in a Box, its end row HomeFit.endSpace), HomeFit.kt and HomeFitTest.kt ported from iOS 3752d114; the textbook flows scroll the set row clear of the bar before tapping it. Open: ScreenshotTest.ideas' Space map drew no coloured samples on CI (11-ideas-map is now shot before the check, for evidence).
- [x] T0115a-android-ai: Android has the iPhone's hosted-AI client (android/app/src/main/java/com/stethoscore/app/llm/: HostedLLMClient, CloudJobs, CloudJobRules, LLMService, MedicalGenerate with MCQPrompt, AccuracyCheck, OwnerSpend). Make N questions, the Cases maker and the debrief's Another patient like this, and the accuracy checker go through the worker, as iOS's do; Settings > AI models chose Off or Stethoscore Cloud (gone since T0132: no writer to choose). Only the personal build (Gradle property stethoscoreOwnerKey, never in the repo) sends the owner key, and it stops at $20.00 counted on the phone (reported usage at Claude's $4/$20 a million, else the request's max_tokens). Rows in android/docs/parity.md ("The hosted AI client").
- [ ] T0115b-android-ai: the rest of iOS's AI on Android: CloudJobCollector and the Delivery (a job finished with the app closed made into its set), GenerationCenter's one card, the osce() writer and OSCE stations, the card and textbook writers (LectureWriterSection), Write a twin and the attending's hint, the coverage and Vitals AI checks, MCQRepair, Provenance on a generated set, CloudChecks' evidence, the accuracy ledger, weights, background loop, reports and badge, Verify what is generated. Not to port: Apple Foundation Models, Doctor-R1 and Gemma on the device, providers with the student's own key.
- [x] T0115b1-android-reach: the owner reaches Make N questions and the Cases maker on Android the way iOS does. New set's From a lecture file comes first for Practice questions (then Type or paste and Import a file) and for Patient cases (then Import a file), as NewSetView.paths(for:); it hosts MCQGenerateForm, whose questions open unsaved in the quiz (Save there; Back asks Keep these questions? with Save to library, Discard and Cancel), and CaseMakeSection (android ui/cases, ported from iOS: Choose a lecture, How many patients, Make N patients), which saves the patients as a set named for the lecture, with the lecture as its source. Next names the set for the lecture, and a category's Paste or import opens New set on Add your lecture with typing chosen (NewSetView(kind:startingAt:)). NewSetReachTest taps from home's New set to a stand-in worker. The accuracy check is not reachable yet (T0115b2).
- [x] T0115b2-android-reach: what iOS reaches that Android still cannot. Done: Check accuracy in the More menu of the quiz, card review, due today, OSCE review and book screens (Theme.swift studyMoreMenu; the OSCE and book screens gain a More circle with it), opening ui/AccuracyWhySheet.kt (AccuracyBadge.swift AccuracyWhySheet: Result with Check now, checked at once when never checked, Rule checks, Checker models, Sources the checkers were shown), over llm/AccuracyCheck and graded by AccuracyModel's prior-1 weights and verdict; a check is remembered while the app runs. New set from a preset (NewSetView(preset:): on Make, the lecture path and its writer) from Coverage's Generate questions (now iOS's syllabus brief), the exam card's Study next and the Ward pocket's Practise this (from the quiz's Clinical reference). The dock's floating copy of Make (FloatingAction: the questions' or the patients' Make while the real one is out of sight). StudyReachTest taps each from the screen to a stand-in worker. Turn into and a lecture shared into the app are T0115b3's. Left: the exam plan's own Clinical reference (ui/learn/ExamPlanScreen.kt) still opens the plain New set; no source proof, ledger on disk, Accept the correction or Report a problem / Report an error yet (T0115b). The card, textbook and OSCE writers on the lecture path are T0115b's.
- [x] T0115b3-android-reach: Turn into and a lecture shared into the app, as iOS. data/ModeConversion.kt ports ModeConversion.swift (targets, canTurn, "Name – Mode", the instant turns: questions into cards, a deck of three or more into a quiz from its own answers, a station into cards that drill its order; the writer's material: the kept lecture, else the set as text; NewSetPreset(turning:into:)), with ModeConversionTest porting ModeConversionTests check for check. ui/library/TurnIntoPicker.kt ports TurnIntoPicker.swift (a tile per mode saying Instant · N cards, Written by AI from your lecture or from this set, or This set; an instant set is added and opened, a written one opens New set on Make with the material in; ModeSwitch hands the choice to the app once the picker has gone) and TurnIntoListView (the Turn into… tile on Questions, Cards, Cases, OSCE and Audio). Turn into is in a library row's menu and the More menu of the quiz (saved, not mid-paper), card review, OSCE review and book. A PDF, Word or PowerPoint file opened or shared from another app gets the Received sheet (ImportInboxSheet: Make questions from this lecture reads it and opens New set on Make with it in, NewSetPreset(lecture:)); the manifest takes those types. TurnIntoReachTest taps each from the screen to the result on a stand-in worker. A written turn's folder is not carried (Android's NewSetPreset has no folder), and the card, textbook and OSCE writers it would open are T0115b's.
- [ ] T0117-mac-suites: since Wave 1 (f3563087) the Mac job's suites dataio, imports and storeload stopped at Brand.swift:37 and :40 (`.wardInk`, `.wardBackground`; run 39735376216). Listing the Ward files (WardTokens, WardLook, WardPalette, WardRelief) could not fix it: WardTokens.swift, and LaunchStage.swift which it needs, import UIKit, and the suites build for macOS, which has SwiftUI but no UIKit (Store.swift fences it for that reason). Done: Brand.swift's look is under `#if canImport(UIKit)` (the app and the Playgrounds zip keep it; the suites read only the name and line, as on Linux), and tools/swift_suite_closure.py, which preflight runs on every suite, reads each as macOS or Linux builds it and fails on a Ward name none of its files define, or a mac-only suite's file importing UIKit. Waits for its Mac run (the push's swift-tests mac job).
- [x] T0118-android-map: ScreenshotTest.ideas' blank Space map on CI (runs 39745559363, 39736799084) was looked at too early, not drawn wrong. The emulator's software GL (SwiftShader 4.0.0.1) builds each shader on its first draw, so the map's first frame with bodies takes seconds (3.6 s, 5.5 s with the Earth maps, on the emulator's own SwiftShader; later frames 0.03 to 0.08 s), and the frame before it holds only the summary star, a point SwiftShader allows 1 px (its point-size range is 1 to 1), which draws nothing: the fixed 3 s pause sampled that frame (0 coloured samples). The map now keeps a record of its finished frames (MapDrawn, on its node as MapDrawnKey, which accessibility does not read); the test waits on it, up to a minute, then looks once, as strictly as before, and a failure says what the map had drawn and what the screen held. Phones and iOS are not affected. Open: the next screenshots run is the proof, android/scripts/capture-screenshots.sh now reads the test and picture counts from ScreenshotTest.kt (10 and 13) and pulls the pictures before it checks them.
- [x] T0126c-android-tour: the Android app tour in stills. TourTest (androidTest, with its camera TourCapture) shoots 88 of the 89 Android rows of the T0126a inventory, each in light and dark from one composition per test (the mode flips by state), 97 tests and 203 PNGs as r<row>-<name>-<light|dark> in /sdcard/Download/stethoscore-tour; tools/tour_screens_android.txt lists them in inventory order. Seeded only from loadExamples, DemoData and InsightExamples; no exam wording is used to find a node. Row 94 (lecture finished) is skipped: it needs live text-to-speech to reach the end and the screen has no start-finished parameter. Bedtime (60) is dark only, as the screen is. It runs only when android.yml is dispatched with tour: true (capture-screenshots.sh tour, concurrency group android-<ref>-tour); the default run leaves TourTest out (-e notClass) and is otherwise unchanged. Open: the first tour run is the proof (expected about 15 min in the 30 min job).
- [x] T0130-android-tour-fixes: what the d2b3c6ff Android tour showed wrong. Ward faces kept a ring's even-odd outline (the ring's middle is the page colour, not white) and cards give their words the ink; the lecture reader's sheet keeps clear of the status bar; home's bar stays behind the keyboard; the map's speed readout shows only in a debug build; the Ward pocket's page ends above its floating total and disclaimer; How sure? fits one row as iOS's ViewThatFits; the tour frames each page as the app does (wardFrameClearance, sheets in their page's place) and shoots bedtime in light too.
- [x] T0132-owner-batch1 (the owner, 22 Oct), iOS and Android alike: (1) sign-in and account-deleted show the launch's white (day) and grey (night) stethoscopes over "Stethoscore" instead of the three mode tiles, looked up by LaunchArt.names in the slots LaunchLogo{,-dark}@{2,3}x.png, filled outside this repository; no build step here adds them, so every CI-built app shows the stand-in stethoscope (Android has no sign-in); (3) card review's ratings are one row of four words, no captions, 44 pt / 48 dp; (4) draw recall's paper fills the page from under the hint to above the pen tray, pressed into the page colour, its corners WardCorner.concentric, the ink in the mode (iOS only: Android has no draw recall); (5) the iOS pocket's total, disclaimer and search no longer stand over its rows (Android's were T0130), home's end row is proved on Android (HomeEndClearTest) and the iOS tour gains library-end; name-sheet light's grey box is the simulator's first-keyboard introduction, not the app; (6) bedtime follows the mode on its page colour; (7) the vitals rhythm card is laid out like a bedside monitor, trace left and the parameter column right; (8) Google's own branded button with the multicolour G, its label at Google's 14 pt scaled, Apple's black by day and white by night (Android has no Google sign-in); (2) the AI models and Add hosted model screens are gone on both platforms (the owner: all the app's text AI on one route, audio on the server's transcription route): every role is the worker's writer route `cramdown-writer` behind Pro, a bearer, the worker's PRO_PAYS and the spend caps (iOS WriterRoute, llm suite; Android WriterRouteTest), and Settings shows the cloud's status, Verify, the accuracy engine and Crash reports as plain rows (iOS SettingsRowsUITests; Android SettingsCloudRowsTest). Repair (review R1-R9): Android's monitor words take the held colours on the dark well, checked for contrast in light and dark; rating words shrink to fit (RatingWordFitTest, font scale 1.3 and 1.45); the iOS trace and divider take the readouts' height; draw recall keeps the paper's size through Compare and the original takes the mode (recallpaper suite); the preview run skips the keyboard's first-use introductions.
- [x] T0132 attempt 3 (the owner, 23 Oct: "Lock it"): only the writer route writes text. iOS lost the on-device question, case and station writers, the offline model download and its package; the question form shows the cloud's reason with See Pro, the case and station screens the reason, and every screen writes through WriterGate (llm suite: no writer, nothing run; tests/governance/writer-lock.test.mjs); a launch removes earlier builds' model files (RetiredModels). Android's question and case screens say why in iOS's words. The worker answers an account from Claude only: no free chain behind it, 402 (See Pro) when Claude is not on its route, nothing else asked when Claude fails; the owner key's route, allowance and $20 wallet unchanged (server/tests/owner-claude.test.mjs A4). Google retired gemini-3.5-flash (it now reaches 3.6 Flash, never used): the server names gemini-3.8-flash at Google's published price from 1 Jan 2027 ($1.50/$7.50, audio $1.50), Flash-Lite stays (server/tests/retired-models.test.mjs). Sign-in's comment names only the art's slots. Not deployed.
- [x] T0132 attempt 4 (the owner, 23 Oct: "only me"): text is written for the owner alone. The worker answers the owner key and the owner signed in (an account rowIsOwner accepts, since the app sends the session first) with the key's route, allowance and one $20 wallet, counted as 'owner'; every other account, Pro or not and whatever PRO_PAYS says, gets 402 (See Pro) before any model is asked (owner-claude A4, A5). Audio is 3.8 Flash only, with no Flash-Lite behind it (retired-models), and the iOS app expects it (CloudTranscript.preferredModel). Android's station screen gives the cloud's reason as its question and case screens do; the switch messages and the preview workflow no longer mention on-device models. Not deployed.
- [x] T0132 attempt 5: the accuracy check is the owner's alone too (a vote's fix is model text): checkBatch refuses anyone but the owner key or the owner signed in with 402 before a vote is asked (ai.test). The transcript notice says a lighter transcriber in plain words, and comments name no model. Android's stations fail closed with the cloud's reason (parity.md). Not deployed.
- [x] T0129-tour-quizchecked: run 39842676971 passed 96/97; r043 failed because the test tapped Check answer below the fold, under the How sure? bar (the app is right: a reader scrolls), so TourCapture.tapInView scrolls a control into view before tapping; QuizCheckedTest checks it in light and dark.
- [x] T0133-deep-twin-occlusion: Write a twin and picture cards, tested step by step on both platforms. iOS: suites twinflow (TwinFlowTests, S1-S7: the miss, the stand-in writer, the wait on a fake London clock, review order, nothing yet, answered, relaunch) and occlusionflow (OcclusionFlowTests, O1-O5: every label masked, Reveal, rating to the next card, the photo path, relaunch); TwinBook and TwinDraft hold ExamStore's twin rules as plain values. Fixed: the heart example left Superior vena cava uncovered (Vision boxes "Superior" taller than "vena", so OcclusionPhrases split the label and OcclusionFilter dropped the pieces; now lines and wraps compare type size, and a title must be 1.25x the median type size). Inferior vena cava showed only in the test's glyph-tight model of the drawing (its "cava" gap), not in a reported run; the same fix covers it. Android: Write a twin is ported (quiz/TwinBook.kt: TwinBook, TwinShelf in twins.json, TwinWriter with the New set writer, TwinSets, the Twins tile under Questions), tested by TwinFlowTest, TwinScreensTest (Robolectric: the chip, the stand-in worker, no writer, nothing yet light and dark with Done) and OcclusionFlowTest. Tour: iOS twin-written and occlusion-revealed; Android r024 shows the Twins words. "Reveal reveals all" is not built: Reveal takes off the asked label and keeps the others grey, as designed; the owner to say if every cover should go. Open: the next Mac run and Android tour are the proof of the new stills.
- [x] T0133 repair: one rectangle per label (the owner): each label is under exactly one cover holding all its words with a margin, never reaching a neighbour; the photo path joins one label's drags (PhotoOcclusion.oneEach, both platforms); a wrap gap is measured as type is set only for glyph-tight boxes, so stacked lower-case labels ("vein" over "artery") stay two. Tested on the heart, a second diagram (a kidney, line-high boxes) and the photo path (occlusionflow, OcclusionFlowTest). Twins: one per miss (TwinBook.canWrite, both platforms); iOS writing is TwinWriting on a TwinDesk, tested with a stand-in writer, retryPending and the alert's words; Android twins.json is written atomically under one lock, an unreadable file is kept aside and said, and twins travel with the library export and import (TwinShelf.reset is ready; Android has no library reset yet). Sure-but-wrong is confidentMistakeIds on both; only the practice quiz moves a twin, not a mock paper, the commute or a reminder (as iOS). Android r024 is back as it was, the Twins words are r024_nothingHereYetTwins.
- [x] T0147-theme-tour: the tours shoot every Ideas map theme in light and dark, on the example notes, for the owner to set beside the Sorta alternate icons. iOS adds ideas-map-neurons, ideas-map-performance, ideas-legend-neurons and ideas-legend-performance (PreviewExtras: GraphTheme.key registered to the theme, the legend open over the map as the Look menu opens it; tools/tour_screens.txt rows 103 and 105). Android adds r103_brainMapPerformance and r105_legendPerformance (ideas-map-performance, ideas-legend-performance), each waiting on the Fast map of 4 notes; Neurons is not ported to Android (GraphTheme.isReady), so it has no row there. iOS has no Space legend still; Space stays ideas-map. Open: the next Mac run and Android tour are the proof of the new stills.
- [~] T0148-ui-suite: why the first full UI run on design/integration (App build 39932576764, 2c144162) never finished. Evidence from its xcresult (cut off, so only Staging/ logs and the failed tests' recordings): no test hung. Passed: Arabic, DesignTour (430 s), Examples (176 s), GraphPreview testBodyCloseUps, testDepthBeforeAfter, testDepthLively, testDepthMeasure (754 s), testDepthProbeOpacity, testDepthSpin, testDepthTurnNeurons, testDepthTurnSpace, testEachStyle, testGraphAtRest, testGraphWhileDragging. Failed: GraphPerfProof testPerfProofRecorded, testPerfProofTour, testPerfProofTourFadeOff (each about 910 s, "the million was not built within 15 minutes: 0 notes · 0 links, 0 fps"), GraphPreview testDepthGlide (Atrial fibrillation pickable, at x 409 just off the 402 pt screen, before the glide). The job was cancelled at 11:02:57 with testHoldDrag 2 s in; the other 20 GraphPreview tests, LocalSignIn, Onboarding, RotationState, SettingsRows, TurnInto and the AX5 step never ran. The suite outgrew the 90-minute job: 45 of its 81 minutes were the three proof tests waiting out their 15 minutes.
  - The million: the main thread answered every one of 7,839 readout reads (about 1 s each), so it was not stalled; the readout stayed "0 notes · 0 links, 0 fps" and the recording shows an empty map with no "cannot draw" label, so GraphPerfRenderer was made and the million never reached the screen. Unoptimised on Linux the whole build (synthetic vault, scene, chunks) takes 28 s for 1,000,000 notes, so 15 minutes is not slowness. GraphPerfCoordinator.load, GraphPerfMapView.show(million:), GraphPerfMillionRenderer.init? and its load() drop a failure without a word (guard ... else { return }), and their NSLogs are silenced by keepTraceOffConsole (OS_ACTIVITY_MODE=disable). It began with 47c13782 (depth fade, 15 Oct): the million drew on the simulator before it, perf-proof-1 failed after it. The fix lies in Graph*.swift, outside T0148's scope: name the failure in the readout (shaders, pipeline or buffer) so the proof fails at once with its reason. testPerformanceMillion has the same cause and will fail after its 7 minutes.
  - testDepthGlide: its premise, Atrial fibrillation past the band's end, does not hold: the Space band culls nothing in the tilted default view (the open item under Space's depth fade above). The band (GraphSpaceDepth.swift) is the owner's decision and outside T0148's scope.
  - testIslandPushAndBack ("no studyMore button after returning", e433ca15 and preview 39616958068): the app crashes. The edge drag's first touch overflows the main thread's stack (EXC_BAD_ACCESS, SIGSEGV, KERN_PROTECTION_FAILURE in the stack guard) in AttributeGraph's propagate_dirty under nested _UIHostingView._hitTest, while the quiz is pushed over the Anki deck; "Application is not running" from then on, the recording frozen on the quiz. No app frame is among the 42 kept, so the chain that runs so deep is not named; it needs the Mac (Instruments, or a breakpoint in the hit test) to find.
  - The AX5 walk (AccessibilityUITests, e433ca15): after "I understand and agree" the app never idles again ("failed to quiesce within 60s", then "main thread busy for 30.0s"), with "Update NavigationRequestObserver tried to update multiple times per frame" and "onChange(of: Optional<Double>)" / "onChange(of: Optional<CGFloat>) action tried to update multiple times per frame" logged at that moment, in both tests: a SwiftUI update loop at the largest text size. Not yet traced to its view; not run on integration (the step never started).
  - "The library didn't open" (Arabic, DesignTour, StraightLines, Onboarding on e433ca15): the dock folded to its list button at 402 pt, fixed by dad43e3f (in 2c144162, not in e433ca15); Arabic and DesignTour pass on 2c144162.
  - Done (app-build.yml): grep --line-buffered so Test Case lines reach the log live; XCTest's per-test limit (16 minutes in the suite, 8 in the AX5 walk) so a stuck test fails by name; the UI step 110 minutes and the AX5 step 20 inside a job of 150, with the summaries in their own always() steps, so they and the upload still run; uitest.log and a11y.log uploaded with the bundles. Only the next Mac run proves the flags and the timings.
- [~] T0152-accessibility: the AX5 walk and the audit (App build 39946874030 at f4e696d1, artifact 12503728336; each issue named from its element screenshot in a11y.xcresult), fixed at their causes; only the next Mac run proves them.
  - Library: "Element has no description" was the search field (librarySearch; UITextField with its placeholder emptied for SearchPrompt): it is labelled with its prompt. "Text clipped" was the countdown pill ("Step 1 in 9..."): its words wrap whole, as the date's do. "Dynamic Type font sizes are partially unsupported" was the date ("FRIDAY, OCTOBER 23", 40 pt caption2 at AX5, so it does grow): WardSmallCaps drops the tracking modifier at the AX sizes instead of tracking 0; the likeliest cause, not proven here.
  - Quiz: "Text clipped" twice, the header's "Question..." and "Tap the answ...", squeezed beside Timed (itself "Ti m e d"): StudyProgressHeader puts its accessory under the words at the AX sizes, the words wrap whole. "The first option is not on screen": the fixed header and the How sure? deck took the whole AX5 screen between them, so no option could be scrolled into view; at the AX sizes both now scroll with the question, and How sure? has a last layout of one chip a row ("Sur e", "Ma ybe" before).
  - Card: "Text clipped" was "How well did you rememb..." over the ratings: it wraps whole.
  - The update loop (e433ca15, "multiple times per frame" after the terms) does not recur on f4e6: none in a11y.log, uitest.log or the job log, and both AX5 tests got past the terms to every screen. Nothing changed for it.
- [x] T0149-theme-shots-ios: the iOS theme stills (ios-preview 39931526624 at e68554b0) fixed at their causes. The first-run card covered Space dark and Neurons and missed Space light: the tour now marks every theme's card and touch lines seen (TourData.mapCardsSeen), the card stays in the app. The Performance readout showed to every user: it is a developer's meter now (GraphPerfReadout: the personal build, or a demo map whose menu is the way back), and the legend's Speed row goes with it. Performance framed the map's bounding ball, so the tall example cluster filled a fifth of the width with its points pressed onto their hubs: a map of up to 2,000 bodies is framed on its bodies (GraphPerfCamera.framing(points:)), and its nearest points carry names (GraphPerfLabelChooser, wired at last; GraphPerfLabelSpots). Neurons was its own scene on its own tissue, hidden by the card; GraphTheme.bodies and .ground name each theme's builder and ground, and Graph3DView picks by them. Tests: graphperf P15, neurons T8. Open: ideas-map-light is the loader (built == nil) at the 7 s shot in two runs; it is the first SceneKit map launch of the light pass, and the fix is in the shoot step (ios-preview.yml, outside T0149): retake while the map's loader shows, or a warm-up launch. Re-shoot ideas-map, ideas-map-neurons, ideas-map-performance, ideas-legend-performance (light and dark).
- [ ] Mac run for T0112: screenshots of home on the 17 Pro, the Pro Max and a
  375 pt phone at the default size and at xxxLarge (the row, the names whole
  or barely smaller, the chosen ring clear of them), and the four UI suites;
  and home's bottom with the tiles passing behind New set and the dock (no
  strip, line or fade), scrolled to the end (the last tile clear above them),
  plus the ward-preview fit gate on every device. The workflow's comment
  (.github/workflows/ward-preview.yml:23-26) and WardControls.swift:66 still
  speak of the cut: word them anew in a task with those files in scope.
- [ ] Home's name as the owner's logo, and smaller text on home (the owner,
  on the first IPA): BrandLogo (Foundation-only, tested in brandlogo) picks
  stethoscore-logo-dark.png at night if present, else stethoscore-logo.png,
  else nil; the logo is added to the root of the built app's bundle after
  build and is never committed. HomeHeader.nameLine fits the logo (or the
  typed name in a box of the same 1449 x 447 aspect and 72 pt default height,
  56 to 112 pt, scaled down when narrower) beside the ECG squiggle as one
  "Stethoscore" header accessibility element, and LaunchStage uncovers the
  logo from left to right on the same clock and span as the typed letters
  with the logo's frame as the title target. On home only, every text style
  steps one Dynamic Type size smaller. Waits for its Ward preview and Launch
  recording.
- [x] T0119 (iOS Wave 2, components; the consistency sweep's rows, owner 22
  Oct "start all waves at once"): one Ward component per role where a row
  names a rebuilt one. Done: the dead CoronaGlow (and CoronaBreath),
  OptionalTag and LiquidGlass.swift deleted (WardTile kept); ModeTile draws
  WardIconSquare; Draw from memory's title eye is WardCircleButtonStyle(on:);
  HelpModeRow, DrawRecallExampleRow and PhotoCardsTile are WardRows; the
  Coverage count chips, ReviewUndoChip and NoteSourceChip are
  WardChipButtonStyle; Disease scripts shows the shared SavedIdeaToast for its
  4 s (10 s with VoiceOver). Already so: BigButtonStyle, ContentCard and the
  slip's card radius. Left, and why: HomeBedRow, SetRow, HomeChip, HomePill
  and FeatureTile (Q3: home one size smaller, 21 Oct); fields (Q6); retiring
  the old names (Q7); TodayGoalRow (a trailing ring, and WardRow has no
  trailing slot); the Q&A disclosures, transcript lines, attempt rows and the
  narrate bar (not the row role); FeatureTile, ExampleTile and
  ReasoningToolTile as WardTiles (WardTile draws its own card, which would
  cover a PopTile button's press; canon has no tappable tile); WardRoundTile
  (a card of controls); CaseClockPill (minutes used of a budget, which
  WardTimerPill's countdown cannot say); ThinProgress and EcgStrip (already
  WardGroove wrappers; WardProgressBar would colour progress as a score);
  GraphRegionPill and LensChip (documented). Waits for a Mac run: shots of the
  help page, the tour list, Draw from memory, the picture-cards shelf,
  Coverage's counts, review's Undo, a note's source chip and Scripts' slip.

### The owner's answers of 16 Oct: retrieval for proof, and fact chains

The owner asked for advanced retrieval (RAG) and for a layer that turns a
patient story into small facts, each one checkable (D6). The brief, with
acceptance A1-A27 and gates G1-G10 fixed before any change, is
docs/verification/rag-plan.md. The owner's answers to it: deploys "if they
pass then go"; the proposer "its ok"; USPSTF stays out; D6's grade "make it
checked and the human step optional for later as it takes so much money and
effort"; the openFDA key "remind me later after all tasks finish".

Each phase: tools/preflight.sh, its bench against the fixed gates, an
independent review, a merge into personal, then the Worker deploy.
- [ ] T0. The bench first (design/rag-bench, no engine change): proxy mode
  (branch code without a deploy), retrieval set R with mechanical labels,
  the proof-only bench P, and the baseline at 2b7ef11e.
  Built 16 Oct (tools/verification-bench: proxy.mjs, retrieval-set.mjs,
  proof-only.mjs, labels/ with SHA256SUMS; tests in bench.test.mjs).
  Repaired 16 Oct after review (T0054): drugs by the bench's own RxNav and
  openFDA test, the FDA oracle past the first hit (salt-only drugs counted
  apart), MedlinePlus from its full XML, real vignettes (25 MedQA and 25
  MedMCQA case stems), nDCG@5's ideal holds the oracle, runs read the stored
  label inputs, --stub never goes live. An official document exists for 44
  of R-dev's 150 items and 21 of R-test's 90. Samples of 20 (R-dev; R-test):
  official recall@5 micro 16.7%; 16.7%, macro 11.1%; 38.9%; key-document
  recall@5 0 of 2; 0 of 3; label-2 documents outside the oracle 0; 0. P
  proved 0 of 20 (no failed lookups, no false proofs). In independent
  review; then the full R and P runs and the proxy baseline (at most one a
  day). Part B (A9-A14) done; worst-batch CPU fixture measured warm 3.6 ms, cold 78 ms.
- [ ] T1. D0: official recall for proof and a per-source quota in fusion
  (design/official-recall; 0 neurons).
- [ ] T2. D6: fact chains, the vignette route's real proposer generalised
  (design/fact-chain). FACT_PROPOSER stays off until A14-A16 pass, then on.
  A fully proven chain backs Checked; Verified also needs the owner's
  sign-off by content hash, which is optional and later (no sign-off screen
  now, but the hash binding stays).
- [ ] T3. D1-lite and D3: a BM25 filter, then one keyless corrective
  rewrite (design/evidence-filter; 0 neurons).
- [ ] T4. D2: lecture passages per claim, on the device
  (design/lecture-passages). They never back anything.
- T5 (a model reranker) and T6 (a dense leg) only when their triggers fire
  (A26).

### The identity (15 Oct, on design/identity)

The owner asked for a real identity, exam wording instead of ward wording
(they typed "an example"; read as "an exam"), and one detailed ECG line, the
same colour beside the name and in the opening. Docs and boards only; the
app does not change until the owner picks a route. Docs in
docs/design/identity/; the route boards are images kept out of the repo.

- [x] audit.md: what is generic today (pointing at shots/ward-r9) and the
  nine-competitor table.
- [x] palettes.md: the three routes' grounds, inks and mode hues, light and
  dark, with every contrast ratio.
- [x] platform.md: the idea, three traits, audience, never-feel-like, and the
  ECG line's role and colour (one Trace token, equal to the hero).
- [x] routes.md: A Red Pen, B Answer Sheet, C Steel & Silicone, each with why
  it is ownable, its risks and what changes in the app; the shared lockup,
  Trace token, marks and font licences; the recommendation (A, with B's mono
  readouts) and three questions for the owner.
- [x] The dark LaunchLogo is the grey tube on design/launch-anim at
  202825ea; the boards composite both marks from that commit, as they are.
- [x] Review 1 (15 Oct) fixed on all three boards: flat cards (no soft lift),
  no rule across home, chips are ink or the item's own mode hue with status
  shown by form, pencil darkened so text on the grid clears 4.5:1 over its
  bold lines (worst case printed), A's margin note on a plain paper plate.
  A: Pen Red's reason over #D32F45 and the ecgLine note; dark Pen Red is a
  crimson, #FF5D6D. C: rebuilt around steel and silicone (correct is the
  mode's hue, wrong is bare steel), Lilac moved to 302 degrees. The boards
  are re-checked by a new reviewer before the owner sees them.
- [x] wording.md: ward-to-exam glossary and the full string inventory (77
  strings to change, 21 of them asserted by tests, and the ward words that
  stay because they are the content).
- [x] Docs review 1 (15 Oct) fixed in the docs: the soft rim is on buttons
  only (fields and the tab bar are flat); every accent follows the mode (A's
  tick in the mode's ink; B's correct in the mode's hue, wrong in pencil,
  no green or red); C's Plum, Lilac and Raspberry moved apart (342, 298 and
  20 degrees) and steel is exactly neutral; the paper is a 6 pt grid with a
  bold line every 30 pt; fonts reach the Playgrounds build as package
  resources registered at launch, with system fallbacks; the progress
  screen is Progress (Results is taken), the reference is Clinical
  reference; Block/Item clash with USMLE and NBME usage, so the owner picks
  those words; the Playgrounds stand-ins and the Arabic Health text are in
  the inventory; a token map to the code on design/ward-polish; ecgLine is
  planned, not yet pushed.
- [x] One combined board render: the docs-review changes above (flat fields
  and tab bar, B's marking, C's hues and steel) and board review 2's
  must-fixes (the phone frame clears the home indicator; B's "3x" label off
  the clear-space line) and nits (C keeps the letter on its correct and
  wrong rows; the lab flag is ink). Checked at 1:1; all three boards are
  5640 x 8964.
- [ ] A fresh board review, round 3.
- [ ] The owner picks a route, and the words for the timer's parts and the
  plan's count; then a separate phase applies it.

### The exam wording, built (22 Oct, T0125)

The owner's words from wording.md ("3 to do", "make it block") and the copy
deck, on iOS and Android in one change set, one pattern per commit. Strings
only; Arabic is left for the owner's words (copy deck question 4).

- [x] The mock exam's timed parts are "Part n" ("Part n of N" in the
  sitting), from one constant per platform, MockFormat.partWord
  (Shared/Exam/MockPaper.swift; quiz/MockPaper.kt). Owner, 22 Oct.
- [x] The daily plan is "Today's revision": "Start revision", rows "1 ·
  Cardiology" (spoken "Item 1, …"), "3 to do · 22 min", "Nothing due", the
  weak-topic lines and the first run's two lines (wording.md rows 1-4, 8-16,
  64-65; its "items" drift rows now say "to do").
- [x] The timer is a "Focus session" of "Block 1 of 4": its tile, chip,
  panel, captions, alarms, spoken lines, the exam plan's line, the Focus
  filter and the Health settings rows (wording.md rows 32-57). The Live
  Activity (StethoscoreWidgets) and the Health permission text (project.yml,
  Arabic) wait: outside this change, and the Arabic word is the owner's.
- [x] The question screen says "Question 7 of 20", "Next question" and,
  over the stem, "Single best answer"; its chip shows only on a retest,
  "Second try" (wording.md rows 17-20).
- [x] Vitals is "Progress" (title, menu, home tile, "Opens Progress"), its
  weak list "Weak topics" with "Practise weak topics", and the subtitles that
  named it (wording.md rows 5-7, 21-26). The menu's "Progress" now meets its
  Arabic catalogue entry.
- [x] The reference is "Clinical reference": its title, the exam plan's
  row, the study menu's item and a set made from it ("Clinical reference:
  …") (wording.md rows 68-71).
- [x] The new-set flow drops its "New admission" label: the screen is
  already titled "New set" (wording.md row 66).
- [x] Twins' subtitle is "Missed points, asked again" (wording.md row 67;
  Android has no study-category list yet).
- [x] An alert that only tells you something closes with "Done", not "OK"
  (13 on iOS, 7 on Android; the copy deck's majority button). The sign-in
  screen's two go through the catalogue: "Done" is a new key with no Arabic
  yet, so the catalogue check reports it until the owner's Arabic word comes.
- [x] Android's own names give way to iOS's: "New set" and "Save set" on
  the editor, "Look and feel" over the dark-mode switch. "Night shift" and
  the settings rows the deck maps to iOS's backup rows wait (copy deck
  question 6; Android's Import JSON adds sets where iOS's Restore replaces).
- [x] Android's empty home says what iOS's does: "Make your first set" and
  "Add a lecture and Stethoscore turns it into questions or flashcards to
  study." Its "YOUR STUDY WARD" label waits (copy deck question 6), and its
  two buttons keep their words: they load the examples and import a
  library, where iOS's one button makes a new set.
- [x] Android's import and print notices count in the singular for one,
  "Imported 1 set", "(1 page)", through the plural helper iOS uses
  (BedPlan.counted).
- [x] An Android import that fails with no reason of its own says
  "Couldn’t import that file. Check it’s a Stethoscore library and try
  again." (iOS's alert pattern). A failure that carries its own message
  still shows that message, as before.
- [x] The daily plan's button to the exam plan says what it does, "Open
  plan" (copy deck rule d), on both phones.
- [x] The iPad keyboard menu is in sentence case like the rest of the app:
  "Open last set in new window", "Search library", "Review due cards". The
  Playgrounds build's stand-in (tools/playgrounds_stubs/core3/Core3Gaps.swift)
  still says "Review Due Cards".
- [ ] Waiting on the owner (copy deck section 5): the rhythm words
  "Steady", "Patchy", "Resting" (question 3: "Steady" is already the trend
  label; wording.md rows 27-31); Android's "Night shift" and "YOUR STUDY
  WARD" (question 6); the three shorter overlines, "ONE BEST ANSWER",
  "WEAKEST FIRST", "BIGGEST GAIN" (question 9); the Arabic for "Done",
  "Today's revision", "Focus session", "Block" and "Part", and the Health
  permission's Arabic (question 4); and a yes to the spoken "Item 1",
  built as wording.md's glossary has it (question 5).
- [ ] Outside this change set: the Live Activity's words
  (ios/StethoscoreWidgets, wording.md rows 58-61), the Health permission
  text (ios/project.yml, row 62), the iPad build's stand-ins
  (tools/playgrounds_stubs, rows 72-77, plus Core3Gaps.swift's "Review Due
  Cards" and CoreExports.swift's "OK"), and the design tour, which still
  tries "Vitals" before "Progress" (ios/UITests/DesignTourUITests.swift).
- [ ] More than words, so not in this change set: the empty due queue's
  next-due line and "Study something else" (it needs the next due time and
  a new action); Android's "Why / how" (it needs the small-caps component,
  which uppercases, in place of the literal "WHY / HOW"); the model download
  error, whose text is wrapped twice ("Download failed: Something went
  wrong — …"); and iOS's account alert "Something went wrong", which also
  shows failures that are not sign-in.

### The paper frame clear of the system bars (22 Oct, T0127)

The owner's marked Android shot (CI 39812806603, 11-ideas-map, a "Guess
first" sheet): the frame's ring ran through the status bar's time and
icons and along the gesture bar, and cut the sheet's Done. Then: "they
should match each device corner radius".

- [x] The opening stops short of every system bar: each side sits at
  max(frame, bar + half the ring), WardPaper.edge, so the ring's whole width
  is clear of the status bar, the navigation or gesture bar, the Dynamic
  Island, the home indicator and a landscape cut-out (Android
  WindowInsets.safeDrawing; iOS the window's safe area, off home only).
- [x] Its corners are concentric with the display's: WardCorner.concentric
  (radius = device - distance from the edge, floored at the element's own
  minimum), one function per platform. Android reads the display corner
  (getRoundedCorner, API 31+); below 31, when none is reported, and on iOS
  (no public value) it is WardPaper.deviceRadius, the corner the frame was
  drawn for. Top and bottom corners take their own radius (bottomRadius).
- [x] Android pages and the learning sheet sit inside the ring
  (wardFrameClearance: the safe area, sideInset at the sides, the ring's
  width at top and bottom, iOS SkyRoot's padding); the sheet's face still
  fills the window. The 3D map keeps its own layout (T0118's).
- [x] Tests: WardFrameClearTest (Android) and the wardframeclear suite (iOS).
- [ ] The next CI screenshots and the tour are the proof (no emulator or
  Mac here).
- [x] T0127b: the corner elements follow the same rule, WardCorner.radii
  (each corner within a gutter of the frame's corner is concentric with
  it, floored at the element's own radius; at most half its shorter
  side). They measure where they stand against the window's corner frame:
  the ring off home ("clear bars, small top": near the top they take the
  ring's top corner), the screen with the display's corner on home
  (Android WardCornerScope and rememberWardCorners; iOS
  WardEdgeStore.cornerFrame and WardCorners). Wired: the dock's panel and
  Ideas pill and the shared card (Android WardCardFace and WardCard, iOS
  wardCard) on both phones; Android's two study bars
  (square, their bottom corners now follow the ring). Already following
  the ring on iOS: the deck slab and study bar (WardDeckSlab's
  slabTopRadius and the island mask). Capsule buttons (Done, back, More)
  are on the rule and stay capsules: no concentric radius exceeds half
  their height.

### Waiting on the owner

- Deploying the Worker with T0132 attempts 3 and 4 (only the owner is written for; 3.8 Flash, audio on it alone): built and tested here, not deployed.
- The marks on the latest screens.
- What they think of the voice itself, now that it plays.
- Each Worker deploy (the last: 15 Oct, about 8:12 am Cairo, run
  38685298818 from personal at bc611221). Given on 16 Oct for each retrieval
  phase that passes its gates and the independent review.
- After all current tasks: the free openFDA key, as the Worker secret
  OPENFDA_API_KEY (120,000 label lookups a day instead of 1,000 per
  address).

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

Macs
- Use all five macOS runners and never leave one free (owner, 15 Oct,
  8:28 am Cairo: "use all 5 macs don't leave any free to finish faster").
  No stream has a Mac cap. Never cancel a build, test or preview just to
  free a Mac; cancel only a run that a newer push replaces. Keep the next
  useful run queued, so a free Mac starts it at once. Speed comes from
  parallel Macs, never from skipping checks or the independent review.

Git
- Never force-push, and never delete remote branches.
- No pull requests unless asked.
- personal is the working branch; keep the session branch (now
  claude/repo-branch-status-check-4k6js8) equal to it. Build on design/<name> (app-build runs there) and take screenshots
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
  far: deleting remote branches, merging codex-fixes, and curl of the agent
  proxy's status page. Write access to NoNeed2name444/claude-code and push
  to Chat-me were refused too, until the owner attached both repositories
  to this session on 9 Oct at about 7:00 AM.

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
