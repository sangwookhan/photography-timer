# Coverage Baseline (B13)

**측정일**: 2026-04-29 (HEAD = `dd71369`)
**도구**: `xcrun xccov` against `xcresult` from `xcodebuild test -enableCodeCoverage YES`
**테스트 plan**: `PTimer.xctestplan` (PTIMER 단위 테스트 304+ 케이스)

---

## 1. 재현 절차

```bash
xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -testPlan PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -enableCodeCoverage YES \
  -derivedDataPath /tmp/ptimer-coverage test

xcrun xccov view --report --only-targets \
  /tmp/ptimer-coverage/Logs/Test/Test-PTimer-*.xcresult

xcrun xccov view --report --files-for-target PTimer.app \
  /tmp/ptimer-coverage/Logs/Test/Test-PTimer-*.xcresult
```

테스트 플랜의 `codeCoverage.targets`에 `PTimer`와 `PTimerWidgets`가 등록되어 있어야 한다. PTimerWidgets 는 widget bundle (`PTimerWidgetsBundle.swift` + `LockScreenTimerTargetWidget.swift`) 만 포함하며 단위 테스트가 없어 본 baseline 측정 시 0% 로 보고된다 — 자체 테스트 도입 전엔 측정만 가능하고 회귀 차단력은 없다. 본 baseline 의 종합 % 는 PTimer.app target 만 집계한 값이다.

---

## 2. 종합

| Target | # 파일 | Coverage |
|---|---|---|
| `PTimer.app` | 30 | **54.57%** (7,466 / 13,681) |

**해석**: 도메인/정책/ViewModel은 80–95%로 강하게 cover, view (Screen/Shell/Panel)은 0–35%로 단위 테스트 범위 밖. UI 회귀는 향후 B8 snapshot 테스트로 보강.

---

## 3. 레이어별 커버리지

### 3.1 Domain / Policy (★ 높은 보장)

| 파일 | Coverage |
|---|---|
| `ReciprocityDomain.swift` | **100.00%** (195 / 195) |
| `CompletedRelativeTimeFormatter.swift` | **98.21%** (55 / 56) |
| `LockScreenTimerCoordinator.swift` | **97.59%** (81 / 83) |
| `ReciprocityCalculationPolicy.swift` | **94.52%** (1,243 / 1,315) |
| `ReciprocityConfidencePresentation.swift` | **84.68%** (420 / 496) |
| `PresetFilmCatalog.swift` | **83.62%** (148 / 177) |
| `ExposureCalculator.swift` | **77.89%** (236 / 303) |

도메인 + 정책 평가기 + 잠금화면 coordinator 평균 **~91%**. 보호 영역 행동이 단위 테스트로 강하게 lock.

### 3.2 ViewModel / Persistence (★ 강한 보장)

| 파일 | Coverage |
|---|---|
| `ExposureCalculatorViewModel.swift` | **90.81%** (1,028 / 1,132) |
| `TimerManager.swift` | **86.52%** (462 / 534) |
| `FilmModeDetailsPresenter.swift` | **81.49%** (1,039 / 1,275) |
| `ViewModelDependencyFactory.swift` | 61.54% (16 / 26) |
| `PersistedCalculatorContext.swift` | 50.00% (13 / 26) |

ViewModel + TimerManager + Presenter 평균 **~86%**. Factory와 Persistence는 production-only 경로(`UserDefaults*`)가 단위 테스트에서 NoOp으로 대체되어 낮음.

### 3.3 Workspace shell / SwiftUI views (◯ 단위 테스트 부분 커버)

| 파일 | Coverage |
|---|---|
| `BottomSheetWorkspaceSnapshot.swift` | **96.77%** (390 / 403) |
| `BottomSheetWorkspaceStateStore.swift` | **92.45%** (49 / 53) |
| `BottomSheetWorkspaceMetrics.swift` | 100% (24 / 24) |
| `BottomSheetWorkspaceSnapshotStore.swift` | 100% (16 / 16) |
| `BottomSheetWorkspacePresentationAdapter.swift` | 100% (8 / 8) |
| `BottomSheetWorkspaceShell.swift` | 15.71% (293 / 1,865) |
| `BottomSheetWorkspaceActions.swift` | 30.77% (8 / 26) |
| `ExposureCalculatorScreen.swift` | 34.39% (1,674 / 4,868) |
| `RunningTimerPanelView.swift` | **0.00%** (0 / 534) |

Shell의 *상태 머신*(snapshot/store/metrics/adapter)은 단위 테스트로 잘 cover. Shell의 *body view*(1,865L 중 다수)와 Screen / RunningTimerPanel은 view layer로 단위 테스트 범위 밖.

### 3.4 App entry / Display state shells (낮음 — 자명)

| 파일 | Coverage |
|---|---|
| `FilmContext/FilmSelectionDisplayState.swift` | 100% (7 / 7) |
| `FilmContext/ExposureCalculatorWorkingContext.swift` | 100% (4 / 4) |
| `FilmContext/FilmModeResultDisplayStates.swift` | 100% (3 / 3) |
| `ExposureCalculatorLayoutMetrics.swift` | 100% (16 / 16) |
| `LockScreenTimerLiveActivity.swift` | 100% (4 / 4) |
| `ContentView.swift` | 100% (3 / 3) |
| `FilmContext/FilmModeDetailsDisplayStates.swift` | 15.00% (6 / 40) |
| `PTimerApp.swift` | 17.17% (17 / 99) |
| `TimerCompletionNotificationScheduler.swift` | 8.89% (8 / 90) |

Display-state struct들은 Equatable 메서드만 작동하므로 작은 카운트. App entry / Live Activity scheduler는 production-only 경로 (테스트에서 NoOp).

---

## 4. 핵심 관찰

1. **보호 영역 (정책 / Calculator / Timer / 영속) 평균 88–94%** — 회귀 차단 강함.
2. **View 레이어 0–35%** — 예상 분포. B8 snapshot 인프라가 추가될 때 보강.
3. **`RunningTimerPanelView` 0%** — A10에서 추출된 view, 단위 테스트 없음. snapshot으로 cover 권장.
4. **`BottomSheetWorkspaceShell.swift` 15.71%** — 1,865L 중 296L cover. 상태 머신 부분은 분리된 store들이 cover, body는 미cover.
5. **`FilmModeDetailsPresenter` 81.49%** — A8 직후. 추가 테스트 작성 여지 있음 (graph edge case).

---

## 5. 향후 갱신

- B1 ViewModel 분할 후 PR별 coverage 측정 — 분할 전후 동등 검증.
- B8 snapshot 인프라 머지 후 view 레이어 coverage가 *snapshot 기반 lock*으로 보강됨 (라인 % 자체는 큰 변화 없음).
- 추가 단위 테스트 작성 우선순위: `RunningTimerPanelView` 로직 추출 후 단위 테스트화 (현재는 view에 묻혀 있음).
- 마일스톤 종료 시점에 본 표 갱신 (전후 % 비교).

---

## 6. CI 통합

현재 CI 파이프라인은 비-목표 (개인 작업). 향후 CI 도입 시 본 절차를 Bitbucket Pipelines / GitHub Actions / Xcode Cloud step에 포함하고 PR 본문에 coverage delta를 첨부.
