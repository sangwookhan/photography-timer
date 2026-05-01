# PTIMER Android 포팅 계획서

PTIMER iOS 앱을 Kotlin/Jetpack Compose 기반 Android 앱으로 동등 이식하기 위한 계획. *계획서 단계*이며 Gradle/Kotlin 코드 생성은 본 작업 범위 외.

근거 문서:
- `Docs/Specs/Calculator.md`, `Timer.md`, `UI.md`, `DomainSchema.md` — 계산·정책·시맨틱 행동 계약 (Android 구현이 만족해야 하는 동등 계약)
- `./CurrentState.md` — iOS 현재 상태 스냅샷
- `./AndroidTestParity.md` — 통과해야 할 단위 테스트 매핑

---

## 1. 목표 / 비-목표

### 1.1 목표

- iOS PTIMER와 *동등한 동작*의 Android 앱:
  - 노출 계산기 (베이스 셔터 + ND stop → 결과 셔터)
  - Reciprocity 정책 평가기 (4종 번들 필름)
  - 타이머 워크스페이스 (compact/large detent, 다중 타이머)
  - 잠금화면 위젯 (Android 한계 안에서 best-effort)
- 보호 영역 시맨틱 100% 보존
- iOS 단위 테스트 invariant를 Android에서 직역 가능한 단위 테스트로 잠금

### 1.2 비-목표

- iOS 코드와의 자동 양방향 동기화 (양쪽 코드는 분석 문서를 권위로 함)
- iOS의 ActivityKit Live Activity와 1:1 동등 (Android 한계로 best-effort)
- 새 기능 추가 (1차 포팅은 *동작 동등*까지)
- 한국어 로컬라이즈 (1차는 영문, iOS와 동일)
- 모든 SF Symbols와 1:1 매핑되는 Material Symbols 매칭 (의미 동등이면 충분)
- **Flutter 미사용** (위키 01_PROJECT_CONTEXT, 4063234 — Flutter는 옵션 아님). Android 포팅은 *native Compose / Kotlin* (KMP 후보)

---

## 2. 모듈 구조 권고

Gradle 멀티 모듈로 레이어 강제. 각 모듈은 *위쪽 의존만* 허용.

```
app/                      Activity, Compose Navigation, Application class
└─ depends on: 모든 feature-* + data-*

feature-calculator/       Compose UI + ViewModel for ExposureCalculatorScreen
└─ depends on: domain-exposure, domain-reciprocity, data-catalog

feature-timer/            Compose UI + ViewModel for BottomSheet workspace + widget UI
└─ depends on: domain-timer, data-persistence

domain-exposure/          순수 Kotlin/JVM (ExposureCalculator, formatting)
domain-reciprocity/       순수 Kotlin/JVM (Domain types, Policy evaluator, Confidence mapper)
domain-timer/             순수 Kotlin/JVM (TimerState, TimerStatus, sanitize, snapshot codec)

data-persistence/         DataStore 어댑터 (TimerSnapshot, ExposureCalculatorContext)
data-catalog/             LaunchPresetFilmCatalog 로더 + 검증 (assets/raw)
```

### 2.1 레이어 의존 규칙

- `app` → 모든 feature·data
- `feature-*` → domain-* + data-* (적정)
- `domain-*` → **다른 domain만** (data·feature 의존 금지)
- `data-*` → domain-*만 (Android API 사용 가능)

iOS의 `Foundation`-only 도메인 정책과 등가.

### 2.2 KMP 가능성 (장기, 비-목표)

`domain-exposure`, `domain-reciprocity`, `domain-timer`는 향후 Kotlin Multiplatform으로 이행해 iOS와 공유 가능. 1차 포팅은 KMP 없이 순수 Kotlin/JVM. 단, 순수 Kotlin로만 작성해 KMP 이행 부담을 줄임.

---

## 3. 기술 매핑 (Swift → Kotlin/Android)

### 3.1 언어/타입

