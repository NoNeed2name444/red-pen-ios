# Review U1b: the U1 repairs on ward-nits and ward-island (21 Oct)

Independent review of the repairs that review U1 asked for, read from each
branch's diff and the code it touches. Nothing was built here. Line numbers
are on each branch's tip.

## Verdicts

| Branch | Verdict |
|---|---|
| design/ward-nits (27291c2d, from c3a15712) | **REPAIR**: the preview's re-encode (W-R1), below |
| design/ward-island (d964f9e4, from 79b8baf3) | **ACCEPT**: I-R1 is in exactly as U1 wrote it |

## design/ward-nits: REPAIR

### N-R1 and the nits: match U1

Every changed line matches U1's old and new text:

1. `HomeFit.pushCovered` is inserted at `ios/RedPen/Shared/Learn/HomeFit.swift:86-97`,
   before `isShort`'s comment, with U1's text.
2. `restCut` and `faces` are taken before `resetDropCounts()`
   (`ios/RedPen/Features/Library/LibraryView.swift:268-271`).
3. The `removed`/`lost` lines replace the old test (`LibraryView.swift:284-286`).
4. The new fault text is at `ios/RedPen/Features/Library/WardHome.swift:1034`.
5. The "home covered" line is at `WardHome.swift:1062`.
6. The six homefit checks go before `if failures.isEmpty {`
   (`ios/RedPen/Tests/HomeFitTests.swift:481-500`). No test was changed or removed.

The two nits U1 gave text for are in:

- `_ = publish()` (`ios/RedPen/Shared/Ward/WardPartLedger.swift:134`).
- The report waits up to `0..<400` ticks (`WardHome.swift:1006`). That covers
  the 41.5 s trip and still sits inside the shots script's 60 s wait for
  "push and back: done" (`tools/ward_shots.sh:98-104`, 30 × 2 s).

U1's third nit (one `drop` overload calling the other) had no text and said
"could". It was left alone, which is fine. Nothing else in the diff changes
meaning.

### The timeline (2a): preview-only, bounded, safe

- **Only on the push-back flag, after a trip starts.** `notePushCut` returns at
  once unless `PreviewLaunch.pushBack` is on and `pushStarted` is set
  (`WardHome.swift:985`). `pushStarted` is set in one place: `previewPushBack`,
  after its guard `PreviewLaunch.screen == "library", PreviewLaunch.pushBack`
  (`LibraryView.swift:257, 272`).
- **No new work or side effects in the app.** The call in the cut's `onChange`
  (`LibraryView.swift:532-535`) passes three `@State` reads (`barTop`,
  `pageFrame`, `restTops`; lines 178, 180, 185). This view already touched
  `HomeFitProbe.shared` in the app (`pageEnd`, line 538).
- **Bounded.** At most 40 entries (`WardHome.swift:985`), printed on one report
  line (`WardHome.swift:1065`).
- **Cannot crash or stall the main thread.** `HomeFitProbe` is `@MainActor`
  and not `@Observable` (`WardHome.swift:950-951`), so an append redraws
  nothing. `notePushCut` is synchronous: no waits, no locks, no force unwraps.
  `String(format: "%.2f")` takes Doubles, and a NaN or infinite value just
  prints as text.
- **Two notes, neither a defect.**
  - It keeps recording after the pop, until it has 40 entries. Its comment
    says "from the push on", so the return to rest shows too.
  - It prints the number of booked tops and the first one, not every top. If
    the collapse turns out to need them all, print the list.

### The workflow step (2b): the gates and the skip list hold; the loop does not

- **The gates read the originals: holds.** The fade check reads
  `mode-switch*.mp4` before the push step
  (`.github/workflows/ward-preview.yml:173-200`). The gates after it read only
  `frames-check.txt`, the fade step's output and the `home-fit` text files
  (lines 229-239).
- **A failed re-encode is safe: holds.** ffmpeg writes to a side file. The list
  ends in `rm -f`, so the loop exits 0 under `set -e` (lines 214-217), and `mv`
  is a rename within one directory. ffmpeg comes from the fade step's
  `apt-get` (line 177), and that step must succeed for the push step to run.
- **Nothing left out silently: holds.** After the re-encode, the second `find`
  catches any file of any type over 95 MB. It lists each one in `skipped.txt`
  inside `out/`, and `git add -A` publishes that list (lines 218-226).
- **The defect (W-R1).** The re-encode loop reads `find`'s list from a pipe,
  and ffmpeg also reads standard input while it encodes unless told
  `-nostdin`. So the first ffmpeg swallows the rest of the list. Two cases:
  - **Two recordings over 95 MB** (say `section-switch.mp4` on two devices):
    only the first is re-encoded. The second is deleted and listed, though it
    could have been kept, which defeats the step's purpose.
  - **A `q` in the swallowed text:** ffmpeg takes it as its quit key. It
    stops early, writes a valid but short file and exits 0, so `mv` publishes a
    cut-short recording with nothing in `skipped.txt`. Today's paths mostly
    reach a `c` first (`switch`, `devices`), which opens ffmpeg's command
    prompt and uses up the rest of that line. A path that starts `./quiz-`
    would trip it.

#### W-R1, the exact change

`.github/workflows/ward-preview.yml:215`.
Old: `            ffmpeg -loglevel error -y -i "$f" -c:v libx264 -preset veryfast -crf 30 -an "$f.small.mp4" \`
New: `            ffmpeg -nostdin -loglevel error -y -i "$f" -c:v libx264 -preset veryfast -crf 30 -an "$f.small.mp4" \`

Not required: the publish job has a 10-minute limit (line 151) and nothing
limits ffmpeg's time. A very long re-encode would cancel the job before the
push. The recordings run 6-11 s (`tools/ward_shots.sh:241-242`), so this is
unlikely. `timeout 300 ffmpeg ...` would turn it into a failed re-encode, which
is then left out and listed.

## design/ward-island: ACCEPT

- `ios/RedPen/Shared/Theme.swift:591-595`: U1's new comment,
  `.font(.body.weight(.semibold))` and `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)`
  replace the old three lines. The `inset > 0` fixed 17 pt is gone, so every
  deck gets the same icon.
- `Theme.swift:605`: `.accessibilityShowsLargeContentViewer()` follows
  `.contentShape(Rectangle())`.
- The size limit is set on the label alone. The viewer goes on the band's
  `HStack`, which still sees the real text size, so the viewer comes on at
  accessibility sizes. Nothing else in the code changed.
- **Still open, as U1 set it.** The plan note says the integration preview
  (38938158628) shows the joined stills with no doubled ink; that was not
  checked here. U1's "Island: still to see" items 1 and 3-5 still need the
  island's own Ward preview, with recordings for 3-5. Item 2 is recorded in
  the plan as the owner's call.

## Checks run here

- Both diffs read, with the code they touch: `previewPushBack` and the
  cut's `onChange`, `HomeFitProbe`, the preview workflow's publish job, and
  `ward_shots.sh`'s waits.
- N-R1 and I-R1 compared with U1's text, line by line.
- ffmpeg is not installed in this container, so the stdin case was not run
  here. It follows from ffmpeg's own documentation of `-stdin` and `-nostdin`.
