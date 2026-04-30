# PTIMER-11 Test Assets

## Scope

- Calculation result accuracy
- Timer creation and state transitions
- Basic calculator screen behavior

## Calculation Input / Output Cases

| Case | Base Shutter Input | ND Input | Expected Result |
| --- | --- | --- | --- |
| 1 | `1/30` | `ND64` | `2.1s` |
| 2 | `1/125` | `8` | `1/16s` |
| 3 | `0.5` | `ND1000` | `500s` |
| 4 | `2s` | `ND64` | `128s` |

## Validation Input Cases

| Case | Base Shutter Input | ND Input | Expected Error |
| --- | --- | --- | --- |
| 1 | `` | `ND64` | `Base shutter is required.` |
| 2 | `abc` | `ND64` | `Enter shutter like 1/30, 0.5, or 2s.` |
| 3 | `0` | `ND64` | `Base shutter must be greater than 0.` |
| 4 | `1/30` | `` | `ND value is required.` |
| 5 | `1/30` | `NDfoo` | `Enter ND like 8, 64, or ND1000.` |
| 6 | `1/30` | `0` | `ND value must be greater than 0.` |

## Timer Flow Cases

| Case | Input / Action | Expected Result |
| --- | --- | --- |
| 1 | Valid calculation, tap `Start Timer` | New timer card appears immediately |
| 2 | Timer running | Remaining time decreases, status stays `Running` |
| 3 | Tap pause while running | Remaining time freezes, status changes to `Paused` |
| 4 | Timer reaches end date | Remaining time becomes `00:00`, status changes to `Completed` |
| 5 | Remove paused/completed timer | Timer card disappears from panel |

## UI Verification Checklist

- Header, Variable Controls, Result Set, Timer Action, and Running Timer Panel are visible on the calculator screen.
- Valid `Shutter` and `ND` input updates the result immediately.
- Invalid input keeps the app stable and shows validation text.
- `Start Timer` is disabled for invalid input and enabled for valid input.
- Running timer cards show:
  - dominant remaining time
  - total duration
  - state indicator
  - calculation basis summary
- Running timers use green status styling.
- Paused timers use orange status styling.
- Completed timers use gray status styling and show `00:00`.
- Empty timer panel shows `No active timers`.

## Automated Test Coverage

- `ExposureCalculatorTests`
  - representative calculation cases
  - invalid input cases
  - parser behavior
  - shutter display formatting
- `TimerManagerTests`
  - Date-based remaining-time calculation
  - running to completed transition
  - pause behavior and remaining-time preservation
  - multi-timer updates and cleanup
- `ExposureCalculatorViewModelTests`
  - timer start enablement
  - timer metadata snapshot preservation
  - display clock formatting
  - completed state projection
