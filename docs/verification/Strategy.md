# 검증 전략 (Verification Strategy)

**작성일**: 2026-04-27
**유형**: 검증 절차 가이드
**현재 위치**: `docs/verification/Strategy.md`
**관련 절차**: `docs/verification/{BackgroundNotificationDelivery,RelaunchRestore}.md`

---

## 1. 목적

PTIMER 구조 개선 작업이 다음을 만족하도록 보장:

- (a) 의도된 변경만 일어나고 시맨틱이 동등하게 보존
- (b) 보호 영역의 invariant가 유지
- (c) 한 번 정한 구조 결정이 시간 경과로 침식되지 않음
- (d) UI 동작이 회귀하지 않음
- (e) spec과 코드 사이의 drift가 조기 감지됨

단일 테스트 suite로는 위 5종을 다 잡지 못함. **5 레이어로 분담**.

---

## 2. 검증 5 레이어

### L1. Per-action 자동 검증

**목적**: PR 단위로 build/test/lint 회귀 차단

**무엇을**:
- Xcode build (`xcodebuild test`) 통과
- 모든 단위 테스트 통과 (`PTimer.xctestplan`)
- SwiftLint warning/error 0
- Coverage 비-회귀 (after coverage gating is introduced: 이전 대비 −1% 이내)

**도구**: local `xcodebuild` / `swiftlint`, and CI when configured

**언제**: 모든 PR

**부족한 점**: 테스트가 *기존에 발견되지 않은* 회귀를 잡지 못함 → L2 필요.

---

### L2. Semantic equivalence 검증

**목적**: 시그니처/표현이 변경된 작업이 시맨틱 동등을 유지하는지

**3중 안전망**:

#### (a) Spec-driven property test

spec의 각 invariant를 직접 property test로 변환. 예: Calculator Spec §3.2의 평가 순서 6단계를 `(metered, profile)` 조합 1만 케이스에 대해 변경 전/후 동일 결과 반환을 검증.

도구: 표준 XCTest. 외부 라이브러리 불필요. 필요 시
fixture-driven 테스트 또는 deterministic snapshot helper를 추가한다.

#### (b) Record-replay

변경 *전* 코드로 event sequence나 display state를 baseline text로
저장 → 변경 *후* 코드로 동일 시나리오 실행 → diff 0 확인.
절차는 §6에서 자세히.

대상: 정책 평가기 입출력, ViewModel 디스플레이 상태 합성, TimerManager 라이프사이클 결과.

#### (c) Golden fixture

spec의 대표 케이스를 `shared/test-fixtures/`의 JSON으로 영구 저장. 양 플랫폼(iOS·Android)이 공유.

(b)와의 차이: (c)는 spec-curated, 영구. (b)는 작업 시점의 현재 동작 snapshot.

**언제**: 시맨틱 변경 가능성이 있는 모든 구조 변경 PR.

---

### L3. Architectural fitness 검증

**목적**: 한 번 정한 구조 결정이 시간 경과로 침식되지 않는지 — 매 PR마다 *구조 invariant*를 자동 검증

**Fitness function 카탈로그**:

| # | 규칙 | 트리거 | 도구 |
|---|---|---|---|
| F1 | Production code shall not import `XCTestRuntime` | after the test-runtime coupling is removed | SwiftLint regex rule |
| F2 | Production code shall not reference `isRunningTests` | after the test-runtime coupling is removed | SwiftLint regex rule |
| F3 | `PTimer/Reciprocity/*` shall not import UIKit/SwiftUI | 도메인 순수성 | SwiftLint imports rule |
| F4 | `PTimer/Reciprocity/*` and `PTimer/ExposureCalculator/ExposureCalculator.swift` shall import only `Foundation` | 보호 영역 | SwiftSyntax 검사 |
| F5 | ViewModel/Models shall not directly instantiate concrete domain evaluators (use protocol) | after model-boundary enforcement is introduced | SwiftSyntax 검사 |
| F6 | Any source file shall not exceed 1,000 lines | after layer-size and decomposition enforcement is introduced | SwiftLint `file_length` |
| F7 | Any function shall not exceed 50 lines / CC 10 | after function/file-size enforcement is introduced | SwiftLint `function_body_length`/`cyclomatic_complexity` |
| F8 | View files shall not import policy/domain types directly | 레이어 단방향 | SwiftSyntax 검사 |
| F9 | `docs/specs/*` 인용한 코드 주석은 실재 § 참조해야 | 신규 권장 | 자체 검사 (grep + spec 파일 anchor 확인) |
| F10 | Persistence keys shall not be inlined; must use `*Storing` 페어 | after the persistence-key surface is enforced | SwiftSyntax 검사 |

