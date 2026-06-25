# PTimer — 요구사항

> **Locale mirror.** 본 파일은 `docs/requirements/Requirements.md`의 한국어 mirror. 표현 분쟁이 있을 때 영문판을 canonical로 본다.

**문서 종류**: 사용자 시나리오 기반 요구사항 문서.
**대상 독자**: 앱이 *무엇을* 해야 하는지 알아야 하는 제품 / 엔지니어링 / 향후 기여자.
**영향 방향**: 요구사항 → 행동 계약 → 코드, **단방향**. 요구사항 문서는 제품 의도에 대해 normative 하다. 하류 문서들은 각 요구사항이 어떻게 명세되고, 구조화되고, 검증되는지를 구체화한다. 하류 문서에 대한 참조는 탐색(navigational) 목적이며 요구사항이 그 문서들에 의존하게 만들지 않는다. 요구사항이 *"시스템은 X를 한다"* 라고 말할 때, *무엇을* 하고 *왜* 하는지는 여기에서 결정되며, *어떻게* 하는지는 하류에서 결정된다.
**문구 규칙**: 모든 요구사항은 *사용자에게 보이는 필요점* 또는 *무결성 불변식(integrity invariant)*을 기술한다. 구현 specifics(픽셀 사이즈, 갱신 주기, 영속화 키, lint 규칙 ID, baseline 파일명, property wrapper 선택 등)는 하류 문서에 속하며 본 문서에 등장하지 않는다.

**문서 경계**: 본 문서는 앱이 *무엇을* 해야 하는지 정의한다. 다음은 정의하지 않는다:

- 시스템이 *어떻게* 구조화되는지 — `docs/architecture/Architecture.md` 참조;
- 각 요구사항을 어떤 *행동 계약*이 realize 하는지 — `docs/specs/` 참조;
- 변경이 *어떻게* 검증되는지 — `docs/verification/Strategy.md` 참조.

요구사항이 non-functional 의무 (예: 결정성, 영속 안정성)를 진술할 때, 그 의무는 여기에 위치하고; 그것을 달성하는 메커니즘은 해당 하류 문서에 위치한다.

---

## 1. 페르소나

### 1.1 장노출 사진가 (primary)

ND 필터를 사용해 장노출을 촬영하는 사진가. 삼각대 위에서 작업하며 옥외 환경이 잦고, 한 컷의 측광 후 수십 초 ~ 수 분 동안 셔터를 열어둔다. 필름 카메라 / 디지털 카메라 / 한 outing 내에 두 가지를 번갈아 사용 가능. 촬영 중에는 iPhone을 portrait grip으로 잡고 있으며, 일단 시퀀스를 시작하면 폰을 잘 내려놓지 않는다.

### 1.2 필름 reciprocity 보정이 필요한 사진가 (specialization)

위와 동일한 사진가가, reciprocity 거동이 측광값과 어긋나는 필름 stock을 사용할 때. 단순 "stops" 계산이 아닌, 활성 필름의 출판된 reciprocity 데이터에 대한 *보정값*이 필요하다. 필름마다 보정 곡선이 다르고, 어떤 것은 제조사 임계치만 발표, 어떤 것은 정량 공식 (선택적으로 제조사 reference 점 포함)을 발표, 어떤 것은 정성적 장노출 안내만 발표한다.

### 1.3 다중 카메라 사진가 (specialization)

한 촬영 세션 안에서 두 대에서 네 대까지 카메라를 운용하는 사진가. 예: reciprocity 보정이 필요한 아날로그 중형 바디를 보정 불필요한 디지털 바디와 병행, 또는 서로 다른 필름이 들어 있는 두 필름 바디 — 각자 자기 reciprocity profile이 필요한 — 를 동시 사용. 흔한 필드 조합:

- **디지털 + 필름** — 디지털 바디 한 대와 필름 바디 한 대를 컷 단위로 번갈아. 활성 카메라가 바뀔 때마다 calculator를 매번 재구축 (필름 다시 고르기, base shutter 다시 입력, ND 다시 설정) 하지 않아야 한다.
- **두 필름, 두 바디** — 예: Portra 400 한 바디 + Acros II 한 바디. 각 카메라가 자기 선택 필름과 자기 reciprocity 결과를 슬롯 전환 사이에 보존해야 한다.
- **카메라별 다중 동시 timer** — 한 카메라가 장노출을 잡는 사이 사진가가 다른 카메라의 다음 컷을 준비. 실행 중 각 timer는 어느 카메라 / 어느 컷에 속하는지 사진가가 한눈에 알 수 있을 만큼의 식별 정보를 포함한다.
- **빠른 필드 전환** — 구도 변경이 빠르다. 활성 카메라 전환은 settings detour가 아닌 단일 / compact 제스처여야 하며, 비활성 카메라의 setup을 reset 하지 않는다.
- **2~4대 active 카메라** — 폰 화면에 들어맞을 정도로 필드 워크플로우는 작게 유지. 4대를 넘어가면 inventory manager 영역으로 이행되며 이는 out of scope (§5 참조).

어떤 timer가 *어느 컷*에 속하는지 *한눈에* 식별해야 함 — 라벨 없는 큐를 외울 수는 없다.

본 제품은 캐주얼 스냅샷 사용자, 스튜디오 스트로브 촬영자, cinematography 사용 사례를 위해 설계되지 *않았다*. 이들은 측광 루프와 timer 필요성이 매우 다르다.

---

## 2. 핵심 시나리오

각 시나리오는 사용자 목표, 앱이 지원해야 하는 단계, 그리고 동작이 자명하지 않은 경계 조건을 기술한다.

### 시나리오 1 — ND 필터 출력 셔터 계산 (digital workflow)

**목표.** 사진가가 카메라로 측광한 뒤, ND 필터로 N stop 줄였을 때 필요한 셔터 속도를 알고 싶다.

**단계.**
1. 카메라 표기 라벨이 적용된 1/3-stop 조밀화 ladder에서 base shutter를 설정.
2. whole-stop ND ladder에서 ND를 설정.
3. 결과 행에서 출력 셔터를 읽음.
4. (선택) 출력 셔터로부터 timer를 시작 — 카메라 내부 셔터나 손목시계로 측정하기 어려운 길이일 때.

