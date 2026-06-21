// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-180: creating an editable Custom Formula from a saved Custom
/// Table. The fitted formula is only a seed; the saved formula is an
/// independent profile, optionally linked back to the table for
/// reference / error display (never calculation).
final class CustomFilmCreateFormulaTests: XCTestCase {

    // MARK: - Seed from a saved table

    func testCreatingFormulaSeedsFromTableFitAndLinks() throws {
        let table = eligibleTableFilm(id: "custom.table.curved", label: "Acme 100")
        let form = try XCTUnwrap(
            CustomFilmEditorFormState.creatingFormula(fromTable: table),
            "An eligible custom table must seed a formula."
        )

        XCTAssertEqual(form.calculationInputKind, .formula)
        XCTAssertEqual(form.referenceTableFilmID, table.id, "The seed pre-links the source table.")
        XCTAssertEqual(form.filmLabel, "Acme 100 Formula", "Label is auto-suggested from the table, editable.")
        XCTAssertEqual(form.isoText, "100")

        // Seeded parameters equal the shared fitted-formula preview
        // (within the editor's 4-decimal seed precision).
        let tableRule = try XCTUnwrap(tableRule(of: table))
        guard case let .available(preview) = CustomTableFittedFormulaPresenter.outcome(for: tableRule),
              let seeded = form.parsedReciprocityFormula() else {
            return XCTFail("Expected an available preview and a parseable seeded formula.")
        }
        XCTAssertEqual(seeded.exponent, preview.exponent, accuracy: 1e-3)
        XCTAssertEqual(seeded.coefficientSeconds, preview.coefficientSeconds, accuracy: 1e-3)
        XCTAssertEqual(seeded.noCorrectionThroughSeconds, preview.noCorrectionThroughSeconds, accuracy: 1e-6)
    }

    func testCreatingFormulaUnavailableForIneligibleTable() {
        XCTAssertNil(CustomFilmEditorFormState.creatingFormula(fromTable: ineligibleTableFilm(id: "t.short")))
    }

    func testCreatingFormulaNilForFormulaOrPresetFilm() throws {
        let formulaFilm = CustomFilmTestSupport.makeCustomFilm(id: "custom.formula")
        XCTAssertNil(CustomFilmEditorFormState.creatingFormula(fromTable: formulaFilm))

        let preset = try XCTUnwrap(LaunchPresetFilmCatalog.films.first { $0.id == "kodak-tri-x-400" })
        XCTAssertNil(CustomFilmEditorFormState.creatingFormula(fromTable: preset))
    }

    // MARK: - Save produces an independent, linked formula profile

    func testSavedFormulaIsIndependentFormulaProfileWithPersistedLink() throws {
        let table = eligibleTableFilm(id: "custom.table.curved", label: "Acme 100")
        let form = try XCTUnwrap(CustomFilmEditorFormState.creatingFormula(fromTable: table))

        guard case let .success(saved) = form.validate(idGenerator: { "generated-id" }) else {
            return XCTFail("Seeded form must validate into a custom formula film.")
        }
        XCTAssertEqual(saved.kind, .custom)
        XCTAssertNotEqual(saved.id, table.id, "The saved formula is a separate film.")
        let profile = try XCTUnwrap(saved.profiles.first)
        XCTAssertTrue(
            profile.rules.contains { if case .formula = $0 { return true }; return false },
            "The saved profile calculates by formula."
        )
        XCTAssertFalse(
            profile.rules.contains { if case .tableInterpolation = $0 { return true }; return false },
            "The saved formula must not carry a table rule — calculation is independent of the table."
        )
        XCTAssertEqual(
            saved.userMetadata?.referenceTableFilmID,
            table.id,
            "The reference-table link persists at film level."
        )
    }

    func testEditRoundTripPreservesLink() throws {
        let table = eligibleTableFilm(id: "custom.table.curved", label: "Acme 100")
        let form = try XCTUnwrap(CustomFilmEditorFormState.creatingFormula(fromTable: table))
        guard case let .success(saved) = form.validate(idGenerator: { "generated-id" }) else {
            return XCTFail("expected success")
        }
        let reopened = try XCTUnwrap(CustomFilmEditorFormState.from(film: saved))
        XCTAssertEqual(reopened.referenceTableFilmID, table.id, "Editing a linked formula preserves the link.")
        XCTAssertEqual(reopened.calculationInputKind, .formula)
    }