| Swift | Kotlin |
|---|---|
| `Double` / `Int` / `String` | 동일 |
| `[T]` | `List<T>` (불변 권장) |
| `T?` | `T?` |
| 단순 enum | `enum class` |
| tagged union | `sealed class/interface` + `data class` (또는 `@Serializable`로 polymorphic) |
| `struct` | `data class` (불변 = `val`) |
| `Codable` | `kotlinx.serialization` (`@Serializable`) |
| `UUID` | `java.util.UUID` |
| `Date` / `TimeInterval` | `java.time.Instant` / `Double` (도메인은 그대로) |
| `precondition`/`assert` | `require(...)` 또는 `check(...)` |
| `@MainActor` | `Dispatchers.Main` 컨텍스트 (ViewModel 내부) |
| `ObservableObject` + `@Published` | `ViewModel` + `MutableStateFlow` / `StateFlow<T>` |
| `Combine.Publisher` / `sink` | `Flow<T>` / `Flow.collect` |
| `Task { @MainActor in ... }` | `viewModelScope.launch(Dispatchers.Main)` |

### 3.2 SwiftUI → Compose

| SwiftUI | Compose |
|---|---|
| `View` | `@Composable fun` |
| `@StateObject` ViewModel | `viewModel<T>()` (Hilt-aware) |
| `@Published` 바인딩 | `collectAsStateWithLifecycle()` |
| `.sheet` | `ModalBottomSheet` (Material 3) |
| `Picker` (wheel) | **커스텀** `LazyColumn` + `rememberSnapFlingBehavior` |
| `TimelineView(.periodic(_, by: 1))` | `LaunchedEffect` 또는 `produceState` + `delay(1.seconds)` 루프 |
| `.onChange(scenePhase)` | `LifecycleEventEffect(Lifecycle.Event.ON_RESUME)` |
| `Color(.systemBackground)` | `MaterialTheme.colorScheme.background` |
| `Color(red:green:blue:)` | `Color(r, g, b, alpha=1f)` (둘 다 0..1f) |
| SF Symbol | `Icon(Icons.Default.Timer ...)` 또는 Material Symbols Compose |
| Identity color slot | iOS와 동일 RGB 6슬롯 (`UI.md` §4.2 그대로) |
| `.spring(response: 0.28, dampingFraction: 0.86)` | `spring(stiffness, dampingRatio)` 동등 시각 효과로 튜닝 |

### 3.3 라이프사이클 / 영속성 / 알림 / 위젯

| iOS API | Android 등가 | 비고 |
|---|---|---|
| `UIApplicationDelegateAdaptor` | `Application` 클래스 + `Activity.onCreate` | 포트레이트 락은 매니페스트 `android:screenOrientation="portrait"` |
| `UserDefaults` | `DataStore<Preferences>` 또는 `DataStore<Proto>` | 키 `"ptimer.timer-state.snapshot"` 그대로 사용 가능 |
| `JSONEncoder/Decoder` | `kotlinx.serialization.json.Json` | iOS Codable의 "nil 필드는 인코딩 안 함" 기본 동작과 호환되도록 `Json { explicitNulls = false }` 설정 권장 |
| `UNUserNotificationCenter` | `NotificationManagerCompat` + `AlarmManager` | 정확한 시점 → `setExactAndAllowWhileIdle` 또는 `setAlarmClock` |
| `UNCalendarNotificationTrigger` | `AlarmManager.setExactAndAllowWhileIdle(RTC_WAKEUP, endDateMillis, pendingIntent)` | 식별자 `"timer-completion-<uuid>"` 그대로 |
| `requestAuthorization([.alert, .sound])` | Android 13+ `POST_NOTIFICATIONS` 런타임 권한 + 채널 생성 | 채널 importance `IMPORTANCE_HIGH` 권장 |
| `AudioServicesPlaySystemSound(1005)` | `RingtoneManager.getRingtone(context, NOTIFICATION_URI).play()` 또는 `ToneGenerator` | 단발 |
| `UINotificationFeedbackGenerator(.success)` | `Vibrator.vibrate(VibrationEffect.createPredefined(EFFECT_DOUBLE_CLICK))` | 의미 동등 |
| `UIApplication.applicationState == .active` | `ProcessLifecycleOwner.get().lifecycle.currentState >= RESUMED` | 포그라운드 알림 발화 가드 |
| `ActivityKit Live Activity` | **R1**: AppWidget + Notification (Android 14+ Live Update 일부 폴백) | 자세한 §6 |

