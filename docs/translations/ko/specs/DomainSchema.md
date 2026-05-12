# Domain Schema Spec

> **Locale mirror.** 본 파일은 `docs/specs/DomainSchema.md`의 한국어 mirror. 표현 분쟁이 있을 때 영문판을 canonical로 본다.

**도메인**: 필름 identity, reciprocity profile, 제조사 규칙, launch preset 카탈로그 뒷단의 데이터 모델.

본 문서는 도메인의 **모양과 의미**를 명세 — 어떤 필드가 존재하고, 무엇을 의미하며, 어떤 invariant가 유지되는가. 인코딩 형식 (JSON, union 타입에 `kind` discriminator)은 §11에 기록된 직렬화 디테일; spec 본문은 플랫폼 + 직렬화기 중립.

---

## 1. Top-level entities

도메인은 세 primary 타입을 가진다:

- **Film identity** — 필름 stock의 안정된 식별자 + identity-level metadata.
- **Reciprocity profile** — 그 필름이 장노출 시간에 어떻게 반응하는지 기술하는 제조사 출판 또는 사용자 정의 dataset. 한 필름은 하나 이상의 profile 포함한다; launch dataset은 필름 당 정확히 한 profile ship.
- **Launch preset 카탈로그** — 앱과 함께 ship 되는 필름 identity의 bundled 모음.

계산 결과 (측광 노출에 대한 profile 평가의 출력)도 영속화되고 round-trip 되므로 도메인의 일부 — §6에 명세.

---

## 2. Film identity

### 2.1 필수 필드

- **id** — 비-empty 문자열, 카탈로그 안에서 unique. 안정된 식별자; 사용자 대면 UI는 결코 표시하지 않음. 영속화 reference의 key.
- **kind** — 다음 중 하나:
  - `preset` — bundled launch dataset entry.
  - `custom` — 사용자 정의 entry (유보; §12 참조).
  - `unknown` — forward-compatible decoding 만을 위해 존재; 결코 쓰이지 않음.
