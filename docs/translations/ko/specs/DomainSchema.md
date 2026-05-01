# Domain Schema Spec

> **Locale mirror.** 본 파일은 `docs/specs/DomainSchema.md` 의 한국어 mirror. 표현 분쟁이 있을 때 영문판이 canonical.

**도메인**: 필름 identity, reciprocity profile, 제조사 규칙, launch preset 카탈로그 뒷단의 데이터 모델.

본 문서는 도메인의 **모양과 의미** 를 명세 — 어떤 필드가 존재하고, 무엇을 의미하며, 어떤 invariant 가 유지되는가. 인코딩 형식 (JSON, union 타입에 `kind` discriminator) 은 §10 에 기록된 직렬화 디테일; spec 본문은 플랫폼 + 직렬화기 중립.

---

## 1. Top-level entities

도메인은 세 primary 타입을 가진다:

- **Film identity** — 필름 stock 의 안정된 식별자 + identity-level metadata.
- **Reciprocity profile** — 그 필름이 장노출 시간에 어떻게 반응하는지 기술하는 제조사 출판 또는 사용자 정의 dataset. 한 필름은 하나 이상의 profile carry; launch dataset 은 필름 당 정확히 한 profile ship.
- **Launch preset 카탈로그** — 앱과 함께 ship 되는 필름 identity 의 bundled 모음.

계산 결과 (측광 노출에 대한 profile 평가의 출력) 도 영속화되고 round-trip 되므로 도메인의 일부 — §6 에 명세.

---

## 2. Film identity

### 2.1 필수 필드

- **id** — 비-empty 문자열, 카탈로그 안에서 unique. 안정된 식별자; 사용자 대면 UI 는 결코 표시하지 않음. 영속화 reference 의 key.
- **kind** — 다음 중 하나:
  - `preset` — bundled launch dataset entry.
  - `custom` — 사용자 정의 entry (유보; §11 참조).
  - `unknown` — forward-compatible decoding 만을 위해 존재; 결코 쓰이지 않음.
