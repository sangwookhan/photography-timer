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

The full layer stack — file-level responsibilities, dependency
direction, source-of-truth ownership, and architectural fitness rules
— is documented in [`docs/architecture/Architecture.md`](docs/architecture/Architecture.md).

Behavior contracts live as language-neutral specs under `docs/specs/`.
They are the source of truth for refactoring; code that contradicts a
spec is a bug or a spec drift to be reconciled.

## Documentation map

| Path | Purpose |
|---|---|
| `docs/requirements/Requirements.md` | User-scenario requirements and product intent. |
| `docs/specs/{Calculator,Timer,UI,DomainSchema}.md` | Behavior contracts. Permanent. |
| `docs/architecture/Architecture.md` | Current code structure: layer stack, file-level responsibilities, dependency direction, source-of-truth ownership, fitness rules. |
| `docs/verification/Strategy.md` | Five-layer verification strategy (test, semantic equivalence, architectural fitness, UI regression, drift audit). |
| `docs/verification/{BackgroundNotificationDelivery,RelaunchRestore}.md` | Manual verification procedures. |
| `docs/conventions/ErrorModel.md` | Error-handling conventions by layer. |
| `docs/translations/ko/` | Korean mirror of requirements and specs. English docs are canonical. |
| `docs/tasks/TASK_TEMPLATE.md` | Per-ticket spec template. |

## Governance

| Aspect | Reference |
|---|---|
| Workflow / source-of-truth order | `AGENTS.md` |
| Build / architecture / protected areas | `CLAUDE.md` |
| Review checklist | `code_review.md` |

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
