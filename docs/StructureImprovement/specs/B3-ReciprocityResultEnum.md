# B3 — Reciprocity Result Enum Spec

**Status**: Done
**Phase**: 3
**Spec precedence**: required before implementation
**Ticket**: PTIMER-118 (Implement Full Structure Improvement Plan)
**Related actions**: B1 (ViewModel 4분할, prerequisite — `ReciprocityModel` 표면적 정리 후 진입), A8 (Presenter, 추가 정리)
**Related infra**: B6 (golden fixture), record-replay 인프라 (`Docs/Verification/RecordReplay-B3-Prototype.md` 패턴 — 이미 archive됨, B3 ticket spec에서 인프라 ticket 분리)

## 구현 진행 메모

- **PR1** (commit `79b6842`): `ReciprocityResultLegacyShapeBaselineTests` +
  `reciprocity-policy-legacy-shape-baseline.txt` (77 cases · 2430 lines)
  baseline freeze.
- **PR2** (commit `6a868b1`): `ReciprocityResult` tagged-union 도입.
  backward-compat decoder (legacy 7-field 형식 수용) +
  `legacyShapeEncoded(using:)` 어댑터로 PR1 baseline byte-identical replay
  통과. `ReciprocityCalculationPolicyResult` 타입 제거; 모든 호출 사이트가
  enum case 또는 편의 accessor로 마이그레이션. PTIMER-90 디코더 모순 검증
  코드는 legacy 디코드 경로에만 남아 backward-compat 입력의 self-consistency를
  검증 (enum 자체는 illegal state를 컴파일 차단).
- **PR3**: SwiftLint custom rule `no_legacy_reciprocity_result_struct` (F11)
  추가 — `didReturnCalculatedTime` / `hasCalculatedExposureTime` +
  `correctedExposureSeconds?` 페어링 패턴 재도입 차단. enum 본가
  (`ReciprocityCalculationPolicy.swift`)는 rule 대상에서 제외. Calculator Spec
  §3.5 본문을 3-form tagged union 표현으로 갱신; 시맨틱 동등 명시. 영속성
  backward-compat 명문화 (DomainSchema §6 cross-ref).

---

## 1. 목적

현재 `ReciprocityCalculationResult`의 구조는 `didReturnCalculatedTime: Bool` + `correctedExposure: T?` 필드 페어를 가지며, 이 두 필드 간 **모순 가능성**(예: flag=true 인데 corrected nil)을 *디코딩 시점에 런타임 검증*으로 차단한다 (PTIMER-90). 이 모순 가능성을 **컴파일 시점에 차단**하기 위해 결과를 tagged union(enum)으로 재모델한다:

```
enum ReciprocityResult {
  case quantified(QuantifiedPayload)   // corrected != nil 보장
  case advisoryOnly(AdvisoryPayload)   // corrected는 표현 불가
  case unsupported(UnsupportedReason)  // corrected는 표현 불가
}
```

→ Illegal states unrepresentable. PTIMER-90 디코더 모순 검증 코드 제거 가능.

---

## 2. 배경 (Why)

`Docs/StructureImprovement/Plan.md` §2.5 타입 시스템 진단:

- 현재 표현은 *flag + optional* — Boolean과 Optional이 *동기화되어야 한다는 invariant*가 런타임 검증에 의존.
- PTIMER-90이 이 invariant를 디코더에서 잡지만, 새 코드 경로가 invariant를 잘못 만드는 위험은 영구.
- enum tagged union으로 표현하면 **잘못된 상태를 코드로 만들 수 없다** (compile-time error).

`Docs/Specs/Calculator.md` §3.5는 결과 메타데이터 7 필드를 명시 + §3.5 끝에 PTIMER-90 invariant 명시. 본 spec은 §3.5의 *시맨틱*을 보존한 채 *표현 형식*만 바꾼다.

---

## 3. 시맨틱 invariant (변경하지 말 것)

1. **`Docs/Specs/Calculator.md` §3.2 평가 순서 6단계 0건 변경** — 정책 평가기 결과 분기 매핑은 동등.
2. **`Docs/Specs/Calculator.md` §3.5 결과 메타데이터 7 필드의 의미 보존** — `calculationBasis`, `sourceAuthorityImpact`, `rangeStatus`, `warningLevel`, `supportingNotes`, `usedReferencePoints`, `didReturnCalculatedTime`. enum 표현에서:
   - `quantified` case가 `correctedExposure` 제공 (옛 `didReturnCalculatedTime = true` 동등)
   - `advisoryOnly` / `unsupported` case는 corrected 미제공 (옛 `didReturnCalculatedTime = false` 동등)
   - 나머지 5 필드는 case별 payload에 보존