### 3.4 Tick 루프

iOS의 `Timer + RunLoop.main`은 Android에선 ViewModel scope 내 `tickerFlow` 또는 Compose `LaunchedEffect` + `delay(100)` 루프. 100ms 주기 동일. 라이프사이클 파괴 시 자동 cancel — `viewModelScope` 사용.

---

## 4. 도메인 직역 가이드

### 4.1 `domain-exposure`

`ExposureCalculator` (`Calculator.md` §1):

- `kotlin.math.pow(2.0, stop.toDouble())`로 ND 적용. `Double.isFinite()` 확인 후 overflow 처리.
- `kotlin.math.log2(x)` stdlib 사용.
- `String.format`은 `Locale.ROOT` 명시 (Java locale 영향 회피).
- `formatRawSeconds`의 reciprocal 비교 임계값 `0.05` 그대로 — 카메라 표기 흡수 의도.
- `stabilityEpsilon = 0.000_001`, `fullStopShutterSpeeds` 19개 값 그대로.

### 4.2 `domain-reciprocity`

도메인 타입은 sealed class + data class 조합:

```kotlin
@Serializable data class FilmIdentity(
    val id: String,
    val kind: FilmIdentityKind,
    val canonicalStockName: String,
    val manufacturer: String? = null,
    /* ... */
)

@Serializable
sealed class ReciprocityRule {
    @SerialName("threshold") @Serializable
    data class Threshold(val threshold: ThresholdReciprocityRule) : ReciprocityRule()
    @SerialName("formula") @Serializable
    data class Formula(val formula: FormulaReciprocityRule) : ReciprocityRule()
    @SerialName("table") @Serializable
    data class Table(val table: TableReciprocityRule) : ReciprocityRule()
    @SerialName("advisory") @Serializable
    data class Advisory(val advisory: AdvisoryReciprocityRule) : ReciprocityRule()
}
```

iOS의 wrapper 형식(`{"kind":"threshold","threshold":{...}}`)을 1:1 호환하려면 `JsonClassDiscriminator` 또는 custom serializer 필요. 1차 포팅은 wrapper 형식 그대로 유지 권고.

`ReciprocityCalculationPolicyEvaluator`:

- 평가 순서 6단계가 *계약* (`Calculator.md` §2). 코드 흐름은 Swift와 1:1.
- `comparisonTolerance = 0.000_001` 동일.
- 두 estimation family (logLog / stopSpace) 수식 그대로 (`kotlin.math.ln`, `pow`, `log2`).
- 결과 메타데이터 invariant (`Calculator.md` §2.4 표) 그대로. 위반 시 `IllegalStateException`.

`ReciprocityConfidencePresentationMapper`:

- basis × authority 표 (`Calculator.md` §4) 그대로 직역. `when` 표현식.
- explanation token enum 그대로.
- `FilmModeDetailsDisplayState` 등 디스플레이 상태(iOS는 `ExposureCalculatorFilmContext.swift`에 위치)는 Android에서는 `feature-calculator`의 ViewModel 출력 모델 디렉토리로 분리 권장.

### 4.3 `domain-timer`

`TimerState` 직역:

```kotlin
data class TimerState(
    val id: UUID,
    val duration: Double,            // 초
    val startDate: Instant,
    val endDate: Instant?,
    val pausedRemainingTime: Double?,
    val pausedAt: Instant?,
    val status: TimerStatus,
)

const val timerStabilityEpsilon = 0.000_001
```

`Instant` 차이는 `Duration.between(a, b).toMillis() / 1000.0`로 초 단위 Double 변환. ε 보정 동일.

`PersistentTimerSnapshot`:

- `kotlinx.serialization` `data class`로 직역
- `SnapshotStatus` decoder의 legacy `"stopped" → paused` 호환은 custom serializer로
- 복원 분기 (`Timer.md` §4) 그대로

### 4.4 `data-catalog`

