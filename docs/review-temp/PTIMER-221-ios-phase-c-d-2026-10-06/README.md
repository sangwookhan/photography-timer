# PTIMER-221 iOS Phase C/D raw evidence (2026-10-06)

Not part of the delivery diff: this commit sits on top of the cleaned
head `1882e1af5812efb3f6638bb948cd07fd8f287b9a` (the version-bump
message amended per review 6002310628; tree unchanged from `ed68a47d`)
and is reachable only through the tag
`evidence/PTIMER-221-ios-phase-d-1882e1af`.

- `phase-c-per-commit/iosclean_cN_*`: at each restructured commit's tree
  (N = 1..5 in commit order; commit 5's tree is the head's tree):
  `swift test --package-path ios/PTimerKit`, `xcodebuild
  build-for-testing` of the PTimer scheme from empty derived data for
  the iPhone 17 simulator (compilation only), and swiftlint outside
  `.build`. The two `*_STALE_DERIVED_DATA_*` logs are the first attempts
  for commits 1 and 2, which reused derived data built from the final
  tree and failed on stale modules; the clean rebuilds pass.
- `phase-d/`: on `1882e1af`, `swift test`, the PTimer test plan executed
  on the iPhone 17 simulator 9144ED16 (`-parallel-testing-enabled NO`)
  with its result bundle, and swiftlint.
