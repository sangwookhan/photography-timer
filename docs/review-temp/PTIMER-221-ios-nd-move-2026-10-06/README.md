# PTIMER-221 iOS ND-move round raw evidence (2026-10-06)

Reachable only through the tag `evidence/PTIMER-221-ios-nd-move-739a6bdc`;
not part of PR #71's diff.

- `per-commit/nd_ios_cN_*`: for each of the four commits (trees
  d1a04ded, 2acb7ea0, 8a8ebeea, 9b993f4d), `swift test`, `xcodebuild
  build-for-testing` from empty derived data, and swiftlint. Commit 3 and
  4 were later re-created with a documentation-only change to
  docs/verification/RelaunchRestore.md (trees df74c97d, 6f0fbe23); every
  code blob is identical.
- `final/`: on `166697528ccf6ff75fad62b7aed4adada1f1e8e0` (code identical to
  the final head `739a6bdc`): `swift test`, the PTimer test plan executed on
  the iPhone 17 simulator 9144ED16 with its result bundle, and swiftlint.
- `captures/`: simulator checks on the final build. 01-15: camera 2 with
  zero auxiliary filters, Pouch selected, Pouch's ND on a wheel, the item
  moved to the Available 52mm Kit (wheel becomes Pouch's Empty wheel,
  selected Filter Sets unchanged). 16-17: an attempt to add a 52mm Kit
  wheel (the added Empty wheel is cleaned before a value can be picked).
  18-19: camera 1 with four mounted auxiliary filters, its ND wheel kept
  the item under the selected 52mm Kit and its selected Filter Sets are
  unchanged. 20-21: after relaunch, both cameras unchanged.