3. **`Docs/Specs/Calculator.md` §3.6 confidence presentation 매핑 0건 변경** — basis × authority → category/level/badge 표 동등.
4. **`Docs/Specs/DomainSchema.md` §6 persisted result 시맨틱 보존** — JSON 디코더는 backward-compat: 옛 `{ didReturnCalculatedTime: true, correctedExposure: 2.0, ... }` 페이로드를 새 enum의 `quantified`로 디코드. 옛 `{ didReturnCalculatedTime: false, correctedExposure: null, ... }`을 advisory/unsupported로 디코드.
5. **`Docs/Specs/DomainSchema.md` §13.4 forbidden pattern (디코딩 모순 차단) 보존** — enum 도입 후엔 자명한 invariant.
6. **모든 단위 테스트 동등 통과** — assertion 변경 0건. 단 *어떻게 결과에 접근하는지*(필드 vs case)는 변경됨.

---

## 4. 목표 상태 (What is true after)

- `ReciprocityResult`가 `enum` 타입. 3 case (`quantified`, `advisoryOnly`, `unsupported`) 각각 payload struct 보유.
- 정책 평가기는 enum case를 직접 반환.
- Confidence presentation, view-model layer가 enum case를 switch로 분기.
- JSON 디코더 backward-compat: 옛 페이로드를 enum으로 변환.
- JSON 인코더는 옛 페이로드 형식을 *그대로 출력*하거나 (영속성 호환), 새 형식으로 출력 후 마이그레이션 (택1, §6에서 결정).
- 디코딩 시점의 모순 검증 코드 (`didReturnCalculatedTime` ↔ `correctedExposure?` 일관성) 제거. enum이 자체 보장.

---

## 5. 비-목표

- **시맨틱 변경 0건** — 결과 분기 동등, metadata 동등, presentation 동등.
- **Persisted timer snapshot의 ReciprocityResult 형식 즉시 변경** 금지 — backward-compat 디코더로만 형식 진화. 인코더 형식 결정은 §6.
- **Calculator Spec의 다른 §** 변경 안 함.
- **DomainSchema Spec §11 catalog validator** 변경 안 함 — 카탈로그 자체 변경 없음.
- **새 reciprocity rule 변형 추가** 안 함.

---

## 6. 결정 포인트 (구현 진입 전 확정 필요)

### 6.1 인코딩 형식

| 옵션 | 영속성 호환 | 디코더 단순성 |
|---|---|---|
| (a) 인코더가 옛 7-필드 형식을 출력 (forward-compat 보존) | 강 | 약 (변환 어댑터) |
| (b) 인코더가 새 enum-tagged 형식을 출력, 디코더는 옛+새 둘 다 받음 (backward-compat) | 중 (옛 데이터 read OK, write는 새 형식) | 중 |
| (c) (b) + 마이그레이션 ticket으로 옛 영속 데이터를 새 형식으로 1회 재인코드 | 약 (마이그레이션 필요) | 강 |

**권고**: (b). 영속화된 timer snapshot은 ReciprocityResult를 매번 *새로 평가하지 않고 저장된 값을 읽는다면* read-side만 보장하면 충분. write는 새 형식.

→ B3 ticket spec 머지 전 결정.

### 6.2 enum payload struct 이름

옵션:
- (a) `ReciprocityResult.QuantifiedPayload` 등 nested
- (b) `QuantifiedReciprocityResult` 등 top-level

권고: (a) nested. namespace 명확.

### 6.3 Backward-compat decoder 위치

옵션:
- (a) `init(from decoder:)` 안에서 옛/새 형식 모두 처리
- (b) `LegacyReciprocityResult` 별도 타입 + 변환 헬퍼

권고: (a). 단일 진입점.

---

## 7. 검증 의무

| 레이어 | 의무 |
|---|---|
| **L1** Per-action 자동 | 모든 ReciprocityCalculationPolicyTests, ReciprocityDomainTests, ReciprocityConfidencePresentationTests + 신규 BackwardCompat decoder 테스트 pass |
| **L2** Semantic equivalence | **★★ 결정적, 의무.** **Record-replay 필수**. main에서 모든 정책 평가 케이스의 (input, output) baseline 기록 → branch에서 enum 결과를 옛 7-필드 형식으로 직렬화 → diff 0. baseline은 PTIMER-17 validation samples 전부 + 단위 테스트 핵심 케이스 (최소 70 case). 절차는 record-replay 인프라 ticket 머지 후 적용. |
| **L3** Architectural fitness | 디코딩 모순 검증 코드 (`didReturnCalculatedTime` vs `correctedExposure` 비교) 제거 — F11 영구 lint rule: 해당 패턴 재도입 금지. |
| **L4** UI 회귀 | 무관 — display state는 enum case를 받지만 외부 시그니처 동등. 단 details sheet snapshot test (B8) pass 권장. |
| **L5** Drift | `Docs/Specs/Calculator.md` §3.5 본문 일부 갱신 가능 (enum 표현 명시). spec 시맨틱은 동등. |

