# Calculator Spec

> **Locale mirror.** 본 파일은 `docs/specs/Calculator.md`의 한국어 mirror. 표현 분쟁이 있을 때 영문판을 canonical로 본다.

**도메인**: 노출 계산 (ND 필터 조정) + reciprocity 보정 (필름별 시간 보정).

본 문서는 행동 계약(behavior contract): 입력이 주어졌을 때 calculator가 *무엇을 산출해야* 하는지, 어떤 invariant가 유지되어야 하는지, 시스템이 *절대* 하지 말아야 할 것. 플랫폼 중립.

---

## 1. 도메인 모델

### 1.1 노출 변수

Calculator는 네 변수와 작업: **Shutter**, **Aperture**, **ISO**, **ND**. 이 중 현 release scope는 **Shutter**와 **ND**. **Aperture**와 **ISO**는 후속 phase로 유보.

각 변수는 어느 시점에도 두 역할 중 하나:

- **Fixed** — 사용자가 값을 직접 설정.
- **Derived** — 시스템이 다른 변수에서 계산.

규칙:
1. 적어도 한 변수는 항상 Derived.
2. 초기 release는 Derived 변수 수를 둘로 cap.
3. 사용자가 Derived 변수를 편집하면 그 변수는 Fixed로 전환되고 calculator가 나머지 Derived를 재계산.

### 1.2 Base shutter + output shutter

시스템은 서로 구별되는 두 개의 shutter 값을 유지한다:

- **Base Shutter** — 측광 노출, 어떤 조정 *전*.
- **Output Shutter** — ND 조정 + (필름 선택 시) reciprocity 보정 후 산출된 값.

Output Shutter는 timer 생성을 driving 하는 값. Base Shutter는 timer 시작에 직접 사용되지 않는다.

### 1.3 Workflow 모드

명시적인 "Digital / Film" 토글은 없음. Workflow는 전적으로 필름 선택 상태로 결정:

- **Digital workflow** — 필름 미선택. (ND만 적용된) Output Shutter가 최종 촬영 값. Reciprocity 비활성.
- **Film workflow** — 필름 선택됨. reciprocity-보정된 노출 ("Corrected Exposure")이 primary 촬영 값이 됨; ND-조정된 셔터는 중간값.

Corrected Exposure 행은 모든 film-workflow 상태에서 계속 보인다 — 비-quantified 안내를 포함한 상태에서도. ("non-quantified" 의미는 §3.3 참조.)

### 1.4 노출 스케일 모드

Calculator는 한 Base Shutter step의 granularity를 정의하는 **exposure scale** 위에서 동작. 현재 출시 scale은 **one-third stop**: Base Shutter는 카메라 표기 라벨이 적용된 1/3-stop 조밀화 ladder (§2.3) 위에서 1/3 stop 단위로 진행. One-third-stop은 **Base Shutter ladder 에만** 적용 — ND picker는 모든 출시 모드에서 whole-stop 유지 (§2.2).

모델 레이어는 **full-stop** scale (1-stop shutter, 동일 whole-stop ND)을 향후 확장을 위한 추상화로 유지. Full-stop scale은 현재 release의 메인 calculator UI에 노출되지 않음:

- 모델 레이어가 "출시 scale" 과 "그 외" 를 분리하지 않고 단일 ladder-aware 추상화를 유지;
- 회귀 테스트가 full-stop math를 직접 검증할 수 있도록;
- 미래의 Settings preference (Full / 1/2 / 1/3 stop)가 calculator 도메인 재설계 없이 활성 scale을 swap 할 수 있도록.

Fractional-aware `NDStep` 도메인 primitive (정수 `thirdStopCount` round-trip 포함)도 마찬가지로 **향후 확장을 위한 도메인 인프라**로 유지 — 출시 ND option이 아님. 미래의 custom 또는 variable-ND workflow가 같은 calculation / persistence 경로를 통과할 수 있도록 존재; 출시 ND picker는 fractional ND 값을 enumerate 하지 않는다.

