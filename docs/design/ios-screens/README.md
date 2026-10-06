# iOS Reference Screen Captures

These are screenshots of the **shipped iOS app**, used as the visual / layout
reference for the Android (PTIMER-146) reimplementation. Where a capture exists
and no approved spec covers the surface, it is the reference for layout and
information architecture (see fidelity tiers below). An approved spec always
takes precedence (see Precedence).

> The repository will be open-sourced. Committed images stay in git history
> permanently and become public when the repo flips to public. These are the
> author's own app screens; do not place anything sensitive here.

## Precedence

These captures were taken on 2026-06-25, before the Filter Set field
workflow (PTIMER-221). They are historical layout references. They do
not override the approved living specification
(`docs/requirements/Requirements.md` and `docs/specs/**`): where a
capture and an approved spec disagree, the spec wins.

The Main wheel row and every filter surface changed after these captures
were taken. That covers the Main header with Select Filters, the mounted
auxiliary summary, Shooting Filters, Filter management, and the item
editor. `main-shooting/wheel-base-nd-*.png` and the filter parts of the
other `main-shooting/` captures therefore show the earlier layout. Their
current behavior and presentation are defined by
`docs/specs/calculator/filter-sets.md`, `docs/specs/calculator/nd-filters.md`,
and `docs/specs/cross-cutting/presentation.md`. No newer captures are
stored here.

## Fidelity tiers

**Tier 1 — clone the iOS layout exactly** (only OS chrome like the X / back `<`
button is adapted to Android idioms):

- `timer-list-fullscreen/`
- `reciprocity-detail/`
- `custom-film-edit/`

**Tier 2 — resemble iOS but adapt to the platform** (optimized together; the
main-screen wheel and bottom-sheet timer list may diverge):

- `main-shooting/`
- `bottom-sheet-timer-list/`

Supporting surfaces: `film-picker/`, `camera-slot/`, `target-shutter/`.

## Capture conventions

- One PNG per **state** (e.g. `empty.png`, `running-multi.png`,
  `film-corrected.png`, `limited-blocked.png`). States matter more than count.
- Portrait orientation (the app is portrait-only). Content only; device frame
  optional.
- **Scrolling screens may be split** into segments. Name them in order with a
  `-N-` index and a position hint, and leave a small **overlap** between
  segments so they can be stitched: `detail-1-top.png`, `detail-2-mid.png`,
  `detail-3-bottom.png`. A single full-height capture is even better when the
  tool supports it.
- Theme: provide whichever theme(s) the app ships (see the open question in the
  task discussion — light only / dark only / both).

## Folder layout

```
docs/design/ios-screens/
  timer-list-fullscreen/
  reciprocity-detail/
  custom-film-edit/
  main-shooting/
  bottom-sheet-timer-list/
  film-picker/
  camera-slot/
  target-shutter/
```
