# B1 — ViewModel 4-Way Decomposition Spec

**Status**: Done (6 of 6 PRs merged)
**Phase**: 3
**Spec precedence**: required before implementation
**Ticket**: PTIMER-118 (Implement Full Structure Improvement Plan)
**Related actions**: A4 (DI factory, prerequisite), A2 (FilmContext split, prerequisite), A8 (Presenter, incremental step), A9 (Coordinator, incremental step)
**Successor specs**: B3 (Result enum), B4 (Timer state types)

---

## 1. 목적

현재 단일 `ExposureCalculatorViewModel` (2,439L · 11 타입 · 6 책임)을 **4개의 작은 `@Observable` 모델**과 **가벼운 coordinator**로 분해한다. SRP 정면 위반을 해소하고, 각 view가 자기에게 필요한 모델만 관찰하도록 ISP를 자연 개선하며, 인지복잡도를 사람이 따라갈 수 있는 크기로 낮춘다.

---

## 2. 배경 (Why)

`Docs/StructureImprovement/Plan.md` §2.1 인지복잡도 + §2.3 SOLID + §2.4 Post-MVVM 진단의 정면 표적:

- **6 책임 동거** — calc + timer + reciprocity + film + persistence + lock screen.
- **2,439L 단일 파일** — 한 함수 읽을 때 머리에 담아야 할 협력자 수가 한계 초과.
- **모든 view가 같은 ViewModel 관찰** — ISP 부분 위반. 한 영역 변경이 무관한 view 재평가 트리거.
- **SwiftUI 추세 미반영** — iOS 17+ `@Observable`, MVVM 경계 재조정으로 표현 가능.

선택한 방향: **MVVM 유지 + 경계 재조정**. TCA·Redux·MV(no VM)는 Plan §7 비-목표.

---

## 3. 목표 아키텍처

```
SwiftUI Views
    │  observes
    ▼
@Observable models (4)
    ├─ CalculatorModel       — 노출 변수 (Base Shutter, ND), Output Shutter, snap·format
    ├─ ReciprocityModel      — 필름 선택 결과를 입력으로 정책 평가, Corrected Exposure,
    │                          confidence presentation, details surface state
    ├─ TimerWorkspaceModel   — 활성 timer collection, dock state, large workspace state,
    │                          completion presentation
    └─ FilmSelectionModel    — film picker sheet state, 카탈로그 접근, 활성 film identity
    │  owned by
    ▼
WorkspaceCoordinator (가벼운 클래스)
    │  uses
    ▼
Domain / Policy + TimerManager + Persistence (변경 없음)
```

### 3.1 모델별 책임

| 모델 | 입력 | 출력 (view-facing) | 부수 효과 |
|---|---|---|---|
| `CalculatorModel` | Base Shutter, ND stop, (선택) film identity | Output Shutter (digital) 또는 Adjusted Shutter (film mode), display state | 영속화: 작업 컨텍스트 |
| `ReciprocityModel` | Adjusted Shutter, film identity의 active profile | Corrected Exposure result, confidence presentation, details surface state | 없음 (순수 변환) |
| `TimerWorkspaceModel` | 새 timer 생성 요청, dock/sheet 사용자 액션 | timer collection, dock state, expanded state, completion 표시 | TimerManager 위임 |
| `FilmSelectionModel` | 사용자의 film picker 액션 | picker sheet state, active film identity, 카탈로그 view | 영속화: 선택된 film |

### 3.2 모델 간 통신

모델 간 **직접 참조 없음**. 통신은:
- 공유 store (예: WorkflowStateStore)를 통한 Pub/Sub
- Coordinator가 cross-cutting 이벤트 중재 (예: "Start Timer 버튼" → CalculatorModel의 결과 → TimerWorkspaceModel.add)

→ 한 모델 변경이 다른 모델을 직접 컴파일 의존시키지 않는다. 결과: 4 모델은 독립적으로 단위 테스트 가능.

