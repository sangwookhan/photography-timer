# 구조 개선 액션 플랜 — 다관점 진단

**작성일**: 2026-04-27 (v2 — 다렌즈 재검토)
**유형**: 실행 액션 문서 (단일 진입점)
**상위 hub**: 위키 19070978 (`구조 개선`) 의 자식 액션 문서
**근거 문서**:
- `Docs/Specs/Calculator.md`, `Timer.md`, `UI.md`, `DomainSchema.md` (도메인 행동 계약 스펙)
- `./CurrentState.md` (인벤토리, 시점 스냅샷)
- 1차 리뷰: 위키 19103745 (8.5/10, Tier 1/2/3 권고)

---

## 1. 목적

PTIMER iOS 앱을 **6개 렌즈**로 점검해 *사람이 읽고 변경하기 쉬운 형태*로 가져가는 액션을 정리한다.

| # | 렌즈 | 핵심 질문 |
|---|---|---|
| 1 | 인지복잡도 | 한 함수를 읽을 때 머리에 담아야 하는 협력자 수가 적절한가 |
| 2 | 명명 | 모듈/파일/함수/변수가 의미와 크기에 맞는 이름인가 |
| 3 | SOLID | SRP/OCP/LSP/ISP/DIP 위반이 어디 있는가 |
| 4 | 아키텍처 (Post-MVVM) | 현 MVVM 패턴이 유효한가, 더 나은 대안이 있는가 |
| 5 | 타입 시스템 | illegal states를 컴파일 차원에서 차단하고 있는가 |
| 6 | 크로스 플랫폼 | Android 포팅 시 코드/테스트/스펙을 어디까지 공유하는가 |

원칙:

- 본 문서는 *액션 후보*. 즉시 착수 안 함. 보호 영역(계산/정책/타이머/영속성)은 spec ticket 선행.
- "사람이 읽기 쉬운 형태"가 1차 기준. 분할이 *컨텍스트 점프 거리를 줄이는 경우에만* 권고.
- 패러다임 교체보다 **경계 재조정**을 선호. TCA·Redux·KMP 즉시 도입은 비-목표.

---

## 2. 진단 렌즈

### 2.1 인지복잡도

LOC가 아니라 **한 함수를 읽을 때 머리에 담아야 하는 협력자 수**가 metric.

| 등급 | 파일 | 비고 |
|---|---|---|
| ✓ 모범 | `ExposureCalculator.swift` (358L), `ReciprocityDomain.swift` (495L), `TimerCompletionNotificationScheduler.swift` (91L), `CompletedRelativeTimeFormatter.swift` (74L) | 의존성 최소, 단일 책임 |
| ◯ 큰데 cohesive | `ReciprocityCalculationPolicy.swift` (1,685L) | 6-step evaluator가 곧 계약. **분할 비-목표** |
| ✗ 위반 | `ExposureCalculatorViewModel.swift` (2,439L · 11 타입) | calc + timer + reciprocity + film + persistence + lock screen 6 책임. **가장 큰 부채** |
| ✗ 위반 | `ExposureCalculatorScreen.swift` (3,158L · ~46 타입) | 5+ 서브섹션 혼재 |
| ✗ 위반 | `BottomSheetWorkspaceShell.swift` (1,710L · 33 타입) | 셸 + 상태머신 + 스냅샷 팩토리 |
| ✗ 위반 | `ExposureCalculatorFilmContext.swift` (271L · **28 타입**) | 271줄에 28 타입 = 평균 ~10L/타입. 3 책임 동거 |
| △ 의심 | `TimerManager.swift` (656L · 16 타입) | lifecycle + persistence + notification scheduling + lock screen coord |

함수 단위 cyclomatic complexity 측정은 미실시 — **B2가 첫 측정**. 추정컨대 ViewModel의 `applyXxxToFilmMode`류, TimerManager restore 분기가 함수 CC 최고치.

### 2.2 명명

| 패턴 | 진단 |
|---|---|
| ✓ 좋은 사례 | `stabilityEpsilon` (이유 설명), `*Storing`/`NoOp*` 페어 (일관), `*Scheduling` 어댑터 |
| ✗ 다중 의미 | **`FilmContext`** = 임시 작업 상태 + 영속 스냅샷 + 23 display state — 한 이름이 3 의미 |
| ✗ 노이즈 접미사 | **23 타입이 모두 `*DisplayState`** — 공통 *의미*가 아니라 공통 *위치*라서 동일 접미사 |
| ✗ 다층 메타포 | **`BottomSheetWorkspaceShell`** = UI 요소(bottom sheet) + 추상(workspace) + 메타포(shell) — 하나만 남기면 명료 |
| △ | `*State`가 도메인(`TimerState`)과 디스플레이(`FilmSelectionDisplayState`) 양쪽. 후자는 `*DisplayState`로 일관 가능 |

**원칙**: 잘못된 크기의 컨테이너가 generic 이름을 끌어당김. **분할 후에야 이름이 자연스러워짐**. 분할 우선, 이름은 부산물.

### 2.3 SOLID

| 원칙 | 진단 |
|---|---|
| **S** Single Responsibility | ExposureCalculator/ReciprocityDomain/Policy/Confidence 모범. **ViewModel(6)/TimerManager(3)/FilmContext(3)/BottomSheetShell(3)/Screen(?) 위반** |
| **O** Open/Closed | 정책/도메인이 *의도적으로* closed (보호 영역) — 안전 결정. 단 UI 카드 variant 확장점 미설계 — 장기 함정 |
| **L** Liskov | `Storing` 페어가 LSP 약점 (NoOp은 출력 분포 다름) — DIP 정리되면 자연 개선 |
| **I** Interface Segregation | `Storing` 분리 좋음. SwiftUI `@Published` 다수는 ISP 부분 위반이지만 SwiftUI 동작 특성. ViewModel 분할 시 자연 개선 |
| **D** Dependency Inversion | **`XCTestRuntime.isRunningTests` production-init branching이 정면 위반**. ViewModel이 구체에 직접 의존 |

