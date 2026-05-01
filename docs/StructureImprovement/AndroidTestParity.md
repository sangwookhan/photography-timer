# Android 포팅 — iOS ↔ Android 단위 테스트 매핑

이 문서는 PTimer iOS의 단위 테스트가 잠그는 invariant를 Android(Kotlin) 측 단위 테스트로 미러링하는 매핑이다.
**모든 행이 Android에서 통과할 때 도메인 포팅 1단계가 끝났다고 본다.**

권위 출처:

- 행동 계약: `Docs/Specs/Calculator.md`, `Docs/Specs/Timer.md`, `Docs/Specs/DomainSchema.md`, `Docs/Specs/UI.md`
- iOS 테스트: `PTimerTests/**/*.swift` (계약을 잠그는 회귀 테스트)
- 포팅 가이드: `./AndroidPortPlan.md`

---

## 0. 일반 원칙

1. **케이스 추가/삭제 금지** (1차). 모든 iOS 케이스를 그대로 옮긴다. 새 케이스는 iOS에 먼저 들어와야 한다.
2. **부동소수점 비교는 epsilon `1e-6`** (iOS의 `stabilityEpsilon`과 동일).
3. **테스트 라이브러리**: `kotlin.test` + `kotlinx-coroutines-test` (`runTest`, `TestScope`로 가상 시간). UI 테스트는 본 문서 범위 외.
4. **Hilt / DI**: 도메인 모듈은 DI 없이 순수 Kotlin/JVM. UI/data 모듈은 `@HiltAndroidTest` 필요시.
5. **Date / Instant**: iOS의 `Date(timeIntervalSinceReferenceDate:)` 직역은 `java.time.Instant.ofEpochSecond(...)` 또는 `Instant.now() + Duration.ofSeconds(...)`로 가상 시간 주입.
6. **TimerManagerTests처럼 시간 의존이 큰 테스트**: `TestScope` + `currentTime`을 통해 결정론적 가상 시간. 실 시계에 의존하지 않음.

---

## 1. 매핑 표 (iOS 테스트 → Android 테스트)

### 1.1 ExposureCalculator

| iOS 테스트 파일 | iOS 케이스 (대표) | Android 테스트 파일 | 노트 |
|---|---|---|---|
| `ExposureCalculatorTests.swift` (223L) | parseBaseShutter `"1/30"`, `"0.5"`, `"2s"`, `"2 sec"` 정규화 / `""`, `"abc"`, `"0"`, `"-1"` reject | `domain-exposure/.../ExposureCalculatorTest.kt` | 동일 입력 → 동일 결과·예외 타입 |
| 위 | `(1/30) × 2^6` snap = 2.0 / `(1/8) × 2^10` snap = 128.0 / `1 × 2^0` = 1.0 | 위 | `assertEquals(2.0, …, 1e-6)` |
| 위 | full-stop 배열 경계: `1×2^4=16 → snap 15` (16 미존재) | 위 | snap 알고리즘 §1.4 |
| 위 | tier 2: `1×2^6=64`, `1×2^5=32 → 30`, `1×2^7=128` | 위 | 두 후보 거리 같으면 30 우선 (≤30+ε) |
| 위 | format: `2 → "2s"`, `2.1 → "2.1s"`, `1/30 → "1/30s"` | 위 | locale ROOT |
| 위 | `formatTimeDisplay(128) → ("02:08", "128s")`, `(3728) → ("01:02:08", "3728s")`, `(90000) → ("1d 01:00:00", "90000s")` | 위 | |
| 위 | NaN / 음수 → `"-"`, `0s/0s` | 위 | |
| `ExposureCalculationAccuracyTests.swift` (255L) | snap-to-full-stop의 *모든* tier 경계 회귀 케이스 | `domain-exposure/.../ExposureCalculationAccuracyTest.kt` | iOS 케이스 1:1 |

### 1.2 Reciprocity Domain (Codable round-trip)

