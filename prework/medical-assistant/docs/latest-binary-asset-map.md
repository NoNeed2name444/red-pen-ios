# Latest native repository binary assets

Source: `NoNeed2name444/red-pen-ios`, branch `preview/cursor-neuron-circuit-perf-d39a`, commit `faecd8cdccd92387ac777335588ebc548b0ab106`, tree `acf6214ba7ae6654d90a7b0b6e2c841af7494edf`. The checkout is `/workspace/git-repositories/red-pen-ios`. All listed outer files were read locally; their byte counts and Git blob IDs match `repository-read-inventory.json`.

## Images

All six PNGs were opened for visual inspection.

| Path | Bytes | Git blob | Inspection |
|---|---:|---|---|
| `design/icon/preview.png` | 1,119,200 | `8d842ff262350232a478bbba5db99d57eaf5b3a0` | 1024×1024 app icon preview: blue rounded-square field, stethoscope, A+ badge |
| `design/icon/source.png` | 1,288,455 | `1332d68ae320d4d199bcd355856a95ceaf75c832` | 1254×1254 source artwork with white margin and same icon |
| `ios/RedPen/Assets.xcassets/AppIcon.appiconset/icon-1024.png` | 977,544 | `93279b2ba8ad287dce1dcac28c95c4df307a9753` | 1024×1024 icon artwork |
| `ios/RedPen/Assets.xcassets/LaunchLogo.imageset/launch-logo@1x.png` | 45,429 | `15d2aebf164bb98fc84d8c4d25416a9634f910f4` | Dark background lockup, icon, “Stethoscore”, “LISTEN · LEARN · SCORE” |
| `ios/RedPen/Assets.xcassets/LaunchLogo.imageset/launch-logo@2x.png` | 132,740 | `182da8f97bac5415814bad5888b699086b4c7c89` | Same launch logo at 2× resolution |
| `ios/RedPen/Assets.xcassets/LaunchLogo.imageset/launch-logo@3x.png` | 217,536 | `607670af899b75e892aff39cd869eb87c6cc9ba1` | Same launch logo at 3× resolution |

## Archive and compression fixtures

| Path | Bytes | Git blob | Read/inspection coverage |
|---|---:|---|---|
| `ios/RedPen/Tests/Fixtures/anki-latest.apkg` | 15,454 | `783aee12ccd4b2a93bade95083f1c9d6344b8deb` | Read every ZIP member. Decompressed `collection.anki21b` (6,728 → 143,360 bytes, SHA-256 `9bd8850b0bd473e75b4ab06acf8b8ed0b60b2fe5f58401296eae5e0e86dea175`) into SQLite read-only; read the table contents and all six note field strings, inspected nine card rows, deck names, table and field names, and config values. There are six notes, nine cards, four decks, five note types, and no review log/graves. SQLite schema includes `cards`, `col`, `config`, `deck_config`, `decks`, `fields`, `graves`, `notes`, `notetypes`, `revlog`, `tags`, and `templates`. `collection.anki2` and `collection.anki21b` both read; `meta` bytes read. |
| `ios/RedPen/Tests/Fixtures/anki-latest.colpkg` | 18,817 | `64aa99e0b21361aaabbcec7002d04c160162a465` | Read every ZIP member. Decompressed `collection.anki21b` (10,106 → 159,744 bytes, SHA-256 `8a56539da509eb5d5d82e0db002da853243e3d0f5a34c7a0a5d29c4b5b2af212`) into SQLite read-only; read table contents and all six note field strings/nine cards. The modern schema also has `fields`, `templates`, and package metadata rows. Metadata, collection, and embedded media bytes were read; media map was parsed. |
| `ios/RedPen/Tests/Fixtures/anki-legacy.apkg` | 20,722 | `3509b34255bed6677f40441a6781884ea6135c67` | Read every ZIP member, including both SQLite files, all four media files, and media map. Inspected every collection table and row, including all six note field strings and nine card rows; extracted and visually opened three PNGs; read full SVG member as text. |
| `ios/RedPen/Tests/Fixtures/zip64.zip` | 271 | `f9b357c31b1181b25df1a3718d0ae29bed3c742a` | Listed and read both ZIP members (`media.txt`, 600 bytes; `b.txt`, 6 bytes), including full text content. |
| `ios/RedPen/Tests/Fixtures/zstd-binary-1.zst` | 2,071 | `b64b9745a43428e3926a02932f07076703de83bb` | Full decompression succeeded: 90,000 output bytes consumed; non-UTF-8 payload. Decompressed SHA-256 `a6cd8816a6191d7e0a50d7ea267103c1e30d1c8ce2b29ec45b429f067b633b88`. |
| `ios/RedPen/Tests/Fixtures/zstd-mixed-3.zst` | 7,844 | `96e8ef37d0866e2ecbec408187b971ff75c35228` | Full decompression succeeded: 24,150 output bytes consumed; mixed non-UTF-8 payload. Decompressed SHA-256 `2c3fe3433ee3b64dcdfe185a487dfeb7c51481dc761eb5ca5993a2a6cd7c482f`. |
| `ios/RedPen/Tests/Fixtures/zstd-text-19.zst` | 20,409 | `840b482e5718c2c351d876db610128636a61a6d0` | Full decompression and UTF-8 decoding succeeded: 190,172 characters, one line, all content read. Decompressed SHA-256 `03d81d0a04ed76a2915459865a8fb29c26c79d8ef3e9a4225f6751f480227b09`. |