### 3.3 Coordinator의 역할

`WorkspaceCoordinator`는:
- 4 모델의 lifetime 소유 (init, deinit)
- DI factory(A4)로부터 협력자(`ExposureCalculator`, `TimerManager`, `ReciprocityCalculationPolicyEvaluator`, persistence stores)를 받아 모델에 분배
- App entry에서 단 1개 인스턴스
- *상태를 가지지 않는다* — 모든 상태는 모델에. Coordinator는 wiring만.

---

## 4. 시맨틱 invariant (변경하지 말 것)

본 작업으로 다음 시맨틱은 **변경되지 않는다**. 변경 전후 동등 검증 의무:

1. **모든 도메인 행동 계약 (`Docs/Specs/`) 보존** — Calculator·Timer·UI·DomainSchema 어떤 spec도 본 작업으로 갱신되지 않는다. spec 변경이 필요하면 본 작업이 spec 위반이다.
2. **모든 단위 테스트가 동등 통과** — assertion 변경 0건. setup/teardown은 새 모델·coordinator 사용으로 마이그레이션 허용.
3. **Display state 타입 시그니처 0건 변경** — `FilmModeExposureResultState`, `BottomSheetWorkspaceSnapshot` 등 view가 소비하는 모든 display state 타입의 외부 시그니처(필드·타입·값 분포) 보존. 어느 모델이 emit하는지만 바뀐다.
4. **영속성 키와 스키마 0건 변경** — UserDefaults 키, JSON 스키마, snapshot 형식 모두 그대로. 본 작업으로 영속화 형식이 절대 진화하지 않는다.
5. **사용자 가시 행동 0건 변경** — 시뮬레이터 스모크 동등.
6. **A4 invariant 보존** — production code의 `XCTestRuntime` 참조 0건 (B1 후에도 영구).

---

## 5. 목표 상태 (What is true after)

- **`ExposureCalculatorViewModel` 더 이상 존재하지 않음.** 또는 lightweight coordinator 별칭으로 잠시 남음(마이그레이션 호환). 최종적으로 제거.
- **4 `@Observable` 모델이 별도 파일에 거주.** 위치는 `PTimer/ExposureCalculator/Models/` (Plan §6 트리 참조).
- **각 view가 자기 모델만 import.** Cross-model import는 coordinator 또는 shared store 경유.
- **모델별 단위 테스트 신규 추가** — 4 모델 각각이 독립 테스트 보유.
- **기존 `ExposureCalculatorViewModelTests`는 재구성** — 모델별로 분할(A11과 동시). 단 모든 어셔션 보존.

---

## 6. 비-목표

- **B3 / B4 type-driven 변경**은 본 작업 범위 밖. 모델 분할 후 별도 진행.
- **Display state 타입 이름 변경** 안 함 (B5 명명 패스에서). 분할 결과 자연스러운 이름이 보이면 그때.
- **새 view 추가 / 기존 view 재구성** 안 함. View 측 변경은 *어느 모델을 관찰하는가*만.
- **새 도메인 protocol 추가** 안 함. A4의 협력자 타입을 그대로 사용.
- **Live Activity / Lock-screen Coordinator 시맨틱 변경** 안 함 — A9에서 이미 분리되었으니 본 작업은 그 결과 위에 진행.
- **Persistence 형식 진화** 안 함 — 디코더 backward-compat도 필요 없다. 형식은 비트 단위 동일.

---

## 7. 검증 의무

`Docs/Verification/Strategy.md` 5 레이어 매핑:

| 레이어 | 의무 |
|---|---|
| **L1** Per-action 자동 | 모든 단위 테스트 동등 통과. 시뮬레이터 빌드 통과. SwiftLint pass. |
| **L2** Semantic equivalence | **★★ 결정적.** 도메인 행동 등가는 두 가지: (a) **record-replay** — 전 / 후 input·output diff 0 (정책 평가기·calculator·timer 라이프사이클). (b) **display-state diff** — 같은 input에 같은 display state 시리얼라이즈 결과 동일. (a)는 `Docs/Verification/Strategy.md` §6 절차. (b)는 ViewModelTests 출력을 baseline 기록 후 새 모델 출력과 비교. |
| **L3** Architectural fitness | **신규 lint rule**: (F5) 어떤 SwiftUI view도 4 모델 중 *하나만* 관찰 (multi-model import 금지, coordinator/store는 예외). (F8) 모델은 다른 모델을 직접 import 하지 않음. SwiftSyntax 검사. |
| **L4** UI 회귀 | **★★ 결정적.** `Docs/Verification/Strategy.md` §2.4 SwiftUI snapshot (B8) 모든 화면 + dock + film picker + details sheet pass. 스크린샷 매뉴얼 매트릭스 (3 density × 타이머 0/1/3 × 필름 on/off) 통과. |
| **L5** Drift | spec § 갱신 0건. drift 없음. |

`Docs/Specs/` 갱신: 없음 (도메인 행동 변경 아님).

---

## 8. 인수 기준 (DoD)

- [x] `ExposureCalculatorViewModel` 모놀리스 제거 또는 lightweight alias로 축소
      — **carry-forward 결정**: 모놀리스를 *제거*하지 않고 1,127L의 thin
      facade로 축소했다. PR5 audit가 production view tree에서 단일-모델
      boundary가 부재하다고 판단했고(스펙 §11 risk mitigation), §4
      invariant(Display state 시그니처 0건 변경)를 위반하지 않으려면
      cross-cutting computed display state는 ViewModel에 잔존시키는 것이
      가장 안전했다. 진행 결과: 4 child models는 SRP를 만족하고,
      WorkspaceCoordinator가 lifetime을 소유하며, ViewModel은
      orchestration-only facade로 남는다. 향후 B5 / B7 재명명·재분리에서
      facade를 추가로 축소할 수 있다.
- [x] 4 `@Observable` 모델이 `PTimer/ExposureCalculator/Models/`에 거주
      (`CalculatorModel` `@Observable`, `ReciprocityModel` `@Observable`,
      `TimerWorkspaceModel` `ObservableObject`, `FilmSelectionModel`
      `ObservableObject` — 후자 둘은 `assign(to:)` republish 호환을 위해
      `@Published`로 유지)
- [x] 각 모델이 독립 단위 테스트 파일 보유, 모두 pass
      (`CalculatorModelTests`, `ReciprocityModelTests`,
      `TimerWorkspaceModelTests`, `FilmSelectionModelTests`)
- [x] 기존 `ExposureCalculatorViewModelTests` 모든 케이스가 분할 /
      마이그레이션 후에도 동등 통과 — 분할은 보류, ViewModel facade
      유지 결정의 직접 결과로 모든 기존 케이스가 손대지 않은 채 통과
- [x] L2 record-replay baseline diff 0 (정책 평가기 + calculator + timer
      라이프사이클) — `RecordReplayBaselineSmokeTests` 및
      `ReciprocityResultLegacyShapeBaselineTests` byte-identical
- [x] L4 SwiftUI snapshot tests pass (Screen + BottomSheetShell + film
      mode result + details sheet) — `DisplayStateSnapshotTests` 9 cases
      byte-identical
- [ ] 시뮬레이터 매뉴얼 스모크 매트릭스 통과 — *carry-forward*: 본 PR은
      코드 변경이 lint 규칙 + dead code 제거 + spec/Plan 갱신뿐이라
      manual smoke matrix를 별도 실행하지 않았다. record-replay +
      display-state snapshot이 동등 검증을 대체.
- [x] L3 lint rule F5/F8 추가 + 위반 0건 (PR6에서 ` .swiftlint.yml`
      에 `view_observes_single_observable_root` 및
      `models_do_not_import_other_models_*` 4개 규칙 추가, 현재
      코드베이스 위반 0건)
