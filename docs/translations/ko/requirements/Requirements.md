# PTimer — 요구사항

> **Locale mirror.** 본 파일은 `docs/requirements/Requirements.md` 의 한국어 mirror. 표현 분쟁이 있을 때 영문판이 canonical.

**문서 종류**: 사용자 시나리오 기반 요구사항 문서.
**대상 독자**: 앱이 *무엇을* 해야 하는지 알아야 하는 제품 / 엔지니어링 / 향후 기여자.
**영향 방향**: 요구사항 → 행동 계약 → 코드, **단방향**. 요구사항 문서는 제품 의도에 대해 normative 하다. 하류 문서들은 각 요구사항이 어떻게 명세되고, 구조화되고, 검증되는지를 구체화한다. 하류 문서에 대한 참조는 탐색(navigational) 목적이며 요구사항이 그 문서들에 의존하게 만들지 않는다. 요구사항이 *"시스템은 X를 한다"* 라고 말할 때, *무엇을* 하고 *왜* 하는지는 여기에서 결정되며, *어떻게* 하는지는 하류에서 결정된다.
**문구 규칙**: 모든 요구사항은 *사용자에게 보이는 필요점* 또는 *무결성 불변식(integrity invariant)* 을 기술한다. 구현 specifics(픽셀 사이즈, 갱신 주기, 영속화 키, lint 규칙 ID, baseline 파일명, property wrapper 선택 등)는 하류 문서에 속하며 본 문서에 등장하지 않는다.

**문서 경계**: 본 문서는 앱이 *무엇을* 해야 하는지 정의한다. 시스템이 *어떻게* 구조화되는지(layering, ownership, 모듈 boundary)는 `docs/architecture/Architecture.md`. 각 요구사항을 어떤 *행동 계약* 이 realize 하는지는 `docs/specs/`. 변경이 *어떻게* 검증되는지는 `docs/verification/Strategy.md`.

---

## 1. 페르소나

### 1.1 장노출 사진가 (primary)

ND 필터를 사용해 장노출을 촬영하는 사진가. 삼각대 위에서 작업하며 옥외 환경이 잦고, 한 컷의 측광 후 수십 초 ~ 수 분 동안 셔터를 열어둔다. 필름 카메라 / 디지털 카메라 / 한 outing 내에 두 가지를 번갈아 사용 가능. 촬영 중에는 iPhone 을 portrait grip 으로 잡고 있으며, 일단 시퀀스를 시작하면 폰을 잘 내려놓지 않는다.

### 1.2 필름 reciprocity 보정이 필요한 사진가 (specialization)

위와 동일한 사진가가, reciprocity 거동이 측광값과 어긋나는 필름 stock 을 사용할 때. 단순 "stops" 계산이 아닌, 활성 필름의 출판된 reciprocity 데이터에 대한 *보정값* 이 필요하다. 필름마다 보정 곡선이 다르고, 어떤 것은 제조사 임계치만 발표, 어떤 것은 표 형태, 어떤 것은 advisory(권고) 만 발표한다.

### 1.3 다중 카메라 사진가 (specialization)

같은 장면을 두 대 이상 카메라로 동시에 촬영하는 사진가. 예: reciprocity 보정이 필요한 아날로그 중형 + 보정 불필요한 디지털 바디를 병행. 어떤 timer 가 *어느 컷* 에 속하는지 *한눈에* 식별해야 함. 라벨 없는 큐를 외울 수는 없다.

본 제품은 캐주얼 스냅샷 사용자, 스튜디오 스트로브 촬영자, cinematography 사용 사례를 위해 설계되지 *않았다*. 이들은 측광 루프와 timer 필요성이 매우 다르다.

---

## 2. 핵심 시나리오

각 시나리오는 사용자 목표, 앱이 지원해야 하는 단계, 그리고 동작이 자명하지 않은 경계 조건을 기술한다.

### 시나리오 1 — ND 필터 출력 셔터 계산 (digital workflow)

**목표.** 사진가가 카메라로 측광한 뒤, ND 필터로 N stop 줄였을 때 필요한 셔터 속도를 알고 싶다.

**단계.**
1. 풀스톱 ladder 에서 base shutter 를 설정.
2. ND stops 를 음이 아닌 정수로 설정.
3. 결과 행에서 출력 셔터를 읽음.
4. (선택) 출력 셔터로부터 timer 를 시작 — 카메라 내부 셔터나 손목시계로 측정하기 어려운 길이일 때.

