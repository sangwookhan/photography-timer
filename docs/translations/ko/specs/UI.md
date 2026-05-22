# UI Spec

> **Locale mirror.** 본 파일은 `docs/specs/UI.md`의 한국어 mirror. 표현 분쟁이 있을 때 영문판을 canonical로 본다.

**도메인**: 사용자 대면 표면 — calculator 화면, bottom-sheet timer workspace, film picker 시트, reciprocity 상세 시트, 잠금 화면 위젯.

본 문서는 사용자가 보는 것 + 상호작용에 대한 행동 계약. display contract (무엇이 렌더되는가) + interaction contract (사용자 입력 시 무엇이 일어나는가)를 기술. 플랫폼 default 인 visual styling 파라미터는 pin 되지 않음 — 숫자는 의도가 특정 값을 요구할 때만 pin.

---

## 1. Global presentation

### 1.1 Orientation

앱은 **portrait only**. Orientation은 앱 진입점에서 강제되며, view는 이 제약을 opt-out 하지 않는다.

### 1.2 Single primary screen

계산과 timer 실행을 모두 담는 **하나의 primary 화면**이 있다. 사용자는 화면 전환 없이 노출을 조정하고 timer를 시작. Calculator와 timer는 분리된 workflow가 아니다. (Wiki 3866625)

### 1.3 Layout density tier

화면은 구조 변경 없이 vertical room에 적응. 세 density tier 지원:

- **Regular** — 표준 spacing, 폰트 크기, padding.
- **Compact** — 짧은 viewport에서 spacing 감소; 구조 변경 없음.
- **Dense** — 가장 작은 viewport에서 calculator footprint가 안정 유지되도록 minimum padding.

Tier 선택은 가용 높이 함수; 구조 (섹션, picker 쌍, 결과, dock)는 tier 가로질러 collapse 또는 rearrange 되지 않는다.

---

## 2. Calculator section

### 2.1 Header / mode strip

변수 섹션 위에 현재 workflow 모드를 전달하는 film row가 위치:

- **필름 미선택 (digital workflow)** — empty-state 라벨 + "Choose Film" affordance를 표시.
- **필름 선택 (film workflow)** — 선택된 필름의 canonical 이름 + 브랜드 + "Change" affordance + "Clear" affordance를 표시.

필름 선택 시, row는 또한 활성 reciprocity profile의 권위와 매칭하는 **명시적 profile-authority 부제**를 포함: official-authority profile에 **"Official guidance"**, unofficial-authority profile에 **"Unofficial practical"**. 라벨은 두 경우 모두 *항상 존재* — "라벨 없음 = official" 의 암묵 해석은 없다.

Launch dataset ([DomainSchema Spec](DomainSchema.md) §13)은 `authority = "official"` profile만 포함 — 따라서 런타임 선택은 실제로 항상 두 라벨 중 하나. `userDefined` 또는 `unknown` 권위 profile (launch dataset에 없음, 둘 다 post-launch 사용자 정의 / 비-launch 흐름용으로 예약)은 부제를 표시하지 않는다 — 부제 부재는 row가 아직 presentation contract가 할당되지 않은 권위를 렌더 중임을 의미. 위의 "always present" 규칙은 그 경우들에 확장되지 않는다.

"Clear" affordance는 Base Shutter 또는 ND를 변경하지 않으면서 필름 선택을 제거. Empty state 에는 나타나지 않는다.

### 2.1.1 카메라 슬롯 페이저 + 이름 변경

Calculator 화면은 네 개의 독립적인 카메라 슬롯 (`Camera 1` ~ `Camera 4`) 사이를 페이지로 전환. 활성 슬롯의 이름이 화면 메인 타이틀로 렌더링; calculator 아래 페이지 indicator는 bounded set 내 활성 슬롯 위치를 표시. 각 슬롯은 자기 calculator 입력, 필름 선택, scale, reciprocity 결과를 보유 — 슬롯 전환은 전환되지 않는 슬롯들을 절대 reset 하지 않는다.

슬롯 타이틀은 이름 변경 affordance도 겸한다. 활성 페이지에서 타이틀을 tap 하면 사진가가 다음을 할 수 있는 sheet가 열림:

- custom 이름 입력 (예: `Hasselblad 500CM`, `Mamiya 7`); 빈 값 또는 whitespace-only 입력은 reset 요청으로 처리되어 canonical `Camera N` 라벨로 대체.
- 명시적 "Reset to Camera N" 액션을 통해 이전에 rename 된 슬롯을 canonical default로 reset.

표시 이름은 선택 필름 / profile과 별개의 축. 이름 변경 영역은 calculator 입력, 필름 선택, scale, reciprocity 결과, 또는 슬롯의 안정된 식별자를 변경하지 않는다. 이미 시작된 timer는 시작 시점에 captured된 슬롯 라벨을 유지 — 이후 rename이 실행 중이거나 완료된 timer의 식별을 retroactively 다시 쓰지 않는다. Custom 이름은 카메라 슬롯 세션 snapshot을 통해 앱 재실행 후에도 영속 ([DomainSchema Spec](DomainSchema.md) §7.4 참조).

### 2.2 Variable section

두 **wheel picker**가 한 row에 side-by-side:

- **Base Shutter picker** — 1/3-stop 조밀화 ladder (1/8000부터 30 s까지 55개 entry, [Calculator Spec](Calculator.md) §2.3)에 카메라 표기 라벨. 1초 미만 행은 reciprocal 분수 (`1/N`, slow end `1/3, 1/2.5, 1/2, 1/1.6, 1/1.3` 포함)로 렌더링하고 `s` suffix 미포함; 1초 이상 행은 카메라 관습대로 정수 또는 `N.Ns`.
- **ND picker** — **`[0, 30]` 닫힌 구간의 정수 stop**. One-third-stop은 Base Shutter ladder 에만 적용 ([Calculator Spec](Calculator.md) §1.4); ND picker는 실제 fixed ND 필터가 whole-stop 강도로 판매되기 때문에 whole-stop 유지. `7 1/3` 또는 `7 2/3` 같은 fractional 행은 출시 ND option list에 **포함되지 않으며**, view 레이어에서 필터링하지 않는다 — option set 자체에 존재하지 않는다.

사용자 노출 scale selector는 현 release에서 의도적으로 노출하지 않음; calculator는 one-third-stop shutter scale 에서만 동작. 미래 Settings preference (Full / 1/2 / 1/3 stop, 그리고 미래의 fractional-ND opt-in)는 유보 ([Calculator Spec](Calculator.md) §1.4 참조) — 출시 시 calculator 화면이 아닌 Settings에 위치.

Picker 쌍이이 변수들의 유일한 입력 경로 — free-text 입력 없음. wheel 값 tap 시 calculator 즉시 update; 스크롤 중 live preview 지원. Aperture + ISO 컨트롤은 유보 — 현 release에 나타나지 않는다.

### 2.3 Result section

결과 섹션은 계산된 노출을 표시:

- **Digital workflow** — [Calculator Spec](Calculator.md) §2.4의 관습적 표기 규칙으로 Output Shutter를 보여주는 primary 줄 + 의미 있을 때 정확한 시간을 (아래 시간-표시 규칙으로 포맷) 보여주는 secondary 줄.
- **Film workflow** — 고정 두 줄 위계. 첫 줄: **Adjusted Shutter** (ND 적용, reciprocity 전). 둘째 줄: **Corrected Exposure**. 두 줄 레이아웃은 모든 reciprocity 결과 카테고리 가로질러 안정 유지.

Corrected Exposure 행은 film workflow에서 항상 표시. 내용은 reciprocity 결과 카테고리로 결정:

- **Quantified** (`No correction` 또는 `Formula-derived`, [Calculator Spec](Calculator.md) §3.5) — Adjusted Shutter와 같은 시간-표시 규칙으로 보정 시간 + status 배지.
- **경고 동반 quantified** (formula이 supported boundary 너머에서 numeric continuation 산출 — converted formula profile은 `Beyond source range`, 그 외는 `Outside guidance` surface) — 숫자 값과 warning-tone 배지로 사용자가 outside manufacturer guidance prediction을 인식.
- **비-quantified** (limited-guidance 결과는 `No quantified prediction`, formula continuation 없는 unsupported는 `No corrected value`) — 숫자 대신 차분한 설명 텍스트. UI는 근거 없는 숫자 값을 만들어내지 않는다.

