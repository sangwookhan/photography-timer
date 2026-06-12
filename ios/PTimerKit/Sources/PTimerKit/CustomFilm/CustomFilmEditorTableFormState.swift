import Foundation
import PTimerCore

/// Which calculation rule the custom film editor authors
/// (PTIMER-178). A custom profile carries exactly one rule —
/// formula XOR tableInterpolation — and a saved profile never
/// converts between the two kinds; the Create flow picks the kind
/// once and the Edit flow opens with the saved kind fixed.
public enum CustomFilmCalculationInputKind: String, Equatable, Hashable {
    case formula
    case table

    public var displayLabel: String {
        switch self {
        case .formula: return "Formula"
        case .table: return "Table"
        }
    }
}

/// One pending Tm/Tc anchor row in the table editor. Both fields
/// stay `String` so the SwiftUI form binds directly; `id` exists
/// only for stable `ForEach` identity while rows are added and
/// removed — it is never persisted.
public struct CustomFilmTableAnchorRowInput: Equatable, Hashable, Identifiable {
    public let id: UUID
    public var meteredText: String
    public var correctedText: String

    public init(
        id: UUID = UUID(),
        meteredText: String = "",
        correctedText: String = ""
    ) {
        self.id = id
        self.meteredText = meteredText
        self.correctedText = correctedText
    }

    /// A fully blank row is ignored by validation and build (it is
    /// a filler row the photographer has not used yet); a partially
    /// filled row is an error.
    public var isBlank: Bool {
        meteredText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension CustomFilmEditorFormState {

    /// Editor affordance limit on table rows. A soft UI cap, not a
    /// validation rule — the sanitizer and domain contract accept
    /// any anchor count ≥ 2.
    public static let tableRowSoftCap = 20

    /// Rows seeded when the Create flow switches to the table kind
    /// (the validation minimum, so the photographer sees the
    /// required shape immediately).
    public static let newTableRowSeedCount = 2

    /// Divisor for the suggested no-correction default: the first
    /// anchor's metered time divided by 10 (first anchor 1 s →
    /// 0.1 s, 10 s → 1 s).
    private static let defaultNoCorrectionDivisor: Double = 10

    /// Pure-value kind switch for the Create flow. Switching to
    /// `.table` seeds the minimum rows and clears the formula-mode
    /// no-correction default ("1") so the table-derived suggestion
    /// applies instead; switching back restores the formula default
    /// when the field is empty. A typed (non-default) no-correction
    /// value survives the toggle in both directions.
    public func switching(
        toCalculationKind kind: CustomFilmCalculationInputKind
    ) -> CustomFilmEditorFormState {
        guard kind != calculationInputKind else { return self }
        var next = self
        next.calculationInputKind = kind
        switch kind {
        case .table:
            if next.tableRows.isEmpty {
                next.tableRows = (0..<Self.newTableRowSeedCount).map { _ in
                    CustomFilmTableAnchorRowInput()
                }
            }
            if next.noCorrectionThroughText
                .trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
                next.noCorrectionThroughText = ""
            }
        case .formula:
            if next.noCorrectionThroughText
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                next.noCorrectionThroughText = "1"
            }
        }
        return next
    }

    // MARK: - Parsed table values

    /// Fully validated table input: ascending anchors plus the
    /// resolved boundaries. The same struct backs `validate()`'s
    /// table branch, the preview surfaces, and the save path so the
    /// preview can never disagree with what Save would persist.
    public struct ParsedTableInput: Equatable {
        public let anchors: [TableAnchor]
        public let noCorrectionThroughSeconds: Double
        /// Derived, not edited: the last anchor's metered time.
        public let sourceRangeThroughSeconds: Double
    }

    /// First valid metered time scanned from the rows, used to
    /// derive the suggested no-correction default while the
    /// photographer is still typing later rows.
    public var firstTableAnchorMeteredSeconds: Double? {
        for row in tableRows where !row.isBlank {
            if let anchor = Self.parsedAnchor(from: row) {
                return anchor.meteredSeconds
            }
            return nil
        }
        return nil
    }

