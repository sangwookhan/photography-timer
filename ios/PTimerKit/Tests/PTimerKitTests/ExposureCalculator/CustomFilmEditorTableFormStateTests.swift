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

    func test_validate_emptyNoCorrection_defaultsToHalfSecond_forTypicalAnchor() throws {
        // Default is min(0.5, firstAnchor / 2); first anchor 1 s → 0.5 s.
        let form = makeTableForm(rows: [("1", "2"), ("10", "80")])
        let rule = try tableRule(from: form)
        XCTAssertEqual(rule.noCorrectionThroughSeconds, 0.5, accuracy: 1e-9)
    }

    func test_validate_emptyNoCorrection_subHalfSecondAnchor_defaultsToHalfAnchor() throws {
        // First anchor 0.4 s → min(0.5, 0.2) = 0.2 s.
        let form = makeTableForm(rows: [("0.4", "1"), ("10", "80")])
        let rule = try tableRule(from: form)
        XCTAssertEqual(rule.noCorrectionThroughSeconds, 0.2, accuracy: 1e-9)
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

    func test_validate_descendingMetered_autoSortedToValid() throws {
        // Rows entered in descending order are auto-sorted before
        // validation, so [10→80, 1→2] is identical to [1→2, 10→80].
        let form = makeTableForm(rows: [("10", "80"), ("1", "2")])
        let rule = try tableRule(from: form)
        XCTAssertEqual(rule.anchors[0].meteredSeconds, 1, accuracy: 1e-9)
        XCTAssertEqual(rule.anchors[1].meteredSeconds, 10, accuracy: 1e-9)
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

    // MARK: - Auto-sort

    func test_parsedTableAnchors_autoSortsDescendingInput() {
        // Rows entered in any order are returned sorted ascending by Tm.
        let form = makeTableForm(rows: [("100", "1600"), ("1", "2"), ("10", "80")])
        let anchors = form.parsedTableAnchors()
        XCTAssertEqual(anchors?.map(\.meteredSeconds), [1, 10, 100])
    }

    func test_parsedTableAnchors_incompleteRowDoesNotPreventSort() {
        // A partially blank row (isBlank == true) is skipped; the
        // remaining complete rows are still sorted and returned.
        var form = makeTableForm(rows: [("10", "80"), ("1", "2")])
        form.tableRows.append(CustomFilmTableAnchorRowInput())
        let anchors = form.parsedTableAnchors()
        XCTAssertEqual(anchors?.map(\.meteredSeconds), [1, 10])
    }

    func test_sortCompleteTableRows_reordersOutOfOrderRows() {
        var form = makeTableForm(rows: [("100", "1600"), ("1", "2"), ("10", "80")])
        form.sortCompleteTableRows()
        XCTAssertEqual(form.tableRows.map(\.meteredText), ["1", "10", "100"])
    }

    func test_sortCompleteTableRows_leavesIncompleteRowInPlace() {
        // Partial row at position 1 must not jump; complete rows around it sort.
        var form = makeTableForm(rows: [("100", "1600"), ("10", "80")])
        form.tableRows.insert(
            CustomFilmTableAnchorRowInput(meteredText: "50", correctedText: ""),
            at: 1
        )
        // Rows: [100→1600, 50→(incomplete), 10→80]
        form.sortCompleteTableRows()
        // Complete positions 0 and 2 sort ascending: 10 < 100
        XCTAssertEqual(form.tableRows[0].meteredText, "10")
        XCTAssertEqual(form.tableRows[1].meteredText, "50") // incomplete — unmoved
        XCTAssertEqual(form.tableRows[2].meteredText, "100")
    }

    func test_sortCompleteTableRows_noOpWhenFewerThanTwoCompleteRows() {
        var form = makeTableForm(rows: [("10", "80")])
        form.tableRows.append(CustomFilmTableAnchorRowInput())
        let original = form.tableRows.map(\.meteredText)
        form.sortCompleteTableRows()
        XCTAssertEqual(form.tableRows.map(\.meteredText), original)
    }

    func test_sortCompleteTableRows_preservesDuplicateMeteredInvalid() {
        // Duplicate Tm values are still invalid after sort; just confirms
        // sort doesn't crash or silently drop rows.
        var form = makeTableForm(rows: [("10", "90"), ("10", "80")])
        form.sortCompleteTableRows()
        XCTAssertEqual(form.tableRows.count, 2)
        XCTAssertNil(form.parsedTableAnchors(), "Duplicates must remain invalid")
    }

    func test_savePath_storesAnchorsSortedByMeteredTime() throws {
        // Rows entered out of order (2, 100, 10) must save ascending.
        let form = makeTableForm(rows: [("2", "2"), ("100", "1000"), ("10", "20")])
        let rule = try tableRule(from: form)
        XCTAssertEqual(rule.anchors.map(\.meteredSeconds), [2, 10, 100])
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

    func test_tableRowValidationReason_outOfOrderCompleteRow_returnsNil() {
        // Out-of-order complete rows are auto-sorted on save/preview;
        // no per-row error is shown for positional order.
        let form = makeTableForm(rows: [("10", "80"), ("5", "40")])
        XCTAssertNil(form.tableRowValidationReason(at: 0, isEditing: false))
        XCTAssertNil(form.tableRowValidationReason(at: 1, isEditing: false))
    }

    func test_tableRowValidationReason_duplicateMetered_returnsError() {
        let form = makeTableForm(rows: [("10", "80"), ("10", "90")])
        XCTAssertEqual(
            form.tableRowValidationReason(at: 1, isEditing: false),
            "Rows must be sorted by Tm."
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

    // MARK: - Duration formatting (no decimal minutes)

    func test_formatDurationExpression_100sDoesNotRenderAsDecimalMinutes() {
        // 100 s used to render as "1.7m" — this pins the fix so it cannot regress.
        let result = CustomFilmEditorFormState.formatDurationExpression(100)
        XCTAssertFalse(
            result.contains(".") && result.hasSuffix("m"),
            "100s formatted as \(result); expected no decimal-minute notation"
        )
        XCTAssertEqual(result, "1m 40s")
    }

    func test_formatDurationExpression_wholeMinutesRenderCompact() {
        XCTAssertEqual(CustomFilmEditorFormState.formatDurationExpression(60), "1m")
        XCTAssertEqual(CustomFilmEditorFormState.formatDurationExpression(120), "2m")
        XCTAssertEqual(CustomFilmEditorFormState.formatDurationExpression(3600), "60m")
    }

    func test_formatDurationExpression_subMinuteValuesUnchanged() {
        XCTAssertEqual(CustomFilmEditorFormState.formatDurationExpression(1), "1s")
        XCTAssertEqual(CustomFilmEditorFormState.formatDurationExpression(30), "30s")
        XCTAssertEqual(CustomFilmEditorFormState.formatDurationExpression(0.5), "0.50s")
        XCTAssertEqual(CustomFilmEditorFormState.formatDurationExpression(1.5), "1.5s")
    }

    func test_formatDurationExpression_fractionalMinutesUseMsSeparation() {
        // Values like 100 s, 400 s, 1262 s are common reciprocity anchors.
        XCTAssertEqual(CustomFilmEditorFormState.formatDurationExpression(400), "6m 40s")
        XCTAssertEqual(CustomFilmEditorFormState.formatDurationExpression(1262), "21m 2s")
        XCTAssertEqual(CustomFilmEditorFormState.formatDurationExpression(90), "1m 30s")
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

    /// The fitted-formula unavailable warning is gated on
    /// `parsedTableInterpolationRule()` being non-nil, so an incomplete
    /// table (which cannot even attempt a fit) must yield no rule and
    /// therefore no warning — never a false "shortening" claim.
    func test_incompleteTable_yieldsNoRuleSoFittedWarningIsSuppressed() {
        var form = makeTableForm(rows: [("2", "2")])
        form.tableRows.append(CustomFilmTableAnchorRowInput(meteredText: "10", correctedText: ""))
        XCTAssertNil(form.parsedTableInterpolationRule())
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

// MARK: - Anchor seconds format

final class CustomFilmEditorAnchorSecondsFormatTests: XCTestCase {

    func test_formatAnchorSeconds_subSixty_returnsPlain() {
        XCTAssertEqual(CustomFilmEditorFormState.formatAnchorSeconds(10), "10s")
        XCTAssertEqual(CustomFilmEditorFormState.formatAnchorSeconds(59), "59s")
    }

    func test_formatAnchorSeconds_exactSixty_includesRawSeconds() {
        let result = CustomFilmEditorFormState.formatAnchorSeconds(60)
        XCTAssertTrue(result.hasPrefix("60s"), "Expected '60s' prefix, got '\(result)'")
    }

    func test_formatAnchorSeconds_100s_displaysSecondsFirst() {
        let result = CustomFilmEditorFormState.formatAnchorSeconds(100)
        XCTAssertTrue(result.hasPrefix("100s"), "Expected '100s' prefix, got '\(result)'")
        XCTAssertTrue(result.contains("1m"), "Expected minutes component, got '\(result)'")
    }

    func test_formatAnchorSeconds_1000s_displaysSecondsFirst() {
        let result = CustomFilmEditorFormState.formatAnchorSeconds(1000)
        XCTAssertTrue(result.hasPrefix("1000s"), "Expected '1000s' prefix, got '\(result)'")
        XCTAssertTrue(result.contains("16m"), "Expected 16m component, got '\(result)'")
    }

    func test_formatAnchorSeconds_neverDecimalMinutes() {
        for seconds in [100.0, 200.0, 300.0, 1000.0] {
            let result = CustomFilmEditorFormState.formatAnchorSeconds(seconds)
            XCTAssertFalse(
                result.contains(".") && result.contains("m"),
                "formatAnchorSeconds(\(seconds)) emitted decimal minutes: '\(result)'"
            )
        }
    }
}
