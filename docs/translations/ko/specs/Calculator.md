# Calculator Spec

> **Locale mirror.** 본 파일은 `docs/specs/Calculator.md` 의 한국어 mirror. 표현 분쟁이 있을 때 영문판이 canonical.

**도메인**: 노출 계산 (ND 필터 조정) + reciprocity 보정 (필름별 시간 보정).

본 문서는 행동 계약(behavior contract): 입력이 주어졌을 때 calculator 가 *무엇을 produce 해야* 하는지, 어떤 invariant 가 유지되어야 하는지, 시스템이 *절대* 하지 말아야 할 것. 플랫폼 중립.

---

## 1. 도메인 모델

### 1.1 노출 변수

Calculator 는 네 변수와 작업: **Shutter**, **Aperture**, **ISO**, **ND**. 이 중 현 release scope 는 **Shutter** 와 **ND**. **Aperture** 와 **ISO** 는 후속 phase 로 유보.

각 변수는 어느 시점에도 두 역할 중 하나:

- **Fixed** — 사용자가 값을 직접 설정.
- **Derived** — 시스템이 다른 변수에서 계산.

규칙:
1. 적어도 한 변수는 항상 Derived.
2. 초기 release 는 Derived 변수 수를 둘로 cap.
3. 사용자가 Derived 변수를 편집하면 그 변수는 Fixed 로 전환되고 calculator 가 나머지 Derived 를 재계산.

### 1.2 Base shutter + output shutter

시스템은 두 개의 distinct 한 shutter 값을 유지:

- **Base Shutter** — 측광 노출, 어떤 조정 *전*.
- **Output Shutter** — ND 조정 + (필름 선택 시) reciprocity 보정 후 produce 된 값.

Output Shutter 는 timer 생성을 driving 하는 값. Base Shutter 는 timer 시작에 직접 사용되지 않는다.

### 1.3 Workflow 모드

명시적인 "Digital / Film" 토글은 없음. Workflow 는 전적으로 필름 선택 상태로 결정:

- **Digital workflow** — 필름 미선택. (ND 만 적용된) Output Shutter 가 최종 촬영 값. Reciprocity 비활성.
- **Film workflow** — 필름 선택됨. reciprocity-보정된 노출 ("Corrected Exposure") 이 primary 촬영 값이 됨; ND-조정된 셔터는 중간값.

Corrected Exposure 행은 모든 film-workflow 상태에서 visible 유지 — 비-quantified 안내를 carry 하는 상태에서도. ("non-quantified" 의미는 §4 참조.)

### 1.4 노출 스케일 모드

Calculator 는 한 Base Shutter step 의 granularity 를 정의하는 **exposure scale** 위에서 동작. 현재 출시 scale 은 **one-third stop**: Base Shutter 는 카메라 표기 라벨이 적용된 1/3-stop 조밀화 ladder (§2.3) 위에서 1/3 stop 단위로 진행. One-third-stop 은 **Base Shutter ladder 에만** 적용 — ND picker 는 모든 출시 모드에서 whole-stop 유지 (§2.2).

모델 레이어는 **full-stop** scale (1-stop shutter, 동일 whole-stop ND) 을 reserved 추상화로 유지. Full-stop scale 은 현재 release 의 메인 calculator UI 에 노출되지 않음:

- 모델 레이어가 "출시 scale" 과 "그 외" 를 분리하지 않고 단일 ladder-aware 추상화를 유지;
- 회귀 테스트가 full-stop math 를 직접 검증할 수 있도록;
- 미래의 Settings preference (Full / 1/2 / 1/3 stop) 가 calculator 도메인 재설계 없이 활성 scale 을 swap 할 수 있도록.

Fractional-aware `NDStep` 도메인 primitive (정수 `thirdStopCount` round-trip 포함) 도 마찬가지로 **reserved 도메인 인프라**로 유지 — 출시 ND option 이 아님. 미래의 custom 또는 variable-ND workflow 가 같은 calculation / persistence 경로를 통과할 수 있도록 존재; 출시 ND picker 는 fractional ND 값을 enumerate 하지 않는다.

이 미래 preference 들이 존재하기 전까지, 사용자에게 활성 scale 의 runtime control 을 노출하지 않음. Persistence 는 활성 scale 토큰을 계속 기록 (§5) — 미래 preference 가 출시될 때 첫 launch 시 사용자의 prior 선택을 덮어쓰지 않고 carry 하기 위함.

---

## 2. Stop 기반 노출 math

### 2.1 단위

모든 노출 조정 math 는 **stop 공간** (밑이 2 인 로그) 에서 수행. 한 stop = 빛이 두 배 변함. Shutter target 은 다음으로 계산:

```
output_seconds = base_seconds × 2^stops
```

ND 값은 stop. 출시 ND ladder 는 whole-stop (§2.2); fractional-capable `NDStep` 도메인 primitive 는 미래 custom / variable-ND workflow 용 reserved 인프라 (§1.4) 로 유지되며 출시 ND picker 에 노출되지 않음. Factor 형태로 들어오는 입력 (예: ND 64×) 은 calculator 진입 전 stop 으로 변환되어야 한다.

### 2.2 ND 입력 범위

ND picker 는 모든 출시 모드에서 **[0, 30] 닫힌 구간의 정수 stop** 을 제시. One-third-stop 은 Base Shutter ladder 에만 적용 (§1.4); ND ladder 는 실제 fixed ND 필터가 whole-stop 강도 (ND2 = 1, ND4 = 2, ND8 = 3, …) 로 판매되기 때문에 whole-stop 유지. Picker 행은 `0, 1, 2, …, 30` — `1/3, 2/3, 7 1/3, 7 2/3` 같은 fractional 값은 출시 ND option set 에 **포함되지 않으며**, view 레이어에서 필터링하지 않는다 (option list 자체에 존재하지 않는다). `[0, 30]` 범위 밖 값은 picker 를 통해 표현 불가능.

Fractional-capable `NDStep` 도메인 primitive (와 정수 `thirdStopCount` persistence round-trip) 는 미래 custom / variable-ND workflow 용 reserved 인프라 (§1.4); 명시적 제품 결정 없이 출시 ND picker 에 노출되지 않는다.

### 2.3 Base shutter 값

Base Shutter picker 는 19-value full-stop 참조 (`1/8000 … 30 s`) 의 각 인접 쌍 사이에 두 개의 중간 step 을 기하평균 비율 `2^(1/3)`, `2^(2/3)` 로 삽입한 **1/3-stop 조밀화 ladder** 를 제시. Full-stop 참조는

```
1/8000, 1/4000, 1/2000, 1/1000, 1/500, 1/250, 1/125,
1/60, 1/30, 1/15, 1/8, 1/4, 1/2,
1, 2, 4, 8, 15, 30   (초)
```

이며, 조밀화된 ladder 는 같은 범위에 걸쳐 55개 entry 를 생성. Picker 행은 카메라 표기 라벨로 렌더링 (예: `1/8000, 1/6400, 1/5000, 1/4000, …, 1/30, 1/25, 1/20, 1/15, 1/13, 1/10, …, 1/2, 1/1.6, 1/1.3, 1s, 1.3s, 1.6s, 2s, 2.5s, 3s, 4s, …, 25s, 30s`) — 사진가가 카메라 다이얼에서 읽는 값과 일치. 내부 canonical seconds 는 기하평균 값 그대로 유지; 계산은 stop-step index 로 진행.

1초 미만 값은 reciprocal 분수 (`1/N`, slow end `1/3, 1/2.5, 1/2, 1/1.6, 1/1.3` 포함) 로 렌더링하고 `s` suffix 를 붙이지 않음. 1초 이상 값은 카메라 관습대로 정수 또는 `N.Ns` 로 렌더링. 자유 텍스트 입력은 미수용; picker 가 유일한 입력 경로.

Reserved full-stop scale (§1.4) 은 19개 full-stop 값을 직접 제시; 해당 surface 는 현재 테스트와 미래 Settings preference 용으로만 사용.

### 2.4 Snap-to-full-stop 출력 규칙

시스템이 출력 셔터를 계산할 때, snap-to-output 정책은 **활성 노출 scale 과 ND step 으로 게이팅**. Snap 은 **둘 다** 만족할 때만 적용:

- 활성 scale 이 reserved full-stop scale (§1.4) 이며,
- ND 값이 whole-stop boundary 에 위치.

출시 one-third-stop scale 에서는 fractional 입력에 대해 두 조건이 모두 성립하지 않고 picker 는 1/3 stop 단위로 진행하므로 snap 은 적용되지 **않음**: 1/3-stop 입력을 full-stop ladder 로 도로 collapse 하면 더 미세한 scale 의 목적이 사라짐. 계산값은 직접 보고됨 (시간 표시는 [UI Spec](UI.md) §2.4 의 규칙으로 포맷).

Snap 이 적용될 때 (reserved full-stop scale + whole-stop ND), 시스템은 표기 관습성을 위해 full-stop 참조 scale 에서 도출된 값을 보고:

- 결과가 **1/8000 .. 30 s** 범위 *안* 이면 19 참조값 중 가장 가까운 값으로 snap.
- 30 s 이상이면 시스템은 **power-of-two** sequence 로 step — snap 된 값은 계산값을 둘러싼 인접한 두 power-of-two 중 더 가까운 값 (64, 128, 256, …). "60, 120, 240" 십진 doubling 이 아님: 60 s 는 64 s 로 round, 60 s 로 보고되지 않음.
- 30 s 경계를 가로지르면, 30 s 위 다음 표시 값은 **64 s** (즉 post-30 s sequence 는 30 → 64 → 128 → 256 → …). 30..64 s 갭 안에서 snap target 은 30 또는 64 중 계산값에 더 가까운 것.

(snap 없는) "exact" 계산값은 snap 표기와 함께 보존되어, 하류 timer 로직이 정확한 숫자를 사용하고 UI 는 관습적 표기를 보여줌. **1 s 미만** 에서는 시스템이 round 된 reciprocal 표기 (예: "1/30") 를 사용 가능 — 정확한 값이 0.0327 일 때도. **1 s 이상** 에서는 시스템이 계산값을 round 하지 않음: 2.13 s 결과는 timer 가 사용할 때 2.13 s 로 유지 — 관습적 표기 "2 s" 로 보일지라도.

### 2.5 방향

ND 조정은 forward 또는 reverse 로 실행:

- **Forward (ND 입력으로)** — Base Shutter + stop count 가 주어지면 Output Shutter 계산.
- **Reverse (ND 출력으로)** — Base Shutter + target Output Shutter 가 주어지면 필요한 stop count 계산.

두 방향 모두 같은 stop-공간 math 사용.

---

## 3. Reciprocity 보정 (film workflow)

필름 선택 시, 시스템은 ND-조정된 셔터에 필름의 reciprocity profile 을 적용해 Corrected Exposure 를 produce. Reciprocity 는 엄격히 후처리: base 노출 계산에 다시 feed 되지 않는다.

### 3.1 3-layer 분리

Reciprocity 계산은 layer 분리를 깨끗하게 보존:

- **Domain layer** 는 제조사 출판 표 또는 공식 + 완전한 provenance 를 보유. 어떤 보간 정책도 인코딩하지 않는다.
- **Calculation policy layer** 는 도메인 데이터 + 측광 노출을 소비하고, 보간/외삽 전략 (§3.3 참조) 을 적용해 명시적 metadata 를 가진 구조화된 결과를 produce.
- **Presentation layer** 는 결과 metadata 를 소비해 신뢰도 cue, note, 경고를 렌더. 숫자를 invent 하지 않으며 metadata 구분을 flatten 하지 않는다 (예: "estimated" 가 "exact" 로 표시되면 안 됨).

### 3.2 평가 순서

측광 노출 `t` 에 대해, 정책 layer 는 필름의 profile 을 다음 순서로 평가. 각 단계는 결과를 produce 하고 멈추거나 fall through.

1. **Exact 표 점** — `t` 가 quantified 표 row 와 정확히 일치하면 row 의 보정값 + basis = `exact_table_point` 반환.
2. **Threshold 무보정** — profile 이 무보정 임계값을 정의하고 `t` 가 그 안에 있으면 `corrected = t` (shift 없음) + basis = `official_threshold_no_correction` 반환.
3. **제조사 stop signal** — profile 이 `t` 이하에서 severity "not-recommended" 인 stop signal 를 포함하면, advisory-only / unsupported 로 short-circuit (signal 의 정책에 따라). Signal 은 후속 단계를 override.
4. **표 보간 / 외삽** — `t` 가 quantified 표 row 사이 또는 외부이고 정책이 허용하면, 적절한 estimation family (§3.3 참조) 로 계산해 basis = `interpolated_within_table` 또는 `extrapolated_beyond_table` 반환.
5. **Formula** — profile 이 지수 공식 `T_c = T_m^P` (또는 등가) 를 정의하면 적용해 basis = `formula_derived` 반환. Formula 평가는 generic "unsupported" fallback 전에 실행 — 공식을 가진 필름이 긴 노출에서도 quantified 유지되도록.
6. **Advisory / unsupported fallback** — 측광 노출이 profile 의 모든 지원 영역 너머이면 숫자 보정값 없이 반환: 정책에 따라 basis = `advisory_only_beyond_official_range` 또는 `unsupported_out_of_policy_range`.

### 3.3 Estimation family 선택

정책이 보간 또는 외삽이 필요할 때:

- 조정이 **보정된 시간** 으로 표현된 profile 은 **log-log** 보간 사용.
- 조정이 **stop delta** 또는 **multiplier** 로 표현된 profile 은 **stop-공간** 보간 사용.

