// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerKit

/// PTIMER-183 follow-up: a formula-mode custom film left on the default
/// shape (Tc₀ = 1, Tm₀ = 1, b = 0) with only `p` entered must resolve its
/// no-correction boundary to 1.0 and pass preview/save, while table mode
/// keeps its own `min(0.5, firstAnchor/2)` default and an explicit
/// formula override is preserved.
final class CustomFilmEditorNoCorrectionDefaultTests: XCTestCase {

    // 1. Formula default success.
    func test_formulaDefaults_onlyExponent_isValid() {
        var form = CustomFilmEditorFormState()
        form.filmLabel = "My Film"
        form.isoText = "100"
        form.exponentText = "1.3"
        // Tc₀ = 1, Tm₀ = 1, b = "" (0), no-correction left at default.
        switch form.validate() {
        case .success:
            break
        case .failure(let errors):
            XCTFail("Expected formula defaults + p=1.3 to be valid, got \(errors.errors)")
        }
    }

    // 3. Explicit formula override preserved (0.5 stays 0.5; guard may fail).
    func test_formulaExplicitNoCorrection_isNotReplaced() {
        var form = CustomFilmEditorFormState()
        form.filmLabel = "My Film"
        form.isoText = "100"
        form.exponentText = "1.3"
        form.noCorrectionThroughText = "0.5"
        XCTAssertEqual(form.noCorrectionThroughText, "0.5")
        // With an explicit 0.5, Tc₀=1, Tm₀=1, p>1, the guard legitimately
        // rejects (formula shortens exposure below 0.5s).
        if case .success = form.validate() {
            XCTFail("Explicit no-correction 0.5 with p>1 should still fail the guard")
        }
    }

    // 4a. Switching table -> formula must not carry the table auto-default.
    func test_switchTableToFormula_restoresFormulaDefault_notTableAuto() {
        var form = CustomFilmEditorFormState()
        form.filmLabel = "My Film"
        form.isoText = "100"
        form.exponentText = "1.3"
        // Toggle to table (clears the "1" default), then back to formula.
        form = form.switching(toCalculationKind: .table)
        form = form.switching(toCalculationKind: .formula)
        switch form.validate() {
        case .success:
            break
        case .failure(let errors):
            XCTFail("Round-trip to table and back must keep a valid 1.0 default, got \(errors.errors)")
        }
    }

    // 4b. A user-entered no-correction survives the toggle both ways.
    func test_userEnteredNoCorrection_survivesModeToggle() {
        var form = CustomFilmEditorFormState()
        form.noCorrectionThroughText = "2"
        form = form.switching(toCalculationKind: .table)
        XCTAssertEqual(form.noCorrectionThroughText, "2", "typed value must survive formula->table")
        form = form.switching(toCalculationKind: .formula)
        XCTAssertEqual(form.noCorrectionThroughText, "2", "typed value must survive table->formula")
    }
}
