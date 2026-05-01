# Timer Spec

> **Locale mirror.** 본 파일은 `docs/specs/Timer.md` 의 한국어 mirror. 표현 분쟁이 있을 때 영문판이 canonical.

**도메인**: 카운트다운 timer 라이프사이클, 영속화, 완료 알림, 잠금 화면 표면.

본 문서는 timer 런타임에 대한 행동 계약(behavior contract). 플랫폼 중립 — 단, 의도가 플랫폼 기능에 의존하는 경우(notification scheduling, Live Activity) 제약을 명시.

---

## 1. 상태 머신

### 1.1 상태

Timer 는 어느 시점에도 다음 세 상태 중 정확히 하나에 있다:

- **running** — 능동적으로 카운트다운. 남은시간이 벽시계와 함께 감소.
- **paused** — frozen. 남은시간이 변하지 않음.
- **completed** — 종단(terminal). 남은시간 = 0. 빠져나갈 수 없음.

Timer 의 표현은 현재 상태에서 의미 있는 필드만 carry — running 은 expected 종료 시간, paused 는 frozen 남은시간 + paused-at instant, completed 는 기록된 완료 timestamp. 상태들이 record 를 공유하는 nullable sibling 은 없음. 따라서 *invalid* 조합 (예: paused-at instant 를 가진 running timer) 은 표현 자체가 불가능.

### 1.2 전환

```
   ┌──────────┐  pause   ┌────────┐
   │ running  │ ───────▶ │ paused │
   │          │ ◀─────── │        │
   └──────────┘  resume  └────────┘
        │
        │ 벽시계가 종료시간 도달
        ▼
   ┌──────────┐
   │completed │   (terminal)
   └──────────┘
```

합법 전환은 오직: `running ⇄ paused`, `running → completed`. **paused → completed** 는 직접 전환 아님 — paused timer 는 complete 되기 전 resume 되어야 한다. completed 는 종단: 빠져나갈 수 없다.

Timer 의 `duration` 은 생성 시점에 설정되며 양수이고 finite. 시스템은 non-positive, non-finite, `NaN` duration 으로 생성하는 것을 거부한다.

### 1.3 생성 시점 snapshot

Timer 가 생성될 때, calculator 의 현재 결과가 timer 의 metadata 로 snapshot: shutter 값, ND stops, film identity (있으면), reciprocity 결과. 후속 calculator 변경은 snapshot 을 변경하지 않는다. 각 timer 는 자체 생성 시점 snapshot 을 carry.

---

## 2. 시간 시맨틱

### 2.1 남은시간

남은시간은 *계산되지* 저장되지 않으며, 상태에 의존:

- **running** — `남은시간 = endDate − now`, `[0, ∞)` 로 clamp.
- **paused** — pause 시점에 capture 된 값에서 frozen.
- **completed** — 정확히 0.

남은시간과 status 의 read 는 단일 source 에서 와야 한다. UI layer 는 이들을 독립적으로 snapshot 하거나 re-derive 하지 않는다 — 런타임 모델에서 read.

### 2.2 Tick

실행 중 timer 는 약 100 ms 주기 tick 으로 벽시계 대조 평가:

- 모든 실행 중 timer 의 남은시간 재계산
- 남은시간이 0 에 도달한 timer 를 (작은 tolerance ε 안에서, 부동소수점 edge case 보호) `completed` 로 전환
- 구독한 UI 가 redraw 하도록 current-date 스트림 publish

Tick 은 calculator workspace, calculator 의 변수 섹션, 또는 비-timer 표면을 rebuild 하지 않는다. timer display state 만 update. (Wiki 8880129)

### 2.3 Resume 은 남은시간을 보존

Paused timer 가 resume 될 때, frozen 남은시간이 새 `endDate = now + 남은시간` 의 기반이 된다. 원래 `duration` 은 변하지 않고, `endDate` 만 forward shift. resume 후 즉시 다시 pause 하면 새 남은시간이 freeze.

---

## 3. 영속화 + 복원

### 3.1 Snapshot 영속화

런타임은 앱 종료 가로질러 전체 timer 컬렉션을 영속화한다. 영속화 형태는 두 부분으로 분리되어 layer 분리가 디스크에서도 mirror:

**Per-timer 런타임 snapshot** — timer 의 런타임 상태를 재구성하는 데 필요한 모든 것:

