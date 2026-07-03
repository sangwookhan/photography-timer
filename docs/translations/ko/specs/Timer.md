# Timer Spec

> **Locale mirror.** 본 파일은 `docs/specs/Timer.md`의 한국어 mirror. 표현 분쟁이 있을 때 영문판을 canonical로 본다.

**도메인**: 카운트다운 timer 라이프사이클, 영속화, 완료 알림, 잠금 화면 표면.

본 문서는 timer 런타임에 대한 행동 계약(behavior contract). 플랫폼 중립 — 단, 의도가 플랫폼 기능에 의존하는 경우(notification scheduling, Live Activity) 제약을 명시.

---

## 1. 상태 머신

### 1.1 상태

Timer는 어느 시점에도 다음 네 상태 중 정확히 하나에 있다:

- **running** — 능동적으로 카운트다운. 남은시간이 벽시계와 함께 감소.
- **paused** — frozen. 남은시간이 변하지 않음.
- **completed** — 종단(terminal); timer가 자연스럽게 끝에 도달. 남은시간 = 0. 빠져나갈 수 없음.
- **canceled** — 종단(terminal); 사용자가 끝나기 전에 timer를 멈춤. 남은시간 = 0. 빠져나갈 수 없음. completed와 구별되어 포기된 컷이 *Done*이 아니라 *Canceled*로 surface 되도록.

Timer의 표현은 현재 상태에서 의미 있는 필드만 포함한다 — running은 expected 종료 시간, paused는 frozen 남은시간 + paused-at instant, completed는 기록된 완료 timestamp. 상태들이 record를 공유하는 nullable sibling은 없음. 따라서 *invalid* 조합 (예: paused-at instant를 가진 running timer)은 표현 자체가 불가능.

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

합법 전환은 오직: `running ⇄ paused`, `running → completed`. **paused → completed**는 직접 전환 아님 — paused timer는 complete 되기 전 resume 되어야 한다. completed는 종단: 빠져나갈 수 없다.

Timer의 `duration`은 생성 시점에 설정되며 양수이고 유한한. 시스템은 non-positive, 유한하지 않은, `NaN` duration으로 생성하는 것을 거부한다.

### 1.3 생성 시점 snapshot

Timer가 생성될 때, calculator의 현재 결과가 timer의 metadata로 snapshot: shutter 값, ND stops, film identity (있으면), reciprocity 결과. 후속 calculator 변경은 snapshot을 변경하지 않는다. 각 timer는 자체 생성 시점 snapshot을 포함한다.

### 1.4 Timer 식별 (identity)

모든 timer는 *어느 컷에 속하는지*를 기술하는 작은 연결 다발 — **식별(identity)** — 을 포함한다. 식별은 시작 시점에 captured 되며 runtime 상태 머신 (§1.1)과 시간 시맨틱 layer (§2) 와는 독립적이다.

**구성.** Timer의 식별은 다음의 union:

- 시작된 **카메라 슬롯** (시작 시점에 활성이던 슬롯의 id와 사람이 읽을 수 있는 라벨; [Requirements](../../../requirements/Requirements.md) §3.8 / FR-8.5 참조);
- **필름 디스크립터** — 필름이 선택되어 있었으면 canonical stock 이름과 활성 profile qualifier, 그렇지 않으면 digital workflow를 신호하는 명시적 *No film* 디스크립터;
- 그 duration을 산출한 **노출 source**.

**노출 source 카테고리.** 정의된 source:

- *digital result* — non-film calculator (필름 미선택); ND-조정 출력 셔터에서 timer 시작.
- *film-adjusted shutter* — film workflow; Adjusted Shutter 행에서 timer 시작.
- *film-corrected exposure* — film workflow; Corrected Exposure 행에서 timer 시작.
- *target shutter* — 사진가의 Target Shutter duration으로부터 시작된 timer. Target duration 자체가 timer duration이다; 비교 값의 가용 여부와 무관. Target-shutter timer는 lifetime 동안 adjusted timer 및 corrected timer와 구별되는 identity를 유지한다. ([Requirements](../../../requirements/Requirements.md) §3.9 + [Calculator Spec](Calculator.md) §3.6 참조.)
- *manual* — calculator 외부에서 공급된 사전 계산된 셔터값. Manual timer는 calculator 식별을 *capture하지 않는다* — 카메라 슬롯도, 필름 디스크립터도, calculator-bound 노출 source도 포함하지 않으며, 표시 계층은 활성 슬롯 식별을 빌리지 않고 generic *Manual timer* basis 라벨로 대체. (FR-4.7)