**한 줄**: SRP가 단연 큰 부채, DIP는 작지만 효과 큼, O/L/I는 종속 변수.

### 2.4 아키텍처 — Post-MVVM 렌즈

iOS 커뮤니티 추세 (2025–2026):

| 패턴 | 본 코드베이스 적합도 |
|---|---|
| **MV (no VM)** — Apple 공식 샘플의 추세 | **부적합** — calc/timer/policy 결합이 복잡해 view-direct는 다시 큰 view |
| **`@Observable` + 작은 모델 여러 개** (iOS 17+) | ★ **가장 맞음** — 패러다임 교체 아님, **경계 재조정** |
| **TCA (The Composable Architecture)** | 과한 비용. 테스트 인프라 단단 — TCA가 해결할 페인 적음 |
| **Redux-like 단일 store** | 마찬가지로 과함 |

**결론**: MVVM 유지 + ViewModel 4분할 (`CalculatorModel` + `ReciprocityModel` + `TimerWorkspaceModel` + `FilmSelectionModel`) + 가벼운 coordinator. 이는 SRP 액션이며 **동시에** SOLID·인지복잡도·이름·ISP를 모두 개선.

### 2.5 타입 시스템 — illegal states unrepresentable

런타임 검증을 컴파일 보장으로 끌어올릴 후보:

| 위치 | 현재 표현 | 가능 표현 |
|---|---|---|
| Reciprocity result | `didReturnCalculatedTime: Bool` + `correctedExposure: T?` (디코딩에서 모순 검증 — PTIMER-90) | `enum Result { quantified(T) / advisoryOnly(notes) / unsupported(reason) }` — 모순 컴파일 차단 |
| Timer state | enum + 상태별 valid 필드 페어링 (`endDate?` `pausedRemainingTime?`) | (a) 현재 유지 / (b) phantom-typed `Timer<Running>`/`Timer<Paused>` / (c) state-specific structs |
| Calculator workflow | film 선택 여부로 분기 | `enum Workflow { digital(...) / film(...) }` — case별 valid 필드 보장 |

**효과**: 런타임 검증 코드 감소, 디코더 반려 케이스 감소, 상호 배타 분기 누락 차단.

### 2.6 크로스 플랫폼 / Clean Architecture

| 옵션 | 어떤 것 공유 | 비용 | ROI |
|---|---|---|---|
| A. Independent native (현 PortPlan) | 사양·테스트 fixture만 | 모든 변경 2x | 1인 사이드 단계 OK |
| **B. Spec parity + shared test fixture** | 카탈로그 JSON + 골든 입출력 | 작음 (golden file 인프라) | ★ **1단계 권장** |
| C. KMP shared module | 도메인/정책/데이터 코드 자체 | 큼 (Swift→Kotlin 재작성, FFI, 디버깅) | 양 플랫폼 출시 + 도메인 변경 잦을 때 |

**현 단계**: **B로 시작**. C(KMP)는 양 플랫폼 출시 + 도메인 진화 속도 검증 후 평가.

### 2.7 핫스팟 인벤토리 (5렌즈 점수 종합)

(`✓` 모범 / `△` 주의 / `✗` 위반 / `n/a` 해당 없음)

| 파일 | 라인·타입 | CC | 명명 | SRP | DIP | 결론 |
|---|---|---|---|---|---|---|
| `ExposureCalculatorViewModel.swift` | 2,439·11 | ✗ | △ | ✗✗ | ✗ | **High 부채** (다관점 최악) |
| `ExposureCalculatorScreen.swift` | 3,158·46 | ✗ | ✓ | ✗ | n/a | **High 부채** |
| `BottomSheetWorkspaceShell.swift` | 1,710·33 | △ | ✗ 메타포 | ✗ | n/a | **High 부채** |
| `ExposureCalculatorFilmContext.swift` | 271·**28** | △ | ✗ 다중의미 | ✗ | n/a | **High 부채** |
| `TimerManager.swift` | 656·16 | △ | ✓ | ✗ | △ | **Medium 부채** |
| `ReciprocityCalculationPolicy.swift` | 1,685·21 | △ in 함수 | ✓ | ✓ | ✓ | OK (응집) |
| `ReciprocityConfidencePresentation.swift` | 691·9 | ✓ | ✓ | ✓ | ✓ | OK |
| `ReciprocityDomain.swift` | 495·30 | ✓ | ✓ | ✓ | ✓ | OK |
| `ExposureCalculator.swift` | 358·4 | ✓ | ✓ | ✓ | ✓ | **모범** |
| `PresetFilmCatalog.swift` | 206·4 | ✓ | ✓ | ✓ | ✓ | OK |

**디렉토리 부담**:
- `PTimer/App/` — entry + ContentView + 1,710L 워크스페이스 셸 동거
- `PTimer/ExposureCalculator/` — FilmContext 단일 파일에 28 타입
- `PTimerTests/` — `ExposureCalculatorViewModelTests.swift` 3,240L · `BottomSheetWorkspaceShellTests.swift` 1,735L 모놀리스

---

## 3. 액션 카탈로그

24개 액션을 **8개 테마**로 그룹. 기존 A1-A12 유지 + 신규 B1-B13. 각 행 한 줄: 액션·효과·비용·위험·Spec 선행 여부·Phase.

비용: **S** 작음 (1-2일) / **M** 중간 (1주) / **L** 큼 (>2주). 위험: 보호 영역 인접도 + 시그니처 변경 범위.

### 3.1 Hygiene & Tooling