**경계 조건.**
- Base shutter 는 표준 19개 풀스톱 ladder (1/8000 ~ 30 s) 에서만 입력 가능. 자유 텍스트 입력은 거부.
- ND stop 입력은 0 이상 30 이하 정수. 범위 밖 값은 받지 않음.
- 출력 셔터는 관습적 사진 표기법으로 표시. ladder 와 정렬되지 않은 계산값은 표시용으로 반올림되되, 정확한 값은 하류 timer 가 사용할 수 있도록 보존.
- 30 s 초과 시 출력은 power-of-two ladder (64, 128, 256 …) 로 snap. 표기에 60 s 는 등장하지 않으며, 30 s 다음 단계는 64 s.

### 시나리오 2 — 필름의 보정 노출 계산 (film workflow)

**목표.** 필름 카메라로 측광한 사진가가, 필름의 reciprocity 특성을 보상한 *보정* 노출을 알고 싶다.

**단계.**
1. 필름 picker 시트를 연다 (picker 는 화면 내 드롭다운이 아닌 별도 시트).
2. 출시 카탈로그에서 preset 필름 stock 을 선택.
3. 필름 row 의 권위(authority) 부제로 활성 reciprocity profile 이 **Official guidance** (제조사 출판) 인지 **Unofficial practical** (커뮤니티 도출) 인지 확인. 출시 dataset 에 포함되는 권위들은 라벨이 항상 표시됨.
4. 시나리오 1 과 동일하게 base shutter 와 ND 설정.
5. 결과 섹션이 두 개의 안정된 행을 표시: **Adjusted Shutter** (ND 적용, reciprocity 전) 와 **Corrected Exposure** (reciprocity 적용 후 최종값).
6. (선택) reciprocity 상세 시트를 열어 근거 데이터 — Profile / Formula 또는 Reference / Graph / Sources 섹션 (이 순서, 안정된 초기 detent) — 를 확인.

**경계 조건.**
- film workflow 에서 Corrected Exposure 행은 *항상 표시*. 사용자가 측광값을 움직여 결과가 *quantified*, *advisory-only*, *unsupported* 사이로 바뀌어도 layout 형태는 변하지 않는다.
- *quantified* 보정 노출은 숫자 primary 행 + 신뢰도 배지 표시. 신뢰도 카테고리는 *exact*, *estimated* (출판 표 내부 보간), *extrapolated* (표 외부), *trusted threshold* (제조사 임계치 이하 무보정) 중 하나.
- *advisory-only* 결과는 숫자 대신 차분한 설명 텍스트를 표시. 데이터가 뒷받침하지 않을 때 앱은 결코 숫자를 *fabricate* 하지 않는다.
- *unsupported* 결과는 안내 문구를 표시하고, 보정 행의 Start Timer 버튼은 설명 가능한 accessibility hint 와 함께 비활성화.
- base shutter 의 풀스톱 ladder, ND 범위, snap-to-full-stop 표기 규칙은 시나리오 1 과 동일.

### 시나리오 3 — 장노출 timer 실행

**목표.** 카메라 셔터를 눌러 노출이 시작된 직후, 사진가가 앱에서 timer 를 시작해 셔터가 열려 있는 시간을 측정하고자 한다.

**단계.**
1. 결과 섹션의 row 중 측정하려는 값에 해당하는 Start Timer affordance 를 활성화. film workflow 에서는 두 가지 시작 affordance — Adjusted Shutter 행과 Corrected Exposure 행 — 가 있고, 사용자가 의도에 따라 선택.
2. timer 가 *workspace 표면* 으로 진입. 이 표면은 calculator 와 *함께* 보이도록 유지된다. 사용자는 timer 를 닫거나 시야에서 잃지 않으면서 다음 컷을 위해 ND 를 조정하거나 필름을 바꿀 수 있다. workspace 표면의 정확한 배치 위치는 디자인 결정이며 요구사항이 아니다.
3. workspace 표면은 각 실행 중인 timer 에 대해 다음을 전달: 남은 시간, 여러 시간 스케일에 걸친 *진행감* (30 s timer 와 30 min timer 모두 반응적으로 느껴지도록), 이름과 시간 텍스트와 무관한 식별 단서.
4. 사용자는 workspace 표면을 *훑어보기 좋은(glanceable) 요약 모드* 와 *모든 실행/일시정지/완료 timer 를 함께 보는 확장 모드* 사이에서 전환 가능.
5. timer 의 duration 이 만료되면, 시스템은 사용자가 폰을 보고 있지 않더라도 (카메라 들고 있거나 폰이 주머니에 있거나) 도달하는 완료 신호를 표시하고, 앱 안 timer 카드는 "Done" 상태로 전환.