이 미래 preference 들이 존재하기 전까지, 사용자에게 활성 scale의 runtime control을 노출하지 않음. Persistence는 활성 scale 토큰을 계속 기록 (§5) — 미래 preference가 출시될 때 첫 launch 시 사용자의 prior 선택을 덮어쓰지 않고 이어가기 위함.

### 1.5 활성 슬롯에 종속되는 calculator 입력

Calculator의 입력 — workflow 모드 (digital vs film), 선택 필름과 활성 reciprocity profile, Base Shutter, ND, 노출 scale 모드, 가장 최근 도출된 reciprocity 결과 — 는 **활성 카메라 슬롯**에 종속된다. 한 촬영 세션은 다중 슬롯을 보유할 수 있다 ([Requirements](../../../requirements/Requirements.md) §3.8); 어느 시점에서도 정확히 하나의 슬롯이 활성이며 그 입력이 calculator 표면과 결과 섹션에서 시작되는 모든 timer를 driven 한다.

활성 슬롯 전환은 입력 set을 *변경하지* 않고 *교체* 한다:

- 떠나는 슬롯의 calculator 상태는 그 슬롯 자신의 상태로 보존 — 필름, base shutter, ND, scale, reciprocity 결과를 그대로 유지.
- 도착하는 슬롯의 이전 저장 상태가 calculator의 활성 입력이 되며, 결과 섹션은 그 입력에 대해 재계산.
- 한 번도 방문하지 않은 슬롯은 fresh 앱 launch와 동일한 default로 도착; 슬롯을 방문하는 동작이 다른 슬롯의 상태를 소비하지 않는다.

전환은 calculator / 필름 선택 / reciprocity 결과 어디에서도 "reset" 또는 "clear" 경로를 호출하지 않는다. 슬롯은 독립적: 활성 슬롯에 가하는 calculator 입력 변경 — Base Shutter 이동, ND 변경, 다른 필름 선택, profile swap — 은 활성 슬롯 상태에만 영향.

위 규칙은 입력 종속(scoping) 만을 기술. 계산 정책 (§2, §3)은 변경되지 않는다 — 모든 슬롯은 자기 입력을 같은 노출 math와 같은 reciprocity 정책에 대해 평가한다.

---

## 2. Stop 기반 노출 math

### 2.1 단위

모든 노출 조정 math는 **stop 공간** (밑이 2 인 로그)에서 수행. 한 stop = 빛이 두 배 변함. Shutter target은 다음으로 계산:

```
output_seconds = base_seconds × 2^stops
```

ND 값은 stop. 출시 ND ladder는 whole-stop (§2.2); fractional-capable `NDStep` 도메인 primitive는 미래 custom / variable-ND workflow용 향후 확장을 위한 인프라 (§1.4)로 유지되며 출시 ND picker에 노출되지 않음. Factor 형태로 들어오는 입력 (예: ND 64×)은 calculator 진입 전 stop으로 변환되어야 한다.

### 2.2 ND 입력 범위

ND picker는 모든 출시 모드에서 **[0, 30] 닫힌 구간의 정수 stop**을 제시. One-third-stop은 Base Shutter ladder 에만 적용 (§1.4); ND ladder는 실제 fixed ND 필터가 whole-stop 강도 (ND2 = 1, ND4 = 2, ND8 = 3, …)로 판매되기 때문에 whole-stop 유지. Picker 행은 `0, 1, 2, …, 30` — `1/3, 2/3, 7 1/3, 7 2/3` 같은 fractional 값은 출시 ND option set에 **포함되지 않으며**, view 레이어에서 필터링하지 않는다 (option list 자체에 존재하지 않는다). `[0, 30]` 범위 밖 값은 picker를 통해 표현 불가능.

Fractional-capable `NDStep` 도메인 primitive (와 정수 `thirdStopCount` persistence round-trip)는 미래 custom / variable-ND workflow용 향후 확장을 위한 인프라 (§1.4); 명시적 제품 결정 없이 출시 ND picker에 노출되지 않는다.