**경계 조건.**
- Base shutter는 1/3-stop 조밀화 ladder (1/8000 ~ 30 s 범위에 걸친 55개 값)에서 카메라 표기 라벨로만 입력 가능. 자유 텍스트 입력은 거부.
- ND 값은 whole-stop ladder `0, 1, 2, …, 30`에서 입력. One-third-stop은 base shutter 에만 적용; ND picker는 실제 fixed ND 필터가 whole-stop 강도로 판매되기 때문에 whole-stop 유지. 범위 밖 값은 받지 않음.
- 출력 셔터는 관습적 사진 표기법으로 표시. 출시 1/3-stop scale 에서는 계산값을 직접 보고 (표준 시간 표시 규칙으로 포맷); 더 거친 ladder로 snap 하지 않으며, 정확한 값은 하류 timer가 그대로 사용.
- 미래 Settings preference가 사용자에게 더 거친 scale (Full / 1/2 stop)을 요청하게 할 수 있음. 그 preference가 존재하면 범위 내 full-stop 결과는 관습 reference로 snap, 30 s 초과 긴 값은 power-of-two doubling ladder (64, 128, 256 …)로 표시 가능. 현 release 에는 그런 selector가 노출되지 않으며, 모든 결과는 1/3-stop 보고 규칙을 따름.

### 시나리오 2 — 필름의 보정 노출 계산 (film workflow)

**목표.** 필름 카메라로 측광한 사진가가, 필름의 reciprocity 특성을 보상한 *보정* 노출을 알고 싶다.

**단계.**
1. 필름 picker 시트를 연다 (picker는 화면 내 드롭다운이 아닌 별도 시트).
2. 출시 카탈로그에서 preset 필름 stock을 선택.
3. 필름 row의 권위(authority) 부제로 활성 reciprocity profile이 **Official guidance** (제조사 출판) 인지 **Unofficial practical** (커뮤니티 도출) 인지 확인. 출시 dataset에 포함되는 권위들은 라벨이 항상 표시됨.
4. 시나리오 1과 동일하게 base shutter와 ND 설정.
5. 결과 섹션이 두 개의 안정된 행을 표시: **Adjusted Shutter** (ND 적용, reciprocity 전)와 **Corrected Exposure** (reciprocity 적용 후 최종값).
6. (선택) reciprocity 상세 시트를 열어 근거 데이터 — Profile / Formula 또는 Reference / Graph / Sources 섹션 (이 순서, 안정된 초기 detent) — 를 확인.

**경계 조건.**
- film workflow에서 Corrected Exposure 행은 *항상 표시된다*. 사용자가 측광값을 움직여 결과가 *quantified*, *limited-guidance*, *unsupported* 사이로 바뀌어도 layout 형태는 변하지 않는다.
- *quantified* 보정 노출은 숫자 primary 행 + status 배지 표시. status 카테고리는 *No correction* (제조사 무보정 임계치 내부), *Formula-derived* (활성 계산 곡선 위), *Beyond source range* / *Outside guidance* (공식이 제조사 supported boundary 너머에서 numeric continuation 산출; 배지는 warning tone) 중 하나.
- *limited-guidance* 결과는 숫자 대신 차분한 설명 텍스트를 표시. 데이터가 뒷받침하지 않을 때 앱은 결코 근거 없이 숫자를 만들어내지 않는다.
- numeric continuation 없는 *unsupported* 결과는 안내 문구를 표시하고, 보정 행의 Start Timer 버튼은 설명 가능한 accessibility hint와 함께 비활성화.
- base shutter ladder, ND ladder, 결과 보고 규칙은 시나리오 1과 동일. 필름 선택은 calculator의 노출 scale을 변경하지 않는다.

### 시나리오 3 — 장노출 timer 실행

**목표.** 카메라 셔터를 눌러 노출이 시작된 직후, 사진가가 앱에서 timer를 시작해 셔터가 열려 있는 시간을 측정하고자 한다.

**단계.**
1. 결과 섹션의 row 중 측정하려는 값에 해당하는 Start Timer affordance를 활성화. film workflow에서는 두 가지 시작 affordance — Adjusted Shutter 행과 Corrected Exposure 행 — 가 있고, 사용자가 의도에 따라 선택.
2. timer가 *workspace 표면*으로 진입. 이 표면은 calculator와 *함께* 보이도록 유지된다. 사용자는 timer를 닫거나 시야에서 잃지 않으면서 다음 컷을 위해 ND를 조정하거나 필름을 바꿀 수 있다. workspace 표면의 정확한 배치 위치는 디자인 결정이며 요구사항이 아니다.
3. workspace 표면은 각 실행 중인 timer에 대해 다음을 전달: 남은 시간, 여러 시간 스케일에 걸친 *진행감* (30 s timer와 30 min timer 모두 반응적으로 느껴지도록), 이름과 시간 텍스트와 무관한 식별 단서.
4. 사용자는 workspace 표면을 *훑어보기 좋은(glanceable) 요약 모드*와 *모든 실행/일시정지/완료 timer를 함께 보는 확장 모드* 사이에서 전환 가능.
5. timer의 duration이 만료되면, 시스템은 사용자가 폰을 보고 있지 않더라도 (카메라 들고 있거나 폰이 주머니에 있거나) 도달하는 완료 신호를 표시하고, 앱 안 timer 카드는 "Done" 상태로 전환.

**경계 조건.**
- 각 timer는 안정된 식별자를 가짐. 정렬: active 그룹은 가장 최근 시작 순, completed 그룹은 가장 최근 완료 순.
- Timer duration은 시작 시점에서 *엄격히 양수이고 유한한*가 아니면 거부 — `Inf`, `NaN` 금지.
- 각 timer는 자동 생성된 이름과 basis-summary 행을 포함한다 — 사용자가 *어느 컷*에 속한 timer인지 재구성할 수 있도록. 이름은 시작 source (digital 결과 vs film adjusted vs film corrected)를 반영하고, 관련 시 필름 stock 이름을 포함.

