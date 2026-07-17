# ND Wheel Architecture v1 — 동작 설명 (record)

PTIMER-199 ticket-scoped 기록. 4개의 ND 휠이 어떻게 생성되고,
값이 실시간으로 계산·표시되고, 커밋 시 순서가 바뀌고,
저장·복원되는지를 — v2 재설계 이전의 현행 구현 기준으로 —
흐름별로 설명한다. 재설계 근거가 히스토리에 남도록
`PTIMER-199-nd-wheel-architecture-ios-v2.md`와 함께 커밋되며, 병합 전
최종 정리 커밋에서 함께 삭제된다.

기준 커밋: `1f92989b` (에포크 모델 v3). 2026-07-17.

---

## 0. 전체 그림 — 데이터가 사는 곳

```mermaid
flowchart TB
    subgraph MODEL["CalculatorModel  (진실의 원천, @Observable)"]
        E["entries — 커밋값<br/>[10, 6.6, 0, 0]"]
        I["ndFilterWheelIDs — identity<br/>[3, 1, 4, 5]"]
        L["liveNDSteps — 드래그 중 오버레이<br/>{ 2 : 4.0 }"]
    end

    subgraph VM["ExposureCalculatorViewModel  (에포크 조율)"]
        A["activeNDWheelIDs {4}<br/>터치 중인 휠 id"]
        P["pendingNDWheelCommits<br/>[(id 4, 4.0)] 정착 순서"]
        T["cleanup 타이머 4s (A0–A3)"]
    end

    E --> EFF["effectiveNDStep = Σ(live ?? 커밋)<br/>10 + 6.6 + 4.0 + 0 = 20.6"]
    L --> EFF
    E --> LAD["pickerNDSteps(forWheel:)<br/>휠별 사다리 (budget 절단)"]
    E --> VIEW["ForEach가 그릴 배열"]
    I --> VIEW

    EFF --> CALC["ExposureCalculator.calculate(base, 20.6)"]
    CALC --> R1["ND 적용 셔터"]
    CALC --> R2["보정 노출 (상반칙)"]
    EFF --> R3["합계 오버레이 '20.6 스톱'"]

    VM -- "장벽에서 1회 persist" --> DISK[("UserDefaults<br/>슬롯별 스냅샷 ndStack")]
```

- 커밋값(`entries`)과 identity(`ndFilterWheelIDs`)는 항상 같은
  길이의 평행 배열. i번째 휠의 값은 `entries[i]`, 그 휠이
  "누구인지"는 `ndFilterWheelIDs[i]`.
- identity는 화면 애니메이션 전용 — 계산·저장에는 쓰이지 않는다.
- `liveNDSteps`는 손가락이 돌리는 동안만 존재하는 오버레이.

---

## 1. 휠 4개가 화면에 생기는 방법

뷰는 배열을 그대로 그린다. 휠 개수 = `entries.count`.

```mermaid
flowchart TB
    M["entries [10, 6.6, 0, 0]<br/>wheelIDs [3, 1, 4, 5]"]
    M -->|"(값, id) 쌍 = wheelSlots"| FE["ForEach(wheelSlots) — id로 키잉"]
    FE --> W1["NDWheelView<br/>id 3 · 값 10"]
    FE --> W2["NDWheelView<br/>id 1 · 값 6.6"]
    FE --> W3["NDWheelView<br/>id 4 · 값 0"]
    FE --> W4["NDWheelView<br/>id 5 · 값 0"]
    FE -.->|canAdd일 때만| ADD["+ Add 컨트롤"]

    subgraph WHEEL["NDWheelView 내부 구조"]
        PK["SwiftUI Picker(.wheel)<br/>└ UIKit UIPickerView"]
        BD["선택 Binding (get/set)"]
        OB["WheelPickerContinuousObserver<br/>드래그 감지 · 라이브 방출"]
        PK --- BD
        PK --- OB
    end
    W3 -.구조.-> WHEEL
```

**Add(+) 탭:**

```mermaid
flowchart LR
    TAP["+ 탭"] --> C1{"C1: 새 휠 사다리에<br/>0보다 큰 값이 있는가?"}
    C1 -- 아니오 --> NOP["무시 (컨트롤도 숨김)"]
    C1 -- 예 --> GROW["entries [10,6.6,0] → [10,6.6,0,0]<br/>wheelIDs [3,1,4] → [3,1,4,6] 새 id"]
    GROW --> DRAW["ForEach가 id 6 휠을 새로 그림<br/>기존 휠은 같은 뷰, 폭만 축소"]
    DRAW --> AFTER["persist 1회 +<br/>cleanup 타이머 무장 (0휠 4초 규칙)"]
```

