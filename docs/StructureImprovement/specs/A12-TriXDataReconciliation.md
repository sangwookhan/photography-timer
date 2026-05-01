# A12 — Tri-X 1s Catalog Data Reconciliation Spec

**Status**: Done
**Phase**: 3
**Spec precedence**: required before implementation
**Ticket**: PTIMER-118 (Implement Full Structure Improvement Plan)
**Related actions**: 독립. 다른 액션 의존 없음.

---

## 1. 목적

번들 launch preset catalog의 **Kodak TRI-X 400 프로파일**에서 metered=1s 위치의 데이터가 위키 권위(`Docs/Sources/wiki/05_reciprocity/15138817_PTIMER_Reciprocity_Validation_Samples.md`)와 어긋난 부분(있다면)을 *권위 출처에 맞추어* 정정한다. 사용자에게 노출되는 reciprocity 결과의 정확성을 위한 데이터 작업이지 코드 변경이 아니다.

---

## 2. 배경 (Why)

`Docs/StructureImprovement/Plan.md` §2.7과 §3.8에 등장한 핫스팟 R-H2: 위키 15138817 (Reciprocity Validation Samples) Tri-X 400 표는 metered = 1 s에서 **+1 stop = corrected 2 s, dev −10%** 를 명시한다. 코드의 `LaunchPresetFilmCatalog.json`의 Tri-X 항목이 이 값과 일치하는지 검증·정정해야 함.

이전 commit log에서 PTIMER-98이 "Tri-X preset alignment with no-correction at/below 1 s"를 기록 — 본 spec은 그 결정을 위반하지 않는다. 다만 1 s *위*의 데이터가 위키와 일치하는지 별개로 검증.

---

## 3. 검증 / 정정 대상

### 3.1 검증

다음 4 metered 점에서 코드 카탈로그와 위키 표 일치 여부 검증:

| metered (s) | 위키(15138817) corrected (s) | 위키 stop delta | 위키 dev adjustment |
|---|---|---|---|
| 1.0 | 2.0 | +1 | dev −10% |
| 10.0 | 50.0 | +2 (≈) | dev −20% |
| 100.0 | 1200.0 | +3 (≈) | dev −30% |

### 3.2 정정 (불일치 발견 시)

- corrected 값 정정 (위키 일치).
- stop delta / dev adjustment 메타데이터 정정.
- threshold 영역 (≤1 s no-correction)은 PTIMER-98 결정 보존.

### 3.3 비-정정

- 표에 없는 metered 점은 본 작업으로 *추가하지 않는다*. 추가 데이터는 별도 ticket.
- 다른 film(Velvia 50, Portra 400 등) 검증은 본 작업 범위 밖.

---

## 4. 시맨틱 invariant (변경하지 말 것)

1. **`Docs/Specs/DomainSchema.md` §11 카탈로그 검증 규칙 9건 모두 통과** — 정정 후에도 catalog validator pass.
2. **`Docs/Specs/Calculator.md` §3.2 평가 순서 0건 변경** — 정책 평가기는 그대로. 단지 입력 데이터의 *값*이 정정됨.
3. **PTIMER-98 결정 보존** — Tri-X threshold ≤1 s 영역은 no-correction.
4. **JSON 스키마 0건 변경** — 카탈로그 파일 형식 그대로. 값만 변경.
5. **Provenance 필드 보존** — `source.kind = manufacturer_published`, `authority = official`, publisher / title / citation / sourceVersion 그대로 (위키 인용 그대로).

---

## 5. 목표 상태 (What is true after)

- `LaunchPresetFilmCatalog.json`의 Tri-X 400 entry가 위키 15138817 §Tri-X 표와 일치.
- 정정 후 ReciprocityCalculationPolicyTests의 Tri-X 테스트 케이스가 정정된 값에 맞춤 (단위 테스트 어셔션 갱신).
- 위키 정합성 audit이 분기별 Spec drift 검사에 들어감 (`Docs/Verification/Strategy.md` §2.5).

---

