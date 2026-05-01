# PTimer 현재 상태 스냅샷 (2026-04-27)

이 문서는 코드, 테스트, git log, 기존 `Docs/`에서 복원되었다.
코드와 충돌하는 경우 코드를 권위로 한다. 시점은 2026-04-27 (HEAD: `2b9da61`).

---

## 1. 프로젝트 한 줄 정의

iPhone 전용·세로 고정 SwiftUI 앱. 필름 사진의 ND 노출 계산과 reciprocity(상반칙 불궤) 보정, 그리고 카운트다운 타이머 워크스페이스(잠금화면 위젯 포함)를 단일 화면 위에 결합한다.

## 1.5 거버넌스 / 리포지토리

(권위: 위키 01_PROJECT_CONTEXT, v3 pack `ptimer_claude_arch_review_pack_v3/docs/claude-handoff/01_PROJECT_CONTEXT.md`.)

- Jira project: `PTIMER`
- Confluence space: `SD` (`https://sangwook.atlassian.net/wiki/spaces/SD`)
- Bitbucket repo: `sangwook2han/ptimertrycodex`
- Branch 명명: `feature/PTIMER-<EpicID>-<slug>` (예: `feature/PTIMER-91-reciprocity-ui-integration`)
- Commit summary 라인에 **Jira ID 미포함**. Jira 링크는 commit body 마지막 줄에 `PTIMER-<ID> Title` 형식 (위키 00_CLAUDE_CONTEXT_APPENDIX, AGENTS.md §Commit Message)
- 운영 스타일: ChatGPT가 Jira/Confluence를 product spec으로 정리 → Codex/Claude가 구현/리뷰 → 사람이 우선순위·승인·머지

## 2. 빌드 / 타깃

- 워크스페이스 진입점: `PTimer.xcodeproj`
- 메인 앱 스킴: `PTimer` (앱 타깃)
- 위젯 타깃: `PTimerWidgets`
- 테스트 타깃: `PTimerTests`
- 테스트 플랜: `PTimer.xctestplan`
- 기본 시뮬레이터 (`.codex/config.toml`): `iPhone 17`

표준 테스트 커맨드:

```bash
xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -testPlan PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## 3. 디렉토리 트리 (소스/테스트/리소스)

```
ptimertrycodex/
├── PTimer/                       # 앱 타깃 소스
│   ├── App/
│   │   ├── PTimerApp.swift                  (130L)  앱 entry, AppDelegate, Live Activity 노출 프로토콜
│   │   ├── ContentView.swift                (  7L)  ExposureCalculatorScreen 패스스루
│   │   └── BottomSheetWorkspaceShell.swift  (1710L) 타이머 워크스페이스 셸 + 상태머신 + 스냅샷 팩토리
│   ├── ExposureCalculator/
│   │   ├── ExposureCalculator.swift              (358L)  순수 ND 계산 + snap-to-full-stop + 셔터/시간 포맷
│   │   ├── ExposureCalculatorViewModel.swift     (2439L) @MainActor ObservableObject 코디네이터
│   │   ├── ExposureCalculatorScreen.swift        (3158L) 메인 SwiftUI 화면
│   │   ├── ExposureCalculatorFilmContext.swift   (271L)  필름 컨텍스트 영속성 + 필름 모드 디스플레이 상태 23종
│   │   └── PresetFilmCatalog.swift               (206L)  번들 JSON 카탈로그 로더 + 검증
│   ├── Reciprocity/
│   │   ├── ReciprocityDomain.swift                  (495L)  도메인 값 타입 일체 (Codable)
│   │   ├── ReciprocityCalculationPolicy.swift       (1685L) 정책 평가기 + 결과 메타데이터
│   │   └── ReciprocityConfidencePresentation.swift  (691L)  신뢰도 표현 카테고리·level·badge·token + Mapper
│   ├── Timers/
│   │   ├── TimerManager.swift                          (656L) 타이머 라이프사이클 + 영속성 + 알림
│   │   ├── TimerCompletionNotificationScheduler.swift  ( 91L) UNUserNotificationCenter 어댑터
│   │   ├── CompletedRelativeTimeFormatter.swift        ( 74L) "5 min ago" 포매터
│   │   └── LockScreenTimerLiveActivity.swift           ( 24L) ActivityKit attributes
│   └── Resources/
│       ├── LaunchPresetFilmCatalog.json   번들 프리셋 필름 (4종)
│       └── Assets.xcassets/               앱 아이콘, AccentColor
├── PTimerWidgets/                # 위젯 타깃
│   ├── LockScreenTimerTargetWidget.swift  (131L) 잠금화면 + Dynamic Island 위젯 surface
│   └── PTimerWidgetsBundle.swift          (  9L) WidgetBundle entry
├── PTimerTests/                  # 테스트 타깃 (소스 미러링)
│   ├── App/
│   │   └── BottomSheetWorkspaceShellTests.swift          (1735L)
│   ├── ExposureCalculator/
│   │   ├── ExposureCalculatorTests.swift                 ( 223L)
│   │   ├── ExposureCalculationAccuracyTests.swift        ( 255L)
│   │   ├── ExposureCalculatorViewModelTests.swift        (3240L)
│   │   └── LaunchPresetFilmCatalogTests.swift            ( 193L)
│   ├── Reciprocity/
│   │   ├── ReciprocityDomainTests.swift                  ( 723L)
│   │   ├── ReciprocityCalculationPolicyTests.swift       (1029L)
│   │   └── ReciprocityConfidencePresentationTests.swift  ( 356L)
│   └── Timers/
│       ├── TimerManagerTests.swift                       (1885L)
│       └── CompletedRelativeTimeFormatterTests.swift     (  85L)
├── Docs/
│   ├── Specs/{Calculator,Timer,UI,DomainSchema}.md       (행동 계약, 영구)
│   ├── Sources/wiki/...                                   (wiki 31 파일, 영구)
│   ├── StructureImprovement/                              (이 Epic 산출물, 일시적)
│   ├── Verification/{Strategy, BackgroundNotificationDelivery, RelaunchRestore}.md
│   ├── Features/Reciprocity/PresetDatasetPolicy.md       (영구 정책)
│   └── tasks/TASK_TEMPLATE.md                             (CLAUDE/AGENTS 지정)
├── .codex/
│   ├── config.toml                Codex CLI 프로젝트 설정 (Draft)
│   └── skills/
├── AGENTS.md                      ChatGPT/Claude/Codex 3-역할 워크플로 정책
├── CLAUDE.md                      빌드·아키텍처·보호 영역 가이드
├── code_review.md                 리뷰 체크리스트
├── README.md                      간단한 README
├── PTimer.xcodeproj/
└── PTimer.xctestplan
```

라인 수 합계: 소스 11,995줄 (15 Swift) + 위젯 140줄 (2 Swift) + 테스트 9,724줄 (10 Swift). 총 **21,859줄 Swift**.

## 4. 레이어 의존성 — 검증 결과

CLAUDE.md가 선언한 스택을 실제 import / 타입 참조로 검증.

```
SwiftUI Views (ContentView, ExposureCalculatorScreen, BottomSheetWorkspaceShell, LockScreenTimerTargetWidget)
        │ uses (display-state struct만 소비)
        ▼
View Model (@MainActor ObservableObject)
        │ owns
        ▼
Domain / Policy        Timer Runtime
ExposureCalculator     TimerManager
ReciprocityCalculation TimerCompletion*
ReciprocityDomain      LockScreenTimerLiveActivity (attributes)
        │
        ▼
