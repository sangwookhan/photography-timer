import Foundation

/// Pending input fields for the custom film / profile editor. All
/// fields are stored as `String` (and one enum) so the SwiftUI form
/// can bind directly without intermediate parsing. The struct is a
/// pure value — every mutation comes from a TextField/Picker binding
/// on the editor view — and the `validate()` method is the only
/// path that produces a domain `FilmIdentity`.
///
/// The editor is intentionally minimal: power-law formula only,
/// no source-evidence rows, no per-rule table input. The
/// validation surface is the boundary the spec names as "reject
/// invalid formula input" — domain types past this point can
/// trust that exponents are positive/finite, ISO is a positive
/// integer, and identity strings are non-empty.
struct CustomFilmEditorFormState: Equatable {
    var profileName: String
    var filmLabel: String
    var isoText: String
    var sourceType: CustomProfileSourceType
    var notes: String
    var exponentText: String
    /// Metered-exposure anchor for the
    /// `Tc = baseTc · (Tm / baseTm)^exponent + offset` formula.
    /// Default `"1"` represents the unanchored exponent-only
    /// form `Tc = Tm^exponent + offset` (preview surfaces
    /// simplify the display when both anchors equal `1`).
    var baseTmText: String
    /// Corrected-exposure anchor paired with `baseTmText`. Same
    /// default `"1"`.
    var baseTcText: String
    var offsetSecondsText: String
    /// Metered exposures up to this many seconds receive
    /// `Tc = Tm` (no correction) instead of the formula. Defaults
    /// to "1" because reciprocity behavior is a long-exposure
    /// concept and sub-1s adjustments would be misleading.
    var noCorrectionThroughText: String
    /// Metered exposures above this many seconds fall outside the
    /// formula's stated source range. Optional: empty /
    /// "Unlimited" means the formula extrapolates upward without
    /// bound (the saved `sourceRangeThroughSeconds` is `nil`).
    var validThroughText: String
    /// Photographer-typed manufacturer string. Stored on
    /// `UserEditableMetadata.customManufacturer`, not on
    /// `FilmIdentity.manufacturer`, so the picker keeps custom
    /// films in the "Custom films" group.
    var manufacturerText: String
    /// Optional reference URL the photographer recorded; lives at
    /// the bottom of the editor and round-trips through
    /// `UserEditableMetadata.referenceURL`.
    var referenceURLText: String

    init(
        profileName: String = "",
        filmLabel: String = "",
        isoText: String = "",
        sourceType: CustomProfileSourceType = .userDefined,
        notes: String = "",
        exponentText: String = "",
        baseTmText: String = "1",
        baseTcText: String = "1",
        offsetSecondsText: String = "",
        noCorrectionThroughText: String = "1",
        validThroughText: String = "",
        manufacturerText: String = "",
        referenceURLText: String = ""
    ) {
        self.profileName = profileName
        self.filmLabel = filmLabel
        self.isoText = isoText
        self.sourceType = sourceType
        self.notes = notes
        self.exponentText = exponentText
        self.baseTmText = baseTmText
        self.baseTcText = baseTcText
        self.offsetSecondsText = offsetSecondsText
        self.noCorrectionThroughText = noCorrectionThroughText
        self.validThroughText = validThroughText
        self.manufacturerText = manufacturerText
        self.referenceURLText = referenceURLText
    }
}

/// Field-level reason a candidate form state failed validation.
/// Returned as an unordered set so the editor can highlight every
/// invalid field on Save rather than only the first one.
enum CustomFilmEditorValidationError: Error, Equatable, Hashable {
    /// Retired — the photographer's `Manufacturer + Label + ISO`
    /// composition drives the auto-generated profile name. The
    /// hidden `profileName` text field stays for backward compat
    /// but the validator never raises this case anymore.
    case missingProfileName
    case missingFilmLabel
    case invalidISO
    case missingFormulaExponent
    case invalidFormulaExponent
    /// Retired in favour of `.invalidBaseTm` / `.invalidBaseTc`.
    /// Kept in the enum so stored references in callers compile,
    /// but the validator no longer raises it.
    case invalidFormulaCoefficient
    case invalidBaseTm
    case invalidBaseTc
    case invalidFormulaOffset
    case invalidNoCorrectionThrough
    /// Retired — empty / "Unlimited" is now the documented
    /// default state. Kept so callers that reference the case in
    /// `Set.contains` compile.
    case missingValidThrough
    case invalidValidThrough
    /// The photographer's combination of anchors/exponent/offset
    /// would produce a corrected exposure shorter than the
    /// metered exposure inside the formula's usable range. The
    /// editor blocks save so the calculator never emits
    /// misleading "long-exposure correction makes the shot
    /// shorter" guidance.
    case formulaShortensExposure
}