### 시나리오 4 — Pause / Resume

**목표.** 사진가가 실행 중인 timer를 일시정지 (구름이 변함, 피사체 이동 등) 후 같은 논리적 지점에서 재개.

**단계.**
1. 실행 중 timer의 pause affordance를 탭.
2. timer가 paused 상태로 진입. 벽시계 시간이 흘러도 paused timer는 자동 완료되지 않음.
3. resume 탭 — timer는 pause 시점의 *frozen 남은시간*에서 계속 진행 (원래 종료시간이 아님).

**경계 조건.**
- 남은시간이 이미 0에 도달한 pause는 *zero-remaining paused* 상태로 들어가는 대신 즉시 *completed*로 short-circuit. 사용자는 "0 s에서 paused" 라는 timer를 보지 않는다.
- paused timer의 가설적 완료 시간은 표시 목적으로 관찰 가능하지만, resume은 항상 종료시간을 *now + 남은시간*으로 재계산. 원래 종료시간은 pause를 가로질러 보존되지 않는다.

### 시나리오 5 — 다중 timer 병렬 실행

**목표.** 두 대 이상 카메라 (또는 한 카메라의 두 대기 노출)를 운용하는 사진가가 컷별로 timer를 분리해 둔다.

**단계.**
1. 시나리오 3을 반복해 두 번째 timer를 시작. workspace 표면은 추가 timer를 수용하면서도 위쪽 calculator를 잃지 않으며, 각 timer는 텍스트를 읽지 않고도 카드를 한눈에 식별할 수 있는 고유 식별 단서를 포함한다.
2. 단일 timer에 focus 해 더 자세히 검사 가능.
3. 다른 timer가 계속 실행되는 동안 한 timer만 일시정지 가능.
4. 완료된 timer는 completed 그룹에 모이고 가장 최근 완료 순.

**경계 조건.**
- timer의 식별 단서는 *해당 timer의 유지되는 동안 안정* — 사용자가 재정렬하거나 focus 하거나 active ↔ completed 그룹 사이로 옮겨도 변하지 않는다.
- workspace 표면은 요약 / 확장 전환 사이에 모양이 안정적. 모드 전환 시 이미 보였던 카드의 layout을 재계산하지 않는다.
- 잠금 화면 표면 (시나리오 6)은 다중 timer가 실행 중이어도 한 번에 *한 개*의 대표 timer만 표시. 선택 규칙은 시나리오 6에 있다.

### 시나리오 6 — 잠금 화면 모니터링

**목표.** 사진가가 셔터가 열려 있는 동안 폰을 내려놓거나 (주머니 등) 하고, 기기의 잠금 화면 표면으로 unlock 없이 남은 시간을 흘끗 본다.

**단계.**
1. timer 시작 (시나리오 3).
2. 폰 잠금. 잠금 화면 표면이 *대표* timer의 이름, duration, 종료시간을 전달.
3. 잠금 화면 표면은 사용자가 unlock 없이도 시간이 흐르는 것을 인지할 정도로 자주 갱신.
4. 모든 timer가 멈추면 (완료 또는 제거) 잠금 화면 표면이 사라진다.

**경계 조건.**
- 대표는 종료시간이 가장 빠른 active timer. 동률은 결정적으로 해소 — 구현이 동률 처리를 비일관적으로 해 표면이 두 timer 사이를 깜빡이는 일은 없어야 한다.
- 앱 active / background 전환을 가로지르는 연속성: scene-phase 변경 중 *기저 선택이 실제로 바뀌지 않는 한* 표면이 두 대표 사이를 깜빡이지 않는다.
- 잠금 화면 표면은 더 이상 존재하지 않는 timer를 절대로 표시하지 않는다 — 모든 실행/일시정지 timer가 멈추면 표면도 종료.

### 시나리오 7 — Timer가 진행 중인 상태에서 앱 재시작

**목표.** 하나 이상의 timer가 실행 중이거나 일시정지 중인 상태에서 사진가의 폰이 재시작 (배터리 / 수동 force-quit / OS 업데이트). 다시 열었을 때 timer들이 그대로 있다.

**단계.**
1. workspace에 timer가 실행 중 / 일시정지 중인 상태에서 앱을 force-quit 또는 폰 재시작.
2. 앱을 다시 열기. 이전 실행 중 timer가 복원 — 실행 중 timer는 앱이 죽어 있던 동안의 벽시계 진행을 반영, 일시정지 timer는 그대로.
3. 종료시간이 이미 지난 실행 중 timer는 completed로 복원되며 완료 timestamp는 *원래 종료시간* (복원 시점이 아님).

**경계 조건.**
- 영속화된 timer 상태는 backward-compatible 추가만으로 진화 — 이전 release가 쓴 snapshot은 현 release 에서도 정확하게 복원되어야 한다.
- freeze metadata가 누락되거나 일관성이 없는 영속화된 paused timer는 손상된 입력으로 취급. 시스템은 그럴듯한 timestamp를 근거 없이 만들어내지 않고 completed로 표시 — 사용자는 *실제로 일어나지 않은 "paused-at" 시간*을 가진 paused timer를 보지 않는다.
- duration이 유한하지 않은 인 timer는 영속화에 들어가지 않는다 — 시작 시점 입력 가드가 어떤 상태도 쓰기 전에 거부.

### 시나리오 8 — 필름 선택이 진행 중인 상태에서 재시작

**목표.** 사진가가 선택한 필름 stock이 앱 재시작에도 살아남아, 매 중단 후 picker를 다시 거치지 않는다.

**단계.**
1. 필름 선택, base shutter, ND 설정.
2. 앱 force-quit.
3. 다시 열기. 같은 필름, base shutter, ND가 복원.

**경계 조건.**
- 카탈로그에 더 이상 존재하지 않는 영속화된 film id는 selection을 silently drop 하고 깨끗한 snapshot을 다시 써, 이후 read가 혼란을 겪지 않게 한다.
- base shutter와 ND는 활성 노출 scale의 ladder에 대해 복원 시 sanitize — 범위 밖 값은 거부, ladder 값만 받는다.
- 노출 scale 토큰 (또는 fractional ND) 등장 이전 release에서 작성된 snapshot도 정상 복원: 누락된 필드는 출시 1/3-stop scale로 resolve 되고, legacy whole-stop 값은 출시 ladder가 legacy full-stop ladder의 strict superset 이므로 그대로 수용된다.

