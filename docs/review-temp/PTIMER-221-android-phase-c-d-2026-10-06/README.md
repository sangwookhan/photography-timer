# PTIMER-221 Android Phase C/D raw evidence (2026-10-06)

Not part of the delivery diff: this commit sits on top of the cleaned
head `a3e38991c1972ea1436ad15a7b51a6bef58c51d4` and is reachable only
through the tag `evidence/PTIMER-221-android-phase-d-a3e38991`.

- `phase-c-per-commit/and_cN_gradle.log`: `./gradlew :core:test
  :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
  :app:compileDebugAndroidTestKotlin` at each restructured commit's tree
  (N = 1..6 in commit order; the final commit trees are identical to the
  built ones). The two `and_c2_*_ATTEMPT_*` logs are the earlier runs of
  commit 2 whose instrumented test sources did not compile; commit 2
  passes the new Shooting Filters callback in those tests
  (`and_c2c_gradle.log`).
- `phase-d/`: `./gradlew --rerun-tasks` of the same tasks on the cleaned
  head, every JUnit XML, and the lint report. Instrumented tests were
  compiled, not run.
