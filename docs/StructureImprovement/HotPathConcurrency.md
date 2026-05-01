# Hot-Path Concurrency Measurement (B9)

**측정일**: 2026-04-29 (HEAD = `eaed96f`)
**호스트**: iPhone 17 Simulator (Xcode 26.4)
**테스트**: `PTimerTests/ReciprocityCalculationPolicyPerformanceTests` (5 케이스)
**용도**: 정책 평가기가 main thread frame budget을 위협하는지 결정. B9 후속(actor 분리) 필요성 평가.

---

## 1. 동기

`Docs/StructureImprovement/Plan.md` §3.5 B9는 picker 스크롤 시 정책 평가가 frame budget을 압박하는지 측정하고, 결과에 따라 actor 분리(Phase 3)를 결정한다. 60 fps 기준 한 frame = **16,667 μs** = 16.67 ms.

Picker 스크롤 시 표시되는 film 행마다 정책 평가가 수행될 수 있다 (현재 코드 경로). 행 5개 visible × scroll 가속 시 frame 당 다중 evaluation 가능성이 있다.

---

## 2. 측정 방법

XCTest `measure` 블록으로 1,000회 evaluation을 측정. XCTMeasure 기본 설정(10 iteration × 1,000 evaluation = 10,000 evaluation per test).

| 케이스 | 프로파일 | metered | 경로 |
|---|---|---|---|
| `testInterpolatedTriXEvaluationPerformance` | Tri-X 400 | 7s | log-log interpolation |
| `testExtrapolatedTriXEvaluationPerformance` | Tri-X 400 | 1500s | log-log extrapolation |
| `testFormulaBasedHP5EvaluationPerformance` | HP5+ | 100s | formula derived |
| `testThresholdNoCorrectionPerformance` | Velvia 50 | 0.5s | threshold no-correction |
| `testMixedPickerScrollWorkloadPerformance` | 4 films × 11 metered points | varied | 혼합 |

### 재현

```bash
xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PTimerTests/ReciprocityCalculationPolicyPerformanceTests \
  test
```

---

## 3. 결과

### 3.1 케이스별 wall-clock

| 케이스 | Wall-clock (10 measure × 1,000 eval) | ≈ μs / eval |
|---|---|---|
| `testThresholdNoCorrectionPerformance` | 0.373 s | ~37 |
| `testInterpolatedTriXEvaluationPerformance` | 0.358 s | ~36 |
| `testFormulaBasedHP5EvaluationPerformance` | 0.285 s | ~29 |
| `testExtrapolatedTriXEvaluationPerformance` | 0.842 s | ~84 |
| `testMixedPickerScrollWorkloadPerformance` | 0.350 s | ~32 |

Wall-clock에는 XCTest framework 오버헤드 (수십 ms) 포함. 실제 evaluate 비용은 보고된 값보다 조금 더 작음. 하지만 **상한값**으로 안전하게 사용 가능.

### 3.2 Frame budget 비교

| 메트릭 | 값 |
|---|---|
| 60 fps frame budget | 16,667 μs |
| 최악 단일 evaluate (extrapolation) | ~84 μs |
| **frame budget 점유율 (worst case)** | **~0.5%** |
| 5 visible rows × evaluate per frame (worst) | ~420 μs (~2.5%) |
| 10 evaluate per frame (가장 공격적인 가정) | ~840 μs (~5%) |

---

## 4. 결론

**Actor 분리 비-필요.** 정책 평가는 main thread frame budget의 1% 미만을 사용. picker 스크롤이 다중 evaluate을 트리거해도 5%를 넘지 않을 것으로 예상. 실제 구현은 row 표시 시점에 한 번 evaluate (cache 가능)할 것이므로 부하는 더 작다.

### B9 후속 (Phase 3 actor 분리) 결정

- **현재**: NOT NEEDED. 측정 결과가 임계값 (frame budget 30% 초과) 미달.
- **재측정 트리거**:
  - Reciprocity 평가 로직이 새로운 외부 I/O 의존성 추가 (예: 네트워크/디스크)
  - 영속화된 dataset 크기 10×↑
  - User-defined formula 도입 후 평가 비용 평가
  - 실제 사용자 보고: picker 스크롤 stutter 발생

이 트리거 중 하나라도 발생 시 본 문서의 측정 절차를 다시 실행. 결과가 30%↑이면 actor 분리 spec 작성 후 Phase 3 진입.

---

## 5. Instruments 후속 측정 (선택)

자동화된 위 측정은 XCTMeasure로 충분하지만, 더 정밀한 frame-level 분석이 필요하면 다음 절차로 Instruments에서 picker 스크롤 trace 가능:

1. iOS Simulator 또는 실 디바이스에서 앱 실행
2. Xcode → Product → Profile (⌘I)
3. **Time Profiler** template 선택
4. Record 시작
5. 앱에서 calculator 화면으로 진입 → Film 선택 sheet 열기
6. 4 preset film을 가로/세로 스크롤로 빠르게 (1초 동안 10회 이상) 다회 토글
7. Record 종료
8. Time Profiler 결과에서 `ReciprocityCalculationPolicyEvaluator.evaluate` 검색
9. 호출 횟수 + 누적 시간 + main thread 점유율 확인

이 절차의 결과를 본 문서 §3에 추가 표로 기록.

---

## 6. 후속 갱신

- B1 ViewModel 분할 후 ReciprocityModel이 evaluate를 호출하는 시점이 바뀔 수 있음 → 재측정 권고.
- 새 Film catalog 항목 추가 시 (특히 table profile entry 다수 추가) → 재측정.
- 각 측정은 본 문서의 §3 표를 추가 row로 갱신 (date column).