| iOS | Android | 노트 |
|---|---|---|
| `ReciprocityDomainTests.swift` (723L) — `FilmIdentity`, `ReciprocityProfile`, 모든 rule variant, 모든 Adjustment variant, 모든 ExposureAdjustment variant의 encode→decode 동등 | `domain-reciprocity/.../ReciprocityDomainSerializationTest.kt` | `kotlinx.serialization` `Json.encodeToString` / `decodeFromString`. wrapper 형식 (`{"kind":"threshold","threshold":{...}}`) 유지 위해 custom serializer. |
| `MeteredExposureSelector` 두 variant | 위 | |
| 옵셔널 필드 nil/생략 모두 정상 디코드 | 위 | `encodeDefaults = false` 또는 `@OptIn(ExperimentalSerializationApi::class)` `@EncodeDefault` 활용 |
| `CorrectedTimeMapping`의 `meteredSeconds: null` 케이스 | 위 | nullable 필드 |
| `ReciprocityTimeRange` `maximumSeconds: null` 케이스 | 위 | 무한 상한 |

### 1.3 Reciprocity Calculation Policy

| iOS | Android | 노트 |
|---|---|---|
| `ReciprocityCalculationPolicyTests.swift` (1029L) | `domain-reciprocity/.../ReciprocityPolicyEvaluatorTest.kt` | 평가 순서 6단계가 곧 계약 |
| **단계 1**: Tri-X metered=10s → exact, corrected=50, basis=`exactTablePoint` | 위 | data: `LaunchPresetFilmCatalog.json`의 Tri-X profile |
| **단계 1**: Velvia metered=64s → unsupported via stop signal (warning notRecommended) | 위 | warning entry 차단 |
| **단계 2**: Tri-X metered=0.5s → thresholdNoCorrection (range [0,1] 포함, corrected = 0.5) | 위 | 단계 2 매칭 |
| **단계 2 vs 1 우선**: Tri-X metered=1s → exact (1s는 정확 row; 단계 1이 단계 2보다 우선) | 위 | 우선순위 표 invariant |
| **단계 3 보간**: Tri-X metered=5s → interpolated logLog | 위 | slope 수식 §2.3 |
| **단계 3 외삽**: Tri-X metered=300s → extrapolated logLog | 위 | beyond last point |
| **단계 3 갭 외삽**: Velvia metered ∈ (1s, firstPoint) → downward extrapolation | 위 | PTIMER d5f058c 잠금 |
| **단계 4 formula**: HP5 Plus metered=10s → `Tc=10^1.31 ≈ 20.4` | 위 | exponent only formula |
| **단계 5 advisory**: Portra metered > 1s (예: 2s) → advisory, corrected=null | 위 | 1s는 단계 2가 우선; 1s 초과만 advisory |
| **단계 6 unsupported**: 매칭 없음 → unsupported, note token = `unsupportedByPolicy` | 위 | |
| **결과 invariant**: basis × estimationFamily × correctedExposure (Calculator.md §2.4) 모든 분기 검증 | 위 | `require(...)` 또는 sealed class 강제 |
| **rangeStatus 매핑** (Calculator.md §2.5) | 위 | enum 비교 |
| **warningLevel 매트릭스** (basis × authority) | 위 | when 표현식 표 |

### 1.4 Reciprocity Confidence Presentation

| iOS | Android | 노트 |
|---|---|---|
| `ReciprocityConfidencePresentationTests.swift` (356L) — basis × authority 매트릭스 (총 7×4) | `domain-reciprocity/.../ReciprocityConfidenceMapperTest.kt` | parameterize. `assertEquals` 기대값 표 |
| Category 매핑 (Calculator.md §4.1) | 위 | |
| Level 매핑 (§4.2) | 위 | |
| Badge style 매핑 (§4.3) | 위 | |
| WarningEmphasis 매핑 (§4.4) | 위 | |
| Short label 매핑 (§4.5) | 위 | 문자열 정확 매칭 |
| Explanation tokens 누적 (중복 없음) | 위 | Set 또는 distinct list |

