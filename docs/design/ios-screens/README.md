# iOS Reference Screen Captures

These are screenshots of the **shipped iOS app**, used as the visual / layout
reference for the Android (PTIMER-146) reimplementation. They replace a written
UI spec: where a capture exists, it is the source of truth for layout and
information architecture (see fidelity tiers below).

> The repository will be open-sourced. Committed images stay in git history
> permanently and become public when the repo flips to public. These are the
> author's own app screens; do not place anything sensitive here.

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
