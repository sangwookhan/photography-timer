import XCTest
@testable import PTimer

/// Pins the draft / input-source contract for the Target Shutter
/// input sheet. The state model isolates these rules from the
/// SwiftUI hosting harness so we can verify them as plain logic:
///
///   1. Draft is the single source of truth — both Quick and Fine
///      modes write to it; wheel positions are stored separately.
///   2. The inactive mode's wheel state is **frozen** while the
///      active mode is being edited, and resyncs from the draft
///      only on mode transition.
///   3. Quick selected/focused state is set only by direct Quick
///      taps, cleared by Fine adjustments and by entering Fine mode.
///   4. Returning to Quick mode does *not* auto-select.
final class TargetShutterInputStateTests: XCTestCase {

    /// Mirror of `TargetShutterInputSheet.quickPresets`. Hard-coded
    /// here so the contract is self-contained — if the sheet's
    /// preset list ever changes, these tests pin the *behavior*
    /// (input-source rules) independently from the *catalogue*.
    private let presets: [TimeInterval] = [
        1, 2, 4, 8, 15, 30,
        60, 120, 240, 480,
        900, 1800,
        3600, 7200, 14_400, 28_800
    ]

    // MARK: - Initial state

    func testInitialDraftFromOnLadderSeedDoesNotAutoSelectQuick() {
        let state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)