/// `Result` requires the failure type to conform to `Error`. `Set`
/// does not, so the validate path wraps the collected reasons in
/// this thin envelope. Hashable + Equatable conformance preserves
/// test ergonomics for asserting against the full reason set.
struct CustomFilmEditorValidationErrors: Error, Equatable, Hashable {
    let errors: Set<CustomFilmEditorValidationError>

    init(_ errors: Set<CustomFilmEditorValidationError>) {
        self.errors = errors
    }

    func contains(_ error: CustomFilmEditorValidationError) -> Bool {
        errors.contains(error)
    }

    var isEmpty: Bool { errors.isEmpty }
}

extension CustomFilmEditorFormState {
    /// Rebuilds editor state from an existing custom `FilmIdentity`
    /// so the Edit flow can prefill every field. Returns `nil` for
    /// non-custom or otherwise unsupported shapes (the editor falls
    /// back to a blank Create form in that defensive case). Numeric
    /// fields render with the same `trim` logic the formula summary
    /// uses so a round-tripped value reads "1.3" instead of
    /// "1.300000".
    static func from(film: FilmIdentity) -> CustomFilmEditorFormState? {
        guard film.kind == .custom,
              let profile = film.profiles.first,
              profile.source.authority == .userDefined,
              let formulaRule = profile.rules.compactMap({ rule -> FormulaReciprocityRule? in
                  if case .formula(let r) = rule { return r }
                  return nil
              }).first else {
            return nil
        }
        let formula = formulaRule.formula
        let sourceType = profile.userMetadata?.customSourceType
            ?? film.userMetadata?.customSourceType
            ?? .userDefined
        let notesValue = profile.userMetadata?.notes.first
            ?? film.userMetadata?.notes.first
            ?? ""

        // The shared formula carries the range boundaries on the
        // formula itself; the editor reads them directly so an
        // Edit round-trip preserves whatever the photographer
        // saved.
        let noCorrectionThrough = formula.noCorrectionThroughSeconds
        let validThrough = formula.sourceRangeThroughSeconds

        // Recover the manufacturer and label from
        // `userMetadata.customManufacturer` and the canonical
        // stock name. Older payloads stored the full name in
        // `canonicalStockName` only; this lookup detects the
        // manufacturer prefix and splits it back into separate
        // fields so the editor surfaces a clean Label row instead
        // of leaking the manufacturer string into it.
        let storedManufacturer = profile.userMetadata?.customManufacturer
            ?? film.userMetadata?.customManufacturer
        let manufacturerText = storedManufacturer ?? ""
        let labelText: String = {
            if let storedManufacturer,
               film.canonicalStockName.hasPrefix("\(storedManufacturer) ") {
                return String(film.canonicalStockName.dropFirst(storedManufacturer.count + 1))
            }
            return film.canonicalStockName
        }()
        let referenceURLText = profile.userMetadata?.referenceURL
            ?? film.userMetadata?.referenceURL
            ?? ""

        // The shared formula stores the anchor pair on the
        // formula directly: `referenceMeteredTimeSeconds` is the
        // editor's Base Tm and `coefficientSeconds` is its Base
        // Tc.
        let baseTm = formula.referenceMeteredTimeSeconds
        let baseTc = formula.coefficientSeconds
        let offsetText = abs(formula.offsetSeconds) < 1e-9
            ? ""
            : Self.formatNumeric(formula.offsetSeconds)
        return CustomFilmEditorFormState(
            profileName: profile.name,
            filmLabel: labelText,
            isoText: "\(film.iso)",
            sourceType: sourceType,
            notes: notesValue,
            exponentText: Self.formatNumeric(formula.exponent),
            baseTmText: Self.formatNumeric(baseTm),
            baseTcText: Self.formatNumeric(baseTc),
            offsetSecondsText: offsetText,
            noCorrectionThroughText: Self.formatNumeric(noCorrectionThrough),
            validThroughText: validThrough.map(Self.formatNumeric) ?? "",
            manufacturerText: manufacturerText,
            referenceURLText: referenceURLText
        )
    }