`LaunchPresetFilmCatalogLoader`:

- `assets/LaunchPresetFilmCatalog.json`을 `context.assets.open(...)`로 읽음
- `Json.decodeFromString<List<FilmIdentity>>(...)`
- 검증 규칙 9가지 (`DomainSchema.md` §4.3) 그대로 sealed class 에러로

### 4.5 `data-persistence`

DataStore Preferences 기반 어댑터. 키 `"ptimer.timer-state.snapshot"` *iOS와 동일* (디버깅·향후 sync 가능성을 위해).

테스트용 NoOp store는 in-memory 또는 항상 빈 결과 반환 — iOS 패턴 그대로.

---

## 5. UI 직역 가이드

### 5.1 ExposureCalculatorScreen

`UI.md` §2 그대로:

- 3-density (regular 620 / compact 560 / dense 488 dp). `BoxWithConstraints`로 가용 높이 측정 후 분기.
- 베이스 셔터 wheel picker — 커스텀 `LazyColumn` + `rememberSnapFlingBehavior`. **full-stop 19개**.
- ND stop wheel picker — 동일 패턴. 정수 **0..30**.
- ResultSection — `FilmModeExposureResultState`를 1:1 매핑하는 Compose 함수 트리.
- 필름 셀렉터 — `ModalBottomSheet`. 선택 시 onDismiss.
- 디테일 시트 — `ModalBottomSheet`에 그래프 + 표 행.

### 5.2 BottomSheetWorkspace

iOS의 `BottomSheetWorkspaceShell` 등가:

- 두 detent (compact/large) 직접 구현. Material 3 `ModalBottomSheet`는 부족 → 커스텀 `Box` + `Modifier.draggable` + `animateDpAsState`.
- 컴팩트 도크: `LazyRow` 96×96 dp 카드 + 86×96 dp 오버플로 카드.
- 드래그 임계값 92dp 위/64dp 아래 그대로.
- `compactItems` 데이터: 도메인 → snapshot 변환 (PresentationAdapter 직역, KMP 후보 코드).
- 정렬 규칙: running·paused → completed, 각 그룹 내 최신순.
- Identity palette 6슬롯 RGB *그대로*. UUID 바이트 해시도 동일 알고리즘.
- Status 색: SwiftUI 시스템 색이 아니라 의미 동등으로 매핑 (success/warning/inactive). Material 3 톤 또는 의미 색상으로 튜닝.

### 5.3 Wheel picker 구현 메모

- `LazyListState`의 `firstVisibleItemIndex`를 selected index로 환산
- `snapFlingBehavior`로 정확한 행 정렬
- 디바운스: 사용자 fling 종료 후 100ms 후 ViewModel에 commit
- 위/아래 padding으로 첫·마지막 항목이 중앙에 올 수 있도록

---

## 6. 잠금화면 위젯 / Live Activity 대응

### 6.1 Android 한계 (R1)

- iOS ActivityKit Live Activity는 **잠금화면 실시간 갱신 카드**. Android에는 진정한 등가 없음 (Android 14의 일부 OEM Live Updates는 표준 아님).
- 가능한 대체:
  - **AppWidget** — 홈 스크린 위젯. 잠금화면 위젯은 일부 OEM/AOSP에서만.
  - **MediaStyle Notification** — 카운트다운에 어색.
  - **ForegroundService + Notification** — 정확한 시점 + 잠금화면에 보임. **1차 포팅 권장 폴백**.

### 6.2 권장 구현 (ForegroundService 폴백)

```
running 타이머 ≥ 1 → ForegroundService 시작
                     → Notification (ongoing, sticky, 잠금화면 표시)
                     → AlarmManager로 endDate에 트리거 예약
                     → 사용자 잠금 해제 시 notification tap → 앱
모든 running 종료    → ForegroundService 중지, AlarmManager 취소
```

Notification 템플릿: title/text/subText/chronometer (countdown). `scheduledTargets[]`는 notification action 또는 expanded view에 추가.

### 6.3 AppWidget (선택, 향후)

