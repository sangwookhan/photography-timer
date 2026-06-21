// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-84 polish: covers the shared
/// `CalculationBasisPresenter` — the single source of the formula
/// expression rendered between the reciprocity graph and the
/// textual interpretation in both the custom editor preview and
/// the Reciprocity Details surface.
final class CalculationBasisPresenterTests: XCTestCase {

    // MARK: - Basic formula

    func test_basic_collapsesToSimpleExponentShape() {
        // coefficient = 1, reference = 1s, offset = 0 → renders
        // without the leading multiplier and without anchor.
        let form = CustomFilmEditorFormState(
            filmLabel: "Basic",
            isoText: "100",
            formulaInputMode: .basic,
            exponentText: "1.30",
            baseTmText: "1",
            baseTcText: "1",
            offsetSecondsText: "",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        XCTAssertEqual(
            CalculationBasisPresenter.calculationBasisText(for: form),
            "Tc = Tm^1.3"
        )
    }

    // MARK: - Scaled formula

    func test_scaled_rendersAnchoredShape() {
        // T-MAX 100 style anchored formula with non-neutral
        // coefficient and reference.
        let form = CustomFilmEditorFormState(
            filmLabel: "TMAX",
            isoText: "100",
            formulaInputMode: .scaled,
            exponentText: "1.0966",
            baseTmText: "0.1",
            baseTcText: "0.1",
            offsetSecondsText: "",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        XCTAssertEqual(
            CalculationBasisPresenter.calculationBasisText(for: form),
            "Tc = 0.1s × (Tm / 0.1s)^1.0966"
        )
    }

    func test_scaled_taskExampleRenders() {
        // Task example: coefficient 3, reference 2s, exponent 1.29.
        let form = CustomFilmEditorFormState(
            filmLabel: "Example",
            isoText: "100",
            formulaInputMode: .scaled,
            exponentText: "1.29",
            baseTmText: "2",
            baseTcText: "3",
            offsetSecondsText: "",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        XCTAssertEqual(
            CalculationBasisPresenter.calculationBasisText(for: form),
            "Tc = 3s × (Tm / 2s)^1.29"
        )
    }

    // MARK: - Advanced formula

    func test_advanced_taskExampleRenders() {
        // Task example: coefficient 10, reference 3s, exponent
        // 1.30, offset 0.3s.
        let form = CustomFilmEditorFormState(
            filmLabel: "Advanced",
            isoText: "100",
            formulaInputMode: .advanced,
            exponentText: "1.30",
            baseTmText: "3",
            baseTcText: "10",
            offsetSecondsText: "0.3",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        XCTAssertEqual(
            CalculationBasisPresenter.calculationBasisText(for: form),
            "Tc = 10s × (Tm / 3s)^1.3 + 0.3s"
        )
    }

    // MARK: - Unparseable form

    func test_unparseableForm_returnsNil() {
        // No exponent → form cannot be parsed; the preview surface
        // suppresses the Calculation Basis block entirely.
        let form = CustomFilmEditorFormState()
        XCTAssertNil(CalculationBasisPresenter.calculationBasisText(for: form))
    }

    // MARK: - Profile-shaped overload parity

    func test_profileOverload_matchesFormOverload_forSameInputs() {
        // Saving the form should produce a profile whose
        // calculation-basis text matches what the editor preview
        // showed pre-save.
        let formState = CustomFilmEditorFormState(
            filmLabel: "Parity",
            isoText: "100",
            formulaInputMode: .scaled,
            exponentText: "1.29",
            baseTmText: "2",
            baseTcText: "3",
            offsetSecondsText: "",
            noCorrectionThroughText: "1",
            validThroughText: ""
        )
        guard case .success(let film) = formState.validate(),
              let profile = film.profiles.first else {
            return XCTFail("Valid form must produce a saved profile.")
        }
        let editorBasis = CalculationBasisPresenter.calculationBasisText(for: formState)
        let profileBasis = CalculationBasisPresenter.calculationBasisText(for: profile)
        XCTAssertEqual(editorBasis, profileBasis)
        XCTAssertEqual(editorBasis, "Tc = 3s × (Tm / 2s)^1.29")
    }

    // MARK: - Non-formula profile

    func test_profileWithoutFormulaRule_returnsNil() {
        // Threshold-only profile (no formula rule) → no
        // calculation-basis text to render.
        let thresholdRule = ThresholdReciprocityRule(
            noCorrectionRange: ReciprocityTimeRange(
                minimumSeconds: 0,
                maximumSeconds: 1
            )
        )
        let profile = ReciprocityProfile(
            id: "no-formula",
            name: "No formula",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.threshold(thresholdRule)]
        )
        XCTAssertNil(CalculationBasisPresenter.calculationBasisText(for: profile))
    }
}