- **identity** — 안정된 id 보존, 카드와 액션이 같은 항목을 계속 target.
- **status** — 정확한 복원 규칙 선택 (running / paused / completed). 여기서 `paused` 는 *frozen, resumable* 상태이며 종단 stop 이 아님.
- **original duration** — timer 의 의도된 target 보존 (display + 경과 계산).
- **creation time** — 출처(provenance) 보존, 안정된 재구성 지원.
- **expected completion time** — 실행 중 timer 가 재시작 시 벽시계와 reconcile (running status only).
- **paused remaining duration** — 앱이 죽은 시간을 가로질러 paused timer 가 frozen 유지 (paused status only).
- **paused-at time** — UI 에서 보이는 paused-state context 보존 (paused status only).
- **completed-at time** — 최종 완료 timestamp 보존 (completed status only).

**Per-timer display metadata snapshot** — display-only state 를 별도로 영속화 — layer 경계가 디스크에서도 보존되도록:

- 컬렉션 레벨의 **next-order 카운터** — 새로 만든 카드가 복원된 카드 뒤에 정렬되도록.
- per-timer **id, order, display name, basis summary** — 재시작 가로질러 카드 정렬과 라벨링 보존.

영속화 형태는 round-trip 해야 함 — 인코딩 후 디코딩하면 동등한 컬렉션을 yield. 빈 컬렉션은 영속화된 blob 을 *완전 제거* (빈 payload 쓰지 않음).

On-disk schema 는 런타임 표현과 *독립*: 영속화된 record 는 flat shape (status discriminator + per-state 필드들) 을 유지하며, encoder 는 런타임이 메모리에서 어떻게 표현하든 그 shape 으로 쓴다. Decoder 는 영속화된 필드들로부터 적절한 런타임 case 를 재구성. 이 분리로 런타임 form 은 저장 데이터 마이그레이션 없이 진화할 수 있다.

### 3.2 Backward-compatible status 디코딩

Decoder 는 `"stopped"` 와 `"paused"` 를 같은 paused-state 토큰으로 받아들인다. Encoder 는 `"paused"` 만 쓴다.

### 3.3 복원 로직

복원은 앱 시작 시 한 번 발생, 후속 reactivation 에서는 발생하지 않음. 각 영속화된 timer 에 대해:

- **running** — `now ≥ endDate − ε` 이면 `completed` 로 복원 (종료시간이 종료 동안 지났음). 아니면 `running` 으로 유지하고 tick 재개.
- **paused** — `paused` 로 복원, frozen 남은시간 유지. 종료 동안의 벽시계는 무관.
- **completed** — `completed` 로 복원, `endDate` 는 기록된 완료 시간으로 설정. 기록된 완료 시간이 누락되면 timer 의 `startDate + duration` 으로 fallback.

복원은 완료 알림, push notification, 또는 사용자 대면 피드백을 fire 하지 않는다. state recovery 만.

### 3.4 Reactivation reconciliation

앱이 포어그라운드로 돌아올 때, 런타임은 실행 중 timer 를 벽시계 대조해 reconcile 하고, 비활성 기간 동안 완료된 경우 상태 update. 완료 알림 (sound, haptic) 은 reactivation 으로 트리거되지 않는다 — 사용자가 인지할 수 있는 포어그라운드 tick 으로만 fire.

---

## 4. 완료 알림

### 4.1 포어그라운드 피드백

Timer 가 application active + 포어그라운드일 때 `completed` 로 전환되면, 시스템은 짧은 audio cue + haptic 재생. 각 전환은 정확히 한 cue + 정확히 한 haptic 을 produce. Reactivation 으로 트리거된 완료는 cue 를 produce 하지 않는다.

### 4.2 백그라운드 + 잠금 화면 전달

앱이 백그라운드 또는 기기가 잠겨 있을 때 실행 중인 timer 에 대해, 시스템은 각 실행 중 timer 의 expected 완료 시간에 local notification 을 schedule. Schedule 은 timer identity 로 결정적으로 keyed:

- timer 생성 → notification schedule
- 일시정지 또는 제거 → notification cancel
- resume → 새 완료 시간으로 reschedule
- `completed` 로 전환 → 아직 pending 인 request cancel

같은 timer identity 에 대한 중복 scheduling 은 발생하지 않는다.

---

## 5. 잠금 화면 표면

시스템은 한 번에 한 *대표* 실행 중 timer 를 잠금 화면에 노출 — 플랫폼의 Live Activity 기능 경유.

### 5.1 대표 선택

대표 timer 는 **expected 완료 시간이 가장 빠른** 실행 중 timer. 동률은 결정적으로 해소 (예: 안정 identity 기준) — 같은 timer 가 re-evaluation 가로질러 선택되도록. 실행 중 timer 가 없으면 잠금 화면 표면은 "no active timer" 표시 (stale 데이터 아님).

