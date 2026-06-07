import XCTest
@testable import PTimerKit

/// Pins the single-draft contract for the Target Shutter input sheet,
/// verified off-simulator as plain logic (no SwiftUI host).
///
/// Contract:
///   1. `draftSeconds` is the single source of truth; Fine h/m/s and
///      the Quick anchor are derived from it, so the two modes can
///      never disagree about the value.
///   2. A Quick change is reflected in Fine immediately, and a Fine
///      change in the Quick anchor immediately.
///   3. Value mutators no-op unless their source mode is active, so a
///      stale wheel emit cannot overwrite the draft after a mode swap.
///   4. Off / clear preserves the draft; Confirm commits exactly
///      `draftSeconds`.
final class TargetShutterInputStateTests: XCTestCase {

    /// Mirror of the sheet's Quick preset ladder. Hard-coded so the
    /// behavior contract is independent of the catalogue.
    private let presets: [TimeInterval] = [
        1, 2, 4, 8, 15, 30,
        60, 120, 240, 480,
        900, 1800,
        3600, 7200, 14_400, 28_800,
    ]

    // MARK: - Quick change → draft + derived Fine

    /// Required: a Quick change updates the draft seconds immediately,
    /// and the derived Fine h/m/s recompute to the same value at once.
    func testQuickSelectionUpdatesDraftAndDerivedFineImmediately() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        XCTAssertEqual(state.activeMode, .quick)

        state.applyQuickSelection(480) // 8m

