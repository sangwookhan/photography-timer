# PTIMER-208 — Reset clears shooting setup without confirmation

Bug. GitHub issue #27. Applies to **both Android and iOS** (per user).

## Problem

Tapping **Reset** on the shooting screen immediately clears the
configured shooting setup. Reset sits next to the **(i) / About**
button, so a single accidental tap meant for **(i)** wipes the active
slot's setup with no undo.

- iOS Reset clears: selected film, ND filter, base shutter, scale
  mode, target shutter (camera name is **not** cleared).
- Android Reset clears: selected film, ND filter, shutter, target
  shutter, **and** the custom camera name.

## Goal

A destructive Reset must not clear setup from a single accidental
tap. Require an explicit confirmation step before the existing reset
runs.

## Scope (UI-only)

- Gate the existing reset call behind a confirmation dialog on both
  platforms. Do **not** change the domain reset behavior.
- iOS: `ExposureCalculatorScreen.swift` `HeaderView` — `.confirmationDialog`
  matching the existing destructive-confirm style; on confirm call
  `onResetFilmModeContext()`.
- Android: `ShootingScreen.kt` — `AlertDialog` matching the existing
  destructive-confirm style (error-colored confirm); on confirm call
  `onReset`.
- Copy is platform-accurate (Android mentions camera name, iOS does
  not).

## Protected areas (untouched)

`resetFilmModeWorkingContext()` (iOS) and `resetActiveSlot()`
(Android) keep their exact clearing semantics. Only the trigger is
gated.

## Verification

- Domain reset unit tests (`ExposureCalculatorViewModel*`,
  `CalculatorControllerTest`) call the reset methods directly and are
  unaffected — they continue to pass.
- The dialog gating is view-layer state matching the existing
  `RenameSlotDialog` / `confirmationDialog` patterns (same
  no-unit-test convention as the sibling dialogs).
- Build both apps; drive the Android emulator to confirm Reset now
  prompts before clearing.
