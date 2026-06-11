# Display State Snapshot Tests (B8)

가벼운 in-house snapshot 인프라. SwiftUI 픽셀 비교가 아니라 *display state 직렬화*를 lock한다.

## 무엇을 검증하나

- ViewModel·Presenter·Mapper·Catalog가 emit하는 `Equatable` 값의 **결정적 직렬화**
- 같은 input → 같은 직렬화 결과
- 직렬화는 `Swift.dump`로. Swift 버전 단위 안정적

따라서 변경이 **시맨틱 동등 (B1/B3/B4)인지 확인하는 결정적 게이트**로 사용 가능. View 회귀(픽셀 수준)는 별도 — 본 인프라는 미커버. PR 리뷰의 매뉴얼 화면 비교 또는 후속 image-snapshot 확장으로 보강 권고.

## 사용

```swift
DisplayStateSnapshot.assert(value, named: "my-scenario")
```

baseline 위치: `<TestRoot>/__Snapshots__/<TestClass>/<name>.txt` (`<TestRoot>`
= 테스트 소스 위의 가장 가까운 지원 루트: `PTimerTests` 또는 `PTimerKitTests`).
이 스위트는 PTIMER-174에서 `PTimerKitTests`로 이전되어 off-simulator로 실행된다.

## 라이프사이클

1. **첫 실행**: baseline 없음 → 헬퍼가 파일 작성 후 *fail* (기록 사실을 노출시켜 사람이 commit해야 함).
2. **이후 실행**: baseline 읽고 직렬화 결과와 비교. 다르면 fail + sidecar `.actual.txt` 작성.
3. **의도적 갱신**: `SNAPSHOT_RECORD=1` 환경변수로 실행 → 모든 매치 케이스가 baseline을 다시 쓰고 fail. 두 번째 (env 없이) 실행으로 verification.

```bash
# Re-record after deliberate change (run from repository root)
SNAPSHOT_RECORD=1 swift test --package-path ios/PTimerKit \
  --filter DisplayStateSnapshotTests

# Verify (no env)
swift test --package-path ios/PTimerKit --filter DisplayStateSnapshotTests
```

## 베이스라인을 commit해야 하는가

**예.** `__Snapshots__/` 디렉토리는 git에 들어간다. 변경은 PR diff로 검토.

## pointfreeco/swift-snapshot-testing 안 쓰는 이유

- 본 프로젝트는 개인 작업 + 외부 의존 최소화 선호.
- B1/B3/B4의 결정적 게이트는 **display-state diff** (L2). `Swift.dump` 텍스트 직렬화로 충분.
- View 픽셀 회귀(L4)가 필요해지면 본 헬퍼에 `UIView.snapshot()` 분기를 추가하거나 그 시점에 라이브러리 도입.

## 어떤 값을 lock할 가치가 있나

- **도메인 / 정책 결과** — `ReciprocityResult`, `ReciprocityConfidencePresentation` (B3 변경의 게이트)
- **Catalog snapshot** — `LaunchPresetFilmCatalog.films` (A12 같은 데이터 정정 시 의도된 diff 확인)
- **Display state 집합체** — `BottomSheetWorkspaceSnapshot`, `FilmModeExposureResultState`, `FilmModeDetailsDisplayState` (B1 모델 분리 시 게이트)
- **TimerState 직렬화** — B4 sum type 도입 후 backward-compat 검증

각 카테고리에 최소 1 baseline. 대표 input은 `ReciprocityPolicyScenarioFactory` 와 `LaunchPresetFilmCatalog`에서.
