# PTIMER-239 iOS #94 — review evidence

Evidence for draft PR #94. It is not product documentation, and this branch is not meant to be merged.

- Spec baseline:
  - Captures were taken against #90 at `a71cf4ca`, the revision in force while they were made.
  - The approved revision is now `ba72ce0e`. Its only change is the Android 360x640dp exclusion, which does not affect these iOS captures.
- PR head when collected: `9eb31818`.
- Environment: Xcode 27.1, default text size. Simulators: iPhone 17 on iOS 26.5, and iPhone Duo on iOS 27.1. Reserved regions need iOS 27.1, so only the Duo exercises them.
- The Duo was driven through DeviceHub (fold, posture, rotation).
- Captures were taken while the feature was built. Each was made with the build of the commit that introduced the behavior shown.

| File | What it shows |
|---|---|
| 01 | iPhone 17: the page is pixel-identical to main |
| 02 | iPhone 17: Shooting Filters sheet, main (left) vs new (right). They differ only in the system's Dynamic Island area |
| 03 | Duo outer, portrait: compact timers in the right side area below the status icons, two cards and "+2" |
| 04 | Duo inner, flat, landscape: the rail in the side area and a bounded single column. A flat fold is reported inactive |
| 05 | Duo inner, half-folded, landscape, before the results-column minimum: the page stayed stacked across the fold |
| 06 | Duo inner, half-folded, portrait (tabletop; the red lines are the fold with its system margins): context and results above, inputs below |
| 07 / 08 | Duo inner, half-folded, landscape (book), Korean and English: context and inputs left of the fold, results right |
| 09 | The real `ResultValueRow` at the 335.5pt results side, Dense, with the widest primaries (`≈23:59:59` with `≈86399s`, `≈11mo 29d`), Korean and English. Rendered by a temporary test that was not committed |
| 10 / 11 | Duo outer after folding from inner landscape: before the fix, landscape with the top and bottom cut off; after the fix, it stays portrait (`da0e2887`) |
| 12 | Duo inner, flat, landscape: the Shooting Filters sheet, main (left) vs new (right). Both are width-limited at this size, so the form size request changes nothing visible here |
| 13 / 14 | The Rename sheet with an unsaved draft on the inner display; after folding, the outer display (portrait) keeps the sheet, the draft and its Cancel/Save buttons |
| 15 | iPad Air 11-inch (M4), iPadOS 26.5: the app runs in iPhone compatibility mode (`TARGETED_DEVICE_FAMILY = 1`) as an iPhone-sized window. All required shooting UI is visible |
| 16 / 17 | iPad compatibility window: in the Target Shutter sheet the lower half of Cancel/Confirm is cut by the window's bottom edge, both on this branch (16) and on main (17). It is not introduced here; Cancel still works |
| 18 | iPad compatibility window: the Shooting Filters sheet opens with Cancel/Apply at the top, and closes with Cancel |
| 19–22 | iPhone 17 (iOS 26.5), hardware keyboard off: Rename shows the software keyboard, and the sheet keeps the field and Cancel/Save above it (19). A typed draft (20) is discarded by Cancel (21). A typed draft is applied by Save (22). The name was restored afterwards |

Captures 15–18 are over 1MB at full resolution. Each has a smaller copy, `*_app-window-crop_*.png` (under 200KB): the iPad app window cropped from the original and scaled to 820px wide. The originals are kept.

`test-log.txt`: app-hosted layout tests, PTimerKit package tests and per-commit build at the head.