**Reciprocity state 배지**가 row와 함께 위치 — 결과 카테고리를 한눈에 전달. Badge 문구는 위 vocabulary와 일치해야 한다; legacy table 시대 문구 (`Exact`, `Estimated`, `Interpolated`, `Extrapolated`, `Advisory`)는 launch preset reciprocity presentation에 등장하지 않는다.

### 2.4 시간 표시 규칙

시간 값은 단일 위계를 따른다. **day-scale** 경계에서 두 표시 모드 적용:

| 범위 | 형식 |
|---|---|
| `< 1 s` | 관습적일 때 reciprocal 표기 (예: `1/30`); 아니면 십진 |
| `1 s ≤ t < 60 s` | 적응 정밀도 초; round 값에 정수, 유용할 때 십진 |
| `60 s ≤ t < 1 h` | `MM:SS` |
| `1 h ≤ t < 1 d` | `HH:MM:SS` |
| `≥ 1 d` (precise 모드) | days + 작은 단위 나머지, 예: `388d 08:40:32` |
| `≥ 1 d` (coarse 모드) | thousands separator가 있는 plain day count, 예: `388d`, `13,599d`, `83,602d` |

**모드 선택**: 결과 섹션의 **primary corrected exposure**는 1 d 이상에서 **coarse 모드** 사용 — 사용자 대면 top-level 값이 sub-day 노이즈에 압도되지 않도록. **상세 표면 + timer view**는 1 d 이상에서 **precise 모드** — secondary reader가 정확한 남은시간 검증 가능하도록. Sub-day 범위는 영향 없음.

Coarse 모드의 thousands grouping은 grouping size 3의 콤마 separator 사용 — 기기 locale에 무관하게 결정적으로 적용.

**계산된** 값 (precise)과 **표기** 값 (관습적)은 내부적으로 별개로 유지된다. 결과 섹션은 표기를 표시; 하류 timer 로직은 계산값 사용. ([Calculator Spec](Calculator.md) §2.4 참조.)

### 2.5 Start Timer affordance

**Start Timer** 버튼은 시스템이 양수 + 유한한 duration의 quantified 결과를 가질 때만 활성. Film workflow에서 affordance는 **Corrected Exposure**에 binding; corrected가 비-quantified 일 때 affordance는 안내 hint와 함께 비활성화 (숨겨지지 않음).

Start Timer tap 시 현재 계산 snapshot으로 새 timer 생성 + dock에 추가. 화면 전환 없음 — dock가 새 항목을 단순 획득.

### 2.6 Reciprocity 상세 표면

Secondary affordance가 선택된 필름의 reference 데이터를 보여주는 **Reciprocity Details 시트**를 연다: 활성 profile, 공식 표현과 제조사 source-evidence row, 그래프 visualization, source 목록. 상세 시트는:

- 차분한 secondary 시각 weight 사용 (loud 아님);
- 공식을 math-style typography로 렌더;
- selector + current-result visual을 main calculator보다 quieter 유지.

**섹션 순서**: 시트는 다음 순서로 섹션을 제시 — 사용자가 결과 graph에 의존하기 *전* 활성 profile basis를 검증할 수 있도록:

1. **Profile** — 활성 profile이름 + *모든* profile에 대해 표시되는 **Authority row** (Official / Unofficial / 등) (모호한 것뿐만 아님).
2. **Reference 데이터** — 활성 공식 표현 + 제조사 source-evidence row ("Source reference" / "Guidance boundary" 하위 섹션), 또는 limited-guidance profile의 no-correction threshold + limited-guidance directive.
3. **Graph** — 계산 곡선과 source-evidence marker.
4. **Sources** — provenance (publisher, citation, sourceVersion).

**시트 높이**: 시트는 profile 모양 (official quantified formula, official limited guidance, unofficial practical formula)에 무관하게 안정된 초기 높이로 열림. 초기 detent는 콘텐츠로 변하지 않는다.

