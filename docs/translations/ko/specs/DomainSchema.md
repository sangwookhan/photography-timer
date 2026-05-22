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
  - `custom` — 사용자 정의 entry (유보; §15 참조).
  - `unknown` — forward-compatible decoding 만을 위해 존재; 결코 쓰이지 않음.
- **canonicalStockName** — 비-empty, 카탈로그 안에서 unique. 필름의 display-default 이름. 예: `"Kodak TRI-X 400"`, `"ILFORD HP5 Plus"`.
- **manufacturer** — 알려진 경우 원래 제조사 문자열. Repackaged 브랜드 라벨 (다른 라벨로 판매되는 필름)은 여기 등장하지 않음 — `brandLabel`에 위치.
- **iso** — 양의 정수; 필름의 box-speed ISO. 모든 identity에 필수.
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
- **name** — 비-empty 문자열. Profile을 surfacing 할 때 display 라벨 (예: "Official formula").
- **source** — provenance metadata (§4 참조).
- **rules** — [reciprocity rule](#5-reciprocity-rules) 배열, 적어도 한 entry. 순서는 계산 정책의 평가 순서가 별도로 정의되는 한도에서만 의미 ([Calculator Spec](Calculator.md) §3.2).
- **notes** — free-form note 문자열 배열 (보조 copy로 렌더).
- **sourceEvidence** — 옵션 [source-evidence row](#33-source-evidence-rows) 배열. Formula profile이 사용자가 공식 prediction을 published 데이터와 대조 verify 할 수 있도록 carry 하는 display 전용 제조사 reference 점. 계산 정책은 이 row를 결코 consume 하지 않으며 anchor로 진입 불가. Reference 점 없는 profile에선 부재 또는 빈 배열.

### 3.2 옵션 필드

- **userMetadata** — §2.3와 평행한 사용자 편집 가능 필드, 본 profile에 scoped. Preset profile 에는 부재.

### 3.3 Source-evidence rows

Profile은 계산 rule 옆에 display 전용 제조사 reference 점을 carry 할 수 있다. Source-evidence row는 presentation 표면이 사용자에게 formula prediction이 published 데이터와 어디서 일치하는지 보여주도록 하며, 그 데이터가 계산에 anchor로 진입하는 일은 결코 없다.

각 row는:

- **meteredExposure** — [측광 노출 selector](#9-metered-exposure-selector); 제조사가 reference를 출판한 측광값.
- **adjustments** — published reference를 기술하는 [노출 조정](#10-exposure-adjustment) 배열 (corrected time, stop delta, color-filter recommendation 등).
- **notes** — free-form note 배열.
- **isSourceEvidenceOnly** — 옵션 boolean (기본 `false`). `true`이면 row가 published evidence로 보존되지만 presentation layer는 formula-fitting marker에서 omit 하고 footnote marker (`*`)를 prefix 해 사용자가 계산 anchor가 아님을 인식하게 한다. ADOX CMS 20 II의 `1/1000 s +1/2 stop` reference가 canonical case — 제조사가 sub-1s 점을 출판하지만 계산 경로는 sub-1s band 전반에서 no-correction 유지.

Source-evidence row는 결코 계산 rule로 promote 되지 않는다. 계산 정책은 의도적으로 이 배열을 모른다.

---

## 4. Source provenance

모든 reciprocity profile은 provenance 포함:

- **kind** — `manufacturerPublished`, `manufacturerArchive` (제조사 자체의 archive / 폐기된 문서), `thirdPartyPublication` (제조사가 아닌 publication; 예: 커뮤니티 field-test practical 공식), `userDefined`, `unknown` 중 하나. Launch dataset은 `manufacturerPublished`만 사용.
- **authority** — `official`, `unofficial`, `userDefined`, `unknown` 중 하나. Launch dataset은 `official`만 사용. Supplementary non-launch profile (§13.3)은 `unofficial` 사용.
- **confidence** — `high`, `medium`, `low`, `unknown` 중 하나. 생략의 default는 `unknown`. Launch dataset은 `high` 사용.
- **publisher** — 데이터를 출판한 entity (예: `"Kodak"`, `"Ilford Photo"`). Launch (official) profile은 필수 비-empty 문자열. Supplementary unofficial profile (§13.3)은 verified source가 아직 없을 때 "source pending verification" 마커로 비워둘 수 있다 — 이 경우 presentation은 Sources 섹션을 표시하지 않고 unofficial-authority 부제 + caveat note로 disclosure 한다.
- **title** — 특정 문서 또는 페이지 참조 옵션 문자열.
- **citation** — 더 정확한 reference (URL, 페이지 번호)가 있는 옵션 문자열.
- **sourceVersion** — 출판된 edition 또는 revision 식별 옵션 문자열.

Provenance 필드는 source에서 verbatim 보존. 시스템은 갭을 채우기 위해 provenance를 합성하지 않는다 — 누락된 옵션 필드는 부재 유지. (Wiki 13172737)

---

## 5. Reciprocity rules

Profile의 동작은 하나 이상의 rule로 표현. Rule은 세 variant의 tagged union:

### 5.1 Threshold rule

보정이 적용되지 않는 영역을 표시.

- **noCorrectionRange** — 보정 시간 = 측광 시간인 측광값을 기술하는 [time range](#8-reciprocity-time-range).
- **adjustments** — threshold band 외부의 안내 전용 조정 배열 (정보용 — 계산 정책은 quantified rule로 해석하지 않는다).
- **notes** — free-form note 배열.

예: `Kodak PORTRA 400`은 ~1 s 미만 무보정 보고; 그 너머 제조사 안내는 "조건 하 시험" (§5.3 limited-guidance rule).

### 5.2 Formula rule

closed-form 보정 표시.

- **meteredRange** — 공식의 도메인을 제약하는 옵션 [time range](#8-reciprocity-time-range). Open-ended `meteredRange`는 "계산 정책이 공식 단계에 도달하는 곳마다 적용" 의미.
- **formula** — 유일하게 정의된 공식 형태는 **지수 power** 형태: `T_c = coefficient × T_m^exponent + offsetSeconds` (`coefficient` 기본값 `1`, `offsetSeconds` 기본값 `0`). 구조는 투명성을 위해 source의 출판된 등식 문자열 포함.
- **additionalAdjustments** — 계산이 소비하지 않는 보충 조정 배열 (예: 현상 시간 hint).
- **extrapolateBeyondMaximum** — boolean (기본 `true`). `true`이면 `meteredRange.maximumSeconds` 너머에서도 공식이 숫자 값을 산출하며 결과는 `unsupportedOutOfPolicyRange`로 reclassify (numeric continuation 동반). `false`이면 상한이 제조사 stop signal — 결과는 `unsupportedOutOfPolicyRange` + 보정 노출 값 자체 부재 (ADOX CMS 20 II `≥ 100 s` "Not recommended" 경계가 이 경우).
- **notes** — free-form note 배열.

Formula profile과 연관된 제조사 reference 점 (예: Provia 100F가 출판한 `240 s +1/3 stop` row)은 formula rule의 데이터가 아닌 profile의 `sourceEvidence` 배열 (§3.1, §3.3)에 위치.

예: `ILFORD HP5 Plus`는 `T_m > 1 s`에 대해 `T_c = T_m^1.31` 사용.

### 5.3 Limited-guidance rule

제조사가 quantified 보정 노출이 아닌 qualitative 안내만 출판한 영역을 표시. 이 영역의 계산 결과는 구조적으로 non-quantified (§6).

- **appliesWhenMetered** — rule이 cover 하는 영역을 제한하는 옵션 [time range](#8-reciprocity-time-range). Open-ended이면 "계산 정책이 이 단계에 도달하는 곳마다 적용".
- **adjustments** — 정성적 조정 배열 (color-filter recommendation, free-form note). 계산 정책은 이를 보조 안내로 surface 하지만 보정 노출을 derive 하지 않는다.
- **notes** — free-form note 배열.

예: `Kodak Ektachrome E100`은 10 s 너머에서 120 s `CC10R` color-filter recommendation을 동반한 limited-guidance rule을 갖는다. 이 영역의 어떤 측광값에 대해서도 결과는 non-quantified.

---

## 6. Calculation result (영속화됨)

계산 정책이 결과를 산출할 때, 결과는 영속화 round-trip 가능하므로 도메인의 일부. ([Calculator Spec](Calculator.md) §3.3)

결과는 세 mutually-exclusive form 중 하나:

- **Quantified** — 보정 노출이 산출됨. metered + corrected + metadata block (아래) 포함. Basis는 `officialThresholdNoCorrection` 또는 `formulaDerived`.
- **Limited-guidance** — 제조사가 이 영역에 대해 qualitative 안내만 출판; 보정 노출 산출 없음. metered + metadata block 포함; `correctedExposure` 필드 없음. Basis는 `limitedGuidanceNoQuantifiedPrediction`.
- **Unsupported** — 측광 노출이 profile의 지원 범위 외부. metered + metadata block 포함; 공식 기반 profile이 supported boundary 너머에서 숫자 continuation을 산출한 경우에만 `correctedExposure` 필드 존재 (그때는 presenter가 outside manufacturer guidance로 mark). Basis는 `unsupportedOutOfPolicyRange`.

모든 form이 포함하는 metadata block:

- **calculationBasis** — `officialThresholdNoCorrection`, `formulaDerived`, `limitedGuidanceNoQuantifiedPrediction`, `unsupportedOutOfPolicyRange` 중 하나.
- **sourceAuthorityImpact** — profile의 provenance에서 derive (current official / archival official / unofficial secondary / user-defined).
- **rangeStatus** — `withinStatedRange`, `beyondLastRepresentativePoint`, `beyondPolicyLimit`.
- **warningLevel** — `none`, `note`, `caution`, `strongWarning`.
- **notes** — token-tagged 사람 읽기 문자열 배열.

`correctedExposure`의 존재는 form (Quantified vs Limited-guidance vs Unsupported)으로 구조적 결정 — form이 보정 노출을 claim 하면서 payload가 없거나 (그 반대) 인 결과는 구성상 표현 불가능 (단 unsupported가 formula-extrapolated continuation을 동반하는 예외만 허용).

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
- **selectedProfileID** — optional 문자열; 선택 필름 위의 활성 reciprocity profile override id. 필름의 profile 배열 (그리고 bundled non-launch profile 레지스트리, §13.3)에 대해 resolve. 더 이상 resolve 되지 않는 id는 override를 silently drop 하고 슬롯은 필름의 primary profile로 복원.
- **baseShutterSeconds** — optional 음이 아닌 유한한 숫자; 슬롯의 확정 된 Base Shutter 값. 활성 노출 scale의 셔터 ladder에 대해 복원 시 sanitize; 부재 또는 invalid 값은 출시 기본값 Base Shutter로 복원.
- **ndStop** / **ndStopThirds** — calculator working context (§7 / §7.2)와 동일한 규약과 우선순위: fractional-aware `ndStopThirds`가 우선, `ndStop`은 legacy hint 취급.
- **exposureScaleMode** — §7.3과 같은 규약을 따르는 optional 문자열 토큰; 부재 ⇒ 출시 one-third-stop scale.
- **customDisplayName** — 사진가가 지정한 슬롯 표시 라벨 (optional). Write 시점에 trim; 빈 / whitespace-only 값은 부재로 영속화 — 복원된 슬롯이 canonical *Camera N* default로 대체 하도록. 슬롯 rename은 이 필드만 변경; 슬롯의 안정된 id와 슬롯별 calculator 입력은 영향받지 않는다.
- **targetShutterSeconds** — 슬롯의 확정된 Target Shutter duration (optional 0보다 큰 유한한 값, [Calculator Spec](Calculator.md) §3.6). 부재, 유한하지 않거나 0 이하인 값은 슬롯에 target 없음으로 복원된다. 슬롯별 target 영속화는 세션 전역 last-used target 메모리를 초기값으로 사용하지 않아야 한다 — 그렇게 하면 한 슬롯의 값이 다른 슬롯에 표시된다.

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

Source-evidence row (§3.3)와 limited-guidance rule (§5.3) 안에서 entry가 어떤 측광값에 적용되는지 식별. 두 variant의 tagged union:

- **exact** — 단일 음이 아닌 유한한 초 값. Entry가 그 값에 정확히 매치.
- **range** — [time range](#8-reciprocity-time-range). Entry가 범위의 어떤 측광값에도 매치.

---

## 10. Exposure adjustment

Rule의 `adjustments` 또는 source-evidence row의 `adjustments` 배열에 attach 된 단일 안내를 기술하는 tagged union. variant:

- **correctedTime** — `{ meteredSeconds?, correctedSeconds, isApproximate? }`. `meteredSeconds`는 옵션 컨텍스트 (원래 측광 점); `correctedSeconds`는 보정 노출. `isApproximate` (기본 `false`)는 카탈로그가 비합리적 변환의 rounded display로 저장하는 값을 표시 — 보통 source가 stop-delta만 출판한 row에서 fractional `stopDelta`로 derive 된 corrected time (`metered × 2^stopDelta`). Multiplier로 derive 된 corrected time (`metered × multiplier`)은 정확한 산술 결과이며 — 카탈로그가 derive 했음에도 — 표시되지 않는다. Presentation layer는 approximate 값을 구분되게 surface (예: 선행 `≈`) — 사용자가 출판된 / 정확히 변환된 anchor와 rounded 값을 한눈에 구별 가능.
- **stopDelta** — `{ stops }`. 출판된 보정은 row의 측광 점에서 더할 stop 수.
- **multiplier** — `{ factor }`. 출판된 보정은 row의 측광 점에서 측광 시간에 대한 scalar multiplier.
- **colorFilter** — `{ filterName, note? }`. 컬러 보정 필터 권고 (예: `5M`, `CC10R`).
- **development** — `{ instruction, note? }`. 현상 시간 조정 hint (예: `-10% development`).
- **warning** — `{ severity, message }`. `severity`는 `caution` 또는 `notRecommended`. Formula의 source-evidence row에서 `notRecommended`는 제조사 stop-signal 경계를 표시 — 단, 계산 정책은 stop-signal 위치를 이 row가 아닌 formula rule의 `meteredRange.maximumSeconds`/`extrapolateBeyondMaximum`에서 읽는다.
- **note** — `{ text }`. Free-form 보조 안내.

Exposure adjustment는 threshold / limited-guidance rule + source-evidence row에 attach 되는 display 전용 데이터. 계산 정책은 이들로부터 quantified prediction을 read 하지 않는다 — 보정 노출 값은 threshold (identity) 또는 formula (closed-form) rule에서만 산출.

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
6. 모든 identity가 양의 `iso` (box-speed ISO).
7. 모든 identity가 정확히 **하나의** profile.
8. 모든 profile의 source가 `kind = "manufacturerPublished"`.
9. 모든 profile의 source가 `authority = "official"`.
10. 모든 profile이 적어도 한 rule, 모든 rule이 알려진 variant로 디코드 (no `unknown` `kind` 값).
11. 모든 profile이 §13의 두 허용 launch shape 중 하나에 매치: rule 셋이 threshold rule을 포함하고 (a) limited-guidance rule 없는 formula rule, 또는 (b) formula rule 없고 `sourceEvidence`가 비어 있는 limited-guidance rule. 단독 threshold, 단독 formula, 또는 다른 조합은 거부.

이 검사들 중 어느 것을 실패하는 카탈로그는 명확한 decode 진단을 출력하고 load 되지 않는다.

---

## 13. Launch dataset scope

Bundled launch 카탈로그는 **34-필름 launch-ready scope** (wiki 13172737, PTIMER-86 preset 데이터셋 정책 결과) ship. 각 ship identity는 `kind = "manufacturerPublished"`, `authority = "official"`, `confidence = "high"`인 current official 제조사 문서에서 source 된 정확히 하나의 primary profile 보유.

모든 launch preset profile은 다음 두 허용 shape 중 정확히 하나에 매치:

1. **Official quantified formula** — threshold rule (무보정 band) + formula rule (closed-form 보정), 제조사 reference 점을 보존하는 옵션 `sourceEvidence` row. 계산은 formula range 내부에서 `formulaDerived` 보정 노출 산출; formula의 `meteredRange.maximumSeconds` 너머에서 `unsupportedOutOfPolicyRange`로 전환 (`extrapolateBeyondMaximum`에 따라 numeric continuation 동반 여부 결정).
2. **Official limited guidance** — threshold rule + threshold 너머 영역에 대한 limited-guidance rule (§5.3). 계산은 threshold band 내부에서 `officialThresholdNoCorrection`, 너머에서 `limitedGuidanceNoQuantifiedPrediction` 산출; formula curve 없음, quantified continuation 없음.

Unofficial practical profile (`authority = "unofficial"`)은 launch 카탈로그 파일 외부에 bundle 되며 §13.3에서 별도로 기술한다.

Launch preset profile은 계산 table rule을 갖지 않는다. 도메인에 `.table` rule variant 자체가 없다; 향후 custom 또는 사용자 정의 table 입력은 launch preset scope 외부이며 도입한다면 새 feature로 설계되어야 한다.

### 13.1 Launch-ready 제조사 분포

| 제조사            | 수    | Profile shape |
|------------------|------:|---------------|
| ILFORD / HARMAN  |    12 | Threshold + formula (`Tc = Tm^P`) |
| Kodak Still Film |     9 | Threshold + formula (B/W: Tri-X 400, T-MAX 100/400) 또는 threshold + limited-guidance (color negative, Ektachrome E100) |
| Fujifilm         |     4 | Threshold + formula with `sourceEvidence` reference row |
| FOMA BOHEMIA     |     3 | Threshold + formula with `sourceEvidence` reference row |
| Rollei           |     4 | Threshold + formula with `sourceEvidence` reference row |
| ADOX             |     2 | Threshold + formula with `sourceEvidence` reference row (CMS 20 II는 100 s stop signal로 `extrapolateBeyondMaximum = false`) |
| **합계**         | **34** | |

### 13.2 Launch dataset 제외 항목

다음 분류는 의도적으로 launch 카탈로그 외부 (PTIMER-86 source-priority 정책):

- Kodak Motion Picture Film (Vision3, Ektachrome 100D, Double-X) — still 사진 우선 scope.
- AgfaPhoto 현 필름 — current official reciprocity 추출 pending.
- ORWO, Bergger, Film Ferrania — 현 제품 라인 확인 but reciprocity 추출 너무 thin.
- Archival 전용 Agfa / AgfaPhoto / Kodak Ektachrome E100G–E100GX entry — archival 데이터가 current shipping 데이터로 promote 되지 않도록 제외.
- Unofficial practical 공식. 특히 unofficial `T_c = T_m^1.34` Portra approximation은 launch 카탈로그 외부에 bundle (§13.3) — primary ship Portra profile로 등장하지 않음.
- Launch-ready 제조사 그룹의 필름 중 source 목록이 여전히 `NV`로 분류한 항목 (Fomapan R100, Cine 100, Cine 400, Cine Ortho 400; Rollei RPX 25, RETRO 400S, INFRARED, ORTHO 25 plus, PAUL & REINHOLD, BLACKBIRD, CROSSBIRD, REDBIRD; ADOX HR-50, Scala 50).

### 13.3 카탈로그 외부에 bundled 된 비-launch profile

시스템은 launch 카탈로그 파일 *외부*에 추가 **비-launch profile**을 bundle 가능 — 런타임에 별도 등록. 이들은:

- launch profile과 같은 도메인 shape (§§1–10)을 따름;
- 정직한 provenance 포함 — 예를 들어 unofficial practical 공식은 `kind = "thirdPartyPublication"` + `authority = "unofficial"`로 선언, official 인 척하지 않음;
- 이미 launch (official) primary profile 가진 필름 identity에 *secondary 대안*으로 사용자가 선택 가능;
- §12 launch-카탈로그 validator를 통과하지 않음 (§12 검증 규칙은 launch 카탈로그 파일에만 적용).

예: Kodak PORTRA 400의 unofficial practical 공식 `T_c = T_m^1.34`가 launch 카탈로그 외부에 PORTRA 400의 official threshold + limited-guidance profile의 secondary 대안으로 bundle.

이 profile의 presentation contract는 [UI Spec](UI.md) §2.1 (명시적 "Official guidance" / "Unofficial practical" 부제) + §2.6 (모든 profile의 details sheet에서 Authority row 표시)에 위치.

---

## 14. Forbidden patterns

도메인은 다음을 **하지 않는다**:

1. Launch preset profile에 계산 table rule을 재도입. 도메인에 `.table` rule variant 자체가 없다; 향후 custom / 사용자 정의 table 입력은 이 scope 외부.
2. Source-evidence row (§3.3)를 계산 anchor로 promote. 계산 정책은 threshold, formula, limited-guidance rule만 read — source-evidence는 display 전용 reference 데이터.
3. 갭을 채우기 위해 provenance 필드 합성. 누락된 옵션 필드는 부재 유지.
4. Repackaged 브랜드 identity와 원-제조사 identity를 한 entry 안에 mix. Repackaging은 원 identity에 대한 `brandLabel` annotation — 평행 record가 아님.
5. 보정 노출을 claim 하면서 값을 포함하지 않거나, 보정 노출 값을 포함하면서 claim 하지 않는 계산 결과 허용 (단 `unsupportedOutOfPolicyRange`가 supported boundary 너머에서 formula-extrapolated numeric continuation을 동반하는 단일 허용 예외). 모순 페어링은 결과의 form으로 표현 불가능.
6. Launch preset profile이 사용자 metadata 포함 허용.
7. 카탈로그 검증 무시. 실패하는 카탈로그는 load-time 에러 — soft-warn 아님.
8. 한 필름의 다중 official profile을 한 record로 collapse. (Wiki 15138817이 multi-profile 지원 예약; launch 에서는 identity 당 한 profile만 ship.)
9. Launch preset reciprocity presentation에서 `Exact`, `Estimated`, `Interpolated`, `Extrapolated`, `Advisory`를 primary user-facing status / badge 문구로 surface. 이 용어는 legacy table 모델을 인코드 했음 — 현 vocabulary는 `No correction` / `Formula-derived` / `Beyond source range` / `No quantified prediction` / `Outside guidance` ([Calculator Spec](Calculator.md) §3.5, [UI Spec](UI.md) §2.3).

---

## 15. Drift + 미해결 질문

- **사용자 정의 필름 schema.** Wiki 15138817이 검증 요구사항으로 list — 데이터 모델과 UX는 명시 안 됨.
- **Multi-profile 지원.** 도메인이 예약 (한 identity가 다중 profile 가질 수 있음) but 선택 메커니즘 (특정 측광 노출에서 어떤 profile가 "active", push/pull 시맨틱, 현상자별 variant)은 명시 안 됨.
- **컬러 보정 metadata.** Velvia 스타일 "M color correction"은 source-evidence row의 `colorFilter` exposure adjustment (§10)로 capture. Per-row annotation과 구분되는 first-class 컬러 보정 정책은 schema entry 없음.
- **현상-시간 조정.** Tri-X 스타일 "dev −10%" 등의 현상-시간 조정 metadata는 source-evidence row의 `development` exposure adjustment (§10)로 capture; first-class 현상-시간 정책은 모델링 안 됨.
- **다음-wave 카탈로그 성장.** Bundled 카탈로그가 34-필름 launch-ready scope cover; PTIMER-86이 list 한 다음-wave 후보 (Kodak Motion Picture, launch-ready 제조사 그룹의 NV-status 필름, 유보된 AgfaPhoto / ORWO / Bergger / Film Ferrania)는 spec 형태로 우선순위 작업 plan 없음.
- **Repackaging 링크.** Schema가 `brandLabel` + `aliases` 받지만 "이 브랜드 X가 identity Y와 같은 필름" 링크를 런타임 등가 검사에 적합하게 formalize 하지 않음.
- **인코딩 versioning.** 인코딩 (`kind` discriminator의 JSON)은 본 spec에서 informative-only but 카탈로그에 version 필드 없음. 향후 형식 변경에 정의된 마이그레이션 story 없음.

---

## 16. Sources of intent (참고)

본 섹션은 *참고 자료* — 규범 아님.

**Wiki (Confluence page id)**
- 13172737 — Reciprocity Film Research List (launch scope, method keys, provenance 규칙, repackaging 정책)
- 15138817 — Reciprocity Validation Samples (최소 검증 매트릭스, 예시 profile)
- 15237121 — Reciprocity Table Calculation Policy Notes (historical: PTIMER-128 / PTIMER-140의 공식 기반 prediction 모델로 대체된 table-interpolation 정책을 기록)
- 15761409 — Reciprocity Table Interpolation and Calculation Policy Draft (historical: 15237121과 동일 상태)

