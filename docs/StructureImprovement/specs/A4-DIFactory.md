# A4 — DI Factory Spec

**Status**: Done
**Phase**: 1
**Spec precedence**: required before implementation
**Ticket**: PTIMER-118 (Implement Full Structure Improvement Plan)
**Related actions**: B1 (ViewModel 4분할) — DI factory is a precondition.

---

## 1. 목적

ViewModel 생성 경로에서 **테스트 런타임 분기**(`XCTestRuntime.isRunningTests`)를 제거하고, **dependency injection factory**로 production / test 협력자를 외부에서 주입한다. DIP 정면 위반 해소가 목표.

---

## 2. 배경 (Why)

현재 production 코드의 ViewModel `init`이 *테스트 환경 여부를 직접 검사*해 NoOp / 실 구현을 분기 주입한다. 결과:

- **DIP 위반** — 고수준 모듈(ViewModel)이 테스트 런타임이라는 *환경 결정*을 안다.
- **LSP 약점** — `Storing` 페어가 출력 분포 차이를 가지면서, 호출 측이 두 구현 모두 가정해야 함.
- **테스트 격리 의존** — production code에 `XCTestRuntime` 참조가 남아있는 한, 테스트 인프라 변경이 production code 변경을 강제할 수 있음.

상세 진단: `Docs/StructureImprovement/Plan.md` §2.3 (SOLID), §2.7 (핫스팟 인벤토리).

---

## 3. 시맨틱 invariant (변경하지 말 것)

다음 행동은 본 작업으로 **변경되지 않는다**. 모든 invariant는 변경 전후 동등 검증 의무가 있다:

1. **테스트에서 ViewModel 생성 시 영속성·알림·Live Activity의 부수 효과 0건** — 단위 테스트는 UserDefaults / ActivityKit / UNUserNotificationCenter를 절대 만지지 않는다 (현재 invariant).
2. **Production 앱 실행 시 모든 협력자가 실제 구현으로 동작** — 영속성 복원, 알림 스케줄링, Live Activity 노출 모두 정상.
3. **모든 기존 단위 테스트가 동등 통과** — 테스트 어셔션 변경 0건. 테스트 setup/teardown이 새 factory 호출로 바뀌는 것은 허용.
4. **ViewModel 외부 인터페이스 (publish 프로퍼티·display state·메서드) 0건 변경** — view 측은 어떤 변화도 감지하지 않는다.

---

## 4. 목표 상태 (What is true after)

- **Production code 어디에도 `XCTestRuntime` / `isRunningTests` 참조가 0건**. SwiftLint custom rule(`F1`/`F2` in Verification/Strategy.md §2.3)로 영구 차단.
- **App entry**가 production factory를 만들어 ViewModel에 주입한다.
- **테스트 setup**이 test factory(NoOp 협력자) 또는 test-specific factory를 만들어 ViewModel에 주입한다.
- **ViewModel `init`은 협력자를 매개변수로 받기만 한다** — 어떤 협력자 *선택* 로직도 가지지 않는다.
- 협력자 *어떤 것을 사용할지* 결정은 factory에서, *언제 사용할지* 결정은 ViewModel에서 (책임 분리).

---

## 5. 비-목표

- ViewModel의 책임 분할 (B1)은 본 spec 범위 밖. 본 작업은 ViewModel을 모놀리스로 둔 채 *주입 경로만* 바꾼다.
- 새로운 protocol 추가 (예: `ExposureCalculating`)는 본 작업 범위 밖. 기존 `*Storing` / `*Scheduling` 페어를 그대로 활용한다.
- App lifecycle / scene 관리 변경 안 함.
- 테스트 케이스 추가/삭제/시맨틱 변경 안 함.
- Live Activity 시맨틱 (PTIMER-69) 변경 안 함.

---

## 6. 검증 의무

`Docs/Verification/Strategy.md`의 5 레이어 매핑:

| 레이어 | 의무 |
|---|---|
| **L1** Per-action 자동 | 모든 ViewModelTests + TimerManagerTests 동등 통과. SwiftLint pass. 시뮬레이터 빌드 통과. |
| **L2** Semantic equivalence | **★★ 결정적**. 시맨틱 등가는 두 가지로 검증: (a) 모든 단위 테스트 동등 통과, (b) production app 수동 스모크 (앱 실행 → 타이머 1개 시작 → 영속성 → 재시작 후 복원 확인). record-replay까지는 불필요 (행동 자체는 변하지 않음). |
| **L3** Architectural fitness | **새 lint rule 영구 추가** — `F1: production code shall not import XCTestRuntime`, `F2: production code shall not reference isRunningTests`. SwiftLint regex rule로. |
| **L4** UI 회귀 | 무관 (도메인 변경, view 측 변화 없음). |
| **L5** Drift | 영향 없음. |

`Docs/Specs/`의 spec § 변경: 없음 (도메인 행동 변경 아님).

---

## 7. 인수 기준 (DoD)

- [ ] `XCTestRuntime.isRunningTests`가 production source(`PTimer/`)에서 0건. SwiftLint F1/F2 rule이 영구 차단.
- [ ] App entry에 production factory 추가. ViewModel은 매개변수 주입만 받음.
- [ ] 테스트 setup이 test factory를 명시적으로 사용.
- [ ] 모든 기존 ViewModelTests + TimerManagerTests 동등 통과.
- [ ] 신규 단위 테스트: factory 자체(production·test 두 종류)의 단위 테스트 추가.
- [ ] 시뮬레이터 스모크 통과 (앱 시작 → 타이머 시작 → 백그라운드 → 재실행 → 복원 확인).

---

## 8. 의존 / 후속

- **선행**: 없음. Phase 0 완료 후 진입 가능.
- **후속**: B1 (ViewModel 4분할)이 본 작업의 결과 위에 진행됨. B1 spec은 본 spec의 invariant + 4분할 추가 invariant를 결합.

---

## 9. 구현 PR 분할 권고

본 spec 머지 후 다음과 같이 구현 PR 분할 권장:

1. (구현 PR 1) Factory 타입과 production factory 추가, ViewModel에 매개변수 주입 경로 추가 (XCTestRuntime 분기는 *남겨둔다*). 테스트는 기존대로.
2. (구현 PR 2) 테스트 setup이 test factory를 사용하도록 마이그레이션. 모든 테스트 동등 통과 확인.
3. (구현 PR 3) Production code의 XCTestRuntime 분기 제거. SwiftLint F1/F2 rule 추가.

각 PR은 `feature/PTIMER-118-a4-di-factory-step-N` 형태 branch.

---

## 10. 후속 갱신

본 spec은 *살아있는* 문서. 갱신 트리거:

- 구현 중에 invariant가 부정확하게 잡혔음을 발견 → 본 spec 갱신 후 PR 진행.
- B1 spec이 본 spec의 일부를 흡수하면 본 spec은 archive 후 삭제 가능.
