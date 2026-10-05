# PTIMER-221 Android Phase C/D raw evidence (2026-10-06)

Not part of the delivery diff: this commit sits on top of the cleaned
head `d7640e9e4af6399d99d38959391abacf3de50daf` (after the version-bump
commit was dropped per review 6002283269) and is reachable only through
the tag `evidence/PTIMER-221-android-phase-d-d7640e9e`.

- `phase-c-per-commit/and_cN_gradle.log`: `./gradlew :core:test
  :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
  :app:compileDebugAndroidTestKotlin` at each restructured commit's tree
  (N = 1..5 in commit order). `and_final5_gradle.log` is the rerun on the
  final commit `d7640e9e` itself. The two `and_c2_*_ATTEMPT_*` logs are
  the earlier runs of commit 2, whose instrumented test sources did not
  compile until it passed the new Shooting Filters callback in them.
- `phase-d/`: `./gradlew --rerun-tasks` of the same tasks on `d7640e9e`
  (69 of 69 tasks executed), every JUnit XML, and the lint report.
  Instrumented tests were compiled, not run.
