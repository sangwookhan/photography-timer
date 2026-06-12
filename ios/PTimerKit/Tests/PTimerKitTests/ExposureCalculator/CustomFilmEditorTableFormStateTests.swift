import XCTest
import PTimerKit
import PTimerCore

/// Form-state coverage for the custom table input kind
/// (PTIMER-178): the anchor-row validation matrix, the derived
/// boundary policy (no-correction default `firstAnchor / 10`,
/// source range = last anchor), the built `FilmIdentity` shape
/// (single `.tableInterpolation` rule + display-only
/// `sourceEvidence` copies), and the Edit-flow round trip.
final class CustomFilmEditorTableFormStateTests: XCTestCase {

    // MARK: - Build (valid table)

    func test_validate_validTable_buildsSingleTableRuleProfile() throws {
        let form = makeTableForm(rows: [("1", "2"), ("10", "80"), ("100", "1600")])
        let film = try XCTUnwrap(validated(form))

        XCTAssertEqual(film.kind, .custom)
        let profile = try XCTUnwrap(film.profiles.first)
        XCTAssertEqual(profile.rules.count, 1)
        guard case .tableInterpolation(let rule) = try XCTUnwrap(profile.rules.first) else {
            return XCTFail("Expected a tableInterpolation rule")
        }
        XCTAssertEqual(
            rule.anchors,
            [
                TableAnchor(meteredSeconds: 1, correctedSeconds: 2),
                TableAnchor(meteredSeconds: 10, correctedSeconds: 80),
                TableAnchor(meteredSeconds: 100, correctedSeconds: 1600),
            ]
        )
        XCTAssertTrue(rule.hasValidParameters)
    }

    func test_validate_emptyNoCorrection_defaultsToFirstAnchorOverTen() throws {
        let form = makeTableForm(rows: [("1", "2"), ("10", "80")])
        let rule = try tableRule(from: form)
        XCTAssertEqual(rule.noCorrectionThroughSeconds, 0.1, accuracy: 1e-9)
    }

    func test_validate_sourceRange_derivedFromLastAnchor() throws {
        let form = makeTableForm(rows: [("1", "2"), ("10", "80"), ("100", "1600")])
        let rule = try tableRule(from: form)
        XCTAssertEqual(rule.sourceRangeThroughSeconds, 100, accuracy: 1e-9)
    }

    func test_validate_explicitNoCorrection_isPreserved() throws {
        var form = makeTableForm(rows: [("10", "80"), ("100", "1600")])
        form.noCorrectionThroughText = "2"
        let rule = try tableRule(from: form)
        XCTAssertEqual(rule.noCorrectionThroughSeconds, 2, accuracy: 1e-9)
    }

    func test_validate_blankRowsAreIgnored() throws {
        var form = makeTableForm(rows: [("1", "2"), ("10", "80")])
        form.tableRows.append(CustomFilmTableAnchorRowInput())
        let rule = try tableRule(from: form)
        XCTAssertEqual(rule.anchors.count, 2)
    }

