# B4 — Timer State Type Strengthening Spec

**Status**: Done
**Phase**: 3
**Spec precedence**: required before implementation
**Ticket**: PTIMER-118 (Implement Full Structure Improvement Plan)
**Related actions**: B1 (ViewModel 4분할, prerequisite — `TimerWorkspaceModel` 표면적 정리 후 진입), A9 (Coordinator separation, prerequisite)

---

## 1. 목적

현재 timer는 **단일 enum status** + **상태별 valid 필드 페어링** 형태로 표현된다 ([Timer Spec](../../Specs/Timer.md) §1.2 + §3.1). 이 표현은 *invalid combination* (예: status=running 인데 endDate=nil)을 *런타임에 검증*하거나 *호출 측 신뢰*에 의존한다. B4는 이 invariant를 **컴파일 차원에서 강제**하기 위한 옵션을 검토하고 선택해 적용한다.

---

## 2. 배경 (Why)

`Docs/StructureImprovement/Plan.md` §2.5 타입 시스템 진단:

- 현재 `TimerState`는 `status: enum`, `endDate: Date?`, `pausedRemainingTime: TimeInterval?`, `pausedAt: Date?`, `completedAt: Date?` 페어. 다음 invariant가 *런타임에만* 보장:
  - running → endDate ≠ nil, pausedRemainingTime = nil, pausedAt = nil
  - paused → endDate ≠ nil, pausedRemainingTime ≥ 0, pausedAt ≠ nil
  - completed → completedAt ≠ nil 또는 endDate로 derive
- 잘못된 조합을 만드는 코드가 *컴파일 통과*. 디코더와 setter들이 invariant를 지키도록 강제함.
- *Phantom-typed* 또는 *state-specific structs*를 쓰면 잘못된 transition이 *컴파일 에러*가 된다.

---

## 3. 옵션 카탈로그

본 spec은 4 옵션을 정리하고 선택을 결정 포인트로 둔다.

### Option A — 현 enum 유지 (no-op)

- 현재 표현 그대로.
- B4 = 0 작업, 부담 없음.
- 단점: invariant가 런타임에만. SOLID·Type 진단 미해소.

### Option B — Phantom typing (`Timer<Running>`, `Timer<Paused>`)

```
struct Timer<State> { ... }
struct Running {} ; struct Paused {} ; struct Completed {}

extension Timer where State == Running {
  func pause() -> Timer<Paused> { ... }
}
extension Timer where State == Paused {
  func resume() -> Timer<Running> { ... }
}
```

- transition을 *type-level*에서 표현. 잘못된 transition은 컴파일 에러.
- 단점: collection (`[Timer<?>]`)이 어려움. existential / type-erasure 필요.
- Swift에서 phantom-typed collection은 awkward.

### Option C — State-specific structs + sum type (★ 권고)

```
enum TimerState {
  case running(RunningTimer)
  case paused(PausedTimer)
  case completed(CompletedTimer)
}

struct RunningTimer { let endDate: Date; ... }
struct PausedTimer { let pausedRemainingTime: TimeInterval; let pausedAt: Date; ... }
struct CompletedTimer { let completedAt: Date; ... }
```

- 각 state가 *valid fields만* 가짐. nil-able 옵션 사라짐.
- transition은 메서드: `running.pause() -> .paused(...)`.
- collection은 자연: `[TimerState]`.
- 단점: 외부 API에 case 분기 강제 (단, 그게 정확한 표현).
- B3의 ReciprocityResult enum 패턴과 일관.

### Option D — Actor isolation

- `actor Timer { ... }` 로 동시성 격리.
- state machine은 actor 내부 invariant.
- 단점: actor 의존이 caller에 전파 (`await`). UI sync 코드 영향 큼.
- 진단된 부담(invariant 컴파일 차단)을 *직접* 해결 안 함.

---

## 4. 권고: Option C

이유:
- B3 ReciprocityResult와 일관된 패턴 (sum type + payload).
- collection 자연.
- transition을 메서드로 표현 → API 명확.
- backward-compat 디코더로 영속성 진화 가능 (B3와 같은 패턴).

본 spec은 **Option C 채택을 권고**. 결정 포인트 §6에서 사용자 / 구현자가 최종 확정.

---

## 5. 시맨틱 invariant (변경하지 말 것)

채택 옵션 무관하게 보존:

1. **`Docs/Specs/Timer.md` §1.2 transition graph 0건 변경** — running ⇄ paused, running → completed, paused → completed 불가 (재실행 후 가능), completed terminal.
2. **`Docs/Specs/Timer.md` §2 time semantics 0건 변경** — remaining time 계산, tick, resume 시 endDate 재계산.
3. **`Docs/Specs/Timer.md` §3 persistence 0건 변경 (시맨틱)** — restore 규칙, backward-compat status decoding ("stopped" / "paused"), reactivation reconciliation.
4. **`Docs/Specs/Timer.md` §6 ordering 0건 변경**.
5. **`Docs/Specs/Timer.md` §7 forbidden patterns 모두 보존**.
6. **모든 단위 테스트 동등 통과**.
7. **A4 / A9 / B1 invariant 보존**.

---

## 6. 결정 포인트 (구현 진입 전 확정 필요)

### 6.1 옵션 선택

A / B / C / D 중 채택. 권고 C.

### 6.2 transition 메서드 시그니처

옵션 C 채택 시:
- (a) `RunningTimer.pause() -> PausedTimer` — caller가 wrapping enum 재구성 책임
- (b) `TimerState.pause() -> TimerState` — caller는 sum type만 다룸
- (c) `TimerState.pause() throws -> TimerState` — pause 가능 case가 아니면 throw