**휠별 사다리** — 각 휠의 선택지는 "30 − 나머지 휠 합"까지 위에서
절단된다. 커밋값에서만 파생되므로 다른 휠이 드래그 중이어도
변하지 않는다.

```text
entries [10, 6.6, 0, 0]에서 3번째 휠(index 2)의 사다리:
budget = 30 − (10 + 6.6 + 0) = 13.4
사다리 = [0, 1, 2, …, 13, 6.6*, 7.6*]   (* 13.4 이하 프리셋)
```

---

## 2. 값을 돌리는 동안 — 실시간 계산과 표시

3번째 휠(id 4)을 돌려 4를 지나는 순간:

```mermaid
sequenceDiagram
    actor F as 손가락
    participant U as UIPickerView
    participant O as Observer
    participant VM as ViewModel
    participant M as CalculatorModel
    participant R as 결과 뷰들

    F->>U: pan .began
    U->>O: (hook된 recognizer)
    O->>VM: beginNDWheelInteraction(id 4)
    Note over VM: activeNDWheelIDs = {4}<br/>에포크 열림 · cleanup 취소

    loop 행이 바뀔 때마다 (30fps 폴링)
        O->>VM: updateLiveNDFilterStep(4.0, forWheel 2)
        Note over VM: 게이트 — 휠 4가 활성일 때만 통과
        VM->>M: liveNDSteps[2] = 4.0
        M-->>R: effectiveNDStep = 10+6.6+4.0+0 = 20.6
        Note over R: ND 적용 셔터 · 합계 오버레이 ·<br/>보정 노출 즉시 재계산
    end
```

- 커밋 스택은 이 동안 **한 글자도 안 변한다.** 라이브 오버레이만
  손가락을 따라 움직인다.
- 여러 휠이 동시에 돌면 `liveNDSteps`에 항목이 여러 개 생기고
  합산은 휠별로 (live ?? 커밋).

---

## 3. 손을 뗀 뒤 — 커밋, 그리고 순서가 바뀌는 방법

```mermaid
sequenceDiagram
    participant U as UIPickerView
    participant B as SwiftUI Binding
    participant G as 화면 게이트
    participant VM as ViewModel
    participant M as CalculatorModel

    U->>B: didSelectRow (감속 종료)
    B->>G: set(4.0, at 2)
    Note over G: 이 휠에 활성 상호작용이<br/>있는가? (또는 VoiceOver)
    G->>VM: setNDFilterStep(4.0, at 2)
    Note over VM: pending += (id 4, 4.0)<br/>active에서 4 제거

    alt 다른 휠이 아직 돌고 있음
        Note over VM: 여기서 정지. 커밋 스택 불변.<br/>화면은 pending 값으로 표시.
    else 전원 정착 — 장벽(세트 커밋)
        VM->>M: pending을 정착 순서로 적용<br/>(30 초과는 도메인이 거부 → 그 휠 복귀)
        VM->>M: sortedForCommit() 정렬 1회
        VM->>M: liveNDSteps 비움
        VM->>VM: persist 1회 · cleanup 재검사 1회
    end
```

**정렬이 "이동 애니메이션"이 되는 원리** — 값과 identity가 같은
permutation으로 함께 움직인다. 4번째 휠에 13을 커밋한 예:

```text
정렬 전   entries  [10, 6.6, 0, 13]      정렬 후  [13, 10, 6.6, 0]
          wheelIDs [ 3,  1,  4,  5]               [ 5,  3,  1,  4]
                                └── id 5(값 13)가 맨 앞으로
```

```mermaid
flowchart LR
    subgraph BEFORE["정렬 전 (위치 1→4)"]
        b1["id 3<br/>10"] ~~~ b2["id 1<br/>6.6"] ~~~ b3["id 4<br/>0"] ~~~ b4["id 5<br/>13"]
    end
    subgraph AFTER["정렬 후"]
        a1["id 5<br/>13"] ~~~ a2["id 3<br/>10"] ~~~ a3["id 1<br/>6.6"] ~~~ a4["id 4<br/>0"]
    end
    b4 -->|"4번째 → 1번째"| a1
    b1 -->|"1 → 2"| a2
    b2 -->|"2 → 3"| a3
    b3 -->|"3 → 4"| a4
```

