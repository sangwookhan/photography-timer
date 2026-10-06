# PTIMER-221 Android ND-move round raw evidence (2026-10-06)

Reachable only through the tag `evidence/PTIMER-221-android-nd-move-ca4c58e2`;
not part of PR #72's diff.

- `per-commit/nd_and_cN_gradle.log`: `./gradlew :core:test
  :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
  :app:compileDebugAndroidTestKotlin` at each of the six commit trees.
- `final/`: `./gradlew --rerun-tasks` of the same tasks on the head
  `ca4c58e2`, every JUnit XML, and the lint report. Instrumented tests were
  compiled, not run.
- `captures/` (emulator-5554, screenshot plus UI dump): 01-08 camera 1 with
  zero auxiliary filters, ND Holder selected, its ND8 on a wheel (a Plus
  wheel is cleaned within about a second, so the value was picked in the
  same adb command); 09-15 ND8 moved to the Available Empty Holder: the
  wheel left the item, and ordinary empty-wheel cleanup removed the Empty
  wheel because another wheel remained; selected Filter Sets unchanged
  and Empty Holder not selected. 16-17: an edge back gesture closed the
  sheet during setup, not a crash. 18-26: mixed state with a CPL at 1 stop
  and a Record-only GND, ND1000 on an ND Holder wheel, moved to the
  selected 72mm Kit: the same wheel keeps the item, the total stays 15
  stops, the mounts and the selected Filter Sets are unchanged, and a
  relaunch restores the same.