    /// Compact numeric rendering shared by `from(film:)` so an edit
    /// round-trip reads back the same exponent/coefficient/offset
    /// strings the formula summary uses.
    private static func formatNumeric(_ value: Double) -> String {
        let formatted = String(format: "%.4f", value)
        var trimmed = formatted
        while trimmed.contains(".") && (trimmed.hasSuffix("0") || trimmed.hasSuffix(".")) {
            trimmed.removeLast()
            if trimmed.hasSuffix(".") {
                trimmed.removeLast()
                break
            }
        }
        return trimmed
    }
}

extension CustomFilmEditorFormState {
    /// Lower bound for accepted ISO box-speed values. 1 covers
    /// long-discontinued slow film and the lowest practical pinhole
    /// targets; below 1 the calculator's metered exposure formatter
    /// would never produce meaningful guidance.
    static let minISO = 1
    /// Upper bound is generous — current commercial stocks top out
    /// near 3200; the cap exists to reject obvious typos / overflow,
    /// not to police photographic realism.
    static let maxISO = 100_000

    /// Validates and converts the pending input into a fully-formed
    /// custom `FilmIdentity`. Returns either the new identity or the
    /// unordered set of field-level reasons it failed. The id is
    /// supplied by the caller so the persistence layer can drive
    /// stable identifiers without the form state having to reach
    /// for a UUID generator at validation time.
    func validate(
        idGenerator: () -> String = { UUID().uuidString }
    ) -> Result<FilmIdentity, CustomFilmEditorValidationErrors> {
        var errors: Set<CustomFilmEditorValidationError> = []

        let trimmedFilmLabel = filmLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedFilmLabel.isEmpty {
            errors.insert(.missingFilmLabel)
        }
        let iso = parseISO(errors: &errors)
        let exponent = parseExponent(errors: &errors)
        let baseTm = parseAnchor(
            baseTmText,
            invalidError: .invalidBaseTm,
            errors: &errors
        )
        let baseTc = parseAnchor(
            baseTcText,
            invalidError: .invalidBaseTc,
            errors: &errors
        )
        let offsetSeconds = optionalFinite(
            offsetSecondsText,
            invalidError: .invalidFormulaOffset,
            errors: &errors
        )
        let noCorrectionThrough = parseNoCorrectionThrough(errors: &errors)
        let validThrough = parseValidThrough(
            noCorrectionThrough: noCorrectionThrough,
            errors: &errors
        )

        if let exponent,
           let baseTm,
           let baseTc,
           let noCorrectionThrough,
           !CustomFilmFormulaGuard.passesUsableRangeCheck(
               .init(
                   exponent: exponent,
                   referenceMeteredTimeSeconds: baseTm,
                   coefficientSeconds: baseTc,
                   offsetSeconds: offsetSeconds ?? 0.0,
                   noCorrectionThroughSeconds: noCorrectionThrough,
                   sourceRangeThroughSeconds: validThrough
               )
           ) {
            errors.insert(.formulaShortensExposure)
        }

        guard errors.isEmpty,
              let exponent,
              let iso,
              let baseTm,
              let baseTc,
              let noCorrectionThrough else {
            return .failure(CustomFilmEditorValidationErrors(errors))
        }

        // The editor does not surface a separate profile-name
        // field; the auto-generated `Manufacturer + Label · ISO N`
        // string drives both the user-facing display name and the
        // internal `ReciprocityProfile.name`. The `profileName`
        // form field stays only as a fallback for callers that
        // still set it explicitly.
        let resolvedProfileName = Self.composeDisplayName(
            manufacturer: manufacturerText,
            label: trimmedFilmLabel,
            iso: iso
        )
        let fallbackName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let film = buildFilmIdentity(
            ValidatedInput(
                profileName: resolvedProfileName.isEmpty
                    ? (fallbackName.isEmpty ? trimmedFilmLabel : fallbackName)
                    : resolvedProfileName,
                filmLabel: trimmedFilmLabel,
                iso: iso,
                exponent: exponent,
                baseTm: baseTm,
                baseTc: baseTc,
                offsetSeconds: offsetSeconds,
                noCorrectionThrough: noCorrectionThrough,
                validThrough: validThrough
            ),
            idGenerator: idGenerator
        )
        return .success(film)
    }

