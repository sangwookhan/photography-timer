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
2. Plus로 ND 휠을 2개 이상으로 만들고, 서로 다른 정수 스톱 값을 선택한다.
   예전 빌드에서 저장한 6.6 같은 분수 값이 있는 기기라면, 그 값을 그대로
   둔 채 이 절차로 그 휠이 같은 값으로 복원되는지도 확인한다(새로 고를 수
   있는 Standard 값은 0–30 정수 스톱뿐이다).
3. force quit.
4. 앱 재실행.
5. 휠 개수·각 휠의 값·정렬 순서(내림차순, 0은 오른쪽)가 그대로
   복원되는지 확인.
6. ND 적용 셔터가 종료 전과 동일한 합산 값을 보이는지 확인.
7. 다른 카메라 슬롯으로 전환했다가 돌아와도 스택이 유지되는지 확인.

### Filter Sets, auxiliary filters, and item moves survive relaunch (PTIMER-221)

계약: `docs/specs/calculator/filter-sets.md` (FILTER-ITEM-005/009,
FILTER-PERSIST-002, FILTER-SET-008, RESET-004/011). 이 절은 확인
절차다. 실제로 기기에서 실행한 항목과 자동 테스트로만 확인한 항목은 각
Code PR의 검증 보고에 구분해 기록한다.

1. 보조 필터 0개로 시작한다. ND 필터만 있는 Filter Set 하나를 선택하고
   Main에서 그 Set의 ND 값을 고른다.
2. 다른 카메라로 전환했다가 돌아오고, force quit 후 재실행한다. ND 값,
   ND 출처(Set), 선택한 Filter Set 순서가 그대로인지 확인한다.
3. 보조 필터를 섞는다: CPL(선택 값 하나)과 GND(기록만)를 장착하고 적용한다.
   재실행 후 각 필터의 이름, 모드, 기여 스톱이 같고 장착이 늘지 않았는지
   확인한다.
4. ND 이동: 선택한 Set A의 ND 항목을 휠에 둔 채, 선택하지 않은(Available)
   Set B로 그 항목을 저장해 옮긴다. A의 기존 휠이 Empty가 되고, B는
   Available 그대로이며, 선택한 Filter Set 목록과 순서가 바뀌지 않는지
   확인한다. 재실행 후에도 같은지 확인한다.
5. B를 선택한 상태에서 같은 이동을 반복한다: 같은 휠이 B 아래에서 그 항목을
   유지하는지 확인한다. 선택한 Set이 다른 두 번째 카메라에서는 그 카메라의
   선택으로 따로 판단되는지 확인한다.
6. 저장된 출처가 낡은 경우: 인벤토리 저장 직후 카메라 세션이 저장되기 전에
   앱이 종료된 상태를 재현할 수 있으면, 재실행 후에도 4·5와 같은 결과이고
   대상 Set이 자동으로 선택되지 않는지 확인한다. 이동 전에 시작한 타이머의
   기록(합계와 필터 참조)은 바뀌지 않아야 한다.
7. Reset: 보조 필터를 모두 지우고 선택한 Filter Set은 유지하는지 확인한다.
8. 예시 필터 세트: 인벤토리를 한 번도 저장한 적이 없는 설치나 업그레이드에서만
   Digital Magnetic Filters, Film Square ND/GND, Film Color Filters가 영어
   이름 그대로 한 번 나타나는지 확인한다. 저장된 빈 인벤토리, 지운 예시,
   읽을 수 없는 데이터나 읽기 실패에서는 다시 넣지 않아야 한다.

## Commit Verification

PR이 timer 영속성·복원에 영향을 주는 경우, 위 5개 timer 시나리오 모두 통과 + automated `TimerManagerTests`의 restore 케이스 통과를 PR 본문에 명시.

PR이 camera-slot session 영속성(ND 스택 포함)에 영향을 주는 경우, ND 스택 시나리오 통과 + automated `NDStackPersistenceTests` 통과를 PR 본문에 명시.

PR이 Filter Set·보조 필터·항목 이동의 영속성에 영향을 주는 경우, 위 PTIMER-221 절에서 실제로 실행한 항목과 자동 테스트(`FilterRestoreReconciliationTests`, `FilterStackPersistenceTests`, `FilterInventoryModelTests`)만으로 확인한 항목을 PR 본문에 구분해 적는다.
