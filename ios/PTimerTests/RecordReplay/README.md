# Record-Replay Trace Infrastructure

Event-sequence record-replay harness. The 7 committed baselines pin
one thing the assertion suites do not: the **cross-collaborator call
order and payload** — lock-screen exposer, notification scheduler,
and persistence store, interleaved per Timer lifecycle scenario —
as a single trace. The assertion suites (`Timers/TimerManager*`)
verify each collaborator's state in isolation; this harness locks how
their calls interleave over a time-driven scenario.

Scope, stated precisely (PTIMER-213): the committed scenarios drive
`TimerManager` directly (via `harness.underlyingTimerManager`), so
what they pin is the **TimerManager-to-collaborator call contract**.
The `ExposureCalculatorViewModel` is constructed for wiring but its
public surface is not the subject. The harness *mechanism* can serve
as an L2 semantic-equivalence gate for a ViewModel-facade split
(B1) or Result/state type renames (B3/B4) — that is its design
intent — but the current baselines are Timer-lifecycle integration
contracts, not full ViewModel-facade insurance. Complementary to
B8 (`Snapshots/`) and B6 (`shared/test-fixtures/`), not a
replacement.

## 무엇을 검증하나

- **이벤트 시퀀스의 결정적 직렬화**. `TimerManager`가 외부 협력자
  (LockScreen exposer, persistence, notification scheduler)에게
  *어떤 호출을 어떤 순서로* 발행하는지를 lock한다. (하니스는
  ViewModel surface로도 구동 가능하지만, 현재 baseline은
  TimerManager를 직접 구동한다 — 위 Scope 참조.)
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
3. **의도적 갱신**: 테스트 프로세스에 `RECORD_REPLAY=1` env를
   전달해 실행 → baseline 덮어쓰고 fail. 두 번째 실행(env 없이)
   으로 verify.

`xcodebuild`는 쉘 env를 시뮬레이터 테스트 프로세스로 전달하지
않는다. `TEST_RUNNER_` 접두사를 붙이면 접두사를 벗겨 테스트
프로세스에 주입된다 (`TEST_RUNNER_RECORD_REPLAY=1` → 테스트에서
`RECORD_REPLAY=1`). 접두사 없는 `RECORD_REPLAY=1`은 조용히
무시되어 verify 실행과 구별되지 않으니 주의.

```bash
# Re-record after deliberate change (run from repository root)
cd ios && TEST_RUNNER_RECORD_REPLAY=1 xcodebuild test \
  -project PTimer.xcodeproj -scheme PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PTimerTests/RecordReplayBaselineSmokeTests \
  -only-testing:PTimerTests/B4TimerLifecycleBaselineTests

# Verify (no env)
cd ios && xcodebuild test ... \
  -only-testing:PTimerTests/RecordReplayBaselineSmokeTests \
  -only-testing:PTimerTests/B4TimerLifecycleBaselineTests
```

Baseline 위치: `PTimerTests/__RecordReplay__/<TestClass>/<name>.txt`.

## 관리 원칙

PTIMER-213에서 유지(re-record & own)로 결정. baseline이 다시
방치되지 않도록:

1. **Protected Area 변경 후 suite 실행.** 타이머 런타임 semantics
   또는 persistence/restore 계약을 건드린 티켓은 완료 전에 이
   suite를 실행한다.
2. **diff 발생 시 원인 검토 먼저.** 호출 순서·payload 변화가 해당
   티켓이 의도한 것인지 확인한다. 의도하지 않은 diff는 회귀다.
3. **의도된 변경일 때만 갱신.** 위의 재기록 명령
   (`TEST_RUNNER_RECORD_REPLAY=1`)으로 재기록하고, env 없이
   재실행해 verify한 뒤 baseline diff를 커밋에 포함한다.

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

- 절차 spec: `docs/verification/Strategy.md` §6
- 자매 헬퍼: `ios/PTimerKit/Tests/PTimerKitTests/Snapshots/README.md` (B8)