**경계 조건.**
- 각 timer 는 안정된 식별자를 가짐. 정렬: active 그룹은 가장 최근 시작 순, completed 그룹은 가장 최근 완료 순.
- Timer duration 은 시작 시점에서 *엄격히 양수이고 finite* 가 아니면 거부 — `Inf`, `NaN` 금지.
- 각 timer 는 자동 생성된 이름과 basis-summary 행을 carry — 사용자가 *어느 컷* 에 속한 timer 인지 재구성할 수 있도록. 이름은 시작 source (digital 결과 vs film adjusted vs film corrected) 를 반영하고, 관련 시 필름 stock 이름을 포함.

### 시나리오 4 — Pause / Resume

**목표.** 사진가가 실행 중인 timer 를 일시정지 (구름이 변함, 피사체 이동 등) 후 같은 논리적 지점에서 재개.

**단계.**
1. 실행 중 timer 의 pause affordance 를 탭.
2. timer 가 paused 상태로 진입. 벽시계 시간이 흘러도 paused timer 는 자동 완료되지 않음.
3. resume 탭 — timer 는 pause 시점의 *frozen 남은시간* 에서 계속 진행 (원래 종료시간이 아님).

**경계 조건.**
- 남은시간이 이미 0 에 도달한 pause 는 *zero-remaining paused* 상태로 들어가는 대신 즉시 *completed* 로 short-circuit. 사용자는 "0 s 에서 paused" 라는 timer 를 보지 않는다.
- paused timer 의 가설적 완료 시간은 표시 목적으로 관찰 가능하지만, resume 은 항상 종료시간을 *now + 남은시간* 으로 재계산. 원래 종료시간은 pause 를 가로질러 보존되지 않는다.

### 시나리오 5 — 다중 timer 병렬 실행

**목표.** 두 대 이상 카메라 (또는 한 카메라의 두 대기 노출) 를 운용하는 사진가가 컷별로 timer 를 분리해 둔다.

**단계.**
1. 시나리오 3 을 반복해 두 번째 timer 를 시작. workspace 표면은 추가 timer 를 수용하면서도 위쪽 calculator 를 잃지 않으며, 각 timer 는 텍스트를 읽지 않고도 카드를 한눈에 식별할 수 있는 고유 식별 단서를 carry.
2. 단일 timer 에 focus 해 더 자세히 검사 가능.
3. 다른 timer 가 계속 실행되는 동안 한 timer 만 일시정지 가능.
4. 완료된 timer 는 completed 그룹에 모이고 가장 최근 완료 순.

**경계 조건.**
- timer 의 식별 단서는 *해당 timer 의 lifetime 동안 안정* — 사용자가 재정렬하거나 focus 하거나 active ↔ completed 그룹 사이로 옮겨도 변하지 않는다.
- workspace 표면은 요약 / 확장 전환 사이에 모양이 안정적. 모드 전환 시 이미 보였던 카드의 layout 을 재계산하지 않는다.
- 잠금 화면 표면 (시나리오 6) 은 다중 timer 가 실행 중이어도 한 번에 *한 개* 의 대표 timer 만 표시. 선택 규칙은 시나리오 6 에 있다.

### 시나리오 6 — 잠금 화면 모니터링

**목표.** 사진가가 셔터가 열려 있는 동안 폰을 내려놓거나 (주머니 등) 하고, 기기의 잠금 화면 표면으로 unlock 없이 남은 시간을 흘끗 본다.

**단계.**
1. timer 시작 (시나리오 3).
2. 폰 잠금. 잠금 화면 표면이 *대표* timer 의 이름, duration, 종료시간을 전달.
3. 잠금 화면 표면은 사용자가 unlock 없이도 시간이 흐르는 것을 인지할 정도로 자주 갱신.
4. 모든 timer 가 멈추면 (완료 또는 제거) 잠금 화면 표면이 사라진다.