### 2.3 Base shutter 값

Base Shutter picker는 19-value full-stop 참조 (`1/8000 … 30 s`)의 각 인접 쌍 사이에 두 개의 중간 step을 기하평균 비율 `2^(1/3)`, `2^(2/3)`로 삽입한 **1/3-stop 조밀화 ladder**를 제시. Full-stop 참조는

```
1/8000, 1/4000, 1/2000, 1/1000, 1/500, 1/250, 1/125,
1/60, 1/30, 1/15, 1/8, 1/4, 1/2,
1, 2, 4, 8, 15, 30   (초)
```이며, 조밀화된 ladder는 같은 범위에 걸쳐 55개 entry를 생성. Picker 행은 카메라 표기 라벨로 렌더링 (예: `1/8000, 1/6400, 1/5000, 1/4000, …, 1/30, 1/25, 1/20, 1/15, 1/13, 1/10, …, 1/2, 1/1.6, 1/1.3, 1s, 1.3s, 1.6s, 2s, 2.5s, 3s, 4s, …, 25s, 30s`) — 사진가가 카메라 다이얼에서 읽는 값과 일치. 내부 canonical seconds는 기하평균 값 그대로 유지; 계산은 stop-step index로 진행.

1초 미만 값은 reciprocal 분수 (`1/N`, slow end `1/3, 1/2.5, 1/2, 1/1.6, 1/1.3` 포함)로 렌더링하고 `s` suffix를 붙이지 않음. 1초 이상 값은 카메라 관습대로 정수 또는 `N.Ns`로 렌더링. 자유 텍스트 입력은 미수용; picker가 유일한 입력 경로.

Reserved full-stop scale (§1.4)은 19개 full-stop 값을 직접 제시; 해당 영역은 현재 테스트와 미래 Settings preference 용으로만 사용.

### 2.4 Snap-to-full-stop 출력 규칙

시스템이 출력 셔터를 계산할 때, snap-to-output 정책은 **활성 노출 scale과 ND step으로 게이팅**. Snap은 **둘 다** 만족할 때만 적용:

- 활성 scale이 예약된 full-stop scale (§1.4)이며,
- ND 값이 whole-stop boundary에 위치.

출시 one-third-stop scale 에서는 fractional 입력에 대해 두 조건이 모두 성립하지 않고 picker는 1/3 stop 단위로 진행하므로 snap은 적용되지 **않음**: 1/3-stop 입력을 full-stop ladder로 도로 collapse 하면 더 미세한 scale의 목적이 사라짐. 계산값은 직접 보고됨 (시간 표시는 [UI Spec](UI.md) §2.4의 규칙으로 포맷).

Snap이 적용될 때 (예약된 full-stop scale + whole-stop ND), 시스템은 표기 관습성을 위해 full-stop 참조 scale에서 도출된 값을 보고:

- 결과가 **1/8000 .. 30 s** 범위 *안* 이면 19 참조값 중 가장 가까운 값으로 snap.
- 30 s 이상이면 시스템은 **power-of-two** sequence로 step — snap 된 값은 계산값을 둘러싼 인접한 두 power-of-two 중 더 가까운 값 (64, 128, 256, …). "60, 120, 240" 십진 doubling이 아님: 60 s는 64 s로 round, 60 s로 보고되지 않음.
- 30 s 경계를 가로지르면, 30 s 위 다음 표시 값은 **64 s** (즉 post-30 s sequence는 30 → 64 → 128 → 256 → …). 30..64 s 갭 안에서 snap target은 30 또는 64 중 계산값에 더 가까운 것.

(snap 없는) "exact" 계산값은 snap 표기와 함께 보존되어, 하류 timer 로직이 정확한 숫자를 사용하고 UI는 관습적 표기를 보여줌. **1 s 미만** 에서는 시스템이 round 된 reciprocal 표기 (예: "1/30")를 사용 가능 — 정확한 값이 0.0327 일 때도. **1 s 이상** 에서는 시스템이 계산값을 round 하지 않음: 2.13 s 결과는 timer가 사용할 때 2.13 s로 유지 — 관습적 표기 "2 s" 로 보일지라도.