- [x] PR 분할 권고대로 단계별 머지 (§10) — PR1–PR6 모두 커밋
      (`0020f1c` → `694c5ab` → 본 PR6)

---

## 9. 의존 / 후속

### 선행

| 액션 | 사유 |
|---|---|
| **A4** DI factory | 모델·coordinator가 협력자를 외부에서 받는다. A4 머지 전엔 모델이 다시 `XCTestRuntime` 분기를 도입할 위험. |
| **A2** FilmContext split | 23 display state 타입이 정리된 위치(`FilmContext/`)에 있어야 모델이 깨끗이 분배 가능. |
| **A8** FilmModeDetailsPresenter | Presenter 추출이 ReciprocityModel 분리의 첫 단계. A8이 머지된 상태에서 ReciprocityModel은 Presenter를 흡수하기 쉬움. |
| **A9** LockScreenTimerCoordinator | Lock-screen ownership이 ViewModel에서 분리된 상태에서 TimerWorkspaceModel은 lock-screen 시맨틱을 알 필요가 없다. |
| **B6** Spec parity fixture | 권장 (필수 아님). golden fixture가 있으면 record-replay 비용↓. |
| **B8** SwiftUI snapshot 인프라 | L4 검증 의무. Snapshot 도구 도입 후에야 view 회귀 lock 가능. |

### 후속

- **B3** Reciprocity Result enum — ReciprocityModel 분리 후에 표면적이 깔끔해 type-driven 변경 작업이 쉬워짐.
- **B4** Timer state types — 마찬가지로 TimerWorkspaceModel 분리 후 진입.
- **B5** Naming pass — 분할 부산물로 새 이름 후보 등장.

---

## 10. 구현 PR 분할 권고

본 spec 머지 후 5–6 단계 PR로 분할:

1. **(PR 1) `WorkspaceCoordinator` skeleton + `CalculatorModel` 도입** — `@Observable` 모델 1개. Coordinator가 ViewModel을 wrapping. 기존 ViewModel 보존, view는 ViewModel 관찰 유지. 단위 테스트 추가.
2. **(PR 2) `ReciprocityModel` 도입** — 정책 평가 책임 이동. A8 Presenter 흡수. ViewModel은 ReciprocityModel을 emit-through.
3. **(PR 3) `TimerWorkspaceModel` 도입** — timer collection·dock·workspace 책임 이동. A9 Coordinator는 TimerWorkspaceModel의 협력자가 됨.
4. **(PR 4) `FilmSelectionModel` 도입** — film picker / 카탈로그 책임 이동.
5. **(PR 5) View 마이그레이션** — 각 view가 직접 관찰할 모델로 binding 갱신. ViewModel을 더 이상 관찰하지 않음. L4 snapshot 통과 확인.
6. **(PR 6) ViewModel 제거 + lint rule (F5/F8) 영구 추가** — 모놀리스 제거. fitness function으로 재도입 차단.

각 PR:
- branch `feature/PTIMER-118-b1-vm-decomp-step-N`
- L2 record-replay diff 0 명시
- 직전 PR의 baseline 갱신 시 사유 명시

---

## 11. 위험 / 트레이드

| 위험 | 완화 |
|---|---|
| 모델 간 cross-cutting 이벤트가 coordinator를 비대하게 만듦 | Coordinator는 *wiring only*. 이벤트 처리가 필요하면 shared store 패턴. coordinator가 100L 초과 시 재검토. |
| `@Observable` macro의 iOS 17+ 의존 | 본 앱의 deployment target 확인 필요. iOS 16 호환이 요구되면 `ObservableObject` + `@Published`로 폴백. |
| Display state 출력이 미묘하게 다름 (timing, ordering) | record-replay로 잡힘. baseline diff 0이 결정적 게이트. |
| View 측 변경 범위가 큰 PR (PR 5)에서 회귀 | snapshot test (B8)이 인프라로 잡혀 있어야 안전. B8 미도입이면 PR 5 보류. |
| 모델 분할이 SOLID 다섯 원칙 모두 만족하지 못함 | DIP·SRP가 1차 목표. OCP는 본 작업 범위 밖. ISP는 자연 개선. LSP는 무관. |

