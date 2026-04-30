# 검증 전략 (Verification Strategy)

**작성일**: 2026-04-27
**유형**: 검증 절차 가이드
**상위 문서**: `docs/StructureImprovement/Plan.md` §11
**기존 패턴**: `docs/Verification/PTIMER-XX-Verification.md` 매뉴얼 절차서 옆의 **전략** 문서

---

## 1. 목적

PTIMER 구조 개선 24개 액션이 다음을 만족하도록 보장:

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
- Coverage 비-회귀 (B13 후 마지노선: 이전 대비 −1% 이내)

**도구**: A5의 CI workflow

**언제**: 모든 PR

**부족한 점**: 테스트가 *기존에 발견되지 않은* 회귀를 잡지 못함 → L2 필요.

---

### L2. Semantic equivalence 검증

**목적**: 시그니처/표현이 변경된 작업(B3/B4/A4/A8/A9/B1)이 시맨틱 동등을 유지하는지

**3중 안전망**:

#### (a) Spec-driven property test

spec의 각 invariant를 직접 property test로 변환. 예: Calculator Spec §3.2의 평가 순서 6단계를 `(metered, profile)` 조합 1만 케이스에 대해 변경 전/후 동일 결과 반환을 검증.

도구: 표준 XCTest. 외부 라이브러리 불필요 (선택지: `pointfreeco/swift-snapshot-testing`의 inline assertion 또는 `typelift/SwiftCheck` property test).

#### (b) Record-replay

변경 *전* 코드로 입출력 N개 케이스를 baseline JSON에 저장 → 변경 *후* 코드로 동일 입력 실행 → diff 0 확인. 절차는 §6에서 자세히.

대상: 정책 평가기 입출력, ViewModel 디스플레이 상태 합성, TimerManager 라이프사이클 결과.

#### (c) Golden fixture (B6)

spec의 대표 케이스를 `shared/test-fixtures/`의 JSON으로 영구 저장. 양 플랫폼(iOS·Android)이 공유. PTIMER-17 reciprocity validation samples이 부분적 시작점.

(b)와의 차이: (c)는 spec-curated, 영구. (b)는 작업 시점의 현재 동작 snapshot.

**언제**: B1/B3/B4/A4/A8/A9 PR (시맨틱 변경 가능성 있는 모든 작업).

---

### L3. Architectural fitness 검증

**목적**: 한 번 정한 구조 결정이 시간 경과로 침식되지 않는지 — 매 PR마다 *구조 invariant*를 자동 검증

**Fitness function 카탈로그**:

| # | 규칙 | 트리거 | 도구 |
|---|---|---|---|
| F1 | Production code shall not import `XCTestRuntime` | A4 후 영구 | SwiftLint regex rule |
| F2 | Production code shall not reference `isRunningTests` | A4 후 영구 | SwiftLint regex rule |
| F3 | `PTimer/Reciprocity/*` shall not import UIKit/SwiftUI | 도메인 순수성 | SwiftLint imports rule |
| F4 | `PTimer/Reciprocity/*` and `PTimer/ExposureCalculator/ExposureCalculator.swift` shall import only `Foundation` | 보호 영역 | SwiftSyntax 검사 |
| F5 | ViewModel/Models shall not directly instantiate concrete domain evaluators (use protocol) | B1 후 | SwiftSyntax 검사 |
| F6 | Any source file shall not exceed 1,000 lines | A1/A2/B1 후 영구 | SwiftLint `file_length` |
| F7 | Any function shall not exceed 50 lines / CC 10 | B2 후 영구 | SwiftLint `function_body_length`/`cyclomatic_complexity` |
| F8 | View files shall not import policy/domain types directly | 레이어 단방향 | SwiftSyntax 검사 |
| F9 | `docs/en/specs/*` 인용한 코드 주석은 실재 § 참조해야 | 신규 권장 | 자체 검사 (grep + spec 파일 anchor 확인) |
| F10 | Persistence keys shall not be inlined; must use `*Storing` 페어 | A4/B10 후 | SwiftSyntax 검사 |

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

#### (a) Snapshot 자동 (B8)

`pointfreeco/swift-snapshot-testing` 도입 — `ExposureCalculatorScreen`, `BottomSheetWorkspaceShell`, 필름 모드 결과 카드. PR마다 자동 비교.

#### (b) 매뉴얼 스모크 매트릭스

|             | 타이머 0개 | 타이머 1개 | 타이머 3개+ |
|-------------|-----------|-----------|-------------|
| Regular     | ✓         | ✓         | ✓           |
| Compact     | ✓         | ✓         | ✓           |
| Dense       | ✓         | ✓         | ✓           |

× 필름 모드 on/off (Tri-X 1s, Velvia 4s, PORTRA 2s 케이스 포함)
× 잠금화면 widget on/off (단일·다중 타이머)

**소요**: 분할 PR (A1/A2/A10/B1) 마다 5분. PR 본문에 스크린샷 1장 첨부.

**언제**: View가 닿는 모든 PR

---