Estimation family 는 단일 필름의 평가 안에서 mix 되지 않는다.

### 3.4 Threshold-to-table 하향 외삽

Profile 의 무보정 임계값 최댓값이 첫 quantified 표 row 보다 *아래* (임계값과 표 사이 갭 생성) 일 때, 정책은 갭 안의 측광값에 대해 **처음 두 quantified 표 점** 을 anchor 로 사용해 외삽된 보정값을 derive. 합성 표 row 는 만들지 않으며, 결과는 두 anchor row 가 `usedReferencePoints` 에 기록된 채 `extrapolated_beyond_table` 로 보고. 하향 외삽은 anchor 에 적어도 두 quantified 점 필요 — 하나만 가능하면 결과는 advisory-only 로 fall through.

### 3.5 결과 형태 + metadata

각 reciprocity 평가는 세 mutually-exclusive form 중 하나의 결과를 produce:

- **Quantified** — 숫자 보정 노출이 반환. 결과는 측광 노출 + 보정 노출 (항상 존재) + 아래 metadata block 을 carry.
- **Advisory-only** — 숫자 보정 노출은 반환 불가, but 시스템은 여전히 설명 + 신뢰도 cue 를 보고. 결과는 측광 노출 + metadata block carry; 보정 노출은 없음.
- **Unsupported** — 측광 노출이 정책 지원 범위 외부. 결과는 측광 노출 + metadata block carry; 보정 노출은 없음.

결과 form 과 calculation basis 는 함께 묶임: `quantified` ↔ `exact_table_point`, `interpolated_within_table`, `extrapolated_beyond_table`, `official_threshold_no_correction`, 또는 `formula_derived`; `advisory_only_beyond_official_range` ↔ `advisoryOnly`; `unsupported_out_of_policy_range` ↔ `unsupported`. 이 페어링은 *구조적* — 런타임 검사가 아닌 컴파일 타임에 강제. 따라서 결과가 숫자 보정값을 claim 하면서 그것을 omit (또는 그 반대) 하는 것이 불가능.

세 form 모두에 존재하는 metadata block 은 carry:

- `calculationBasis` — 다음 중 하나: `exact_table_point`, `interpolated_within_table`, `extrapolated_beyond_table`, `official_threshold_no_correction`, `advisory_only_beyond_official_range`, `unsupported_out_of_policy_range`, `formula_derived`.
- `sourceAuthorityImpact` — profile provenance (제조사 출판 / field-tested / anecdotal) 에서 derive.
- `rangeStatus` — within / extrapolated / threshold-only / beyond-guidance.
- `warningLevel` — none / caution / advisory / not-recommended.
- `supportingNotes` — 결과를 설명하는 사람-읽기 텍스트.
- `usedReferencePoints` — 결과를 inform 한 표 row 또는 공식 계수.

Persistence layer 는 flat-field layout (측광, 보정, 명시적 returned-time 플래그, metadata block) 과 three-form layout 둘 다 decode 시 받아들인다; encoder 는 three-form layout 으로 쓴다. ([DomainSchema Spec](DomainSchema.md) §6 참조.)

### 3.6 Confidence presentation

Presentation layer 는 각 결과를 다음 다섯 신뢰도 카테고리 중 하나로 매핑:

- **Exact** — basis = `exact_table_point` 또는 `formula_derived` (직접 출판된 계수).
- **Estimated** — basis = `interpolated_within_table`.
- **Extrapolated** — basis = `extrapolated_beyond_table`. extrapolated 와 estimated 는 distinct 한 카테고리로 표시; extrapolated 는 더 강한 low-confidence signal 을 carry.
- **Advisory-only** — basis = `advisory_only_beyond_official_range` 또는 임계값 band 너머의 threshold 무보정. UI 는 숫자 대신 차분한 설명 텍스트 표시; 값을 fabricate 하지 않는다.
- **Unsupported** — basis = `unsupported_out_of_policy_range`. 같은 규칙: fabricate 한 숫자 없음.

---

## 4. Timer 통합

Timer 는 **Output Shutter** (digital workflow) 또는 **Corrected Exposure** (film workflow) 에서 생성. 시스템은 비-quantified 결과에서 timer 를 시작하지 않는다 — 보정 노출이 advisory-only 또는 unsupported 일 때 Film 모드 timer-start affordance 는 비활성화되며, 사용자는 입력을 변경하거나 ND-조정된 셔터로 명시적으로 진행하도록 안내.

Timer 의 metadata 는 생성 시점의 계산 결과 snapshot. 후속 calculator 입력 변경은 이미 생성된 timer 를 변경하지 않는다. ([Timer Spec](Timer.md) §1 참조.)