**경계 조건.**
- 대표는 종료시간이 가장 빠른 active timer. 동률은 결정적으로 해소 — 구현이 동률 처리를 비일관적으로 해 표면이 두 timer 사이를 깜빡이는 일은 없어야 한다.
- 앱 active / background 전환을 가로지르는 연속성: scene-phase 변경 중 *기저 선택이 실제로 바뀌지 않는 한* 표면이 두 대표 사이를 깜빡이지 않는다.
- 잠금 화면 표면은 더 이상 존재하지 않는 timer 를 절대로 표시하지 않는다 — 모든 실행/일시정지 timer 가 멈추면 표면도 종료.

### 시나리오 7 — Timer 가 진행 중인 상태에서 앱 재시작

**목표.** 하나 이상의 timer 가 실행 중이거나 일시정지 중인 상태에서 사진가의 폰이 재시작 (배터리 / 수동 force-quit / OS 업데이트). 다시 열었을 때 timer 들이 그대로 있다.

**단계.**
1. workspace 에 timer 가 실행 중 / 일시정지 중인 상태에서 앱을 force-quit 또는 폰 재시작.
2. 앱을 다시 열기. 이전 실행 중 timer 가 복원 — 실행 중 timer 는 앱이 죽어 있던 동안의 벽시계 진행을 반영, 일시정지 timer 는 그대로.
3. 종료시간이 이미 지난 실행 중 timer 는 completed 로 복원되며 완료 timestamp 는 *원래 종료시간* (복원 시점이 아님).

**경계 조건.**
- 영속화된 timer 상태는 backward-compatible 추가만으로 진화 — 이전 release 가 쓴 snapshot 은 현 release 에서도 정확하게 복원되어야 한다.
- freeze metadata 가 누락되거나 일관성이 없는 영속화된 paused timer 는 손상된 입력으로 취급. 시스템은 그럴듯한 timestamp 를 fabricate 하지 않고 completed 로 표면화 — 사용자는 *실제로 일어나지 않은 "paused-at" 시간* 을 가진 paused timer 를 보지 않는다.
- duration 이 non-finite 인 timer 는 영속화에 들어가지 않는다 — 시작 시점 입력 가드가 어떤 상태도 쓰기 전에 거부.

### 시나리오 8 — 필름 선택이 진행 중인 상태에서 재시작

**목표.** 사진가가 선택한 필름 stock 이 앱 재시작에도 살아남아, 매 중단 후 picker 를 다시 거치지 않는다.

**단계.**
1. 필름 선택, base shutter, ND 설정.
2. 앱 force-quit.
3. 다시 열기. 같은 필름, base shutter, ND 가 복원.

**경계 조건.**
- 카탈로그에 더 이상 존재하지 않는 영속화된 film id 는 selection 을 silently drop 하고 깨끗한 snapshot 을 다시 써, 이후 read 가 혼란을 겪지 않게 한다.
- base shutter 와 ND 는 복원 시 sanitize — 범위 밖 값은 거부, ladder 값만 받는다.

---

## 3. 기능 요구사항

각 요구사항은 시나리오 back-reference 가 있는 "시스템은 X를 한다" 의무. 표현은 의도적으로 acceptance-criteria 스타일에 가깝다.

### 3.1 Calculator

- **FR-1.1** 사용자는 base shutter 값을 관습적 사진 풀스톱 ladder (1/8000 s ~ 30 s) 에서만 입력. 자유형 숫자 입력은 받지 않는다. (시나리오 1, 2)
- **FR-1.2** 사용자는 ND-stop 값을 지원 범위 내 음이 아닌 정수로만 입력. 지원 범위는 stacked-ND 실용 사용을 cover 할 정도로 넓다. (시나리오 1)
- **FR-1.3** 시스템은 base shutter 와 ND 로부터 출력 셔터를 노출 stop 산술로 계산. (시나리오 1)
- **FR-1.4** 시스템은 출력 셔터를 관습적 사진 표기법으로 표시 — 범위 내 값은 같은 ladder 의 가장 가까운 reference 셔터로 snap, 30 s 초과 긴 값은 임의 소수가 아닌 doubling 형태 ladder 로 표시. 표시값이 snap 결과여도 정확한 값은 하류 timer 가 쓰도록 보존. (시나리오 1)
- **FR-1.5** 시스템은 non-finite 결과를 만드는 계산 입력을 거부 — 호출자에게 typed failure 로 표면화 (오해 가능한 숫자 대신). (시나리오 1 경계)
- **FR-1.6** 사용자가 입력값을 드래그하는 동안 시스템은 입력에 commit 하지 않으면서 결과를 미리 보임 (gesture 가 끝날 때까지). 사용자는 원래 값에서 release 해 되돌릴 수 있다. (시나리오 1)