    /// Suggested no-correction default (`firstAnchorMetered / 10`).
    /// The editor shows it as the field placeholder; an empty field
    /// resolves to this value at validate/save so the suggestion
    /// re-derives whenever the first anchor changes without ever
    /// overwriting a value the photographer typed.
    public var defaultTableNoCorrectionSeconds: Double? {
        firstTableAnchorMeteredSeconds.map { $0 / Self.defaultNoCorrectionDivisor }
    }

    /// Derived source-range boundary (`max(anchor.meteredSeconds)`,
    /// i.e. the last anchor of the validated ascending table).
    /// `nil` until the rows form a valid table. Read-only in the
    /// editor — PTIMER-178 does not expose source range as an
    /// editable field.
    public var derivedTableSourceRangeSeconds: Double? {
        parsedTableAnchors()?.last?.meteredSeconds
    }

    /// Anchors parsed from the non-blank rows, or `nil` when any
    /// non-blank row is invalid, the metered times are not strictly
    /// ascending, any corrected time is shorter than its metered
    /// time, or fewer than two anchors remain.
    public func parsedTableAnchors() -> [TableAnchor]? {
        var anchors: [TableAnchor] = []
        for row in tableRows where !row.isBlank {
            guard let anchor = Self.parsedAnchor(from: row),
                  anchor.correctedSeconds >= anchor.meteredSeconds else {
                return nil
            }
            if let previous = anchors.last,
               anchor.meteredSeconds <= previous.meteredSeconds {
                return nil
            }
            anchors.append(anchor)
        }
        return anchors.count >= 2 ? anchors : nil
    }

    /// Strict full-table parse mirroring `validate()`'s table
    /// branch. Returns `nil` whenever Save would be disabled, so
    /// preview surfaces stay honest with the Save guard.
    public func parsedTableInput() -> ParsedTableInput? {
        guard let anchors = parsedTableAnchors(),
              let first = anchors.first,
              let last = anchors.last else {
            return nil
        }
        guard let noCorrection = resolvedTableNoCorrectionSeconds(
            firstAnchorMeteredSeconds: first.meteredSeconds
        ) else {
            return nil
        }
        return ParsedTableInput(
            anchors: anchors,
            noCorrectionThroughSeconds: noCorrection,
            sourceRangeThroughSeconds: last.meteredSeconds
        )
    }

    /// The rule the saved profile would carry, synthesized from the
    /// current form. `nil` when the form cannot save.
    public func parsedTableInterpolationRule() -> TableInterpolationReciprocityRule? {
        guard let parsed = parsedTableInput() else { return nil }
        return TableInterpolationReciprocityRule(
            anchors: parsed.anchors,
            noCorrectionThroughSeconds: parsed.noCorrectionThroughSeconds,
            sourceRangeThroughSeconds: parsed.sourceRangeThroughSeconds
        )
    }

    /// Preview gate for the table kind — mirrors
    /// `formulaCanRenderPreview` on the formula side.
    public var tableCanRenderPreview: Bool {
        parsedTableInterpolationRule() != nil
    }

    /// Resolves the editable no-correction field against the table
    /// rules: empty falls back to the derived suggestion; a typed
    /// value must be a finite, strictly positive duration strictly
    /// below the first anchor's metered time. Stricter than the
    /// domain contract's `>= 0` — the table evaluator feeds the
    /// no-correction knee into log-log interpolation, so `0` must
    /// never be saved (`log10(0)` would poison the first segment).
    private func resolvedTableNoCorrectionSeconds(
        firstAnchorMeteredSeconds: Double
    ) -> Double? {
        switch CustomFilmDurationParser.parse(noCorrectionThroughText) {
        case .empty:
            return firstAnchorMeteredSeconds / Self.defaultNoCorrectionDivisor
        case .seconds(let value)
            where value.isFinite && value > 0 && value < firstAnchorMeteredSeconds:
            return value
        case .seconds, .unlimited, .none:
            return nil
        }
    }

    private static func parsedAnchor(
        from row: CustomFilmTableAnchorRowInput
    ) -> TableAnchor? {
        guard let metered = parsedPositiveSeconds(row.meteredText),
              let corrected = parsedPositiveSeconds(row.correctedText) else {
            return nil
        }
        return TableAnchor(meteredSeconds: metered, correctedSeconds: corrected)
    }