**Capture 규칙.** 식별 capture는 *시작 시점에 한 번* 일어난다. Captured 값은 timer에 고정되며, runtime 상태로부터 다시 도출되지 않고, 사용자가 이후 활성 카메라 슬롯을 전환하거나, 슬롯을 rename하거나, 활성 필름을 바꾸거나, profile을 다시 선택하더라도 덮어쓰이지 않는다.

**상태 가로지른 안정성.** 식별은 timer의 lifetime을 가로질러 불변. *running*, *paused*, *completed*, workspace 안에서의 *재정렬*, 사용자 *focus*, 확장 보기 *inspect*, 영속화 복원 — 같은 식별 다발이 동반된다. 상태 머신 전환 (§1.2)은 식별을 mutate 하지 않는다.

**표시 vs 데이터.** 식별은 *데이터*. workspace가 카메라 / 필름 / source를 카드 라벨이나 accessibility 문자열로 *어떻게* 렌더링하는지는 [UI Spec](UI.md)에 문서화된 표시 관심사. 식별의 데이터 형태가 contract이며, 표시 문자열은 contract를 깨지 않고 변경 가능.

---

## 2. 시간 시맨틱

### 2.1 남은시간

남은시간은 *계산되지* 저장되지 않으며, 상태에 의존:

- **running** — `남은시간 = endDate − now`, `[0, ∞)`로 clamp.
- **paused** — pause 시점에 capture 된 값에서 frozen.
- **completed** — 정확히 0.

남은시간과 status의 read는 단일 source에서 와야 한다. UI layer는 이들을 독립적으로 snapshot 하거나 re-derive 하지 않는다 — 런타임 모델에서 read.

### 2.2 Tick

실행 중 timer는 약 100 ms 주기 tick으로 벽시계 대조 평가:

- 모든 실행 중 timer의 남은시간 재계산
- 남은시간이 0에 도달한 timer를 (작은 tolerance ε 안에서, 부동소수점 edge case 보호) `completed`로 전환
- 구독한 UI가 redraw 하도록 current-date 스트림 publish

Tick은 calculator workspace, calculator의 변수 섹션, 또는 비-timer 표면을 rebuild 하지 않는다. timer display state만 update. (Wiki 8880129)

### 2.3 Resume은 남은시간을 보존

Paused timer가 resume 될 때, frozen 남은시간이 새 `endDate = now + 남은시간`의 기반이 된다. 원래 `duration`은 변하지 않고, `endDate`만 forward shift. resume 후 즉시 다시 pause 하면 새 남은시간이 freeze.

---

## 3. 영속화 + 복원

### 3.1 Snapshot 영속화

런타임은 앱 종료 가로질러 전체 timer 컬렉션을 영속화한다. 영속화 형태는 두 부분으로 분리되어 layer 분리가 저장 형태에서도 유지:

**Per-timer 런타임 snapshot** — timer의 런타임 상태를 재구성하는 데 필요한 모든 것:

- **identity** — 안정된 id 보존, 카드와 액션이 같은 항목을 계속 target.
- **status** — 정확한 복원 규칙 선택 (running / paused / completed). 여기서 `paused`는 *frozen, resumable* 상태이며 종단 stop이 아님.
- **original duration** — timer의 의도된 target 보존 (display + 경과 계산).
- **creation time** — 출처(provenance) 보존, 안정된 재구성 지원.
- **expected completion time** — 실행 중 timer가 재시작 시 벽시계와 reconcile (running status only).
- **paused remaining duration** — 앱이 죽은 시간을 가로질러 paused timer가 frozen 유지 (paused status only).
- **paused-at time** — UI에서 보이는 paused-state context 보존 (paused status only).
- **completed-at time** — 최종 완료 timestamp 보존 (completed status only).

**Per-timer display metadata snapshot** — display-only state를 별도로 영속화 — layer 경계가 디스크에서도 보존되도록:

- 컬렉션 레벨의 **next-order 카운터** — 새로 만든 카드가 복원된 카드 뒤에 정렬되도록.
- per-timer **id, order, display name, basis summary** — 재시작 가로질러 카드 정렬과 라벨링 보존.