---

## 3. 기능 요구사항

각 요구사항은 시나리오 back-reference가 있는 "시스템은 X를 한다" 의무. 표현은 의도적으로 acceptance-criteria 스타일에 가깝다.

### 3.1 Calculator

- **FR-1.1** 사용자는 base shutter 값을 출시 1/3-stop 조밀화 ladder의 카메라 표기 라벨 (1초 미만은 `1/N` reciprocal 분수, 1초 이상은 정수 또는 `N.Ns` 카메라 관습) 에서만 입력. 자유형 숫자 입력은 받지 않는다. (시나리오 1, 2)
- **FR-1.2** 사용자는 ND 값을 whole-stop ladder `0, 1, 2, …, 30` 에서만 입력. 지원 범위는 stacked-ND 실용 사용을 cover 할 정도로 넓다. One-third-stop은 base shutter 에만 적용; ND ladder는 모든 출시 모드에서 whole-stop 유지. (시나리오 1)
- **FR-1.3** 시스템은 base shutter와 ND로부터 출력 셔터를 노출 stop 산술로 계산. (시나리오 1)
- **FR-1.4** 시스템은 출력 셔터를 관습적 사진 표기법으로 표시. 출시 1/3-stop scale 에서는 표준 시간 표시 규칙으로 포맷한 계산값을 직접 보고하며 더 거친 ladder로 snap 하지 않는다. 정확한 값은 하류 timer가 쓰도록 보존. 미래 Settings preference가 사용자에게 더 거친 scale을 옵트인하게 할 때 full-stop ladder로 snap 하고 (30 s 초과는 power-of-two ladder로) 표시 가능; 그 전까지 그런 snap은 적용되지 않는다. (시나리오 1)
- **FR-1.5** 시스템은 유한하지 않은 결과를 만드는 계산 입력을 거부 — 호출자에게 typed failure로 표시한다 (오해 가능한 숫자 대신). (시나리오 1 경계)
- **FR-1.6** 사용자가 입력값을 드래그하는 동안 시스템은 입력에 확정하지 않고 결과를 미리 보임 (gesture가 끝날 때까지). 사용자는 원래 값에서 놓아 되돌릴 수 있다. (시나리오 1)

### 3.2 Reciprocity

- **FR-2.1** 시스템은 launch 시점에 큐레이트된 preset 필름 set을 제공 — 각 필름은 정확히 하나의 출판된 reciprocity profile 보유. Launch 카탈로그는 current official 제조사 문서에서 source 되어야 하며 quantified formula profile (옵션 제조사 source-evidence row 포함)과 장노출 영역이 정성적인 limited-guidance profile 모두를 cover. 출판된 안내 — threshold 범위, color-filter 권고, 현상 시간 hint, stop-signal 경계 — 를 사용자가 drill into 할 수 있는 형태로 보존. (시나리오 2)
- **FR-2.2** 측광 노출과 활성 profile이 주어지면, 시스템은 결과를 정확히 세 form 중 하나 — *quantified*, *limited-guidance*, *unsupported* — 로 분류하며, 한 결과가 둘 이상 form을 동시에 표현하는 것을 허용하지 않는다. (시나리오 2)
- **FR-2.3** *quantified* 결과는 보정 노출값, 사용자가 한눈에 읽을 수 있는 status 배지, 그리고 사용자가 상세 화면에서 공식 표현과 제조사 reference 점을 볼 수 있는 출처 정보를 포함한다. (시나리오 2)
- **FR-2.4** *limited-guidance* 결과는 보정 숫자 대신 차분한 안내 텍스트를 제시. 데이터가 뒷받침하지 않을 때 시스템은 보정 숫자를 근거 없이 만들어내지 않는다. (시나리오 2 경계)
- **FR-2.5** numeric continuation 없는 *unsupported* 결과는 안내 노트를 제시하고, 보정 노출 행의 Start Timer affordance를 비활성화 — 이유를 설명하는 accessibility hint 동반. Supported range 외부의 formula prediction을 numeric continuation으로 동반하는 *unsupported* 결과 (공식이 source-range boundary 너머에서 값을 계속 산출하는 경우)는 warning-tone 배지와 함께 값을 surface 하며 Start Timer affordance를 활성 유지. (시나리오 2 경계)
- **FR-2.6** Reciprocity 평가는 결정적 — 같은 profile과 측광값은 항상 같은 결과 form, 보정값, status 표시를 산출한다. (NFR-D.1)
- **FR-2.7** 사용자는 calculator와 화면을 다투는 inline 드롭다운이 아닌, 별도의 dismissible 표면을 통해 필름 선택에 도달. (시나리오 2)
- **FR-2.8** Reciprocity 커버리지는 *정량 공식*이 있는 필름으로 한정되지 않는다. threshold-only / limited-guidance 출판 가이드는 일차 지원 범위로 다루며 (보조 대체이 아님), 도메인은 향후 비공식 / 사용자 정의 entry를 위한 capacity를 예약한다. (시나리오 2 경계; FR-2.2 보완)
- **FR-2.9** 사용자는 네 공식 항 (anchor에서의 보정 노출, anchor에서의 측광 노출, 곡선 지수, 고정 offset)과 두 range/policy 경계 (no-correction 상한 + source/confidence 상한)를 노출하는 formula-first editor로 **custom reciprocity 공식 profile**을 작성 가능. Custom profile은 preset 공식 profile과 동일한 공유 guarded 공식 평가 경로를 사용. (Persona 1.2)
- **FR-2.10** 사용자는 custom reciprocity profile을 **저장, 재사용, 선택, 편집, 삭제** 가능. 저장된 custom profile은 앱 재실행을 견디고 preset 카탈로그와 같은 film picker에서 선택 가능하며, 제조사-published entry로 오인될 수 없도록 자기 그룹에 제시. (Persona 1.2; 시나리오 2)
- **FR-2.11** Calculator에서 선택된 custom profile은 preset profile과 같은 조건으로 Corrected Exposure를 구동하며, Corrected Exposure 행의 **Start Timer** affordance는 custom-profile 결과가 quantified이거나 source range 너머 numeric 공식 continuation을 가질 때마다 사용 가능. (Persona 1.2; 시나리오 2, 3; FR-2.5 확장)
- **FR-2.12** Editor는 무효 공식 입력 — 예를 들어 비양수 anchor 노출, 누락된 지수, 또는 잘못된 순서의 range 경계 — 를 위반된 제약의 inline 설명을 surface 하고 무효 state가 사용 가능한 보정을 만든다고 시사할 preview 출력을 억제함으로써 **거부 또는 안전하게 제시**. 시스템은 공식 state가 공유 파라미터 계약을 위반하는 custom profile을 절대 영속하지 않는다. (Persona 1.2)
- **FR-2.13** Custom profile의 **사진가 제공 source metadata** (source kind, 제조사 / stock 라벨, reference URL)는 verbatim 보존되며 **절대 제조사 권위로 제시되지 않는다**. Film 행 authority 부제, picker 행 배지, Details 표면, 그리고 custom profile에서 시작된 모든 timer는 결과가 user-defined profile에서 왔음을 분명히 한다. (Persona 1.2; FR-2.3 보완)
- **FR-2.14** Custom-profile 계산에서 시작된 각 timer는 사진가가 — source custom profile이 나중에 편집되거나 삭제된 후에도 — timer의 duration이 user-defined profile에서 왔음을 인식할 수 있을 만큼의 custom-profile identity를 metadata에 보존. (시나리오 3, 5; FR-4.6 확장)

