# PTIMER-230 Android #93 — review evidence

Evidence for draft PR #93. It is not product documentation, and this branch is not meant to be merged.

- Spec: #90 at `a71cf4ca`.
- PR head when collected: `54676280`.
- All captures use font_scale 1.0 on API 37 emulators:
  - Fold8 substitute AVD: cover 1248x1972px, inner 2448x1848px, 420dpi.
  - Pixel 10.
- "Busy" is the seeded heavy state: a film with a model choice, Target Shutter, 3 filter wheels with auxiliaries, and 4 timers.
- Captures were taken while the feature was built. Each was made with the build of the commit that introduced the behavior shown. Later commits did not change that behavior, apart from the film row moving into the header (from `fa93329d`).

| File | What it shows |
|---|---|
| 01 / 02 | Removing the last timer: main moves the header down 58dp, the fix keeps it (`f84860ae`) |
| 03 / 04 / 05 | Fold8 cover, busy: side rail chosen; frames from a rail tap straight to full Timers; X returns to the rail |
| 06 | Fold8 inner flat: inputs and results side by side, film row across the top |
| 07 | Pixel 10 busy: bottom strip as before |
| 08 / 09 | Full Timers covers the whole window: cover with two records; inner with the list centered |
| 10 / 11 | Book (hinge 90; the red line is the reported fold): strip right, dots left; full Timers right of the fold |
| 12 / 13 | Tabletop: default page with context and results above the fold; busy page left stacked across the fold (open #90 question), with full Timers above the fold |
| 14 / 15 / 16 | Bounded task card on the flat inner display, right of the fold in book, full screen on the cover |
| 17 / 18 | Folding keeps Shooting Filters and its refusal notice; a density recreation reopens it |
| 19 | Density 420 → 440 → 420: full Timers stays open on the focused timer (`54676280`) |
| 20 | 360x640dp busy: the existing page scroll path (open #90 question) |

`test-log.txt`: unit tests, lint and per-commit compile at the head.
