<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# 검증 전략 (Verification Strategy)

**작성일**: 2026-04-27
**유형**: 검증 절차 가이드
**현재 위치**: `docs/verification/Strategy.md`
**관련 절차**: `docs/verification/{BackgroundNotificationDelivery,RelaunchRestore}.md`

---

## 1. 목적

PTIMER 구조 개선 작업이 다음을 만족하도록 보장:

- (a) 의도된 변경만 일어나고 시맨틱이 동등하게 보존
- (b) 보호 영역의 invariant가 유지
- (c) 한 번 정한 구조 결정이 시간 경과로 침식되지 않음
- (d) UI 동작이 회귀하지 않음
- (e) spec과 코드 사이의 drift가 조기 감지됨

단일 테스트 suite로는 위 5종을 다 잡지 못함. **5 레이어로 분담**.

---

## 2. 검증 5 레이어

### L1. Per-action 자동 검증

**목적**: PR 단위로 build/test/lint 회귀 차단

**무엇을**:
- 패키지 테스트 통과 (`swift test --package-path ios/PTimerKit` —
  `PTimerCoreTests`/`PTimerKitTests`, 시뮬레이터 불필요, 테스트 대다수)
- Xcode build (`cd ios && xcodebuild test`) 통과
- app-hosted 단위 테스트 통과 (`ios/PTimer.xctestplan` — OS 경계
  스위트)
- SwiftLint warning/error 0
- Coverage 비-회귀 (after coverage gating is introduced: 이전 대비 −1% 이내)

**도구**: local `swift test` / `xcodebuild` / `swiftlint`, and CI when configured

**언제**: 모든 PR

**부족한 점**: 테스트가 *기존에 발견되지 않은* 회귀를 잡지 못함 → L2 필요.

---

### L2. Semantic equivalence 검증

**목적**: 시그니처/표현이 변경된 작업이 시맨틱 동등을 유지하는지

**3중 안전망**:

#### (a) Spec-driven property test

spec의 각 invariant를 직접 property test로 변환. 예: Calculator Spec §3.2의 평가 순서 5단계를 `(metered, profile)` 조합 1만 케이스에 대해 변경 전/후 동일 결과 반환을 검증.

도구: 표준 XCTest. 외부 라이브러리 불필요. 필요 시
fixture-driven 테스트 또는 deterministic snapshot helper를 추가한다.

#### (b) Record-replay

변경 *전* 코드로 event sequence나 display state를 baseline text로
저장 → 변경 *후* 코드로 동일 시나리오 실행 → diff 0 확인.
절차는 §6에서 자세히.

대상: 정책 평가기 입출력, ViewModel 디스플레이 상태 합성, TimerManager 라이프사이클 결과.

#### (c) Golden fixture

spec의 대표 케이스를 `shared/test-fixtures/`의 JSON으로 영구 저장. 양 플랫폼(iOS·Android)이 공유.

(b)와의 차이: (c)는 spec-curated, 영구. (b)는 작업 시점의 현재 동작 snapshot.

관리형 카메라 persistence는 release migration fixture를 추가로 유지한다.
이 절은 정확한 릴리즈 버전, fixture 내용, migration 경로, 설치 업그레이드
절차의 단일 source of truth이다. Requirements와 Living Specs는 이 절을
참조하며 해당 세부사항을 반복하지 않는다.

- 0.8.0 기준 fixture는 플랫폼별 실제 release source에서 만든다.
  iOS는 marketing version 0.8.0, build 1의 마지막 iOS 변경
  `bedd9e107679437baec4ea68d3e1300cf2aaf535`를 사용한다. Android는
  versionName 0.8.0, versionCode 5의 Play 업로드 준비가 합쳐진
  `35f5fce6c2970b70845df7747c54fe76343c8ef3`를 사용한다. 두 커밋 사이의
  변경은 Android 파일에만 있으며 iOS 저장 형식은 같다. 각 플랫폼의 release
  configuration으로 생성한 네 슬롯 원본 payload를 보존한다. Camera 1은
  `Nikon Z7`(film 없음, Target Shutter 2분), Camera 2는
  `Hasselblad 503CX`(`Kodak TMAX 100`, Target Shutter 30분),
  Camera 3은 `Nikon F2`(`Kentmere 100`, Target Shutter 없음)로
  설정하고 Camera 4는 출고 기본 상태로 둔다. 0.8.0에는 Sample Filter
  Set이 없으므로 이 fixture에는 Sample inventory/selection을 넣지 않는다.