    /// The canonical display-name composer used by both the
    /// editor's auto-generated profile name and the editor view's
    /// header text. Same rule applied in one place so the runtime
    /// / Details / timer surfaces all read the same string for a
    /// given (manufacturer, label, ISO) triple.
    static func composeDisplayName(
        manufacturer: String,
        label: String,
        iso: Int?
    ) -> String {
        let trimmedManufacturer = manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameParts = [trimmedManufacturer, trimmedLabel].filter { !$0.isEmpty }
        let nameJoined = nameParts.joined(separator: " ")
        let isoSegment = iso.map { "ISO \($0)" } ?? ""
        let segments = [nameJoined, isoSegment].filter { !$0.isEmpty }
        return segments.joined(separator: " · ")
    }

    /// Parses an anchor field (`baseTmText` / `baseTcText`).
    /// Empty input falls back to the documented `1` default so the
    /// editor's default state behaves like an exponent-only
    /// formula; non-empty, non-finite, or non-positive input
    /// raises the matching error so the editor surfaces it.
    /// Accepts the same duration shapes (`100`, `100s`, `5m`,
    /// `1h`) as the application-range fields so the photographer
    /// can write `0.1s` for a base anchor without ambiguity.
    /// "Unlimited" makes no sense for an anchor and is rejected.
    /// Empty input still falls back to the documented `1` default.
    private func parseAnchor(
        _ text: String,
        invalidError: CustomFilmEditorValidationError,
        errors: inout Set<CustomFilmEditorValidationError>
    ) -> Double? {
        switch CustomFilmDurationParser.parse(text) {
        case .empty:
            return 1.0
        case .seconds(let value) where value.isFinite && value > 0:
            return value
        case .seconds, .unlimited, .none:
            errors.insert(invalidError)
            return nil
        }
    }

    private func parseNoCorrectionThrough(
        errors: inout Set<CustomFilmEditorValidationError>
    ) -> Double? {
        switch CustomFilmDurationParser.parse(noCorrectionThroughText) {
        case .empty:
            return 1.0
        case .unlimited:
            // "Unlimited" makes no sense for the no-correction
            // threshold (it would skip the formula entirely);
            // surface as invalid.
            errors.insert(.invalidNoCorrectionThrough)
            return nil
        case .seconds(let value) where value >= 0:
            return value
        case .seconds, .none:
            errors.insert(.invalidNoCorrectionThrough)
            return nil
        }
    }

    /// An empty / "Unlimited" entry means the formula has no upper
    /// bound. The validator never raises `.missingValidThrough` —
    /// the field is optional. Non-empty values still have to be
    /// finite, positive, and strictly greater than
    /// `noCorrectionThrough`.
    private func parseValidThrough(
        noCorrectionThrough: Double?,
        errors: inout Set<CustomFilmEditorValidationError>
    ) -> Double? {
        switch CustomFilmDurationParser.parse(validThroughText) {
        case .empty, .unlimited:
            return nil
        case .seconds(let parsed) where parsed.isFinite && parsed > 0:
            if let noCorrectionThrough, parsed <= noCorrectionThrough {
                errors.insert(.invalidValidThrough)
                return nil
            }
            return parsed
        case .seconds, .none:
            errors.insert(.invalidValidThrough)
            return nil
        }
    }

    /// Bundle of validated, type-safe fields handed to
    /// `buildFilmIdentity`. The bundling exists so the build
    /// function stays under the swiftlint parameter-count limit
    /// without leaking raw `String` fields past the validation
    /// boundary.
    private struct ValidatedInput {
        let profileName: String
        let filmLabel: String
        let iso: Int
        let exponent: Double
        let baseTm: Double
        let baseTc: Double
        let offsetSeconds: Double?
        let noCorrectionThrough: Double
        /// `nil` when the photographer left the field blank /
        /// "Unlimited" — the saved formula's
        /// `sourceRangeThroughSeconds` is then `nil`.
        let validThrough: Double?
    }

    private func parseISO(errors: inout Set<CustomFilmEditorValidationError>) -> Int? {
        let trimmed = isoText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = Int(trimmed), (Self.minISO...Self.maxISO).contains(parsed) {
            return parsed
        }
        errors.insert(.invalidISO)
        return nil
    }

