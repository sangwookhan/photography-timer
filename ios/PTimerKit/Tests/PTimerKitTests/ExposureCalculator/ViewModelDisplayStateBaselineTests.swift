// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// Display-state baseline tests for the cross-cutting orchestration
/// surface that the `ExposureCalculatorViewModel` facade exposes. Each
/// scenario drives the view-model facade through user-flow inputs that
/// pull simultaneously from `CalculatorModel`, `ReciprocityModel`,
/// `FilmSelectionModel`, and `TimerWorkspaceModel`, then dumps the
/// published surface as a committed text baseline.
///
/// These complement `RecordReplayBaselineSmokeTests` (which captures
/// the persistence + lock-screen + notification side-effect trace)
/// and the policy-level `DisplayStateSnapshotTests` (which lock pure
/// reciprocity results and confidence presentation). Together they
/// fence-post the invariant that the four-model decomposition
/// must produce byte-identical user-visible state for the same input.
@MainActor
final class ViewModelDisplayStateBaselineTests: XCTestCase {

    // MARK: - Default state

    /// Fresh ViewModel with no film selected — the digital workflow
    /// entry point. Locks `activeCalculatorContext`,
    /// `filmReciprocityBindingState`, and `filmModeExposureResultState`
    /// to confirm a no-film selection emits the expected null state.
    func testDigitalWorkflowDefaultStateBaseline() {
        let viewModel = makeViewModel()

        DisplayStateSnapshot.assert(
            ViewModelCrossCuttingDump(viewModel: viewModel),
            named: "digital-workflow-default"
        )
    }

    // MARK: - Film mode

    /// Tri-X 400 selected at metered=1s. Tri-X is formula-backed; the
    /// scenario locks the film-workflow cross-cutting surface for a
    /// formula-derived result at the threshold boundary.
    func testFilmModeTableProfileBaseline() throws {
        let viewModel = makeViewModel()
        viewModel.scaleMode = .fullStop
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        viewModel.selectPresetFilm(film)

        viewModel.baseShutter = 1.0
        viewModel.ndStop = 0

        DisplayStateSnapshot.assert(
            ViewModelCrossCuttingDump(viewModel: viewModel),
            named: "film-mode-trix-formula-1s"
        )
    }

    /// Tri-X with ND applied — corrected exposure derived from the
    /// adjusted shutter, not the metered base. Locks the ND × film
    /// composition path through the formula calculation curve.
    func testFilmModeTableProfileWithNDStopBaseline() throws {
        let viewModel = makeViewModel()
        viewModel.scaleMode = .fullStop
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        viewModel.selectPresetFilm(film)

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6

        DisplayStateSnapshot.assert(
            ViewModelCrossCuttingDump(viewModel: viewModel),
            named: "film-mode-trix-nd-6-stops"
        )
    }

    /// Portra 400 limited-guidance profile — locks the non-quantified
    /// branch where `correctedExposure` carries a limited-guidance
    /// message rather than a numeric value.
    func testFilmModeLimitedGuidanceBaseline() throws {
        let viewModel = makeViewModel()
        viewModel.scaleMode = .fullStop
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" }
        )
        viewModel.selectPresetFilm(film)

        viewModel.baseShutter = 4.0
        viewModel.ndStop = 0

        DisplayStateSnapshot.assert(
            ViewModelCrossCuttingDump(viewModel: viewModel),
            named: "film-mode-portra-limited-guidance"
        )
    }

    // MARK: - Helpers

    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging(currentDate: Date(timeIntervalSince1970: 1_700_000_000))
        )
    }
}

/// Snapshot-friendly bundle of the ViewModel cross-cutting surface.
/// `Swift.dump` walks the struct deterministically; volatile fields
/// (`UUID`, absolute `Date`) are excluded so reruns produce identical
/// output without taming the underlying types. Keep this struct
/// stable across PRs — it pins the contract.
private struct ViewModelCrossCuttingDump {
    let activeCalculatorContext: ActiveExposureCalculatorContext
    let isFilmWorkflowActive: Bool
    let canResetFilmModeWorkingContext: Bool
    let filmReciprocityBindingState: FilmModeReciprocityBindingDump?
    let filmModeExposureResultState: FilmModeExposureResultStateDump?
    let canShowFilmDetails: Bool
    let canStartTimer: Bool
    let timersCount: Int

    @MainActor
    init(viewModel: ExposureCalculatorViewModel) {
        self.activeCalculatorContext = viewModel.activeCalculatorContext
        self.isFilmWorkflowActive = viewModel.isFilmWorkflowActive
        self.canResetFilmModeWorkingContext = viewModel.canResetFilmModeWorkingContext
        self.filmReciprocityBindingState = viewModel.filmReciprocityBindingState.map(
            FilmModeReciprocityBindingDump.init
        )
        self.filmModeExposureResultState = viewModel.filmModeExposureResultState.map(
            FilmModeExposureResultStateDump.init
        )
        self.canShowFilmDetails = viewModel.canShowFilmDetails
        self.canStartTimer = viewModel.canStartTimer
        self.timersCount = viewModel.timers.count
    }
}

private struct FilmModeReciprocityBindingDump {
    let filmStockName: String
    let profileAuthority: String
    let policyResultBasis: String
    let correctedExposureSeconds: Double?
    let presentationCategory: String
    let presentationBadgeStyle: String

    init(_ binding: FilmModeReciprocityBindingState) {
        self.filmStockName = binding.film.canonicalStockName
        self.profileAuthority = String(describing: binding.profile.source.authority)
        self.policyResultBasis = String(describing: binding.policyResult.metadata.basis)
        self.correctedExposureSeconds = binding.policyResult.correctedExposureSeconds
        self.presentationCategory = String(describing: binding.presentation.category)
        self.presentationBadgeStyle = String(describing: binding.presentation.badgeStyle)
    }
}

private struct FilmModeExposureResultStateDump {
    let adjustedShutterSeconds: Double
    let reciprocityStateTone: String
    let adjustedShutterCanStart: Bool
    let correctedKind: String
    let correctedSeconds: Double?
    let correctedPrimary: String
    let correctedSecondary: String
    let correctedExposureCanStart: Bool

    init(_ state: FilmModeExposureResultState) {
        self.adjustedShutterSeconds = state.adjustedShutterSeconds
        self.reciprocityStateTone = String(describing: state.reciprocityState.tone)
        self.adjustedShutterCanStart = state.adjustedShutterAction.canStartTimer
        self.correctedKind = String(describing: state.correctedExposure.kind)
        self.correctedSeconds = state.correctedExposure.correctedExposureSeconds
        self.correctedPrimary = state.correctedExposure.primaryText
        self.correctedSecondary = state.correctedExposure.secondaryText
        self.correctedExposureCanStart = state.correctedExposureAction.canStartTimer
    }
}
