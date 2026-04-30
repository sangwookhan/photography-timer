# Record-Replay Trace Infrastructure

Event-sequence record-replay harness used as the L2 *semantic
equivalence* gate for B1 (ViewModel 4분할), B3 (Reciprocity Result
enum), and B4 (Timer state types). Complementary to B8 (`Snapshots/`)
and B6 (`shared/test-fixtures/`), not a replacement.

## 무엇을 검증하나

- **이벤트 시퀀스의 결정적 직렬화**. ViewModel + TimerManager가
  외부 협력자(LockScreen exposer, persistence, notification
  scheduler)에게 *어떤 호출을 어떤 순서로* 발행하는지를 lock한다.
- 같은 시나리오 → 같은 trace.
- 시간은 가상 시계(`RecordReplayHarness.virtualNow`)로 진행되며
  `Date` 값은 trace에서 reference date 기준 상대 offset으로
  렌더된다. 실제 timestamp는 trace에 들어가지 않는다.
- 단계 번호(`step`)는 monotonic integer. wall-clock timestamp가
  아니다.

## 왜 in-house인가

- `DisplayStateSnapshot`(B8)과 동일한 이유. 외부 의존 없이
  `Swift.dump` 텍스트 직렬화 + on-disk diff로 충분하며,
  baseline 파일은 PR diff로 검토 가능.
- B8과 baseline 라이프사이클(`RECORD_REPLAY=1`로 재기록 →
  fail → 검토 → 두 번째 실행으로 verify)이 의도적으로 동일.

## 라이프사이클

1. **첫 실행**: baseline 없음 → 헬퍼가 파일 작성 후 *fail*
   (의도 commit 강제).
2. **이후 실행**: baseline 읽고 `recorder.renderTrace()` 결과와
   비교. 다르면 fail + sidecar `.actual.txt` 작성.
3. **의도적 갱신**: `RECORD_REPLAY=1` env로 실행 → baseline
   덮어쓰고 fail. 두 번째 실행(env 없이)으로 verify.

```bash
# Re-record after deliberate change
RECORD_REPLAY=1 xcodebuild test \
  -project PTimer.xcodeproj -scheme PTimer \
  -destination 'platform=iOS Simulator,id=1D7DAD65-A280-4114-A928-585CAEE969E9' \
  -only-testing:PTimerTests/RecordReplayBaselineSmokeTests

# Verify (no env)
xcodebuild test ... -only-testing:PTimerTests/RecordReplayBaselineSmokeTests
```

Baseline 위치: `PTimerTests/__RecordReplay__/<TestClass>/<name>.txt`.

## 언제 사용하나 (3개 헬퍼 비교)

| 헬퍼 | 검증 단위 | 대표 사용처 |
| --- | --- | --- |
| `DisplayStateSnapshot` (B8) | 단일 값의 직렬화 | Presenter 출력, 정책 결과, catalog snapshot. 입력→출력 매핑 한 단계 |
| `shared/test-fixtures/` (B6) | 입출력 페어 (golden 데이터) | Reciprocity 결과 cross-platform 비교. 입력 + 기대 출력 JSON |
| `RecordReplay` (this) | **이벤트 시퀀스** | 시간/상태 전이를 동반하는 시나리오. 협력자 호출 순서·payload |

기준:
- **단일 값**의 직렬화 회귀가 관심사면 B8.
- **iOS↔Android(또는 미래의 다른 플랫폼)** 동등성 검증이면 B6.
- ViewModel/TimerManager가 **여러 외부 호출**을 발행하는 시나리오
  (`exposer.expose`/`exposer.clear`, `persistence.save` 등)
  의 순서·내용을 lock해야 하면 record-replay.

## 새 spy 추가하기

`RecordReplaySpies.swift`의 패턴을 따른다:

1. 대상 protocol 채택.
2. init에서 `RecordReplayRecorder` + 이벤트 prefix + `referenceDate`
   를 받는다.
3. 각 메서드에서 `recorder.record(_:payload:)` 또는
   `recorder.recordSignal(_:)`을 호출.
4. `Date` 페이로드는 `RecordReplayDateRendering.render(_:referenceDate:)`
   로 reference-date-relative offset으로 렌더.
5. **fake business behavior 금지** — 비-trivial return은 `NoOp*`
   기본값과 동등해야 한다. 시나리오가 primed return을 필요로
   하면 별도 spy variant로 분리.

## 시나리오 작성 패턴

```swift
@MainActor
func testMyScenario() {
    let harness = RecordReplayHarness()
    let viewModel = ExposureCalculatorViewModel(
        dependencies: harness.makeDependencies()
    )

    // Drive the scenario via ViewModel surface or TimerManager
    // surface. Use deterministic UUIDs (do not rely on `UUID()`).
    _ = harness.underlyingTimerManager.start(
        id: UUID(uuidString: "...")!,
        duration: 30
    )
    harness.advanceAndTick(by: 30)

    RecordReplayBaseline.assert(harness.recorder, named: "my-scenario")
}
```

핵심 결정:

- **시간**: `harness.advance(by:)` / `advanceAndTick(by:)`로만 진행.
  `XCTWaiter`/`Thread.sleep` 금지.
- **UUID**: 시나리오에서 직접 고정. ViewModel의 `startTimer(from:)`
  처럼 내부에서 `UUID()`를 호출하는 API는 trace 비결정성의 원인.
- **payload**: `Swift.dump` 출력. Swift 버전에 안정적이지만
  타입 이름 변경(B1/B3/B4가 의도하는 바)이 일어나면 baseline diff
  가 발생 — 그게 record-replay의 목적이다.

## 참조

- 절차 spec: `Docs/Verification/Strategy.md` §6
- 자매 헬퍼: `PTimerTests/Snapshots/README.md` (B8)
- 진행 상태: `Docs/StructureImprovement/Plan.md` §3.9