    private func parseExponent(errors: inout Set<CustomFilmEditorValidationError>) -> Double? {
        let trimmed = exponentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errors.insert(.missingFormulaExponent)
            return nil
        }
        if let parsed = Double(trimmed), parsed.isFinite, parsed > 0 {
            return parsed
        }
        errors.insert(.invalidFormulaExponent)
        return nil
    }

    private func buildFilmIdentity(
        _ input: ValidatedInput,
        idGenerator: () -> String
    ) -> FilmIdentity {
        // Custom profiles produce the same shared
        // `ReciprocityFormula` shape preset profiles use, so the
        // runtime evaluator, the Details graph presenter, the
        // equation formatter, and the timer identity summary all
        // read one schema. Editor UI labels map onto the shared
        // field names verbatim:
        //
        //   Base Tm                → referenceMeteredTimeSeconds
        //   Base Tc                → coefficientSeconds
        //   Exponent               → exponent
        //   Offset                 → offsetSeconds
        //   No correction up to    → noCorrectionThroughSeconds
        //   Source range through   → sourceRangeThroughSeconds
        //
        // `sourceRangeThroughSeconds` is a confidence boundary
        // (not a calculation stop). Inputs strictly above it still
        // compute a corrected exposure; the policy evaluator
        // surfaces them as `unsupportedFormulaOutsideSourceRange`
        // so the Details / timer surfaces flag the prediction
        // as beyond the photographer's stated source range.
        let formula = ReciprocityFormula(
            formulaFamily: .modifiedSchwarzschild,
            coefficientSeconds: input.baseTc,
            referenceMeteredTimeSeconds: input.baseTm,
            exponent: input.exponent,
            offsetSeconds: input.offsetSeconds ?? 0,
            noCorrectionThroughSeconds: input.noCorrectionThrough,
            sourceRangeThroughSeconds: input.validThrough
        )
        let formulaRule = FormulaReciprocityRule(formula: formula)

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteList = trimmedNotes.isEmpty ? [] : [trimmedNotes]
        let trimmedManufacturer = manufacturerText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let manufacturerForMetadata = trimmedManufacturer.isEmpty ? nil : trimmedManufacturer
        let trimmedURL = referenceURLText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let urlForMetadata = trimmedURL.isEmpty ? nil : trimmedURL
        let profileMetadata = UserEditableMetadata(
            notes: noteList,
            customSourceType: sourceType,
            customManufacturer: manufacturerForMetadata,
            referenceURL: urlForMetadata
        )
        let profile = ReciprocityProfile(
            id: idGenerator(),
            name: input.profileName,
            source: ReciprocitySourceProvenance(
                kind: .userDefined,
                authority: .userDefined,
                confidence: .unknown,
                publisher: ""
            ),
            rules: [.formula(formulaRule)],
            userMetadata: profileMetadata
        )
        let filmMetadata = UserEditableMetadata(
            customSourceType: sourceType,
            customManufacturer: manufacturerForMetadata,
            referenceURL: urlForMetadata
        )
        // Compose `canonicalStockName` from manufacturer + label so
        // every downstream surface (selector primary text, timer
        // identity, Details title) reads the full film name. The
        // top-level `FilmIdentity.manufacturer` stays `nil` so the
        // picker keeps custom rows in the "Custom films" section
        // instead of merging them with preset manufacturer groups.
        let canonical = manufacturerForMetadata
            .map { "\($0) \(input.filmLabel)" }
            ?? input.filmLabel
        return FilmIdentity(
            id: idGenerator(),
            kind: .custom,
            canonicalStockName: canonical,
            manufacturer: nil,
            brandLabel: nil,
            aliases: [],
            iso: input.iso,
            productionStatus: .unknown,
            profiles: [profile],
            userMetadata: filmMetadata
        )
    }

    private func optionalFinitePositive(
        _ text: String,
        invalidError: CustomFilmEditorValidationError,
        errors: inout Set<CustomFilmEditorValidationError>
    ) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let value = Double(trimmed), value.isFinite, value > 0 {
            return value
        }
        errors.insert(invalidError)
        return nil
    }

    /// Offset accepts the duration parser's `.seconds` case
    /// (`100`, `100s`, `5m`, `1h`) but rejects `Unlimited`. Empty
    /// stays optional (the editor's documented 0s default applies
    /// in the build path).
    private func optionalFinite(
        _ text: String,
        invalidError: CustomFilmEditorValidationError,
        errors: inout Set<CustomFilmEditorValidationError>
    ) -> Double? {
        switch CustomFilmDurationParser.parse(text) {
        case .empty:
            return nil
        case .seconds(let value) where value.isFinite:
            return value
        case .seconds, .unlimited, .none:
            errors.insert(invalidError)
            return nil
        }
    }
}