Persistence (UserDefaults*Store, NoOp*Store via XCTestRuntime.isRunningTests)
```

**누수 검사 결과**: 누수 없음.
- Views는 도메인/정책 타입을 직접 import하지 않음. 오직 `FilmModeExposureResultState`, `FilmModeDetailsDisplayState`, `BottomSheetWorkspaceSnapshot`, `FilmSelectionDisplayState` 등 ViewModel이 emit하는 디스플레이 상태만 참조.
- 도메인/정책은 `Foundation`만 import. UI 프레임워크 무관.
- TimerManager는 `Foundation` + `Combine` + `AudioToolbox` + `UIKit`(`UINotificationFeedbackGenerator`, `UIApplication.State`). 정책/도메인 무관.
- 위젯 타깃은 `LockScreenTimerLiveActivity`의 attributes 타입만 공유.

**테스트 격리 패턴**: 모든 영속성·Live Activity·알림 채널이 `Storing` 프로토콜과 `NoOp...` 구현 페어를 가짐. ViewModel이 `XCTestRuntime.isRunningTests`로 분기해 NoOp 주입. 결과: 단위 테스트가 UserDefaults / ActivityKit / UNUserNotificationCenter를 절대 만지지 않음.

## 5. 테스트 커버리지 매트릭스

| 소스 파일 | 전용 테스트 | 비고 |
|---|---|---|
| `ExposureCalculator.swift` | `ExposureCalculatorTests` (223L) + `ExposureCalculationAccuracyTests` (255L) | ND 계산, snap, 포맷 — 잠김 |
| `ExposureCalculatorViewModel.swift` | `ExposureCalculatorViewModelTests` (3240L) | 상태 합성, 필름 선택, 타이머 통합, restore 모놀리스 |
| `ExposureCalculatorFilmContext.swift` | (간접: ViewModelTests) | 컨텍스트 영속성 회귀 포함 |
| `PresetFilmCatalog.swift` | `LaunchPresetFilmCatalogTests` (193L) | 9개 검증 규칙 + 번들 인덱스 |
| `ExposureCalculatorScreen.swift` | ✗ 없음 | SwiftUI 뷰 — UI 테스트 도구 미도입 |
| `ReciprocityDomain.swift` | `ReciprocityDomainTests` (723L) | Codable round-trip, 변형 셀렉터 |
| `ReciprocityCalculationPolicy.swift` | `ReciprocityCalculationPolicyTests` (1029L) | 평가 순서 6단계, estimation 패밀리 |
| `ReciprocityConfidencePresentation.swift` | `ReciprocityConfidencePresentationTests` (356L) | basis × authority 매트릭스 |
| `TimerManager.swift` | `TimerManagerTests` (1885L) | 라이프사이클, 영속성, 복원 |
| `TimerCompletionNotificationScheduler.swift` | (간접: TimerManagerTests) | 어댑터 |
| `CompletedRelativeTimeFormatter.swift` | `CompletedRelativeTimeFormatterTests` (85L) | 경계 케이스 |
| `LockScreenTimerLiveActivity.swift` | ✗ 없음 | ActivityKit attributes (선언적) |
| `BottomSheetWorkspaceShell.swift` | `BottomSheetWorkspaceShellTests` (1735L) | 상태머신, 스냅샷 팩토리, 정렬 |
| `ContentView.swift` | ✗ 없음 | 7줄 패스스루 |
| `PTimerApp.swift` | ✗ 없음 | UIKit AppDelegate |
| `LockScreenTimerTargetWidget.swift` | ✗ 없음 | 위젯 surface (선언적 SwiftUI) |

소스 ↔ 테스트 비율: **0.81 : 1** (테스트 9,724L / 소스 11,995L). 정책·도메인·타이머 코어는 잠금 강도가 매우 높음.

## 6. 보호 영역 (CLAUDE.md / AGENTS.md 일치)

다음 5개 영역은 **task-level 명시 승인 없이 변경 금지**. 본 문서들 모두 이 정책을 침범하지 않는다.

1. 노출 계산 규칙: `ExposureCalculator.calculate`, snap-to-full-stop, `stabilityEpsilon`
2. Reciprocity 정책 평가 순서 및 결과 시맨틱: `ReciprocityCalculationPolicyEvaluator`
3. 신뢰도 표현 매핑: `ReciprocityConfidencePresentation`
4. 타이머 런타임 시맨틱: pause/resume/complete 상태머신, `TimerManager`
5. 영속성·복원 계약: 스냅샷 스키마, UserDefaults 키
6. **Calculator-input invariant** (위키 02_SOURCE_OF_TRUTH): Calculator 입력 변경(베이스 셔터/ND/필름 선택)이 *이미 생성된 타이머의 metadata snapshot*을 mutate 금지. 즉 새 계산은 *새 타이머* 후보일 뿐, 기존 타이머는 그대로
7. **Timer truth invariants** (위키 8880129): Timer runtime이 source of truth. Dock/sheet/overlay/list는 projection. UI presentation state가 timer lifecycle truth 소유 금지. tick 시 전체 workspace 재빌드 금지

## 7.0 1차 리뷰 (위키 19103745) 결과 요약

본 문서와 `./Plan.md`는 **위키 19103745 (`2026-04-24 코드·아키텍처·디렉토리 리뷰 #1`)의 후속 작업**이다. 1차 리뷰는 **8.5/10 평가** + Tier 1/2/3 권고를 제시:

- **Tier 1**: `.gitignore` 확장, 임시 root 파일 제거, minimal CI workflow
- **Tier 2**: production init의 `XCTestRuntime.isRunningTests` 분기 → DI factory, SwiftLint + CI, README 아키텍처 요약
- **Tier 3**: `FilmModeDetailsPresenter` 추출, `TimerCoordinator` 분리, `ExposureCalculatorScreen` section split, Widget tests, Reciprocity helper consolidation

본 스냅샷은 1차 리뷰 권고를 *부분적으로* 반영. 6렌즈 다관점 진단과 24개 액션 카탈로그는 `./Plan.md`에 통합. 1차 리뷰 권고는 *모두 미수행* 상태이며, Phase 0/1부터 단계 진행이 권고됨.

위키 19070978 (`구조 개선` hub)이 본 작업 type의 영구 hub. 본 분석 문서들은 그 hub의 자식 리뷰.

## 7. git log 테마 그룹화 (총 116 커밋)

대표 커밋만 발췌. PR 머지 커밋은 트렁크 통합 시점.

### 7.1 부트스트랩 (가장 오래된 ~10 커밋)
- 앱 스캐폴드, README, 초기 ND 계산 골격, 계산기 UI 골격

### 7.2 계산기 / 타이머 1세대
- ND 계산 정수 stop 기반으로 리팩터, 셔터/시간 포맷 통일
- 타이머 실행 흐름, 멀티 타이머 아키텍처와 테스트 정착
- snap-to-full-stop, 정확도 회귀 테스트 추가

### 7.3 입력 UI 현대화
- ND 입력을 wheel picker로 (`aefdc65`)
- 셔터 입력을 wheel picker로 (`483613a`)
- 셔터·ND 피커 병렬 배치 (`6541786`)
- UI 영문 정규화 (`0ec9890`)

### 7.4 타이머 정확도·UX 강화
- stop 기반 셔터 스케일링 정밀화 (`62cf8c3`)
- 타이머 의미론 회귀 테스트 확장
- 타이머 패널 UX 폴리싱