홈 스크린 위젯으로 동등 정보 노출. `AppWidgetProvider` + 30초/알람 시점 갱신 권장 (1초 갱신은 배터리 영향).

---

## 7. 포팅 순서 (의존성 역순)

각 단계 후 단위 테스트 잠금 (`TestParity.md` 표 단위로 진행):

```
0. 모듈 스켈레톤 + Gradle (Kotlin 2.x, Compose BOM, kotlinx.serialization, datastore, hilt)
1. domain-exposure                  ← ExposureCalculator + 잠금 단위 테스트
2. domain-reciprocity (도메인 부분)  ← ReciprocityDomain + 직렬화 round-trip
3. domain-reciprocity (정책 부분)    ← Policy evaluator + 평가 순서 테스트 (6단계)
4. domain-reciprocity (프레젠테이션) ← Confidence mapper + 매트릭스 테스트
5. data-catalog                     ← LaunchPresetFilmCatalog 로더 + 검증 9 + 4종 인덱스
6. domain-timer                     ← TimerState + sanitize + snapshot codec
7. data-persistence                 ← DataStore 어댑터 + 키 보존
8. ViewModel 레이어                  ← StateFlow 기반, display-state data class
9. Compose UI: Calculator → BottomSheet → Picker → Film modal
10. Notifications + AlarmManager
11. ForegroundService + 잠금화면 notification (R1 폴백)
12. (선택) AppWidget
```

---

## 8. 위험 등록부

| ID | 위험 | 영향 | 완화 |
|---|---|---|---|
| **R1** | ActivityKit 등가물 부재 | 잠금화면 실시간 카드 제공 못 함 | ForegroundService + sticky notification 폴백; 사용자 온보딩에 명시 |
| **R2** | `SCHEDULE_EXACT_ALARM` 권한 거부 (Android 12+) | 정확한 종료 시간 알림 실패 가능성 | 첫 알람 등록 시 권한 요청 + 거부 시 inexact 알람 폴백 + UI 경고 |
| **R3** | Android 13+ `POST_NOTIFICATIONS` 런타임 권한 거부 | 모든 알림 발생 안 함 | 첫 타이머 시작 시 권한 요청 + 거부 시 인앱 토스트 + 설정 deep link |
| **R4** | Doze / App Standby로 백그라운드 작업 지연 | 알림 시점 부정확 | `setExactAndAllowWhileIdle`; WorkManager는 1차 미사용 |
| **R5** | 부동소수점 결과 미세 오차 | iOS와 다른 케이스에서 0.000_002 차이 → 잠금 테스트 실패 | 모든 단위 테스트에서 epsilon `1e-6`; 코드 수식은 1:1 직역 |
| **R6** | Snapshot JSON 키 불일치 | iOS↔Android 디버깅 어려움 | iOS 키 그대로 (camelCase); kotlinx.serialization custom serializer로 wrapper 형식 유지 |
| **R7** | wheel picker UX가 SwiftUI Picker와 미세하게 다름 | 사용자 친밀도 ↓ | 시뮬레이터-실기 비교 후 fling 속도/snap 동작 튜닝 |
| **R8** | `BottomSheetWorkspaceShell`의 두 detent 정확 재현 | Material 3 ModalBottomSheet 부족 | 커스텀 Box + Modifier.draggable로 직접 구현 |
| **R9** | spring 애니메이션 정확 매칭 어려움 | 미세 시각 차이 | Compose `spring`으로 *시각적 동등*까지 |
| **R10** | iOS `XCTestRuntime.isRunningTests` 등가 부재 | 테스트가 실수로 실 OS 채널 호출 | DI 컨테이너(Hilt)로 NoOp 페어 항상 주입; `@HiltAndroidTest` 별도 설정 |

---

## 9. 보호 영역 (Android 측에서도 동일하게 보존)

iOS와 동일하게, 다음 7종은 Android 코드에서도 task-level approval 없이 변경 금지:

1. 노출 계산: `ExposureCalculator.calculate`, snap-to-full-stop 두 tier, `stabilityEpsilon`
2. Reciprocity 정책 평가 순서 6단계 + 결과 invariant (위키 PTIMER-90)
3. Confidence 매핑 (basis × authority → level/badge/emphasis)
4. 타이머 상태머신 (running/paused/completed 전이) + sanitize
5. 영속성 키와 JSON 스키마 (snapshot codec, 카탈로그 검증) (PTIMER-86)
6. **Timer truth invariants** (위키 8880129):
   - Timer runtime state = source of truth
   - Dock/sheet/overlay/list = projection only
   - tick 시 전체 workspace 재빌드 금지 (Compose: `remember`된 sub-component만 recompose)
   - Calculator input ≠ timer metadata mutation
   - Android 매핑: `StateFlow<List<TimerState>>`이 source, projection은 `derivedStateOf` 또는 `Flow.map`. UI state holder는 truth 소유 금지.
7. **Result hierarchy invariant** (위키 16482307): Adjusted/Corrected 행은 advisory-only/unsupported에서도 *visible*, fabricated numeric value 금지.

Android 측 CLAUDE.md 또는 README에 동일 문구로 명시. 위키 페이지 ID는 source comment에 인용.

---

## 10. 산출 모듈 구조 요약

```
ptimer-android/
├── settings.gradle.kts
├── build.gradle.kts
├── app/
│   ├── src/main/AndroidManifest.xml         (portrait, POST_NOTIFICATIONS, SCHEDULE_EXACT_ALARM)
│   └── src/main/java/.../PTimerApp.kt
├── feature-calculator/
│   └── src/main/java/.../ui/ExposureCalculatorScreen.kt
├── feature-timer/
│   ├── src/main/java/.../ui/BottomSheetWorkspace.kt
│   └── src/main/java/.../widget/TimerNotificationService.kt
├── domain-exposure/
│   └── src/main/kotlin/.../ExposureCalculator.kt
├── domain-reciprocity/
│   ├── src/main/kotlin/.../ReciprocityDomain.kt
│   ├── src/main/kotlin/.../ReciprocityCalculationPolicyEvaluator.kt
│   └── src/main/kotlin/.../ReciprocityConfidencePresentationMapper.kt
├── domain-timer/
│   ├── src/main/kotlin/.../TimerState.kt
│   └── src/main/kotlin/.../PersistentTimerSnapshot.kt
├── data-persistence/
│   └── src/main/java/.../TimerPersistenceStore.kt
└── data-catalog/
    ├── src/main/java/.../LaunchPresetFilmCatalogLoader.kt
    └── src/main/assets/LaunchPresetFilmCatalog.json   (iOS와 동일 파일)
```

`assets/LaunchPresetFilmCatalog.json`은 iOS의 `PTimer/Resources/LaunchPresetFilmCatalog.json`을 *동일 파일* 복사. 카탈로그 업데이트 시 양쪽 동시 갱신.

---

## 11. 타임라인 추정 (참고)

| 단계 | 추정 노력 |
|---|---|
| 0. 모듈 스켈레톤 | 0.5d |
| 1–4. 도메인 / 정책 / Confidence | 3–5d (테스트 포함) |
| 5. 카탈로그 로더 | 1d |
| 6–7. Timer / Persistence | 2–3d |
| 8. ViewModel | 2–3d |
| 9. Compose UI | 5–7d (3-density + 두 detent + wheel picker) |
| 10. Notifications | 2d |
| 11. ForegroundService 폴백 | 2–3d |
| 12. AppWidget | (선택) 2d |
| 통합 테스트 / 디버그 / 사용자 검증 | 3–5d |
| **합계** | **약 22–32d (1인, 풀타임)** |

추정만이며 실 작업은 senior arch 결정 후 정밀 산정.

---

## 12. 비-목표 재확인

- iOS ↔ Android 코드 자동 sync 없음
- KMP 멀티플랫폼 1차 미사용 (단, KMP 친화 패턴으로 작성)
- Live Activity 1:1 동등 없음 (R1)
- 한국어 / 다국어 1차 미포함
- 새 기능 없음
- 본 문서는 *iOS 분석 문서*를 권위 베이스로 한다. iOS 분석이 wiki와 어긋나면 wiki를 따른다.