### 3.3 Timer 라이프사이클

- **FR-3.1** 시스템은 *엄격히 양수이고 유한한* 인 duration 만으로 timer를 시작. 무한, NaN, non-positive duration은 진입점에서 거부 — 어떤 영속 상태도 쓰기 전. (시나리오 3 경계)
- **FR-3.2** Timer는 다음 상태 전환만 따라 이동: *running → paused*, *paused → running*, *running → completed*, *paused → completed* (frozen 남은시간이 0에 도달한 resume 경유). 다른 전환은 표현 불가능. (시나리오 3, 4)
- **FR-3.3** Paused timer는 완료를 향해 벽시계 시간을 소비하지 않는다. frozen 남은시간은 사용자가 두고 간 그대로 보존. (시나리오 4)
- **FR-3.4** Resume은 timer를 *now + frozen 남은시간*부터 재시작 — 원래 종료시간은 pause를 가로질러 보존되지 않는다. (시나리오 4 경계)
- **FR-3.5** 남은시간이 이미 0에 도달한 pause는 zero-remaining paused 상태로 진입하는 대신 completed로 short-circuit. (시나리오 4 경계)
- **FR-3.6** completed 로의 각 전환은 사용자에게 정확히 *한 개*의 외부 완료 신호를 만들어낸다. 보류 중인 신호는 timer가 제거되거나 running → paused로 전환될 때 취소. (시나리오 3)
- **FR-3.7** Active timer는 가장 최근 시작 순으로 표시; completed timer는 가장 최근 완료 순으로 표시. 동률은 결정적으로 해소되어 사용자가 불안정한 순서를 보지 않는다. (시나리오 5)

### 3.4 Multi-timer + 잠금 화면

- **FR-4.1** 시스템은 다중 동시 timer를 지원하며, 각 timer는 running / paused / completed / 재정렬 / focus / inspect 전환을 가로질러 살아남는 안정된 식별자를 가진다. (시나리오 5)
- **FR-4.2** 각 timer는 비-텍스트 식별 단서 (예: 색조, 형태, 패턴)를 포함한다 — 사용자가 이름이나 시간 텍스트를 읽지 않고도 형제 timer들과 한눈에 구분 가능하도록. 단서는 timer의 유지되는 동안 안정. (시나리오 5)
- **FR-4.3** 잠금 화면 표면은 한 번에 최대 한 개의 timer만 표시. 선택 규칙 (가장 빠른 종료시간, 결정적 동률 해소)은 시나리오 6에 문서화. (시나리오 6)
- **FR-4.4** running / paused timer가 남지 않으면 잠금 화면 표면은 종료. 사용자는 더 이상 존재하지 않는 잠금 화면 timer를 보지 않는다. (시나리오 6)
- **FR-4.5** 잠금 화면 표면은 사용자가 폰 unlock 없이 시간이 흐르는 것을 인지할 만큼 자주 갱신. (시나리오 6)
- **FR-4.6** 각 timer는 의도한 카메라 / 컷 / 노출과 연결할 수 있을 만큼의 식별 metadata를 포함한다 — 최소한 시작된 카메라 슬롯, 필름 선택 (있을 경우), 그리고 timer를 산출한 노출 source 종류. 식별 metadata는 timer 시작 시점에 captured 되며, 이후 활성 카메라 슬롯이나 활성 필름 선택이 바뀌어도 timer의 lifetime을 가로질러 drift 하지 않는다. (시나리오 5; Persona 1.3)
- **FR-4.7** Calculator와 결합되지 않은 source로 시작한 timer — *manual* 경로, 외부 사전 계산된 셔터값을 받는 경우 — 는 시작 시점의 활성 카메라 슬롯 / 필름 / 노출 source 식별을 *상속하지 않는다*. 표시 계층은 활성 슬롯 식별을 빌리지 않고 generic basis 라벨로 대체한다. (시나리오 5; Persona 1.3)

### 3.5 영속화