- **canonicalStockName** — 비-empty, 카탈로그 안에서 unique. 필름의 display-default 이름. 예: `"Kodak TRI-X 400"`, `"ILFORD HP5 Plus"`.
- **manufacturer** — 알려진 경우 원래 제조사 문자열. Repackaged 브랜드 라벨 (다른 라벨로 판매되는 필름)은 여기 등장하지 않음 — `brandLabel`에 위치.
- **productionStatus** — `current`, `discontinued`, `unknown` 중 하나. Launch dataset entry는 `current` 가짐.
- **profiles** — [reciprocity profile](#3-reciprocity-profile) 배열. Launch dataset은 identity 당 정확히 한 entry.

### 2.2 옵션 필드

- **brandLabel** — 필름이 판매되는 secondary 브랜드 문자열 (예: 제조사-rebranded variant).
- **aliases** — 같은 필름을 가리키는 것으로 알려진 대체 이름 배열.
- **userMetadata** — 사용자 편집 가능 metadata (§2.3 참조); preset entry 에는 부재.

### 2.3 사용자 편집 가능 metadata

비-preset (또는 사용자 augmented) identity에 대해:

- **displayNameOverride** — UI에서 `canonicalStockName`를 override 하는 옵션 문자열.
- **tags** — 문자열 배열.
- **notes** — free-form note 문자열 배열.

Preset launch entry는 사용자 metadata를 포함하지 않는다.

---

## 3. Reciprocity profile

Profile은 필름 stock이 장노출 측광값에 어떻게 반응하는지 기술.

### 3.1 필수 필드

- **id** — 비-empty 문자열, 부모 identity의 profile 배열 안에서 unique.
- **name** — 비-empty 문자열. Profile을 surfacing 할 때 display 라벨 (예: "Manufacturer table").
- **source** — provenance metadata (§4 참조).
- **rules** — [reciprocity rule](#5-reciprocity-rules) 배열, 적어도 한 entry. 순서는 계산 정책의 평가 순서가 별도로 정의되는 한도에서만 의미 ([Calculator Spec](Calculator.md) §3.2).
- **notes** — free-form note 문자열 배열 (보조 copy로 렌더).

### 3.2 옵션 필드

- **userMetadata** — §2.3와 평행한 사용자 편집 가능 필드, 본 profile에 scoped. Preset profile 에는 부재.

---

## 4. Source provenance

모든 reciprocity profile은 provenance 포함:

- **kind** — `manufacturer_published`, `manufacturer_secondary` (예: 라이센시를 통해 재발행된 데이터 시트), `vendor_published`, `community_field_tested`, `historical_archive` 중 하나. Launch dataset은 `manufacturer_published`만 사용.
- **authority** — `official`, `field_tested`, `anecdotal` 중 하나. Launch dataset은 `official`만 사용.
- **confidence** — `unknown`, `high`, `medium`, `low` 중 하나. 생략의 default는 `unknown`. Launch dataset은 `high` 사용.
- **publisher** — 필수 비-empty 문자열 (데이터를 출판한 entity, 예: `"Kodak"`, `"ILFORD HARMAN"`).
- **title** — 특정 문서 또는 페이지 참조 옵션 문자열.
- **citation** — 더 정확한 reference (URL, 페이지 번호)가 있는 옵션 문자열.
- **sourceVersion** — 출판된 edition 또는 revision 식별 옵션 문자열.

Provenance 필드는 source에서 verbatim 보존. 시스템은 갭을 채우기 위해 provenance를 합성하지 않는다 — 누락된 옵션 필드는 부재 유지. (Wiki 13172737)

---

## 5. Reciprocity rules

Profile의 동작은 하나 이상의 rule로 표현. Rule은 네 variant의 tagged union:

### 5.1 Threshold rule

보정이 적용되지 않는 영역을 표시.

- **noCorrectionRange** — 보정 시간 = 측광 시간인 측광값을 기술하는 [time range](#7-reciprocity-time-range).
- **adjustments** — threshold band 외부의 안내 전용 조정 배열 (정보용 — 계산 정책은 quantified rule로 해석하지 않는다).
- **notes** — free-form note 배열.

예: `Kodak PORTRA 400`은 ~1 s 미만 무보정 보고; 그 너머 제조사 안내는 "조건 하 시험" (advisory, 비-quantified).

### 5.2 Formula rule

closed-form 보정 표시.

- **meteredRange** — 공식의 도메인을 제약하는 옵션 [time range](#7-reciprocity-time-range). Open-ended `meteredRange`는 "계산 정책이 공식 단계에 도달하는 곳마다 적용" 의미.
- **formula** — 유일하게 정의된 공식 형태는 **지수 power** 형태: `T_c = T_m^P` + 옵션 계수 + offset (`T_c = coefficient × T_m^exponent + offsetSeconds`). 구조는 투명성을 위해 source의 출판된 등식 문자열 포함.
- **additionalAdjustments** — 계산이 소비하지 않는 보충 조정 배열 (예: 현상 시간 hint).
- **notes** — free-form note 배열.

예: `ILFORD HP5 Plus`는 `T_m > 1 s`에 대해 `T_c = T_m^1.31` 사용.

### 5.3 Table rule

이산 측광 → 보정 샘플 점 set 표시.

- **entries** — 비-empty entry 배열, 각 entry는:
  - **meteredExposure** — [측광 노출 selector](#8-metered-exposure-selector) (정확한 초 값 또는 범위).
  - **adjustments** — 그 점에서의 보정을 기술하는 비-empty [노출 조정](#9-exposure-adjustment) 배열.
  - **notes** — 그 표 row에 attached 된 free-form note 배열.

단일 entry의 조정은 estimation family를 mix 하지 않는다 — row는 `correctedTime` 스타일 조정 또는 `stopDelta`/`multiplier` 스타일 조정 둘 다가 아닌 하나만 사용. ([Calculator Spec](Calculator.md) §3.3)

예: `Kodak TRI-X 400` 표: 1 s → +1 stop (보정 2 s, dev −10%); 10 s → +2 stops (보정 50 s, dev −20%); 100 s → +3 stops (보정 1200 s, dev −30%).

### 5.4 Advisory rule

비-quantified 안내만 있는 영역 표시.

- **range** — advisory가 적용되는 [time range](#7-reciprocity-time-range).
- **severity** — `caution`, `not_recommended` 중 하나. `not_recommended`는 stop signal ([Calculator Spec](Calculator.md) §3.2 step 3 참조).
- **guidanceText** — 제조사 advisory wording을 담는 비-empty 문자열.

예: `Fujifilm Velvia 50`은 64 s에서 `not_recommended` advisory 포함한다.

---

## 6. Calculation result (영속화됨)

계산 정책이 결과를 산출할 때, 결과는 영속화 round-trip 가능하므로 도메인의 일부. ([Calculator Spec](Calculator.md) §3.5)

결과는 세 mutually-exclusive form 중 하나:

- **Quantified** — 보정 노출이 산출됨. metadata block (아래 참조) + `correctedExposure` payload (초 단위 reciprocity 시간 값)을 포함한다.
- **Advisory-only** — 안내는 가능 but quantified 시간 없음. metadata block을 포함; `correctedExposure` 필드 없음.
- **Unsupported** — 이 측광 점에 대한 안내 없음. metadata block을 포함; `correctedExposure` 필드 없음.

모든 form이 포함하는 metadata block:

- **calculationBasis** — 다음 중 하나: `exact_table_point`, `interpolated_within_table`, `extrapolated_beyond_table`, `official_threshold_no_correction`, `advisory_only_beyond_official_range`, `unsupported_out_of_policy_range`, `formula_derived`.
- **sourceAuthorityImpact** — profile의 provenance에서 derive.
- **rangeStatus** — `within_table`, `extrapolated`, `threshold_only`, `beyond_guidance`.
- **warningLevel** — `none`, `caution`, `advisory`, `not_recommended`.
- **supportingNotes** — 사람 읽기 문자열 배열.
- **usedReferencePoints** — 결과를 inform 한 row 또는 공식 계수에 대한 reference 배열.

`correctedExposure`의 존재는 form (Quantified vs Advisory-only/Unsupported)으로 구조적 결정 — form이 보정 노출을 claim 하면서 payload가 없거나 (그 반대) 인 결과는 구성상 표현 불가능.

---

## 7. Calculator working context (영속화됨)

Calculator 화면에서 사용자가 설정한 입력 — 이 도메인의 일부 — 은 앱 재시작에서 살아남도록 persistence를 round-trip. ([Calculator Spec](Calculator.md) §5; [Requirements](../requirements/Requirements.md) FR-5.2)

Working-context snapshot이 포함하는 항목:

- **filmId** — optional 문자열, 선택된 필름 식별. 카탈로그 (§2)에서 resolve. 부재 ⇒ digital workflow.
- **baseShutterSeconds** — 음이 아닌 유한한 숫자; 확정 된 Base Shutter 값. 활성 노출 scale의 셔터 ladder에 대해 복원 시 sanitize (§7.1).
- **ndStop** — `[0, 30]`의 음이 아닌 정수, optional; whole-stop ND 값. 영속화된 ND가 whole-stop 경계에 위치할 때 존재; fractional 일 때 부재 (§7.2).
- **ndStopThirds** — 음이 아닌 정수, optional; 영속화된 ND 값을 1/3-stop 카운트로 표현 (`0 ⇒ 0 stops`, `1 ⇒ 1/3 stop`, `3 ⇒ 1 stop`, `4 ⇒ 1 1/3 stop`, …). 영속화된 ND가 fractional 일 때 존재; whole-stop 값에 대해서도 항상 필드를 emit 하는 release가 작성한 snapshot에서는 (`ndStop × 3`과 동등하게) 함께 존재 가능.
- **exposureScaleMode** — optional 문자열 토큰, 활성 노출 scale 식별 (§7.3). 부재 ⇒ 출시 one-third-stop scale.
- **activeCameraSlotIDRaw** — optional 문자열, 이 snapshot이 기술하는 calculator 상태가 어느 카메라 슬롯에 속하는지의 raw 식별자. Forward-compatibility 주석 전용: 다중 슬롯 세션 snapshot (§7.4)이 부재할 때 단일 컨텍스트 형태만 읽을 수 있는 이전 release도 올바른 슬롯 연결을 복원할 수 있도록 존재. 부재 ⇒ default 슬롯 연결. 슬롯 세션 상태의 active source of truth는 §7.4 — 컨텍스트 snapshot의 이 주석은 대체.

### 7.1 스키마 진화 + 하위 호환

Snapshot shape는 하위 호환 추가만으로 진화 ([Requirements](../requirements/Requirements.md) NFR-S.2). `ndStopThirds` 또는 `exposureScaleMode` 등장 이전 snapshot도 정상 복원:

- `ndStopThirds`가 없는 snapshot은 영속화된 ND 값에 대해 `ndStop`으로 대체 — 활성 scale의 ND ladder에서 whole-stop count로 처리.
- `exposureScaleMode`가 없는 snapshot은 **출시 one-third-stop scale**로 대체. 출시 셔터 ladder는 legacy full-stop ladder의 strict superset 이므로 legacy whole-stop 셔터 값을 다시 쓰지 않고도 유효한 ladder entry로 유지.
- `exposureScaleMode`가 존재하지만 인식되지 않는 snapshot은 decode 실패 대신 출시 one-third-stop scale로 대체.

### 7.2 Fractional ND identity (예약된)

Persistence 레이어는 fractional ND를 `Double`이 아닌 `ndStopThirds` (1/3-stop 정수 카운트)로 표현. 이는 **향후 확장을 위한 도메인 인프라**: 출시 ND picker는 whole-stop만 enumerate ([Calculator Spec](Calculator.md) §2.2) 하므로 출시 정상 상태 snapshot에는 `ndStopThirds`가 기록되지 않는다. 이 필드는 미래 custom / variable-ND workflow가 `Double` drift 없이 정수 identity로 fractional ND를 영속화할 수 있도록 존재; Decoder는 둘 다 존재할 때 `ndStop`을 legacy hint로 취급하고 `ndStopThirds`를 우선.

### 7.3 노출 scale 토큰

`exposureScaleMode`는 활성 노출 scale을 enumerate 하는 문자열 토큰. 출시 토큰은 `"oneThirdStop"` (출시 기본값)와 `"fullStop"` ([Calculator Spec](Calculator.md) §1.4의 미래 Settings preference 용 예약된). 다른 토큰은 예약된.

### 7.4 카메라 슬롯 세션 snapshot

한 촬영 세션은 다중 카메라 슬롯을 포함 할 수 있다 ([Requirements](../requirements/Requirements.md) §3.8; [Calculator Spec](Calculator.md) §1.5). 슬롯 세션 snapshot은 모든 슬롯의 calculator 상태와 활성 슬롯 id를 capture한다 — 재시작이 활성 슬롯뿐 아니라 전체 세션을 복원하도록.

슬롯 세션 snapshot이 포함하는 항목:

- **schemaVersion** — on-disk 형태를 식별하는 음이 아닌 정수. 출시 값은 `1`. Decoder는 알 수 없는 schemaVersion을 거부하고 legacy 단일 컨텍스트 복원 경로 (§7)로 대체 — 현 release가 이해하지 못하는 미래 형식의 snapshot이 세션을 오염시킬 수 없도록.
- **activeSlotID** — 저장 시점의 활성 슬롯 raw 식별자 문자열. 다른 곳에서 사용하는 같은 슬롯 id alphabet으로 resolve (현 release의 `camera1` … `camera4`, [Calculator Spec](Calculator.md) §1.5); 인식되지 않는 값은 load 실패 대신 canonical 첫 슬롯으로 대체.
- **slots** — 사용자가 방문한 슬롯별 (그리고 옵션으로 custom 라벨만 가진 슬롯의) snapshot 배열. On-disk 순서는 결정성을 위해 슬롯 id 정렬; runtime은 순서에 의존하지 않는다.

각 슬롯별 snapshot이 포함하는 항목:

- **slotIDRaw** — 슬롯의 안정된 id alphabet과 일치하는 식별자 문자열. 알 수 없는 id는 decode 시 silently skip — 영속화는 runtime이 resolve 못 하는 슬롯이 존재하는 척하지 않는다.
- **selectedPresetFilmID** — optional 문자열; 슬롯의 선택 필름 카탈로그 id (있을 경우). 카탈로그 (§2)에서 resolve; 어떤 카탈로그 entry와도 더 이상 매칭되지 않는 id는 crash 또는 근거 없는 필름 identity 생성 대신 **No film** (digital workflow)로 복원.
- **selectedProfileID** — optional 문자열; 선택 필름 위의 활성 reciprocity profile override id. 필름의 profile 배열 (그리고 bundled non-launch profile 레지스트리, §13.4)에 대해 resolve. 더 이상 resolve 되지 않는 id는 override를 silently drop 하고 슬롯은 필름의 primary profile로 복원.
- **baseShutterSeconds** — optional 음이 아닌 유한한 숫자; 슬롯의 확정 된 Base Shutter 값. 활성 노출 scale의 셔터 ladder에 대해 복원 시 sanitize; 부재 또는 invalid 값은 출시 기본값 Base Shutter로 복원.
- **ndStop** / **ndStopThirds** — calculator working context (§7 / §7.2)와 동일한 규약과 우선순위: fractional-aware `ndStopThirds`가 우선, `ndStop`은 legacy hint 취급.
- **exposureScaleMode** — §7.3과 같은 규약을 따르는 optional 문자열 토큰; 부재 ⇒ 출시 one-third-stop scale.
- **customDisplayName** — 사진가가 지정한 슬롯 표시 라벨 (optional). Write 시점에 trim; 빈 / whitespace-only 값은 부재로 영속화 — 복원된 슬롯이 canonical *Camera N* default로 대체 하도록. 슬롯 rename은 이 필드만 변경; 슬롯의 안정된 id와 슬롯별 calculator 입력은 영향받지 않는다.
- **targetShutterSeconds** — 슬롯의 확정된 Target Shutter duration (optional 0보다 큰 유한한 값, [Calculator Spec](Calculator.md) §3.8). 부재, 유한하지 않거나 0 이하인 값은 슬롯에 target 없음으로 복원된다. 슬롯별 target 영속화는 세션 전역 last-used target 메모리를 초기값으로 사용하지 않아야 한다 — 그렇게 하면 한 슬롯의 값이 다른 슬롯에 표시된다.

#### 7.4.1 Legacy 단일 컨텍스트 snapshot 으로부터의 마이그레이션

복원 시 슬롯 세션 snapshot (§7.4)이 source of truth. Legacy 단일 컨텍스트 snapshot (§7)은 다중 슬롯 스키마 이전의 세션이 reset 되지 않도록 첫 launch 후 한 번 마이그레이션 source로 read:

- 슬롯 세션 snapshot이 부재할 때 runtime은 legacy 단일 컨텍스트 snapshot 으로부터 복원. 그 `activeCameraSlotIDRaw` 주석이 존재하면 legacy 값들이 속한 슬롯을 가리킴; 부재 ⇒ canonical default 슬롯.
- 마이그레이션 후 첫 save는 슬롯 세션 snapshot을 작성. 이후 launch는 새 snapshot을 read 하고 슬롯 세션 목적으로는 legacy 단일 컨텍스트 store를 무시.
- 슬롯 세션 store가 현 release가 인식하지 못하는 `schemaVersion`의 snapshot을 가지면 load가 nothing을 반환하고 runtime은 legacy 마이그레이션 경로로 대체; 다음 save는 현 스키마로 snapshot을 다시 쓴다.

#### 7.4.2 스키마 진화

슬롯 세션 snapshot은 backward-compatible 추가만으로 진화 ([Requirements](../requirements/Requirements.md) NFR-S.2). Optional 필드 추가 — 예: 위의 `customDisplayName` 또는 `targetShutterSeconds` — 는 `schemaVersion` bump 없이 허용; 그 필드가 없는 이전 snapshot은 그대로 decode (필드는 부재로 처리). Breaking change (기존 필드 rename, 필수 필드 drop, 기존 필드 의미 변경)는 조정된 `schemaVersion` 증가와 문서화된 마이그레이션 단계 없이는 허용되지 않는다.

---

## 8. Reciprocity time range

범위는 측광 노출 값을 bound:

- **minimumSeconds** — 음이 아닌 유한한 숫자.
- **maximumSeconds** — 음이 아닌 유한한 숫자, 또는 부재 / null = "no upper bound".

`maximumSeconds`가 존재할 때 `≥ minimumSeconds` 여야. 경계 시맨틱 (closed vs open)은 자연스러운 read를 따름: 측광값 `t`는 `minimumSeconds ≤ t`이고 (`maximumSeconds` 부재 또는 `t ≤ maximumSeconds`) 일 때 범위 안.

---

## 9. Metered exposure selector

Table rule entry 안에서 row가 어떤 측광값에 적용되는지 식별. 두 variant의 tagged union:

- **exact** — 단일 음이 아닌 유한한 초 값. Row가 그 값에 정확히 매치.
- **range** — [time range](#7-reciprocity-time-range). Row가 범위의 어떤 측광값에도 매치.

같은 table rule 안에서 row의 metered selector는 다른 row의 metered selector와 overlap 하지 않는다.

---

## 10. Exposure adjustment

Entry가 노출을 어떻게 보정하는지 기술하는 tagged union. variant:

- **correctedTime** — `{ meteredSeconds?, correctedSeconds }`. `meteredSeconds`는 옵션 컨텍스트 (원래 측광 점); `correctedSeconds`는 보정 노출. 점 사이 보간 시 **log-log** estimation driving.
- **stopDelta** — `{ stops }`. 보정은 더할 양수 stop 수. 보간 시 **stop-공간** estimation driving.
- **multiplier** — `{ factor }`. 보정은 측광 시간에 대한 양수 scalar multiplier. 보간 시 **stop-공간** estimation driving.

단일 table row의 조정은 한 번에 한 estimation family만 사용. ([Calculator Spec](Calculator.md) §3.3)

---

## 11. 인코딩 (informative)

현재 직렬화는 `camelCase` 필드 이름의 JSON. Tagged union은 `kind` discriminator 필드 사용; variant payload는 variant와 같은 이름의 sibling 필드에 위치. 예시 shape:

```jsonc
// Reciprocity rule (variant: threshold)
{ "kind": "threshold", "threshold": { "noCorrectionRange": { ... }, ... } }

// Exposure adjustment (variant: correctedTime)
{ "kind": "correctedTime", "correctedTime": { "correctedSeconds": 2.0 } }
```

필드 누락 + 명시 `null`은 decode 시 등가로 처리. Encoder는 부재 옵션 필드를 `null` 쓰지 말고 omit. On-disk 형식은 진화 가능 — spec 본문 (§§1–10)이 contract, 인코딩이 아님.

---

## 12. 카탈로그 검증 규칙

bundled launch 카탈로그는 런타임이 받아들이기 전 다음 검사 통과해야.

1. Film identity 배열이 비-empty.
2. 모든 identity가 비-empty `id`, 카탈로그 가로질러 unique.
3. 모든 identity가 비-empty `canonicalStockName`, 카탈로그 가로질러 unique.
4. 모든 identity가 `kind = "preset"`.
5. 모든 identity가 `productionStatus = "current"`.
6. 모든 identity가 정확히 **하나의** profile.
7. 모든 profile의 source가 `kind = "manufacturer_published"`.
8. 모든 profile의 source가 `authority = "official"`.
9. 모든 profile이 적어도 한 rule, 모든 rule이 알려진 variant로 디코드 (no `unknown` `kind` 값).

이 검사들 중 어느 것을 실패하는 카탈로그는 명확한 decode 진단을 출력하고 load 되지 않는다.

---

## 13. Launch dataset scope

의도된 first-wave launch dataset은 **34 필름** (wiki 13172737). 현 bundled 카탈로그는 spec 진화 작업 중 **더 작은 subset** ship; wiki 15138817의 검증 매트릭스가 검증 샘플로 cover 되어야 할 일곱 시나리오 명세 (official formula, official table, color guidance, threshold-only advisory, archival official, 사용자 정의, multi-profile 지원).

현 bundled subset은 검증 매트릭스 시나리오 가로지른 대표 profile 포함. 현 bundle → 34-필름 launch 까지의 경로는 점진적이며 정책 spec와 함께 추적.

### 12.1 카탈로그 외부에 bundled 된 비-launch profile

시스템은 launch 카탈로그 파일 *외부*에 추가 **비-launch profile**을 bundle 가능 — 런타임에 별도 등록. 이들은:

- launch profile과 같은 도메인 shape (§§1–10)을 따름;
- 정직한 provenance 포함한다 — 예를 들어 unofficial practical 공식은 `kind = "community_field_tested"` (또는 등가) + `authority = "unofficial"`로 선언, official 인 척하지 않음;
- 이미 launch (official) primary profile 가진 필름 identity에 *secondary 대안*으로 사용자가 선택 가능;
- §12 launch-카탈로그 validator를 통과하지 않음 (§12 검증 규칙은 launch 카탈로그 파일에만 적용).

예: Kodak PORTRA 400의 unofficial practical 공식 `T_c = T_m^1.34`가 launch 카탈로그 외부에 PORTRA 400의 official threshold-only profile의 secondary 대안으로 bundle.

이 profile의 presentation contract는 [UI Spec](UI.md) §2.1 (명시적 "Official guidance" / "Unofficial practical" 부제) + §2.6 (모든 profile의 details sheet에서 Authority row 표시)에 위치.

---

## 14. Forbidden patterns

도메인은 다음을 **하지 않는다**:

1. 어떤 rule의 데이터 shape 안에 보간 또는 외삽 정책 인코딩. 도메인은 제조사 점을 verbatim 저장; 계산 정책이 해석 결정.
2. 갭을 채우기 위해 provenance 필드 합성. 누락된 옵션 필드는 부재 유지.
3. Repackaged 브랜드 identity와 원-제조사 identity를 한 entry 안에 mix. Repackaging은 원 identity에 대한 `brandLabel` annotation — 평행 record가 아님.
4. 보정 노출을 claim 하면서 값을 포함하지 않거나, 보정 노출 값을 포함하면서 claim 하지 않는 계산 결과 허용. 모순 페어링은 결과의 form으로 표현 불가능.
5. 단일 table row가 *보간 목적*으로 estimation family를 mix 허용. 보간은 row 당 정확히 한 estimation family read — `correctedTime`와 `stopDelta`/`multiplier` 모두 기록되어 있을 때 계산 정책은 `correctedTime` 선택 + 다른 것을 대안 estimation 경로가 아닌 보충 annotation (현상 advisory, color-filter note)으로 처리. Secondary annotation만 기록한 row (예: `stopDelta` + 현상 조정)는 stop-delta family 유지. 금지 케이스는 *모호한 보간* — precedence 규칙 없는 같은 row에 경쟁하는 두 primary estimation family. (Calculator Spec §3.3)
6. Launch preset profile이 사용자 metadata 포함 허용.
7. 카탈로그 검증 무시. 실패하는 카탈로그는 load-time 에러 — soft-warn 아님.
8. 한 필름의 다중 official profile을 한 record로 collapse. (Wiki 15138817이 multi-profile 지원 예약; launch 에서는 identity 당 한 profile만 ship.)

---

## 15. Drift + 미해결 질문

- **사용자 정의 필름 schema.** Wiki 15138817이 검증 요구사항으로 list — 데이터 모델과 UX는 명시 안 됨.
- **Multi-profile 지원.** 도메인이 예약 (한 identity가 다중 profile 가질 수 있음) but 선택 메커니즘 (특정 측광 노출에서 어떤 profile가 "active", push/pull 시맨틱, 현상자별 variant)은 명시 안 됨.
- **컬러 보정 metadata.** Wiki 15138817에 Velvia 스타일 "M color correction" 언급 but schema entry 없음. 현재 (있다면) free-form `notes`로 capture.
- **현상-시간 조정.** 현상-시간 조정 metadata (예: wiki 안내의 Tri-X 스타일 "dev −10%")는 first-class schema 필드로 표현되지 않는다.
- **Launch dataset 성장.** Bundled 카탈로그가 34-필름 wiki target 미달. Spec 형태로 갭 close 위한 우선순위 작업 plan 없음.
- **Repackaging 링크.** Schema가 `brandLabel` + `aliases` 받지만 "이 브랜드 X가 identity Y와 같은 필름" 링크를 런타임 등가 검사에 적합하게 formalize 하지 않음.
- **인코딩 versioning.** 인코딩 (`kind` discriminator의 JSON)은 본 spec에서 informative-only but 카탈로그에 version 필드 없음. 향후 형식 변경에 정의된 마이그레이션 story 없음.

---

## 16. Sources of intent (참고)

본 섹션은 *참고 자료* — 규범 아님.

**Wiki (Confluence page id)**
- 13172737 — Reciprocity Film Research List (launch scope, method keys, provenance 규칙, repackaging 정책)
- 15138817 — Reciprocity Validation Samples (최소 검증 매트릭스, 예시 profile)
- 15237121 — Reciprocity Table Calculation Policy Notes (책임 분리, 유보 항목)
- 15761409 — Reciprocity Table Interpolation and Calculation Policy Draft (책임 분리, metadata, 정책 방향)