        XCTAssertEqual(state.draftSeconds, 480)
        XCTAssertEqual(state.quickSelectedPreset, 480)
        // Derived Fine reflects the Quick change instantly — no swap needed.
        XCTAssertEqual(state.fineHours, 0)
        XCTAssertEqual(state.fineMinutes, 8)
        XCTAssertEqual(state.fineSeconds, 0)
    }

    func testQuickSelectionDerivedFineForCompoundValue() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyQuickSelection(7200) // 2h
        XCTAssertEqual(state.fineHours, 2)
        XCTAssertEqual(state.fineMinutes, 0)
        XCTAssertEqual(state.fineSeconds, 0)
    }

    // MARK: - Fine change → draft + derived Quick anchor

    /// Required: a Fine change updates the draft seconds immediately.
    func testFineSelectionUpdatesDraftImmediately() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.setActiveMode(.fine)

        state.applyFineSelection(hours: 0, minutes: 1, seconds: 5)

        XCTAssertEqual(state.draftSeconds, 65)
        XCTAssertNil(state.quickSelectedPreset, "Fine edits clear any Quick highlight")
        // Quick anchor parks on the nearest preset to the new draft.
        XCTAssertEqual(state.quickWheelAnchor(in: presets), 60,
                       "65s → nearest preset 60 (vs 120)")
    }

    // MARK: - Stale emit does not overwrite the other mode

    /// Required: while Fine is active, a stale Quick emit (a Quick wheel
    /// still settling after the user swiped away) must not overwrite the
    /// Fine value.
    func testStaleQuickEmitDoesNotOverwriteFine() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.setActiveMode(.fine)
        state.applyFineSelection(hours: 0, minutes: 1, seconds: 5) // 65s
        XCTAssertEqual(state.draftSeconds, 65)

        // Late Quick wheel emit arriving after the swap to Fine.
        state.applyQuickSelection(480)

        XCTAssertEqual(state.draftSeconds, 65,
                       "Quick emit while Fine is active is dropped in the model")
        XCTAssertEqual(state.activeMode, .fine)
        XCTAssertNil(state.quickSelectedPreset)
    }

    /// Symmetric: while Quick is active, a stale Fine emit must not
    /// overwrite the Quick value.
    func testStaleFineEmitDoesNotOverwriteQuick() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        XCTAssertEqual(state.activeMode, .quick)
        state.applyQuickSelection(120)
        XCTAssertEqual(state.draftSeconds, 120)

        // Late Fine wheel emit arriving after the swap to Quick.
        state.applyFineSelection(hours: 0, minutes: 5, seconds: 0)

        XCTAssertEqual(state.draftSeconds, 120,
                       "Fine emit while Quick is active is dropped in the model")
        XCTAssertEqual(state.activeMode, .quick)
        XCTAssertEqual(state.quickSelectedPreset, 120)
    }

    // MARK: - Mode transitions preserve the draft

    /// Required: Quick → Fine carries the current draft into the h/m/s
    /// wheels with no loss.
    func testQuickToFineCarriesDraftIntoFineWheels() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyQuickSelection(240) // 4m

        state.setActiveMode(.fine)

        XCTAssertEqual(state.draftSeconds, 240, "Draft preserved across the swap")
        XCTAssertEqual(state.fineHours, 0)
        XCTAssertEqual(state.fineMinutes, 4)
        XCTAssertEqual(state.fineSeconds, 0)
        XCTAssertNil(state.quickSelectedPreset, "Entering Fine clears the Quick highlight")
    }

    /// Required: Fine → Quick reflects the current draft per policy
    /// (anchor on nearest preset, no auto-select).
    func testFineToQuickParksAnchorOnNearestPresetWithoutAutoSelect() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.setActiveMode(.fine)
        state.applyFineSelection(hours: 0, minutes: 6, seconds: 30) // 390s

        state.setActiveMode(.quick)

        XCTAssertEqual(state.draftSeconds, 390, "Draft preserved across the swap")
        XCTAssertEqual(state.quickWheelAnchor(in: presets), 480,
                       "390s → nearest preset 480/8m (vs 240, distance 90 vs 150)")
        XCTAssertNil(state.quickSelectedPreset, "Returning to Quick must not auto-select")
    }

    func testModeTransitionsPreserveCustomDraft() {
        var state = TargetShutterInputState.initial(seedSeconds: 65, quickPresets: presets)
        XCTAssertEqual(state.activeMode, .fine, "Custom seed opens in Fine")

        state.setActiveMode(.quick)
        XCTAssertEqual(state.draftSeconds, 65)
        state.setActiveMode(.fine)
        XCTAssertEqual(state.draftSeconds, 65)
        XCTAssertEqual(state.fineSeconds, 5)
    }

    // MARK: - Initial seed / mode selection / slot isolation

    func testInitialModeIsQuickWhenSeedMatchesPreset() {
        let state = TargetShutterInputState.initial(seedSeconds: 7200, quickPresets: presets)
        XCTAssertEqual(state.activeMode, .quick)
        XCTAssertEqual(state.draftSeconds, 7200)
    }

    func testInitialModeIsFineForCustomSeed() {
        let state = TargetShutterInputState.initial(
            seedSeconds: 2 * 3600 + 9 * 60,
            quickPresets: presets
        )
        XCTAssertEqual(state.activeMode, .fine)
        XCTAssertEqual(state.fineHours, 2)
        XCTAssertEqual(state.fineMinutes, 9)
    }

    /// Required (slot-isolation): a nil seed (no committed target for
    /// this slot) falls back to the default — it must not leak another
    /// slot's value. The caller (sheet wrapper) passes nil for slots
    /// with no committed target.
    func testNilSeedFallsBackToDefaultForSlotIsolation() {
        let state = TargetShutterInputState.initial(seedSeconds: nil, quickPresets: presets)
        XCTAssertEqual(state.draftSeconds, TargetShutterInputState.defaultSeedSeconds)
    }

    func testInitialSanitizesInvalidSeed() {
        XCTAssertEqual(TargetShutterInputState.initial(seedSeconds: .nan, quickPresets: presets).draftSeconds, 60)
        XCTAssertEqual(TargetShutterInputState.initial(seedSeconds: -10, quickPresets: presets).draftSeconds, 60)
        XCTAssertEqual(TargetShutterInputState.initial(seedSeconds: 0, quickPresets: presets).draftSeconds, 60)
    }

    func testInitialClampsHugeSeedToMaximum() {
        let state = TargetShutterInputState.initial(seedSeconds: 999_999, quickPresets: presets)
        XCTAssertEqual(state.draftSeconds, TargetShutterInputState.maxTotalSeconds)
        XCTAssertEqual(state.fineHours, 23)
        XCTAssertEqual(state.fineMinutes, 59)
        XCTAssertEqual(state.fineSeconds, 59)
    }

    func testInitialEnabledFalseOpensOffWithSeedPreserved() {
        let state = TargetShutterInputState.initial(
            seedSeconds: 8 * 3600,
            quickPresets: presets,
            initialEnabled: false
        )
        XCTAssertTrue(state.isDraftCleared)
        XCTAssertEqual(state.draftSeconds, 8 * 3600, "Off preserves the seed as dimmed context")
    }

    // MARK: - Off / clear and re-arm parity

    /// Required: Off (clear) preserves the underlying draft and only
    /// flips the flag + clears the highlight.
    func testClearPreservesDraftAndFlagsOff() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyQuickSelection(120)

        state.clearDraft()

        XCTAssertTrue(state.isDraftCleared)
        XCTAssertEqual(state.draftSeconds, 120, "Clear preserves the draft for a snap-free re-arm")
        XCTAssertNil(state.quickSelectedPreset)
    }

    /// Required: while Off, wheel emits are ignored (no silent re-arm).
    func testWheelEmitsIgnoredWhileOff() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyQuickSelection(120)
        state.clearDraft()

        state.applyQuickSelection(480)
        state.setActiveMode(.fine)
        state.applyFineSelection(hours: 5, minutes: 0, seconds: 0)

        XCTAssertTrue(state.isDraftCleared, "Off must not auto-re-enable from wheel input")
        XCTAssertEqual(state.draftSeconds, 120, "Off must not mutate the draft")
    }

    func testReArmRestoresPreservedDraft() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyQuickSelection(240)
        state.clearDraft()

        state.reArmDraft(seedSeconds: 240)

        XCTAssertFalse(state.isDraftCleared)
        XCTAssertEqual(state.draftSeconds, 240, "Toggling On restores the preserved draft, no re-seed")
    }

    func testReArmSeedsFromSeedWhenDraftIsZero() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.setActiveMode(.fine)
        state.applyFineSelection(hours: 0, minutes: 0, seconds: 0) // draft 0
        state.clearDraft()
        XCTAssertEqual(state.draftSeconds, 0)

        state.reArmDraft(seedSeconds: 480)

        XCTAssertFalse(state.isDraftCleared)
        XCTAssertEqual(state.draftSeconds, 480)
        XCTAssertEqual(state.fineMinutes, 8)
    }

    func testClearedFlagSurvivesModeTransitions() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.clearDraft()

        state.setActiveMode(.fine)
        XCTAssertTrue(state.isDraftCleared, "Clear survives swapping to Fine")
        state.setActiveMode(.quick)
        XCTAssertTrue(state.isDraftCleared, "Clear survives swapping back to Quick")
    }

    // MARK: - Confirm value + custom marker

    /// Required: Confirm commits exactly the current `draftSeconds`
    /// after a sequence of edits.
    func testDraftSecondsIsTheCommittedValueAfterEdits() {
        var state = TargetShutterInputState.initial(seedSeconds: nil, quickPresets: presets)
        state.applyQuickSelection(120)
        state.setActiveMode(.fine)
        state.applyFineSelection(hours: 0, minutes: 3, seconds: 15)

        // `draftSeconds` is what the sheet's Confirm passes to onSet.
        XCTAssertEqual(state.draftSeconds, 195)
        XCTAssertEqual(state.totalSeconds, 195)
    }

    func testQuickIsExactMatchTracksDraft() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        XCTAssertTrue(state.quickIsExactMatch(in: presets))

        state.setActiveMode(.fine)
        state.applyFineSelection(hours: 0, minutes: 1, seconds: 5)
        XCTAssertFalse(state.quickIsExactMatch(in: presets))
    }
}