- **FR-5.1** Timer 상태 (state machine에 필요한 running / paused / completed 정보)와 timer 표시 metadata (사용자가 보는 이름, basis-summary 행, LIFO 삽입 순서) 모두 앱 재시작 후에도 유지된다. (시나리오 7)
- **FR-5.2** Calculator 컨텍스트 — 선택된 필름, 노출 scale 토큰, base shutter, ND, 그리고 설정된 경우 Target Shutter duration (FR-9.1, FR-9.5) — 는 앱 재시작에서 살아남아, 사용자가 매 중단마다 picker를 다시 거치지 않게 한다. 노출 scale 토큰을 기록하는 이유는 미래 Settings preference가 사용자의 prior 선택을 upgrade 시 덮어쓰지 않고 이어가기 위함이다. (시나리오 8)
- **FR-5.3** 영속화된 형태는 backward-compatible 추가만으로 진화. 이전 release가 쓴 snapshot은 현 release에서 정확하게 복원되어야 하며, 특히 이전 release가 사용한 status 토큰은 read 시 계속 받아들여져야 한다. (시나리오 7)
- **FR-5.4** 앱 다운타임 동안 종료시간이 이미 지난 실행 중 timer는 completed로 복원되며 완료 timestamp는 *원래 종료시간* (복원 시점이 아님). (시나리오 7 경계)
- **FR-5.5** Freeze metadata가 누락되거나 일관성이 없는 영속화된 paused timer는 손상된 입력으로 취급. 시스템은 그럴듯한 timestamp를 근거 없이 만들어내지 않고 completed로 표시한다. (시나리오 7 경계)
- **FR-5.6** 복원 시 카탈로그에 더 이상 존재하지 않는 film id는 silently drop. 시스템은 깨끗한 snapshot을 다시 써 이후 read가 혼란을 겪지 않게 한다. (시나리오 8 경계)

### 3.6 Calculator 화면 + workspace

- **FR-6.1** 계산과 timer 실행은 단일 primary 표면에 산다. 사용자는 실행 중 노출을 모니터링하기 위해 별도 "timer 화면" 으로 navigate 하지 않는다. (시나리오 3, 5)
- **FR-6.2** Primary 표면은 기기의 수직 공간에 적응하되 개념 구조를 재배치하지 않는다 — 모든 density에서 같은 요소가 존재, spacing만 변한다. (시나리오 1)
- **FR-6.3** Workspace 표면은 사용자에게 두 가지 별개의 표시 — calculator 위쪽을 우선하는 *훑어보기 좋은 요약*과 timer 목록을 우선하는 *확장 보기* — 를 제공. 중간 상태는 out of scope. (시나리오 3, 5)
- **FR-6.4** Workspace 표면은 calculator를 가리지 않으면서 calculator와 공존. 사용자는 timer가 실행 중에도 timer 표면을 dismiss 하거나 옮기지 않으면서 calculator 입력을 조정할 수 있다. (시나리오 3, 5; 배치는 디자인 선택, 요구사항 아님.)
- **FR-6.5** Reciprocity 상세 표면은 섹션을 고정 순서로 제시 — *Profile / source authority* 먼저, 다음 *Formula 또는 Reference data*, 다음 *Graph*, 다음 *Sources*. 이 순서는 *신뢰할 수 있는 안내는 시각 보조가 아닌 데이터에서 온다*는 점을 전달. (시나리오 2)

### 3.7 Orientation + 입력

- **FR-7.1** 앱은 orientation을 lock 해 사진가가 측광 / 조정 중에 단일 grip으로 폰을 잡을 수 있도록 한다. 현 release는 portrait만 지원. (Persona 1.1)
- **FR-7.2** Base shutter와 ND는 유효 값으로 snap 하는 컨트롤로 입력. 자유 텍스트 숫자 입력은 받지 않는다 — 오타가 calculator를 비-사진학적 상태로 빠뜨릴 수 없도록. (시나리오 1)

### 3.8 카메라 슬롯

- **FR-8.1** 시스템은 단일 촬영 세션 안에 다중 카메라 슬롯을 노출. 지원 범위는 두 개에서 네 개까지 — 그 범위 밖 구성은 촬영 workspace scope의 일부가 아니다. (Persona 1.3; inventory 사례 out of scope는 §5에 기록)
- **FR-8.2** 각 카메라 슬롯은 자기 calculator 상태를 보존 — workflow 모드 (digital vs film), 선택 필름과 활성 reciprocity profile (film workflow일 때), base shutter, ND, 노출 scale, 가장 최근 도출된 reciprocity 결과, 그리고 슬롯의 Target Shutter 상태 (FR-9.1). 슬롯은 독립적: 활성 슬롯에서 만든 calculator 변경 — Target Shutter의 enabling, disabling, editing 포함 — 은 비활성 슬롯으로 전파되지 않는다. (Persona 1.3; 시나리오 1, 2)
- **FR-8.3** 활성 슬롯 전환은 모든 비활성 슬롯의 calculator 상태를 그대로 보존한다. 전환은 calculator / 필름 선택 / reciprocity 결과 어디에서도 "reset" 경로를 호출하지 않는다 — 활성 입력 set이 *교체* 되지 *변경* 되지 않는다. (Persona 1.3)
- **FR-8.4** 사용자는 메인 촬영 workspace에서 단일 / 한눈에 잡히는 affordance로 활성 카메라 슬롯을 전환할 수 있다 — settings detour가 아니다. 정확한 affordance (paged TabView, segmented control, swipe gesture, 그 외)는 디자인 결정이며, 요구사항은 calculator에서 한 제스처 거리에 전환이 있는 것이다. (Persona 1.3)
- **FR-8.5** 각 카메라 슬롯은 calculator 상태 / timer / (장차) record 시스템 핸드오프를 의도한 카메라와 연결하기에 충분한 식별 정보를 노출한다 — 최소한 안정된 id와 사람이 읽을 수 있는 표시 라벨. 안정된 id는 표시 라벨과 독립적이며 사용자가 슬롯을 rename 해도 변하지 않는다. (Persona 1.3; FR-4.6 / FR-8.7 보완)
- **FR-8.6** 카메라 슬롯 세션 상태 — 활성 슬롯 id, 모든 슬롯의 보존된 calculator 상태 (설정된 경우 슬롯의 Target Shutter duration 포함, FR-9.5), 그리고 사진가가 지정한 custom 슬롯 라벨 — 는 calculator working 컨텍스트 (FR-5.2)와 같은 조건으로 앱 재시작 후에도 유지된다. 영속화된 슬롯 상태는 backward-compatible 추가만으로 진화 (NFR-S.2); custom 슬롯 라벨 또는 슬롯 Target Shutter 필드를 아직 기록하지 않던 이전 release가 작성한 snapshot은 누락 필드가 부재로 처리되어 정상 복원되어야 한다. (Persona 1.3; 시나리오 8)
- **FR-8.7** 사용자는 카메라 슬롯의 표시 라벨을 사진가 지정값으로 rename 할 수 있고, rename 된 슬롯을 canonical *Camera N* default로 reset 할 수 있다. Rename affordance는 settings detour가 아닌, 메인 촬영 workspace의 슬롯 타이틀에 위치한다. (Persona 1.3)
- **FR-8.8** 빈 값 또는 whitespace-only rename 입력은 빈 라벨로 영속화되지 않고 reset 요청으로 처리된다. Rename은 슬롯의 안정된 id, calculator 상태, 필름 선택, reciprocity 결과, 다른 슬롯의 상태, 그리고 rename 이전에 시작된 timer가 capture 한 슬롯 라벨을 변경하지 않는다. (Persona 1.3 경계; FR-4.6 / FR-8.5 보완)

