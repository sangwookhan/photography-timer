# Refactoring Specs

본 디렉토리는 **Spec 선행 필수 액션**의 변경 invariant·시맨틱 등가 의무·트레이드를 정의하는 *리팩토링 스펙*을 모은다.

이 spec은 **도메인 행동 계약** (`Docs/Specs/`)과 다르다:

| 종류 | 위치 | 무엇 | 수명 |
|---|---|---|---|
| 도메인 행동 계약 | `Docs/Specs/` | 시스템이 *무엇을 해야 하는가* (Calculator/Timer/UI/DomainSchema) | 영구 |
| 리팩토링 스펙 | `Docs/StructureImprovement/specs/` | *어떻게 코드를 재구조화* (DI factory, ViewModel 4분할 등) | Epic 종료 시 삭제 |

## 액션별 spec (Plan.md §3)

| 액션 | Phase | 파일 | 상태 |
|---|---|---|---|
| **A4** DI factory | 1 | [A4-DIFactory.md](A4-DIFactory.md) | Draft |
| **A8** FilmModeDetailsPresenter 추출 | 2 | [A8-FilmModeDetailsPresenter.md](A8-FilmModeDetailsPresenter.md) | Draft |
| **A9** LockScreenTimerCoordinator 분리 | 3 | [A9-LockScreenTimerCoordinator.md](A9-LockScreenTimerCoordinator.md) | Draft |
| **A12** Tri-X 1s 데이터 reconciliation | 3 | [A12-TriXDataReconciliation.md](A12-TriXDataReconciliation.md) | Draft |
| **B1** ViewModel 4분할 | 3 | [B1-ViewModelDecomposition.md](B1-ViewModelDecomposition.md) | Draft |
| **B3** Reciprocity Result enum | 3 | [B3-ReciprocityResultEnum.md](B3-ReciprocityResultEnum.md) | Draft |
| **B4** Timer state 타입 강화 | 3 | [B4-TimerStateTypes.md](B4-TimerStateTypes.md) | Draft |

## 사용 규칙

- 각 spec은 *변경하지 말아야 할 시맨틱*을 명시한다 (invariant).
- 시맨틱 변경 가능성 있는 액션은 **record-replay baseline**을 의무화한다 (`Docs/Verification/Strategy.md` §6).
- spec은 머지 후 구현 PR과 분리한다 (한 PR = 한 책임).
