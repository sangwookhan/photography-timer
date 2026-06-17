# PTIMER-146 Android MVP — Implementation Build Log

Auto-mode implementation session. Times are KST (session date 2026-06-17).

## Timing summary

| Phase | Start | End | Duration | Result |
|---|---|---|---|---|
| Preflight + toolchain bootstrap + baseline assemble | 03:16:19 | 03:20:00 | ~3m41s | clean preflight; baseline APK built |
| Slice 1 — Gradle/module setup | 03:20:00 | 03:21:40 | 1m40s | green, committed `db926f2` |
| Slice 2 — Exposure core (parity) | 03:21:40 | 03:27:29 | 5m49s | green, committed `530c02f` |
| Slice 3 — Reciprocity calculation primitives (partial) | 03:27:29 | 03:33:27 | 5m58s | green, committed `6c779da` |
| Slice 4 — Timer state machine + runtime + snapshot | 03:33:27 | 03:37:31 | 4m04s | green, committed `c73c6e6` |
| Finalization (verify, artifacts, PR) | 03:37:31 | — | — | — |
| **Total (start → final verification)** | 03:16:19 | 03:38:07 | **21m 48s** | clean build green |

Notes:
- Preflight included a one-time Gradle 8.9 + Build-Tools 34 + Platform 35
  download, which accounts for most of the ~3m41s preflight window.
- Each slice ended on a green `./gradlew :core:test assembleDebug` and was
  committed before the next slice began. No `BROKEN:` commits were used.

## Preflight result (verified)

- Worktree: `PTIMER-146-android-mvp`, branch `feature/PTIMER-146-android-mvp`.
- `HEAD == origin/main == 0078b80` (includes PTIMER-165 + PTIMER-180; excludes
  PTIMER-188 — verified clean).
- iOS source diff vs origin/main: **none** throughout the session.
- Toolchain: JDK 21 (Android Studio JBR), `ANDROID_HOME` set; baseline
  `assembleDebug` succeeded.

## What was completed

Pure-Kotlin `:core` foundation, fully unit-tested, no Android dependency:
- Slice 1: `:core` module wired (kotlin.jvm + serialization), smoke test.
- Slice 2: exposure calculation parity (calculator, ladders, snap, formatting)
  driven by `shared/test-fixtures/exposure-golden.json`.
- Slice 3 (partial): reciprocity calculation primitives — formula evaluator,
  log-log table evaluator, OLS fitter, no-shortening guard, duration parser,
  no-correction boundary.
- Slice 4: timer state machine, runtime, snapshot/restore, ordering, identity.

Final clean verification: `./gradlew clean :core:test testDebugUnitTest
assembleDebug` → BUILD SUCCESSFUL; 51 `:core` tests + app `ExampleUnitTest`,
0 failures.

## What was NOT completed (deferred to a follow-up session, owner review)

Too large to complete safely in this session; stopped per auto-mode policy with
all verified work kept green:
- Slice 3 remainder: full catalog JSON domain (FilmIdentity / ReciprocityProfile
  / provenance / adjustments / userMetadata), 37-film loader + shape validation,
  policy evaluator, confidence presentation, alternate-model registry,
  reference-table resolver.
- Slices 5–10: timer coordinator + ViewModel + DataStore persistence + runnable
  timer UI; calculator + film selection + alternate-model selection; camera
  slots + rename; custom film library + table/formula authoring + fitted preview
  + create-formula-from-table; Target Shutter; Reciprocity Details; Android
  notifications + foreground service.

See `PTIMER-146-android-test-intent-map.md` for the per-area status and gap list.

---

## Resumed session (continue from Draft PR #16)

Resumed to complete the deferred Slice 3 remainder and Slices 5–10. Times KST.

| Phase | End | Duration | Result |
|---|---|---|---|
| Resume preflight (base clean, build green) | 09:17 | ~2m | clean |
| Slice 3 remainder — catalog + policy + confidence + alternates + resolver | 09:24:16 | ~6m45s | green `87bff3d`, `5432fb2` |
| Slice 5 — timer workflow (VM + coordinator + DataStore + UI) | 09:29:29 | ~5m | green `a20bcb6` |
| Slice 6 — calculator + film + alternate-model | 09:34:05 | ~4m35s | green `8ab3c46` |
| Slice 7 — camera slots + rename | 09:38:29 | ~4m25s | green `023eba3` |
| Slice 8 — custom film (formula/table/fitted/create-from-table) | 09:45:22 | ~7m | green `2a1d572` |
| Slice 9 — Target Shutter | 09:48:40 | ~3m20s | green `7a4e560` |
| Slice 10a — Reciprocity Details | 09:51:19 | ~2m40s | green `3b52b6a` |
| Slice 10b — notifications | 09:54:54 | ~3m35s | green `ccde417` |
| **Resumed total (09:15 → ~09:56)** | — | **~41m** | all slices complete |

Final clean verification: `./gradlew clean :core:test testDebugUnitTest
assembleDebug` → BUILD SUCCESSFUL; **72 core + 39 app = 111 tests, 0 failures**;
iOS/shared diff vs origin/main = 0. No `BROKEN:` commits. All 10 Round-3 slices
implemented. Deferred: foreground service + exact background delivery; UI polish;
device/emulator `connectedAndroidTest`.

---

## Post-user-test follow-ups

1. **Start-action model fix** (`ea68abd`): replaced the single generic Start with
   separate Adjusted/Corrected/Target start actions; limited guidance keeps
   Adjusted enabled and disables only Corrected. Visually verified on
   emulator-5554. Test count rose to 72 core + 41 app.
2. **Screen-hierarchy cleanup** (`01a2934`): safe-area insets (title clears the
   status bar / cutout), sectioned cards (Film+model / Target / Base+ND /
   Result), custom-film actions demoted, vertical non-clipping timer cards.
   UI-only; tests unchanged + green. Visually verified on emulator (no-film,
   quantified Pan F Plus with both starts, active timer rows with source
   identity). Screenshots saved to the owner's Desktop
   (`PTIMER146_android_v2_*.png`).
3. **iOS look alignment** (`78b75ec`): segmented reciprocity-model picker
   (replacing the dropdown), filled ▶ play actions on the Adjusted/Corrected/
   Target rows, white sectioned cards, a camera-header Reset, and iOS-parity
   timer rows (status pill, source subtitle, Base·ND·Adjusted metadata line,
   "Ends HH:mm:ss" for running, "Start new" on active + "Start again" on
   completed). Base/ND stay as steppers (Compose has no iOS-equivalent wheel as
   a base component; explicitly out of scope). TimerWorkspaceController/codec
   gained a metadata field + cloneToNew; 72 core + 42 app tests, 0 failures.
   Visually verified on emulator (Fomapan 100 Classic segmented picker, ▶
   starts, enriched timer rows). Screenshots: `PTIMER146_android_v3_*.png`.