- **canonicalStockName** — 비-empty, 카탈로그 안에서 unique. 필름의 display-default 이름. 예: `"Kodak TRI-X 400"`, `"ILFORD HP5 Plus"`.
- **manufacturer** — 알려진 경우 원래 제조사 문자열. Repackaged 브랜드 라벨 (다른 라벨로 판매되는 필름) 은 여기 등장하지 않음 — `brandLabel` 에 위치.
- **productionStatus** — `current`, `discontinued`, `unknown` 중 하나. Launch dataset entry 는 `current` 가짐.
- **profiles** — [reciprocity profile](#3-reciprocity-profile) 배열. Launch dataset 은 identity 당 정확히 한 entry.

### 2.2 옵션 필드

- **brandLabel** — 필름이 판매되는 secondary 브랜드 문자열 (예: 제조사-rebranded variant).
- **aliases** — 같은 필름을 가리키는 것으로 알려진 대체 이름 배열.
- **userMetadata** — 사용자 편집 가능 metadata (§2.3 참조); preset entry 에는 부재.

### 2.3 사용자 편집 가능 metadata

비-preset (또는 사용자 augmented) identity 에 대해:

- **displayNameOverride** — UI 에서 `canonicalStockName` 를 override 하는 옵션 문자열.
- **tags** — 문자열 배열.
- **notes** — free-form note 문자열 배열.

Preset launch entry 는 사용자 metadata 를 carry 하지 않는다.

---

## 3. Reciprocity profile

Profile 은 필름 stock 이 장노출 측광값에 어떻게 반응하는지 기술.

### 3.1 필수 필드

- **id** — 비-empty 문자열, 부모 identity 의 profile 배열 안에서 unique.
- **name** — 비-empty 문자열. Profile 을 surfacing 할 때 display 라벨 (예: "Manufacturer table").
- **source** — provenance metadata (§4 참조).
- **rules** — [reciprocity rule](#5-reciprocity-rules) 배열, 적어도 한 entry. 순서는 계산 정책의 평가 순서가 별도로 정의되는 한도에서만 의미 ([Calculator Spec](Calculator.md) §3.2).
- **notes** — free-form note 문자열 배열 (보조 copy 로 렌더).

### 3.2 옵션 필드

- **userMetadata** — §2.3 와 평행한 사용자 편집 가능 필드, 본 profile 에 scoped. Preset profile 에는 부재.

---

## 4. Source provenance

모든 reciprocity profile 은 provenance carry:

- **kind** — `manufacturer_published`, `manufacturer_secondary` (예: 라이센시를 통해 재발행된 데이터 시트), `vendor_published`, `community_field_tested`, `historical_archive` 중 하나. Launch dataset 은 `manufacturer_published` 만 사용.
- **authority** — `official`, `field_tested`, `anecdotal` 중 하나. Launch dataset 은 `official` 만 사용.
- **confidence** — `unknown`, `high`, `medium`, `low` 중 하나. 생략의 default 는 `unknown`. Launch dataset 은 `high` 사용.
- **publisher** — 필수 비-empty 문자열 (데이터를 출판한 entity, 예: `"Kodak"`, `"ILFORD HARMAN"`).
- **title** — 특정 문서 또는 페이지 참조 옵션 문자열.
- **citation** — 더 정확한 reference (URL, 페이지 번호) 가 있는 옵션 문자열.
- **sourceVersion** — 출판된 edition 또는 revision 식별 옵션 문자열.

Provenance 필드는 source 에서 verbatim 보존. 시스템은 갭을 채우기 위해 provenance 를 합성하지 않는다 — 누락된 옵션 필드는 부재 유지. (Wiki 13172737)

---

## 5. Reciprocity rules

Profile 의 동작은 하나 이상의 rule 로 표현. Rule 은 네 variant 의 tagged union:

### 5.1 Threshold rule

보정이 적용되지 않는 영역을 표시.

- **noCorrectionRange** — 보정 시간 = 측광 시간인 측광값을 기술하는 [time range](#7-reciprocity-time-range).
- **adjustments** — threshold band 외부의 안내 전용 조정 배열 (정보용 — 계산 정책은 quantified rule 로 해석하지 않는다).
- **notes** — free-form note 배열.

예: `Kodak PORTRA 400` 은 ~1 s 미만 무보정 보고; 그 너머 제조사 안내는 "조건 하 시험" (advisory, 비-quantified).

### 5.2 Formula rule

closed-form 보정 표시.

- **meteredRange** — 공식의 도메인을 제약하는 옵션 [time range](#7-reciprocity-time-range). Open-ended `meteredRange` 는 "계산 정책이 공식 단계에 도달하는 곳마다 적용" 의미.
- **formula** — 유일하게 정의된 공식 형태는 **지수 power** 형태: `T_c = T_m^P` + 옵션 계수 + offset (`T_c = coefficient × T_m^exponent + offsetSeconds`). 구조는 투명성을 위해 source 의 출판된 등식 문자열 포함.
- **additionalAdjustments** — 계산이 소비하지 않는 보충 조정 배열 (예: 현상 시간 hint).
- **notes** — free-form note 배열.

예: `ILFORD HP5 Plus` 는 `T_m > 1 s` 에 대해 `T_c = T_m^1.31` 사용.

### 5.3 Table rule

이산 측광 → 보정 샘플 점 set 표시.

- **entries** — 비-empty entry 배열, 각 entry 는:
  - **meteredExposure** — [측광 노출 selector](#8-metered-exposure-selector) (정확한 초 값 또는 범위).
  - **adjustments** — 그 점에서의 보정을 기술하는 비-empty [노출 조정](#9-exposure-adjustment) 배열.
  - **notes** — 그 표 row 에 attached 된 free-form note 배열.

단일 entry 의 조정은 estimation family 를 mix 하지 않는다 — row 는 `correctedTime` 스타일 조정 또는 `stopDelta`/`multiplier` 스타일 조정 둘 다가 아닌 하나만 사용. ([Calculator Spec](Calculator.md) §3.3)

예: `Kodak TRI-X 400` 표: 1 s → +1 stop (보정 2 s, dev −10%); 10 s → +2 stops (보정 50 s, dev −20%); 100 s → +3 stops (보정 1200 s, dev −30%).

### 5.4 Advisory rule

비-quantified 안내만 있는 영역 표시.

- **range** — advisory 가 적용되는 [time range](#7-reciprocity-time-range).
- **severity** — `caution`, `not_recommended` 중 하나. `not_recommended` 는 stop signal ([Calculator Spec](Calculator.md) §3.2 step 3 참조).
- **guidanceText** — 제조사 advisory wording 을 carry 하는 비-empty 문자열.

예: `Fujifilm Velvia 50` 은 64 s 에서 `not_recommended` advisory carry.

---

## 6. Calculation result (영속화됨)

계산 정책이 결과를 produce 할 때, 결과는 영속화 round-trip 가능하므로 도메인의 일부. ([Calculator Spec](Calculator.md) §3.5)

결과는 세 mutually-exclusive form 중 하나:

- **Quantified** — 보정 노출이 produce 됨. metadata block (아래 참조) + `correctedExposure` payload (초 단위 reciprocity 시간 값) carry.
- **Advisory-only** — 안내는 가능 but quantified 시간 없음. metadata block carry; `correctedExposure` 필드 없음.
- **Unsupported** — 이 측광 점에 대한 안내 없음. metadata block carry; `correctedExposure` 필드 없음.

모든 form 이 carry 하는 metadata block:

- **calculationBasis** — 다음 중 하나: `exact_table_point`, `interpolated_within_table`, `extrapolated_beyond_table`, `official_threshold_no_correction`, `advisory_only_beyond_official_range`, `unsupported_out_of_policy_range`, `formula_derived`.
- **sourceAuthorityImpact** — profile 의 provenance 에서 derive.
- **rangeStatus** — `within_table`, `extrapolated`, `threshold_only`, `beyond_guidance`.
- **warningLevel** — `none`, `caution`, `advisory`, `not_recommended`.
- **supportingNotes** — 사람 읽기 문자열 배열.
- **usedReferencePoints** — 결과를 inform 한 row 또는 공식 계수에 대한 reference 배열.

`correctedExposure` 의 존재는 form (Quantified vs Advisory-only/Unsupported) 으로 구조적 결정 — form 이 보정 노출을 claim 하면서 payload 가 없거나 (그 반대) 인 결과는 구성상 표현 불가능.

---

## 7. Reciprocity time range

범위는 측광 노출 값을 bound:

- **minimumSeconds** — 음이 아닌 finite 숫자.
- **maximumSeconds** — 음이 아닌 finite 숫자, 또는 부재 / null = "no upper bound".

`maximumSeconds` 가 존재할 때 `≥ minimumSeconds` 여야. 경계 시맨틱 (closed vs open) 은 자연스러운 read 를 따름: 측광값 `t` 는 `minimumSeconds ≤ t` 이고 (`maximumSeconds` 부재 또는 `t ≤ maximumSeconds`) 일 때 범위 안.

---

## 8. Metered exposure selector

Table rule entry 안에서 row 가 어떤 측광값에 적용되는지 식별. 두 variant 의 tagged union:

- **exact** — 단일 음이 아닌 finite 초 값. Row 가 그 값에 정확히 매치.
- **range** — [time range](#7-reciprocity-time-range). Row 가 범위의 어떤 측광값에도 매치.

같은 table rule 안에서 row 의 metered selector 는 다른 row 의 metered selector 와 overlap 하지 않는다.

---

## 9. Exposure adjustment

Entry 가 노출을 어떻게 보정하는지 기술하는 tagged union. variant:

- **correctedTime** — `{ meteredSeconds?, correctedSeconds }`. `meteredSeconds` 는 옵션 컨텍스트 (원래 측광 점); `correctedSeconds` 는 보정 노출. 점 사이 보간 시 **log-log** estimation driving.
- **stopDelta** — `{ stops }`. 보정은 더할 양수 stop 수. 보간 시 **stop-공간** estimation driving.
- **multiplier** — `{ factor }`. 보정은 측광 시간에 대한 양수 scalar multiplier. 보간 시 **stop-공간** estimation driving.

단일 table row 의 조정은 한 번에 한 estimation family 만 사용. ([Calculator Spec](Calculator.md) §3.3)

---

## 10. 인코딩 (informative)

현재 직렬화는 `camelCase` 필드 이름의 JSON. Tagged union 은 `kind` discriminator 필드 사용; variant payload 는 variant 와 같은 이름의 sibling 필드에 위치. 예시 shape:

```jsonc
// Reciprocity rule (variant: threshold)
{ "kind": "threshold", "threshold": { "noCorrectionRange": { ... }, ... } }

// Exposure adjustment (variant: correctedTime)
{ "kind": "correctedTime", "correctedTime": { "correctedSeconds": 2.0 } }
```

필드 누락 + 명시 `null` 은 decode 시 등가로 처리. Encoder 는 부재 옵션 필드를 `null` 쓰지 말고 omit. On-disk 형식은 진화 가능 — spec 본문 (§§1–9) 이 contract, 인코딩이 아님.

---

## 11. 카탈로그 검증 규칙

bundled launch 카탈로그는 런타임이 받아들이기 전 다음 검사 통과해야.

1. Film identity 배열이 비-empty.
2. 모든 identity 가 비-empty `id`, 카탈로그 가로질러 unique.
3. 모든 identity 가 비-empty `canonicalStockName`, 카탈로그 가로질러 unique.
4. 모든 identity 가 `kind = "preset"`.
5. 모든 identity 가 `productionStatus = "current"`.
6. 모든 identity 가 정확히 **하나의** profile.
7. 모든 profile 의 source 가 `kind = "manufacturer_published"`.
8. 모든 profile 의 source 가 `authority = "official"`.
9. 모든 profile 이 적어도 한 rule, 모든 rule 이 알려진 variant 로 디코드 (no `unknown` `kind` 값).

이 검사들 중 어느 것을 실패하는 카탈로그는 명확한 decode 진단을 produce 하고 load 되지 않는다.

---

## 12. Launch dataset scope

의도된 first-wave launch dataset 은 **34 필름** (wiki 13172737). 현 bundled 카탈로그는 spec 진화 작업 중 **더 작은 subset** ship; wiki 15138817 의 검증 매트릭스가 검증 샘플로 cover 되어야 할 일곱 시나리오 명세 (official formula, official table, color guidance, threshold-only advisory, archival official, 사용자 정의, multi-profile 지원).

현 bundled subset 은 검증 매트릭스 시나리오 가로지른 대표 profile 포함. 현 bundle → 34-필름 launch 까지의 경로는 점진적이며 정책 spec 와 함께 추적.

### 12.1 카탈로그 외부에 bundled 된 비-launch profile

시스템은 launch 카탈로그 파일 *외부* 에 추가 **비-launch profile** 을 bundle 가능 — 런타임에 별도 등록. 이들은:

- launch profile 과 같은 도메인 shape (§§1–9) 을 따름;
- 정직한 provenance carry — 예를 들어 unofficial practical 공식은 `kind = "community_field_tested"` (또는 등가) + `authority = "unofficial"` 로 선언, official 인 척하지 않음;
- 이미 launch (official) primary profile 가진 필름 identity 에 *secondary 대안* 으로 사용자가 선택 가능;
- §11 launch-카탈로그 validator 를 통과하지 않음 (§11 검증 규칙은 launch 카탈로그 파일에만 적용).

예: Kodak PORTRA 400 의 unofficial practical 공식 `T_c = T_m^1.34` 가 launch 카탈로그 외부에 PORTRA 400 의 official threshold-only profile 의 secondary 대안으로 bundle.

이 profile 의 presentation contract 는 [UI Spec](UI.md) §2.1 (명시적 "Official guidance" / "Unofficial practical" 부제) + §2.6 (모든 profile 의 details sheet 에서 Authority row 표시) 에 위치.

---

## 13. Forbidden patterns

도메인은 다음을 **하지 않는다**:

1. 어떤 rule 의 데이터 shape 안에 보간 또는 외삽 정책 인코딩. 도메인은 제조사 점을 verbatim 저장; 계산 정책이 해석 결정.
2. 갭을 채우기 위해 provenance 필드 합성. 누락된 옵션 필드는 부재 유지.
3. Repackaged 브랜드 identity 와 원-제조사 identity 를 한 entry 안에 mix. Repackaging 은 원 identity 에 대한 `brandLabel` annotation — 평행 record 가 아님.
4. 보정 노출을 claim 하면서 값을 carry 하지 않거나, 보정 노출 값을 carry 하면서 claim 하지 않는 계산 결과 허용. 모순 페어링은 결과의 form 으로 표현 불가능.
5. 단일 table row 가 *보간 목적* 으로 estimation family 를 mix 허용. 보간은 row 당 정확히 한 estimation family read — `correctedTime` 와 `stopDelta`/`multiplier` 모두 기록되어 있을 때 계산 정책은 `correctedTime` 선택 + 다른 것을 대안 estimation 경로가 아닌 보충 annotation (현상 advisory, color-filter note) 으로 처리. Secondary annotation 만 기록한 row (예: `stopDelta` + 현상 조정) 는 stop-delta family 유지. 금지 케이스는 *모호한 보간* — precedence 규칙 없는 같은 row 에 경쟁하는 두 primary estimation family. (Calculator Spec §3.3)
6. Launch preset profile 이 사용자 metadata carry 허용.
7. 카탈로그 검증 무시. 실패하는 카탈로그는 load-time 에러 — soft-warn 아님.
8. 한 필름의 다중 official profile 을 한 record 로 collapse. (Wiki 15138817 이 multi-profile 지원 예약; launch 에서는 identity 당 한 profile 만 ship.)

---

## 14. Drift + 미해결 질문

- **사용자 정의 필름 schema.** Wiki 15138817 이 검증 요구사항으로 list — 데이터 모델과 UX 는 명시 안 됨.
- **Multi-profile 지원.** 도메인이 예약 (한 identity 가 다중 profile 가질 수 있음) but 선택 메커니즘 (특정 측광 노출에서 어떤 profile 가 "active", push/pull 시맨틱, 현상자별 variant) 은 명시 안 됨.
- **컬러 보정 metadata.** Wiki 15138817 에 Velvia 스타일 "M color correction" 언급 but schema entry 없음. 현재 (있다면) free-form `notes` 로 capture.
- **현상-시간 조정.** 현상-시간 조정 metadata (예: wiki 안내의 Tri-X 스타일 "dev −10%") 는 first-class schema 필드로 표현되지 않는다.
- **Launch dataset 성장.** Bundled 카탈로그가 34-필름 wiki target 미달. Spec 형태로 갭 close 위한 우선순위 작업 plan 없음.
- **Repackaging 링크.** Schema 가 `brandLabel` + `aliases` 받지만 "이 브랜드 X 가 identity Y 와 같은 필름" 링크를 런타임 등가 검사에 적합하게 formalize 하지 않음.
- **인코딩 versioning.** 인코딩 (`kind` discriminator 의 JSON) 은 본 spec 에서 informative-only but 카탈로그에 version 필드 없음. 향후 형식 변경에 정의된 마이그레이션 story 없음.

---

## 15. Sources of intent (참고)

본 섹션은 *참고 자료* — 규범 아님.

**Wiki (Confluence page id)**
- 13172737 — Reciprocity Film Research List (launch scope, method keys, provenance 규칙, repackaging 정책)
- 15138817 — Reciprocity Validation Samples (최소 검증 매트릭스, 예시 profile)
- 15237121 — Reciprocity Table Calculation Policy Notes (책임 분리, 유보 항목)
- 15761409 — Reciprocity Table Interpolation and Calculation Policy Draft (책임 분리, metadata, 정책 방향)

