# PTIMER-70 Verification

## Scope

PTIMER-70 restores timer state after the previous app process is gone and a
new launch reconstructs the workspace from persisted timer snapshots.

PTIMER-67 remains responsible for recalculating in-memory running timers when
the same process returns from inactive/background to active.

## Restore Entry Point Self-Review

There is one relaunch restore entry point:

- `TimerManager.init(...)`
  - calls `restorePersistedTimersIfNeeded()`
  - guards with `hasRestoredPersistedTimers`
  - restores persisted timer snapshots exactly once per manager instance

Lifecycle reactivation does not re-run PTIMER-70 restore:

- `ExposureCalculatorScreen.onChange(scenePhase == .active)`
  - calls `ExposureCalculatorViewModel.reconcileTimersAfterAppBecomesActive()`
  - delegates to `TimerManager.reconcileAfterAppBecomesActive()`
  - this is PTIMER-67 reconciliation only

## Snapshot Schema Rationale

`PersistentTimerSnapshot` persists only the fields needed to reconstruct timer
behavior and stable card identity after relaunch.

- `id`
  - preserves timer identity so cards and actions keep targeting the same item
- `status`
  - chooses the correct restore rule for running, stopped, or completed timers
- `duration`
  - preserves the original timer target for display and elapsed calculations
- `startDate`
  - keeps original timer provenance and supports stable reconstruction
- `expectedCompletionAt`
  - lets running timers reconcile against real wall clock time on relaunch
- `pausedRemainingDuration`
  - keeps stopped timers frozen without consuming time while the app is gone
- `pausedAt`
  - preserves paused-state context shown in the UI
- `completedAt`
  - preserves the final completion timestamp for completed timers

`PersistentTimerMetadataCollectionSnapshot` persists only the display metadata
needed to restore card identity.

- `nextTimerOrder`
  - keeps newly created cards ordered after restored cards
- `timers[].id`
  - joins display metadata back to restored timer state
- `timers[].order`
  - preserves workspace ordering
- `timers[].name`
  - preserves card title
- `timers[].basisSummary`
  - preserves the calculation/context subtitle

## Automated Coverage

`PTimerTests/TimerManagerTests.swift`

- `testRestoreRunningTimerAfterTerminationKeepsItRunningWithWallClockRemainingTime`
- `testRestoreRunningTimerAfterTerminationCompletesIfExpectedCompletionAlreadyPassed`
- `testRestoreStoppedTimerAfterTerminationPreservesRemainingTime`
- `testRestoreCompletedTimerAfterTerminationKeepsCompletedState`
- `testRestoreMultipleTimersAfterTerminationPreservesIDsAndStatuses`
- `testRestoreEntryPointLoadsSnapshotOnlyDuringInitialization`

`PTimerTests/ExposureCalculatorViewModelTests.swift`

- `testRelaunchRestoresTimerCardIdentityMetadataForMultipleTimers`

## Manual Verification

### Running timer survives relaunch

1. Launch the app.
2. Create a timer long enough to observe, for example 30 seconds.
3. Force quit the app immediately.
4. Relaunch the app before the original completion time.
5. Confirm the timer is restored as running.
6. Confirm the remaining time reflects real elapsed wall clock time.

### Running timer expires while the app is dead

1. Launch the app.
2. Create a short timer, for example 3 seconds.
3. Force quit the app before it completes.
4. Wait until the original completion time passes.
5. Relaunch the app.
6. Confirm the timer is restored as completed.

### Stopped timer remains frozen across relaunch

1. Launch the app.
2. Create a timer.
3. Stop it with a visible amount of remaining time.
4. Force quit the app.
5. Wait longer than the remaining time.
6. Relaunch the app.
7. Confirm the timer is still stopped.
8. Confirm the remaining time is unchanged from when it was stopped.

### Completed timer remains completed across relaunch

1. Launch the app.
2. Create a very short timer and let it complete.
3. Force quit the app.
4. Relaunch the app.
5. Confirm the timer is still completed and shows the same completion context.

### Multiple timers preserve identity and ordering

1. Launch the app.
2. Create at least two timers with different durations and names/context.
3. Stop one timer and leave another running.
4. Force quit the app.
5. Relaunch the app.
6. Confirm each restored card keeps the same title, subtitle, order, and status.
7. Confirm actions still target the correct timer card after relaunch.
