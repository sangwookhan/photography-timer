# PTIMER-221 paired iOS/Android capture set

Review evidence for the Android Code PR. One directory per scenario,
each holding the iOS reference and the Android result for that scenario.
Supplementary shots of the same scenario are suffixed `-b`, `-c`, `-d`.

**The comparison itself is in [COMPARISON.md](COMPARISON.md)** — one row
per scenario with the observed behavior on each platform, the contract
id, and the classification.

**Not every pair is identically seeded.** The first pass drove each
platform to the same *situation*, not to the same set names, totals and
interaction phase. COMPARISON.md marks every row `SAME SEED`,
`DIFFERENT SEED`, or `RESEED PENDING`. Only a `SAME SEED` row may be read
as visual or transition parity evidence; a `DIFFERENT SEED` row supports
its behavioral claim only. Scenario 22 is Android-only and is not parity
evidence at all.

## Provenance

| | iOS | Android |
| --- | --- | --- |
| build | `main` at `64565f7394fb6d3b00be3655e1b6fb84851c5967` (the merge of the iOS PTIMER-221 PR; also the baseline this Code PR is rebased onto) | `feature/PTIMER-221-android` — see the per-frame build table below |
| device | iPhone 17 simulator, UDID `9144ED16-488D-41F0-B736-3E0564BC6874` | `emulator-5554`, Pixel_10 AVD, API 37 |
| screen | 402 x 874 pt, 3x (1206 x 2622 px) | 411.43 x 923.43 dp, density 420 (2.625 px/dp, 1080 x 2424 px) |
| appearance | light | dark — the app hard-codes `PTimerTheme(darkTheme = true, dynamicColor = false)`, and `cmd uimode night no` does not change it |
| locale | ko-KR | ko-KR, set per-app with `cmd locale set-app-locales com.sangwook.ptimer.debug --locales ko-KR` |
| bundle / package | `com.sangwook.PTimer.dev` | `com.sangwook.ptimer.debug` |
| captured | 2026-09-23 22:43-23:32 KST, plus two retakes 2026-09-24 00:39-01:16 | 2026-09-23 23:39 - 2026-09-24 00:23 KST, re-driven to the iOS seeds 2026-09-24 01:08-02:05 |

### Android frames come from two commits

The Android set was reshot against the iOS seeds after the layout and
localization corrections landed, and one further correction landed
mid-pass, so the frames are not all from one build. They are labelled
rather than averaged:

| build | frames |
| --- | --- |
| `496a4ec4` | `09`, `13`, `13-b`, `15`, `16`, `17`, `18`, `19`, `19-b`, `21`, `28` |
| `120bb559` | `07`, `25`, `26`, `26-b`, `26-c`, `26-d` |
| `79b339c9` | every scenario not listed above, unchanged from the first pass |

`120bb559` changes only how a mixed stack's total is formatted on the
timer card, which is why exactly the timer-card frames were reshot
against it and the rest stay valid. `07` was additionally verified on
`496a4ec4` before that commit landed — same keypad, same input type,
same focus behaviour — so it is cross-checked on both.

Superseded frames are not in the working tree but are not lost: the
first-pass images are in this repository's history, at the commit that
added this directory. The ones replaced were replaced because they
showed the wrong thing — `07` captured the item editor's autofocused
name field instead of a focused choice field, `13` was taken after the
status region's linger had expired, and the rest were driven to
different set names, totals and stack compositions than iOS.

### One incidental difference in the scenario 26 frames

Their shot-sequence badge reads `2` where the iOS references read `1`.
The Android app's data was wiped by a reinstall between passes, so that
camera's counter had already advanced. It is consistent across all four
frames of the sequence and is unrelated to what they demonstrate.

Because the two platforms render in different appearances, **no colour
comparison in the matrix is a measured hue match** — colour differences
are stated as semantic roles (Material error vs iOS orange), not as
pixel values.

## How to read these images

The committed PNGs are **downscaled to 1200 px tall and colour-quantised**
so the set costs about 1.7 MB instead of 12 MB. They are for reading
layout, wording, and ordering. **Do not measure geometry off them** — every
geometric claim in the comparison matrix was measured on the full-size
originals: by pixel-scanning the 3x PNGs on iOS, and from `uiautomator
dump` node `bounds` on Android.

## Scenarios