권고: (b) — caller-friendly. invalid case의 pause 호출은 전체 op no-op (또는 warning log).

### 6.3 영속화 backward-compat

- 옛 영속 형식: `status: String + endDate: Date? + pausedRemainingTime: ... + ...`.
- 새 형식 옵션:
  - (a) 옛 형식 그대로 유지 (인코더가 status string으로 직렬화). 디코더는 sum case로 변환.
  - (b) 새 tagged 형식 출력. 디코더는 옛+새 둘 다 받음.

권고: (a). 영속 형식 비-진화. 코드 표현만 sum type.

### 6.4 transition 메서드의 Date 입력

resume 시 `.now` 의존 또는 caller가 Date 주입? 후자가 테스트 가능.

권고: caller가 Date 주입 (또는 `Clock` protocol).

---

## 7. 검증 의무

| 레이어 | 의무 |
|---|---|
| **L1** Per-action 자동 | 모든 TimerManagerTests 동등 통과 |
| **L2** Semantic equivalence | **★★ 결정적, 의무.** **Record-replay 필수**. main에서 모든 timer 라이프사이클 시퀀스 (시작·일시정지·재개·완료·다중 timer·재실행·force quit·reactivation) baseline 기록. branch에서 동일 입력 → 동일 외부 관찰 가능 결과 (display state, persistence snapshot, lock-screen 호출). diff 0. |
| **L3** Architectural fitness | **신규**: status 페어링 검증 코드 패턴 재도입 차단 (옛 페어링 검사 코드가 Sum type 도입 후 등장하면 lint fail). |
| **L4** UI 회귀 | 무관 — 외부 display state 동등. 단 dock·workspace snapshot test (B8) pass 권장. |
| **L5** Drift | `Docs/Specs/Timer.md` 본문 일부 갱신 가능 (상태 표현 형식 명시, 시맨틱 동등). |

---

## 8. 인수 기준 (DoD)

- [x] 채택 옵션의 표현이 코드에 적용. — Option C (sum type + payload structs) PR2 (`2f02ea3`)
- [x] 모든 TimerManagerTests + 타이머 관련 ViewModelTests 동등 통과.
- [x] L2 record-replay baseline diff 0. — PR1 (`5425852`) baseline 6 시나리오, PR2에서 byte-identical 재생 확인.
- [x] 영속화 형식 backward-compat 검증 테스트 추가. — `PersistentTimerSnapshot.SnapshotStatus` decoder가 `paused`/`stopped` 모두 수용; 기존 TimerManagerTests + record-replay reactivation/relaunch 시나리오로 커버.
- [x] L3 lint rule 추가 (페어링 검사 코드 재도입 차단). — F12 `no_legacy_timer_state_struct_init` (PR3).
- [x] Timer Spec 본문 *형식 표현*만 갱신. — `Docs/Specs/Timer.md` §1.1 + §3.1에 sum-type representation 메모 추가 (PR3).

---

## 9. 의존 / 후속

### 선행

| 액션 | 사유 |
|---|---|
| **A4** DI factory | 권장 |
| **A9** LockScreenTimerCoordinator | **필수**. lock-screen 분리 후 timer 표현 변경의 영향 범위가 정리됨. |
| **B1** ViewModel 분할 | **필수** (TimerWorkspaceModel 표면적). |
| **Record-replay 인프라** | **필수**. B3와 같은 인프라 재사용. |

### 후속

- 본 작업 후 timer 관련 코드의 nil-able 분기 제거. 코드 가독성↑.

---

## 10. 구현 PR 분할 권고

본 spec 머지 + 옵션 확정 + record-replay 인프라 머지 후:

| PR | 내용 | 상태 | Commit |
|---|---|---|---|
| 1 | main에서 timer 라이프사이클 baseline 기록 (record-replay 인프라) | **Done** | `5425852` |
| 2 | Sum type 도입 + transition 메서드 + backward-compat 디코더. encoder는 옛 형식 그대로(권고 §6.3-a). TimerManager·ViewModel·Coordinator 모두 sum case 분기. record-replay diff 0 통과. | **Done** | `2f02ea3` |
| 3 | Lint rule 추가 (F12), Timer Spec 본문 갱신 — sum type 표현 명시, 시맨틱 동등. | **Done** | (this PR) |

각 PR:
- branch `feature/PTIMER-118-b4-timer-types-step-N`
- L2 record-replay 결과 첨부

---

## 11. 위험 / 트레이드

| 위험 | 완화 |
|---|---|
| Sum type 도입이 caller 코드 (TimerManager, ViewModel)의 변경 범위가 매우 큼 | 한 PR에 묶지 않고 단계적 진행. 파일별 commit. |
| 옵션 C가 collection 처리에서 case별 분기를 매번 요구 | switch가 자연스러움. 헬퍼 함수로 흔한 분기 (예: remainingTime, isActive)를 sum type extension에. |
| Persistence 디코더가 옛 형식(특히 stopped → paused 매핑)에서 새 sum case로 매핑이 미묘함 | backward-compat 단위 테스트 케이스 매트릭스 (옛 형식 모든 status 변형 × 모든 nil-able 조합) 추가. |
| Transition 메서드가 invalid 호출 시 동작 (no-op vs throw) 결정이 caller 코드에 영향 | 결정 포인트 §6.2에서 확정. 권고는 no-op + caller 책임. |

---

## 12. 후속 갱신

본 spec은 *살아있는* 문서. 갱신 트리거:

- 옵션 결정 (§6.1) 변경 시 §3-§4 재작성.
- 구현 중 invariant 부정확 발견 → spec 갱신.
- B4 머지 후 본 spec은 archive 후보.