### 3.2 Reciprocity

- **FR-2.1** 시스템은 launch 시점에 큐레이트된 preset 필름 set 을 제공 — 각 필름은 적어도 하나의 출판된 reciprocity profile 보유. (시나리오 2)
- **FR-2.2** 측광 노출과 활성 profile 이 주어지면, 시스템은 결과를 정확히 세 form 중 하나 — *quantified*, *advisory-only*, *unsupported* — 로 분류하며, 한 결과가 둘 이상 form 을 동시에 표현하는 것을 허용하지 않는다. (시나리오 2)
- **FR-2.3** *quantified* 결과는 보정 노출값, 사용자가 한눈에 읽을 수 있는 신뢰도 표시, 그리고 사용자가 drill-in 해 근거 표 row 또는 공식을 볼 수 있는 출처 정보를 carry. (시나리오 2)
- **FR-2.4** *advisory-only* 결과는 보정 숫자 대신 차분한 안내 텍스트를 제시. 데이터가 뒷받침하지 않을 때 시스템은 보정 숫자를 fabricate 하지 않는다. (시나리오 2 경계)
- **FR-2.5** *unsupported* 결과는 카테고리별 안내 노트를 제시하고, 보정 노출 행의 Start Timer affordance 를 비활성화 — 이유를 설명하는 accessibility hint 동반. (시나리오 2 경계)
- **FR-2.6** Reciprocity 평가는 결정적 — 같은 profile 과 측광값은 항상 같은 결과 form, 보정값, 신뢰도 표시를 produce. (NFR-D.1)
- **FR-2.7** 사용자는 calculator 와 화면을 다투는 inline 드롭다운이 아닌, 별도의 dismissible 표면을 통해 필름 선택에 도달. (시나리오 2)
- **FR-2.8** Reciprocity 커버리지는 *완전 정량 곡선* 이 있는 필름으로 한정되지 않는다. threshold-only / advisory-only 출판 가이드는 first-class scope 로 다루며 (보조 fallback 이 아님), 도메인은 향후 비공식 / 사용자 정의 entry 를 위한 capacity 를 예약한다. (시나리오 2 경계; FR-2.2 보완)

### 3.3 Timer 라이프사이클

- **FR-3.1** 시스템은 *엄격히 양수이고 finite* 인 duration 만으로 timer 를 시작. 무한, NaN, non-positive duration 은 진입점에서 거부 — 어떤 영속 상태도 쓰기 전. (시나리오 3 경계)
- **FR-3.2** Timer 는 다음 상태 전환만 따라 이동: *running → paused*, *paused → running*, *running → completed*, *paused → completed* (frozen 남은시간이 0 에 도달한 resume 경유). 다른 전환은 표현 불가능. (시나리오 3, 4)
- **FR-3.3** Paused timer 는 완료를 향해 벽시계 시간을 소비하지 않는다. frozen 남은시간은 사용자가 두고 간 그대로 보존. (시나리오 4)
- **FR-3.4** Resume 은 timer 를 *now + frozen 남은시간* 부터 재시작 — 원래 종료시간은 pause 를 가로질러 보존되지 않는다. (시나리오 4 경계)
- **FR-3.5** 남은시간이 이미 0 에 도달한 pause 는 zero-remaining paused 상태로 진입하는 대신 completed 로 short-circuit. (시나리오 4 경계)
- **FR-3.6** completed 로의 각 전환은 사용자에게 정확히 *한 개* 의 외부 완료 신호를 produce. 보류 중인 신호는 timer 가 제거되거나 running → paused 로 전환될 때 취소. (시나리오 3)
- **FR-3.7** Active timer 는 가장 최근 시작 순으로 표시; completed timer 는 가장 최근 완료 순으로 표시. 동률은 결정적으로 해소되어 사용자가 불안정한 순서를 보지 않는다. (시나리오 5)

### 3.4 Multi-timer + 잠금 화면