    // MARK: - Reference points + error

    func testReferencePointRowsMergeTableAnchorsWithErrorAndDedup() throws {
        let table = eligibleTableFilm(id: "custom.table.curved", label: "Acme 100")
        let form = try XCTUnwrap(CustomFilmEditorFormState.creatingFormula(fromTable: table))
        let anchors = try XCTUnwrap(tableRule(of: table)).anchors  // metered 1, 10, 100

        let rows = CustomFilmEditorPreviewPresenter.referencePointRows(
            form: form,
            linkedTableAnchors: anchors
        )

        // samples [1,10,60,300,1000] ∪ anchors {1,10,100} → 1,10,60,100,300,1000 (1 & 10 dedup).
        XCTAssertEqual(rows.map(\.meteredSeconds), [1, 10, 60, 100, 300, 1000])

        let anchorRow = try XCTUnwrap(rows.first { $0.meteredSeconds == 100 })
        XCTAssertEqual(anchorRow.referenceCorrectedSeconds, 600, "Reference Tc comes from the table anchor.")
        XCTAssertNotNil(anchorRow.stopError, "An anchor row shows formula-vs-table stop error.")

        let standardOnlyRow = try XCTUnwrap(rows.first { $0.meteredSeconds == 60 })
        XCTAssertNil(standardOnlyRow.referenceCorrectedSeconds, "A standard-only row has no reference value.")
        XCTAssertNil(standardOnlyRow.stopError, "A standard-only row has no error.")
    }

    func testReferencePointRowsWithoutLinkHaveNoReferenceOrError() throws {
        let table = eligibleTableFilm(id: "custom.table.curved", label: "Acme 100")
        let form = try XCTUnwrap(CustomFilmEditorFormState.creatingFormula(fromTable: table))

        let rows = CustomFilmEditorPreviewPresenter.referencePointRows(
            form: form,
            linkedTableAnchors: []
        )
        XCTAssertEqual(rows.map(\.meteredSeconds), [1, 10, 60, 300, 1000])
        XCTAssertTrue(rows.allSatisfy { $0.referenceCorrectedSeconds == nil && $0.stopError == nil })
    }

    // MARK: - Formula preview graph reference markers (Q2)

    func testFormulaPreviewGraphShowsLinkedReferenceMarkersOnlyWhenLinked() throws {
        let table = eligibleTableFilm(id: "custom.table.curved", label: "Acme 100")
        let form = try XCTUnwrap(CustomFilmEditorFormState.creatingFormula(fromTable: table))
        let anchors = try XCTUnwrap(tableRule(of: table)).anchors

        let linked = try XCTUnwrap(
            CustomFilmEditorPreviewGraphPresenter.graphDisplayState(
                for: form,
                linkedReferenceTableAnchors: anchors
            )
        )
        XCTAssertFalse(
            linked.sourceReferenceMarkers.isEmpty,
            "A linked formula graph must show the table's anchors as source-reference markers."
        )
        // The current result point is still plotted, i.e. the curve is
        // the formula (the markers are an overlay, not the curve).
        XCTAssertNotNil(linked.currentPoint)

        let unlinked = try XCTUnwrap(
            CustomFilmEditorPreviewGraphPresenter.graphDisplayState(
                for: form,
                linkedReferenceTableAnchors: []
            )
        )
        XCTAssertTrue(
            unlinked.sourceReferenceMarkers.isEmpty,
            "An unlinked formula graph stays unchanged — no source-reference markers."
        )
    }

    // MARK: - Edit-flow reference-table hydration (resolver)

    func testResolverHydratesSavedFormulaLinkFromPersistedMetadata() throws {
        let table = eligibleTableFilm(id: "custom.table.curved", label: "Acme 100")
        let form = try XCTUnwrap(CustomFilmEditorFormState.creatingFormula(fromTable: table))
        guard case let .success(savedFormula) = form.validate(idGenerator: { "f-id" }) else {
            return XCTFail("seeded form must validate")
        }

        let resolution = CustomFilmReferenceTableResolver.resolve(for: savedFormula) { id in
            id == table.id ? table : nil
        }
        XCTAssertFalse(resolution.isLinkedButMissing)
        XCTAssertEqual(
            resolution.anchors,
            try XCTUnwrap(tableRule(of: table)).anchors,
            "A saved formula must re-hydrate its linked table's anchors from referenceTableFilmID."
        )
    }