- 과거 0.8.0 release source에는 불변 tag
  `release/ios/0.8.0`과 `release/android/0.8.0`을 각각 위 커밋에
  생성한다. 과거 submission tag는 소급 생성하지 않는다.
- 앞으로 스토어에 업로드할 때마다
  `submission/<platform>/<version>-build<build>` annotated tag를 즉시
  생성한다. 거절되거나 교체된 submission tag도 보존하고, 다음 업로드는 새
  build 번호의 tag를 사용한다. 스토어 승인 후 같은 커밋에
  `release/<platform>/<version>` annotated tag를 한 번 생성한다. 공유된
  submission/release tag는 삭제하거나 다른 커밋으로 이동하지 않는다. Tag
  message는 플랫폼, version, build 번호, 업로드 또는 승인 날짜를 기록한다.
- 릴리즈와 migration fixture의 source 단위는 항상 GitHub에서 합쳐진 PR의
  merge commit이다. PR 내부 중간 커밋은 source로 사용하지 않는다. 플랫폼별
  릴리즈 준비가 서로 다른 PR에서 끝나면 iOS와 Android release tag는 서로
  다른 merge commit을 가리킬 수 있다.
- 플랫폼별 원본 저장 형식은 따로 보관할 수 있지만 기대하는 semantic state는
  공유한다.
- 지원되는 두 경로인 0.8.0 → 현재 개발 schema와 0.9.1 → 현재 개발
  schema를 iOS와 Android 단위 테스트로 각각 검증한다. 0.8.0 migration
  과정에서 Sample Filter Set inventory가 seed되더라도 migration만으로
  카메라에 자동 선택되지 않는지 확인한다.