### 1.5 Launch Preset Film Catalog

| iOS | Android | 노트 |
|---|---|---|
| `LaunchPresetFilmCatalogTests.swift` (193L) | `data-catalog/.../LaunchPresetFilmCatalogLoaderTest.kt` | iOS 검증 9 + 4 인덱스 |
| 번들 카탈로그 정상 로드, 4종 순서: Tri-X 400, Portra 400, Velvia 50, HP5 Plus | 위 | `assets/LaunchPresetFilmCatalog.json` |
| 9개 검증 규칙 (DomainSchema.md §4.3) 각각 위반 → 정확한 에러 | 위 | 9 케이스 1:1 |
| 디코드 실패 → `Malformed` 에러 (사람 친화 메시지) | 위 | `SerializationException` 캡처 |

### 1.6 Timer Manager / TimerState

| iOS | Android | 노트 |
|---|---|---|
| `TimerManagerTests.swift` (1885L) | `domain-timer/.../TimerStateTest.kt` + `feature-timer/.../TimerManagerTest.kt` | 두 모듈로 나눔 |
| `start(duration: 0)` → null/실패, 타이머 추가 안 됨 | 위 | |
| `start(d)` 직후 remainingTime ≈ d (1 tick 오차) | 위 | TestScope `currentTime` |
| running 타이머 tick 후 `now + ε ≥ endDate` → completed | 위 | virtualTime + advance |
| `pause` 후 임의 시간 흘러도 paused.remainingTime 동일 | 위 | virtualTime advance + 동일 검증 |
| `resume` 후 endDate = now + frozenRemaining | 위 | |
| `pause` / `remove` / `removeCompletedTimers`는 알림 취소 동반 | `feature-timer/.../TimerManagerTest.kt` | NotificationScheduling fake |
| 영속성: 새 타이머 추가 시 saveSnapshot, 모두 비면 clearSnapshot | 위 | DataStore in-memory fake |
| **PTIMER-70 복원**: running이 wall clock으로 이미 지났으면 즉시 completed | 위 | virtualTime 기반 |
| **PTIMER-70 복원**: paused는 frozen 그대로 (wall-clock 진행 무시) | 위 | |
| **PTIMER-70 복원**: completed는 그대로 | 위 | |
| **PTIMER-67 재활성화**: 알림 *발화 없음* | 위 | alertService fake spy |
| `XCTestRuntime.isRunningTests` 자동 NoOp 주입 | (Hilt + `@HiltAndroidTest`로 NoOp 모듈 주입) | DI 패턴 차이 |
| Snapshot 디코더의 legacy `"stopped" → paused` 호환 | `domain-timer/.../PersistentTimerSnapshotTest.kt` | custom serializer |

### 1.7 Completed Relative Time Formatter

| iOS | Android | 노트 |
|---|---|---|
| `CompletedRelativeTimeFormatterTests.swift` (85L) | `domain-timer/.../CompletedRelativeTimeFormatterTest.kt` | |
| 0 ≤ x < 60s → "just now" | 위 | |
| 60s, 119s → "1 min ago" | 위 | regular |
| 3600s → "1 hr ago" | 위 | |
| 86400s → "1 day ago", 172800s → "2 days ago" | 위 | 복수형 day만 |
| compact: "1m ago", "1h ago", "1d ago" | 위 | |
| `nextRefreshDate` 다음 분/시/일 경계 | 위 | 정확 동등 |
| 이미 지난 경우 nil | 위 | |

### 1.8 BottomSheet Workspace (View 인접 + Snapshot 팩토리)

