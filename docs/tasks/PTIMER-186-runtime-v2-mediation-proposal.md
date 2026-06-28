# PTIMER-186 — Catalog Runtime Schema v2 Mediation Proposal

## Verdict

PTIMER-186의 결론은 **Catalog Runtime Schema v2 제안**으로 정리한다.

새 runtime은 사람이 읽고 수정할 수 있는 flat JSON이어야 한다. 기존 decoder-shaped JSON의 `rules` 중첩, `sourceEvidence` 중복, code-defined alternate profile, hardcoded promoted-unofficial allowlist를 줄인다.

Claude의 authoring YAML + generator 제안은 phase 2 관리 레이어로 채택한다. 그러나 phase 1의 중심은 runtime v2 자체다.

---

## Core mediation

1. **새 runtime JSON v2를 만든다**
   - 기존 decoder-shaped JSON은 legacy로 본다.
   - 앱은 새 runtime JSON을 직접 decode한다.
   - 목표는 사람이 읽고 수정 가능한 runtime format이다.

2. **authoring YAML은 선택 레이어로 둔다**
   - YAML authoring + generator 방향은 좋다.
   - 다만 PTIMER-186의 중심 산출물은 YAML이 아니라 **runtime schema v2**다.
   - YAML은 관리 편의를 위한 source-of-truth 후보로 둔다.

3. **runtime v2는 flat JSON으로 간다**
   - `rules[].kind + formula.formula.formulaFamily` 구조 제거
   - `sourceEvidence` 중복 제거
   - `calculation` 블록 도입
   - `referencePoints`는 formula/evidence-only 용도로 제한
   - table anchor는 한 번만 저장

4. **`tier` 대신 `role` + `authority`를 분리한다**
   - `role`: 앱 안에서의 역할  
     예: `primary`, `alternate`, `derived`, `community`
   - `authority`: 출처 권위  
     예: `official`, `appDerived`, `community`, `unofficial`, `userDefined`

5. **anchor는 배열 쌍보다 object로 둔다**
   - `[[1, 2], [10, 50]]`는 짧지만 사람이 편집할 때 실수하기 쉽다.
   - runtime도 사람이 이해하기 쉬워야 하므로 명시적인 object가 낫다.

```json
{
  "meteredSeconds": 10,
  "correctedSeconds": 50
}
```

---

## Runtime v2 example

```json
{
  "schema": "ptimer.catalog.v2",
  "schemaVersion": 2,
  "catalogVersion": "2026.06",
  "copyright": "Copyright © 2026 Sangwook Han",
  "license": "Apache-2.0",
  "sources": {
    "kodak-tri-x-datasheet": {
      "kind": "manufacturerPublished",
      "authority": "official",
      "confidence": "high",
      "publisher": "Kodak",
      "title": "KODAK PROFESSIONAL TRI-X 400 Film — Technical Data",
      "citation": "Publication F-4017"
    }
  },
  "films": [
    {
      "id": "kodak-tri-x-400",
      "kind": "preset",
      "canonicalStockName": "Tri-X 400",
      "manufacturer": "Kodak",
      "brandLabel": "KODAK PROFESSIONAL TRI-X 400",
      "aliases": ["Tri-X"],
      "iso": 400,
      "productionStatus": "current",
      "profiles": [
        {
          "id": "kodak-tri-x-official-graph-table",
          "name": "Official Kodak graph/table",
          "selectorLabel": "Graph table",
          "role": "primary",
          "authority": "official",
          "sourceId": "kodak-tri-x-datasheet",
          "model": "table",
          "calculation": {
            "kind": "table",
            "interpolation": "logLog",
            "basis": "manufacturerGraphTable",
            "noCorrectionThroughSeconds": 0.1,
            "sourceRangeThroughSeconds": 100,
            "anchors": [
              { "meteredSeconds": 1, "correctedSeconds": 2 },
              { "meteredSeconds": 2, "correctedSeconds": 5 },
              { "meteredSeconds": 3, "correctedSeconds": 10 },
              { "meteredSeconds": 5, "correctedSeconds": 20 },
              { "meteredSeconds": 7, "correctedSeconds": 32 },
              { "meteredSeconds": 10, "correctedSeconds": 50 },
              { "meteredSeconds": 20, "correctedSeconds": 120 },
              { "meteredSeconds": 30, "correctedSeconds": 200 },
              { "meteredSeconds": 50, "correctedSeconds": 420 },
              { "meteredSeconds": 70, "correctedSeconds": 720 },
              { "meteredSeconds": 100, "correctedSeconds": 1200 }
            ]
          },
          "anchorMetadata": [
            { "meteredSeconds": 1, "published": true },
            { "meteredSeconds": 10, "published": true },
            { "meteredSeconds": 100, "published": true }
          ],
          "notes": [
            "Published rows are marked in anchorMetadata; other anchors are graph-estimated."
          ]
        }
      ]
    }
  ]
}
```

