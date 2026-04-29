import XCTest
@testable import PTimer

/// PR2 of B1 (`Docs/StructureImprovement/specs/B1-ViewModelDecomposition.md`)
/// — direct unit tests for the newly extracted `ReciprocityModel`.
/// These cover the reciprocity facade in isolation; the legacy
/// `ExposureCalculatorViewModelTests` continue to cover the same
/// behavior end-to-end via the ViewModel surface.
final class ReciprocityModelTests: XCTestCase {

    // MARK: - evaluate

    @MainActor
    func testEvaluateProducesExactResultForTriXTablePoint() {
        let model = ReciprocityModel()
        let profile = ReciprocityPolicyScenarioFactory.triXProfile()

        let result = model.evaluate(
            profile: profile,
            meteredExposureSeconds: 10
        )

        XCTAssertEqual(result.metadata.basis, .exactTablePoint)
        XCTAssertNotNil(result.correctedExposureSeconds)
    }

    @MainActor
    func testEvaluateProducesEstimatedResultForTriXInterpolation() {
        let model = ReciprocityModel()
        let profile = ReciprocityPolicyScenarioFactory.triXProfile()

        let result = model.evaluate(
            profile: profile,
            meteredExposureSeconds: 5
        )

        XCTAssertEqual(result.metadata.basis, .interpolatedWithinTable)
        XCTAssertNotNil(result.correctedExposureSeconds)
    }

    // MARK: - makeDetailsDisplayState

    @MainActor
    func testMakeDetailsDisplayStateProducesNonNilForQuantifiedTriXScenario() {
        let model = ReciprocityModel()
        let profile = ReciprocityPolicyScenarioFactory.triXProfile()
        let film = FilmIdentity(
            id: "tri-x-test",
            kind: .preset,
            canonicalStockName: "Tri-X",
            manufacturer: "Kodak",
            brandLabel: "Tri-X 400",
            aliases: [],
            productionStatus: .current,
            profiles: [profile],
            userMetadata: nil
        )
        let policyResult = model.evaluate(
            profile: profile,
            meteredExposureSeconds: 10
        )
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError> =
            .success(
                ExposureCalculationResult(
                    baseShutterSeconds: 10,
                    stop: 0,
                    resultShutterSeconds: 10
                )
            )

        let displayState = model.makeDetailsDisplayState(
            input: FilmModeDetailsPresenterInput(
                bindingState: bindingState,
                calculationResult: calculationResult,
                filmModeExposureResultState: nil,
                formatDuration: { "\($0)s" },
                formatDurationCoarse: { "\($0)s" },
                formatAxisDuration: { "\($0)s" }
            )
        )

        XCTAssertNotNil(displayState)
        XCTAssertEqual(displayState?.title, "Reciprocity Details")
    }

    // MARK: - reciprocityStateDisplayState

    @MainActor
    func testReciprocityStateDisplayStateForTrustedExactScenario() {
        let model = ReciprocityModel()
        let profile = ReciprocityPolicyScenarioFactory.triXProfile()
        let film = FilmIdentity(
            id: "tri-x-test",
            kind: .preset,
            canonicalStockName: "Tri-X",
            manufacturer: "Kodak",
            brandLabel: "Tri-X 400",
            aliases: [],
            productionStatus: .current,
            profiles: [profile],
            userMetadata: nil
        )
        let policyResult = model.evaluate(
            profile: profile,
            meteredExposureSeconds: 10
        )
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )

        let displayState = model.reciprocityStateDisplayState(for: bindingState)

        XCTAssertEqual(displayState.tone, .trusted)
        XCTAssertTrue(displayState.showsInfoAffordance)
    }

    // MARK: - delegation parity

    @MainActor
    func testEvaluateMatchesDirectEvaluatorForKnownScenario() {
        let model = ReciprocityModel()
        let directEvaluator = ReciprocityCalculationPolicyEvaluator()
        let profile = ReciprocityPolicyScenarioFactory.triXProfile()

        let viaModel = model.evaluate(profile: profile, meteredExposureSeconds: 5)
        let viaDirect = directEvaluator.evaluate(profile: profile, meteredExposureSeconds: 5)

        // ReciprocityModel is a thin facade — both paths must agree.
        XCTAssertEqual(viaModel.metadata.basis, viaDirect.metadata.basis)
        XCTAssertEqual(
            viaModel.correctedExposureSeconds,
            viaDirect.correctedExposureSeconds
        )
    }
}