### L5. Spec-code drift 검증

**목적**: 시간 경과로 spec과 코드가 어긋나는지

**주기**: **분기별** 또는 마일스톤 종료 시점

**검증 항목**:
- coverage % 추세 (B13 시계열) — 어느 레이어가 떨어지는지
- 파일 크기 top-10 추세 — 분할 결정이 보존되는지 (다시 부풀지 않는지)
- CC 분포 히스토그램 (B2 시계열) — 함수 복잡도가 다시 늘어나는지
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
| 단위 테스트 9,724L | L1 (테스트 데이터) |
| `docs/Verification/PTIMER-XX-Verification.md` 매뉴얼 절차서 패턴 | L4 매뉴얼 스모크 발판 |
| `Storing` 페어 | DI 발판, L3 fitness 일부 |

### 추가 필요

| 도구 | 무엇 | 어느 액션 | 비용 |
|---|---|---|---|
| GitHub Actions / Bitbucket Pipelines | CI workflow | A5 | S |
| SwiftLint config | L1 + L3 (F1/F2/F3/F6/F7) | A5 + B2 | S |
| SwiftSyntax 검사 (자체) | L3 정밀 fitness (F4/F5/F8/F10) | B1 후속 | M (1주) |
| `pointfreeco/swift-snapshot-testing` | L4 자동 | B8 | S |
| Record-replay 인프라 | L2 (a/b) | B3 spike | M (1주) |
| `xcrun llvm-cov` 보고 자동화 | L1/L5 | B13 | S |
| Mutation testing (`muter`) | 메타 — 검증의 검증 | 1년 후 검토 | L (선택) |

---

## 4. 액션별 검증 매핑

★★ = 결정적 (의무) · ★ = 적용 · – = 무관

| 액션 | L1 | L2 | L3 | L4 | L5 | 비고 |
|---|---|---|---|---|---|---|
| A1/A2/A11 | ★★ | – | – | ★(A1) | – | 단순 split. 기존 테스트 + UI 스모크 |
| A3 | ★★ | – | – | – | – | 신규 통합 테스트가 자체 검증 |
| A4 (DI factory) | ★ | ★★ | ★(F1/F2 영구) | – | – | XCTestRuntime 잠금 fitness 즉시 |
| A5 | ★★ | – | ★(F6/F7 인프라) | – | – | 인프라 |
| A6/A7 | – | – | – | – | – | doc only |
| A8 (Presenter) | ★ | ★★ | – | ★ | – | record-replay 권장 |
| A9 (Coordinator) | ★ | ★★ | – | – | – | 잠금화면 매뉴얼 추가 |
| A10 (Screen 추출) | ★ | – | – | ★★ | – | snapshot 결정적 |
| A12 (Tri-X 데이터) | ★ | ★★ | – | – | – | golden fixture 신규 케이스 + 사용자 메뉴얼 |
| **B1 (VM 4분할)** | ★ | ★★ | ★ | ★★ | – | **다층, 가장 위험** |
| B2 (CC 한도) | ★ | – | ★★ | – | ★(시계열) | L3·L5 인프라 |
| **B3 (Result enum)** | ★ | ★★ | – | – | – | record-replay **필수** (§6) |
| **B4 (Timer types)** | ★ | ★★ | ★(컴파일) | – | – | 옵션에 따라 컴파일 차단 우선 |
| B5 (명명) | ★★ | – | – | – | – | |
| B6 (fixture) | – | ★★ (인프라) | – | – | ★ | L2의 인프라 자체 |
| B7 (KMP spike) | – | – | – | – | – | 보고서 |
| B8 (snapshot) | – | – | – | ★★ (인프라) | – | L4의 인프라 자체 |
| B9 (concurrency) | ★ | – | – | – | ★ | frame budget 보고서 |
| B10 (error 모델) | ★ | – | ★ | – | – | 가이드 + lint |
| B11/B12 | – | – | – | – | – | 옵션 |
| B13 (coverage) | – | – | – | – | ★★ (인프라) | L1/L5 데이터 소스 |

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

## 6. Record-replay 절차 (B3 예시)

B3 (Reciprocity Result enum) 적용 시:

### Step 1. main에서 baseline 기록

새 fixture 디렉토리: `PTimerTests/Fixtures/RecordReplay/<feature>/`

```bash
git checkout main
swift test --filter ReciprocityCalculationPolicyTests \
  -- --record-baseline \
  > PTimerTests/Fixtures/RecordReplay/B3-reciprocity-result/baseline-2026-04-27.json
```

각 테스트 케이스의 입력 + 결과를 JSON으로 저장:
- 입력: `(metered exposure, profile JSON 직렬화)`
- 결과: `(corrected, basis, rangeStatus, warningLevel, supportingNotes, usedReferencePoints, didReturnCalculatedTime)`

baseline은 git에 커밋 (재현성·리뷰 가능성).

### Step 2. branch에서 enum으로 변경