    func test_validate_sourceEvidence_carriesDisplayCopiesOfAnchors() throws {
        let form = makeTableForm(rows: [("1", "2"), ("10", "80")])
        let film = try XCTUnwrap(validated(form))
        let profile = try XCTUnwrap(film.profiles.first)

        XCTAssertEqual(profile.sourceEvidence.count, 2)
        let pairs: [(metered: Double, corrected: Double)] = profile.sourceEvidence.compactMap { row in
            guard case .exactSeconds(let metered) = row.meteredExposure else { return nil }
            let corrected = row.adjustments.compactMap { adjustment -> Double? in
                guard case .exposure(.correctedTime(let mapping)) = adjustment else { return nil }
                return mapping.correctedSeconds
            }.first
            guard let corrected else { return nil }
            return (metered, corrected)
        }
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].metered, 1, accuracy: 1e-9)
        XCTAssertEqual(pairs[0].corrected, 2, accuracy: 1e-9)
        XCTAssertEqual(pairs[1].metered, 10, accuracy: 1e-9)
        XCTAssertEqual(pairs[1].corrected, 80, accuracy: 1e-9)
    }

    func test_validate_editIDQueue_reusesProfileThenFilmID() throws {
        let form = makeTableForm(rows: [("1", "2"), ("10", "80")])
        var idQueue = ["profile-id", "film-id"]
        let result = form.validate {
            idQueue.isEmpty ? "overflow" : idQueue.removeFirst()
        }
        guard case .success(let film) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(film.id, "film-id")
        XCTAssertEqual(film.profiles.first?.id, "profile-id")
    }

    // MARK: - Validation matrix (invalid tables)

    func test_validate_singleAnchor_failsInsufficient() {
        let form = makeTableForm(rows: [("10", "80")])
        assertFailure(form, contains: .insufficientTableAnchors)
    }

    func test_validate_unparseableValue_failsInvalidAnchors() {
        let form = makeTableForm(rows: [("abc", "80"), ("100", "1600")])
        assertFailure(form, contains: .invalidTableAnchors)
    }

    func test_validate_nonPositiveValue_failsInvalidAnchors() {
        let form = makeTableForm(rows: [("0", "2"), ("10", "80")])
        assertFailure(form, contains: .invalidTableAnchors)
    }

    func test_validate_descendingMetered_failsInvalidAnchors() {
        let form = makeTableForm(rows: [("10", "80"), ("1", "2")])
        assertFailure(form, contains: .invalidTableAnchors)
    }

    func test_validate_duplicateMetered_failsInvalidAnchors() {
        let form = makeTableForm(rows: [("10", "80"), ("10", "90")])
        assertFailure(form, contains: .invalidTableAnchors)
    }

    func test_validate_correctedShorterThanMetered_failsInvalidAnchors() {
        let form = makeTableForm(rows: [("10", "5"), ("100", "1600")])
        assertFailure(form, contains: .invalidTableAnchors)
    }

    func test_validate_partiallyFilledRow_failsInvalidAnchors() {
        var form = makeTableForm(rows: [("1", "2"), ("10", "80")])
        form.tableRows.append(CustomFilmTableAnchorRowInput(meteredText: "50", correctedText: ""))
        assertFailure(form, contains: .invalidTableAnchors)
    }

    func test_validate_zeroNoCorrection_failsStricterThanDomain() {
        // The domain contract allows `>= 0`, but the table evaluator
        // feeds the knee into log-log space — the editor must never
        // save 0.
        var form = makeTableForm(rows: [("1", "2"), ("10", "80")])
        form.noCorrectionThroughText = "0"
        assertFailure(form, contains: .invalidNoCorrectionThrough)
    }

    func test_validate_noCorrectionAtFirstAnchor_fails() {
        var form = makeTableForm(rows: [("1", "2"), ("10", "80")])
        form.noCorrectionThroughText = "1"
        assertFailure(form, contains: .invalidNoCorrectionThrough)
    }

    func test_validate_unlimitedNoCorrection_fails() {
        var form = makeTableForm(rows: [("1", "2"), ("10", "80")])
        form.noCorrectionThroughText = "Unlimited"
        assertFailure(form, contains: .invalidNoCorrectionThrough)
    }

    func test_validate_missingIdentity_stillReportsIdentityErrors() {
        var form = makeTableForm(rows: [("1", "2"), ("10", "80")])
        form.filmLabel = ""
        form.isoText = ""
        guard case .failure(let envelope) = form.validate() else {
            return XCTFail("Expected failure")
        }
        XCTAssertTrue(envelope.contains(.missingFilmLabel))
        XCTAssertTrue(envelope.contains(.invalidISO))
    }

    // MARK: - Row-level wording

    func test_tableRowValidationReason_flagsShorteningRow() {
        let form = makeTableForm(rows: [("10", "5"), ("100", "1600")])
        XCTAssertEqual(
            form.tableRowValidationReason(at: 0, isEditing: false),
            "Tc must be ≥ Tm"
        )
        XCTAssertNil(form.tableRowValidationReason(at: 1, isEditing: false))
    }

    func test_tableRowValidationReason_flagsOutOfOrderRow() {
        let form = makeTableForm(rows: [("10", "80"), ("5", "40")])
        XCTAssertEqual(
            form.tableRowValidationReason(at: 1, isEditing: false),
            "Tm must increase down the table"
        )
    }

    func test_tableRowValidationReason_blankRowIsSilent() {
        var form = makeTableForm(rows: [("1", "2"), ("10", "80")])
        form.tableRows.append(CustomFilmTableAnchorRowInput())
        XCTAssertNil(form.tableRowValidationReason(at: 2, isEditing: false))
    }

    // MARK: - Kind switching

    func test_switchingToTable_seedsMinimumRows_andClearsFormulaDefault() {
        let form = CustomFilmEditorFormState()
        let switched = form.switching(toCalculationKind: .table)
        XCTAssertEqual(switched.calculationInputKind, .table)
        XCTAssertEqual(switched.tableRows.count, CustomFilmEditorFormState.newTableRowSeedCount)
        XCTAssertTrue(switched.noCorrectionThroughText.isEmpty)
    }

    func test_switchingBackToFormula_restoresFormulaDefault() {
        let form = CustomFilmEditorFormState()
            .switching(toCalculationKind: .table)
            .switching(toCalculationKind: .formula)
        XCTAssertEqual(form.calculationInputKind, .formula)
        XCTAssertEqual(form.noCorrectionThroughText, "1")
    }

    func test_switchingToTable_keepsTypedNoCorrection() {
        var form = CustomFilmEditorFormState()
        form.noCorrectionThroughText = "0.5"
        let switched = form.switching(toCalculationKind: .table)
        XCTAssertEqual(switched.noCorrectionThroughText, "0.5")
    }

    // MARK: - Edit-flow round trip

    func test_fromFilm_tableProfile_prefillsTableKindAndRows() throws {
        var form = makeTableForm(rows: [("1", "2"), ("10", "80"), ("100", "1600")])
        form.noCorrectionThroughText = "0.5"
        form.notes = "Step wedge test"
        let film = try XCTUnwrap(validated(form))

        let reopened = try XCTUnwrap(CustomFilmEditorFormState.from(film: film))
        XCTAssertEqual(reopened.calculationInputKind, .table)
        XCTAssertEqual(reopened.tableRows.count, 3)
        XCTAssertEqual(reopened.tableRows[1].meteredText, "10")
        XCTAssertEqual(reopened.tableRows[1].correctedText, "80")
        XCTAssertEqual(reopened.noCorrectionThroughText, "0.5")
        XCTAssertEqual(reopened.filmLabel, "Test Film")
        XCTAssertEqual(reopened.isoText, "100")
        XCTAssertEqual(reopened.notes, "Step wedge test")

        // The reopened form must save back to an identical rule.
        let rebuilt = try tableRule(from: reopened)
        let original = try tableRule(from: form)
        XCTAssertEqual(rebuilt, original)
    }

    func test_fromFilm_formulaProfile_staysFormulaKind() throws {
        let film = CustomFilmTestSupport.makeCustomFilm(id: "formula-film")
        let reopened = try XCTUnwrap(CustomFilmEditorFormState.from(film: film))
        XCTAssertEqual(reopened.calculationInputKind, .formula)
        XCTAssertTrue(reopened.tableRows.isEmpty)
    }

    // MARK: - Preview parity

    func test_parsedTableRule_matchesSavedRule() throws {
        let form = makeTableForm(rows: [("1", "2"), ("10", "80")])
        let previewRule = try XCTUnwrap(form.parsedTableInterpolationRule())
        let savedRule = try tableRule(from: form)
        XCTAssertEqual(previewRule, savedRule)
        XCTAssertTrue(form.tableCanRenderPreview)
    }

    func test_previewTableRows_reproduceAnchorsExactly_andMarkBeyondSource() throws {
        let form = makeTableForm(rows: [("1", "2"), ("10", "80"), ("100", "1600")])
        let rows = CustomFilmEditorPreviewPresenter.tableRows(form: form)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(try XCTUnwrap(rows[0].correctedSeconds), 2, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(rows[1].correctedSeconds), 80, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(rows[2].correctedSeconds), 1600, accuracy: 1e-6)
        XCTAssertEqual(rows[0].status, .tableApplied)
        XCTAssertEqual(rows[3].status, .beyondSourceRange)
        XCTAssertNotNil(rows[3].correctedSeconds)
    }

    func test_previewTableRows_emptyWhileTableInvalid() {
        let form = makeTableForm(rows: [("10", "80")])
        XCTAssertTrue(CustomFilmEditorPreviewPresenter.tableRows(form: form).isEmpty)
        XCTAssertNotNil(CustomFilmEditorPreviewPresenter.tableDiagnosisMessage(form: form))
        XCTAssertFalse(form.tableCanRenderPreview)
    }

    // MARK: - Helpers

    private func makeTableForm(
        rows: [(metered: String, corrected: String)]
    ) -> CustomFilmEditorFormState {
        CustomFilmEditorFormState(
            filmLabel: "Test Film",
            isoText: "100",
            noCorrectionThroughText: "",
            calculationInputKind: .table,
            tableRows: rows.map {
                CustomFilmTableAnchorRowInput(
                    meteredText: $0.metered,
                    correctedText: $0.corrected
                )
            }
        )
    }

    private func validated(_ form: CustomFilmEditorFormState) -> FilmIdentity? {
        guard case .success(let film) = form.validate() else { return nil }
        return film
    }

    private func tableRule(
        from form: CustomFilmEditorFormState
    ) throws -> TableInterpolationReciprocityRule {
        let film = try XCTUnwrap(validated(form))
        let profile = try XCTUnwrap(film.profiles.first)
        guard case .tableInterpolation(let rule) = try XCTUnwrap(profile.rules.first) else {
            throw XCTSkip("Expected tableInterpolation rule")
        }
        return rule
    }

    private func assertFailure(
        _ form: CustomFilmEditorFormState,
        contains error: CustomFilmEditorValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let envelope) = form.validate() else {
            return XCTFail("Expected validation failure", file: file, line: line)
        }
        XCTAssertTrue(
            envelope.contains(error),
            "Expected \(error) in \(envelope.errors)",
            file: file,
            line: line
        )
    }
}