| iOS | Android | 노트 |
|---|---|---|
| `BottomSheetWorkspaceShellTests.swift` (1735L) | `feature-timer/.../BottomSheetWorkspaceTests.kt` (또는 분할) | |
| 정렬: running·paused → completed, 각 그룹 시각 내림차순 | `feature-timer/.../WorkspaceOrderingTest.kt` | PresentationAdapter 단위 테스트 |
| compactItems와 sections의 ID 매핑 | 위 | snapshot 동등 |
| expand/collapse 시 detent 전이 | `feature-timer/.../WorkspaceStateStoreTest.kt` | StateFlow assertion |
| focus 타이머 expandAndFocusTimer가 detent를 large로, selectedTimerID 설정 | 위 | |
| snapshot publisher가 redundant 변경에서 publish 안 함 | `feature-timer/.../SnapshotPublisherTest.kt` | `distinctUntilChanged` 기반 |
| `completedCount` 정확 | 위 | |
| compact viewport 카드 수 vs 오버플로 | 위 | |
| identity color slot이 동일 UUID에서 동일 | `feature-timer/.../IdentityPaletteTest.kt` | UUID 16바이트 해시 동일 |

### 1.9 ExposureCalculator ViewModel (상태 합성)

| iOS | Android | 노트 |
|---|---|---|
| `ExposureCalculatorViewModelTests.swift` (3240L) | `feature-calculator/.../ExposureCalculatorViewModelTests.kt` (가능시 분할) | |
| `filmSelectionDisplayState` 빈/선택 상태 | 위 | StateFlow 검증 |
| `filmModeExposureResultState`가 정책 결과 정확히 반영 | 위 | |
| `FilmModeTimerActionState.canStartTimer` 비활성 조건 (음수, NaN, 정책 unsupported) | 위 | |
| `filmSelectorEntries` 정렬 (canonicalStockName 기준) | 위 | |
| ScenePhase 재활성화에서 reconcile 호출 (PTIMER-67) | 위 | LifecycleEventEffect |
| 컨텍스트 영속성 (필름 선택, 베이스 셔터, ND stop이 재실행 후 복원) | 위 + `data-persistence` 통합 | |

---

## 2. 통과 기준 (Definition of Parity)

다음을 만족할 때 *도메인 포팅 1단계*가 종료된 것으로 간주:

1. 위 표의 모든 행이 Android 측에 *존재*하며 통과한다.
2. 추가/삭제된 케이스가 없다 (iOS와 1:1).
3. 모든 부동소수점 비교가 epsilon `1e-6`를 사용한다.
4. 가상 시간 의존 테스트가 실 시계에 의존하지 않는다.
5. `kotlinx.serialization` round-trip이 iOS Codable 출력과 *바이트 단위*로 동일하지 않더라도, *의미 단위*로 동일하면 통과 (필드 순서·중복 키 무시).
6. NoOp/실 페어 패턴이 적용되어 단위 테스트가 OS 채널(DataStore IO 제외)을 만지지 않는다.

---

## 3. 케이스 추가 정책

iOS에 없는 회귀 케이스가 *Android에서만* 발견된 경우:

1. iOS에도 같은 케이스를 추가 (양쪽 잠금 동등 유지).
2. 양쪽이 모두 통과할 때만 머지.
3. 본 문서 §1 표를 갱신.

iOS에 새 케이스가 들어오면:

1. Android 표에도 즉시 행 추가 (TODO 마크).
2. 다음 PR에 케이스 직역.

---

## 4. 도구 / 환경

- Kotlin 2.x
- Compose BOM 최신
- `org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.x+`
- `org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.x+`
- `androidx.test:core`, `kotlin.test`
- (선택) Turbine — Flow assertion DSL
- 도메인 모듈은 `kotlin("jvm")` 플랫폼 (Android API 미사용) → 빠른 단위 테스트

```kotlin
// domain-exposure/build.gradle.kts
plugins { kotlin("jvm") }
dependencies {
    testImplementation(kotlin("test"))
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.0")
}
```

---

## 5. 비-목표

- UI 스냅샷 테스트 (Compose Preview / Paparazzi) 1차 미포함.
- E2E 테스트 (Maestro / UIAutomator) 1차 미포함.
- 성능/메모리 벤치마크 1차 미포함.

이들은 별도 RFC 항목.