영속화 형태는 round-trip 해야 함 — 인코딩 후 디코딩하면 동등한 컬렉션을 yield. 빈 컬렉션은 영속화된 blob을 *완전 제거* (빈 payload 쓰지 않음).

On-disk schema는 런타임 표현과 *독립*: 영속화된 record는 flat shape (status discriminator + per-state 필드들)을 유지하며, encoder는 런타임이 메모리에서 어떻게 표현하든 그 shape으로 쓴다. Decoder는 영속화된 필드들로부터 적절한 런타임 case를 재구성. 이 분리로 런타임 form은 저장 데이터 마이그레이션 없이 진화할 수 있다.

### 3.2 Backward-compatible status 디코딩

Decoder는 `"stopped"`와 `"paused"`를 같은 paused-state 토큰으로 받아들인다. Encoder는 `"paused"`만 쓴다.

### 3.3 복원 로직

복원은 앱 시작 시 한 번 발생, 후속 reactivation 에서는 발생하지 않음. 각 영속화된 timer에 대해:

- **running** — `now ≥ endDate − ε` 이면 `completed`로 복원 (종료시간이 종료 동안 지났음). 아니면 `running`으로 유지하고 tick 재개.
- **paused** — `paused`로 복원, frozen 남은시간 유지. 종료 동안의 벽시계는 무관.
- **completed** — `completed`로 복원, `endDate`는 기록된 완료 시간으로 설정. 기록된 완료 시간이 누락되면 timer의 `startDate + duration`으로 대체.

복원은 완료 알림, push notification, 또는 사용자 대면 피드백을 fire 하지 않는다. state recovery만.

### 3.4 Reactivation reconciliation

앱이 포어그라운드로 돌아올 때, 런타임은 실행 중 timer를 벽시계 대조해 reconcile 하고, 비활성 기간 동안 완료된 경우 상태 update. 완료 알림 (sound, haptic)은 reactivation으로 트리거되지 않는다 — 사용자가 인지할 수 있는 포어그라운드 tick 으로만 fire.

---

## 4. 완료 알림

Timer는 완료를 현장에서 놓치기 어렵도록 **단계적 alert**을 표시한다. 긴 timer의 경우 terminal 완료 alert에 앞서 완료가 임박했음을 알리는 pre-alert가 하나 또는 둘 선행한다.

### 4.1 Duration별 alert 단계

`T`를 예상 완료 시점이라 하자. Timer가 만들어내는 단계적 alert은 duration에 따라 달라진다:

- **duration ≤ 30s** — `T`에만 완료 alert.
- **30s < duration ≤ 60s** — `T − 5s`에 **pre1**, 이어서 `T`에 완료.
- **duration > 60s** — `T − 10s`에 **pre1**, `T − 5s`에 **pre2**, 이어서 `T`에 완료.

이 lead time은 **포어그라운드 / in-tick** schedule이다: 어느 duration이 pre-alert를 받는지(구간 경계)는 결정적이고 플랫폼 중립적이며, 포어그라운드 tick 경로는 delivery 지연이 없으므로 이 시점에 정확히 pre-alert를 fire 한다. 플랫폼의 **백그라운드 notification** 채널은 같은 구간에 대해 notification 전달 지연을 흡수하기 위해 *더 이른* lead time을 사용할 수 있다 (§4.4 참고) — 구간 자체는 동일하고 lead time만 다르다.

### 4.2 Alert 성격

- **pre1**은 부드러운 "완료 임박" 신호다. Haptic-first — 플랫폼이 지원하면 pre1은 sound보다 vibration/haptic을 우선한다. 백그라운드 delivery에서 vibration-only를 보장할 수 없는 플랫폼(특히 iOS local notification)은 pre1을 best-effort로 구현하며 vibration-only 동작을 약속하지 않는다.
- **pre2**는 더 강한 "곧 종료" escalation이다. **앱이 포어그라운드가 아닐 때만** 전달되며, 포어그라운드에 표시되는 alert로는 절대 나타나지 않는다. 문구는 남은시간을 전달한다 (예: "5s remaining").
- **completion**은 평소의 terminal alert이며 기존 동작보다 강해질 필요는 없다.

Pre-alert 문구는 남은시간을 전달하며("10s remaining", "5s remaining"), `T` 이전에 노출을 멈춰야 한다는 뜻을 암시하지 않는다.

