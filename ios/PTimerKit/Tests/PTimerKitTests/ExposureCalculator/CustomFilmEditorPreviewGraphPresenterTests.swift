import XCTest
import PTimerKit
import PTimerCore

/// Editor preview graph unification.
///
/// The editor's Preview graph routes a synthesized binding state
/// through `FilmModeDetailsGraphPresenter`, so identical formula
/// parameters must produce a display state whose axis labels,
/// viewport range, tick policy, no-correction band, source-range
/// boundary, and formula title all match the runtime Reciprocity
/// Details graph.
@MainActor
final class CustomFilmEditorPreviewGraphTests: XCTestCase {

    func test_axisLabelsAndTitle_matchDetailsGraphPresenter() {
        let state = CustomFilmEditorPreviewGraphPresenter.graphDisplayState(
            for: makeValidForm()
        )
        XCTAssertEqual(state?.xAxisLabel, "Adjusted shutter")
        XCTAssertEqual(state?.yAxisLabel, "Corrected exposure")
        XCTAssertEqual(state?.title, "Reciprocity Graph")
    }

    func test_graphHeader_suppressesFormulaText_forCustomAndAnchoredForms() {
        // Custom power-law path
        do {
            let form = makeValidForm(exponent: "1.30")
            let state = CustomFilmEditorPreviewGraphPresenter.graphDisplayState(for: form)
            XCTAssertNotNil(state, "Editor preview must still produce a graph state.")
            XCTAssertNil(
                state?.formulaDisplayText,
                "Custom-path graph state must drop the in-header formula text so the shared Calculation Basis block is the single source."
            )
        }
        // Anchored formula path
        do {
            let form = makeValidForm(
                exponent: "1.0966",
                baseTm: "0.1",
                baseTc: "0.1",
                offset: "0",
                validThrough: "240"
            )
            let state = CustomFilmEditorPreviewGraphPresenter.graphDisplayState(for: form)
            XCTAssertNil(state?.formulaDisplayText)
        }
    }

    // MARK: - Viewport range matches Details

    /// The Details graph extends the viewport one decade below 1 s
    /// so the no-correction band always reads with visible width.
    /// The editor preview must inherit the same lower bound.
    func test_viewportRange_extendsBelowOneSecond() throws {
        let state = try XCTUnwrap(
            CustomFilmEditorPreviewGraphPresenter.graphDisplayState(for: makeValidForm())
        )
        XCTAssertEqual(state.xRange.lowerBound, 0.01, accuracy: 1e-9)
        XCTAssertEqual(state.yRange.lowerBound, 0.01, accuracy: 1e-9)
    }

    // MARK: - Tick policy matches Details

    /// When the viewport extends below 1 s, the Details presenter
    /// prepends sub-second ticks ("1/100s", "1/10s") to the tier's
    /// tick set. The editor preview inherits the same set.
    func test_axisTicks_includeSubSecondLabels() {
        let state = CustomFilmEditorPreviewGraphPresenter.graphDisplayState(
            for: makeValidForm()
        )
        let labels = state?.xAxisTicks.map(\.label) ?? []
        XCTAssertTrue(labels.contains("1/10s"))
        XCTAssertTrue(labels.contains("1s"))
    }

    // MARK: - No-correction band

    func test_noCorrectionThrough_drivesGreenBandUpperBound() {
        let form = makeValidForm(noCorrection: "2", validThrough: "240")
        let state = CustomFilmEditorPreviewGraphPresenter.graphDisplayState(for: form)
        XCTAssertEqual(state?.noCorrectionRangeUpperBoundSeconds, 2)
    }

    // MARK: - Boundary semantics

    /// Finite `validThrough` → the formula upper bound is the
    /// supported-range cap, and the not-recommended boundary
    /// (the red dashed line) is absent because there is no
    /// manufacturer-published "not recommended" anchor on a
    /// user-defined profile.
    func test_finiteValidThrough_setsSupportedUpperBound() {
        let form = makeValidForm(validThrough: "240")
        let state = CustomFilmEditorPreviewGraphPresenter.graphDisplayState(for: form)
        XCTAssertEqual(state?.supportedRangeUpperBoundSeconds, 240)
    }

    /// `Unlimited` (empty validThrough) leaves both the supported
    /// upper bound and the not-recommended boundary off so the
    /// formula curve extends to the viewport edge.
    func test_unlimitedValidThrough_noBoundaryOrUpperBound() {
        let form = makeValidForm(validThrough: "")
        let state = CustomFilmEditorPreviewGraphPresenter.graphDisplayState(for: form)
        XCTAssertNil(state?.supportedRangeUpperBoundSeconds)
        XCTAssertNil(state?.notRecommendedBoundarySeconds)
    }

    // MARK: - Curve sampling matches Details

    /// The Details curve sampler emits an identity segment in the
    /// no-correction zone (Tc = Tm) joined to the formula segment
    /// past the threshold. The editor preview inherits the same
    /// segments because it routes through the same sampler.
    func test_curveSampling_includesIdentitySegmentBelowThreshold() {
        let form = makeValidForm(noCorrection: "1", validThrough: "240")
        let state = CustomFilmEditorPreviewGraphPresenter.graphDisplayState(for: form)
        let identitySamples = state?.sourcePoints.filter {
            abs($0.meteredExposureSeconds - $0.correctedExposureSeconds) < 1e-6
                && $0.meteredExposureSeconds < 1.0
        } ?? []
        XCTAssertFalse(
            identitySamples.isEmpty,
            "Curve must include identity (Tc=Tm) samples inside the no-correction zone."
        )
    }