- 0.9.1 migration fixture test는 시험을 시작할 때의 최신 `main` PR
  merge commit으로 iOS와 Android에서 먼저 수행한다. 현재 기준 source는
  `9213f12a4ddd81334f304a10e491bba96216a806`(#74)이다. 이 시험 fixture는
  PTIMER-234 개발 검증용이며 현재 iOS MARKETING_VERSION과 README가
  0.9.0인 사실 때문에 공식 iOS 0.9.1 release fixture라고 주장하지 않는다.
  시험 전에 `main`이 다른 PR merge commit으로 전진했다면 두 플랫폼 모두
  그 최신 merge commit에서 fixture를 다시 만든다. 플랫폼별 스토어 승인 후
  불변 tag `release/ios/0.9.1`과 `release/android/0.9.1`이 생기면 각
  tag가 가리키는 merge commit으로 공식 fixture와 설치 업그레이드 증거를
  다시 생성하여 개발 fixture를 대체한다. `Nikon Z7`은
  `Digital Magnetic Filters`를 선택한다. 두 필름 카메라
  `Hasselblad 503CX`와 `Nikon F2`는 공용으로
  `Film Square ND/GND`와 `Film Color Filters`를 모두 선택한다.
  Camera 4는 기본 상태로 둔다. 이후 버전으로 migration할 때 Sample Set
  stable id와 카메라별 선택을 보존한다.
- 현재 release가 지원하는 fixed-slot 저장 형식은 위의 공식 0.8.0과 0.9.1
  fixture가 대표한다. Pre-release Draft, 수동 수정, 오염된 개발 데이터는
  migration fixture가 아니며 개발·시험 기기에서 앱 데이터 삭제 또는
  재설치로 제거한다.
- 자동 이름 sequence가 없거나 읽히지 않는 경우의 fixture는 첫 Add가 일반
  할당 경로로 `Camera 5`를 만들기 전에 6을 저장하고, 다음 Add가
  `Camera 6`을 만드는지 양 플랫폼에서 검증한다. 기존에 같은 표시 이름이
  있어도 새 camera identity를 사용하는지 확인한다.
- 인식 가능한 shape의 누락 필드 fixture는 새 identity, `Camera`, shown,
  fresh calculator state, 첫 shown active 기본값과 정규화 저장을 검증한다.
  keyed record가 아닌 entry는 제외하고, duplicate identity의 첫 record는
  유지하며 이후 record에는 새 identity를 발급한다.
- 저장 내용은 성공적으로 읽었지만 version, camera collection 또는 전체
  managed payload를 decode할 수 없는 fixture는 새 opaque identity 네 개를
  사용한 fresh state로 한 번에 교체되는지, 교체 사이에 legacy migration이
  실행되지 않는지, timer snapshot이 보존되는지 검증한다. 독립 sequence가
  유효한 값 12인 fixture는 replacement sequence 12를 보존하고, sequence가
  없거나 읽히지 않는 fixture는 5를 사용하는지 각각 검증한다. 저장소 read가
  content 없이 실패하는 fixture는 delete/write/legacy migration이 모두 없고
  camera action이 비활성화되며 `Camera data couldn't be loaded. Restart the
  app.` 설명이 표시되고 다음 launch에서 initialization을 재시도하는지
  별도로 검증한다.
- 첫 공식 managed-camera release 이후의 모든 공식 릴리즈는 해당 릴리즈
  코드나 설치 앱에서 생성한 fixture를 추가한다. 이후 테스트는 보존된 모든
  공식 fixture를 현재 schema까지 migration하여 stable id, 이름,
  디지털/필름 계산 상태, Filter Set inventory/selection, 순서, 표시 상태,
  active camera와 자동 이름 sequence를 검증한다.
- 사람이 현재 schema를 보고 과거 fixture JSON을 다시 작성하지 않는다.

**언제**: 시맨틱 변경 가능성이 있는 모든 구조 변경 PR과 managed-camera
schema/migration 변경 PR.

---

### L3. Architectural fitness 검증

**목적**: 한 번 정한 구조 결정이 시간 경과로 침식되지 않는지 — 매 PR마다 *구조 invariant*를 자동 검증

**Fitness function 카탈로그**:

| # | 규칙 | 트리거 | 도구 |
|---|---|---|---|
| F1 | Production code shall not import `XCTestRuntime` | after the test-runtime coupling is removed | SwiftLint regex rule |
| F2 | Production code shall not reference `isRunningTests` | after the test-runtime coupling is removed | SwiftLint regex rule |
| F3 | `ios/PTimer/Reciprocity/*` shall not import UIKit/SwiftUI | 도메인 순수성 | SwiftLint imports rule |
| F4 | `ios/PTimer/Reciprocity/*` and `ios/PTimer/ExposureCalculator/ExposureCalculator.swift` shall import only `Foundation` | 보호 영역 | SwiftSyntax 검사 |
| F5 | ViewModel/Models shall not directly instantiate concrete domain evaluators (use protocol) | after model-boundary enforcement is introduced | SwiftSyntax 검사 |
| F6 | Any source file shall not exceed 1,000 lines | after layer-size and decomposition enforcement is introduced | SwiftLint `file_length` |
| F7 | Any function shall not exceed 50 lines / CC 10 | after function/file-size enforcement is introduced | SwiftLint `function_body_length`/`cyclomatic_complexity` |
| F8 | View files shall not import policy/domain types directly | 레이어 단방향 | SwiftSyntax 검사 |
| F9 | `docs/specs/*` 인용한 코드 주석은 실재 § 참조해야 | 신규 권장 | 자체 검사 (grep + spec 파일 anchor 확인) |
| F10 | Persistence keys shall not be inlined; must use `*Storing` 페어 | after the persistence-key surface is enforced | SwiftSyntax 검사 |

**도구 선택지**:
- **SwiftLint custom regex rule**: 빠르고 가능한 것 (F1/F2/F3/F6/F7)
- **SwiftSyntax 기반 자체 검사**: 의존성 그래프, 타입 사용, 정밀 (F4/F5/F8/F10)
- **`periphery`**: unused code, dead config 검출 (보조)

**언제**: CI 게이트 — 모든 PR

**비용**: SwiftLint 규칙 추가는 5분/규칙. SwiftSyntax 검사는 처음 1주 + 보존 영구.

---

### L4. UI 회귀 검증

**목적**: View 변경이 화면 동작을 바꾸지 않는지

**2중 방어**:

#### (a) Snapshot 자동

현재 자동 snapshot은 in-house display-state snapshot이다. helper는
baseline을 호출 테스트 파일 위의 가장 가까운 지원 루트(`PTimerTests`
또는 `PTimerKitTests`) 아래에서 해석한다. display-state snapshot
스위트는 PTIMER-174에서 `PTimerKitTests`로 이전되어 off-simulator로
실행된다. 위치: `ios/PTimerKit/Tests/PTimerKitTests/Snapshots/`,
baseline:
`ios/PTimerKit/Tests/PTimerKitTests/__Snapshots__/<TestClass>/<name>.txt`.

이 helper는 SwiftUI 픽셀 비교가 아니라 ViewModel/Presenter/Mapper가
emit하는 `Equatable` display state의 결정적 직렬화를 lock한다.
픽셀 수준 View 회귀는 아직 자동화하지 않고, View가 닿는 PR에서
매뉴얼 스모크나 스크린샷 리뷰로 보강한다.

#### (b) 매뉴얼 스모크 매트릭스

|             | 타이머 0개 | 타이머 1개 | 타이머 3개+ |
|-------------|-----------|-----------|-------------|
| Regular     | ✓         | ✓         | ✓           |
| Compact     | ✓         | ✓         | ✓           |
| Dense       | ✓         | ✓         | ✓           |

× 필름 모드 on/off (Tri-X 1s, Velvia 4s, PORTRA 2s 케이스 포함)
× 잠금화면 widget on/off (단일·다중 타이머)

**설치 업그레이드 검증**: 공식 0.8.0과 0.9.1 fixture가 iOS와 Android
단위 테스트에서 현재 schema까지 통과하면, 설치된 실제 데이터의 업그레이드
시험은 최신 공식 릴리즈 → 후보 릴리즈 경로만 수행한다. 0.9.1 설치 데이터는
0.8.0에서 위의 Nikon Z7 + Hasselblad 503CX + Nikon F2 구성을 만든 뒤
업그레이드하여 준비한다. fixture가 실패하면 영향을 받는 설치 업그레이드
경로를 추가로 재현한다. Draft 또는 오염된 개발 데이터는 이 검증의 입력으로
사용하지 않는다.

Managed-camera UI 변경은 iOS와 Android에서 같은 fixture와 같은 언어로
utility page, all-hidden empty state, management normal mode, management edit
mode, delete confirmation을 각각 캡처한다. 두 플랫폼의 native container 차이는
허용하되, row 정보 순서, visible actions, swipe-to-delete, drag reorder, bottom
actions, 문구의 동일성을 나란히 검토한다.

Cameras 화면의 시각 위계는 각 플랫폼이 지원하는 appearance에서 확인한다.
iOS는 light와 dark, 현재 dark-only인 Android는 dark를 캡처한다. Close, Edit,
Done이 다른 시트와 같은 플랫폼 표준 모양인지, 대비와 터치 영역이 충분한지
확인한다. Add camera는 채움 없는 테두리 버튼인지, 라벨 대비 4.5:1, 테두리
대비 3:1, 높이 44~48을 만족하는지 측정한다. 라벨은 중립색이고 accent 색은
leading plus에만 쓰이는지, 투명도 감소 없이 활성 버튼으로 보이는지, 모든
Add camera의 접근성 이름이 `Add camera`로 유지되는지도 확인한다.

**소요**: 분할 PR 마다 5분. PR 본문에 스크린샷 1장 이상 첨부.

**언제**: View가 닿는 모든 PR. Managed-camera release 후보는 최신 공식
릴리즈에서의 설치 업그레이드 증거를 추가한다.

---

### L5. Spec-code drift 검증

**목적**: 시간 경과로 spec과 코드가 어긋나는지

**주기**: **분기별** 또는 마일스톤 종료 시점

**검증 항목**:
- coverage % 추세 (시계열) — 어느 레이어가 떨어지는지
- 파일 크기 top-10 추세 — 분할 결정이 보존되는지 (다시 부풀지 않는지)
- CC 분포 히스토그램 (시계열) — 함수 복잡도가 다시 늘어나는지
- **spec-code audit**: 각 spec §의 1줄 단언을 코드에서 직접 확인

#### Spec-code audit 체크리스트 (분기별)

| Spec | § | 단언 | 검증 방법 |
|---|---|---|---|
| Calculator | §2.2 | ND 범위 [0, 30] | 코드 상수 grep |
| Calculator | §2.3 | 19개 셔터 값 | 코드 배열 비교 |
| Calculator | §2.4 | 30s 경계 분기 | 분기 조건 grep |
| Calculator | §3.2 | 평가 순서 5단계 + correction-invariant clamp | evaluator switch case + clampToCorrectionInvariant 비교 |
| Calculator | §3.3 | Result form (quantified/limited/unsupported) | ReciprocityResult enum 카운트 |
| Timer | §2.2 | 100ms tick | timer interval 상수 |
| Timer | §3.1 | 영속성 키 (deletable on empty) | UserDefaults 키 grep + 빈 컬렉션 핸들링 |
| Timer | §3.2 | "stopped"/"paused" 둘 다 디코드 | decoder 분기 |
| Timer | §5.1 | 가장 이른 endDate 선택 | LockScreenCoord 정렬 |
| UI | §1.1 | Portrait only | Info.plist 또는 entry 분기 |
| UI | §3.1 | 2-detent (medium 없음) | detent enum 카운트 |
| UI | §3.2 | 92pt up / 64pt down | drag threshold 상수 |
| UI | §3.5 | 3-layer progress | 코드 layer 카운트 |
| DomainSchema | §12 | 11개 catalog 검증 규칙 (positive ISO + shape allow-list 포함) | LaunchPresetFilmCatalogV2Loader.validateLaunchCatalog |
| DomainSchema | §13 | 2-shape launch allow-list + §13.3 unofficial 분리 | LaunchPresetFilmCatalogShapeTests + UnofficialPracticalProfilesShapeTests |

**도구**: 일부 grep, 일부 AST. **첫 audit은 매뉴얼**, 이후 자동화 가능 항목 점진 추가.

---

## 3. 도구 스택

### 이미 있는 것

| 도구 | 무엇 |
|---|---|
| `swift test`, `ios/PTimerKit/Tests` (`PTimerCoreTests`/`PTimerKitTests`) | L1 — off-simulator, 테스트 대다수 |
| Xcode test, `ios/PTimer.xctestplan` | L1 — app-hosted OS 경계 스위트 |
| `ios/PTimerTests/` XCTest suite | L1 (테스트 데이터) |
| `docs/verification/{BackgroundNotificationDelivery,RelaunchRestore}.md` | L4 매뉴얼 스모크 발판 |
| `Storing` 페어 | DI 발판, L3 fitness 일부 |
| `ios/PTimerKit/Tests/PTimerKitTests/Snapshots/` | L2/L4 display-state snapshot |
| `ios/PTimerTests/RecordReplay/` | L2 event-sequence record-replay |

### 추가 필요

| 도구 | 무엇 | 도입 시점 | 비용 |
|---|---|---|---|
| GitHub Actions / Bitbucket Pipelines | CI workflow | after CI is configured | S |
| SwiftLint config | L1 + L3 (F1/F2/F3/F6/F7) | after CI is configured + after function/file-size enforcement is introduced | S |
| SwiftSyntax 검사 (자체) | L3 정밀 fitness (F4/F5/F8/F10) | after model-boundary enforcement is introduced | M (1주) |
| SwiftUI/image snapshot 자동화 | L4 픽셀 회귀 | 후속 필요 시 | M |
| `xcrun llvm-cov` 보고 자동화 | L1/L5 | after coverage gating is introduced | S |
| Mutation testing (`muter`) | 메타 — 검증의 검증 | 1년 후 검토 | L (선택) |

---

## 4. 변경 유형별 검증 매핑

★★ = 결정적 (의무) · ★ = 적용 · – = 무관

| 변경 유형 | L1 | L2 | L3 | L4 | L5 | 비고 |
|---|---|---|---|---|---|---|
| ViewModel/레이어 분할 | ★★ | ★★ | ★ | ★★ | – | **다층, 가장 위험** |
| Result enum / Timer state type 변경 | ★ | ★★ | ★(컴파일) | – | – | record-replay **필수** (§6) |
| DI factory 및 테스트 런타임 결합 제거 | ★ | ★★ | ★(F1/F2 영구) | – | – | 테스트 런타임 참조 잠금 |
| 파일/함수 복잡도 상한 도입 | ★ | – | ★★ | – | ★(시계열) | L3·L5 인프라 |
| Golden fixture 인프라 | – | ★★ (인프라) | – | – | ★ | L2의 인프라 자체 |
| Display-state snapshot 인프라 | – | – | – | ★★ (인프라) | – | L4의 인프라 자체 |
| CI/리포팅 인프라 | ★★ | – | ★ | – | ★★ (인프라) | L1/L5 데이터 소스 |
| Presenter/Coordinator/UI 구성 변경 | ★ | ★★ | – | ★ | – | 매뉴얼 스모크 + snapshot 권장 |
| 데이터/정책 보정 및 에러 모델 가이드 | ★ | ★★ | ★ | – | – | fixture 케이스 + 가이드 검증 |
| 문서 전용 변경 / 스파이크 | – | – | – | – | – | 보고서 또는 문서 검토 |

---

## 5. PR Verification artifact

각 PR은 본문에 다음을 첨부:

```markdown
## Verification

- [x] L1 — CI build/test/lint pass: <link>
- [x] L2 — Semantic equivalence: <method: spec-property / record-replay / fixture>
       evidence: <link>
- [x] L3 — Fitness: 새 위반 0건 <link to lint report>
- [x] L4 — UI: snapshot diff 0 / <screenshot>
- [x] L5 — Drift: 영향 없음 / spec § <link>
```

각 액션의 결정적 레이어(★★)는 **반드시 체크**. 결정적 레이어가 *적용 안 됨*이면 사유 명시.

---

## 6. Record-replay 절차 (Reciprocity Result enum 예시)

Reciprocity Result enum 도입 시:

### Step 1. main에서 baseline 기록

현재 record-replay 인프라 위치:
`ios/PTimerTests/RecordReplay/`, baseline 위치:
`ios/PTimerTests/__RecordReplay__/<TestClass>/<name>.txt`.

```bash
cd ios && RECORD_REPLAY=1 xcodebuild test \
  -project PTimer.xcodeproj -scheme PTimer \
  -testPlan PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PTimerTests/<RecordReplayTestClass>
```

첫 실행 또는 재기록 실행은 baseline을 쓰고 의도적으로 fail한다.
baseline은 deterministic text trace이며 PR diff로 검토한다.

baseline은 git에 커밋 (재현성·리뷰 가능성).

### Step 2. branch에서 대상 변경 구현

- 보호 영역과 scope를 확인한 뒤 대상 변경을 구현한다.
- trace 대상 협력자 호출 순서와 payload가 의도치 않게 바뀌지
  않아야 한다.
- 의도된 변경이라면 baseline diff를 리뷰 가능한 증거로 남긴다.

### Step 3. branch에서 baseline 재생

```bash
cd ios && xcodebuild test \
  -project PTimer.xcodeproj -scheme PTimer \
  -testPlan PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PTimerTests/<RecordReplayTestClass>
```

각 시나리오 실행 결과가 committed baseline text trace와 diff 0이어야
통과한다.

### Step 4. PR

PR 본문 §5 양식에:
- `L2 — Semantic equivalence: record-replay`
- `evidence: ios/PTimerTests/__RecordReplay__/<TestClass>/<name>.txt`
  + diff 결과 캡처

### Record-replay 인프라 비용

- 인프라는 XCTest + on-disk text baseline 방식으로 도입 완료.
- 신규 시나리오는 `RecordReplayHarness`와 spy를 추가하고 baseline을
  commit한다.

Record-replay 인프라는 timer types, presenter, coordinator, ViewModel 분할 등 후속 구조 변경에서도 동일하게 활용한다.

### 구현 노트

실제 인프라는 XCTest + display-state snapshot 패턴을 재사용한다. CLI 플래그
대신 환경변수로 재기록 모드를 토글한다.

- 위치: `ios/PTimerTests/RecordReplay/` (Trace/Baseline/Spies/Harness + smoke test)
- baseline: `ios/PTimerTests/__RecordReplay__/<TestClass>/<name>.txt`
- 재기록: `cd ios && RECORD_REPLAY=1 xcodebuild test ... -only-testing:PTimerTests/<TestClass>` → fail (의도 commit 강제) → env 없이 재실행으로 verify
- record-replay는 **이벤트 시퀀스**(LockScreen exposer 호출 순서, persistence save/clear, notification schedule/cancel)를 lock하는 데 집중한다 — 단순 input/output 페어 baseline은 별도 unit/snapshot 테스트가 이미 커버한다.
- 자세한 사용법은 `ios/PTimerTests/RecordReplay/README.md`.

본 인프라는 텍스트 trace + on-disk diff로 semantic equivalence
evidence를 남기며, display-state snapshot과 라이프사이클을 통일해 학습 비용을
최소화했다.

---

## 7. 메타 — 검증의 검증

장기적으로 검증 인프라가 *효과적인지* 평가:

- **Mutation testing** (1년 후 검토): `muter`로 코드 일부러 손상 → 테스트가 잡는지. 검증 인프라의 효과 측정. mutation score < 80%인 모듈 식별.
- **Coverage gap analysis** (반기): 미커버 라인의 *종류* 분석. 단순 % 외에 어떤 레이어가 빈약한지.
- **Spec citation audit** (반기): 코드/PR description의 spec citation이 실재 spec § 존재하는지 lint. 죽은 링크 자동 차단.
- **Verification artifact compliance** (반기): 머지된 PR 중 §5 양식을 따른 비율. 누락된 PR을 식별.

---

## 8. 단계 도입 (검증 인프라 자체 로드맵)

```
Phase 0  L1(local/CI), L4 매뉴얼 스모크
Phase 1  Coverage gating → L1 강화; complexity caps → L3 부분 + L5 시계열; F1/F2는 test-runtime coupling 제거 후 영구
Phase 2  Display-state snapshot helper → L4 자동; cross-platform fixture gate → L2(c) 인프라
Record-replay 인프라 도입 (§6 참조)
Phase 3  L3 SwiftSyntax 검사 (F4/F5/F8/F10) — after model-boundary enforcement is introduced
분기 1회 L5 audit (§2.5 체크리스트)
1년 후   Mutation testing 검토
```

---

## 9. 핵심 invariants — 가장 위험한 결정 3건

| 결정 | 검증 의무 | 레이어 |
|---|---|---|
| DI factory + test-runtime coupling 제거 | production code의 `XCTestRuntime` 참조 0건 영구 보존 | L3 (F1/F2) |
| ViewModel 분할 | 모든 ViewModelTests + 모델별 단위 테스트 + UI snapshot + record-replay (각 분할 단계) | L1 + L2 + L3 + L4 |
| Reciprocity Result enum | record-replay baseline diff 0 | L2 결정적 — spec ticket의 *전제 조건*으로 명문화 |

---

## 10. 비-목표

- **TDD 강제** — 본 전략은 *기존 테스트 + 추가 안전망*. 신규 ticket이 TDD를 강제하지 않음
- **100% 커버리지** — 의미 없는 % 추구는 비-목표. *의미 있는 레이어별* coverage 목표
- **자동 spec-code audit (전체)** — 매뉴얼이 1차, 자동화는 항목 단위 점진
- **모든 PR record-replay** — L2★★ 액션만 의무. 비-시맨틱 변경은 L1으로 충분
- **검증 자동화의 자동화** — 메타(§7) 검토는 *사람이 결정*, 도구가 결정 안 함

---

## 11. 참고

- 스펙 출처: `docs/specs/{Calculator,Timer,UI,DomainSchema}.md`
- 요구사항 출처: `docs/requirements/Requirements.md`
- 매뉴얼 절차서: `docs/verification/{BackgroundNotificationDelivery,RelaunchRestore}.md`
- 보호 영역: 각 spec §6 (Forbidden patterns)