| # | 액션 | 효과 | 비용 | 위험 | Spec | Phase |
|---|---|---|---|---|---|---|
| A5 | `.gitignore` 확장, 임시 파일 제거, SwiftLint baseline 설정. **CI workflow는 Phase 1로 이연** — Bitbucket Pipelines / GitHub Actions / Xcode Cloud / 로컬 hook 중 플랫폼 결정 필요 | 1차 리뷰 Tier 1+2 충족, PR 게이트 확보 (CI 부분은 결정 후) | S | Low | No | 0 (lint·.gitignore) / 1 (CI) |
| A6 | README 아키텍처 1단락 + handoff appendix import | onboarding 가속 | S | None | No | 0 |
| A7 | CLAUDE.md 부록 (명명·레이어 가이드) | 신규 코드 일관성 | S | None | No | 0 |
| **B2** | SwiftLint에 `cyclomatic_complexity`/`function_body_length` 한도. hot 함수 5개 식별 | 인지복잡도 *데이터 기반* 분할 우선순위 | S | Low | No | 1 |
| **B13** | `xcrun llvm-cov` 도입 → 커버리지 % 측정. CurrentState §5 매트릭스 보강 | 보장 가시화, 회귀 차단 | S | None | No | 1 |

### 3.2 Structural Split (저위험, 시그니처 동결)

| # | 액션 | 효과 | 비용 | 위험 | Spec | Phase |
|---|---|---|---|---|---|---|
| A1 | `App/Workspace/` 7-way split (`git mv`) | 1,710L → 7파일 (~80–400L 각) | M | Low | No | 2 |
| A2 | `ExposureCalculator/FilmContext/` 4-way split | 271L · 28 타입 → 4파일 | M | Low | No | 2 |
| A11 | 거대 테스트 파일 주제별 분할 | 탐색 비용↓ (테스트 navigator 그룹화) | M | Low | No | 2 |

### 3.3 Architecture: Post-MVVM (Spec 선행)

| # | 액션 | 효과 | 비용 | 위험 | Spec | Phase |
|---|---|---|---|---|---|---|
| **B1** | ViewModel 4분할: `@Observable` `CalculatorModel` + `ReciprocityModel` + `TimerWorkspaceModel` + `FilmSelectionModel` + 가벼운 `WorkspaceCoordinator` | SRP 단연 큰 부채 해소 + ISP/I/CC 자연 개선. **다관점 최대 ROI** | **L** | High (보호 영역 인접) | **Yes** | 3 |
| A8 | `FilmModeDetailsPresenter` 추출 (B1의 점진적 1단계) | ViewModel 슬림화 시작점 | M | Med-High | **Yes** | 2 |
| A9 | `LockScreenTimerCoordinator` 분리 (B1의 점진적 2단계) | ViewModel ownership 1건 이동 | M-H | High (타이머 시맨틱) | **Yes** | 3 |
| **B5** | 분할 후 명명 패스 — `FilmContext` 분해 결과물 + `*DisplayState` 접미사 정리. CLAUDE.md 부록에 패턴 명문화 | 분할 부산물로 자연스러움 | S | Low | No | 2/3 |

### 3.4 Type Safety (Spec 선행, illegal states 차단)

| # | 액션 | 효과 | 비용 | 위험 | Spec | Phase |
|---|---|---|---|---|---|---|
| **B3** | Reciprocity result를 `enum Result { quantified(T) / advisoryOnly / unsupported }`로 — 현재 `didReturnCalculatedTime: Bool + correctedExposure: T?` 페어 대체 | 디코딩 모순 검증(PTIMER-90) 코드 제거. illegal states 컴파일 차단. JSON 디코더는 backward-compat 유지 | M | Med (보호 영역 — 시맨틱 동등 검증 필수) | **Yes** | 3 |
| **B4** | Timer state 강화 — 4 옵션 검토 후 채택: (a) 현 enum 유지 / (b) phantom-typed `Timer<Running>`/`Timer<Paused>` / (c) state-specific structs / (d) actor isolation. spec에서 트레이드 정리 | 불법 transition 컴파일 또는 런타임 차단 | M-L | Med-High | **Yes** | 3 |

### 3.5 Side Effects & DI

| # | 액션 | 효과 | 비용 | 위험 | Spec | Phase |
|---|---|---|---|---|---|---|
| A4 | DI factory 도입 — `XCTestRuntime.isRunningTests` 분기 제거. App entry에서 production/test factory 주입 | DIP 정면 위반 해소. LSP 자연 개선 | M | Med (init 시그니처 변경) | **Yes** | 1 |
| **B9** | 핫 패스 동시성 측정 — picker 스크롤 → 정책 평가 frame budget. 결과에 따라 actor 분리 | 메인 스레드 압박 사전 차단 | S (측정), M (분리) | Low (측정만) / Med (분리) | No | 1 (측정), 3 (분리) |
| **B10** | 에러 모델 통일 — 현재 Optional/throws/precondition 혼재. 도메인은 `Result`/`throws`, presentation은 Optional 정책 명문화 (CLAUDE.md 또는 별도 문서) | 일관, 누락 검증 차단 | M | Low | No | 2 |

### 3.6 Testing

| # | 액션 | 효과 | 비용 | 위험 | Spec | Phase |
|---|---|---|---|---|---|---|
| A3 | Widget/ActivityKit/Notification fake/spy 통합 테스트 | 1차 리뷰 R-H1 해소 | M | Med (fake 작성) | No | 1 |
| **B8** | SwiftUI snapshot 테스트 (`pointfreeco/swift-snapshot-testing`) — `Screen.swift`·`BottomSheetShell.swift`·필름 모드 결과 카드 | UI 회귀 lock (UI 테스트 인프라 도입 비용 회피) | M | Low | No | 2 (구조 분할 후) |

### 3.7 Cross-Platform (Android 포팅 전제)

