Temporary evidence for the PTIMER-235 font-scale investigation.
This branch is not to be merged.

Setup: emulator-5554, app 0.9.0-debug from main 8b3b6cdb, 1080x2424
(files downscaled to 1700 px height), en-US. State: Fomapan 100 Classic
(Official FOMA table), base 1/30, ND 10 stops, target shutter 1m, one
running timer.

capped/: normal build (app-wide 1.3 cap active), system font scale
0.85, 1.0, 1.3, 2.0 for Main, Timers, Details.

uncapped/: throwaway local build with the app-wide cap constant raised
to 100 (source change not committed or pushed), system font scale 1.0,
1.3, 2.0 for Main, Timers, Details. main-no-timer_1.0.png is Main at
1.0 with no timer present.

input-screens-capped-2.0/: normal build, system font scale 2.0
(effective 1.3 in app windows). Screens checked: film picker, Shooting
filters, target shutter sheet, overflow menu, rename camera.

capped/ also holds Main, Timers, Details at 1.15 (normal build).