### 2.5 방향

ND 조정은 forward 또는 reverse로 실행:

- **Forward (ND 입력으로)** — Base Shutter + stop count가 주어지면 Output Shutter 계산.
- **Reverse (ND 출력으로)** — Base Shutter + target Output Shutter가 주어지면 필요한 stop count 계산.

두 방향 모두 같은 stop-공간 math 사용.

---

## 3. Reciprocity 보정 (film workflow)

필름 선택 시, 시스템은 ND-조정된 셔터에 필름의 reciprocity profile을 적용해 Corrected Exposure를 산출한다. Reciprocity는 엄격히 후처리: base 노출 계산에 되돌려지지 않는다.

### 3.1 3-layer 분리

Reciprocity 계산은 layer 분리를 깨끗하게 보존:

- **Domain layer**는 제조사 출판 threshold + formula + limited-guidance rule + 완전한 provenance를 보유, 그리고 (display 전용) source-evidence row를 보유. 어떤 계산 정책도 인코딩하지 않는다.
- **Calculation policy layer**는 도메인 데이터 + 측광 노출을 소비해 명시적 metadata를 가진 구조화된 결과를 산출한다. Source-evidence row는 display 전용이며 의도적으로 정책 layer에 invisible.
- **Presentation layer**는 결과 metadata를 소비해 status / badge 텍스트, 신뢰도 cue, note, 경고를 렌더. 숫자를 invent 하지 않으며 metadata 구분을 flatten 하지 않는다.

### 3.2 평가 순서

측광 노출 `t`에 대해, 정책 layer는 필름의 profile을 다음 순서로 평가. 각 단계는 결과를 산출하고 멈추거나 다음 단계로 넘어간다.

1. **Formula rule** — profile이 formula rule을 정의하면 공유 `ReciprocityFormula` (`Tc = a × (Tm / Tref)^p + b`)를 `t`에서 평가. 공식 자체가 guard를 소유:
   - `t ≤ noCorrectionThroughSeconds` → `corrected = t` + basis = `officialThresholdNoCorrection` 반환.
   - 그 외에는 `evaluate(...)`가 `withinSourceRange(corrected)`, `beyondSourceRange(corrected)`, `invalidInput`, `invalidFormula`, `formulaOutputUnusable`, `unsafeShorteningFormula` 중 하나 반환. 정책은 각각:
     - `withinSourceRange` → `formulaDerived` (보정 노출 동반);
     - `beyondSourceRange` → numeric continuation을 carry하는 `unsupportedOutOfPolicyRange` (값은 `sourceRangeThroughSeconds` 너머의 formula prediction이며 manufacturer guidance가 아닌 outside guidance로 표현);
     - `invalidInput` → 잘못된 측광 입력을 표현하는 `unsupportedOutOfPolicyRange`;
     - `invalidFormula` → parameter contract 위반을 표현하는 `unsupportedOutOfPolicyRange` (PTIMER-84 custom formula가 이 별도 case를 사용);
     - `formulaOutputUnusable` → 런타임 산술 실패를 표현하는 `unsupportedOutOfPolicyRange`;
     - `unsafeShorteningFormula` → `corrected = t`로 `officialThresholdNoCorrection`에 handoff (reciprocity 보정이 셔터를 결코 줄이지 않도록 보장하는 보편 safety net).
2. **Threshold 무보정** — 독립 threshold rule을 여전히 가지는 profile (limited-guidance 모양)에 한해, `t`가 threshold 안에 있으면 `corrected = t` + basis = `officialThresholdNoCorrection` 반환.
3. **Limited guidance** — profile이 `t`를 cover하는 (또는 open-ended) `appliesWhenMetered`의 limited-guidance rule을 정의하면 `limitedGuidanceNoQuantifiedPrediction` 반환. 숫자 보정 노출 없음.
4. **Unsupported 대체** — 어떤 rule도 적용되지 않으면 보정 노출 없이 `unsupportedOutOfPolicyRange` 반환.