ForEach가 id로 키잉되어 있고 커밋이 `withAnimation(0.35s)` 안에서
실행되므로, SwiftUI가 각 id의 프레임 이동을 애니메이션한다 =
휠들이 미끄러져 교차한다. 정착 후 사다리(budget)가 새 커밋값
기준으로 재계산되고, 화면·합계·결과·커밋 스택이 전부 일치한다.

---

## 4. 저장과 복원

```mermaid
flowchart TB
    subgraph SAVE["저장 (장벽의 persist 단계)"]
        E2["entries [13, 10, 6.6, 0]"]
        E2 --> RS["CameraSlotCalculatorSnapshot<br/>.ndFilterSteps (런타임, 슬롯별)"]
        RS --> PS["PersistentCameraSlotCalculatorSnapshot"]
        PS --> ND["ndStack: 휠당 1항목<br/>whole / thirds / exact 중 정확히 1필드"]
        PS --> LEG["레거시 스칼라 ndStop = 최대값 휠 13<br/>(구버전 호환)"]
        ND --> UD[("UserDefaults<br/>슬롯 4개 각각")]
        LEG --> UD
    end
```

```mermaid
flowchart TB
    subgraph RESTORE["복원 (재실행 / 슬롯 전환)"]
        UD2[("UserDefaults")] --> DEC["ndStack 디코드<br/>실패 시 이 필드만 격리 (스냅샷 유지)"]
        DEC --> VAL{"검증: 1–4개?<br/>전부 0 이상 유한?<br/>합 ≤ 30?"}
        VAL -- 불합격 --> FB["레거시 스칼라 →<br/>그것도 없으면 [0] 1휠"]
        VAL -- 합격 --> RES["restoreNDFilterSteps([13,10,6.6,0])<br/>entries 복원 + wheelIDs 새로 발급"]
        FB --> DRAW2["ForEach가 휠들을 그림"]
        RES --> DRAW2
        DRAW2 --> CLEAN["cleanup 재검사<br/>(복원된 0휠도 4초 규칙)"]
    end
```

- identity와 라이브/pending 상태는 **저장하지 않는다** — 디스크에는
  커밋값 배열만 간다.
- 저장 시점: 장벽, Add/삭제, 슬롯 전환 등 커밋 상태가 실제로 바뀐
  직후 1회.

---

## 5. 삭제 흐름 (개수가 줄어드는 두 경로)

```mermaid
flowchart LR
    subgraph AUTO["자동 (A0–A3)"]
        Z["정리 가능한 0휠 존재"] --> IDLE["4초 무접촉"]
        IDLE --> RM["0휠 전부 제거<br/>(전부 0이면 1개 유지)"]
        RM --> ANIM["fade + 폭 축소 애니메이션"] --> PST["persist"]
    end
    subgraph MANUAL["수동 (과회전)"]
        Z2["0에 멈춘 휠을<br/>아래로 1행 이상 당김"] --> REL["릴리스"]
        REL --> ONE["당긴 그 휠(identity)만 즉시 제거"] --> PST2["persist"]
    end
```

수동 삭제는 다른 휠이 돌고 있는 동안엔 무시된다 (자동 정리에
맡김).

---

## 6. 파일 맵

| 역할 | 파일 |
|---|---|
| 스택 도메인 (합/정렬/불변식) | `PTimerCore/Exposure/NDFilterStack.swift` |
| 커밋값·identity·라이브 맵·사다리 | `PTimerKit/Calculator/CalculatorModel.swift` |
| 에포크·장벽·cleanup·persist 조율 | `PTimerKit/Calculator/ExposureCalculatorViewModel.swift` |
| 휠 행 조립·바인딩·Add·합계 오버레이 | `PTimer/ExposureCalculator/ExposureWorkspaceMainLayoutStyle.swift` |
| 화면 배선·커밋 게이트 | `PTimer/ExposureCalculator/ExposureCalculatorScreen.swift` |
| 드래그 감지·라이브 방출·정착 감지 | `PTimer/ExposureCalculator/WheelPickerContinuousObserver.swift` |
| 슬롯 스냅샷 직렬화 | `PTimerKit/Persistence/PersistentCameraSlotSession.swift` 외 |