        XCTAssertEqual(state.draftSeconds, 60)
        XCTAssertEqual(state.activeMode, .quick)
        XCTAssertNil(state.quickSelectedPreset,
                     "Initial open never auto-selects — Quick selection requires a direct tap in this sheet session")
        XCTAssertEqual(state.quickWheelAnchor, 60,
                       "Quick wheel must park on the nearest preset to the seed")
        XCTAssertEqual(state.fineHours, 0)
        XCTAssertEqual(state.fineMinutes, 1)
        XCTAssertEqual(state.fineSeconds, 0)
    }

    func testInitialDraftFromOffLadderSeedKeepsExactValueAndParksWheelOnNearest() {
        let state = TargetShutterInputState.initial(seedSeconds: 65, quickPresets: presets)

        XCTAssertEqual(state.draftSeconds, 65,
                       "Off-ladder seed must round-trip — the draft is the source of truth")
        XCTAssertEqual(state.quickWheelAnchor, 60,
                       "Quick wheel parks on the nearest preset (60 vs 120, distance 5 vs 55)")
        XCTAssertEqual(state.fineMinutes, 1)
        XCTAssertEqual(state.fineSeconds, 5)
        XCTAssertNil(state.quickSelectedPreset)
    }

    func testInitialDraftFromNilSeedFallsBackToOneMinuteDefault() {
        let state = TargetShutterInputState.initial(seedSeconds: nil, quickPresets: presets)

        XCTAssertEqual(state.draftSeconds, 60)
        XCTAssertEqual(state.quickWheelAnchor, 60)
        XCTAssertEqual(state.fineMinutes, 1)
    }

    func testInitialDraftSanitizesInvalidSeed() {
        let nan = TargetShutterInputState.initial(seedSeconds: .nan, quickPresets: presets)
        XCTAssertEqual(nan.draftSeconds, 60)

        let negative = TargetShutterInputState.initial(seedSeconds: -10, quickPresets: presets)
        XCTAssertEqual(negative.draftSeconds, 60)

        let zero = TargetShutterInputState.initial(seedSeconds: 0, quickPresets: presets)
        XCTAssertEqual(zero.draftSeconds, 60)
    }

    func testInitialDraftClampsHugeSeedToMaximum() {
        let state = TargetShutterInputState.initial(seedSeconds: 999_999, quickPresets: presets)

        XCTAssertEqual(state.draftSeconds, 23 * 3600 + 59 * 60 + 59)
        XCTAssertEqual(state.fineHours, 23)
        XCTAssertEqual(state.fineMinutes, 59)
        XCTAssertEqual(state.fineSeconds, 59)
    }

    // MARK: - Quick tap (active mode = Quick)

    func testQuickTapWritesDraftAndQuickWheelOnly() {
        var state = TargetShutterInputState.initial(seedSeconds: nil, quickPresets: presets)
        let initialFineH = state.fineHours
        let initialFineM = state.fineMinutes
        let initialFineS = state.fineSeconds

        state.applyQuickTap(300)

        XCTAssertEqual(state.draftSeconds, 300)
        XCTAssertEqual(state.quickWheelAnchor, 300)
        XCTAssertEqual(state.quickSelectedPreset, 300)
        XCTAssertEqual(state.activeMode, .quick)

        // Fine state must NOT update mid-Quick-scroll — the Fine
        // wheels (which may be visible behind the page indicator
        // depending on the pager) stay still until the user actually
        // switches mode.
        XCTAssertEqual(state.fineHours, initialFineH)
        XCTAssertEqual(state.fineMinutes, initialFineM)
        XCTAssertEqual(state.fineSeconds, initialFineS)
    }

    func testQuickTapAfterFineEditRestoresSelection() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)

        state.applyFineChange(hours: 0, minutes: 1, seconds: 5)
        XCTAssertNil(state.quickSelectedPreset)

        state.applyQuickTap(480)
        XCTAssertEqual(state.draftSeconds, 480)
        XCTAssertEqual(state.quickWheelAnchor, 480)
        XCTAssertEqual(state.quickSelectedPreset, 480)
        XCTAssertEqual(state.activeMode, .quick)
    }

    // MARK: - Fine adjustment (active mode = Fine)

    func testFineChangeWritesDraftAndFineFieldsOnly() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyQuickTap(60)
        let originalQuickAnchor = state.quickWheelAnchor

        state.applyFineChange(hours: 0, minutes: 1, seconds: 5)

        XCTAssertEqual(state.draftSeconds, 65)
        XCTAssertEqual(state.fineHours, 0)
        XCTAssertEqual(state.fineMinutes, 1)
        XCTAssertEqual(state.fineSeconds, 5)
        XCTAssertEqual(state.activeMode, .fine)
        XCTAssertNil(state.quickSelectedPreset,
                     "Fine adjustment must clear any prior Quick selection")

        // Quick wheel state must NOT update mid-Fine-scroll — the
        // Quick wheel (or its peek) stays still until mode-switch.
        XCTAssertEqual(state.quickWheelAnchor, originalQuickAnchor,
                       "Quick wheel anchor stays frozen while Fine is the active source")
    }

    func testFineChangeLandingExactlyOnPresetDoesNotSelectIt() {
        var state = TargetShutterInputState.initial(seedSeconds: 65, quickPresets: presets)

        state.applyFineChange(hours: 0, minutes: 1, seconds: 0)

        XCTAssertEqual(state.draftSeconds, 60)
        XCTAssertNil(state.quickSelectedPreset,
                     "Fine landing on a preset value MUST NOT mark it selected")
    }

    func testRepeatedFineChangesKeepQuickSelectionCleared() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyQuickTap(60)

        state.applyFineChange(hours: 0, minutes: 1, seconds: 30)
        state.applyFineChange(hours: 0, minutes: 2, seconds: 0)
        state.applyFineChange(hours: 0, minutes: 3, seconds: 15)

        XCTAssertEqual(state.draftSeconds, 195)
        XCTAssertNil(state.quickSelectedPreset)
    }

    func testFineChangeClampsBeyondMaximum() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)

        state.applyFineChange(hours: 99, minutes: 99, seconds: 99)

        // Stored Fine fields hold the clamped values too — anything
        // else would let the wheel UI show a different total than
        // the draft on the next render.
        XCTAssertEqual(state.draftSeconds, 23 * 3600 + 59 * 60 + 59)
        XCTAssertEqual(state.fineHours, 99,
                       "Stored Fine hours field accepts the raw user input; clamping is applied to the draft")
    }

    // MARK: - Mode transitions

    func testEnterFineModeReseedsFineWheelsFromDraft() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)

        // User scrolls Quick to 4m. Fine fields stay at the original
        // (0, 1, 0) — they're frozen while Quick is active.
        state.applyQuickTap(240)
        XCTAssertEqual(state.fineMinutes, 1, "Fine fields stay frozen during Quick scroll")

        // User swipes to Fine. The transition reseeds Fine fields
        // from the draft so the wheels start at the correct value.
        state.setActiveMode(.fine, quickPresets: presets)

        XCTAssertEqual(state.activeMode, .fine)
        XCTAssertEqual(state.fineHours, 0)
        XCTAssertEqual(state.fineMinutes, 4)
        XCTAssertEqual(state.fineSeconds, 0)
        XCTAssertNil(state.quickSelectedPreset,
                     "Switching to Fine clears any Quick selection")
    }

    func testEnterQuickModeReseedsQuickAnchorFromDraftWithoutAutoSelecting() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.setActiveMode(.fine, quickPresets: presets)
        state.applyFineChange(hours: 0, minutes: 6, seconds: 30) // 390s
        XCTAssertEqual(state.quickWheelAnchor, 60,
                       "Quick anchor stays frozen during Fine scroll")

        state.setActiveMode(.quick, quickPresets: presets)

        XCTAssertEqual(state.activeMode, .quick)
        XCTAssertEqual(state.quickWheelAnchor, 480,
                       "Returning to Quick parks the wheel on the nearest preset to the current draft (390s → 480/8m)")
        XCTAssertNil(state.quickSelectedPreset,
                     "Returning to Quick must NOT auto-select a preset")
    }

    func testModeTransitionsPreserveDraft() {
        var state = TargetShutterInputState.initial(seedSeconds: 65, quickPresets: presets)

        state.setActiveMode(.fine, quickPresets: presets)
        XCTAssertEqual(state.draftSeconds, 65)

        state.setActiveMode(.quick, quickPresets: presets)
        XCTAssertEqual(state.draftSeconds, 65)

        state.setActiveMode(.fine, quickPresets: presets)
        XCTAssertEqual(state.draftSeconds, 65)
    }

    // MARK: - Custom marker

    func testQuickIsExactMatchOnLadderValue() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        XCTAssertTrue(state.quickIsExactMatch(in: presets))

        state.applyFineChange(hours: 0, minutes: 0, seconds: 65)
        XCTAssertFalse(state.quickIsExactMatch(in: presets))
    }

    // MARK: - Continuous-row updates

    /// Pins the contract that the `WheelPickerContinuousObserver`
    /// relies on for the Quick wheel: every row passing the centre
    /// updates the draft and the Quick selection live, while the
    /// Fine fields stay frozen.
    func testContinuousQuickRowEmitsUpdateDraftAndLeaveFineFrozen() {
        var state = TargetShutterInputState.initial(seedSeconds: nil, quickPresets: presets)
        let initialFineH = state.fineHours
        let initialFineM = state.fineMinutes
        let initialFineS = state.fineSeconds

        for preset in [1.0, 2.0, 4.0, 8.0] as [TimeInterval] {
            state.applyQuickTap(preset)
            XCTAssertEqual(TimeInterval(state.draftSeconds), preset)
            XCTAssertEqual(state.quickSelectedPreset, preset)
        }

        XCTAssertEqual(state.fineHours, initialFineH)
        XCTAssertEqual(state.fineMinutes, initialFineM)
        XCTAssertEqual(state.fineSeconds, initialFineS,
                       "Continuous Quick scroll must never touch Fine fields")
    }

    /// Pins the equivalent contract for Fine Tune: every row passing
    /// the centre updates the draft, keeps Quick selection cleared,
    /// and leaves the Quick wheel anchor untouched.
    func testContinuousFineRowEmitsUpdateDraftAndLeaveQuickFrozen() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyQuickTap(60)
        let originalQuickAnchor = state.quickWheelAnchor

        for newSeconds in 0...5 {
            state.applyFineChange(hours: 0, minutes: 1, seconds: newSeconds)
            XCTAssertEqual(state.draftSeconds, 60 + newSeconds)
            XCTAssertNil(state.quickSelectedPreset)
        }

        XCTAssertEqual(state.activeMode, .fine)
        XCTAssertEqual(state.quickWheelAnchor, originalQuickAnchor,
                       "Continuous Fine scroll must never touch the Quick wheel anchor")
    }

    // MARK: - Round-trip

    func testQuickThenFineThenQuickClearsAndRestoresSelection() {
        var state = TargetShutterInputState.initial(seedSeconds: nil, quickPresets: presets)

        state.applyQuickTap(60)
        XCTAssertEqual(state.quickSelectedPreset, 60)

        state.setActiveMode(.fine, quickPresets: presets)
        XCTAssertNil(state.quickSelectedPreset)
        state.applyFineChange(hours: 0, minutes: 1, seconds: 5)
        XCTAssertNil(state.quickSelectedPreset)

        state.setActiveMode(.quick, quickPresets: presets)
        XCTAssertNil(state.quickSelectedPreset)

        state.applyQuickTap(120)
        XCTAssertEqual(state.quickSelectedPreset, 120)
        XCTAssertEqual(state.draftSeconds, 120)
    }
}