| # | 액션 | 효과 | 비용 | 위험 | Spec | Phase |
|---|---|---|---|---|---|---|
| **B6** | Spec parity + shared test fixture — `shared/test-fixtures/`에 카탈로그 JSON + 골든 입출력 fixture(Reciprocity·Exposure). iOS Tests + Android Tests 모두 같은 fixture 소비 | 안드로이드 도메인 등가 보장의 **최저 비용** 메커니즘. AndroidPort/TestParity의 자동 검증화 | M | Low | No | 2 |
| **B7** | KMP 검토 spike (시간제한 1주) — 도메인/정책을 KMP 모듈로 옮겼을 때 빌드·FFI·디버깅 비용 측정. `./KMPSpike.md` 보고서로 go/no-go | 장기 단일 모듈 가능성 평가 (ROI 데이터) | S (spike) | Low (조사만) | No | 3 (Android 출시 후) |

### 3.8 Domain Data & Misc

| # | 액션 | 효과 | 비용 | 위험 | Spec | Phase |
|---|---|---|---|---|---|---|
| A10 | `ExposureCalculatorScreen.swift` metrics + 1–2 자족 nested view 추출 | 인지복잡도 부분 완화 | M | Med (SwiftUI 바인딩 표면) | No | 2/3 |
| A12 | Tri-X 1s 카탈로그 데이터 reconciliation (위키 15138817) | 권위 일치, 사용자 노출 정확화 | M | High (사용자 노출 변경) | **Yes** | 3 |
| **B11** | (옵션) DocC 또는 인라인 doc 강화 — `Docs/Specs/`가 우선이므로 후순위 | onboarding | S | None | No | 후순위 |
| **B12** | (옵션) 디자인 토큰 (color/spacing/typography) 추출 — 현재 미충돌, 트리거 발생 시 | 디자인 일관성 | S | None | No | 후순위, 트리거 시 |

### 3.9 진행 현황 (Progress)

PTIMER-118 구현 진행을 액션별로 기록. **Done** = 머지된 commit으로 인수 기준 만족. **In Progress** = PR 일부 머지, 잔여 PR 있음. **Pending** = 미착수.

| 액션 | 상태 | 완료 commit / 비고 |
|---|---|---|
| A1 BottomSheet split | **Done** | `App/Workspace/` 7파일 분할 |
| A2 FilmContext split | **Done** | `ExposureCalculator/FilmContext/` 5파일 분할 |
| A3 Widget/ActivityKit 통합 테스트 | **Done** | 직접 테스트 9건 추가 (`PTimerTests/Timers/LockScreenTimerCoordinatorTests.swift`) — `SpyExposer` 기반. ViewModel 통합 테스트와 별도. |
| A4 DI factory | **Done** | `d57452c` ViewModelDependencyFactory + SwiftLint F1/F2 |
| A5 Repo hygiene | **Done** | `.gitignore` 확장 + SwiftLint baseline |
| A6 README 아키텍처 | **Done** | 1단락 추가 |
| A7 CLAUDE.md 부록 | **Done** | Companion docs and conventions 섹션 |
| A8 FilmModeDetailsPresenter | **Done** | `7081d64` ViewModel 2500→1318L (~1182L 추출) |
| A9 LockScreenTimerCoordinator | **Done** | 타입을 `Timers/`로 이동 + Combine publisher 구독으로 자율 동기화. `syncTimers`의 직접 호출 제거. SwiftLint `no_activitykit_in_viewmodel` rule 추가. lifetime은 ViewModel이 보유 (DI seam 이동은 B1에 흡수) |
| A10 Screen 추출 | **Done** | `4fc3dea` LayoutMetrics + RunningTimerPanel 분리 |
| A11 테스트 파일 분할 | **Done** | ViewModelTests + BottomSheetShellTests 주제별 분할 |
| A12 Tri-X 데이터 reconciliation | **Done** | `1239854` 1s entry 위키 일치 |
| B1 ViewModel 4분할 | **Done** | Spec 완료. 6 PR 머지: PR1 `0020f1c` WorkspaceCoordinator + CalculatorModel · PR2 `bb88c7e` ReciprocityModel (정책 평가 facade, A8 Presenter 흡수) · PR3 `342e5fa` TimerWorkspaceModel (timer collection · metadata persistence · lifecycle ops · completed-time refresh) · PR4 `a121d9e` FilmSelectionModel (preset 카탈로그 · 활성 film identity · 컨텍스트 영속화 · authority label) · PR5 `694c5ab` view-migration preparation (`WorkspaceCoordinator: ObservableObject`, screen이 coordinator를 `@StateObject`로 직접 보유) · PR6 본 PR lint F5/F8 + ViewModel 1,168→1,127L slim (`shutterSpeeds` hoist + dead back-compat init 제거) + 모든 baseline byte-identical. **carry-forward**: leaf view 직접 관찰 마이그레이션은 단일-모델 boundary를 가진 production view가 부재하여 §4 invariant 준수 차원에서 보류, ViewModel은 lightweight orchestration facade로 잔존. fitness rule(F5/F8)이 모델 재합성 차단. |
| B2 SwiftLint CC 한도 | **Done** | `.swiftlint.yml`에 function/file/type body + CC 임계값 추가. hot 함수 인벤토리는 `HotFunctions.md` |
| B3 Reciprocity Result enum | **Done** | PR1 `79b6842` baseline freeze (77 cases · 2430 lines) → PR2 `6a868b1` enum migration (byte-identical legacy replay) → PR3 lint F11 + spec §3.5 갱신 |
| B4 Timer state types | **Done** | 3 PR 머지: PR1 `5425852` baselines (6 시나리오) + PR2 `2f02ea3` sum-type migration (`TimerState` enum + `RunningTimer`/`PausedTimer`/`CompletedTimer` payload structs + backward-compat init; record-replay byte-identical) + PR3 본 PR (lint F12 `no_legacy_timer_state_struct_init` + Timer Spec §1.1/§3.1 sum-type representation 메모) |
| B5 명명 패스 | **Done** | `416a13b` CLAUDE.md에 Coordinator/Presenter/Factory/모듈-prefix 규칙 추가 |
| B6 Spec parity fixture | **Done** | `ea666bc` `shared/test-fixtures/` 3 golden JSON |
| B7 KMP spike | **Pending** | Android 출시 후 |
| B8 Display state snapshot | **Done** | `8eb65d3` Lightweight Swift.dump-based snapshot harness + 9 baseline scenarios (Tri-X exact/interp/extrap, Velvia threshold, HP5 formula, Portra advisory, confidence presentations, catalog snapshot). View-pixel snapshot은 별도 (필요 시 image-snapshot 확장) |
| B9 핫 패스 동시성 측정 | **Done (measurement)** | XCTMeasure 5 케이스 추가. 결과: per-evaluate ~30–84μs = frame budget의 ~0.5%. **actor 분리 비-필요**. 재측정 트리거는 `HotPathConcurrency.md` |
| B10 에러 모델 통일 | **Done** | `6f57476` `Docs/Conventions/ErrorModel.md` |
| B13 Coverage 측정 | **Done** | 테스트 plan에 `codeCoverage` 활성화. baseline = 54.57% (도메인 88–94%, view 0–35%). 절차 + 분석은 `Coverage.md` |
| Record-replay 인프라 | **Done** | `PTimerTests/RecordReplay/` 5 파일 (Trace/Baseline/Spies/Harness + smoke test) + 1 baseline. B8 패턴 재사용 (env `RECORD_REPLAY=1`로 재기록). B1/B3/B4의 L2 semantic-equivalence 게이트로 사용. 절차는 `Docs/Verification/Strategy.md` §6 |