### 7.5 Reciprocity / Film mode 통합 (가장 큰 테마, 최근 ~3개월)
- PTIMER-91 reciprocity UI 통합 (피처 브랜치, PR #12–#19 누적)
- `e9bca30` Reciprocity details 참조 그래프 추가 (대형 디프)
- `e82258f` 일반 표 외삽 ceiling 제거
- `f22597f` 재실행 간 필름 컨텍스트 복원
- `2277910` 공식 fallback 분류 수정
- `41dd0a7` 실패 정책 단위 테스트 수정
- `d5f058c` Velvia 50의 threshold→table 갭 unsupported 반환 수정 (122 회귀 케이스 추가)
- `383c55c` 필름 셀렉터 → 모달 시트 (PTIMER-110)
- `648d21d` Reciprocity 디테일 표현 복원
- `ca01f66` PR #20 머지
- `9b936b1` PTIMER-112 day-scale 결과 표시 coarse 모드 (예: "13,599d") — primary corrected exposure만 적용, detail/timer는 정밀 유지
- `d013c2b` Portra 400 official/unofficial 프로파일 명시화 — Film row 부제(Official guidance / Unofficial practical), details 시트 섹션 순서(Profile→Formula→Graph→Sources), 0.85 detent, 120s graph 상한, Authority row 항상 노출, 비공식 `T_c = T_m^1.34` 보조 프로파일 launch catalog 외부에 등록
- `2b9da61` (HEAD) PR #22 머지

### 7.6 거버넌스·문서
- `913d24d` `.codex/config.toml` 스캐폴드
- `0df74fe` AGENTS.md 3-역할 워크플로 정의
- `60b0d19` 커밋 메시지 hanging indent 문서화
- `3bd9693` CLAUDE.md 추가
- `a33638e` 프리셋 필름 카탈로그 외부화 (JSON)

## 8. 진행 중·열린 작업 지표

- 소스 트리에 `TODO` / `FIXME` / `XXX` 마커 **없음** (production code 기준).
- `.codex/config.toml`은 "Draft" 단계로 표시됨.
- 최근 PR (`ca01f66` PR #20)이 reciprocity details 표현을 *restore* 한 점은, 최근 표현 단순화→복원 사이클이 있었다는 신호. 현 상태가 안정 시점.
- Verification 문서 (`BackgroundNotificationDelivery`, `RelaunchRestore`)는 매뉴얼 절차서. 코드 잠금은 별도 단위 테스트가 담당.
- `Docs/Features/Reciprocity/PresetDatasetPolicy.md`는 launch dataset policy의 권위 문서. 현재 코드 카탈로그는 **번들 4종** (Tri-X 400, Portra 400, Velvia 50, HP5 Plus); 이 문서가 명시한 launch scope 34종은 *목표*이며 현 시점 모두 적재된 것은 아님 — `LaunchPresetFilmCatalog.json` 실데이터로 확인.

## 9. 산출 문서 인덱스 (이 작업의 결과물)

**스펙 (영구, `Docs/Specs/`)** — 행동 계약, 리팩토링 후에도 유지
- `Docs/Specs/Calculator.md` — 노출·Reciprocity 행동 계약
- `Docs/Specs/Timer.md` — 타이머 상태머신·영속성·알림 행동 계약
- `Docs/Specs/UI.md` — 화면·위젯·인터랙션 행동 계약
- `Docs/Specs/DomainSchema.md` — 도메인 모델 (필름·프로파일·규칙·카탈로그)

**이 Epic의 산출물 (일시적, `Docs/StructureImprovement/`)** — Epic 종료 시 삭제 가능
- `./CurrentState.md` (이 문서) — 시점 스냅샷
- `./Plan.md` — 다관점 진단 + 24 액션 카탈로그 + 4 Phase 로드맵
- `./AndroidPortPlan.md` — Kotlin/Compose 포팅 계획
- `./AndroidTestParity.md` — iOS↔Android 단위 테스트 매핑

**검증 (`Docs/Verification/`)** — 영구
- `Docs/Verification/Strategy.md` — 5 레이어 검증 전략
- `Docs/Verification/BackgroundNotificationDelivery.md` — 알림 매뉴얼 절차
- `Docs/Verification/RelaunchRestore.md` — 복원 매뉴얼 절차

**권위 출처 (`Docs/Sources/`)** — wiki 31 페이지 로컬 사본
