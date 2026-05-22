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
        3600, 7200, 14_400, 28_800,
    ]

    // MARK: - Initial enabled / Off

    /// Backward-compat with all prior tests: `initialEnabled` defaults
    /// to `true`, so `.initial(seedSeconds:quickPresets:)` opens the
    /// sheet On.
    func testInitialEnabledDefaultsToTrue() {
        let state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        XCTAssertFalse(state.isDraftCleared,
                       "Default initialEnabled is true — sheet opens On")
    }

    /// Tapping the inactive main row signals **edit intent** — the
    /// section view always passes `initialEnabled: true` so the user
    /// lands in a ready-to-edit state. Combined with a `nil` seed
    /// (slot-leak prevention), the state seeds to the default 1
    /// minute and the user can immediately Confirm or adjust.
    func testInactiveEntryOpensReadyToCreateWithDefaultSeed() {
        let state = TargetShutterInputState.initial(
            seedSeconds: nil,
            quickPresets: presets,
            initialEnabled: true
        )

        XCTAssertFalse(state.isDraftCleared,
                       "Sheet opens On when entered from inactive main row — no extra toggle tap needed")
        XCTAssertEqual(state.draftSeconds, TargetShutterInputState.defaultSeedSeconds,
                       "Default 1m seed when no committed target is present (no cross-slot last-used leak)")
        XCTAssertEqual(state.activeMode, .quick,
                       "Default 60s sits on the Quick preset ladder, so the sheet opens in Quick")
    }

    /// When no Target Shutter is committed (no active target), the
    /// caller passes `initialEnabled: false`. The sheet opens Off
    /// while preserving the seeded duration as dimmed context.
    func testInitialEnabledFalseOpensOffWithSeedPreserved() {
        let eightHours: TimeInterval = 8 * 3600
        let state = TargetShutterInputState.initial(
            seedSeconds: eightHours,
            quickPresets: presets,
            initialEnabled: false
        )
        XCTAssertTrue(state.isDraftCleared,
                      "initialEnabled=false opens the sheet Off")
        XCTAssertEqual(state.draftSeconds, Int(eightHours),
                       "Seeded duration is preserved as Off-state dimmed context (not zeroed)")
    }

    /// Off with no seed falls back to the default seed so toggling
    /// the switch On lands on a sensible value (no `0s` flash).
    func testInitialEnabledFalseWithNilSeedFallsBackToDefault() {
        let state = TargetShutterInputState.initial(
            seedSeconds: nil,
            quickPresets: presets,
            initialEnabled: false
        )
        XCTAssertTrue(state.isDraftCleared)
        XCTAssertEqual(state.draftSeconds, TargetShutterInputState.defaultSeedSeconds)
    }

    // MARK: - Initial Quick/Fine mode based on preset match

    /// Seed that exactly matches a Quick preset opens the sheet in
    /// Quick mode — the user lands on the matching wheel position
    /// directly.
    func testInitialModeIsQuickWhenSeedMatchesPreset() {
        let twoHours = TargetShutterInputState.initial(seedSeconds: 7200, quickPresets: presets)
        XCTAssertEqual(twoHours.activeMode, .quick)

        let eightHours = TargetShutterInputState.initial(seedSeconds: 8 * 3600, quickPresets: presets)
        XCTAssertEqual(eightHours.activeMode, .quick)
    }

    /// Custom duration (off the Quick ladder) opens the sheet in Fine
    /// Tune so the user is dropped into the wheels that can express
    /// the value.
    func testInitialModeIsFineWhenSeedDoesNotMatchPreset() {
        let custom = TargetShutterInputState.initial(
            seedSeconds: 2 * 3600 + 9 * 60,
            quickPresets: presets
        )
        XCTAssertEqual(custom.activeMode, .fine,
                       "Custom durations not on the Quick ladder open in Fine Tune")

        let alsoCustom = TargetShutterInputState.initial(
            seedSeconds: 13 * 3600 + 2 * 60,
            quickPresets: presets
        )
        XCTAssertEqual(alsoCustom.activeMode, .fine)
    }

    /// Off + custom duration still respects the preset-match rule for
    /// the underlying mode (controls are dimmed regardless, but the
    /// derived mode pre-positions the wheels for when the user toggles
    /// back On).
    func testInitialModeRespectsPresetMatchEvenWhenInitialEnabledFalse() {
        let custom = TargetShutterInputState.initial(
            seedSeconds: 2 * 3600 + 9 * 60,
            quickPresets: presets,
            initialEnabled: false
        )
        XCTAssertEqual(custom.activeMode, .fine)
        XCTAssertTrue(custom.isDraftCleared)
    }

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

        // Mode transition is what flips `activeMode` to `.fine`;
        // `applyFineChange` itself no longer touches `activeMode` so a
        // stale Fine emit arriving after the user swiped to Quick
        // cannot yank the sheet back to Fine.
        state.setActiveMode(.fine, quickPresets: presets)
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

        // The user swipes to Fine before scrolling — the mode
        // transition is what flips `activeMode`. The continuous-row
        // emits below simulate Fine wheel scroll while the page is
        // active.
        state.setActiveMode(.fine, quickPresets: presets)

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

    // MARK: - activeMode is mutated only by mode transitions

    /// Pins the new contract that value-entering mutators do not
    /// touch `activeMode`. Without this, a late Quick observer emit
    /// arriving after the user already swiped to Fine would yank the
    /// sheet back to Quick.
    func testApplyQuickTapDoesNotChangeActiveMode() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.setActiveMode(.fine, quickPresets: presets)
        XCTAssertEqual(state.activeMode, .fine)

        // Simulate a stale Quick wheel emit arriving after the user
        // already moved to Fine.
        state.applyQuickTap(240)

        XCTAssertEqual(state.activeMode, .fine,
                       "applyQuickTap must not yank activeMode back to .quick — only setActiveMode does")
    }

    /// Symmetric pin for `applyFineChange`: simulates a stale Fine
    /// wheel emit arriving after the user already moved to Quick.
    func testApplyFineChangeDoesNotChangeActiveMode() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        XCTAssertEqual(state.activeMode, .quick)

        state.applyFineChange(hours: 0, minutes: 2, seconds: 0)

        XCTAssertEqual(state.activeMode, .quick,
                       "applyFineChange must not yank activeMode back to .fine — only setActiveMode does")
    }

    // MARK: - Clear draft

    /// Toggle Off (clearDraft) sets the cleared flag while preserving
    /// `draftSeconds`, `quickWheelAnchor`, and the fine fields so
    /// toggling back On restores the previous draft without a snap.
    /// `quickSelectedPreset` clears because the Quick wheel no
    /// longer represents a committed selection.
    func testClearDraftSetsFlagAndPreservesUnderlyingDraft() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyQuickTap(120)
        XCTAssertFalse(state.isDraftCleared)
        XCTAssertEqual(state.draftSeconds, 120)
        XCTAssertEqual(state.quickSelectedPreset, 120)

        state.clearDraft()

        XCTAssertTrue(state.isDraftCleared)
        XCTAssertEqual(state.draftSeconds, 120,
                       "Clear preserves draftSeconds so toggling back On restores the previous value without a snap")
        XCTAssertNil(state.quickSelectedPreset)
    }

    /// Clear must not snap the wheels — the user should see the same
    /// physical wheel positions they had a moment ago, just with
    /// `None` as the draft readout.
    func testClearDraftPreservesWheelAnchorAndFineFields() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyQuickTap(240)
        state.setActiveMode(.fine, quickPresets: presets)
        state.applyFineChange(hours: 1, minutes: 0, seconds: 0)
        let preservedAnchor = state.quickWheelAnchor
        let preservedH = state.fineHours
        let preservedM = state.fineMinutes
        let preservedS = state.fineSeconds

        state.clearDraft()

        XCTAssertEqual(state.quickWheelAnchor, preservedAnchor)
        XCTAssertEqual(state.fineHours, preservedH)
        XCTAssertEqual(state.fineMinutes, preservedM)
        XCTAssertEqual(state.fineSeconds, preservedS)
    }

    // MARK: - Toggle Off / Toggle On round-trip

    /// Toggling On after Off (via the sheet header switch) restores
    /// the preserved draft when one exists.
    func testReArmDraftRestoresPreservedDraftWhenPositive() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyQuickTap(240)
        state.clearDraft()
        XCTAssertTrue(state.isDraftCleared)
        XCTAssertEqual(state.draftSeconds, 240)

        state.reArmDraft(seedSeconds: 240, quickPresets: presets)

        XCTAssertFalse(state.isDraftCleared)
        XCTAssertEqual(state.draftSeconds, 240,
                       "Toggling back On restores the previous draft without re-seeding")
    }

    /// When the preserved draft is zero (edge case — user fine-rolled
    /// to 0/0/0 then toggled Off), Toggle On falls back to seeding
    /// from `seedSeconds`.
    func testReArmDraftSeedsFromSeedSecondsWhenDraftIsZero() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.setActiveMode(.fine, quickPresets: presets)
        state.applyFineChange(hours: 0, minutes: 0, seconds: 0)
        state.clearDraft()
        XCTAssertTrue(state.isDraftCleared)
        XCTAssertEqual(state.draftSeconds, 0)

        state.reArmDraft(seedSeconds: 480, quickPresets: presets)

        XCTAssertFalse(state.isDraftCleared)
        XCTAssertEqual(state.draftSeconds, 480)
        XCTAssertEqual(state.fineHours, 0)
        XCTAssertEqual(state.fineMinutes, 8)
        XCTAssertEqual(state.fineSeconds, 0)
        XCTAssertEqual(state.quickWheelAnchor, 480,
                       "Quick anchor re-parks on the nearest preset to the seeded value")
    }

    /// When neither the preserved draft nor `seedSeconds` is valid,
    /// `reArmDraft` falls back to the default seed (1 minute).
    func testReArmDraftFallsBackToDefaultWhenNoSeed() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.setActiveMode(.fine, quickPresets: presets)
        state.applyFineChange(hours: 0, minutes: 0, seconds: 0)
        state.clearDraft()

        state.reArmDraft(seedSeconds: nil, quickPresets: presets)

        XCTAssertFalse(state.isDraftCleared)
        XCTAssertEqual(state.draftSeconds, TargetShutterInputState.defaultSeedSeconds)
    }

    // MARK: - Continuous-scroll variants preserve wheel momentum

    /// Continuous-scroll mid-flick Quick observer must not write
    /// back to `quickWheelAnchor`. Writing the anchor mid-deceleration
    /// triggers SwiftUI to call `UIPickerView.selectRow(_:animated:)`
    /// and kills momentum.
    func testApplyQuickContinuousScrollDoesNotTouchWheelAnchor() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyQuickTap(60)
        let originalAnchor = state.quickWheelAnchor
        XCTAssertEqual(originalAnchor, 60)

        state.applyQuickContinuousScroll(480)

        XCTAssertEqual(state.draftSeconds, 480,
                       "Mid-scroll observer must update the draft readout")
        XCTAssertEqual(state.quickSelectedPreset, 480,
                       "Mid-scroll observer must update the visual selection highlight")
        XCTAssertEqual(state.quickWheelAnchor, originalAnchor,
                       "Mid-scroll observer must NOT write the wheel anchor — that would interrupt UIPickerView deceleration")
        XCTAssertFalse(state.isDraftCleared)
    }

    /// Symmetric pin for Fine: mid-scroll observer must not write
    /// the per-column fine fields, which the column Picker bindings
    /// read.
    func testApplyFineContinuousScrollDoesNotTouchFineFields() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.setActiveMode(.fine, quickPresets: presets)
        let originalH = state.fineHours
        let originalM = state.fineMinutes
        let originalS = state.fineSeconds

        state.applyFineContinuousScroll(hours: 1, minutes: 30, seconds: 15)

        XCTAssertEqual(state.draftSeconds, 1 * 3600 + 30 * 60 + 15,
                       "Mid-scroll observer must update the draft readout from the new wheel row")
        XCTAssertEqual(state.fineHours, originalH,
                       "Mid-scroll observer must NOT write fineHours — would kill momentum")
        XCTAssertEqual(state.fineMinutes, originalM)
        XCTAssertEqual(state.fineSeconds, originalS)
        XCTAssertFalse(state.isDraftCleared)
    }

    // MARK: - Off state ignores wheel input

    /// Toggle Off is the only path that disables Target Shutter; the
    /// toggle On is the only path that re-enables it. Wheel emits
    /// arriving while Off must NOT silently re-arm the draft — that
    /// would mean a stale observer pulse fired after the user
    /// flipped the switch Off could resurrect the target without
    /// the user touching the switch again.
    func testApplyQuickTapIgnoredWhenOff() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyQuickTap(60)
        state.clearDraft()
        let preservedDraft = state.draftSeconds
        let preservedAnchor = state.quickWheelAnchor
        XCTAssertTrue(state.isDraftCleared)

        state.applyQuickTap(480)

        XCTAssertTrue(state.isDraftCleared, "Off state must not auto-re-enable on Quick tap")
        XCTAssertEqual(state.draftSeconds, preservedDraft, "Off state must not mutate the draft")
        XCTAssertEqual(state.quickWheelAnchor, preservedAnchor, "Off state must not mutate the wheel anchor")
    }

    /// Symmetric pin for Fine.
    func testApplyFineChangeIgnoredWhenOff() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.setActiveMode(.fine, quickPresets: presets)
        state.applyFineChange(hours: 0, minutes: 1, seconds: 30)
        state.clearDraft()
        let preservedDraft = state.draftSeconds
        let preservedH = state.fineHours
        let preservedM = state.fineMinutes
        let preservedS = state.fineSeconds
        XCTAssertTrue(state.isDraftCleared)

        state.applyFineChange(hours: 0, minutes: 5, seconds: 0)

        XCTAssertTrue(state.isDraftCleared, "Off state must not auto-re-enable on Fine change")
        XCTAssertEqual(state.draftSeconds, preservedDraft)
        XCTAssertEqual(state.fineHours, preservedH)
        XCTAssertEqual(state.fineMinutes, preservedM)
        XCTAssertEqual(state.fineSeconds, preservedS)
    }

    /// Same contract for mid-scroll Quick observer pulses arriving
    /// after the user flipped the switch Off mid-deceleration.
    func testApplyQuickContinuousScrollIgnoredWhenOff() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyQuickTap(60)
        state.clearDraft()
        let preservedDraft = state.draftSeconds
        let preservedSelected = state.quickSelectedPreset
        XCTAssertTrue(state.isDraftCleared)

        state.applyQuickContinuousScroll(480)

        XCTAssertTrue(state.isDraftCleared)
        XCTAssertEqual(state.draftSeconds, preservedDraft)
        XCTAssertEqual(state.quickSelectedPreset, preservedSelected)
    }

    /// Symmetric pin for mid-scroll Fine observer pulses.
    func testApplyFineContinuousScrollIgnoredWhenOff() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.setActiveMode(.fine, quickPresets: presets)
        state.applyFineChange(hours: 0, minutes: 2, seconds: 0)
        state.clearDraft()
        let preservedDraft = state.draftSeconds

        state.applyFineContinuousScroll(hours: 1, minutes: 0, seconds: 0)

        XCTAssertTrue(state.isDraftCleared)
        XCTAssertEqual(state.draftSeconds, preservedDraft)
    }

    /// `reArmDraft` is the explicit re-enable path — the only way to
    /// leave Off without a fresh sheet open. After it runs, the
    /// `applyXxx` mutators are usable again.
    func testReArmDraftIsExplicitReEnablePath() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.applyQuickTap(120)
        state.clearDraft()
        XCTAssertTrue(state.isDraftCleared)

        // Wheel input is still ignored while Off.
        state.applyQuickTap(480)
        XCTAssertTrue(state.isDraftCleared)
        XCTAssertEqual(state.draftSeconds, 120)

        // Toggle On via reArmDraft — now the wheel input is honoured.
        state.reArmDraft(seedSeconds: nil, quickPresets: presets)
        XCTAssertFalse(state.isDraftCleared)

        state.applyQuickTap(480)
        XCTAssertEqual(state.draftSeconds, 480)
        XCTAssertEqual(state.quickWheelAnchor, 480)
    }

    /// The cleared flag survives mode transitions — the user can
    /// clear in Fine, swipe to Quick, and still see `None` until
    /// they actually pick a value. With `clearDraft` now preserving
    /// `draftSeconds`, `setActiveMode(.fine)` rebuilds fine fields
    /// from that preserved value (60s here) rather than zero.
    func testSetActiveModeAfterClearPreservesClearedFlag() {
        var state = TargetShutterInputState.initial(seedSeconds: 60, quickPresets: presets)
        state.clearDraft()
        XCTAssertTrue(state.isDraftCleared)

        state.setActiveMode(.fine, quickPresets: presets)

        XCTAssertTrue(state.isDraftCleared,
                      "Mode transition after Clear must keep the cleared flag — user is still in the cleared draft session")
        XCTAssertEqual(state.fineHours, 0)
        XCTAssertEqual(state.fineMinutes, 1)
        XCTAssertEqual(state.fineSeconds, 0,
                       "Fine fields rebuild from the preserved draftSeconds (60s here), not from zero")

        state.setActiveMode(.quick, quickPresets: presets)
        XCTAssertTrue(state.isDraftCleared,
                      "Swiping back to Quick after Clear also preserves the flag")
    }
}