---

## Formula profile example

```json
{
  "id": "ilford-pan-f-plus-50-official-formula",
  "name": "Official formula",
  "role": "primary",
  "authority": "official",
  "sourceId": "ilford-reciprocity",
  "model": "formula",
  "calculation": {
    "kind": "formula",
    "family": "modifiedSchwarzschild",
    "referenceMeteredSeconds": 1,
    "referenceCorrectedSeconds": 1,
    "exponent": 1.33,
    "offsetSeconds": 0,
    "noCorrectionThroughSeconds": 1
  },
  "referencePoints": [],
  "notes": [
    "Exponent p = 1.33."
  ]
}
```

---

## Threshold guidance example

Claude의 `threshold-guidance` 제안은 채택한다. 기존 threshold + limitedGuidance pair를 하나의 model로 묶으면 사람이 이해하기 쉽고 잘못 조합하기 어렵다.

```json
{
  "id": "kodak-ektar-100-official-threshold",
  "name": "Official threshold guidance",
  "role": "primary",
  "authority": "official",
  "sourceId": "kodak-ektar-datasheet",
  "model": "thresholdGuidance",
  "calculation": {
    "kind": "thresholdGuidance",
    "noCorrectionRangeSeconds": {
      "from": 0.0001,
      "through": 1
    },
    "guidance": [
      {
        "appliesWhenMeteredAboveSeconds": 1,
        "message": "Longer exposures: test under your conditions."
      }
    ]
  },
  "notes": []
}
```

---

## Table evidence policy

중재안에서는 다음 정책을 사용한다.

- table profile:
  - `calculation.anchors`가 단일 진실
  - `sourceEvidence` 저장 안 함
  - published/approx 구분은 `anchorMetadata`에만 저장
- formula profile:
  - 계산은 `calculation`
  - 표시용 기준점은 `referencePoints`
- warning / not recommended:
  - `referencePoints` 또는 `guidance`에 명시

원칙:

```text
숫자는 가능한 한 한 번만 쓴다.
```

---

## Phase plan

### Phase 1 — Runtime v2 도입

- `LaunchPresetFilmCatalog.v2.json` 설계
- iOS/Android v2 decoder 추가
- v2 → existing domain model adapter 작성
- 기존 계산 결과와 동치 검증
- 기존 v1 catalog는 legacy fallback 또는 비교용으로 유지

### Phase 2 — Authoring source + generator

- 필요하면 YAML authoring source 도입
- source registry / per-film files 도입
- v2 runtime JSON 생성
- fixture 생성
- dead fixture block은 살릴지 제거할지 결정

이 순서가 사용자 지시인 “runtime을 새로 만든다”를 먼저 충족하고, Claude의 generator 장점도 유지한다.

---

## Fixture policy

- `catalogExpectations`: 유지 또는 v2 기준 재생성
- `perFilmExpectations`: 테스트가 읽게 만들거나 제거
- `rejectionCases`: 테스트가 읽게 만들거나 제거
- `launchCatalogValidationRules`: 테스트가 읽게 만들거나 제거

원칙:

```text
읽히지 않는 fixture block은 생성하지 않는다.
살릴 fixture는 반드시 테스트가 assert한다.
```

---

## Custom film policy

지금은 runtime v2 grammar가 custom film에 재사용 가능하도록만 설계한다.

custom export/import 포맷은 아직 설계하지 않는다.

먼저 별도 분석에서 결정할 것:

- custom film을 사용자 공유 기능으로 제공할지
- iOS/Android schemaVersion 정책을 어떻게 맞출지
- `referenceTableFilmID` 위치를 어떻게 통일할지
- linked table이 없을 때 어떻게 처리할지

---

## Final mediation proposal

```text
PTIMER-186의 결론은 Catalog Runtime Schema v2 제안으로 정리한다.

새 runtime은 flat JSON으로 만들고, 사람이 읽고 수정할 수 있어야 한다.
기존 sourceEvidence 중복, tagged-union 중첩, code-defined alternate,
hardcoded promoted-unofficial allowlist를 줄인다.

Claude의 authoring YAML + generator 제안은 phase 2 관리 레이어로 채택한다.
그러나 phase 1의 중심은 runtime v2 자체다.

runtime v2는 role과 authority를 분리하고, anchors는 명시적 object 배열로 둔다.
table anchors는 단일 진실로 관리하며, formula evidence는 referencePoints로 제한한다.

custom film export/import는 별도 product-gated track으로 분리한다.
```