## 6. 비-목표

- **다른 film 검증** 안 함.
- **위키 자체 변경** 안 함. 위키가 *권위*다.
- **카탈로그에 새 metered 점 추가** 안 함.
- **Reciprocity 정책 평가기 / Confidence presentation 변경** 안 함.
- **Threshold 영역(≤1 s) 변경** 안 함.

---

## 7. 검증 의무

| 레이어 | 의무 |
|---|---|
| **L1** Per-action 자동 | 정정된 Tri-X 데이터에 대한 정책 평가 단위 테스트 pass + catalog validator pass |
| **L2** Semantic equivalence | **★★ 결정적**. 두 가지: (a) 위키 표와 코드 데이터의 직접 비교 — 자동 검증 스크립트 또는 단위 테스트 추가. (b) 정정 *전* 단위 테스트 케이스 일부가 *틀린* 값을 어셔션하고 있을 수 있으므로 (위키와 어긋난 채 잠겨 있던 경우), 그 어셔션은 *명시적으로 정정* + 정정 사유를 commit body에 명시. |
| **L3** Architectural fitness | 무관 |
| **L4** UI 회귀 | 사용자 메뉴얼 검증: Tri-X 선택 + base shutter 1/30·1·10s에서 corrected 결과를 위키 값과 비교. |
| **L5** Drift | spec § 갱신 0건. 단 spec-code audit 체크리스트(`Docs/Verification/Strategy.md` §2.5)에 catalog 검증 항목 추가 권장. |

---

## 8. 인수 기준 (DoD)

- [ ] Tri-X 400 entry의 4 metered 점 (1, 10, 100 s + threshold 영역) 위키 일치.
- [ ] 정정으로 인해 어셔션이 변경된 단위 테스트가 있다면 commit body에 *어떤 어셔션이 왜 변경*되었는지 명시.
- [ ] catalog validator pass.
- [ ] 정책 평가 단위 테스트 (Tri-X 케이스) pass.
- [ ] 사용자 메뉴얼 검증 — Tri-X 1s metered → corrected 2.0 s 결과 확인.
- [ ] (권고) `Docs/Verification/Strategy.md` §2.5 audit 체크리스트에 catalog 일관성 항목 추가.

---

## 9. 의존 / 후속

### 선행

| 액션 | 사유 |
|---|---|
| 없음 | 독립 작업. 다른 액션과 병렬 가능. |

### 후속

- 본 작업 후 Tri-X 외 다른 film의 위키 일관성 audit이 sequential 후속 ticket으로 가능.

---

## 10. 구현 PR 분할 권고

작은 작업이라 단일 PR:

1. **(PR 1)** 카탈로그 데이터 정정 + 단위 테스트 어셔션 갱신 (필요 시) + 매뉴얼 검증 결과 첨부 + spec audit 체크리스트 갱신.

branch: `feature/PTIMER-118-a12-trix-reconciliation`

---

## 11. 위험 / 트레이드

| 위험 | 완화 |
|---|---|
| 정정 *전* 단위 테스트가 *틀린 값에 잠겨* 있어, 정정으로 회귀 *처럼 보임* | commit body에 위키 출처 인용 + before/after 명시. PR 리뷰 시 위키 권위 확인. |
| 사용자 가시 결과 변경 (Tri-X 사용자에게 corrected 시간이 달라 보임) | 사용자 메뉴얼 검증 + 사용자에게 정정 사유 안내 (changelog 또는 in-app 안내, 후순위). |
| 위키 자체가 부정확 / 다른 권위가 위키와 충돌 | 본 spec은 위키를 권위로 *전제*. 위키 검토는 별도 ticket. PTIMER-86 PresetDatasetPolicy의 conflict resolution policy 참조. |

---

## 12. 후속 갱신

본 spec은 *살아있는* 문서. 갱신 트리거:

- 정정 결과 commit 후 본 spec status를 "Done" 으로 갱신.
- 다른 film 일관성 audit이 후속 ticket으로 분할되면 본 spec은 archive.