**완료 요약**: 24 액션 + record-replay 인프라 중 22 + 1 = 23 Done, 1 Pending. Phase 0/1/2 완료. Phase 3은 B3 + B1 + B4 머지 완료. 잔여 Pending = B7 (KMP spike, Android 출시 후).

### 3.10 Post-Epic 후속 작업 (PTIMER-118 review follow-ups)

PTIMER-118 머지 후 코드 리뷰에서 surface 한 P0/P1/P2 항목들의 정리 commit 들. 본 Plan 의 24 액션과는 별도 cycle이지만 Epic 완료 직후 발생했으므로 progress 추적 차원에서 동일 표에 기록.

| 항목 | 상태 | Commit / 비고 |
|---|---|---|
| P0-1 Calculator §2.4 spec wording (power-of-two) | **Done** | `c36f1ca` |
| P0-2 DomainSchema §6/§13.4 spec wording (B3 enum) | **Done** | `c36f1ca` |
| P0-3 TimerManager.start `+Infinity` guard | **Done** | `9ae4709` |
| P0-4 PausedTimer.endDate stored→computed | **Done** | `388096f` + `9cc1433` (corner test fixup) |
| Group A cleanup (HotFunctions.md / WorkspaceCoordinator doc / VM dead code / Persistent prefix rename / xctestplan widget coverage) | **Done** | `92b8731` |
| P1-4 B1 facade trim — 4a reciprocity formatters + ISO inference | **Done** | `4a7a16f` |
| P1-4 B1 facade trim — 4b corrected-exposure display composers | **Done** | `c913824` |
| P1-4 B1 facade trim — 4c-1 type relocation (RunningTimerItem, TimerMetadataPersistence) | **Done** | `0b219aa` |
| P1-4 B1 facade trim — 4c-2 live preview overlay → CalculatorModel | **Done** | `edba82d` |
| P1-8 Screen extraction — FilmModeDetailsView | **Done** | `df4d163` |
| P1-8 Screen extraction — WheelPickerContinuousObserver | **Done** | `0865fb1` |
| Phase A — UI §2.1 / DomainSchema §13.5 wording corrections | **Done** | `4783e33` |
| Phase B — F11 / F12 / F5 lint regex tighten + F8 message + xctestplan env reset | **Done** | `76c1cce` (later partially reverted by `2e46734`) |
| Phase C — Paused-snapshot restore reject + back-compat init contract + Date() determinism in tests | **Done** | `403791a` |
| Phase D — ViewModel cross-cutting display-state baselines (P1-7) | **Done** | `2e46734` |
| Phase D — Shared exposure-golden / catalog-validation fixture iOS consumer (P2-2) | **Done** | `03b100e` |
| Phase E — User-scenario-driven Requirements doc | **Done** | `8a5ebf7` (`Docs/Requirements/Requirements.md`) |
| P2-3 record-replay missing scenarios (force-quit relaunch with paused timer; resume-zero) | **Carry-forward** | RecordReplayHarness 가 in-process 시뮬에 한정되어 force-quit relaunch path 시뮬에 적합치 않음. 별도 인프라 확장 ticket. |
| P2-8 TimerManagerTests.swift 분할 (1,885L) | **Carry-forward** | A11 의 누락분이지만 file split 비용 대비 가치 낮음. 별도 ticket 시 진행. |

**Post-Epic 작업 요약**: 4 P0 + Group A + 5 P1 + 4 Phase 항목 = 14 commit. Phase E `Docs/Requirements/Requirements.md` 신설은 Epic 의 *요구사항 layer 부재* 갭을 채움. 2 항목 carry-forward (별도 ticket).

ViewModel 사이즈: 2,439L (Epic 시작) → 1,127L (Epic 종료) → **725L** (post-Epic facade trim). Screen 사이즈: 3,158L → 2,911L → **1,567L** (post-Epic Screen 추출, Plan §6 1,500 target 거의 달성).

---

## 4. 실행 로드맵

