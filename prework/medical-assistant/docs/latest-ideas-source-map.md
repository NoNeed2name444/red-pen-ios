# Latest native Ideas graph source map

Pinned source: `red-pen-ios` at commit `faecd8cdccd92387ac777335588ebc548b0ab106` (`/workspace/repositories/red-pen-ios-latest`). Scope is the complete `ios/RedPen/Features/Notes/` tree: 62 Swift files, 1,294,321 bytes. Every file was read through EOF in consecutive ranges (for the longest files, ranges were tracked in `/tmp/latest-ideas-read-state.json`). This map records the source-defined contracts and per-file coverage; it does not reproduce source code. Final byte lengths and SHA256 values below were rechecked against the materialized tree.

## Source-defined Ideas and graph contracts

`IdeasView.swift`, `IdeasBottomBar.swift`, `IdeaBoardView.swift`, `NoteEditorView.swift`, `NoteMarkdown.swift`, `NotesShared.swift`, `IdeaTools.swift`, and `NoteExamples.swift` define the note capture, list/board/space modes, editor, board placement/connect behavior, link syntax, and note/card transformation. List mode captures into the current folder; board and space capture at the root. Board coordinates persist on notes while camera pan/zoom state is transient. The editor autosaves after a short debounce and on close, resolves wiki links and supports linking/creating pages, and supports card conversion.

`GraphTouchModel.swift` defines touch classification and selection events/effects. The thresholds are 0.25 s to turn a body hold into a drag, 0.55 s for a stationary options menu, 10 pt movement slop, and a 0.30 s / 40 pt double-tap pairing window. Selection feeds peek cards, open, link focus, and options. `GraphMapPanels.swift` defines the peek card, link/folder pickers, node menu, and link-length control. `Graph3DView.swift`, `GraphMotion.swift`, and `GraphNodeFactory.swift` connect those contracts to SceneKit nodes, camera, selection, filters, links, animation and accessibility. GraphMotion owns the shared render loop: spring motion for ordinary map bodies, parent-first orbit updates for hierarchical themes, filtering/ghosts, node/link pop transitions, drag release velocity, shader time, dynamic label styling, and deleted-body departures.

`GraphTheme.swift`, `GraphThemePlan` (in `GraphThemePlan.swift`), and `GraphThemeScene.swift` define the shared theme interface and plan-to-scene adapter. Space/Universe and Performance use their dedicated builders; Neurons and Circuit expose deterministic `ThemePlan` values consumed by the shared scene. The shared data contracts include bodies, links, envelopes, systems, regions, and optional patches/bars/feeds. Theme looks supply body nodes, link materials, backdrop, camera lens, optional link board/arbor, decoration, and per-frame ticker.

`GraphUniverse.swift`, `GraphSpaceOptics.swift`, `GraphNodeStyles.swift`, `GraphStyleAnimator.swift`, and `GraphStyleShaders.swift` define the Space/Universe hierarchy, roles, orbits and shared style inputs. `GraphUniverse` derives folder/note roles and positions deterministically from note hierarchy and links; `GraphMotion` keeps the parent-relative offsets and carries parent movement to descendants. `GraphNodeStyles` defines individual body styles and persisted global/per-folder choices. `GraphStyleAnimator` updates per-style pieces, lighting, tails, and selection orbit. `GraphFraming.swift` packs disconnected groups, turns the points by principal spread axes, and fits the graph to the available view window.

`GraphNeurons.swift`, `GraphNeuronStates.swift`, `GraphNeuronLook.swift`, and `GraphNeuronShaders.swift` define Neurons roles, geometry, stored cell-state overrides, material/shader inputs, and impulse ticker. `GraphCircuit.swift`, `GraphCircuitDress.swift`, `GraphCircuitLook.swift`, and `GraphCircuitShaders.swift` define Circuit roles and deterministic board planning, dress mappings, board/part rendering and the trace/current shader inputs. `GraphLinkCurve.swift` provides shared curve/routing math; `GraphRibbons.swift` samples those paths into link strips and reuses GPU buffers; `GraphFrameSync.swift` synchronizes render state; `GraphLineStyle.swift` defines the shared straight/curved setting.

`GraphPerf*` files define the separate large-map Performance renderer: source graph representation, seeded layout, cluster and LOD states, picking, camera gestures, shaders, GPU renderer, synthetic demo, and its map view. This surface has separate renderer mechanics while it uses the shared Ideas commands and theme-facing UI contracts.