`sourceRangeThroughSeconds`는 **source / fitting confidence boundary**이지 calculation hard stop이 아니다 — 모든 공식은 그 너머에서도 숫자 값을 산출하고 (위 1단계 안전 검사 적용), 결과는 억제되는 대신 beyond-source 표현으로 reclassify 된다.

1단계의 `unsafeShorteningFormula` handoff가 보편 **correction invariant**다: 보정 노출이 측광 값보다 짧으면 identity로 치환. Reciprocity 보정은 adjusted shutter를 절대 줄일 수 없으며, safety net이 공식 곡선이 자신의 no-correction 경계를 넘는 edge case에서도 그 보장을 유지한다.

### 3.3 결과 형태 + metadata

각 reciprocity 평가는 세 mutually-exclusive form 중 하나의 결과를 산출한다:

- **Quantified** — 숫자 보정 노출이 반환. 결과는 측광 노출 + 보정 노출 + 아래 metadata block을 포함. Basis는 `officialThresholdNoCorrection` 또는 `formulaDerived`.
- **Limited-guidance** — 숫자 보정 노출은 반환 불가, 하지만 시스템은 측광 노출 + metadata block을 보고. Basis는 `limitedGuidanceNoQuantifiedPrediction`. Presentation layer는 숫자 대신 차분한 안내 텍스트를 렌더.
- **Unsupported** — 측광 노출이 정책 지원 범위 외부. 결과는 측광 노출 + metadata block을 포함. Basis는 `unsupportedOutOfPolicyRange`. 공식 기반 profile이 supported boundary 너머에서 numeric continuation을 산출한 경우에만 옵션 보정 노출 존재; presenter가 outside manufacturer guidance로 mark.

Form과 basis의 페어링은 *구조적* — 런타임 검사가 아닌 컴파일 타임에 강제. 따라서 결과가 숫자 보정값을 claim 하면서 그것을 omit 하는 것이 불가능 (위의 source range 외부 formula prediction을 동반하는 unsupported 단일 예외만 허용).

세 form 모두에 존재하는 metadata block은 포함:

- `calculationBasis` — `officialThresholdNoCorrection`, `formulaDerived`, `limitedGuidanceNoQuantifiedPrediction`, `unsupportedOutOfPolicyRange` 중 하나.
- `sourceAuthorityImpact` — profile provenance (current official / archival official / unofficial secondary / user-defined)에서 derive.
- `rangeStatus` — `withinStatedRange`, `beyondLastRepresentativePoint`, `beyondPolicyLimit`.
- `warningLevel` — `none`, `note`, `caution`, `strongWarning`.
- `notes` — token-tagged 사람-읽기 문자열 배열.

### 3.4 Reference 데이터 presentation

Reference panel은 profile에 attach 된 source 데이터를 surface. 표현 규칙은 source 사실 보존에 관한 것 — 계산이 아니다:

- 양쪽 form (stop / multiplier + adjusted/corrected time)을 carry 하는 source-evidence row는 둘 다 surface. 한 값을 골라 다른 것을 drop 하는 formatter는 published source 정보를 사용자에게서 숨긴다.
- Row의 compact column은 둘 다 존재할 때 한 cell에 두 사실 결합 (예: `+0.5 stops · 15s`). 한 형태만 출판되면 그것만 표시.
- 카탈로그가 `isApproximate`로 저장한 corrected-time 값 (비합리적 변환의 rounded display, 보통 fractional-stop derivation `metered × 2^stopDelta`)은 시각적으로 구분 — 예를 들어 leading `≈` — 사용자가 한눈에 published 또는 정확히 변환된 anchor와 rounded 것을 구별. Multiplier-derive corrected time (`metered × multiplier`)은 정확한 산술 — mark 되지 않음.
- `isSourceEvidenceOnly`로 mark 된 source-evidence row는 published evidence로 보존되지만 `*` footnote marker로 렌더 — 사용자가 row가 formula-fitting anchor로 사용되지 않음을 인식 (ADOX CMS 20 II의 sub-1s reference가 canonical case).
- 현상 시간 hint + 컬러 필터 권고는 보정 노출 column에 fold 되지 않고 별도 cell / note로 유지. 이들은 documentation이지 계산 입력 아님.
- Reference panel은 새 계산 정책을 도입하지 않는다. 계산 정책이 이미 consume 하는 데이터 (threshold + limited-guidance rule) 또는 의도적으로 무시하는 데이터 (source-evidence row)에 대한 presentation contract.
- PTIMER-88 보조 안내 formatter는 presentation layer 전용. 저장된 표기 정확히 보존 (예: `5M`, `7.5M`, `2.5G`, `CC10R`, `-10% development`) — 텍스트 normalize 안 함. 안내를 별도 카테고리로 매핑: 컬러 보정, 현상 조정, 경고, note. 노출 시간 출력은 primary calculator 결과 유지; 이 row는 보조 안내 전용.

### 3.5 Confidence presentation

Presentation layer는 각 결과를 다음 네 신뢰도 카테고리 중 하나로 매핑:

- **No correction** — basis = `officialThresholdNoCorrection`. 보정 노출 = 측광 노출. User-facing label: `No correction`.
- **Formula-derived** — basis = `formulaDerived`. 결과는 활성 계산 곡선에 anchor. User-facing label: `Formula-derived`.
- **Limited guidance** — basis = `limitedGuidanceNoQuantifiedPrediction`. User-facing label: `No quantified prediction`. UI는 숫자 대신 차분한 설명 텍스트 표시; 근거 없는 값을 만들지 않는다.
- **Unsupported** — basis = `unsupportedOutOfPolicyRange`. User-facing label은 supported range 외부의 formula prediction 가용 여부에 따라: 출판된 source range 외부의 converted formula profile (sourceEvidence 포함 formula rule)이면 `Beyond source range`, 그 외 numeric continuation이면 `Outside guidance`, 값 자체가 없으면 `No corrected value`.

카테고리와 badge 문구는 launch preset reciprocity presentation에서 `Exact`, `Estimated`, `Interpolated`, `Extrapolated`, `Advisory`를 primary status / badge 텍스트로 surface 하지 않는다 — 이 용어들은 legacy table 모델을 인코드 했으며 현 vocabulary에 포함되지 않는다.

### 3.6 Target Shutter 비교 (optional, post-reciprocity)

Target Shutter는 사진가가 지정한 목표 duration을 calculator의 현재 결과와 비교하기 위한 optional workflow. 계산 정책 (§2)과 reciprocity 정책 (§3.1–§3.5) 위에 겹쳐 적용된다 — target의 enabling, disabling, editing은 두 정책 어느 쪽에도 되돌아가지 않으며 이미 확정된 결과를 변경하지 않는다.

**비교 기준.** 비교 기준은 workflow에 따라 결정된다:

- **Non-film workflow** — 비교 값은 Adjusted Shutter다.
- **quantified 보정 노출이 있는 film workflow** — 비교 값은 Corrected Exposure다.
- **quantified 보정 노출이 없는 film workflow** (limited-guidance 또는 unsupported, §3.3) — 비교 값은 사용할 수 없다.

**Stop 차이 표시.** 비교 값이 존재할 때 시스템은 target duration과 비교 값 사이의 stop 차이를 표시한다. 표시되는 stop 차이는 앱의 stop 표시 단위로 반올림한다; 0으로 반올림되는 차이는 *match* 형태로 표시 (signed zero 대신). 비교 값이 없을 때 시스템은 근거 없는 stop 차이를 만들지 않으며, target은 그대로 표시된 채 행은 차분한 unavailable 표시를 한다.