```
Phase 0  Hygiene · Doc (즉시)
   A5(repo hygiene), A6(README), A7(CLAUDE 부록)
                                              │
Phase 1  Stabilize · Side Effects · Measure   ▼
   A4(DI factory, **Spec 선행**)                    ◄── DIP 핵심
   A3(Widget/ActivityKit 통합 테스트)               ◄── R-H1
   B2(CC 한도 + hot 함수 식별)                      ◄── 데이터 기반 우선순위
   B13(coverage 측정)                              ◄── 보장 가시화
   B9(핫 패스 측정만)                               ◄── 동시성 결정 근거
                                              │
Phase 2  Structural Split · Test 분할          ▼
   A1(BottomSheet split) ║ A2(FilmContext split)   (병렬, 디렉토리 다름)
   A11(테스트 분할), B8(SwiftUI snapshot)
   B5(명명 패스), B10(에러 모델 통일)
   B6(Spec parity fixture, Android 전제)
   A8(FilmModeDetailsPresenter, **Spec 선행**)      ◄── A2 안정 후
   A10(Screen 부분 추출)
                                              │
Phase 3  Architecture · Type Safety            ▼
   B1(ViewModel 4분할, **Spec 선행 필수**)          ◄── A2/A8/A9 누적 결과
   A9(TimerCoordinator, B1의 부분)
   B3(Reciprocity Result enum, **Spec 선행 필수**)
   B4(Timer state 타입 강화, **Spec 선행 필수**)
   B9(actor 분리, B9 측정 결과 따라)
   A12(Tri-X 데이터 reconciliation, **Spec 선행 필수**)
   B7(KMP spike, Android 출시 후)
```

**중요 의존**:
- B1 ⇐ A2(FilmContext 분해) ⇐ A8(Presenter 추출) ⇐ A9(Coordinator 분리) — *점진적 ownership 이동*
- B3/B4 ⇐ B1 (모델 분할이 type-driven 변경의 표면적 정리)
- B7 ⇐ B6 (Spec parity → KMP는 같은 fixture 재사용)
- B8 ⇐ A1/A10 (분할 후에야 snapshot이 의미)

**머지 원칙**:
- 한 PR = 한 액션 (섞지 않음).
- 모든 PR은 본 문서 + 관련 Spec + (해당 시) 1차 리뷰 위키 19103745 인용.
- Branch 명명: `feature/PTIMER-<EpicID>-<slug>`. Commit body 마지막 줄 `PTIMER-<ID> Title`.
- 보호 영역 인접 액션(A4/A8/A9/A12/B1/B3/B4)은 **spec ticket 머지 후** 별도 PR.

---

## 5. 분할/이동의 일반 원칙

1. **단순 split (A1/A2/A11)**: 시그니처/시맨틱 변경 금지. *형식*만 바꿈. `git mv` 사용.
2. **Spec-required (A4/A8/A9/A12, B1/B3/B4)**: 시그니처 또는 데이터 변경 가능. spec ticket이 *변경 범위 + invariant*를 명시해야 머지 가능.
3. **테스트 변경 없음 (A1/A2/A10/A11)**: 케이스 추가/삭제 금지, 위치만 이동.
4. **테스트 추가가 목적 (A3/B8)**: 본 ticket의 *목적*이 테스트 신설.
5. **타입 변경 (B3/B4)은 데이터 마이그레이션과 별도**: 디코더는 backward-compatible 유지. 신규 enum 케이스가 기존 JSON에서 합성 가능해야 함.
6. **보호 영역 시맨틱 변경 금지**: B3/B4는 *표현 형태*만 바꾸고 시맨틱은 동등 유지 (spec invariant 검증 의무).
7. **CI/lint 통과 + 시뮬레이터 빌드 + 전체 테스트 통과**가 머지 조건.

---

## 6. 영향 받는 디렉토리 트리 (목표 상태)

Phase 2/3 완료 후 의도된 구조:

```
ptimertrycodex/
├── PTimer/
│   ├── App/
│   │   ├── PTimerApp.swift
│   │   ├── ContentView.swift
│   │   └── Workspace/                                       (A1)
│   │       ├── BottomSheetWorkspaceShell.swift
│   │       ├── BottomSheetWorkspaceStateStore.swift
│   │       ├── BottomSheetWorkspaceSnapshotStore.swift
│   │       ├── BottomSheetWorkspacePresentationAdapter.swift
│   │       ├── BottomSheetWorkspaceSnapshot.swift
│   │       ├── BottomSheetWorkspaceMetrics.swift
│   │       └── BottomSheetWorkspaceActions.swift
│   ├── ExposureCalculator/
│   │   ├── ExposureCalculator.swift                         (모범, 변경 없음)
│   │   ├── ExposureCalculatorScreen.swift                   (A10 후 ~1,500L 목표)
│   │   ├── PresetFilmCatalog.swift
│   │   ├── FilmContext/                                     (A2)
│   │   │   ├── ExposureCalculatorWorkingContext.swift       (transient)
│   │   │   ├── PersistedCalculatorContext.swift             (영속 + Storing)
│   │   │   ├── FilmSelectionDisplayState.swift
│   │   │   ├── FilmModeResultDisplayStates.swift
│   │   │   └── FilmModeDetailsDisplayStates.swift
│   │   ├── Models/                                          (B1, Phase 3)
│   │   │   ├── CalculatorModel.swift                        (@Observable)
│   │   │   ├── ReciprocityModel.swift
│   │   │   ├── TimerWorkspaceModel.swift
│   │   │   ├── FilmSelectionModel.swift
│   │   │   └── WorkspaceCoordinator.swift
│   │   └── Coordinators/                                    (A8/A9 → B1로 흡수)
│   ├── Reciprocity/                                         (변경 없음 — 응집)
│   ├── Timers/                                              (A9: Coordinator 외부 이동)
│   └── Resources/
├── PTimerWidgets/                                           (A3로 테스트만 추가)
├── PTimerTests/                                             (A11)
│   ├── ExposureCalculator/
│   │   ├── ExposureCalculatorTests.swift
│   │   ├── ExposureCalculationAccuracyTests.swift
│   │   ├── LaunchPresetFilmCatalogTests.swift
│   │   ├── (B1 후) CalculatorModelTests.swift
│   │   ├── (B1 후) ReciprocityModelTests.swift
│   │   ├── (B1 후) TimerWorkspaceModelTests.swift
│   │   └── (B1 후) FilmSelectionModelTests.swift
│   ├── App/
│   │   ├── BottomSheetWorkspaceShellTests.swift
│   │   ├── BottomSheetWorkspaceSnapshotFactoryTests.swift
│   │   ├── BottomSheetWorkspaceOrderingTests.swift
│   │   ├── BottomSheetIdentityPaletteTests.swift
│   │   ├── ActivityKitExposerTests.swift                    (A3)
│   │   └── ScreenSnapshotTests.swift                        (B8)
│   ├── Reciprocity/
│   └── Timers/
│       ├── TimerManagerTests.swift
│       ├── CompletedRelativeTimeFormatterTests.swift
│       └── UserNotificationSchedulerTests.swift             (A3)
└── shared/                                                  (B6 신설)
    └── test-fixtures/
        ├── reciprocity-golden.json
        ├── exposure-golden.json
        └── catalog-validation-cases.json
```