`GraphDeath.swift` and `GraphDeathScene.swift` define removal transitions. A scene rebuild identifies removed bodies, keeps cloned nodes unpickable, animates their links and effect, and removes them after completion; full effects are bounded by the graphics tier. `GraphLabelContrast.swift` defines estimated per-label backdrop color, WCAG contrast selection, hysteresis and easing. `GraphLegend.swift` defines theme-specific legend and first-run/empty-state hints. `GraphPreview.swift` supplies launch-argument fixtures and preview interactions using temporary stores. `GraphLook.swift`, `GraphSpaceShaders.swift`, `GraphShaderKit.swift`, `GraphShaderCatalog.swift`, and `GraphNodeShaders.swift` contain inline shader sources, generated artwork and shader support/probe contracts; there are no separate shader source assets in this Notes directory.

## Full-read coverage

All rows are from the pinned materialized tree and have `full_read` status. The SHA256 column fingerprints the exact local UTF-8 file bytes.

| Path | Bytes | Lines | SHA256 |
|---|---:|---:|---|
| `ios/RedPen/Features/Notes/ForceLayout3D.swift` | 6100 | 149 | `a12943142f40eb57ecd4fd1de23a7137d0d4f5980b9f106e836bff8f776a2582` |
| `ios/RedPen/Features/Notes/Graph3DView.swift` | 123282 | 2572 | `5febf8e7b2553250e034a9d7bc684120c4a324cc7ce4fe86243fa2f9b7ded931` |
| `ios/RedPen/Features/Notes/GraphCircuit.swift` | 49916 | 1144 | `a7e55b19e56a47b7cefe34e9ba448de79395e528bbf2cff9a6c6d97911c73e60` |
| `ios/RedPen/Features/Notes/GraphCircuitDress.swift` | 3820 | 93 | `4bde1414283347f79decddc13dea16f7677d5c223dc0800169c818d7213c82b2` |
| `ios/RedPen/Features/Notes/GraphCircuitLook.swift` | 43114 | 917 | `31dadd3ec0253e8022e96ef6439d5c0088811b4e0c4054a2cf9d1e8bbb7f14ab` |
| `ios/RedPen/Features/Notes/GraphCircuitShaders.swift` | 21773 | 446 | `48d1d127ae70e65ccb773d7ded9ac8d8b32c102dae7901ef32c586919693cce2` |
| `ios/RedPen/Features/Notes/GraphDeath.swift` | 14578 | 336 | `d108fe37856f8aaba1b9d666d35fec506261d7036654cd54b9e39f2a4ca1504a` |
| `ios/RedPen/Features/Notes/GraphDeathScene.swift` | 30735 | 607 | `52df78ffb685aea0dfa178a9c531320a1a7ae1a7d3188a33001d1a0cd96bf47d` |
| `ios/RedPen/Features/Notes/GraphFrameSync.swift` | 4647 | 105 | `c39d1b1f6415a2156108e9efff9ad8e82f93de727c00a14bacf8ca88483824eb` |
| `ios/RedPen/Features/Notes/GraphFraming.swift` | 14349 | 328 | `923ca1a0086ffb78de3ae3bc76fc71ea0e23b7fd86881c49a24622d65a53c90f` |
| `ios/RedPen/Features/Notes/GraphLabelContrast.swift` | 23425 | 520 | `b4df76da592d6225941db0f48b38f00c49c50bee1624752d33054f1310e2076a` |
| `ios/RedPen/Features/Notes/GraphLegend.swift` | 28234 | 488 | `20086e363f307946ab4d0338b3325aa10bf8ceeda709e8728f4bb15046c5b35e` |
| `ios/RedPen/Features/Notes/GraphLens.swift` | 3289 | 79 | `ea1f0e445bcd069579c07be901448bc2a085bb76e43eebcbb912b0c9046972a7` |
| `ios/RedPen/Features/Notes/GraphLineStyle.swift` | 12637 | 303 | `2bcebef96d5cb0c4cbafa7b653bb446eadc03ccc05975f279c3c48f7b4afd283` |
| `ios/RedPen/Features/Notes/GraphLinkCurve.swift` | 17301 | 409 | `10da694c9e8c385c5e48f4dcbdf4f9e3cf28e5d5994ac0cb020029f0740f2bc3` |
| `ios/RedPen/Features/Notes/GraphLook.swift` | 44490 | 978 | `33a73284130ff05552d283e515d16c5beff0791d7b01339aa5d5cd2179ddd32a` |
| `ios/RedPen/Features/Notes/GraphMapPanels.swift` | 14355 | 406 | `f429a64911bc67c1624c31ea837d738a8223ded1de2266eea0f7b05bfc183014` |
| `ios/RedPen/Features/Notes/GraphMotion.swift` | 91208 | 2059 | `4e95a6e068badcfa4e145bb21015e5a6d0242a14f71c1120eddd0bc9a19b1dd0` |
| `ios/RedPen/Features/Notes/GraphNeuronImpulses.swift` | 5395 | 127 | `d8312506731b7da41ae5db9ebb413aa66d9d84354585a26707d21e7f860b7493` |
| `ios/RedPen/Features/Notes/GraphNeuronLook.swift` | 51129 | 1074 | `c9147b8e7931e6be2da9b36bae634b6c5e5a12500c3e9ee24a4b81ce30ff7e43` |
| `ios/RedPen/Features/Notes/GraphNeuronShaders.swift` | 25526 | 537 | `0d1a7c4eca3be988f724b4e6e267f9fd9ebd866361f80471d6a5459124792a47` |
| `ios/RedPen/Features/Notes/GraphNeuronStates.swift` | 11925 | 281 | `ed070ea4fe4a1d8c0619b06f7d4bc7c3d4a397cbc1d01f79a8f6c4de29887914` |
| `ios/RedPen/Features/Notes/GraphNeurons.swift` | 30992 | 712 | `4e19bc4f3a8713b736bf75b7d707fdb4d569d1f2b9cda1b35708be2e485fbf6e` |
| `ios/RedPen/Features/Notes/GraphNodeFactory.swift` | 38843 | 881 | `22066b121b9bbeb371c8dbebe77db8a1569eba790c76172bddaf67c31e12b8f2` |
| `ios/RedPen/Features/Notes/GraphNodeShaders.swift` | 8071 | 178 | `63d2d2e05ce26151efe6ec04d3fd0df4360d48138b4549323a74e7d56d85326d` |
| `ios/RedPen/Features/Notes/GraphNodeStyles.swift` | 11238 | 265 | `233f51f32daf4a1fd4d1c53bfae295537f2404c96b67a135fd17d90133fd3a67` |
| `ios/RedPen/Features/Notes/GraphPerfAdapter.swift` | 1986 | 46 | `cb8d57e0a79e70f2d2f8d06f150c2bb1c86d2d2012c12637cbf05042a9e91866` |
| `ios/RedPen/Features/Notes/GraphPerfCamera.swift` | 9842 | 227 | `27c07171b9472193509d333897c5c8c82f4f58c3a1835251573d0e18b62d1a74` |
| `ios/RedPen/Features/Notes/GraphPerfClusters.swift` | 14533 | 339 | `de82ee4874c14e0017947e1a80d76128b4587bbfd3deaecf43e946dfa8c67cd2` |
| `ios/RedPen/Features/Notes/GraphPerfForce.swift` | 19538 | 452 | `ff1c25f672573484e7c3a3941f3403d288785eb34b7f98d3796a314054144c4d` |
| `ios/RedPen/Features/Notes/GraphPerfGraph.swift` | 19502 | 434 | `3c3740347fdd3d7f6763e6de58886bc6bdcbddfe281d64ec55e2ed05fc4bf185` |
| `ios/RedPen/Features/Notes/GraphPerfLOD.swift` | 6991 | 168 | `80d5fc5dd6dcff40a381f5159c3450627058b18d63fc8c747df379bfdfa0b745` |
| `ios/RedPen/Features/Notes/GraphPerfLayout.swift` | 11617 | 247 | `63bee9b52267c66b93290bb44037c4f7a12c047ee6352ad317278887c0fef207` |
| `ios/RedPen/Features/Notes/GraphPerfMapView.swift` | 16555 | 408 | `b6a4a6b988462d1e0caff2c36fade3b29a27c81af1126055d239ecf5e6db4da6` |
| `ios/RedPen/Features/Notes/GraphPerfPick.swift` | 13649 | 294 | `20daf34b715b3e27fd5ecb9605e0aecbb4f6816c5c20a0a9474e6dd78cb7d0d0` |
| `ios/RedPen/Features/Notes/GraphPerfRenderer.swift` | 18790 | 410 | `9ff5d378f02912d9280ce2ceb4e7b1d6160e72fb5d98d7483a598fd189d8fb6c` |
| `ios/RedPen/Features/Notes/GraphPerfScene.swift` | 8961 | 202 | `1e8cb81d8266a2e6f171a8351bd97fdcf3b6673a9a0abc1fb2dbc6abf2cfc912` |
| `ios/RedPen/Features/Notes/GraphPerfShaders.swift` | 12220 | 288 | `e3ed1992fcdfdadfd2c16763e40035fe4679c6b360a2fe9027c2cb0841f497db` |
| `ios/RedPen/Features/Notes/GraphPerfSynthetic.swift` | 7337 | 163 | `d808a44acc7ebe5b3fc6bd79c17a736c8836339cbdae8160cd056d761cfe0a08` |
| `ios/RedPen/Features/Notes/GraphPerfTheme.swift` | 11328 | 315 | `f1c3f7b7a92c6945c1b87ac776aff84d7ee7653012d5c8cccf10e0dc4ceec566` |
| `ios/RedPen/Features/Notes/GraphPreview.swift` | 18585 | 339 | `7d2d7b4437e19b9a6fdd04ac23b94f5cc5abf0ed089faeb98e54e1bfc11164ae` |
| `ios/RedPen/Features/Notes/GraphRibbons.swift` | 29516 | 621 | `e09a7112da132a027c4efe7fe0d8222025f1fe5df779661cc67635df1874311f` |
| `ios/RedPen/Features/Notes/GraphShaderCatalog.swift` | 3841 | 82 | `3cc552d7e0e719442e9cde01bb34e918458050095b06b45c3b545b7240b9ed6f` |
| `ios/RedPen/Features/Notes/GraphShaderKit.swift` | 4470 | 103 | `3a49151bd10752e7b9f1cc09b59079f773d9ef9aba0cb73cc78566ffc6cc32e2` |
| `ios/RedPen/Features/Notes/GraphSpaceOptics.swift` | 16068 | 360 | `9df6c731d3c82e58c2e919dfe0111938feb112096bf5f6a0bcc0223c54e6b4ba` |
| `ios/RedPen/Features/Notes/GraphSpaceShaders.swift` | 64684 | 1375 | `1dc769cfb5932e9476e31ffee62b4d9541794a688e9093e01726ce070bc2276f` |
| `ios/RedPen/Features/Notes/GraphStyleAnimator.swift` | 31492 | 647 | `cb0cbe8d434faf8b3b156155c55942896b5ba8cdd3c2f71c1f4c428f192d52e4` |
| `ios/RedPen/Features/Notes/GraphSynapse.swift` | 7485 | 163 | `564b3277330b65e6eb567e671f2793440c1d6a42948ff82db5d4b2fab5ba1f25` |
| `ios/RedPen/Features/Notes/GraphTheme.swift` | 7793 | 174 | `49bcd2b67cb53817f59b5f3f649002f5e395614f3dcd0d9fa9ef07f0434542a0` |
| `ios/RedPen/Features/Notes/GraphThemePlan.swift` | 10305 | 247 | `c658400234f0f23197cbfab0b5c8748014d7cbefe3a7e765145e5ef93051f425` |
| `ios/RedPen/Features/Notes/GraphThemeScene.swift` | 15584 | 338 | `826dc2a062f24a08a108ac2045c4421b4b42b17f8d553a564f0dcf49936428b9` |
| `ios/RedPen/Features/Notes/GraphTouchModel.swift` | 15881 | 391 | `89b35e98c0ae6f8c350ccd75e1430854e5f9fc6ef8ce68292eae832595dc9c68` |
| `ios/RedPen/Features/Notes/GraphUniverse.swift` | 62463 | 1518 | `50f97a5ee6a0edc086d5373b30a5aa5592d861c67b45d9129276d12aa04c3531` |
| `ios/RedPen/Features/Notes/GraphUniverseScene.swift` | 20309 | 406 | `458ecbf9382e06221cbff0d63459f95fc62521653573ab727641022eec5ff98a` |
| `ios/RedPen/Features/Notes/IdeaBoardView.swift` | 14406 | 346 | `e006bb33c60e965a69be1ee049e6cc1ec55bea2ac3bccd3373dea60e995933f4` |
| `ios/RedPen/Features/Notes/IdeaTools.swift` | 5954 | 172 | `e1af670fbacf70b163eb65e22e00606ca97a998e2e749ccde738f6be4a8acca1` |
| `ios/RedPen/Features/Notes/IdeasBottomBar.swift` | 6584 | 186 | `5572388895f9a738a156938eb9ec97bb0d1c6a23c3d56820a8e81165181be903` |
| `ios/RedPen/Features/Notes/IdeasView.swift` | 15632 | 410 | `8172a1892b27941e665ca037ad0947a650384c51b6bed716ed9a5e571a3ded5c` |
| `ios/RedPen/Features/Notes/NoteEditorView.swift` | 22269 | 600 | `040a1f36fb1a452c8f6790d60373b7c39682838d84b2f32125ee810f4309956d` |
| `ios/RedPen/Features/Notes/NoteExamples.swift` | 6076 | 119 | `e62b424cd558bcf20094ccd4e11f0056f33bcc5e4b631b17a824c98bc1ad27fc` |
| `ios/RedPen/Features/Notes/NoteMarkdown.swift` | 7487 | 181 | `02ffeee3548393560835db97d1ef66d9fa5d2db79c867fd238271f8acb7e4379` |
| `ios/RedPen/Features/Notes/NotesShared.swift` | 4216 | 105 | `fa727604ca763979a78c9b0ca5b7917d67aa1a5c04d4fa306e3f17263f4e8911` |

Coverage total: **62 / 62 files**, **1,294,321 / 1,294,321 bytes**. No UTF-8 source file in the scoped tree was excluded. The tracker retains cumulative range-read notes for larger files at `/tmp/latest-ideas-read-state.json`.