### 4.2.1 무음 / 진동 모드에서의 가청성

현장 촬영에서는 사진가가 폰을 보고 있지 않을 수 있으므로, 완료 alert — 그리고 더 강한 pre2 escalation — 은 각 플랫폼이 허용하는 가장 강한 경로로 **기기가 무음 / 진동 모드일 때도 들려야 한다**:

- 기본 notification-sound 경로는 무음 / 진동 모드에서 억제되므로 불충분하다. 시스템은 플랫폼이 허용하는 한 무음 / 진동 모드에서도 살아남는 alert 경로를 대신 사용한다 (예: alarm-stream sound, 또는 무음 스위치를 override 하는 playback 지향 audio session을 통한 앱 소유 재생).
- **pre1**은 계속 haptic-first이며 이 요구사항으로 audible이 되지는 않는다.
- **포어그라운드** 완료(및 해당하는 경우 pre2)는 위의 audible 경로를 사용한다: Android는 alarm-stream sound, iOS는 앱이 active인 동안 무음 스위치를 override 하는 앱 소유 `.playback` audio.
- **백그라운드 / 잠금** 상태의 delivery는 local notification만으로 이루어진다 (§4.4). Android는 notification 경로가 alarm-stream sound를 구동하므로 백그라운드/잠금 상태의 완료도 무음 / 진동 모드에서 들린다. iOS는 종료 시점에 sound를 재생하기 위해 스스로를 살려두지 않는다 — 백그라운드 audio keep-alive 방식을 시도했으나 신뢰할 수 없어 제거했다(화면이 꺼진 상태에서 소리가 나지 않는 경우가 있었다) — 따라서 무음 모드에서 백그라운드/잠금 상태의 iOS 완료는 local notification 자체가 제공하는 범위로 제한된다. Critical Alerts entitlement는 사용하지 않으며(out of scope), 시스템 Clock timer와의 parity도 claim 하지 않는다.
- **뒤늦은 alarm 없음.** 앱이 백그라운드/잠금 상태인 동안 완료된 timer는 앱이 나중에 포어그라운드로 돌아왔을 때 audible alarm을 뒤늦게 재생하지 않는다. 복귀 시 완료는 조용히 reconcile — 상태와 history만 update — 되며, 실제로 *실시간(live)*으로 포어그라운드에서 완료되는 경우에만 alarm이 재생된다.

### 4.2.2 Alarm 정지

앱이 재생하는 완료 alarm(§4.2.1의 alarm-stream / playback-session sound — OS가 소유하는 notification sound와는 다름)은 시간이 제한되어 있고 정지 가능하다:

- **제한된 자동 정지.** Alarm은 짧은 고정 구간 동안만 울리고 스스로 멈추므로, 사용자가 폰에 다가가지 않아도 무한히 울리지 않는다. 한 번에 최대 하나의 timer만 alarm을 울린다.
- **앱 내 탭으로 정지.** Alarm이 울리는 동안 사용자는 실행 중 timer affordance — compact mini-timer 표면 또는 대응하는 timer 행 — 을 탭해 앱 안에서 소리를 끌 수 있다. 정지 affordance는 **해당 timer의 alarm이 울리는 동안에만** 나타나며, 그 외에는 해당 표면이 평소 동작을 유지한다(예: mini timer는 workspace를 연다).
- **Sound만.** Alarm 정지는 audio만 끈다. Timer 상태는 바뀌지 않는다 — `completed` timer는 completed 상태를 유지하며 dismiss 되거나 제거되지 않고, 여전히 실행 중인 timer는 계속 실행된다. 정지는 "어느 timer가 울리는가" 신호만 지우므로 affordance는 평소 동작으로 돌아간다.

이번 범위는 앱 내 정지만 다루며, notification-level 정지 action은 out of scope.

### 4.2.3 무음 모드 안내 (수동적, best-effort)

백그라운드/잠금 상태의 무음 가청성이 모든 플랫폼에서 보장되지는 않으므로(§4.2.1), 앱은 기기가 음소거되어 있을 수 있음을 암시하는 수동적 안내를 표시해 사진가가 긴 노출 전에 볼륨을 확인할 수 있게 할 수 있다. 철저히 비침해적이다:

- **Best-effort일 뿐.** 무음 스위치를 신뢰성 있게 감지한다고 주장하지 않는다. 문구는 부드럽게 유지되며(예: "Silent mode may be on. Turn it off and check volume before long exposures.") 기기가 무음 상태*라고* 단정하지 않는다.
- **Timer를 절대 gate 하지 않는다.** Timer 시작을 막거나, 지연시키거나, gate 하지 않으며, modal을 띄우거나 확인을 요구하지 않고, 앱이 보이는/포어그라운드 상태일 때만 동작한다.
- **드물게 표시.** 세션당 최대 한 번, 방해되지 않는 작은 안내로 나타나며, 완료 alarm이 울리는 중이거나 timer notification을 통해 앱이 열린 경우에는 표시되지 않는다.

플랫폼이 playback timing으로 이 probe를 구현하는 경우, 완료-alarm audio와 간섭하지 않도록 격리된 경로를 사용한다.

### 4.3 포어그라운드 피드백

Timer가 application active + 포어그라운드일 때 `completed`로 전환되면, 시스템은 짧은 audio cue + haptic 재생. 각 전환은 정확히 한 cue + 정확히 한 haptic을 만들어낸다. Reactivation으로 트리거된 완료는 cue를 만들어내지 않는다.

포어그라운드에서는 timer가 pre1 시점을 지날 때 시스템이 haptic-first **pre1** cue를 추가로 재생할 수 있다. **pre2**는 (§4.2에 따라) 포어그라운드에서 절대 재생되지 않는다. 포어그라운드 pre-alert cue는 인지 가능한 포어그라운드 tick을 통해서만 fire 하며 reactivation reconciliation으로는 fire 하지 않고, 각 시점 통과마다 최대 한 번만 fire 한다.

### 4.4 백그라운드 + 잠금 화면 전달

앱이 백그라운드이거나 기기가 잠겨 있을 때 실행 중인 timer에 대해, 시스템은 해당하는 각 단계(pre1, pre2, completion)의 시점에 local notification을 schedule 한다. Schedule은 timer identity + 단계로 결정적으로 keyed 되므로:

- timer 생성 → 해당하는 모든 단계 schedule
- 일시정지 또는 제거 → 모든 단계 cancel
- resume → 새 완료-상대 시점으로 모든 단계 reschedule
- `completed`로 전환되거나 취소됨 → 아직 pending인 단계 cancel

같은 timer identity + 단계에 대한 중복 scheduling은 발생하지 않는다.

**iOS notification 타이밍 + 문구.** Local notification은 수 초 늦게 전달될 수 있어 `T − 5s` alert가 timer가 이미 완료된 *이후에* 도착할 수 있다. 그래서 iOS는 백그라운드 pre-alert를 §4.1의 포어그라운드 schedule보다 **더 이르게** fire 한다 — 같은 구간, 더 이른 lead time:

- **30s < duration ≤ 60s** — `T − 15s`에 audible pre-alert 하나, 이어서 완료.
- **duration > 60s** — `T − 30s`에 부드러운(무음) heads-up, `T − 15s`에 audible pre-alert, 이어서 완료.

각 pre-alert의 본문은 **schedule된 시점의** 남은시간(제때 도착했다는 claim이 아님)과 사용자 로컬 짧은 시간 스타일의 **예상 종료 시각**을 함께 명시한다(예: "15s remaining · ends 10:30 PM") — delivery가 늦더라도 실제 목표 시점이 모호하지 않도록. 완료 notification 문구는 변경되지 않는다.

Android는 기존에 승인된 동작을 유지한다: alarm-stream notification 경로가 진동 / 무음 모드에서 audible alert를 구동하므로 기존 pre-alert 타이밍이 그대로 유지된다.

---

## 5. 잠금 화면 표면

시스템은 한 번에 한 *대표* 실행 중 timer를 잠금 화면에 노출 — 플랫폼의 Live Activity 기능 경유.

### 5.1 대표 선택

대표 timer는 **expected 완료 시간이 가장 빠른** 실행 중 timer. 동률은 결정적으로 해소 (예: 안정 identity 기준) — 같은 timer가 re-evaluation 가로질러 선택되도록. 실행 중 timer가 없으면 잠금 화면 표면은 "no active timer" 표시 (stale 데이터 아님).

### 5.2 연속성