**Target 안정성.** Target duration은 base shutter, ND, 필름 선택, reciprocity 정책 결과가 변해도 고정 유지; 비교 값만 갱신된다. Target 자체 편집이 변경의 유일한 경로.

**슬롯 종속.** Target Shutter 상태는 다른 calculator 입력과 같은 조건으로 활성 카메라 슬롯에 종속 (§1.5). 활성 슬롯 전환은 슬롯의 나머지 입력과 함께 target을 교체한다; 비활성 슬롯에 저장된 target은 다른 슬롯에 노출되지 않는다.

---

## 4. Timer 통합

Timer는 **Output Shutter** (digital workflow), **Corrected Exposure** (film workflow), 또는 **Target Shutter** (설정된 경우, §3.6)에서 생성. 시스템은 limited-guidance 보정 노출에서 timer를 시작하지 않는다 — 결과가 `limitedGuidanceNoQuantifiedPrediction`, 또는 numeric continuation 없는 `unsupportedOutOfPolicyRange` 일 때 Film 모드 corrected-exposure timer affordance는 비활성화되며, 사용자는 입력을 변경하거나 ND-조정된 셔터로 명시적으로 진행하도록 안내. Supported range 외부의 formula prediction을 동반하는 unsupported numeric (공식이 source-range boundary 너머에서 값을 계속 산출하는 경우)은 warning treatment와 함께 timer를 활성화 — 사용자가 예측값을 commit 할 수 있게. Target Shutter에서 시작된 timer의 duration은 target 자체이며, 비교 값의 가용 여부와 무관.

Timer의 metadata는 생성 시점의 계산 결과 snapshot. 후속 calculator 입력 변경은 이미 생성된 timer를 변경하지 않는다. Timer의 exposure source는 유지되는 동안 구별 유지된다 — Target Shutter timer는 후속 입력 변경에 무관하게 Target Shutter timer로 남는다. ([Timer Spec](Timer.md) §1.4 참조.)

---

## 5. 재시작 가로지른 복원

Calculator의 working context — 선택된 필름 identity + **노출 scale 토큰** (§1.4) + Base Shutter + ND 값 + 설정된 경우 Target Shutter duration (§3.6) — 는 digital + film 양 workflow에서 영속화 + 재시작 시 복원. Working context는 카메라 슬롯별로 종속 (§1.5) — 모든 슬롯의 상태와 활성 슬롯 id가 함께 보존되며, 다중 슬롯 세션의 on-disk 형태는 [DomainSchema Spec](DomainSchema.md) §7.4에 기술. 저장된 preset identity가 어떤 catalog entry로도 resolve 되지 않거나 활성 scale의 ladder에 대한 숫자 값 검증이 실패면, 시스템은 정의된 default로 안전하게 대체 (crash 또는 silent drift 아님).

노출 scale 토큰 (또는 fractional ND) 등장 이전 release에서 작성된 snapshot도 정상 복원: 누락된 필드는 **출시 one-third-stop scale** (§1.4)로 resolve 되고, 정수 ND 값은 새 ladder의 whole-stop count로 처리됨. 출시 ladder는 legacy full-stop ladder의 strict superset 이므로 legacy whole-stop 값을 다시 쓸 필요 없이 유효한 ladder entry로 유지됨. 다중 슬롯 세션이 등장하기 이전 release에서 작성된 snapshot도 마찬가지로 정상 복원: 첫 launch 시 legacy 단일 컨텍스트 형태를 읽고, 이후 저장은 다중 슬롯 세션 형태로 작성된다 ([DomainSchema Spec](DomainSchema.md) §7.4.1 참조).

---

## 6. Forbidden patterns

시스템은 다음을 **하지 않는다**:

1. 결과가 limited-guidance 일 때, 또는 numeric continuation 없는 unsupported 일 때 숫자 보정값을 근거 없이 만들어내기. Supported range 외부의 numeric formula prediction은 허용되며 outside manufacturer guidance로 표시.
2. 도메인 모델 안에 계산 정책을 인코딩. (도메인은 제조사 데이터를 verbatim으로 저장; 정책은 자체 layer.)
3. Source-evidence row (display reference 데이터)를 계산 anchor로 promote.
4. Reciprocity 보정이 adjusted shutter를 줄이도록 허용. `corrected < metered`를 산출하는 어떤 rule path든 `officialThresholdNoCorrection`으로 reclassify (§3.2 correction invariant).
5. 1 s 이상 계산값 round. (Round 표기는 sub-second 에서만 허용.)
6. Calculator 입력 변경이 이미 생성된 timer의 metadata를 mutate.
7. Limited-guidance 보정 노출, 또는 numeric continuation 없는 unsupported 결과에서 timer 시작.
8. 활성 workflow에 quantified 비교 값이 없을 때 Target Shutter stop 차이를 근거 없이 만들기. 행은 대신 차분한 unavailable 표시를 한다.
9. Signed-zero Target Shutter stop 차이 표시; 0으로 반올림되는 차이는 *match* 형태로 collapse (§3.6).
10. Launch preset reciprocity presentation에서 `Exact`, `Estimated`, `Interpolated`, `Extrapolated`, `Advisory`를 primary user-facing status / badge 문구로 surface.

---

## 7. Drift + 미해결 질문

미해결 또는 부분 명세. 시스템이 의도에서 silently 더 drift 하지 않도록 기록.

- **Aperture + ISO** 노출 변수는 intent-level (wiki 3964929) 이지만 현 release에 포함 안 됨. Fixed/Derived 상태 머신, 다중 변수 linkage 규칙, 한 변수 이상 가로지른 reverse 계산은 유보.
- **두 개 위 multi-derived ceiling.** Wiki 3964929가 확장 옵션 예약 — 결정 기록 없음.
- **Outside-source-range prediction cap.** `sourceRangeThroughSeconds`를 가진 공식은 경계 너머에서도 numeric continuation을 산출한다 (경계는 source/fitting confidence marker이지 hard stop이 아니다). Profile-independent ceiling이 이 prediction을 얼마나 멀리 확장하도록 cap 할지는 open.
- **사용자 정의 필름 schema.** Wiki 15138817이 검증 요구사항으로 list — 데이터 모델과 UX는 명시 안 됨. 향후 custom table 입력도 launch preset scope 외부이며 자체 feature 설계가 필요하다.
- **다중 profile 필름.** 일부 필름은 다중 official profile 가질 수 있음 (다른 현상액, push/pull). 선택 규칙은 아직 정의 안 됨; 현 launch 정책은 필름 identity 당 한 primary profile ship.
- **First-class 컬러 / 현상 정책.** Profile이 이를 source-evidence adjustment로 기록 (예: Velvia 50 `5M`, Tri-X 400 `-10% development`) but spec은 calculator가 display 너머로 어떻게 promote 할지 아직 정의 안 됨.

---

## 8. Sources of intent (참고)

이들은 *참고 자료*이며 normative가 아니다. 위의 spec 본문이 사용자 대면 contract; 아래 인용은 reader가 *왜* 특정 표현이 선택됐는지 trace 할 수 있게 한다.

**Wiki (페이지 id 인용)**
- 3964929 — 계산 엔진 규칙 (변수, fixed/derived 상태, ND 정책, reciprocity 적용 흐름)
- 7438337 — 노출 스톱 스케일 관행 조사 (rounded-notation vs exact-value 분리)
- 13172737 — Reciprocity Film Research List (launch scope, method keys, provenance 규칙)
- 15237121 — Reciprocity Table Calculation Policy Notes (historical: PTIMER-128 / PTIMER-140의 공식 기반 prediction 모델로 대체된 table-interpolation 정책을 기록)
- 15761409 — Reciprocity Table Interpolation and Calculation Policy Draft (historical: 15237121과 동일 상태)
- 15138817 — Reciprocity Validation Samples (최소 검증 매트릭스, 예시 profile)
- 16482307 — Film Selection and Reciprocity Calculator UI (workflow 방향, state semantics)

