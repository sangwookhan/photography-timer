# Hot Function Inventory (B2)

**측정일**: 2026-04-30 (HEAD = `388096f`, post-PTIMER-118 cleanup)
**방법**: `wc -l` 기반 파일 LOC + SwiftUI body 휴리스틱. 도구는 SwiftLint 미설치 환경에서 사용한 휴리스틱.
**용도**: B1 facade trim (잔여 PR), Screen 추출 (잔여 PR), SOLID 분할 우선순위.

---

## 1. 상위 파일 (LOC 기준)

| Rank | 파일 | LOC | 주 책임 | 비고 |
|---|---|---|---|---|
| 1 | `PTimer/ExposureCalculator/ExposureCalculatorScreen.swift` | 2,911 | SwiftUI Views + Layout | A10 부분 추출 후 잔존. `FilmModeDetails*` (~1,090L) + `WheelPickerContinuousObserver` (~225L) 미추출 |
| 2 | `PTimer/Reciprocity/ReciprocityCalculationPolicy.swift` | 1,979 | 6-step policy evaluator + ReciprocityResult enum + 양방향 Codable | B3 enum 도입(+294L)으로 증가. 의도적 응집. 분할 비-목표 (Plan §2.1) |
| 3 | `PTimer/ExposureCalculator/FilmModeDetailsPresenter.swift` | 1,262 | Reciprocity details presenter | A8 결과. ReciprocityModel(B1)으로 facade 위임 — 본체는 잔존 |
| 4 | `PTimer/ExposureCalculator/ExposureCalculatorViewModel.swift` | 1,103 | View-model facade (B1 carry-forward) | B1 PR1-6 후 facade 잔존. ~700L 가 model로 이동 가능 (B1 facade-trim 잔여 PR) |
| 5 | `PTimer/App/Workspace/BottomSheetWorkspaceShell.swift` | 1,022 | Workspace shell + dock | A1 후. `CompactTimerMiniCardView` (~280L) + `BottomSheetLargeWorkspaceView` (~360L) 추출 여지 |
| 6 | `PTimer/Timers/TimerManager.swift` | 842 | Timer 라이프사이클 + 영속화 + sum-type | B4 sum-type(+186L) 으로 증가. restore 분기 복잡 |
| 7 | `PTimer/Reciprocity/ReciprocityConfidencePresentation.swift` | 691 | Basis × authority → presentation | 응집됨 |

---

## 2. 상위 함수 (body 라인 기준)

목록은 비-SwiftUI 함수와 SwiftUI `var body` 분리.

### 2.1 비-SwiftUI 함수 / 메서드

| Rank | File:Line | 함수 | ~Body L | 복잡도 노트 |
|---|---|---|---|---|
| 1 | `ReciprocityCalculationPolicy.swift` | `evaluate(...)` | ~92 | 6-step evaluation order. 의도적 응집. 분할 시 spec 위반 위험 |
| 2 | `ReciprocityCalculationPolicy.swift` | `evaluateEstimatedTableResult(...)` | ~72 | log-log interpolation + boundary handling |
| 3 | `FilmModeDetailsPresenter.swift` | `formulaGraphSourcePoints(...)` | ~66 | sample 도메인 결정 + 포인트 생성 |
| 4 | `FilmModeDetailsPresenter.swift` | `formulaDetailsGraphDisplayState(...)` | ~66 | formula graph state 조립 |
| 5 | `FilmModeDetailsPresenter.swift` | `tableDetailsGraphDisplayState(...)` | ~51 | table graph state 조립 |
| 6 | `FilmModeDetailsPresenter.swift` | `makeFilmModeDetailsCurrentResultState()` | ~50 | layout 분기 + value 텍스트 매핑 |
| 7 | `ExposureCalculatorViewModel.swift:919` | `correctedExposureDisplayState(...)` | ~50 | reciprocity result → display state |
| 8 | `ReciprocityCalculationPolicy.swift` | `warningLevel(...)` | ~47 | 4 case × 위치 변형 |
| 9 | `ExposureCalculatorScreen.swift:584` | `pickerColumnLayout(...)` | 45 | picker column 측정 |
| 10 | `ReciprocityCalculationPolicy.swift` | `evaluateExactTableMatch(...)` | ~42 | exact match + 메타데이터 조립 |

### 2.2 SwiftUI `var body` (Screen + Shell)

| Rank | File:Line | ~Body L | 추정 view | 비고 |
|---|---|---|---|---|
| 1 | `ExposureCalculatorScreen.swift:3143` | 151 | (root view 또는 큰 섹션) | A10 후 잔여. 추출 후보 |
| 2 | `BottomSheetWorkspaceShell.swift:1826` | 123 | dock or workspace view | snapshot test (B8) lock 후 분할 안전 |
| 3 | `ExposureCalculatorScreen.swift:140` | 100 | 상단 섹션 | |
| 4 | `ExposureCalculatorScreen.swift:3643` | 96 | (대형 섹션) | |
| 5 | `ExposureCalculatorScreen.swift:1233` | 69 | film mode result card | |
| 6 | `ExposureCalculatorScreen.swift:3041` | 64 | | |
| 7 | `ExposureCalculatorScreen.swift:1092` | 62 | | |

---

## 3. 권고 분할 우선순위

본 hot-list가 정확한 측정은 아니지만 다음을 제안:

| 우선순위 | 대상 | 이유 |
|---|---|---|
| **High** | `ExposureCalculatorScreen.swift` 의 root view (151L) | 단일 view 가독성 회복. snapshot test (B8) 도입 후 안전 분할 |
| **High** | `ExposureCalculatorViewModel.correctedExposureDisplayState` | B1의 ReciprocityModel로 흡수 후 자연 단순화 |
| **Med** | `BottomSheetWorkspaceShell` 의 큰 body (123L) | snapshot test 후 dock / workspace 별 view 분할 |
| **Med** | `FilmModeDetailsPresenter` 의 graph 메서드들 (66L × 2) | B1의 ReciprocityModel과 통합 시 응집도 재평가 |
| **Low** | `ReciprocityCalculationPolicy.evaluate` (92L) | spec 응집. 분할 시 6-step 평가 순서 위반 위험. **분할 비-목표** |

---

## 4. SwiftLint 임계값 적용 결과 (예상)

`.swiftlint.yml` v2 (이번 commit) 기준:

| 규칙 | warning | error | 예상 violation 수 |
|---|---|---|---|
| `function_body_length` | 80L | 200L | warning ~3건, error 0건 |
| `file_length` | 1,500L | 3,500L | warning 4건 (Screen, Reciprocity, Presenter, ViewModel), error 0건 |
| `type_body_length` | 500L | 2,000L | warning 2–3건, error 0건 |
| `cyclomatic_complexity` | 15 | 25 | warning ~5건 (Reciprocity evaluators), error 0건 |
| `nesting` | type=2, func=3 | — | TBD |

**머지 차단 0건** — error 임계값은 의도적 보수. warning 정리는 B1/추가 view 추출 진행에 따라 자연 감소.

---

## 5. 후속 갱신

- 잔여 PR(Screen 추출, B1 facade trim, BottomSheetShell 추가 분할) 각각이 본 표 갱신.
- swiftlint를 실제 실행해 위 측정과 SwiftLint 자체 측정을 일치 검증 (현재는 휴리스틱만).
- 각 마일스톤 종료 시점에 측정일 + HEAD commit hash 갱신.
