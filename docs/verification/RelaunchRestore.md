<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Timer Relaunch Restore — Manual Verification

## Scope

App 프로세스가 종료된 뒤 새 launch가 영속된 timer snapshot으로부터 workspace를 재구성하는 동작을 사람이 직접 확인하는 절차.

(같은 프로세스에서 inactive/background → active 전이 시의 in-memory 재계산은 본 절차의 대상이 아니다 — 그건 reactivation 동작이며 별개.)

행동 계약: [Timer Lifecycle spec](../specs/timers/lifecycle.md) (Persistence and restoration).

## Manual Verification

### Running timer survives relaunch

1. 앱을 실행한다.
2. 관찰 가능한 길이의 timer를 만든다 (예: 30초).
3. 즉시 force quit.
4. 원래 completion 시각이 지나기 전에 재실행.
5. timer가 running 상태로 복원되는지 확인.
6. remaining time이 실제 경과한 wall clock을 반영하는지 확인.

### Running timer expires while the app is dead

1. 앱을 실행한다.
2. 짧은 timer를 만든다 (예: 3초).
3. completion 전에 force quit.
4. 원래 completion 시각이 지나도록 대기.
5. 앱 재실행.
6. timer가 completed로 복원되는지 확인.

### Paused timer remains frozen across relaunch

1. 앱을 실행한다.
2. timer를 만든다.
3. remaining time이 보일 때 pause.
4. force quit.
5. remaining time보다 더 길게 대기.
6. 앱 재실행.
7. timer가 여전히 paused (frozen, resumable)인지 확인.
8. remaining time이 pause 시점과 동일한지 확인.

### Completed timer remains completed across relaunch

1. 앱을 실행한다.
2. 매우 짧은 timer를 만들어 완료시킨다.
3. force quit.
4. 앱 재실행.
5. timer가 여전히 completed이고 같은 completion context를 보이는지 확인.

### Multiple timers preserve identity and ordering

1. 앱을 실행한다.
2. 다른 duration·이름·context의 timer를 최소 2개 만든다.
3. 하나는 pause, 다른 하나는 running 유지.
4. force quit.
5. 앱 재실행.
6. 복원된 각 카드가 같은 title·subtitle·order·status를 유지하는지 확인.
7. 복원 후에도 action이 올바른 timer 카드를 대상으로 하는지 확인.

### ND filter wheel stack survives relaunch (PTIMER-199)

Timer snapshot이 아닌 camera-slot session snapshot의 복원이지만, 같은
"process 종료 후 재실행" 절차를 공유하므로 여기서 함께 확인한다.

1. 앱을 실행한다.
2. edge Add control로 ND 휠을 2개 이상으로 만들고, 서로 다른 값(프리셋
   6.6 포함 권장)을 선택한다.
3. force quit.
4. 앱 재실행.
5. 휠 개수·각 휠의 값·정렬 순서(내림차순, 0은 오른쪽)가 그대로
   복원되는지 확인.
6. ND 적용 셔터가 종료 전과 동일한 합산 값을 보이는지 확인.
7. 다른 카메라 슬롯으로 전환했다가 돌아와도 스택이 유지되는지 확인.

## Commit Verification

PR이 timer 영속성·복원에 영향을 주는 경우, 위 5개 timer 시나리오 모두 통과 + automated `TimerManagerTests`의 restore 케이스 통과를 PR 본문에 명시.

PR이 camera-slot session 영속성(ND 스택 포함)에 영향을 주는 경우, ND 스택 시나리오 통과 + automated `NDStackPersistenceTests` 통과를 PR 본문에 명시.
