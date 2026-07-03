# Photography Timer

Photography Timer is an exposure calculator and countdown timer for film
and digital photography. The current app helps calculate adjusted shutter
times, film reciprocity-corrected exposures, target shutter differences,
and shooting timers. PTIMER is the project and repository code name.

## Current Status

- iPhone is the first release target.
- Android has an MVP native implementation in progress.
- Current app/development version: 0.7.3.
- Planned public release target: Photography Timer 0.7.
- Homepage: https://sangwookhan.github.io/photography-timer/
- Privacy Policy: https://sangwookhan.github.io/photography-timer/privacy.html
- Support: https://sangwookhan.github.io/photography-timer/support.html
- Film Data Attribution: https://sangwookhan.github.io/photography-timer/attribution.html

## Repository Layout

| Path | Purpose |
|---|---|
| `ios/PTimer.xcodeproj` | iOS app, widget, and app-hosted test project. |
| `ios/PTimerKit` | Swift package for reusable core, app logic, presenters, view models, and SwiftUI components. |
| `android/` | Native Android MVP project using Kotlin, Jetpack Compose, and Gradle. |
| `shared/test-fixtures/` | Cross-platform fixtures used by tests. |
| `docs/` | Requirements, specs, architecture, verification, and task documents. |

## iOS Quick Start

Open `ios/PTimer.xcodeproj` in Xcode, select the `PTimer` scheme, and
run on an iPhone simulator or device.

```bash
swift test --package-path ios/PTimerKit

cd ios && xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -testPlan PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

If `iPhone 17` is unavailable, list destinations with:

```bash
cd ios && xcodebuild -showdestinations -project PTimer.xcodeproj -scheme PTimer
```

## Android Quick Start

Android requires JDK 17 or newer and an Android SDK configured through
`ANDROID_HOME` or `android/local.properties`.

```bash
cd android && ./gradlew assembleDebug
cd android && ./gradlew test
cd android && ./gradlew lint
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution and licensing
expectations.

## License

Copyright © 2026 Sangwook Han.

Photography Timer is licensed under the [Apache License, Version 2.0](LICENSE).
Film data attribution notes are recorded in [NOTICE](NOTICE).
