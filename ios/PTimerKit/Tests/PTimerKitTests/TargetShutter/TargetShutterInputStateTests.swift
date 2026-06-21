// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

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

    // MARK: - C8h5: live wheel telemetry

    /// Active Quick live telemetry updates the displayed (readout) value but
    /// deliberately leaves the committed draft and the picker anchor still,
    /// so the spinning wheel keeps its momentum.
    func testActiveQuickLiveTelemetryUpdatesDisplayNotDraft() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        let anchorBefore = state.quickWheelAnchor(in: presets)

        state.applyLiveQuick(480)

        XCTAssertEqual(state.displaySeconds, 480, "Readout follows the live wheel value")
        XCTAssertEqual(state.draftSeconds, 60, "Committed draft stays put mid-spin")
        XCTAssertEqual(state.quickWheelAnchor(in: presets), anchorBefore,
                       "Picker anchor stays put mid-spin (momentum preserved)")
    }

    /// Active Fine live telemetry updates the displayed value only.
    func testActiveFineLiveTelemetryUpdatesDisplayNotDraft() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.setActiveMode(.fine)

        state.applyLiveFine(hours: 1, minutes: 30, seconds: 15)

        XCTAssertEqual(state.displaySeconds, 1 * 3600 + 30 * 60 + 15)
        XCTAssertEqual(state.draftSeconds, 60, "Committed draft stays put mid-spin")
    }

    /// A settled selection supersedes and clears the live value.
    func testSettleClearsLiveValue() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyLiveQuick(480)
        XCTAssertEqual(state.liveDraftSeconds, 480)

        state.applyQuickSelection(900) // settle
        XCTAssertNil(state.liveDraftSeconds, "Settle clears the transient live value")
        XCTAssertEqual(state.draftSeconds, 900)
        XCTAssertEqual(state.displaySeconds, 900)
    }

    /// Inactive Quick live telemetry (a stale emit after switching to Fine)
    /// is ignored — it must not touch the draft or the displayed value.
    func testInactiveQuickLiveTelemetryIgnoredAfterSwitchToFine() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.setActiveMode(.fine)
        state.applyFineSelection(hours: 0, minutes: 3, seconds: 0) // 180s

        state.applyLiveQuick(28_800) // stale Quick spin still decelerating

        XCTAssertNil(state.liveDraftSeconds, "Inactive Quick live emit recorded nothing")
        XCTAssertEqual(state.displaySeconds, 180, "Readout unaffected by stale Quick emit")
        XCTAssertEqual(state.draftSeconds, 180)
    }

    /// Symmetric: inactive Fine live telemetry after switching to Quick.
    func testInactiveFineLiveTelemetryIgnoredAfterSwitchToQuick() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyQuickSelection(120)

        state.applyLiveFine(hours: 5, minutes: 0, seconds: 0) // stale Fine spin

        XCTAssertNil(state.liveDraftSeconds)
        XCTAssertEqual(state.displaySeconds, 120)
        XCTAssertEqual(state.draftSeconds, 120)
    }

    /// Cleared / Off state ignores live telemetry (no silent re-arm).
    func testClearedStateIgnoresLiveTelemetry() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.clearDraft()

        state.applyLiveQuick(480)
        state.setActiveMode(.fine)
        state.applyLiveFine(hours: 2, minutes: 0, seconds: 0)

        XCTAssertNil(state.liveDraftSeconds)
        XCTAssertTrue(state.isDraftCleared)
        XCTAssertEqual(state.displaySeconds, 60, "Off ignores live emits; readout shows preserved draft")
    }

    /// Switching mode mid-spin flushes the latest live value into the draft,
    /// so the entering mode opens from the live value, not the old one.
    func testModeSwitchMidSpinFlushesLiveValueIntoDraft() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)

        // Quick fling in progress: live value ahead of the committed draft.
        state.applyLiveQuick(900) // 15m, not yet settled
        XCTAssertEqual(state.draftSeconds, 60)

        state.setActiveMode(.fine) // switch before settle

        XCTAssertEqual(state.draftSeconds, 900, "Latest live value carried into the draft on switch")
        XCTAssertNil(state.liveDraftSeconds)
        XCTAssertEqual(state.fineMinutes, 15, "Fine opens from the flushed live value")
    }

    /// Confirm folds an in-progress live value into the draft so a confirm
    /// tapped before settle commits what the user sees.
    func testCommitLiveIntoDraftUsesLiveValue() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.setActiveMode(.fine)
        state.applyLiveFine(hours: 0, minutes: 3, seconds: 15) // 195s, not settled

        state.commitLiveIntoDraft()

        XCTAssertEqual(state.draftSeconds, 195, "Confirm-time flush commits the live value")
        XCTAssertNil(state.liveDraftSeconds)
    }

    /// C8h6: composing a Fine live update from the *live* other-column values
    /// (`liveFine*`) — the way the sheet wires its columns — keeps both moving
    /// wheels' values present instead of flipping the third reading back to
    /// the settled draft between emits.
    func testConcurrentFineWheelsComposeFromLiveValues() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.setActiveMode(.fine) // draft 60 = 0h 1m 0s

        // Minutes wheel → 5, composed against the live other columns.
        state.applyLiveFine(hours: state.liveFineHours, minutes: 5, seconds: state.liveFineSeconds)
        XCTAssertEqual(state.displaySeconds, 5 * 60)

        // Seconds wheel → 30 must preserve the live 5 minutes, not revert to
        // the settled 1 minute.
        state.applyLiveFine(hours: state.liveFineHours, minutes: state.liveFineMinutes, seconds: 30)
        XCTAssertEqual(state.displaySeconds, 5 * 60 + 30, "Seconds update keeps the live minutes")

        // Minutes wheel → 6 must preserve the live 30 seconds.
        state.applyLiveFine(hours: state.liveFineHours, minutes: 6, seconds: state.liveFineSeconds)
        XCTAssertEqual(state.displaySeconds, 6 * 60 + 30, "Minutes update keeps the live seconds")

        // Committed draft stays put through the whole live sequence.
        XCTAssertEqual(state.draftSeconds, 60)
    }
}