### 3.9 Target Shutter

- **FR-9.1** 앱은 사진가가 지정한 목표 노출 duration을 현재 계산 결과와 비교하기 위한 **optional Target Shutter workflow**를 지원한다. (Persona 1.1; 시나리오 1, 2)
- **FR-9.2** Non-film workflow에서 비교 값은 Adjusted Shutter; quantified 보정 노출이 존재하는 film workflow에서 비교 값은 Corrected Exposure다. quantified 보정 노출이 없는 film 상태에서는 근거 없는 비교값을 표시하지 않는다. (시나리오 1, 2; FR-2.4 보완)
- **FR-9.3** Target duration은 base shutter, ND, 필름 선택, reciprocity 정책 결과가 변해도 고정 유지; 비교 값만 갱신된다. Target 변경의 유일한 경로는 target 자체 편집이다. (시나리오 1, 2)
- **FR-9.4** 사용자는 Target Shutter로부터 timer를 시작할 수 있다. 이렇게 시작된 timer는 target duration 자체를 timer duration으로 사용하며, Adjusted Shutter / Corrected Exposure timer와 유지되는 동안 구별되는 exposure source identity를 유지한다 (FR-4.6 확장). (시나리오 3, 5)
- **FR-9.5** Target Shutter 상태는 카메라 슬롯별로 종속 (FR-8.2 확장). 활성 슬롯 전환은 슬롯의 다른 입력과 함께 target도 교체하며, 비활성 슬롯에 저장된 target은 다른 슬롯에 노출되지 않는다 — 슬롯별 영속화는 세션 전역 last-used target 메모리를 초기값으로 사용하지 않아야 한다. (Persona 1.3)

---

## 4. 비기능 요구사항

### 4.1 결정성

- **NFR-D.1** Reciprocity 평가, 노출 계산, timer state machine 전환은 입력의 결정적 함수. 현재 시간은 항상 호출자가 제공 — evaluator 내부에서 ambient 소스를 읽지 않는다. 같은 입력은 항상 같은 출력을 산출한다.
- **NFR-D.2** 영속화 형식은 손실 없이 round-trip — snapshot을 인코딩 후 디코딩하면 원본과 구별 불가능한 값을 산출한다.

### 4.2 타입 안전성

- **NFR-T.1** 불법(illegal) 상태 조합은 표현 불가능해야 한다. Reciprocity 결과는 quantified와 limited-guidance를 동시에 가질 수 없고, timer는 running과 paused를 동시에 가질 수 없다. 언어가 지원하는 곳에서는 컴파일 타임에 강제.
- **NFR-T.2** 무결성 불변식이 런타임 검사에서 구조적 검사로 격상된 후, 그것을 silently 런타임 검사로 다시 격하시키는 코드 패턴은 codebase 재진입이 차단되어야 한다. 메커니즘 (lint, code review, type-system 기능)은 하류 선택; 의무는 *해당 회귀가 들어와도 알아채지 못한 채로 머지되지 않을 것*.

### 4.3 아키텍처 적합성

- **NFR-A.1** 프로덕션 코드는 자신이 테스트 환경에서 실행 중인지 감지하지 않는다. 프로덕션과 테스트 협력자 사이의 이음새(seam)는 의존성 주입(DI) 이지, 런타임 분기가 아니다.
- **NFR-A.2** 특정 외부 표면 (잠금 화면 위젯, 알림)에 속하는 관심사는 view model로 누설되지 않는다. 각 외부 표면은 전용 owner를 가진다.
- **NFR-A.3** Feature-scoped 상태는 서로 직접 참조하지 않는다. 한 feature가 다른 feature의 상태를 필요로 할 때, cross-feature wiring은 composition 이음새(seam)의 책임이지 feature 내부의 책임이 아니다. (어떻게 layering 되는지는 `docs/architecture/Architecture.md` 참조.)
- **NFR-A.4** view는 최대 한 feature의 상태만 직접 관찰한다. cross-cutting 표시 상태는 더 상위 이음새에서 합성. (어떻게 layering 되는지는 `docs/architecture/Architecture.md` 참조.)

### 4.4 검증

- **NFR-V.1** 도메인과 정책 로직은 사용자가 보는 값에 대한 회귀를 실질적으로 감지하는 단위 테스트 coverage를 가진다. 수치 목표는 `docs/verification/Strategy.md`에 기록되어 있으며, *floor* 이지 ceiling이 아니다.
- **NFR-V.2** 타입 주도 변경 (reciprocity 결과 form, timer state 표현)은 외부 관찰 가능 동작이 변경되지 않았음을 증명할 수단을 가진다. 메커니즘은 `docs/verification/Strategy.md`에 기록.
- **NFR-V.3** Cross-cutting 표시 상태 — 각 사용자 시나리오에서 calculator 화면이 보여주는 것 — 는 lock 되어 내부 재구조화가 사용자가 보는 것을 silently 바꾸지 못하게 한다. 메커니즘은 `docs/verification/Strategy.md`에 기록.
- **NFR-V.4** Cross-platform parity 자료는 iOS test suite가 소비해 자료 변경이 포팅 시점이 아닌 런타임에 즉시 반영되도록 한다. 메커니즘은 `docs/verification/Strategy.md`에 기록.