    /// The text the graph header used to render is still available
    /// on the shared Calculation Basis presenter — the relocation
    /// must not lose the wording, only move it to a single spot.
    func test_calculationBasis_carriesSameWordingAsTheLegacyGraphHeader() {
        let form = makeValidForm(
            exponent: "1.0966",
            baseTm: "0.1",
            baseTc: "0.1",
            offset: "0",
            validThrough: "240"
        )
        XCTAssertEqual(
            CalculationBasisPresenter.calculationBasisText(for: form),
            "Tc = 0.1s × (Tm / 0.1s)^1.0966"
        )
    }

    // MARK: - Viewport stability

    /// Same formula → same viewport. The user must be able to
    /// compare two parameter sweeps without auto-zoom shifting the
    /// frame.
    func test_sameFormula_producesSameViewport() {
        let formA = makeValidForm(exponent: "1.30", validThrough: "240")
        let formB = makeValidForm(exponent: "1.30", validThrough: "240")
        let stateA = CustomFilmEditorPreviewGraphPresenter.graphDisplayState(for: formA)
        let stateB = CustomFilmEditorPreviewGraphPresenter.graphDisplayState(for: formB)
        XCTAssertEqual(stateA?.xRange, stateB?.xRange)
        XCTAssertEqual(stateA?.yRange, stateB?.yRange)
        XCTAssertEqual(stateA?.scaleTier, stateB?.scaleTier)
    }

    // MARK: - Parse failure

    func test_unparseableForm_returnsNil() {
        let form = CustomFilmEditorFormState(exponentText: "abc")
        XCTAssertNil(CustomFilmEditorPreviewGraphPresenter.graphDisplayState(for: form))
    }

    // MARK: - Parity with runtime Details for the same parameters

    /// End-to-end parity check: a saved custom profile must produce
    /// the same graph display state (sourcePoints, axes, ranges,
    /// boundaries, formula text) on both the editor preview and the
    /// runtime Details surface for the documented manual-verification
    /// scenario (Kodak Myfilm · ISO 25 · 1 / 1.41 / 1.33 / 1 / 1 / Unlimited).
    func test_editorPreview_matchesRuntimeDetailsForSameParameters() {
        let form = makeValidForm(
            exponent: "1.33",
            baseTm: "1",
            baseTc: "1.41",
            offset: "1",
            noCorrection: "1",
            validThrough: ""
        )
        let editorState = CustomFilmEditorPreviewGraphPresenter.graphDisplayState(for: form)

        // Build the equivalent saved profile via the editor's own
        // FormState pipeline so the parity check uses the runtime
        // production path, not a hand-crafted fixture.
        let formState = CustomFilmEditorFormState(
            filmLabel: "Myfilm",
            isoText: "25",
            exponentText: "1.33",
            baseTmText: "1",
            baseTcText: "1.41",
            offsetSecondsText: "1",
            noCorrectionThroughText: "1",
            validThroughText: "",
            manufacturerText: "Kodak"
        )
        guard case .success(let film) = formState.validate(),
              let profile = film.profiles.first else {
            return XCTFail("Saved-profile pipeline must succeed for the documented scenario")
        }
        let policyResult = ReciprocityCalculationPolicyEvaluator().evaluate(
            profile: profile,
            meteredExposureSeconds: CustomFilmEditorPreviewGraphPresenter.previewMeteredSeconds
        )
        let runtimeState = FilmModeDetailsGraphPresenter().graphDisplayState(
            for: FilmModeDetailsGraphPresenter.Input(
                bindingState: FilmModeReciprocityBindingState(
                    film: film,
                    profile: profile,
                    policyResult: policyResult,
                    presentation: policyResult.confidencePresentation
                ),
                calculationResult: .success(
                    ExposureCalculationResult(
                        baseShutterSeconds: CustomFilmEditorPreviewGraphPresenter.previewMeteredSeconds,
                        ndStep: NDStep(stops: 0),
                        resultShutterSeconds: CustomFilmEditorPreviewGraphPresenter.previewMeteredSeconds
                    )
                ),
                formatDuration: { "\($0)s" }
            )
        )

        XCTAssertEqual(editorState?.xAxisLabel, runtimeState?.xAxisLabel)
        XCTAssertEqual(editorState?.yAxisLabel, runtimeState?.yAxisLabel)
        XCTAssertEqual(editorState?.xRange, runtimeState?.xRange)
        XCTAssertEqual(editorState?.yRange, runtimeState?.yRange)
        XCTAssertEqual(editorState?.scaleTier, runtimeState?.scaleTier)
        XCTAssertEqual(editorState?.noCorrectionRangeUpperBoundSeconds,
                       runtimeState?.noCorrectionRangeUpperBoundSeconds)
        XCTAssertEqual(editorState?.supportedRangeUpperBoundSeconds,
                       runtimeState?.supportedRangeUpperBoundSeconds)
        XCTAssertEqual(editorState?.notRecommendedBoundarySeconds,
                       runtimeState?.notRecommendedBoundarySeconds)
        XCTAssertEqual(editorState?.formulaDisplayText, runtimeState?.formulaDisplayText)
        XCTAssertEqual(editorState?.sourcePoints.count, runtimeState?.sourcePoints.count)
    }

    // MARK: - Helpers

    private func makeValidForm(
        exponent: String = "1.30",
        baseTm: String = "1",
        baseTc: String = "1",
        offset: String = "0",
        noCorrection: String = "1",
        validThrough: String = "240"
    ) -> CustomFilmEditorFormState {
        CustomFilmEditorFormState(
            exponentText: exponent,
            baseTmText: baseTm,
            baseTcText: baseTc,
            offsetSecondsText: offset,
            noCorrectionThroughText: noCorrection,
            validThroughText: validThrough
        )
    }
}