- **FR-4.1** 시스템은 다중 동시 timer 를 지원하며, 각각 재정렬 / focus / 그룹 전환을 가로질러 살아남는 안정된 식별자를 가진다. (시나리오 5)
- **FR-4.2** 각 timer 는 비-텍스트 식별 단서 (예: 색조, 형태, 패턴) 를 carry — 사용자가 이름이나 시간 텍스트를 읽지 않고도 형제 timer 들과 한눈에 구분 가능하도록. 단서는 timer 의 lifetime 동안 안정. (시나리오 5)
- **FR-4.3** 잠금 화면 표면은 한 번에 최대 한 개의 timer 만 표시. 선택 규칙 (가장 빠른 종료시간, 결정적 동률 해소) 은 시나리오 6 에 문서화. (시나리오 6)
- **FR-4.4** running / paused timer 가 남지 않으면 잠금 화면 표면은 종료. 사용자는 더 이상 존재하지 않는 잠금 화면 timer 를 보지 않는다. (시나리오 6)
- **FR-4.5** 잠금 화면 표면은 사용자가 폰 unlock 없이 시간이 흐르는 것을 인지할 만큼 자주 갱신. (시나리오 6)

### 3.5 영속화

- **FR-5.1** Timer 상태 (state machine 에 필요한 running / paused / completed 정보) 와 timer 표시 metadata (사용자가 보는 이름, basis-summary 행, LIFO 삽입 순서) 모두 앱 재시작에서 살아남는다. (시나리오 7)
- **FR-5.2** Calculator 컨텍스트 — 선택된 필름, base shutter, ND — 는 앱 재시작에서 살아남아, 사용자가 매 중단마다 picker 를 다시 거치지 않게 한다. (시나리오 8)
- **FR-5.3** 영속화된 형태는 backward-compatible 추가만으로 진화. 이전 release 가 쓴 snapshot 은 현 release 에서 정확하게 복원되어야 하며, 특히 이전 release 가 사용한 status 토큰은 read 시 계속 받아들여져야 한다. (시나리오 7)
- **FR-5.4** 앱 다운타임 동안 종료시간이 이미 지난 실행 중 timer 는 completed 로 복원되며 완료 timestamp 는 *원래 종료시간* (복원 시점이 아님). (시나리오 7 경계)
- **FR-5.5** Freeze metadata 가 누락되거나 일관성이 없는 영속화된 paused timer 는 손상된 입력으로 취급. 시스템은 그럴듯한 timestamp 를 fabricate 하지 않고 completed 로 표면화. (시나리오 7 경계)
- **FR-5.6** 복원 시 카탈로그에 더 이상 존재하지 않는 film id 는 silently drop. 시스템은 깨끗한 snapshot 을 다시 써 이후 read 가 혼란을 겪지 않게 한다. (시나리오 8 경계)

### 3.6 Calculator 화면 + workspace

- **FR-6.1** 계산과 timer 실행은 단일 primary 표면에 산다. 사용자는 실행 중 노출을 모니터링하기 위해 별도 "timer 화면" 으로 navigate 하지 않는다. (시나리오 3, 5)
- **FR-6.2** Primary 표면은 기기의 수직 공간에 적응하되 개념 구조를 재배치하지 않는다 — 모든 density 에서 같은 요소가 존재, spacing 만 변한다. (시나리오 1)
- **FR-6.3** Workspace 표면은 사용자에게 두 가지 distinct 한 표시 — calculator 위쪽을 우선하는 *훑어보기 좋은 요약* 과 timer 목록을 우선하는 *확장 보기* — 를 제공. 중간 상태는 out of scope. (시나리오 3, 5)
- **FR-6.4** Workspace 표면은 calculator 를 가리지 않으면서 calculator 와 공존. 사용자는 timer 가 실행 중에도 timer 표면을 dismiss 하거나 옮기지 않으면서 calculator 입력을 조정할 수 있다. (시나리오 3, 5; 배치는 디자인 선택, 요구사항 아님.)
- **FR-6.5** Reciprocity 상세 표면은 섹션을 고정 순서로 제시 — *Profile / source authority* 먼저, 다음 *Formula 또는 Reference data*, 다음 *Graph*, 다음 *Sources*. 이 순서는 *신뢰할 수 있는 안내는 시각 보조가 아닌 데이터에서 온다* 는 점을 전달. (시나리오 2)

### 3.7 Orientation + 입력

- **FR-7.1** 앱은 orientation 을 lock 해 사진가가 측광 / 조정 중에 단일 grip 으로 폰을 잡을 수 있도록 한다. 현 release 는 portrait 만 지원. (Persona 1.1)
- **FR-7.2** Base shutter 와 ND 는 유효 값으로 snap 하는 컨트롤로 입력. 자유 텍스트 숫자 입력은 받지 않는다 — 오타가 calculator 를 비-사진학적 상태로 빠뜨릴 수 없도록. (시나리오 1)