    private static func parsedPositiveSeconds(_ text: String) -> Double? {
        switch CustomFilmDurationParser.parse(text) {
        case .seconds(let value) where value.isFinite && value > 0:
            return value
        case .empty, .seconds, .unlimited, .none:
            return nil
        }
    }

    // MARK: - Row-level validation wording

    /// Concise inline reason rendered under one anchor row, or
    /// `nil` when the row is fine (or fully blank — blank rows are
    /// filler, not errors). Mirrors the per-field hints the formula
    /// card uses so the table card reads with the same vocabulary.
    public func tableRowValidationReason(
        at index: Int,
        isEditing: Bool
    ) -> String? {
        guard tableRows.indices.contains(index) else { return nil }
        if !isEditing, isUntouchedNewForm() { return nil }
        let row = tableRows[index]
        if row.isBlank { return nil }

        let meteredBlank = row.meteredText
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let correctedBlank = row.correctedText
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if meteredBlank { return "Tm is required" }
        if correctedBlank { return "Tc is required" }
        guard let metered = Self.parsedPositiveSeconds(row.meteredText) else {
            return "Tm must be > 0"
        }
        guard let corrected = Self.parsedPositiveSeconds(row.correctedText) else {
            return "Tc must be > 0"
        }
        if corrected < metered { return "Tc must be ≥ Tm" }
        if let previous = lastValidAnchorMetered(before: index),
           metered <= previous {
            return "Tm must increase down the table"
        }
        return nil
    }

    private func lastValidAnchorMetered(before index: Int) -> Double? {
        var lastMetered: Double?
        for row in tableRows.prefix(index) where !row.isBlank {
            guard let anchor = Self.parsedAnchor(from: row),
                  anchor.correctedSeconds >= anchor.meteredSeconds else { continue }
            if let current = lastMetered, anchor.meteredSeconds <= current { continue }
            lastMetered = anchor.meteredSeconds
        }
        return lastMetered
    }

    // MARK: - Validate + build (table branch)

    /// Table-kind counterpart of `validate()`. Same identity rules
    /// as the formula path; the calculation portion validates the
    /// anchor rows and boundaries per PTIMER-178 and builds a
    /// profile whose single rule is `.tableInterpolation`, with
    /// display-only `sourceEvidence` copies regenerated from the
    /// same rows.
    func validateTable(
        idGenerator: () -> String
    ) -> Result<FilmIdentity, CustomFilmEditorValidationErrors> {
        var errors: Set<CustomFilmEditorValidationError> = []

        let trimmedFilmLabel = filmLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedFilmLabel.isEmpty {
            errors.insert(.missingFilmLabel)
        }
        let iso = parseISO(errors: &errors)

        let anchors = validatedTableAnchors(errors: &errors)
        var noCorrection: Double?
        if let firstAnchor = anchors?.first {
            noCorrection = resolvedTableNoCorrectionSeconds(
                firstAnchorMeteredSeconds: firstAnchor.meteredSeconds
            )
            if noCorrection == nil {
                errors.insert(.invalidNoCorrectionThrough)
            }
        } else {
            // Without a valid first anchor the upper bound cannot be
            // checked, but a syntactically broken or non-positive
            // entry is already reportable.
            switch CustomFilmDurationParser.parse(noCorrectionThroughText) {
            case .empty:
                break
            case .seconds(let value) where value.isFinite && value > 0:
                break
            case .seconds, .unlimited, .none:
                errors.insert(.invalidNoCorrectionThrough)
            }
        }

        guard errors.isEmpty,
              let iso,
              let anchors,
              let lastAnchor = anchors.last,
              let noCorrection else {
            return .failure(CustomFilmEditorValidationErrors(errors))
        }

        let resolvedProfileName = Self.composeDisplayName(
            manufacturer: manufacturerText,
            label: trimmedFilmLabel,
            iso: iso
        )
        let fallbackName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule = TableInterpolationReciprocityRule(
            anchors: anchors,
            noCorrectionThroughSeconds: noCorrection,
            sourceRangeThroughSeconds: lastAnchor.meteredSeconds
        )
        // Calculation anchors live ONLY on the rule; the
        // `sourceEvidence` rows below are display-only copies for
        // the Sources card / graph markers, regenerated from the
        // same editor rows on every save so the two representations
        // cannot drift. The calculation policy never reads them.
        let profile = ReciprocityProfile(
            id: idGenerator(),
            name: resolvedProfileName.isEmpty
                ? (fallbackName.isEmpty ? trimmedFilmLabel : fallbackName)
                : resolvedProfileName,
            source: Self.customSourceProvenance(),
            rules: [.tableInterpolation(rule)],
            userMetadata: customProfileMetadata(),
            sourceEvidence: Self.displayEvidenceRows(for: anchors)
        )
        let film = assembleCustomFilm(
            profile: profile,
            filmLabel: trimmedFilmLabel,
            iso: iso,
            idGenerator: idGenerator
        )
        return .success(film)
    }