- 도메인: `ReciprocityResult`를 `enum { quantified(T) / advisoryOnly / unsupported }`로
- JSON 디코더: backward-compat — 기존 `didReturnCalculatedTime + correctedExposure?` 페이로드를 enum 케이스로 변환
- 정책 평가기: 새 enum 반환
- 직렬화 어댑터: 새 enum → 옛 페이로드 형식으로 직렬화하는 헬퍼 (replay 비교용)

### Step 3. branch에서 baseline 재생

```bash
swift test --filter ReciprocityCalculationPolicyTests \
  -- --replay-baseline PTimerTests/Fixtures/RecordReplay/B3-reciprocity-result/baseline-2026-04-27.json
```

각 baseline 입력 → 새 코드 실행 → enum 결과를 옛 표현으로 직렬화 → baseline JSON과 diff 0이어야 통과.

### Step 4. PR

PR 본문 §5 양식에:
- `L2 — Semantic equivalence: record-replay`
- `evidence: PTimerTests/Fixtures/RecordReplay/B3-reciprocity-result/baseline-2026-04-27.json` + diff 결과 캡처

### Record-replay 인프라 비용

- 인프라 1주 (XCTest extension + JSON decode/encode 헬퍼). 재사용 가능
- 본 ticket(B3)에서 1일

다음 record-replay 활용 액션: B4 (Timer types), A8 (Presenter), A9 (Coordinator), B1 (VM 분할 — 단계마다).

### 구현 노트 (2026-04 도입)

위 §6의 절차는 CLI flavor(`swift test --filter ... -- --record-baseline`)로 작성되었지만, 실제 인프라는 XCTest + B8 snapshot 패턴을 재사용한다. CLI 플래그 대신 환경변수로 재기록 모드를 토글한다.

- 위치: `PTimerTests/RecordReplay/` (Trace/Baseline/Spies/Harness + smoke test)
- baseline: `PTimerTests/__RecordReplay__/<TestClass>/<name>.txt`
- 재기록: `RECORD_REPLAY=1 xcodebuild test ... -only-testing:PTimerTests/<TestClass>` → fail (의도 commit 강제) → env 없이 재실행으로 verify
- B6 fixture(`shared/test-fixtures/reciprocity-golden.json`)는 B3 입출력 페어를 이미 커버하므로 B3는 record-replay에 추가 baseline 없이도 진입 가능. record-replay는 **이벤트 시퀀스**(LockScreen exposer 호출 순서, persistence save/clear, notification schedule/cancel)를 lock하는 데 집중.
- 자세한 사용법은 `PTimerTests/RecordReplay/README.md`.

원래 §6의 JSON-flavor 절차는 *개념*적으로 유효하다 (입력/출력 페어 직렬화 후 diff). 본 인프라는 동일 결과를 텍스트 trace + on-disk diff로 달성하며, B8과 라이프사이클을 통일해 학습 비용을 최소화했다.

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
Phase 0  L1(CI · A5), L4 매뉴얼 스모크
Phase 1  B13(coverage) → L1 강화, B2(CC) → L3 부분 + L5 시계열, A4 후 L3 F1/F2 영구
Phase 2  B8(snapshot) → L4 자동, B6 → L2(c) 인프라
B3 진입  Record-replay 인프라 도입 (§6)
Phase 3  L3 SwiftSyntax 검사 (F4/F5/F8/F10) — B1 후
분기 1회 L5 audit (§2.5 체크리스트)
1년 후   Mutation testing 검토
```

---

## 9. 핵심 invariants — 가장 위험한 결정 3건

| 결정 | 검증 의무 | 레이어 |
|---|---|---|
| A4 DI factory | production code의 `XCTestRuntime` 참조 0건 영구 보존 | L3 (F1/F2) |
| B1 ViewModel 4분할 | 모든 ViewModelTests + 모델별 단위 테스트 + UI snapshot + record-replay (각 분할 단계) | L1 + L2 + L3 + L4 |
| B3 Reciprocity Result enum | record-replay baseline diff 0 | L2 결정적 — spec ticket의 *전제 조건*으로 명문화 |

---

## 10. 비-목표

- **TDD 강제** — 본 전략은 *기존 테스트 + 추가 안전망*. 신규 ticket이 TDD를 강제하지 않음
- **100% 커버리지** — 의미 없는 % 추구는 비-목표. *의미 있는 레이어별* coverage 목표
- **자동 spec-code audit (전체)** — 매뉴얼이 1차, 자동화는 항목 단위 점진
- **모든 PR record-replay** — L2★★ 액션만 의무. 비-시맨틱 변경은 L1으로 충분
- **검증 자동화의 자동화** — 메타(§7) 검토는 *사람이 결정*, 도구가 결정 안 함

---

## 11. 참고

- 액션 카탈로그: `docs/StructureImprovement/Plan.md` §3
- 스펙 출처: `docs/en/specs/{Calculator,Timer,UI,DomainSchema}.md`
- 매뉴얼 절차서 패턴: `docs/Verification/PTIMER-{11,68,70}-Verification.md`
- 보호 영역: 각 spec §6 (Forbidden patterns)
