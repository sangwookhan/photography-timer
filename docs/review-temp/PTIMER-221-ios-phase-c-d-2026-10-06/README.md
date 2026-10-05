# PTIMER-221 iOS Phase C/D raw evidence (2026-10-06)

Not part of the delivery diff: this commit sits on top of the cleaned
head `ed68a47da8763016c20948996d75207eaa1f263c` and is reachable only
through the tag `evidence/PTIMER-221-ios-phase-d-ed68a47d`.

- `phase-c-per-commit/iosclean_cN_*`: at each restructured commit's tree
  (N = 1..5 in commit order; the final commit trees are identical to the
  built ones): `swift test --package-path ios/PTimerKit`, `xcodebuild
  build-for-testing` of the PTimer scheme from empty derived data for
  the iPhone 17 simulator, and swiftlint outside `.build`. The two
  `*_STALE_DERIVED_DATA_*` logs are the first attempts for commits 1 and
  2, which reused derived data built from the final tree and failed on
  stale modules; the clean rebuilds pass.
- `phase-d/`: on the cleaned head, `swift test`, the PTimer test plan on
  the iPhone 17 simulator 9144ED16 (`-parallel-testing-enabled NO`) with
  its result bundle, and swiftlint.
