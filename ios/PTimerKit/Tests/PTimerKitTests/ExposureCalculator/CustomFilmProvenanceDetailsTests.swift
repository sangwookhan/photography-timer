import XCTest
import PTimerKit
import PTimerCore

/// Details provenance coverage. Asserts the custom-only
/// multi-line provenance block exposes source type, formula
/// summary, range, and user notes — and that it never reads
/// like manufacturer-backed guidance.
@MainActor
final class CustomFilmProvenanceDetailsTests: XCTestCase {

    private let presenter = ReciprocityDetailsVocabularyPresenter()

    func test_customProvenance_listsSourceTypeFormulaRangeAndNotes() throws {
        let film = makeCustomFilm(
            sourceType: .personalTest,
            exponent: 1.30,
            noCorrectionThrough: 1.0,
            validThrough: 240.0,
            notes: ["Bracketed at 1s, 4s, 30s"]
        )
        let profile = try XCTUnwrap(film.profiles.first)
        let provenance = try XCTUnwrap(presenter.customProvenanceText(film: film, profile: profile))

        XCTAssertTrue(provenance.contains("Personal test"))
        XCTAssertTrue(provenance.contains("Tc"))
        XCTAssertTrue(provenance.contains("1.3"))
        XCTAssertTrue(provenance.contains("No correction through 1s"))
        XCTAssertTrue(provenance.contains("Source range through 4m"))
        XCTAssertTrue(provenance.contains("Bracketed at 1s, 4s, 30s"))
    }

    func test_customProvenance_doesNotPresentOfficialWording() throws {
        let film = makeCustomFilm(
            sourceType: .communityReference,
            exponent: 1.45,
            noCorrectionThrough: 1.0,
            validThrough: 120.0,
            notes: []
        )
        let profile = try XCTUnwrap(film.profiles.first)
        let provenance = try XCTUnwrap(presenter.customProvenanceText(film: film, profile: profile))
        let lowered = provenance.lowercased()
        XCTAssertFalse(lowered.contains("official"))
        XCTAssertFalse(lowered.contains("manufacturer"))
        XCTAssertFalse(lowered.contains("kodak"))
        XCTAssertFalse(lowered.contains("fuji"))
    }

    // MARK: - Structured custom-profile section

    /// The Details sheet renders custom-profile metadata as a
    /// dedicated section below the graph rather than as text inside
    /// the top result card. The section exposes one row per fact so
    /// each line is independently inspectable.
    func test_customProfileSection_emitsOneRowPerFact() throws {
        let film = makeCustomFilm(
            sourceType: .personalTest,
            exponent: 1.30,
            noCorrectionThrough: 1.0,
            validThrough: 240.0,
            notes: ["Bracketed at 1s, 4s, 30s"]
        )
        let profile = try XCTUnwrap(film.profiles.first)
        let section = try XCTUnwrap(
            presenter.customProfileSection(film: film, profile: profile)
        )
        XCTAssertEqual(section.title, "Custom profile")

        let titles = section.rows.map(\.title)
        // The formula itself is the Reciprocity Graph title
        // (canonical formula display); repeating it as a row here
        // would duplicate the same expression on the Details
        // sheet, so the section carries only the surrounding
        // provenance.
        XCTAssertEqual(titles, ["Source", "Range", "Notes"])
        XCTAssertFalse(
            section.rows.contains { $0.style == .formulaExpression },
            "Custom profile section must not duplicate the graph's formula text."
        )

        XCTAssertEqual(section.rows[0].value, "Personal test")
        // Range row renders as two stand-alone lines (PTIMER-84 polish).
        let rangeLines = section.rows[1].value.components(separatedBy: "\n")
        XCTAssertEqual(rangeLines.count, 2)
        XCTAssertEqual(rangeLines[0], "No correction through 1s")
        XCTAssertEqual(rangeLines[1], "Source range through 4m")
        XCTAssertEqual(section.rows[2].value, "Bracketed at 1s, 4s, 30s")
    }

    /// When the formula has no finite source-range upper bound, the
    /// Range row still renders both lines but the second line reads
    /// "Source range unlimited" so the user reads the confidence
    /// boundary explicitly rather than its absence.
    func test_customProfileSection_unlimitedSourceRange_rendersUnlimitedLine() throws {
        let film = makeCustomFilm(
            sourceType: .userDefined,
            exponent: 1.30,
            noCorrectionThrough: 1.0,
            validThrough: nil,
            notes: []
        )
        let profile = try XCTUnwrap(film.profiles.first)
        let section = try XCTUnwrap(
            presenter.customProfileSection(film: film, profile: profile)
        )
        guard let rangeRow = section.rows.first(where: { $0.title == "Range" }) else {
            return XCTFail("Custom profile section must include a Range row.")
        }
        let lines = rangeRow.value.components(separatedBy: "\n")
        XCTAssertEqual(lines, [
            "No correction through 1s",
            "Source range unlimited",
        ])
    }

    func test_customProfileSection_returnsNilForPresetProfile() throws {
        // Use a preset Provia 100F profile — official authority,
        // so the custom-profile section must not render.
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "Provia 100F" }
        )
        let profile = try XCTUnwrap(film.profiles.first)
        XCTAssertNil(presenter.customProfileSection(film: film, profile: profile))
    }

    func test_summaryDetailText_returnsNilForUserDefinedProfile() throws {
        // The top result card stays focused on the per-shot output
        // (Adjusted / Corrected / Status). Custom provenance now
        // belongs in the dedicated section below the graph, so the
        // detail line under Status must be empty for user-defined
        // profiles.
        let film = makeCustomFilm(
            sourceType: .personalTest,
            exponent: 1.30,
            noCorrectionThrough: 1.0,
            validThrough: 60.0,
            notes: []
        )
        let profile = try XCTUnwrap(film.profiles.first)
        let model = ReciprocityModel()
        let policyResult = model.evaluate(profile: profile, meteredExposureSeconds: 4)
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        XCTAssertNil(presenter.summaryDetailText(for: bindingState))
    }

    // PTIMER-159: the Details subtitle now names the active model
    // (profile name) rather than delegating to the authority label, so
    // the former `subtitleAuthorityLabel` presenter API was removed.

    // MARK: - Helpers

    private func makeCustomFilm(
        sourceType: CustomProfileSourceType,
        exponent: Double,
        noCorrectionThrough: Double,
        validThrough: Double?,
        notes: [String]
    ) -> FilmIdentity {
        let formula = ReciprocityFormula(
            exponent: exponent,
            noCorrectionThroughSeconds: noCorrectionThrough,
            sourceRangeThroughSeconds: validThrough
        )
        let profile = ReciprocityProfile(
            id: "custom-profile",
            name: "Custom",
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.formula(FormulaReciprocityRule(formula: formula))],
            notes: [],
            userMetadata: UserEditableMetadata(
                notes: notes,
                customSourceType: sourceType
            ),
            sourceEvidence: []
        )
        return FilmIdentity(
            id: "custom-film",
            kind: .custom,
            canonicalStockName: "Custom",
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: 100,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: UserEditableMetadata(customSourceType: sourceType)
        )
    }
}
