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

## Scope

- Gate the reset behind a confirmation dialog on both platforms.
- Resolve the cross-platform divergence (Android cleared the camera
  name, iOS did not) by offering **two explicit reset choices** with
  one shared string set, so translation stays centralized:
  - **Reset settings** — clears film, ND, shutter, target; keeps the
    camera name.
  - **Reset settings and name** — also clears the camera name.
- Keep a single `Reset` entry point; the two choices live inside the
  confirmation surface (iOS `.confirmationDialog`, Android
  `AlertDialog` with stacked buttons) so the anti-mistap gate holds.

## Behavior change (authorized)

This deliberately changes reset semantics so both platforms expose
both behaviors:

- iOS adds `resetFilmModeWorkingContextAndCameraName()` (existing
  `resetFilmModeWorkingContext()` is the settings-only path).
- Android splits `resetActiveSlot()` into `resetActiveSlotSettings()`
  (keeps name) and `resetActiveSlotSettingsAndName()` (clears name).

Strings are identical literals on both platforms, ready to lift into
shared resources when localization infra lands.

## Verification

- iOS: `CalculatorViewModelCameraSlotRenameTests` gains
  `testResetSettingsKeepsCustomCameraName` and
  `testResetSettingsAndNameClearsCustomCameraName`.
- Android: `CalculatorControllerTest` gains
  `resetActiveSlotSettingsKeepsCustomName` and renames the existing
  test to `resetActiveSlotSettingsAndNameClearsFilmInputsAndName`.
- The dialog gating itself is view-layer state (same no-unit-test
  convention as the sibling rename/target dialogs).
- Build both apps; drive the Android emulator to confirm Reset now
  prompts with both choices and that "Reset settings" preserves the
  camera name.