    /// Anchor scan for `validateTable`. Inserts the coarse error
    /// cases (`.invalidTableAnchors` / `.insufficientTableAnchors`)
    /// and returns the ascending anchor list only when every
    /// non-blank row participates cleanly.
    private func validatedTableAnchors(
        errors: inout Set<CustomFilmEditorValidationError>
    ) -> [TableAnchor]? {
        var anchors: [TableAnchor] = []
        var rowsValid = true
        for row in tableRows where !row.isBlank {
            guard let anchor = Self.parsedAnchor(from: row),
                  anchor.correctedSeconds >= anchor.meteredSeconds else {
                rowsValid = false
                continue
            }
            if let previous = anchors.last,
               anchor.meteredSeconds <= previous.meteredSeconds {
                rowsValid = false
                continue
            }
            anchors.append(anchor)
        }
        if !rowsValid {
            errors.insert(.invalidTableAnchors)
            return nil
        }
        if anchors.count < 2 {
            errors.insert(.insufficientTableAnchors)
            return nil
        }
        return anchors
    }

    /// Display-only `sourceEvidence` copies of the table anchors,
    /// in the same row shape the shipped official table profiles
    /// use (`.exactSeconds` selector + one corrected-time exposure
    /// adjustment) so the existing Sources card and graph anchor
    /// markers render custom tables with no new presentation code.
    public static func displayEvidenceRows(
        for anchors: [TableAnchor]
    ) -> [ReciprocitySourceEvidenceRow] {
        anchors.map { anchor in
            ReciprocitySourceEvidenceRow(
                meteredExposure: .exactSeconds(anchor.meteredSeconds),
                adjustments: [
                    .exposure(.correctedTime(CorrectedTimeMapping(
                        meteredSeconds: anchor.meteredSeconds,
                        correctedSeconds: anchor.correctedSeconds
                    ))),
                ]
            )
        }
    }

    // MARK: - Edit-flow prefill (table branch)

    /// Rebuilds editor state from a saved custom table film so the
    /// Edit flow prefills the rows. Counterpart of the formula
    /// branch inside `from(film:)`; returns `nil` when the profile
    /// carries no table rule.
    static func fromTableFilm(
        _ film: FilmIdentity,
        profile: ReciprocityProfile
    ) -> CustomFilmEditorFormState? {
        guard let tableRule = profile.rules.compactMap({ rule -> TableInterpolationReciprocityRule? in
            if case .tableInterpolation(let r) = rule { return r }
            return nil
        }).first else {
            return nil
        }
        let seed = recoveredIdentitySeed(film: film, profile: profile)
        let rows = tableRule.sortedAnchors.map { anchor in
            CustomFilmTableAnchorRowInput(
                meteredText: Self.formatNumeric(anchor.meteredSeconds),
                correctedText: Self.formatNumeric(anchor.correctedSeconds)
            )
        }
        return CustomFilmEditorFormState(
            profileName: profile.name,
            filmLabel: seed.labelText,
            isoText: "\(film.iso)",
            sourceType: seed.sourceType,
            notes: seed.notesValue,
            noCorrectionThroughText: Self.formatNumeric(tableRule.noCorrectionThroughSeconds),
            manufacturerText: seed.manufacturerText,
            referenceURLText: seed.referenceURLText,
            calculationInputKind: .table,
            tableRows: rows
        )
    }
}