---

## 5. 재시작 가로지른 복원

Calculator 의 working context — 선택된 필름 identity + **노출 scale 토큰** (§1.4) + Base Shutter + ND 값 — 는 digital + film 양 workflow 에서 영속화 + 재시작 시 복원. 저장된 preset identity 가 어떤 catalog entry 로도 resolve 되지 않거나 활성 scale 의 ladder 에 대한 숫자 값 검증이 실패면, 시스템은 정의된 default 로 안전하게 fallback (crash 또는 silent drift 아님).

노출 scale 토큰 (또는 fractional ND) 등장 이전 release 에서 작성된 snapshot 도 정상 복원: 누락된 필드는 **출시 one-third-stop scale** (§1.4) 로 resolve 되고, 정수 ND 값은 새 ladder 의 whole-stop count 로 처리됨. 출시 ladder 는 legacy full-stop ladder 의 strict superset 이므로 legacy whole-stop 값을 다시 쓸 필요 없이 유효한 ladder entry 로 유지됨.

---

## 6. Forbidden patterns

시스템은 다음을 **하지 않는다**:

1. 결과가 advisory-only 또는 unsupported 일 때 숫자 보정값을 fabricate.
2. 도메인 모델 안에 보간 또는 외삽 정책을 인코딩. (도메인은 제조사 데이터를 verbatim 으로 저장; 정책은 자체 layer.)
3. Estimation family 를 mix (예: stop-delta profile 에 log-log 적용, 또는 그 반대).
4. 제조사 "not-recommended" stop signal 을 generic 외삽으로 무시.
5. 1 s 이상 계산값 round. (Round 표기는 sub-second 에서만 허용.)
6. Calculator 입력 변경이 이미 생성된 timer 의 metadata 를 mutate.
7. 비-quantified 보정 노출에서 timer 시작.

---

## 7. Drift + 미해결 질문

미해결 또는 부분 명세. 시스템이 의도에서 silently 더 drift 하지 않도록 기록.

- **Aperture + ISO** 노출 변수는 intent-level (wiki 3964929) 이지만 현 release 에 포함 안 됨. Fixed/Derived 상태 머신, 다중 변수 linkage 규칙, 한 변수 이상 가로지른 reverse 계산은 유보.
- **두 개 위 multi-derived ceiling.** Wiki 3964929 가 확장 옵션 예약 — 결정 기록 없음.
- **Per-data-shape 정책 선택.** Wiki 15761409 가 모든 profile shape 가 log-log 를 원하지 않을 수 있다고 명시 — 어떤 것은 stop-공간 원할 수도. 현 코드는 §3.3 을 일관 적용. Per-profile override 메커니즘은 결정 안 됨.
- **외삽 cap.** Quantified table 외삽은 제조사 stop signal 이 차단할 때까지 계속 — stop signal 이 없는 profile 에 implicit ceiling 이 있어야 하는지는 미정 (open question).
- **사용자 정의 필름 schema.** Wiki 15138817 이 검증 요구사항으로 list — 데이터 모델과 UX 는 명시 안 됨.
- **다중 profile 필름.** 일부 필름은 다중 official profile 가질 수 있음 (다른 현상액, push/pull). 선택 규칙은 아직 정의 안 됨; 현 launch 정책은 필름 identity 당 한 primary profile ship.
- **컬러 + 현상 안내.** Profile 이 이를 기록 (예: Velvia 50 "M color correction", Tri-X dev-time 조정) but spec 은 calculator 가 이를 어떻게 표면화하는지 아직 정의 안 됨.

---

## 8. Sources of intent (참고)

이들은 *참고 자료* 이며 normative 가 아니다. 위의 spec 본문이 사용자 대면 contract; 아래 인용은 reader 가 *왜* 특정 표현이 선택됐는지 trace 할 수 있게 한다.

**Wiki (페이지 id 인용)**
- 3964929 — 계산 엔진 규칙 (변수, fixed/derived 상태, ND 정책, reciprocity 적용 흐름)
- 7438337 — 노출 스톱 스케일 관행 조사 (rounded-notation vs exact-value 분리)
- 13172737 — Reciprocity Film Research List (launch scope, method keys, provenance 규칙)
- 15237121 — Reciprocity Table Calculation Policy Notes (도메인 / 정책 / presentation 분리)
- 15761409 — Reciprocity Table Interpolation and Calculation Policy Draft (책임 분리, metadata, 정책 방향)
- 15138817 — Reciprocity Validation Samples (최소 검증 매트릭스, 예시 profile)
- 16482307 — Film Selection and Reciprocity Calculator UI (workflow 방향, state semantics)