---

## 4. 비기능 요구사항

### 4.1 결정성

- **NFR-D.1** Reciprocity 평가, 노출 계산, timer state machine 전환은 입력의 결정적 함수. 현재 시간은 항상 호출자가 제공 — evaluator 내부에서 ambient 소스를 읽지 않는다. 같은 입력은 항상 같은 출력을 produce.
- **NFR-D.2** 영속화 형식은 손실 없이 round-trip — snapshot 을 인코딩 후 디코딩하면 원본과 구별 불가능한 값을 produce.

### 4.2 타입 안전성

- **NFR-T.1** 불법(illegal) 상태 조합은 표현 불가능해야 한다. Reciprocity 결과는 quantified 와 advisory 를 동시에 가질 수 없고, timer 는 running 과 paused 를 동시에 가질 수 없다. 언어가 지원하는 곳에서는 컴파일 타임에 강제.
- **NFR-T.2** 무결성 불변식이 런타임 검사에서 구조적 검사로 격상된 후, 그것을 silently 런타임 검사로 다시 격하시키는 코드 패턴은 codebase 재진입이 차단되어야 한다. 메커니즘 (lint, code review, type-system 기능) 은 하류 선택; 의무는 *해당 회귀가 들어와도 알아채지 못한 채로 머지되지 않을 것*.

### 4.3 아키텍처 적합성

- **NFR-A.1** 프로덕션 코드는 자신이 테스트 환경에서 실행 중인지 감지하지 않는다. 프로덕션과 테스트 협력자 사이의 이음새(seam)는 의존성 주입(DI) 이지, 런타임 분기가 아니다.
- **NFR-A.2** 특정 외부 표면 (잠금 화면 위젯, 알림) 에 속하는 관심사는 view model 로 누설되지 않는다. 각 외부 표면은 전용 owner 를 가진다.
- **NFR-A.3** Feature-scoped 상태는 서로 직접 참조하지 않는다. 한 feature 가 다른 feature 의 상태를 필요로 할 때, cross-feature wiring 은 composition 이음새(seam) 의 책임이지 feature 내부의 책임이 아니다. (어떻게 layering 되는지는 `docs/architecture/Architecture.md` 참조.)
- **NFR-A.4** view 는 최대 한 feature 의 상태만 직접 관찰한다. cross-cutting 표시 상태는 더 상위 이음새에서 합성. (어떻게 layering 되는지는 `docs/architecture/Architecture.md` 참조.)

### 4.4 검증

- **NFR-V.1** 도메인과 정책 로직은 사용자가 보는 값에 대한 회귀를 실질적으로 감지하는 단위 테스트 coverage 를 가진다. 수치 목표는 `docs/verification/Strategy.md` 에 기록되어 있으며, *floor* 이지 ceiling 이 아니다.
- **NFR-V.2** 타입 주도 변경 (reciprocity 결과 form, timer state 표현) 은 외부 관찰 가능 동작이 변경되지 않았음을 증명할 수단을 가진다. 메커니즘은 `docs/verification/Strategy.md` 에 기록.
- **NFR-V.3** Cross-cutting 표시 상태 — 각 사용자 시나리오에서 calculator 화면이 보여주는 것 — 는 lock 되어 내부 재구조화가 사용자가 보는 것을 silently 바꾸지 못하게 한다. 메커니즘은 `docs/verification/Strategy.md` 에 기록.
- **NFR-V.4** Cross-platform parity 자료는 iOS test suite 가 소비해 자료 변경이 포팅 시점이 아닌 런타임에 즉시 surface 되도록 한다. 메커니즘은 `docs/verification/Strategy.md` 에 기록.

### 4.5 성능

- **NFR-P.1** 단일 reciprocity 평가는 지원 기기에서 인터랙티브 frame budget 내에 충분한 여유를 두고 들어맞아야 한다. 데이터셋이 한 자릿수 이상 커지거나 새 estimation family 가 도입될 때 재측정 필요.
- **NFR-P.2** 사용자 입력 live preview 는 launch 카탈로그 또는 동급 카탈로그에서 stutter 하지 않는다.

### 4.6 영속화 안정성

- **NFR-S.1** 영속 상태의 저장 위치는 안정된 contract. 저장 위치 rename 은 명시적 마이그레이션 고려가 필요한 breaking change.
- **NFR-S.2** 영속화 형태는 backward-compatible 추가만으로 진화. 디코더는 옛 형태를 받아들이고, 인코더는 deprecated 필드 쓰기를 멈출 수 있지만 이전에 쓰여진 snapshot 은 여전히 정확하게 복원되어야 한다.

