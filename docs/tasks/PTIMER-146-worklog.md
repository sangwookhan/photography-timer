# PTIMER-146 Android MVP — Work Log

Running record of the instructions given for the PTIMER-146 Android MVP work and
the report returned for each pass, kept for later work-record use. All work is on
branch `feature/PTIMER-146-android-mvp` / Draft PR #16 (kept draft throughout; no
`ios/` or `shared/` changes in any pass).

> Fidelity note: entries before this file existed are faithful condensed
> summaries. This file was compacted on 2026-06-21 to avoid unsafe full-file
> reconstruction through the GitHub connector.

## Pass index

| # | Pass | HEAD | Tests | Outcome |
|---|---|---|---|---|
| 1 | iOS Test-Intent Parity Audit + Blocker Implementation | `7778a4f` | 123 | Per-test audit doc; 5 MVP blockers fixed |
| 2 | Restore/Persistence Hardening Pass 1 | `2221f9b` | 147 | timer-id collision, stale film/profile, slot-name, custom-id, per-item decode |
| 3 | Restore/Persistence Hardening Pass 2 | `c6a5825` | 159 | malformed-typed-field per-item decode, dup-id ordering, ready guard |
| 4 | Narrow restore catch scope | `3ee1f77` | 164 | catch = load/decode only; wiring surfaces errors |
| 5 | Catch-scope finish | `df5323a` | 164 | `runCatching` covers only load/decode |
| 6 | End-to-End Restore + Custom Film Verification | `45b0170` | 172 | app-level restore/custom tests; on-device kill/relaunch restore confirmed |
| 7 | Background Timer Completion Reliability | `5ccb538` | 184 | scheduler abstraction + AlarmManager best-effort |
| 8 | Background Completion Cleanup | `6d52f0d` | 184 | force-stop wording, completion subtitle, ongoing-notif policy |
| 9 | Exact Alarm Permission + Delivery Verification | `f0b32bf` | 192 | exact-when-permitted + request flow; both paths verified on device |
| 10 | Exact Alarm Settings Return Cleanup | `b4c4c77` | 198 | refresh on resume reschedules + clears notice; round-trip verified on device |
| 11 | Post-Process-Death Alarm Delivery Verification | `103fd0f` | 198 | exact-granted delivery after `am kill` verified on device; docs-only |
| 12 | Compose UI Smoke Test | `5bbf0c1` | 198 JVM + 3 instrumented | connected run blocked by Espresso/API37-preview |
| 13 | Stable Emulator Compose Smoke Retry | `a5cfb90` | 198 JVM; smoke 0/3 verified | stable API emulator unavailable + uncreatable |
| 14 | Robolectric Host-Side Compose Smoke | latest branch HEAD at that pass | 201 JVM | host-side ShootingScreen smoke 3/3 green; not a connected-test replacement |
| 15 | UI Parity Inventory | `5b074b1` | not run here | Inventory doc added; no UI implementation; Gradle not run here |

## Pass 15 — UI Parity Inventory

Instruction scope: inventory only; do not implement UI changes; keep PR #16 draft.

Report:

- Android UI parity is not complete.
- Current Android source already has an iOS-like shooting hierarchy, sectioned
  cards, segmented model picker, filled play actions, and richer timer cards.
  Therefore the older handoff statement that UI parity had not started is stale
  for the current branch.
- Major remaining gaps: Details graph/source-reference, Custom Film formula/table
  editor UI and create-formula CTA placement, film selector quality, and
  target/base/ND control density.
- Counts: 18 UI areas checked; 7 already acceptable, 8 need implementation,
  2 need screenshot/user decision, 1 deferred.
- Verification in this pass: Android source/docs inspected through GitHub
  connector. Direct current iOS UI source was not successfully fetched. Gradle
  was not run because there is no local checkout/network clone in this execution
  environment.
- File added: `docs/tasks/PTIMER-146-ui-parity-inventory.md`.