---

## 7. 명시적 비-목표

본 액션 플랜은 다음을 *수행하지 않는다*:

- **TCA 도입 안 함** — 테스트 인프라가 이미 단단, TCA가 해결할 페인 적음
- **Redux-like 단일 store 안 함** — 본 앱 규모에 과함
- **MV (no VM) 패턴 안 함** — calc/timer/policy 결합이 복잡해 view-direct는 다시 큰 view
- **KMP 즉시 도입 안 함** — B7 spike 결과로만 결정. Android 출시 전엔 B6 spec parity로 충분
- **Reciprocity Domain / Policy / ConfidencePresentation 분할 안 함** — 응집됨, 위키 권위(PTIMER-90, 16482307)와 일치
- **도메인 enum/구조체의 *시맨틱* 변경 안 함** — B3/B4는 *표현 형태*만 바꾸고 시맨틱 동등 유지
- **영속성 키 변경 안 함** — backward-compat 디코더로만 형식 진화
- **새 기능 추가 안 함** — 4-변수 가변 노출 모델, 카탈로그 34종 확장 등은 별도 Epic

---

## 8. 검증 / Done 기준

| 액션 | Done 기준 |
|---|---|
| A1 | 7개 파일이 `App/Workspace/`, 모든 단위 테스트 동등, 시뮬레이터 스모크 통과 |
| A2 | 4–5개 파일이 `ExposureCalculator/FilmContext/`, ViewModelTests 동등, 컨텍스트 영속성 회귀 없음 |
| A3 | 신규 fake/spy 통합 테스트 pass, 기존 테스트 영향 없음 |
| A4 | `XCTestRuntime.isRunningTests` production-init 분기 제거, factory 단위 테스트 추가, 시뮬레이터 빌드 통과 |
| A5 | (Phase 0) `.gitignore`가 zip/temp 차단 + SwiftLint baseline config 존재 + 로컬 lint pass. (Phase 1) CI 플랫폼 결정 후 PR 자동 lint·build·test 실행 |
| A6 | README 아키텍처 1단락 |
| A7 | CLAUDE.md 부록 단락, 향후 PR이 인용 |
| A8 | Presenter 단독 파일, ViewModelTests + Presenter 단위 테스트 통과 |
| A9 | Coordinator 단독 파일, TimerManagerTests + 신규 단위 테스트 + 잠금화면 메뉴얼 검증 통과 |
| A10 | metrics + 1–2 컴포넌트 추출, 3-density 메뉴얼 스모크 통과 |
| A11 | 모든 테스트 케이스 동등 통과, Xcode test navigator 그룹 표시 |
| A12 | 카탈로그 데이터 변경 + 정책 평가 단위 테스트 통과 + 신규 1s metered 케이스, 사용자 메뉴얼 검증 |
| **B1** | 4 모델 + coordinator, ViewModel 모놀리스 100% 분해, 모든 ViewModelTests 동등 + 모델별 단위 테스트 신규 |
| **B2** | SwiftLint config에 `cyclomatic_complexity`/`function_body_length` 한도, hot 함수 5개 보고서 |
| **B3** | Reciprocity result enum, JSON 디코더 backward-compat 검증, `didReturnCalculatedTime` 모순 검증 코드 제거, 정책 시맨틱 동등 |
| **B4** | 채택 옵션의 spec invariant가 모두 컴파일 또는 unit test로 검증 |
| **B5** | 분할 후 신규 파일 명명이 일관, CLAUDE.md 부록 인용, lint 통과 |
| **B6** | `shared/test-fixtures/` 신설, 양 플랫폼 단위 테스트 같은 fixture 소비, AndroidPort/TestParity 자동 검증 |
| **B7** | `./KMPSpike.md` 보고서, go/no-go 판단 + 비용 추정 |
| **B8** | Screen + BottomSheetShell + 결과 카드 snapshot 테스트가 PR 게이트 |
| **B9** | picker 스크롤 frame budget 측정 보고서, 메인 스레드 시간 < 임계 (또는 actor 분리 결정) |
| **B10** | 에러 모델 가이드 (CLAUDE.md 또는 별도 문서), 모든 신규 코드가 인용 |
| **B13** | 커버리지 % 보고서 (레이어별), 매 마일스톤 갱신 |

