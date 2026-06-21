# PTimer

Native iPhone app for film photography exposure calculation (ND filter +
reciprocity correction) and countdown timers, with a lock-screen Live
Activity widget.

## Stack

- Swift / SwiftUI
- Xcode project (`ios/PTimer.xcodeproj`)
- Test target: `ios/PTimerTests`
- Widget target: `ios/PTimerWidgets`
- Test plan: `ios/PTimer.xctestplan`

iOS sources live under `ios/`. A native Android skeleton lives under
`android/`. Shared cross-platform test fixtures live at
`shared/test-fixtures/`.

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

1. Open `ios/PTimer.xcodeproj` in Xcode.
2. Select an iPhone Simulator.
3. Build and run the `PTimer` scheme.

### Running tests

```bash
cd ios && xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -testPlan PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

If `iPhone 17` is unavailable, choose any available iPhone simulator
listed by `cd ios && xcodebuild -showdestinations -project PTimer.xcodeproj
-scheme PTimer`.

### Linting (local)

```bash
brew install swiftlint            # one-time
cd ios && swiftlint lint          # run from repository root
```

Configuration lives in `ios/.swiftlint.yml`. Phase 0 baseline is
intentionally relaxed; size and complexity thresholds are added in a
later phase.

## License

Copyright © 2026 Sangwook Han. Licensed under the
[Apache License, Version 2.0](LICENSE).

## Android skeleton

A minimal native Android project lives under `android/`. It builds
independently and currently launches to a placeholder Compose screen
only; no PTimer features are ported.

### Prerequisites

- JDK 17 or newer. Android Studio's bundled JBR is sufficient. For
  CLI builds, point `JAVA_HOME` at a JDK 17+ install. The Gradle
  wrapper handles Gradle itself.
- Android SDK. Set `ANDROID_HOME` or create
  `android/local.properties` with `sdk.dir=<path>`.

### Build and test

```bash
cd android && ./gradlew assembleDebug          # build debug APK
cd android && ./gradlew test                   # unit tests
cd android && ./gradlew lint                   # Android Lint
cd android && ./gradlew installDebug           # install on device/emulator
```

`connectedAndroidTest` requires a running device or emulator and is
not part of the skeleton's required DoD.

### Android Studio: opening the project

Prefer opening the **repository root** in Android Studio when
reviewing Git history across both platforms. If you open `android/`
directly and Git history is not visible, add the parent repository
directory as a Git root from *Preferences/Settings → Version
Control → Directory mappings*. Do not initialize a new Git
repository inside `android/`, and do not commit `android/.idea/`.
