# A8 — FilmModeDetailsPresenter Extraction Spec

**Status**: Done
**Phase**: 2
**Spec precedence**: required before implementation
**Ticket**: PTIMER-118 (Implement Full Structure Improvement Plan)
**Related actions**: A2 (FilmContext split, prerequisite), B1 (ViewModel 4분할, successor — A8 is the first incremental step toward B1's `ReciprocityModel`)

---

## 1. 목적

현재 `ExposureCalculatorViewModel`이 직접 보유한 **필름 모드 reciprocity details surface**의 표현 책임을 별도 *Presenter* 타입으로 추출한다. ViewModel 모놀리스 슬림화의 첫 점진적 단계이자, B1의 `ReciprocityModel` 분리를 위한 표면적 정리.

---

## 2. 배경 (Why)

`Docs/StructureImprovement/Plan.md` §2.1 인지복잡도 분석에서 ViewModel은 6 책임 모놀리스다. 그 중 reciprocity details (graph, formula reference, source list, profile authority row) 표현은 **자족 가능한 응집 단위**이며, 다른 ViewModel 책임과 혼재할 필요가 없다. 추출 시:

- ViewModel 라인 / 타입 카운트 즉시 감소
- B1의 `ReciprocityModel` 분리 시 Presenter가 그대로 흡수 가능
- Reciprocity details 변경 (UI Spec §2.6, PTIMER-95·100·112)이 ViewModel을 건드리지 않음

---

## 3. Scope of extraction

추출 대상 책임:

- 활성 film identity의 active profile 결정
- Profile authority(Official/Unofficial) 표시 데이터 생성 (PTIMER-112, [UI Spec](../../Specs/UI.md) §2.6)
- Reciprocity details sheet의 4 섹션 데이터 생성 (Profile / Formula·Reference / Graph / Sources, [UI Spec](../../Specs/UI.md) §2.6)
- 그래프 reference data (canonical 120 s 상한, PTIMER-112)
- Formula 표현 (math-style typography 데이터)
- Detail-mode coarse / precise 시간 표현 분기 ([UI Spec](../../Specs/UI.md) §2.4)

**비-추출** (ViewModel에 남는 것):

- Adjusted Shutter / Corrected Exposure 결과 자체 (Reciprocity 정책 평가 결과)
- Timer 시작 affordance 활성화 로직
- Film 선택·해제 액션
- Picker sheet state

---

## 4. 시맨틱 invariant (변경하지 말 것)

1. **Details surface 표시 출력 0건 변경.** sheet 진입·표시·닫힘 동작 보존. 모든 디스플레이 상태 타입의 외부 시그니처 보존.
2. **`Docs/Specs/UI.md` §2.6 행동 계약 보존** — section 순서 (Profile → Formula → Graph → Sources), 0.85 detent, 120 s graph 상한, Authority row 항상 노출.
3. **Reciprocity 정책 평가 0건 변경** — A8은 *표현 추출*이지 *정책 변경*이 아니다. `Docs/Specs/Calculator.md` §3.5 result metadata 시맨틱 그대로.
4. **모든 단위 테스트 동등 통과.** assertion 변경 0건.
5. **A4 invariant 보존** — Presenter도 협력자를 외부에서 받는다. `XCTestRuntime` 참조 0건.

---

## 5. 목표 상태 (What is true after)

- `FilmModeDetailsPresenter` 타입이 별도 파일에 거주. 위치 권고: `PTimer/ExposureCalculator/Presenters/FilmModeDetailsPresenter.swift` (단, B1 진입 시 `Models/ReciprocityModel`로 흡수될 위치).
- ViewModel은 Presenter를 **소유**(또는 협력자로 보유)하고 details 표시 데이터 요청을 위임.
- Presenter는 `FilmIdentity`, 활성 metered exposure, 정책 평가 결과를 입력으로 받아 디스플레이 상태 타입(예: details sheet의 4 섹션 모델)을 출력.
- Presenter의 입력은 *값*만. 외부 lifecycle / async 의존 없음. 단위 테스트 가능.
- ViewModelTests 중 details 관련 테스트는 Presenter 단위 테스트로 자연스럽게 분할 (A11과 호환).

---

## 6. 비-목표

- **ViewModel의 다른 책임 추출** 안 함 (B1에서). 본 작업은 *details Presenter만*.
- **Reciprocity 정책 평가기 변경** 안 함.
- **`Docs/Specs/UI.md` §2.6 시맨틱 변경** 안 함. 단지 표현 코드의 *위치*가 바뀐다.
- **새 디스플레이 상태 타입 추가** 안 함. 기존 타입 재사용.
- **Presenter protocol 화** 안 함 (B1에서 모델 통신 정리할 때 결정). A8은 concrete type으로 충분.

---

## 7. 검증 의무

| 레이어 | 의무 |
|---|---|
| **L1** Per-action 자동 | 모든 ViewModelTests + 신규 PresenterTests pass |
| **L2** Semantic equivalence | **★★** **record-replay**: 같은 input(metered + profile)에 같은 details display state 출력. baseline은 main에서 기록 후 branch에서 diff 0. (`Docs/Verification/Strategy.md` §6 절차) |
| **L3** Architectural fitness | Presenter는 `Foundation`만 import (도메인 순수성, F4 영구 추가). |
| **L4** UI 회귀 | Details sheet snapshot test (B8 진행 시) pass. 매뉴얼: 6 film(official table·formula·threshold·advisory·unofficial 등)에서 details sheet 확인. |
| **L5** Drift | spec § 갱신 0건. |

`Docs/Specs/UI.md` 갱신: 없음. (Presenter는 같은 spec을 만족시키는 *다른 코드 구조*.)

---

## 8. 인수 기준 (DoD)

- [ ] `FilmModeDetailsPresenter`가 별도 파일·타입으로 분리.
- [ ] ViewModel은 Presenter 호출만 보유, details 로직 내부 코드 0줄.
- [ ] PresenterTests 신규 추가 (최소: 5 film 케이스 × 4 섹션 매트릭스).
- [ ] 기존 ViewModelTests 동등 통과.
- [ ] L2 record-replay baseline diff 0.
- [ ] L3 fitness — Presenter import는 `Foundation`만.
- [ ] PR 분할 권고대로 단계 진행.

---

## 9. 의존 / 후속

### 선행

| 액션 | 사유 |
|---|---|
| **A2** FilmContext split | details display state 23 타입이 `FilmContext/`에 정리되어야 Presenter가 깨끗이 import. |
| **A4** DI factory | (권장) Presenter도 협력자 주입 받음. A4 머지 후가 안전. |

### 후속

- **B1** ViewModel 분할의 PR 2(`ReciprocityModel` 도입)에서 Presenter를 흡수.
- **B3** Result enum 도입 시 Presenter가 새 enum을 직접 매칭하도록 갱신 (API 표면 정리됨).

---

## 10. 구현 PR 분할 권고

본 spec 머지 후 2 단계 PR:

1. **(PR 1) Presenter 도입 + ViewModel 위임** — `FilmModeDetailsPresenter` 타입 생성, ViewModel은 Presenter를 owns. 기존 ViewModel 메서드들은 Presenter 호출로 전환. 단위 테스트 추가. ViewModelTests 동등 통과 + PresenterTests 신규 통과.
2. **(PR 2) ViewModelTests 중 details 관련을 PresenterTests로 마이그레이션** — A11 테스트 분할의 일부. 어셔션 시맨틱 보존.

각 PR:
- branch `feature/PTIMER-118-a8-presenter-step-N`
- L2 baseline diff 0 명시

---

## 11. 위험 / 트레이드

| 위험 | 완화 |
|---|---|
| Presenter 입력 값 시그니처가 ViewModel 내부 의존을 노출 | 입력은 도메인 값(`FilmIdentity`, `Double`, 정책 결과)으로 한정. ViewModel 내부 protocol 의존 금지. |
| B1 도입 시 Presenter 위치(`Presenters/`)가 다시 이동(`Models/`) | 위치 이동은 mechanical. PR 비용 작음. 본 spec은 위치를 *권고*로 명시. |
| Details sheet에서 `@State` 의존(detent fraction 등) | Presenter는 데이터 생성만. UI state(`@State` selection)는 view 측에 남는다. |

---

## 12. 후속 갱신

본 spec은 *살아있는* 문서. 갱신 트리거:

- B1 spec이 ReciprocityModel의 표면적을 확정하면 본 spec의 §3 Scope를 재검토.
- 구현 중 invariant 부정확 발견 → spec 갱신 후 PR 진행.
- B1 머지 후 본 spec은 archive 후보.