**도구 선택지**:
- **SwiftLint custom regex rule**: 빠르고 가능한 것 (F1/F2/F3/F6/F7)
- **SwiftSyntax 기반 자체 검사**: 의존성 그래프, 타입 사용, 정밀 (F4/F5/F8/F10)
- **`periphery`**: unused code, dead config 검출 (보조)

**언제**: CI 게이트 — 모든 PR

**비용**: SwiftLint 규칙 추가는 5분/규칙. SwiftSyntax 검사는 처음 1주 + 보존 영구.

---

### L4. UI 회귀 검증

**목적**: View 변경이 화면 동작을 바꾸지 않는지

**2중 방어**:

#### (a) Snapshot 자동

현재 자동 snapshot은 in-house display-state snapshot이다. 위치:
`PTimerTests/Snapshots/`, baseline:
`PTimerTests/__Snapshots__/<TestClass>/<name>.txt`.

이 helper는 SwiftUI 픽셀 비교가 아니라 ViewModel/Presenter/Mapper가
emit하는 `Equatable` display state의 결정적 직렬화를 lock한다.
픽셀 수준 View 회귀는 아직 자동화하지 않고, View가 닿는 PR에서
매뉴얼 스모크나 스크린샷 리뷰로 보강한다.

#### (b) 매뉴얼 스모크 매트릭스

|             | 타이머 0개 | 타이머 1개 | 타이머 3개+ |
|-------------|-----------|-----------|-------------|
| Regular     | ✓         | ✓         | ✓           |
| Compact     | ✓         | ✓         | ✓           |
| Dense       | ✓         | ✓         | ✓           |

× 필름 모드 on/off (Tri-X 1s, Velvia 4s, PORTRA 2s 케이스 포함)
× 잠금화면 widget on/off (단일·다중 타이머)

**소요**: 분할 PR 마다 5분. PR 본문에 스크린샷 1장 첨부.

**언제**: View가 닿는 모든 PR

---

### L5. Spec-code drift 검증

**목적**: 시간 경과로 spec과 코드가 어긋나는지

**주기**: **분기별** 또는 마일스톤 종료 시점

**검증 항목**:
- coverage % 추세 (시계열) — 어느 레이어가 떨어지는지
- 파일 크기 top-10 추세 — 분할 결정이 보존되는지 (다시 부풀지 않는지)
- CC 분포 히스토그램 (시계열) — 함수 복잡도가 다시 늘어나는지
- **spec-code audit**: 각 spec §의 1줄 단언을 코드에서 직접 확인

#### Spec-code audit 체크리스트 (분기별)

| Spec | § | 단언 | 검증 방법 |
|---|---|---|---|
| Calculator | §2.2 | ND 범위 [0, 30] | 코드 상수 grep |
| Calculator | §2.3 | 19개 셔터 값 | 코드 배열 비교 |
| Calculator | §2.4 | 30s 경계 분기 | 분기 조건 grep |
| Calculator | §3.2 | 평가 순서 6단계 | evaluator switch case 비교 |
| Calculator | §3.3 | log-log vs stop-space 선택 | 분기 grep |
| Timer | §2.2 | 100ms tick | timer interval 상수 |
| Timer | §3.1 | 영속성 키 (deletable on empty) | UserDefaults 키 grep + 빈 컬렉션 핸들링 |
| Timer | §3.2 | "stopped"/"paused" 둘 다 디코드 | decoder 분기 |
| Timer | §5.1 | 가장 이른 endDate 선택 | LockScreenCoord 정렬 |
| UI | §1.1 | Portrait only | Info.plist 또는 entry 분기 |
| UI | §3.1 | 2-detent (medium 없음) | detent enum 카운트 |
| UI | §3.2 | 92pt up / 64pt down | drag threshold 상수 |
| UI | §3.5 | 3-layer progress | 코드 layer 카운트 |
| DomainSchema | §11 | 9개 검증 규칙 | catalog validator 코드 |

**도구**: 일부 grep, 일부 AST. **첫 audit은 매뉴얼**, 이후 자동화 가능 항목 점진 추가.

---

## 3. 도구 스택

### 이미 있는 것

| 도구 | 무엇 |
|---|---|
| Xcode test, `PTimer.xctestplan` | L1 |
| `PTimerTests/` XCTest suite | L1 (테스트 데이터) |
| `docs/verification/{BackgroundNotificationDelivery,RelaunchRestore}.md` | L4 매뉴얼 스모크 발판 |
| `Storing` 페어 | DI 발판, L3 fitness 일부 |
| `PTimerTests/Snapshots/` | L2/L4 display-state snapshot |
| `PTimerTests/RecordReplay/` | L2 event-sequence record-replay |

### 추가 필요