### 5.2 연속성

앱이 active 가 될 때, 시스템은 기존 잠금 화면 표면을 *resolve* (재생성 아님). Timer 추가, 완료, relocking 은 같은 Live Activity 인스턴스가 update — 병렬 activity 를 spawn 하지 않는다.

### 5.3 Refresh cadence

잠금 화면 표면은 보이는 시간을 약 1 s cadence 로 refresh. Widget rendering layer 가 이 refresh 를 책임지고, 런타임은 관련 변경 시마다 target 완료 시간을 publish.

---

## 6. 표시 정렬

런타임이 정렬 결정을 *한 번* 내리고, UI layer 는 re-sort 없이 소비.

- **Active 그룹** — running + paused timer 가 한 안정된 정렬 도메인. 정책: **생성 LIFO** — 가장 최근 생성된 timer 가 먼저. running 과 paused 는 그룹 안에서 분리되지 않음 — 둘 다 "active".
- **Completed 그룹** — completed timer, 완료 시간 desc. 가장 최근 먼저. Active 그룹 *뒤* 에 표시.

Compact / expanded 표면은 같은 정렬을 사용. 선택/포커스된 timer (있을 때) 는 reorder 하지 않고 highlight 만.

---

## 7. Forbidden patterns

시스템은 다음을 **하지 않는다**:

1. 생성된 timer 의 metadata snapshot 을 calculator 입력 변경에 반응해 mutate.
2. UI 표면 (dock, sheet, overlay, list) 안에서 timer 상태의 별도 사본을 유지. 모든 표면은 같은 런타임 source 의 *읽기 전용 projection*.
3. Tick 으로 calculator workspace 를 rebuild. Tick 은 timer-display state 에만 영향.
4. View-builder 코드 경로 안에서 timer 상태 mutation 로직 실행. 런타임이 mutation 을 own, view 는 read 만.
5. `CalculatorState` 와 `TimerRuntimeState` 를 단일 mutable 구조로 collapse. Calculator state 는 immutable 생성-시점 snapshot, 런타임 state 는 elapsed/paused/completed 보유.
6. 앱 reactivation 으로 완료 sound/haptic fire.
7. 같은 timer identity 에 대한 중복 완료 notification schedule.
8. 모든 timer 가 멈춘 후 stale 상태에 대한 잠금 화면 Live Activity 표시.
9. 남은시간이 UI 표면들 사이에서 비일관 값을 read 하도록 허용. 단일 source of truth.

---

## 8. Drift 와 미해결 질문

- **완료 timer 보존.** Wiki 8847362 가 completed 는 "최근 항목만" 으로 제한될 수 있다고 명시. 구체적 보존 임계값은 결정 안 됨.
- **다중 timer 작업의 selection 모델.** Wiki 9601025 가 강한 selection 모델을 의도적으로 deferring. 다중 선택, batch action, 또는 cross-timer 링킹 spec 은 없음.
- **Bottom sheet 의 detent threshold** (compact 98 pt + ND 예약 132 pt; large 560 pt; 92 pt up-drag, 64 pt down-drag) 는 [UI Spec](UI.md) §4 에 문서화.
- **Notification 그룹화 + audio 정책.** 짧은 시간 안 다중 백그라운드 완료가 group 되어야 하는지, audio cue 가 timer 종류로 변하는지 정의 spec 없음.
- **Live Activity 테스트 커버리지.** Wiki 19103745 가 ActivityKit + notification 통합 테스트 누락 명시. 잠금 화면 동작은 §5 의 contract 으로 governed 되지만 시스템 레벨 통합 path 에 대해 아직 검증 안 됨.
- **Pause-during-completion race.** "사용자가 런타임 중 완료-evaluation 도중 pause" 에 대한 명시 spec 없음 — 동작은 tick ordering 에서 emerge. 명료화 가치 있음.
- **Notification copy.** "이 timer 가 완료" 외 local notification body 텍스트 spec 없음.

---

## 9. Sources of intent (참고)

이들은 *참고 자료* 이며 normative 가 아니다.

**Wiki (페이지 id 인용)**
- 8847362 — Floating Timer Dock UI Design (display 정책, 정렬, dock 상태, destructive-action 배치)
- 8880129 — Floating Timer Dock Architecture (state 분리, projection-over-copying, forbidden patterns)
- 9568257 — Bottom Sheet UI 기획 초안 (compact / expanded UX, deferred selection model)
- 9601025 — Bottom Sheet UI Architecture 설계 초안 (도메인 / presentation / view layer 분리)