엔드 투 엔드 done:
- *Phase 0/1*은 빠르게 완료 (A3/A4/A5/A6/A7 + B2/B9 측정/B13) — 즉시 가치
- *Phase 2*는 구조 분할 + 테스트 분할 + 명명 (A1/A2/A8/A10/A11 + B5/B6/B8/B10) — 코드 탐색 비용 명확히 감소
- *Phase 3*는 *충분한 spec*이 있을 때만 (A9/A12 + B1/B3/B4/B7)
- 각 PR이 본 문서 + Spec 인용

---

## 9. 후속 갱신

본 문서는 *살아있는* 문서. 갱신 트리거:

- 1차 리뷰 권고 Tier 1/2/3 중 하나라도 머지되면 §3 표 갱신 + done 표시
- 새 부담 지점 발견 시 §2.7 핫스팟에 추가
- 마일스톤 종료 시점에 §4 실행 순서 재검토 (위키 19070978 hub 운영 원칙)
- 4-변수 가변 노출 모델 Epic 시작 시 §3 우선순위 재정렬 (A8/A9/B1이 그 Epic의 전제 조건이 될 가능성)
- Android 포팅 본격 시작 시 B6/B7 우선순위 상향
- B2/B9/B13 측정 결과가 새 부담 지점을 드러낼 때

---

## 10. 한눈에 정리 (TL;DR)

**렌즈별 부채**:
- **인지복잡도**: ViewModel 2,439L (6 책임), Screen 3,158L, BottomSheetShell 1,710L (33 타입), FilmContext 28 타입
- **명명**: `FilmContext`/`*DisplayState`/`BottomSheetWorkspaceShell` 다중 의미 — *분할 부산물로 해결*
- **SOLID**: SRP가 단연 큰 부채 (ViewModel + 4 큰 파일), DIP 작지만 효과 큼 (DI factory 1건), O/L/I는 종속 변수
- **아키텍처**: MVVM 유지 + `@Observable` 4분할이 정답 (TCA·Redux·MV 비용/가치 미달)
- **타입**: Reciprocity result enum + Timer state 강화로 illegal-states 컴파일 차단
- **크로스플랫폼**: Spec parity (B6) → KMP는 출시 후 평가 (B7 spike)

**즉시 가능 (P0/P1)**:
- A5 hygiene · A6 README · A7 CLAUDE 부록 · B2 CC 한도 · B13 coverage
- A4 DI factory · A3 Widget 테스트 · B9 핫패스 측정

**저위험 분할 (Phase 2)**:
- A1 BottomSheet split · A2 FilmContext split · A11 테스트 분할
- B5 명명 · B6 fixture · B8 snapshot · B10 에러 모델

**Spec 선행 필수 (Phase 3)**:
- A4 · A8 · A9 · A12 · **B1 ViewModel 4분할** · **B3 Result enum** · **B4 Timer types**

**24개 액션, 8개 테마, 4 Phase**. 다관점 최대 ROI 액션 3건 = **A4 (DIP) + A1·A2 (구조 분할) + B1 (Post-MVVM)**.

---

## 11. 검증 전략 (요약)

상세 절차·도구·체크리스트는 **`Docs/Verification/Strategy.md`** 참고. 본 절은 액션 ↔ 검증 레이어 매핑 요약.

### 11.1 5 레이어

| 레이어 | 무엇을 잡나 | 어떻게 |
|---|---|---|
| **L1** Per-action 자동 | 단일 PR build/test/lint 회귀 | A5의 CI |
| **L2** Semantic equivalence | 시그니처/표현 변경의 시맨틱 동등 | spec-driven property test, **record-replay**, golden fixture (B6) |
| **L3** Architectural fitness | 구조 결정의 시간적 침식 | SwiftLint custom rule + SwiftSyntax 검사 |
| **L4** UI 회귀 | View 동작 변화 | B8 snapshot + 매뉴얼 스모크 매트릭스 |
| **L5** Spec-code drift | spec과 코드의 어긋남 | 분기별 audit (B13/B2 시계열 + spec § grep) |

### 11.2 액션 군별 결정적 레이어 (★★ = 의무)

| 액션 군 | 결정적 레이어 |
|---|---|
| 단순 split (A1/A2/A11) | L1 |
| 인프라 (A3/A5/B6/B8/B13) | 자체 검증 |
| DIP/SRP 변경 (A4/A8/A9) | L1 + **L2★★** |
| **ViewModel 4분할 (B1)** | **L2★★ + L3 + L4★★** |
| **Type-driven (B3/B4)** | **L2★★ (record-replay 필수)** |
| 데이터 (A12) | L2★★ + 사용자 메뉴얼 |

### 11.3 PR Verification artifact

각 PR 본문에 5 레이어 적용/비적용 + 증거 링크를 명시. 결정적 레이어 ★★는 의무. 양식: Strategy.md §5.

### 11.4 검증 인프라 단계 도입

| 시점 | 도입 |
|---|---|
| Phase 0 | L1 (CI · A5), L4 매뉴얼 스모크 |
| Phase 1 | B13 (coverage), B2 (CC 한도) → L1 강화 + L5 시계열 시작, A4 후 L3 F1/F2 영구 |
| Phase 2 | B8 snapshot → L4 자동, B6 → L2(c) 인프라 |
| **B3 진입 시** | **Record-replay 인프라** (Strategy §6 — 절차 참조; B3 ticket spec에서 인프라 ticket으로 분리) |
| Phase 3 | L3 SwiftSyntax 검사 (F4/F5/F8/F10) — B1 후 |
| 분기 1회 | L5 spec-code audit |

### 11.5 가장 위험한 결정 3건의 검증 의무

- **A4 DI factory**: production code의 `XCTestRuntime` 참조 0건 영구 (L3 F1/F2)
- **B1 ViewModel 4분할**: 모든 ViewModelTests + 모델별 단위 + UI snapshot + record-replay (각 분할 단계)
- **B3 Reciprocity Result enum**: record-replay baseline diff 0 (L2 결정적, **spec ticket의 전제 조건**)