| 도구 | 무엇 | 도입 시점 | 비용 |
|---|---|---|---|
| GitHub Actions / Bitbucket Pipelines | CI workflow | after CI is configured | S |
| SwiftLint config | L1 + L3 (F1/F2/F3/F6/F7) | after CI is configured + after function/file-size enforcement is introduced | S |
| SwiftSyntax 검사 (자체) | L3 정밀 fitness (F4/F5/F8/F10) | after model-boundary enforcement is introduced | M (1주) |
| SwiftUI/image snapshot 자동화 | L4 픽셀 회귀 | 후속 필요 시 | M |
| `xcrun llvm-cov` 보고 자동화 | L1/L5 | after coverage gating is introduced | S |
| Mutation testing (`muter`) | 메타 — 검증의 검증 | 1년 후 검토 | L (선택) |

---

## 4. 변경 유형별 검증 매핑

★★ = 결정적 (의무) · ★ = 적용 · – = 무관

| 변경 유형 | L1 | L2 | L3 | L4 | L5 | 비고 |
|---|---|---|---|---|---|---|
| ViewModel/레이어 분할 | ★★ | ★★ | ★ | ★★ | – | **다층, 가장 위험** |
| Result enum / Timer state type 변경 | ★ | ★★ | ★(컴파일) | – | – | record-replay **필수** (§6) |
| DI factory 및 테스트 런타임 결합 제거 | ★ | ★★ | ★(F1/F2 영구) | – | – | 테스트 런타임 참조 잠금 |
| 파일/함수 복잡도 상한 도입 | ★ | – | ★★ | – | ★(시계열) | L3·L5 인프라 |
| Golden fixture 인프라 | – | ★★ (인프라) | – | – | ★ | L2의 인프라 자체 |
| Display-state snapshot 인프라 | – | – | – | ★★ (인프라) | – | L4의 인프라 자체 |
| CI/리포팅 인프라 | ★★ | – | ★ | – | ★★ (인프라) | L1/L5 데이터 소스 |
| Presenter/Coordinator/UI 구성 변경 | ★ | ★★ | – | ★ | – | 매뉴얼 스모크 + snapshot 권장 |
| 데이터/정책 보정 및 에러 모델 가이드 | ★ | ★★ | ★ | – | – | fixture 케이스 + 가이드 검증 |
| 문서 전용 변경 / 스파이크 | – | – | – | – | – | 보고서 또는 문서 검토 |

---

## 5. PR Verification artifact

각 PR은 본문에 다음을 첨부:

```markdown
## Verification

- [x] L1 — CI build/test/lint pass: <link>
- [x] L2 — Semantic equivalence: <method: spec-property / record-replay / fixture>
       evidence: <link>
- [x] L3 — Fitness: 새 위반 0건 <link to lint report>
- [x] L4 — UI: snapshot diff 0 / <screenshot>
- [x] L5 — Drift: 영향 없음 / spec § <link>
```

각 액션의 결정적 레이어(★★)는 **반드시 체크**. 결정적 레이어가 *적용 안 됨*이면 사유 명시.

---

## 6. Record-replay 절차 (Reciprocity Result enum 예시)

Reciprocity Result enum 도입 시:

### Step 1. main에서 baseline 기록

현재 record-replay 인프라 위치:
`PTimerTests/RecordReplay/`, baseline 위치:
`PTimerTests/__RecordReplay__/<TestClass>/<name>.txt`.

```bash
RECORD_REPLAY=1 xcodebuild test \
  -project PTimer.xcodeproj -scheme PTimer \
  -testPlan PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PTimerTests/<RecordReplayTestClass>
```

첫 실행 또는 재기록 실행은 baseline을 쓰고 의도적으로 fail한다.
baseline은 deterministic text trace이며 PR diff로 검토한다.

baseline은 git에 커밋 (재현성·리뷰 가능성).

### Step 2. branch에서 대상 변경 구현

- 보호 영역과 scope를 확인한 뒤 대상 변경을 구현한다.
- trace 대상 협력자 호출 순서와 payload가 의도치 않게 바뀌지
  않아야 한다.
- 의도된 변경이라면 baseline diff를 리뷰 가능한 증거로 남긴다.

### Step 3. branch에서 baseline 재생

```bash
xcodebuild test \
  -project PTimer.xcodeproj -scheme PTimer \
  -testPlan PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PTimerTests/<RecordReplayTestClass>
```

각 시나리오 실행 결과가 committed baseline text trace와 diff 0이어야
통과한다.

### Step 4. PR

PR 본문 §5 양식에:
- `L2 — Semantic equivalence: record-replay`
- `evidence: PTimerTests/__RecordReplay__/<TestClass>/<name>.txt`
  + diff 결과 캡처