    func testResolverReflectsEditedTableAnchorsWithoutTouchingFormula() throws {
        let table = eligibleTableFilm(id: "custom.table.curved", label: "Acme 100")
        let form = try XCTUnwrap(CustomFilmEditorFormState.creatingFormula(fromTable: table))
        guard case let .success(savedFormula) = form.validate(idGenerator: { "f-id" }) else {
            return XCTFail("seeded form must validate")
        }
        // Table edited after the formula was saved (same id, new anchors).
        let editedTable = tableFilm(
            id: table.id,
            label: "Acme 100",
            anchors: [(1, 2), (10, 50), (100, 600)],
            noCorrection: 0.5,
            sourceRange: 100
        )
        let resolution = CustomFilmReferenceTableResolver.resolve(for: savedFormula) { _ in editedTable }
        XCTAssertEqual(resolution.anchors, try XCTUnwrap(tableRule(of: editedTable)).anchors)
        XCTAssertEqual(
            resolution.anchors.first(where: { $0.meteredSeconds == 10 })?.correctedSeconds,
            50,
            "Reference anchors reflect the edited table (10→50)."
        )
    }

    func testResolverMarksMissingWhenLinkedTableDeleted() throws {
        let table = eligibleTableFilm(id: "custom.table.curved", label: "Acme 100")
        let form = try XCTUnwrap(CustomFilmEditorFormState.creatingFormula(fromTable: table))
        guard case let .success(savedFormula) = form.validate(idGenerator: { "f-id" }) else {
            return XCTFail("seeded form must validate")
        }
        let resolution = CustomFilmReferenceTableResolver.resolve(for: savedFormula) { _ in nil }
        XCTAssertTrue(resolution.isLinkedButMissing, "A deleted linked table marks the formula as linked-but-missing.")
        XCTAssertTrue(resolution.anchors.isEmpty)
    }

    func testResolverEmptyForUnlinkedFormula() {
        let unlinked = CustomFilmTestSupport.makeCustomFilm(id: "custom.formula")
        let resolution = CustomFilmReferenceTableResolver.resolve(for: unlinked) { _ in nil }
        XCTAssertFalse(resolution.isLinkedButMissing, "An unlinked formula is not 'missing' — it simply has no link.")
        XCTAssertTrue(resolution.anchors.isEmpty)
    }

    // MARK: - Fixtures

    private func eligibleTableFilm(id: String, label: String = "Custom Stock") -> FilmIdentity {
        tableFilm(id: id, label: label, anchors: [(1, 2), (10, 100), (100, 600)], noCorrection: 0.5, sourceRange: 100)
    }

    private func ineligibleTableFilm(id: String) -> FilmIdentity {
        tableFilm(id: id, label: "Short", anchors: [(2, 2), (10, 20)], noCorrection: 0.2, sourceRange: 10)
    }

    private func tableFilm(
        id: String,
        label: String,
        anchors: [(Double, Double)],
        noCorrection: Double,
        sourceRange: Double
    ) -> FilmIdentity {
        let profile = ReciprocityProfile(
            id: "\(id)-profile",
            name: "Custom table",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [
                .tableInterpolation(TableInterpolationReciprocityRule(
                    anchors: anchors.map { TableAnchor(meteredSeconds: $0.0, correctedSeconds: $0.1) },
                    noCorrectionThroughSeconds: noCorrection,
                    sourceRangeThroughSeconds: sourceRange
                )),
            ],
            userMetadata: UserEditableMetadata(customSourceType: .personalTest)
        )
        return FilmIdentity(
            id: id,
            kind: .custom,
            canonicalStockName: label,
            aliases: [],
            iso: 100,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: UserEditableMetadata(customSourceType: .personalTest)
        )
    }

    private func tableRule(of film: FilmIdentity) -> TableInterpolationReciprocityRule? {
        for rule in film.profiles.first?.rules ?? [] {
            if case let .tableInterpolation(table) = rule { return table }
        }
        return nil
    }
}
