# PTimer

Native iPhone app for film photography exposure calculation (ND filter +
reciprocity correction) and countdown timers, with a lock-screen Live
Activity widget.

## Stack

- Swift / SwiftUI
- Xcode project (`PTimer.xcodeproj`)
- Test target: `PTimerTests`
- Widget target: `PTimerWidgets`
- Test plan: `PTimer.xctestplan`

## Architecture summary

PTimer follows a layered architecture with strict one-way dependencies:

```
SwiftUI Views  →  ViewModel (@MainActor ObservableObject)  →  Domain / Policy + Timer Runtime  →  Persistence
```

- **SwiftUI Views** render only; they consume display-state structs emitted
  by the view model.
- **ViewModel** orchestrates the calculator, timer runtime, reciprocity
  policy, persistence, and the lock-screen target coordinator.
- **Domain / Policy** are pure value-types and pure-function modules:
  exposure math, reciprocity policy evaluation, confidence presentation.
- **Timer Runtime** owns timer lifecycle, persistence, completion
  notifications, and the lock-screen Live Activity surface.
- **Persistence** is behind protocol pairs (real + NoOp) so unit tests
  never touch UserDefaults / ActivityKit / UNUserNotification.

Behavior contracts are documented as language-neutral specs under
`docs/en/specs/`. They are the source of truth for refactoring; code that
contradicts a spec is a bug or a spec drift to be reconciled.

## Documentation map

| Path | Purpose |
|---|---|
| `docs/en/specs/{Calculator,Timer,UI,DomainSchema}.md` | Behavior contracts. Permanent. |
| `docs/Sources/wiki/` | Local cache of authoritative Confluence pages cited by the specs. |
| `docs/StructureImprovement/` | Active structural-improvement Epic work products (analysis snapshot, action plan, Android port plan). Removed when the Epic closes. |
| `docs/Verification/Strategy.md` | Five-layer verification strategy (CI, semantic equivalence, architectural fitness, UI regression, drift audit). |
| `docs/Verification/{BackgroundNotificationDelivery,RelaunchRestore}.md` | Manual verification procedures. |
| `docs/Features/Reciprocity/PresetDatasetPolicy.md` | Launch dataset policy. Permanent. |
| `docs/tasks/TASK_TEMPLATE.md` | Per-ticket spec template. |

## Governance

| Aspect | Reference |
|---|---|
| Workflow / source-of-truth order | `AGENTS.md` |
| Build / architecture / protected areas | `CLAUDE.md` |
| Review checklist | `code_review.md` |
| Action plan in flight | `docs/StructureImprovement/Plan.md` |

## Getting started

1. Open `PTimer.xcodeproj` in Xcode.
2. Select an iPhone Simulator.
3. Build and run the `PTimer` scheme.

### Running tests

```bash
xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -testPlan PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

If `iPhone 17` is unavailable, choose any available iPhone simulator
listed by `xcodebuild -showdestinations -project PTimer.xcodeproj
-scheme PTimer`.

### Linting (local)

```bash
brew install swiftlint   # one-time
swiftlint lint           # from repo root
```

Configuration lives in `.swiftlint.yml`. Phase 0 baseline is intentionally
relaxed; size and complexity thresholds are added in a later phase.