**Graph 축**: 공식 graph는 현재 입력 측광 노출에 무관하게 **canonical 120 s 상한**까지 확장 — reference 곡선이 입력 가로질러 시각적으로 안정 유지되도록.

### 2.7 Target Shutter 행

Target Shutter 행 ([Calculator Spec](Calculator.md) §3.6 참조)은 메인 촬영 calculator의 optional compact 영역. Calculator의 primary 결과 hierarchy를 대체하지 않는다 — Adjusted Shutter, Reciprocity 상태, Corrected Exposure가 film workflow에서 사진가의 primary 표시 위치를 유지하며, digital workflow에서는 Output Shutter가 primary 표시로 유지.

**행 상태.** 행은 두 상태로 표시:

- **Inactive** — 확정된 target이 없음을 알리는 compact 상태 행. 행을 탭하면 input 시트가 열린다.
- **Active** — target duration, 활성 비교 값과의 stop 차이, 그리고 target용 timer start affordance를 제시하는 compact 행. 비교 기준은 행에 다시 표시되지 않는다 — workflow에 의해 결정 ([Calculator Spec](Calculator.md) §3.6).

메인 행은 destructive `Clear` affordance 또는 enable/disable switch를 표시하지 않는다. 제거와 disabling은 input 시트가 소유하며, 메인 영역은 상태와 액션 중심으로 유지한다.

**Input 시트.** Input 시트는 draft 편집 화면. Draft 변경 (enable, disable, 값 선택)은 사용자가 Confirm하기 전까지 확정된 target에 영향을 주지 않는다.

- **Confirm** — draft를 확정 (활성화된 양수 값은 target 설정; 비활성화된 draft는 target 제거).
- **Cancel** — draft 폐기.
- **Sheet dismissal** (drag-to-dismiss, tap-outside, 또는 `Confirm` 이외의 모든 종료) — Cancel과 동일하게 동작.

시트는 draft target의 enabled 여부를 제어하는 native switch를 제시; switch 비활성화는 확정된 target을 즉시 제거하지 않는다. duration 입력은 두 가지 보완 입력 방식을 제공 — **Quick** (preset 시간) + **Fine Tune** (h/m/s 입력) — 사진가가 흔한 값을 빠르게 고르거나 custom 값을 세밀하게 맞출 수 있도록. 두 입력 방식은 단일 draft target을 공유; 둘 사이 전환은 다른 쪽에서 한 작업을 파괴하지 않는다.

---

## 3. Timer workspace (bottom sheet)

Dock + 전체 timer 목록은 같은 런타임 source의 projection ([Timer Spec](Timer.md) §6). Workspace는 두 detent를 가진 **bottom sheet**.

### 3.1 Detent

- **Compact** — calculator 화면 하단에 anchor 된 glanceable horizontal dock. Calculator가 primary 표시로 유지.
- **Large** — 화면 대부분을 cover 하는 expanded sheet, 전체 timer 목록 제시.

**Medium detent는 존재하지 않음**; 모델은 엄격히 두 상태.

### 3.2 Drag threshold

사용자 drag가 detent 사이 전환:

- compact에서 약 92 pt up-drag → large로 expansion.
- large에서 약 64 pt down-drag → compact로 collapse.

Threshold는 비대칭이다: 확장이 collapse보다 쉬워서 우발적인 위 swipe에 work view를 잃지 않고, 의도된 아래 swipe 에서만 collapse.

### 3.3 Compact dock contract

Compact detent에서 dock:

- 각 running, paused, completed timer를 horizontal scroll 목록의 **96 × 96 pt** 카드로 표시;
- 화면에 맞는 것보다 timer가 더 많으면 끝에 **86 × 96 pt overflow 카드** 포함;
- 약 22 pt 코너 반경 + 약 10 pt horizontal spacing 사용;
- horizontal만 scroll — full-page scrolling은 허용 안 됨 — 위쪽 calculator 섹션은 pin 유지. (Wiki 8847362)

각 compact 카드는 표시: primary 남은시간 줄 (지배 신호), status 아이콘, 총 duration, **multi-layered 진행 표시** (§3.5 참조). destructive action (delete, clear)은 표시 **안 함**. 카드 tap 시 상세 열기 / expanded workspace에서 포커스; long-press, swipe, 유사 제스처는 명세 안 됨.