---

## 5. Out of scope (현 release)

본 제품은 의도적으로 다음을 제외:

- 변수 섹션의 Aperture 와 ISO 컨트롤. wiki 3866625 의 4-variable 모델은 향후 Epic 으로 예약; 현 release 는 base-shutter + ND 만.
- 자유 텍스트 셔터 입력.
- 명시적 확인 없이 시트 외부 탭으로 필름 선택을 drop. selection 제거의 유일한 길은 "Clear" affordance.
- Timer 큐잉 / 체이닝 (A 끝나면 B 시작). 다중 timer 는 *병렬로* 독립 실행되는 timer 들이지 sequence 가 아님.
- 스튜디오 strobe / flash duration 모드.
- Video 모드 / cinematography.
- Cross-device 동기화. 각 폰이 자신의 카탈로그와 영속 상태를 보유.
- TCA / Redux 스타일 글로벌 store.

---

## 6. 미해결 질문 / 예약 결정

이들은 요구사항이 아니다 — wiki / ticket 이 향후 결정을 예약해 둔 지점들. 암묵적 요구사항으로 drift 하지 않게 여기에 명시.

- **사용자 정의 필름.** wiki 15138817 이 사용자 정의 필름을 향후 검증 대상으로 list — entry/edit UX, 검증 규칙, 영속화 경계는 미정.
- **identity 당 다중 profile.** 도메인은 한 identity 에 다중 profile 을 attach 할 능력을 예약하지만, launch dataset 은 identity 당 하나의 profile 만 ship 하며 active-profile 선택 규칙은 pin 되지 않았다.
- **컬러 보정 metadata.** Velvia 스타일 "M color correction" 이 wiki 15138817 에 언급되지만 schema entry 가 없다.
- **Android 포팅.** 향후 Android 포팅을 예상하며 cross-platform parity 를 위한 공유 test-fixture 자료를 큐레이팅 중이지만, Android codebase 자체는 현 release scope 안에 없다.
- **Aperture / ISO 변수 모델.** wiki 3866625 가 4-variable 파생 모델을 제안하지만 현 release 는 구현하지 않는다.

---

## 7. Living document

본 파일은 *요구사항* 계층이다. 사용자 필요점 ground truth (wiki problem statement) 와 요구사항의 모든 하류 사이에 위치. 하류 문서(아키텍처, 스펙, 검증)에 대한 참조는 탐색(navigational) 목적이며 규범적 의존을 형성하지 않는다. 갱신 트리거:

- 새 사용자 시나리오 추가, 또는 기존 시나리오 closed (예: 다중 profile 선택 ship).
- 새 기능 요구사항 신설 또는 기존 retire.
- 비기능 요구사항 임계값 변화 (예: coverage target 상향, perf budget 강화).
- 미해결 질문 (§6) 해결.

각 갱신은 driver 가 된 wiki 페이지 또는 PR 을 인용한다.

---

## 8. Sources of intent (참고)

제품 의도는 wiki 에 anchor. 구현과 충돌 해결의 source-of-truth 순서는 `AGENTS.md`를 따른다. 아래 wiki
항목은 제품 의도를 뒷받침하는 참고 출처다.

- Wiki 3244033 — 사진가용 타이머 앱 — 문제 정의 (앱이 다루는 일곱 가지 문제)
- Wiki 3375105 — 제품 방향 초안
- Wiki 3866625 — 화면 흐름 초안 (계산과 실행을 단일 화면이 통합)
- Wiki 16482307 — Film Selection and Reciprocity Calculator UI (workflow 방향, 용어)
- Wiki 9601025 — Bottom Sheet UI Architecture (현 workspace shell 구현)
- Wiki 8847362 — Floating Timer Dock UI Design (현 다중 timer 표면 구현)

이들은 *참고 자료* 이며 normative 가 아니다. wiki 3244033 의 일곱 가지 문제는 모든 요구사항이 거슬러 올라가는 사용자 필요점 ground truth. 나머지 entries 는 사용자에게 보이는 결과가 위 §2, §3 에 normative 로 captured 된 특정 결정들을 기록 — wiki 인용은 reader 가 *왜* 특정 표현이 선택됐는지 trace 할 수 있게 한다.