---

## 8. 인수 기준 (DoD)

- [x] `ReciprocityResult`가 enum 타입. 3 case + payload struct. (PR2)
- [x] 정책 평가기, confidence presentation, view-model 모두 enum case
  또는 편의 accessor로 분기. (PR2)
- [x] JSON 디코더 backward-compat: legacy 7-field payload를 enum case로
  복원 (PR2). PR1 baseline 77 cases byte-identical replay 통과.
- [x] L2 record-replay: PR1 baseline (`reciprocity-policy-legacy-shape-baseline.txt`)
  PR2 통과로 diff 0 확인. (PR2)
- [x] L3 lint rule F11 (`no_legacy_reciprocity_result_struct`) 추가
  + `PTimer/` 위반 0건. (PR3)
- [x] PTIMER-90 런타임 invariant이 enum 표현으로 컴파일 차단.
  legacy decode 경로의 self-consistency 검증만 잔존 (backward-compat 입력
  검증 목적). (PR2)
- [x] Calculator Spec §3.5 본문을 3-form tagged union 표현으로 갱신;
  시맨틱 동등 명시; 영속성 backward-compat 명문화. (PR3)

---

## 9. 의존 / 후속

### 선행

| 액션 | 사유 |
|---|---|
| **B1** ViewModel 분할 | 권장. ReciprocityModel이 분리되어 있으면 enum 도입 변경 표면적이 명확. |
| **A8** Presenter | 권장. Details surface가 Presenter에 있으면 변경 위치 명확. |
| **Record-replay 인프라** | **필수**. L2 결정적 검증의 도구. 별도 인프라 ticket 머지 후 진입. |
| **B6** Golden fixture | 권장. PTIMER-17 validation samples이 fixture로 정리되어 있으면 baseline 작성 가속. |

### 후속

- B3 후 reciprocity 표현 변경 작업이 더 자연스러워짐 (예: 결과의 새 메타데이터 추가).

---

## 10. 구현 PR 분할 권고

본 spec 머지 + record-replay 인프라 ticket 머지 후:

1. **(PR 1) main에서 baseline 기록** — record-replay 인프라가 있는 main 상태에서 모든 정책 평가 케이스 baseline JSON 저장. PR 본체는 fixture 추가 + 헬퍼 코드.
2. **(PR 2) Enum 도입 + backward-compat decoder + 옛 형식 직렬화 어댑터** — `ReciprocityResult` enum 정의. JSON decoder가 옛/새 둘 다 디코드. 옛 7-필드 형식 직렬화 헬퍼 추가 (replay 비교용). 정책 평가기는 새 enum 반환. confidence presentation, view-model 모두 enum case로 마이그레이션. `didReturnCalculatedTime` 모순 검증 코드 제거. record-replay diff 0 통과.
3. **(PR 3) Lint rule F11 영구 추가, Calculator Spec §3.5 본문 갱신** — 표현 형식 enum 명시. 시맨틱 동등 강조.

각 PR:
- branch `feature/PTIMER-118-b3-result-enum-step-N`
- L2 record-replay 결과 첨부

---

## 11. 위험 / 트레이드

| 위험 | 완화 |
|---|---|
| 새 enum이 옛 7 필드를 *완전히* 표현 못 함 (어떤 필드가 case별로 달라야 하는데 그렇지 않음) | spec ticket에서 enum 정의 자체를 검토 + payload struct 필드 매트릭스 (basis × case) 검증. enum 표현 불가능이면 B3 보류. |
| 영속화된 ReciprocityResult가 거의 없음 (timer snapshot이 매 launch마다 재평가일 가능성) → backward-compat 부담 작음 | 코드 검토에서 영속 경로 확인. 만약 매번 재평가이면 §6.1 옵션 (b) 자명. |
| Confidence presentation의 분기 표가 *flag + optional 기반*으로 작성됨 → enum 마이그레이션 시 표 재구성 필요 | 표 자체는 spec § 3.6에 있고 case 기반으로 자연스러움. presentation 코드만 정리. |

---

## 12. 후속 갱신

본 spec은 *살아있는* 문서. 갱신 트리거:

- 구현 중 결정 포인트 §6 옵션 변경 → spec 갱신.
- record-replay 인프라 ticket spec 작성 시 본 spec § 7 L2 절차를 참조하여 인프라 design 결정.
- B3 머지 후 본 spec은 archive 후보.