| id | seeded state |
| --- | --- |
| `01-entry-point` | Any stack; locate the Filter Set management entry in the ND header. Also checked with four wheels, where the Plus control is hidden. |
| `02-management-empty` | No Filter Sets. Management surface opened from the ND header. iOS `-b`: two sets, to show creation order. |
| `03-create-filter-set` | Create-set surface, empty name then `NiSi` typed (`-b`). Opened four times in a row to check that the suggested colour varies. |
| `04-edit-mode-controls` | One Filter Set in the list, at rest and in edit mode (`-b`). |
| `05-editor-fixed-nd1000` | New Fixed item, value `1000`, ND notation; live conversion line. |
| `06-editor-gnd-od` | New GND item, OD `0.9`; calculation-modes section. Android `-b`: the next new item opening with the remembered notation (FILTER-ITEM-007). |
| `07-editor-cpl` | New CPL item with choices `1`, `1.5`, `2`, with **the first choice field focused** so the keyboard on screen is the one that field raises. The first-pass frames captured the autofocused *name* field's QWERTY on both platforms and evidenced nothing; both were reshot. |
| `08-editor-cpl-invalid` | `2.341` typed into a CPL choice; inline validation and disabled save. |
| `09-set-detail-three-items` | One set holding a Fixed, a GND and a CPL item, in registration order. |
| `10-add-immediate-order` | A settled mixed stack, then one Plus add of a source whose group already leads. The frame is taken immediately after the add with nothing else touched. iOS `-b` is mid-animation, iOS `-c` and Android `-b` are the discriminating three-then-four-wheel case. |
| `11-empty-wheel-idle-cleanup` | An unmounted Empty Filter Set wheel left idle past the ~4 s interval. |
| `12-order-after-change` | The wheel added in scenario 10, after it commits an item. |
| `13-fallback-commit` | A drag that traverses at least one selectable row and settles on a row already mounted on the same camera. `-b` is the mid-drag frame with the unavailable candidate at the touch centre. |
| `14-rejection-no-fallback` | A one-row drag whose only traversed row is unavailable. |
| `15-status-idle` / `16-status-moving` / `17-status-rejection` | The three status-region contents over the same mixed stack. |
| `18-gnd-record-only` / `19-gnd-full` | One GND wheel in each calculation mode, same stack, to show the wheel does not move. |
| `20-empty-vs-standard-zero` | A Standard 0 wheel and a Filter Set Empty wheel side by side. |
| `21-cap-no-usable-row` | Total driven to exactly 30 stops, then a Plus add attempted on a source with no row that fits the remaining budget. |
| `22-cap-record-only-addable` | Total at 30 stops with a free wheel slot and an unmounted Record-only GND. Android only: the iOS pass could not construct this state inside the idle interval, so there is no iOS reference. `android-b` is the same wheel after the ordinary idle interval removed it. |
| `23-camera-switch` | Camera 2's independent stack and remembered Plus source, then camera 1 restored (`-b`). |
| `24-after-relaunch` | The same stack after force-stop and relaunch. |
| `25-timer-reference` | A timer started from a mixed stack; primary total line and secondary reference line. |
| `26-timer-reference-after-delete` | The Filter Set behind that running timer renamed (Android `ios`/`android` first frame), then deleted: the confirmation dialog (`-b` iOS / `-c` Android), the collapsed stack (`-c` iOS / `-d` Android), and the timer entry after cancelling (`-d` iOS / `-e` Android). |
| `27-a11y-wheel` | One wheel's accessibility label and value. iOS read from source (the simulator accessibility tree tool was unavailable); Android label read from `uiautomator dump`, value read from source because the dump does not serialise `stateDescription`. |
| `28-a11y-status` | The status region's accessibility structure: leading detail and total as separate elements. |

## Known gaps

- **iOS `22-cap-record-only-addable` is missing.** At 30 stops iOS refuses
  any add, and building the state below the cap and then raising the total
  had to happen inside the 4 s idle interval, which the tooling round-trip
  could not beat.
- **Neither platform was observed with its screen reader speaking.** The
  iOS accessibility tree tool was disabled in this environment and
  enabling VoiceOver would have left the handover simulator in a
  screen-reader state; on Android the values were read from `uiautomator`
  and from source. Both accessibility rows state their source.
- **iOS Plus tap-to-add is untested.** An injected zero-travel tap never
  fires SwiftUI's `DragGesture(minimumDistance: 0)` `onChanged`, so the
  arbiter never leaves its rest state. The browse-drag add and the
  long-press manage paths were both exercised.

This directory is ticket-scoped review evidence and is expected to be
removed before merge.