### 4.5 성능

- **NFR-P.1** 단일 reciprocity 평가는 지원 기기에서 인터랙티브 frame budget 내에 충분한 여유를 두고 들어맞아야 한다. 데이터셋이 한 자릿수 이상 커지거나 새 estimation family가 도입될 때 재측정 필요.
- **NFR-P.2** 사용자 입력 live preview는 launch 카탈로그 또는 동급 카탈로그에서 stutter 하지 않는다.

### 4.6 영속화 안정성

- **NFR-S.1** 영속 상태의 저장 위치는 안정된 contract. 저장 위치 rename은 명시적 마이그레이션 고려가 필요한 breaking change.
- **NFR-S.2** 영속화 형태는 backward-compatible 추가만으로 진화. 디코더는 옛 형태를 받아들이고, 인코더는 deprecated 필드 쓰기를 멈출 수 있지만 이전에 쓰여진 snapshot은 여전히 정확하게 복원되어야 한다.

---

## 5. Out of scope (현 release)

본 제품은 의도적으로 다음을 제외:

- 변수 섹션의 Aperture와 ISO 컨트롤. wiki 3866625의 4-variable 모델은 향후 Epic으로 예약; 현 release는 base-shutter + ND만.
- 자유 텍스트 셔터 입력.
- 사용자 노출 scale selector. 출시 calculator는 1/3-stop scale 에서만 동작; Full / 1/2 / 1/3 stop preference는 미래 Settings 영역로 유보 ([Calculator Spec](../specs/Calculator.md) §1.4 참조).
- 명시적 확인 없이 시트 외부 탭으로 필름 선택을 drop. selection 제거의 유일한 길은 "Clear" affordance.
- Timer 큐잉 / 체이닝 (A 끝나면 B 시작). 다중 timer는 *병렬로* 독립 실행되는 timer들이지 sequence가 아님.
- 스튜디오 strobe / flash duration 모드.
- Video 모드 / cinematography.
- Cross-device 동기화. 각 폰이 자신의 카탈로그와 영속 상태를 보유. 사용자가 작성한 custom reciprocity profile의 remote sharing도 out of scope; FR-2.9는 local 작성만 다룬다.
- Table-derived custom reciprocity 입력. 현 custom-profile workflow (FR-2.9 ~ FR-2.14)는 항별로 작성한 공식을 받는다; multi-row reference table과 point fitting을 custom 계산 model로 쓰는 것은 향후 기능으로 유보.
- picker의 select / create / edit / delete affordance를 넘어선 광범위한 film-inventory 관리. Bulk import/export, 태깅, custom-profile editor 외부의 per-stock 노트는 본 release의 일부가 아니다.
- TCA / Redux 스타일 글로벌 store.

---

## 6. 미해결 질문 / 예약 결정

이들은 요구사항이 아니다 — wiki / ticket이 향후 결정을 예약해 둔 지점들. 암묵적 요구사항으로 drift 하지 않게 여기에 명시.

- **사용자 정의 필름.** wiki 15138817이 사용자 정의 필름을 향후 검증 대상으로 list — entry/edit UX, 검증 규칙, 영속화 경계는 미정.
- **identity 당 다중 profile.** 도메인은 한 identity에 다중 profile을 attach 할 능력을 예약하지만, launch dataset은 identity 당 하나의 profile만 ship 하며 active-profile 선택 규칙은 pin 되지 않았다.
- **컬러 보정 metadata.** Velvia 스타일 "M color correction" 이 wiki 15138817에 언급되지만 schema entry가 없다.
- **Android 포팅.** 향후 Android 포팅을 예상하며 cross-platform parity를 위한 공유 test-fixture 자료를 큐레이팅 중이지만, Android codebase 자체는 현 release scope 안에 없다.
- **Aperture / ISO 변수 모델.** wiki 3866625가 4-variable 파생 모델을 제안하지만 현 release는 구현하지 않는다.

---

## 7. Living document

본 파일은 *요구사항* 계층이다. 사용자 필요점 ground truth (wiki problem statement)와 요구사항의 모든 하류 사이에 위치. 하류 문서(아키텍처, 스펙, 검증)에 대한 참조는 탐색(navigational) 목적이며 규범적 의존을 형성하지 않는다. 갱신 트리거:

- 새 사용자 시나리오 추가, 또는 기존 시나리오 closed (예: 다중 profile 선택 ship).
- 새 기능 요구사항 신설 또는 기존 retire.
- 비기능 요구사항 임계값 변화 (예: coverage target 상향, perf budget 강화).
- 미해결 질문 (§6) 해결.

각 갱신은 driver가 된 wiki 페이지 또는 PR을 인용한다.

---

## 8. Sources of intent (참고)

제품 의도는 wiki에 anchor. 구현과 충돌 해결의 source-of-truth 순서는 `AGENTS.md`를 따른다. 아래 wiki
항목은 제품 의도를 뒷받침하는 참고 출처다.

- Wiki 3244033 — 사진가용 타이머 앱 — 문제 정의 (앱이 다루는 일곱 가지 문제)
- Wiki 3375105 — 제품 방향 초안
- Wiki 3866625 — 화면 흐름 초안 (계산과 실행을 단일 화면이 통합)
- Wiki 16482307 — Film Selection and Reciprocity Calculator UI (workflow 방향, 용어)
- Wiki 9601025 — Bottom Sheet UI Architecture (현 workspace shell 구현)
- Wiki 8847362 — Floating Timer Dock UI Design (현 다중 timer 표면 구현)

이들은 *참고 자료*이며 normative가 아니다. wiki 3244033의 일곱 가지 문제는 모든 요구사항이 거슬러 올라가는 사용자 필요점 ground truth. 나머지 entries는 사용자에게 보이는 결과가 위 §2, §3에 normative로 captured된 특정 결정들을 기록 — wiki 인용은 reader가 *왜* 특정 표현이 선택됐는지 trace 할 수 있게 한다.