앱이 active가 될 때, 시스템은 기존 잠금 화면 표면을 *resolve* (재생성 아님). Timer 추가, 완료, relocking은 같은 Live Activity 인스턴스가 update — 병렬 activity를 spawn 하지 않는다.

### 5.3 Refresh cadence

잠금 화면 표면은 보이는 시간을 약 1 s cadence로 refresh. Widget rendering layer가 이 refresh를 책임지고, 런타임은 관련 변경 시마다 target 완료 시간을 publish.

---

## 6. 표시 정렬

런타임이 정렬 결정을 *한 번* 내리고, UI layer는 re-sort 없이 소비.

- **Active 그룹** — running + paused timer가 한 안정된 정렬 도메인. 정책: **생성 LIFO** — 가장 최근 생성된 timer가 먼저. running과 paused는 그룹 안에서 분리되지 않음 — 둘 다 "active".
- **Completed 그룹** — completed timer, 완료 시간 desc. 가장 최근 먼저. Active 그룹 *뒤*에 표시.

Compact / expanded 표면은 같은 정렬을 사용. 선택/포커스된 timer (있을 때)는 reorder 하지 않고 highlight만.

---

## 7. Forbidden patterns

시스템은 다음을 **하지 않는다**:

1. 생성된 timer의 metadata snapshot을 calculator 입력 변경에 반응해 mutate.
2. UI 표면 (dock, sheet, overlay, list) 안에서 timer 상태의 별도 사본을 유지. 모든 표면은 같은 런타임 source의 *읽기 전용 projection*.
3. Tick으로 calculator workspace를 rebuild. Tick은 timer-display state 에만 영향.
4. View-builder 코드 경로 안에서 timer 상태 mutation 로직 실행. 런타임이 mutation을 own, view는 read만.
5. `CalculatorState`와 `TimerRuntimeState`를 단일 mutable 구조로 collapse. Calculator state는 immutable 생성-시점 snapshot, 런타임 state는 elapsed/paused/completed 보유.
6. 앱 reactivation으로 완료 sound/haptic fire.
7. 같은 timer identity에 대한 중복 완료 notification schedule.
8. 모든 timer가 멈춘 후 stale 상태에 대한 잠금 화면 Live Activity 표시.
9. 남은시간이 UI 표면들 사이에서 비일관 값을 read 하도록 허용. 단일 source of truth.

---

## 8. Drift와 미해결 질문

- **완료 timer 보존.** Wiki 8847362가 completed는 "최근 항목만" 으로 제한될 수 있다고 명시. 구체적 보존 임계값은 결정 안 됨.
- **다중 timer 작업의 selection 모델.** Wiki 9601025가 강한 selection 모델을 의도적으로 defer. 다중 선택, batch action, 또는 cross-timer 링킹 spec은 없음.
- **Bottom sheet의 detent threshold** (compact 98 pt + ND 예약 132 pt; large 560 pt; 92 pt up-drag, 64 pt down-drag)는 [UI Spec](UI.md) §3.1 / §3.2에 문서화.
- **Notification 그룹화 + audio 정책.** 짧은 시간 안 다중 백그라운드 완료가 group 되어야 하는지, audio cue가 timer 종류로 변하는지 정의 spec 없음.
- **Live Activity 테스트 커버리지.** Wiki 19103745가 ActivityKit + notification 통합 테스트 누락 명시. 잠금 화면 동작은 §5의 contract으로 governed 되지만 시스템 레벨 통합 path에 대해 아직 검증 안 됨.
- **Pause-during-completion race.** "사용자가 런타임 중 완료-evaluation 도중 pause" 에 대한 명시 spec 없음 — 동작은 tick ordering에서 emerge. 명료화 가치 있음.
- **Notification copy.** "이 timer가 완료" 외 local notification body 텍스트 spec 없음.

---

## 9. Sources of intent (참고)

이들은 *참고 자료*이며 normative가 아니다.

**Wiki (페이지 id 인용)**
- 8847362 — Floating Timer Dock UI Design (display 정책, 정렬, dock 상태, destructive-action 배치)
- 8880129 — Floating Timer Dock Architecture (state 분리, projection-over-copying, forbidden patterns)
- 9568257 — Bottom Sheet UI 기획 초안 (compact / expanded UX, deferred selection model)
- 9601025 — Bottom Sheet UI Architecture 설계 초안 (도메인 / presentation / view layer 분리)