### Record-replay 인프라 비용

- 인프라는 XCTest + on-disk text baseline 방식으로 도입 완료.
- 신규 시나리오는 `RecordReplayHarness`와 spy를 추가하고 baseline을
  commit한다.

Record-replay 인프라는 timer types, presenter, coordinator, ViewModel 분할 등 후속 구조 변경에서도 동일하게 활용한다.

### 구현 노트

실제 인프라는 XCTest + display-state snapshot 패턴을 재사용한다. CLI 플래그
대신 환경변수로 재기록 모드를 토글한다.

- 위치: `PTimerTests/RecordReplay/` (Trace/Baseline/Spies/Harness + smoke test)
- baseline: `PTimerTests/__RecordReplay__/<TestClass>/<name>.txt`
- 재기록: `RECORD_REPLAY=1 xcodebuild test ... -only-testing:PTimerTests/<TestClass>` → fail (의도 commit 강제) → env 없이 재실행으로 verify
- fixture(`shared/test-fixtures/reciprocity-golden.json`)는 Reciprocity Result enum 입출력 페어를 이미 커버하므로 record-replay는 추가 baseline 없이도 시작 가능하다. record-replay는 **이벤트 시퀀스**(LockScreen exposer 호출 순서, persistence save/clear, notification schedule/cancel)를 lock하는 데 집중한다.
- 자세한 사용법은 `PTimerTests/RecordReplay/README.md`.

본 인프라는 텍스트 trace + on-disk diff로 semantic equivalence
evidence를 남기며, display-state snapshot과 라이프사이클을 통일해 학습 비용을
최소화했다.

---

## 7. 메타 — 검증의 검증

장기적으로 검증 인프라가 *효과적인지* 평가:

- **Mutation testing** (1년 후 검토): `muter`로 코드 일부러 손상 → 테스트가 잡는지. 검증 인프라의 효과 측정. mutation score < 80%인 모듈 식별.
- **Coverage gap analysis** (반기): 미커버 라인의 *종류* 분석. 단순 % 외에 어떤 레이어가 빈약한지.
- **Spec citation audit** (반기): 코드/PR description의 spec citation이 실재 spec § 존재하는지 lint. 죽은 링크 자동 차단.
- **Verification artifact compliance** (반기): 머지된 PR 중 §5 양식을 따른 비율. 누락된 PR을 식별.

---

## 8. 단계 도입 (검증 인프라 자체 로드맵)

```
Phase 0  L1(local/CI), L4 매뉴얼 스모크
Phase 1  Coverage gating → L1 강화; complexity caps → L3 부분 + L5 시계열; F1/F2는 test-runtime coupling 제거 후 영구
Phase 2  Display-state snapshot helper → L4 자동; cross-platform fixture gate → L2(c) 인프라
Record-replay 인프라 도입 (§6 참조)
Phase 3  L3 SwiftSyntax 검사 (F4/F5/F8/F10) — after model-boundary enforcement is introduced
분기 1회 L5 audit (§2.5 체크리스트)
1년 후   Mutation testing 검토
```

---

## 9. 핵심 invariants — 가장 위험한 결정 3건

| 결정 | 검증 의무 | 레이어 |
|---|---|---|
| DI factory + test-runtime coupling 제거 | production code의 `XCTestRuntime` 참조 0건 영구 보존 | L3 (F1/F2) |
| ViewModel 분할 | 모든 ViewModelTests + 모델별 단위 테스트 + UI snapshot + record-replay (각 분할 단계) | L1 + L2 + L3 + L4 |
| Reciprocity Result enum | record-replay baseline diff 0 | L2 결정적 — spec ticket의 *전제 조건*으로 명문화 |

---

## 10. 비-목표

- **TDD 강제** — 본 전략은 *기존 테스트 + 추가 안전망*. 신규 ticket이 TDD를 강제하지 않음
- **100% 커버리지** — 의미 없는 % 추구는 비-목표. *의미 있는 레이어별* coverage 목표
- **자동 spec-code audit (전체)** — 매뉴얼이 1차, 자동화는 항목 단위 점진
- **모든 PR record-replay** — L2★★ 액션만 의무. 비-시맨틱 변경은 L1으로 충분
- **검증 자동화의 자동화** — 메타(§7) 검토는 *사람이 결정*, 도구가 결정 안 함

---

## 11. 참고

- 스펙 출처: `docs/specs/{Calculator,Timer,UI,DomainSchema}.md`
- 요구사항 출처: `docs/requirements/Requirements.md`
- 매뉴얼 절차서: `docs/verification/{BackgroundNotificationDelivery,RelaunchRestore}.md`
- 보호 영역: 각 spec §6 (Forbidden patterns)
