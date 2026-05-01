# A9 — LockScreenTimerCoordinator Separation Spec

**Status**: Done
**Phase**: 3
**Spec precedence**: required before implementation
**Ticket**: PTIMER-118 (Implement Full Structure Improvement Plan)
**Related actions**: A4 (DI factory, prerequisite), A8 (Presenter, prior step), B1 (ViewModel 분할, successor — A9 is the second incremental step toward B1's `TimerWorkspaceModel`)

> **Implementation note (2026-04-29)**: `LockScreenTimerCoordinator`
> (renamed from `LockScreenTimerTargetCoordinator`) and its supporting
> `EligibleRunningTimer` struct live in
> `PTimer/Timers/LockScreenTimerCoordinator.swift`. The coordinator now
> subscribes to the ViewModel's timer publisher via Combine and drives
> the lock-screen surface autonomously — `syncTimers` no longer calls
> the coordinator directly. The ViewModel still retains the coordinator
> instance so the Combine subscription stays alive; full lifetime
> ownership migration to a DI seam (app entry / factory) is the
> remaining incremental step and is folded into B1's
> `TimerWorkspaceModel` work where the natural seam exists. A SwiftLint
> rule (`no_activitykit_in_viewmodel`) now blocks regressions where the
> ViewModel pulls in ActivityKit directly.

---

## 1. 목적

현재 `ExposureCalculatorViewModel`이 보유한 **lock-screen Live Activity coordinator** ownership을 ViewModel 외부로 분리한다. ViewModel 모놀리스 슬림화의 두 번째 점진적 단계이자 B1의 `TimerWorkspaceModel`이 lock-screen 책임을 갖지 않게 하기 위한 표면적 정리.

---

## 2. 배경 (Why)

`Docs/Specs/Timer.md` §5에 lock-screen 위젯 행동 계약이 정의됨:
- 가장 이른 endDate를 가진 running timer를 representative로 선택
- 앱 active 시 기존 Live Activity instance 재사용 (새 instance 생성 금지)
- 1 s cadence refresh, no active timer 시 placeholder 표시

이 행동을 위해 현재 ViewModel은 `LockScreenTimerTargetCoordinator` (또는 동등한 이름의 협력자)를 직접 보유하고, timer 변화 이벤트마다 coordinator를 호출한다. 결과:

- **ViewModel이 lock-screen을 안다** — Timer Spec §5의 책임이 ViewModel 책임에 누적됨.
- **B1 진입 시 `TimerWorkspaceModel`이 lock-screen까지 갖게 되는 위험** — 모델 책임 비대.
- **ActivityKit 의존이 ViewModel을 통해 새어 나옴** — 도메인 순수성 약화.

A9는 lock-screen ownership을 ViewModel 밖의 *독립 coordinator*에 옮긴다.

---

## 3. 분리 대상 / 보존 대상

### 분리 (이동)

- `LockScreenTimerTargetCoordinator` (또는 동등 협력자)의 ownership
- Representative timer 선택 로직
- Live Activity instance 생성·갱신·종료 호출
- 앱 active 시 기존 instance resolve 로직

### 보존 (그대로 ViewModel/모델에 남음)

- Timer collection 자체 (timer 시작·일시정지·재개·완료 액션)
- Timer 상태 변화의 *알림 이벤트 발행* (subscriber pattern)
- Workspace UI 상태

---

## 4. 시맨틱 invariant (변경하지 말 것)

1. **`Docs/Specs/Timer.md` §5 행동 계약 0건 변경.** Representative 선택, continuity, refresh cadence, no-active fallback 모두 동등.
2. **`Docs/Specs/Timer.md` §7 forbidden patterns 모두 보존** — 특히 "lock-screen Live Activity for stale state after all timers stopped" 금지.
3. **PTIMER-69 commit 결정 보존** — earliest end date 선택, deterministic tie-breaking, app active 시 surface resolve.
4. **모든 단위 + 매뉴얼 검증 동등 통과** — 잠금화면 매뉴얼 확인 절차(`Docs/Verification/RelaunchRestore.md`와 동등 수준)에서 동작 확인.
5. **A4 invariant 보존** — 새 coordinator도 협력자를 외부에서 받는다. `XCTestRuntime` 참조 0건.

---

## 5. 목표 상태 (What is true after)

- 독립 `LockScreenTimerCoordinator` 클래스 (또는 actor)가 별도 파일에 거주. 위치 권고: `PTimer/Timers/LockScreenTimerCoordinator.swift`.
- ViewModel은 lock-screen coordinator를 직접 import / 호출 0건. 대신 timer 변화 이벤트만 publish.
- Lock-screen coordinator는 timer publisher / store를 *관찰*해 자기 책임을 수행.
- App entry (또는 DI factory)가 coordinator의 lifetime 소유.
- B1 진입 시 `TimerWorkspaceModel`은 coordinator를 알 필요가 전혀 없다 (decoupled).

---

## 6. 비-목표

- **`Docs/Specs/Timer.md` §5 시맨틱 변경** 안 함.
- **ActivityKit 추상화** 안 함 — 기존 `LockScreenTimerTargetExposer` protocol과 NoOp 구현 그대로.
- **새 timer 이벤트 publish 인프라 도입** 안 함 — 기존 publisher / `Combine` 또는 `@Observable`의 자연스러운 변화 신호 활용.
- **Timer state machine 변경** 안 함 (B4에서). 본 작업은 *ownership 이동*.
- **위젯(Widget) 타깃 변경** 안 함. `LockScreenTimerLiveActivity` attributes 그대로.

---

## 7. 검증 의무

| 레이어 | 의무 |
|---|---|
| **L1** Per-action 자동 | 모든 TimerManagerTests + ViewModelTests + 신규 `LockScreenTimerCoordinatorTests` pass |
| **L2** Semantic equivalence | **★★** **record-replay**: 동일 timer 라이프사이클 시퀀스(시작·일시정지·재개·완료·다중 timer)에 대해 lock-screen coordinator 호출 시퀀스 (representative timer ID, update 시각, end 시각) baseline 기록 후 diff 0. (`Docs/Verification/Strategy.md` §6 절차) |
| **L3** Architectural fitness | **신규**: ViewModel은 ActivityKit 또는 `LockScreenTimer*` 타입을 import 할 수 없다 (SwiftSyntax 검사). |
| **L4** UI 회귀 | 무관 (잠금화면 위젯 surface 변경 0건). |
| **L5** Drift | spec § 갱신 0건. Timer Spec §5 그대로. |

매뉴얼 검증: `Docs/Verification/` 산하에 새 매뉴얼 절차서 추가 권고 — `LockScreenLiveActivityContinuity.md` (5–6 시나리오: 단일·다중 timer, app active/inactive 전환, 재실행, force quit, all-stopped 시 surface 종료).

---

## 8. 인수 기준 (DoD)

- [ ] `LockScreenTimerCoordinator`가 별도 파일·타입.
- [ ] ViewModel에서 ActivityKit / `LockScreenTimer*` import 0건.
- [ ] 신규 `LockScreenTimerCoordinatorTests` (representative selection, tie-break, app-active resolve, all-stopped cleanup) pass.
- [ ] 기존 TimerManagerTests + ViewModelTests 동등 통과.
- [ ] L2 record-replay baseline diff 0.
- [ ] L3 fitness rule 추가 + 위반 0건.
- [ ] 매뉴얼: 잠금화면 시나리오 5종 통과.
- [ ] (권고) `Docs/Verification/LockScreenLiveActivityContinuity.md` 매뉴얼 절차서 추가.

---

## 9. 의존 / 후속

### 선행

| 액션 | 사유 |
|---|---|
| **A4** DI factory | Coordinator도 협력자 주입. A4 머지 후가 안전. |
| **A8** Presenter | 선행 권고. ViewModel이 Presenter 방향으로 분해 시작된 후가 자연스러움. |

### 후속

- **B1** ViewModel 분할 PR 3 (`TimerWorkspaceModel` 도입) 시 lock-screen은 이미 분리되어 있어 모델은 timer 책임만 가짐.
- **B4** Timer state types 작업과 무관 (lock-screen은 state 표현 형식과 독립).

---

## 10. 구현 PR 분할 권고

본 spec 머지 후 2 단계 PR:

1. **(PR 1) Coordinator 도입 + ViewModel ownership 이동** — 새 coordinator 타입 도입, app entry / DI factory가 lifetime 소유, ViewModel은 timer 이벤트만 publish. 기존 ViewModelTests 동등 통과.
2. **(PR 2) Lint rule 영구 추가 + 매뉴얼 절차서 추가** — F-rule(ViewModel ↛ ActivityKit), `LockScreenLiveActivityContinuity.md` 매뉴얼.

각 PR:
- branch `feature/PTIMER-118-a9-lock-screen-coord-step-N`
- L2 baseline diff 0 명시

---

## 11. 위험 / 트레이드

| 위험 | 완화 |
|---|---|
| Timer 이벤트 publish 구조가 기존에 명확치 않음 — coordinator가 timer를 *어떻게* 관찰? | (1) 기존 `TimerManager`에 Combine publisher 또는 closure callback이 이미 있으면 재사용. (2) 없으면 *최소한의* publisher만 추가 — full event sourcing 도입 금지. |
| Coordinator가 race condition으로 stale activity 표시 | TimerManager 호출 thread 일관성 유지 (`@MainActor` 권장). race test 케이스 추가. |
| App active 전이 시 surface resolve 로직이 누락되면 새 instance 생성 → spec 위반 | record-replay 베이스라인에 active 전이 시퀀스 포함 의무. |

---

## 12. 후속 갱신

본 spec은 *살아있는* 문서. 갱신 트리거:

- B1 spec이 `TimerWorkspaceModel` 표면적을 확정하면 §3 분리 대상 재검토.
- 구현 중 invariant 부정확 발견 → spec 갱신 후 PR 진행.
- B1 머지 후 본 spec은 archive 후보.
