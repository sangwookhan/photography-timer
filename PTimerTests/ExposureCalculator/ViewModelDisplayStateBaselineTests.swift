import XCTest
@testable import PTimer

/// Display-state baseline tests for the cross-cutting orchestration
/// surface that the legacy `ExposureCalculatorViewModel` facade
/// exposes (per B1 PR6 carry-forward). Each scenario drives the
/// ViewModel through user-flow inputs that pull simultaneously from
/// `CalculatorModel`, `ReciprocityModel`, `FilmSelectionModel`, and
/// `TimerWorkspaceModel`, then dumps the published surface as a
/// committed text baseline.
///
/// These complement `RecordReplayBaselineSmokeTests` (which captures
/// the persistence + lock-screen + notification side-effect trace)
/// and the policy-level `DisplayStateSnapshotTests` (which lock pure
/// reciprocity results and confidence presentation). Together they
/// fence-post the B1 invariant that the four-model decomposition
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

    /// Tri-X 400 selected with metered=1/4s, ND 0. Locks the film
    /// workflow's full cross-cutting surface for an exact-table-point
    /// reciprocity scenario.
    func testFilmModeTriXExactTablePointBaseline() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        viewModel.selectPresetFilm(film)

        // Tri-X 1s entry → corrected 2s. baseShutter set to 1s.
        viewModel.baseShutter = 1.0
        viewModel.ndStop = 0

        DisplayStateSnapshot.assert(
            ViewModelCrossCuttingDump(viewModel: viewModel),
            named: "film-mode-trix-exact-table"
        )
    }

    /// Tri-X with ND applied — corrected exposure derived from the
    /// adjusted shutter, not the metered base. Locks the ND × film
    /// composition path.
    func testFilmModeTriXWithNDStopBaseline() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" }
        )
        viewModel.selectPresetFilm(film)

        // baseShutter 1/30 + ND 6 → adjusted ~ 2s; reciprocity table
        // covers this with an interpolated/extrapolated quantified
        // result depending on dataset.
        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6

        DisplayStateSnapshot.assert(
            ViewModelCrossCuttingDump(viewModel: viewModel),
            named: "film-mode-trix-nd-6-stops"
        )
    }

    /// Portra 400 advisory-only profile — locks the non-quantified
    /// branch where `correctedExposure` carries an advisory message
    /// rather than a numeric value.
    func testFilmModePortraAdvisoryBaseline() throws {
        let viewModel = makeViewModel()
        let film = try XCTUnwrap(
            viewModel.availablePresetFilms.first { $0.canonicalStockName == "Portra 400" }
        )
        viewModel.selectPresetFilm(film)

        viewModel.baseShutter = 4.0
        viewModel.ndStop = 0

        DisplayStateSnapshot.assert(
            ViewModelCrossCuttingDump(viewModel: viewModel),
            named: "film-mode-portra-advisory"
        )
    }

    // MARK: - Helpers

    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 3600,
                dateProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
            )
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