## Acquisition notes

The connector initially rejected the binary blobs as non-UTF-8. Pinned, shallow Git checkouts later supplied all 13 latest-branch and 11 default-branch files; each checkout’s Git blob IDs and sizes match the inventory entries. The default-branch snapshot below was visually inspected at commit `9eb54309c5edd879b11ce5fa722a972e1652859b` (tree `bacceb01a23a4f1e0605a99f7be8555a8551b90b`).

In the modern Anki SQLite files, all tables and rows were read. Every note row’s full `flds` content was examined: the fixtures contain text and markup, tags, cloze text, image occlusion fields, and references to embedded media. Small text/blob config cells were read; some binary protobuf config cells were identified by stored type and size, but not decoded into semantic fields. The package media maps and media bytes were read, and the legacy package’s PNGs were opened visually. This is the remaining content-interpretation limit for the Anki fixture databases.

## Default-branch PNG assets

All 11 PNGs were opened for visual inspection.

| Path | Bytes | Git blob | Inspection |
|---|---:|---|---|
| `design/icon/background-dark.png` | 5,502 | `9c2b3a7ad101197c4e0b3302c13d147d477de072` | Solid dark red square background |
| `design/icon/background.png` | 5,528 | `b7851c50dbfee070ad288fe256d44a2d5f968239` | Solid bright red square background |
| `design/icon/clear-dark.png` | 74,315 | `8e87fa540b31c57d3189a2b1aed8f777327e654f` | White rounded document with four grey lines on transparency |
| `design/icon/clear-light.png` | 53,732 | `559695831c3c9a682b0dffde930495e289a84b96` | Black rounded document with four grey lines on transparency |
| `design/icon/foreground-tinted.png` | 74,315 | `8e87fa540b31c57d3189a2b1aed8f777327e654f` | Exact same bytes as `clear-dark.png`, verified by Git blob ID |
| `design/icon/foreground.png` | 74,313 | `5e0d81fc930c15ea0750599f810494274de08761` | White rounded document with three grey lines and a blue bottom line |
| `design/icon/preview-dark.png` | 63,401 | `de72c369374d5f988528384c4b9aa43efac3262e` | White document mark on dark grey background |
| `design/icon/preview.png` | 75,000 | `2131dca1b7e1aa8099dab42793d3f70530fcbacb` | White document mark on red background |
| `ios/RedPen/Assets.xcassets/AppIcon.appiconset/icon-1024-dark.png` | 54,793 | `73d60f566e386daa7e92e8120195829f236c5df3` | White document glyph on dark red rounded square |
| `ios/RedPen/Assets.xcassets/AppIcon.appiconset/icon-1024-tinted.png` | 51,564 | `5575ad8e224f103fc8220e97a56ea49a636a56a1` | Dark glyph with light-blue accent on transparency |
| `ios/RedPen/Assets.xcassets/AppIcon.appiconset/icon-1024.png` | 65,562 | `6cc07f9d00a8697338db5b7e808ff31c31fed5a8` | White document glyph centered on bright red rounded square |