Identity cue (예: 색조 또는 배지)는 lower metadata 영역에 위치; 남은시간이 primary 시각 신호 유지.

### 3.4 Expanded (large) workspace contract

Large detent에서 workspace는 두 섹션으로 그룹화된 전체 timer 목록 제시:

- **Active** — 생성 LIFO 순서의 running + paused timer. ([Timer Spec](Timer.md) §6)
- **Recently Completed** — 완료 시간 desc 순서의 completed timer, active 그룹 뒤에 표시.

각 row는 표시: 제목 (또는 대체 identity 텍스트), state, 남은 + 총 시간을 trailing alignment의 두 줄 위계로, 그리고 state에 따른 inline action affordance (pause, resume, remove).

사용자가 compact 카드 또는 overflow 카드를 tap 하면 workspace가 expand + 그 timer가 포커스 — 절제된 highlight와 함께 view로 scroll. 포커싱은 런타임 state를 mutate 하지 않는다. Overflow tap은 첫 숨김 timer에 포커스.

### 3.5 Compact 진행 표시

각 compact 카드는 multiple 시간 스케일에 timer의 footprint를 전달하는 **3-layer 진행 표시** 포함:

- **Bottom layer** — 60-second cycle (sub-minute 입자도).
- **Middle layer** — 60-minute cycle (sub-hour 입자도).
- **Top layer** — 24-hour frame 안에 매핑된 원본 timer duration.

가시 layer는 총 duration으로 gate: 짧은 timer는 bottom layer만 표시; 긴 timer는 점진적으로 middle + top 노출. Bar 레벨 애니메이션은 금지 — active running에 대해 status 아이콘만 pulse 가능.

### 3.6 Completed 표시

Completed timer는 compact + expanded 표면에서 일관되게 표시. 카드 라벨은 둘 다 **"Done"**. 원본 duration + 완료 timing이 secondary metadata로 가시 유지.

---

## 4. Film picker 시트

Film 선택은 in-screen 드롭다운 또는 inline 목록이 아닌 **dedicated modal 시트**를 연다.

### 4.1 Display contract

각 row는 flexible leading 영역에 필름의 canonical 이름 + 고정 trailing 컬럼에 compact ISO-speed capsule chip 표시. Checkmark slot이 trailing edge에 예약 — 현재 선택된 필름 여부와 무관 — selection 변경 시 row 위치가 절대 shift 하지 않도록.

시트의 affordance는 selection state에 의존:

- Empty state ("Choose Film") — 시트 헤더 라벨이 "Choose Film" wording.
- Selected state — 시트 헤더 라벨이 "Change" wording.

**Cancel** 액션은 selection 변경 없이 시트 종료. Row tap은 **즉시 selection 적용 + 시트 dismiss** — confirm 단계 없음.

시트는 in-list edit, sort, filter affordance를 포함하지 않음 — 유보. Launch dataset은 scroll로 충분할 만큼 작음. (Launch dataset scope는 [DomainSchema Spec](DomainSchema.md) §13 참조.)

### 4.2 Clear

"Clear" affordance는 calculator 화면의 헤더 / mode strip에 위치 — picker 시트가 아님. Clearing은 별도 작업.

---

## 5. 잠금 화면 위젯

잠금 화면 위젯은 한 대표 실행 중 timer의 **expected 완료 시간**을 표시. ([Timer Spec](Timer.md) §5)

- 위젯 refresh cadence는 약 1 s; 표시 시간은 각 refresh 마다 update.
- 실행 중 timer가 없을 때 위젯은 stale 데이터 대신 "no active timer" 표시.
- 위젯 표면은 Live Activity 인스턴스 — 런타임이 lifecycle (생성, update, end)을 driving. 위젯은 읽기 전용 — 위젯 사용자 입력은 out of scope.

---

## 6. Forbidden patterns

UI는 다음을 **하지 않는다**:

1. Full-page scrolling 허용. Calculator 섹션은 pin; dock + expanded workspace만 scroll.
2. Compact 카드에 destructive action (delete, clear, stop) 표시. Destructive action은 expanded card 또는 상세 표면에 위치.
3. View 컴포넌트 안에서 timer 상태 유지. View는 projection — 런타임이 source. ([Timer Spec](Timer.md) §7)
4. Reciprocity 결과가 비-quantified 일 때 숫자 Corrected Exposure를 근거 없이 만들어내기. 대신 설명 텍스트 표시. ([Calculator Spec](Calculator.md) §6 참조.)
5. 런타임과 독립적으로 남은시간 re-derive.
6. View-builder 코드 경로 안에서 timer mutation 로직 (start, pause, resume, complete) 실행.
7. Bar 레벨에서 진행 bar 애니메이션. status 아이콘만 애니메이션 가능.
8. View layer 안에서 timer reorder. 정렬은 런타임이 결정 ([Timer Spec](Timer.md) §6).
9. In-screen에서 film selection 드롭다운 열기. 선택은 항상 dedicated 시트로 열기.
10. 메인 Target Shutter 행에 Clear 또는 enable/disable switch 배치 (§2.7). 두 affordance는 input 시트 안에만 존재.
11. Target Shutter 시트 dismissal (drag-to-dismiss, tap-outside)을 확정으로 처리. `Confirm` 만이 확정된 Target Shutter를 변경한다 (§2.7).

---

## 7. Drift + 미해결 질문

- **Wheel picker snap 동작.** Wheel picker 모델은 live preview와 함께 snap-to-grid를 시사 but 정확한 상호작용 (swipe-momentum 멈춤 지점, tap-to-set vs tap-to-cycle)은 spec에 pin 안 됨.
- **Film picker sort / search.** 현 launch dataset은 작아서 ([DomainSchema Spec](DomainSchema.md) §13 참조) flat scrollable 목록으로 충분. Dataset 성장 시 sort + search 필요; ordering 정책 결정 안 됨.
- **애니메이션 feel.** Detent 전환 + 카드 애니메이션은 플랫폼 default spring 파라미터 사용; 사람-읽기 feel 진술 기록 없음. Feel이 중요하면 numeric stiffness/damping에 pin 하지 말고 verbally ("부드럽게, ~300 ms, no overshoot") 명세 권고.
- **Reciprocity 상세 표면 깊이.** Graph 컴포넌트, 축 범위, labeling 규칙은 부분 명세; 축, 단위, edge case에 대한 사람-읽기 spec은 불완전.
- **Empty-state copy.** 비-quantified / unsupported 보정 노출의 차분한 안내 텍스트는 코드에서 lock 되지만 정확한 string은 본 spec에 pin 안 됨; 로컬라이제이션 도착 시 재방문.
- **선택 모델.** 다중 선택 없음, batch action 표면 없음. Wiki 9601025가 의도적으로 defer; UI도 그것에 대해 아무것도 노출 안 함.
- **Accessibility 라벨.** Film 모드 timer action에 대한 row-specific 접근성 라벨 존재 but 앱 가로지른 완전한 accessibility spec은 없음.
- **잠금 화면 위젯 상세.** §5 contract 외 위젯의 typography, color, layout은 플랫폼 관습; 상세 pin 안 됨.

---

## 8. Sources of intent (참고)

본 섹션은 *참고 자료* — 규범 아님.

**Wiki (Confluence page id)**
- 3866625 — 화면 흐름 초안 (계산 + 실행 단일 화면)
- 3899394 — 계산 화면 와이어프레임 초안 (화면 구조)
- 3932162 — UI 인터랙션 + 컴포넌트 구조 초안 (컴포넌트 위계, fixed/derived 토글, calculator vs timer 분리)
- 8847362 — Floating Timer Dock UI Design (dock 상태, 스크롤 독립성, destructive action)
- 8880129 — Floating Timer Dock Architecture (one-source-of-truth projection)
- 9568257 — Bottom Sheet UI 기획 초안 (compact / expanded UX)
- 9601025 — Bottom Sheet UI Architecture 설계 초안 (layer 분리)
- 16482307 — Film Selection and Reciprocity Calculator UI (workflow 방향, 용어)