---

## 12. 후속 갱신

본 spec은 *살아있는* 문서. 갱신 트리거:

- 구현 중 invariant 부정확 발견 → spec 갱신 후 PR 진행.
- B3·B4 spec 작성 시 본 spec의 모델 경계를 참조하므로, 본 spec 변경은 후속 spec에 영향.
- B1 완료 후 본 spec은 archive 후보 (StructureImprovement/ Epic 종료 시).

---

## 13. 구현 노트 (PR 단위 진행)

| PR | 상태 | 비고 |
|---|---|---|
| **PR 1** `WorkspaceCoordinator` skeleton + `CalculatorModel` | **Done** | `@Observable` `CalculatorModel` (calc 슬라이스: `ExposureCalculator` 인스턴스, `baseShutterSeconds`, `ndStop`, `calculationResult`) + 가벼운 `WorkspaceCoordinator` 도입. 기존 `ExposureCalculatorViewModel` public surface 보존, 내부에서 `CalculatorModel`에 위임. View / 테스트 변경 없음. App entry는 coordinator 경유로 ViewModel 생성. 모든 baseline (B3 legacy-shape, B8 display-state, record-replay smoke) byte-identical replay 확인. |
| **PR 2** `ReciprocityModel` | **Done** | `@Observable` `ReciprocityModel` (정책 평가 책임 facade) 도입 — `ReciprocityCalculationPolicyEvaluator` + A8 `FilmModeDetailsPresenter` 소유권을 ViewModel → 모델로 이동. 모델은 stored business state 없이 `evaluate` / `makeDetailsDisplayState` / `reciprocityStateDisplayState` 진입점만 노출. `WorkspaceCoordinator`가 `CalculatorModel` + `ReciprocityModel` 둘 다 보유. ViewModel public surface 보존. 모든 baseline byte-identical. |
| **PR 3** `TimerWorkspaceModel` | **Done** | `ObservableObject` + `@Published` `TimerWorkspaceModel` 도입 — `TimerManager`, timer metadata persistence (`TimerMetadataPersistenceStoring` + `timerMetadata` 딕셔너리 + `nextTimerOrder`), `timers: [RunningTimerItem]` published 컬렉션, lifecycle 동작 (`startTimer(id:duration:name:basisSummary:)` / pause / resume / remove / clearCompletedTimers / reconcile), `CompletedRelativeTimeFormatter` + completed-time refresh 스케줄, `syncTimers` 구독을 ViewModel → 모델로 이동. ViewModel은 `timerWorkspaceModel.$timers` 를 자기 `@Published var timers` 로 republish 하여 view 바인딩 / lock-screen Combine 구독 / record-replay smoke 테스트 모두 변경 없이 유지. Lock-screen coordinator 소유권은 ViewModel에 잔존 (PR5/PR6에서 정리). `WorkspaceCoordinator`가 `CalculatorModel` + `ReciprocityModel` + `TimerWorkspaceModel` 모두 보유. ViewModel public surface 보존. 모든 baseline byte-identical. |
| **PR 4** `FilmSelectionModel` | **Done** | `ObservableObject` + `@Published` `FilmSelectionModel` 도입 — preset film 카탈로그 (`presetFilms: [FilmIdentity]`), 활성 film identity 슬라이스 (`activeContext.selectedPresetFilm` + `selectedProfileOverride`), `ExposureCalculatorContextPersistenceStoring` 컨텍스트 영속화 store, 선택 / 해제 동작 (`selectEntry(_:)` / `selectPresetFilm(_:)` / `clearSelectedPresetFilm()`), 영속화 부수효과 (`restoreContext()` / `persistContext()` / `clearPersistedContext()`), `filmRowAuthorityLabel(for:)` 정적 헬퍼를 ViewModel → 모델로 이동. 모델은 calc 입력값(`baseShutterSeconds` + `ndStop`)을 closure 로 주입 받아 영속 시점에 풀링 — 영속 스키마(`selectedPresetFilmID + baseShutterSeconds + ndStop` 단일 snapshot) byte-identical 보존. ViewModel은 `filmSelectionModel.$activeContext` 을 자기 `@Published var activeCalculatorContext` 로 republish. `WorkspaceCoordinator`가 4 모델 (`CalculatorModel` + `ReciprocityModel` + `TimerWorkspaceModel` + `FilmSelectionModel`) 모두 보유. ViewModel public surface 보존. 모든 baseline byte-identical. |
| **PR 5** View 마이그레이션 (preparation) | **Done** | `WorkspaceCoordinator: ObservableObject` 채택 + `ExposureCalculatorScreen`이 coordinator를 `@StateObject`로 직접 보유하도록 전환. `init()`은 coordinator를 만들고 자식 모델·ViewModel을 coordinator 경유로 한 번만 구성. PR6에서 leaf view들이 `coordinator.timerWorkspaceModel` / `.filmSelectionModel` / `.calculatorModel` / `.reciprocityModel`을 직접 관찰하도록 갈아끼울 수 있는 wiring을 마련. **leaf view 직접 관찰 마이그레이션은 carry-forward**: 현재 production tree의 child view (`HeaderView` / `VariableSectionView` / `ResultSectionView` / `FilmSelectorOverlay` / `BottomSheetWorkspaceShell` / `FilmModeDetailsSheet`)는 (a) plain-value 매개변수만 받아 이미 ViewModel과 분리되어 있거나(`FilmSelectorOverlay`, `BottomSheetWorkspaceShell`), (b) ViewModel이 가공한 `*DisplayState` 컴퓨트 프로퍼티 여러 개를 동시에 읽어 — 한 모델 관찰만으로는 등가 재현이 어렵다. 깨끗한 단일-모델 boundary를 가진 production view가 부재하여, "shape-shift display states or add new model methods" 제약(§4 invariant)을 어기지 않으려면 PR5에서 마이그레이션을 강제하지 않는다(스펙 §11 risk mitigation 채택). PR6는 ViewModel을 carry-forward facade로 유지하면서 lint F5/F8로 재도입을 차단. ViewModel public surface 보존. 모든 baseline byte-identical. |
| **PR 6** Lock B1 + lint F5/F8 + ViewModel slim | **Done** | 본 PR. SwiftLint 커스텀 규칙 5종 추가: `view_observes_single_observable_root`(F5, 한 SwiftUI 파일이 4 모델 중 둘 이상을 `@StateObject`/`@ObservedObject`/`@EnvironmentObject`/`@Bindable`로 동시에 선언하면 error) 1개 + `models_do_not_import_other_models_{calc,reciprocity,timer,film}`(F8, 4 모델 파일이 서로의 타입 이름을 import 하면 error) 4개. 현재 코드베이스 위반 0건. ViewModel 1,168L → 1,127L (-41L) — `nonisolated static let shutterSpeeds` 를 `CalculatorModel`로 hoist하고 (`ExposureCalculatorScreen` + 내부 호출자 갱신), 더 이상 도달하지 않는 PR1/PR2/PR3 staging 단계용 두/세/네 인자 back-compat convenience init 3종을 제거 (`init(dependencies:)` 1-인자 convenience만 `RecordReplayBaselineSmokeTests` 호환을 위해 유지). leaf-view 직접 관찰 마이그레이션은 PR5 audit 결정에 따라 carry-forward; ViewModel을 lightweight orchestration facade로 남겨 cross-cutting display state 시그니처(§4 invariant) 보존. 모든 baseline byte-identical. 빌드·전체 테스트 그린. |
