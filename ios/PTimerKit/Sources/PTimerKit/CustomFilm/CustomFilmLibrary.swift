// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation
import PTimerCore

/// Source-of-truth model for photographer-authored custom film
/// reciprocity profiles. Holds an ordered list of `FilmIdentity`
/// entries whose `kind == .custom` and whose single profile carries
/// `.userDefined` authority.
///
/// Persistence: the library loads the `CustomFilmLibraryStoring`
/// snapshot at init and writes back on every mutation. Pass a
/// `NoOpCustomFilmLibraryStore` for tests that only care about
/// the in-memory invariants; pass the app's concrete
/// `CustomFilmLibraryStoring` adapter (wired by
/// `ViewModelDependencyFactory.production()`) for the shipping
/// path.
///
/// Ownership: the model is the only writer for the custom list.
/// Mutating callers go through `add` / `remove`; readers consume the
/// `@Published` value. Insertion order is preserved so newly created
/// entries appear at the bottom of the list in the selector —
/// matching the user's mental model of "I added this last."
@MainActor
public final class CustomFilmLibrary: ObservableObject {
    @Published public private(set) var customFilms: [FilmIdentity]
    private let store: CustomFilmLibraryStoring

    public init(
        store: CustomFilmLibraryStoring = NoOpCustomFilmLibraryStore(),
        initial: [FilmIdentity] = []
    ) {
        self.store = store
        // Persisted snapshot is the source of truth when present so
        // a relaunch surfaces the saved library byte-for-byte; the
        // `initial` parameter is for in-memory test setup that does
        // not have a store.
        let restored = store.loadSnapshot()?.films ?? initial
        self.customFilms = CustomFilmLibrary.sanitized(restored)
    }

    /// Appends a freshly created custom film. Entries with a
    /// duplicate `id` replace the prior entry in place so a future
    /// "edit" path can call through the same method without
    /// reordering the list.
    public func add(_ film: FilmIdentity) {
        guard film.kind == .custom else {
            return
        }
        if let index = customFilms.firstIndex(where: { $0.id == film.id }) {
            customFilms[index] = film
        } else {
            customFilms.append(film)
        }
        persist()
    }

    /// Removes the entry matching `id`. No-op when no entry matches —
    /// the caller (delete flow / selection fallback) is responsible
    /// for any post-removal state reconciliation.
    public func remove(id: String) {
        let before = customFilms.count
        customFilms.removeAll { $0.id == id }
        if customFilms.count != before {
            persist()
        }
    }

    /// Writes the current in-memory state to the persistence store.
    /// Called after every mutation that changes the published
    /// collection so a relaunch always restores the latest state
    /// — the library never accumulates unflushed changes.
    private func persist() {
        store.saveSnapshot(
            PersistentCustomFilmLibrarySnapshot(films: customFilms)
        )
    }

    /// Direct lookup by id. Returns `nil` when the entry is not in
    /// the library; the calculator-restore path uses this to resolve
    /// a persisted custom-film reference once persistence ships.
    public func film(withID id: String) -> FilmIdentity? {
        customFilms.first { $0.id == id }
    }

    public var isEmpty: Bool { customFilms.isEmpty }

    /// Drops malformed entries so a corrupted payload (manual
    /// UserDefaults edit, an in-development schema that never
    /// shipped, future schema mismatch) cannot resurface in the
    /// picker. Sanitation rules cover the invariants every
    /// downstream surface assumes — `kind`, identifiers, profile
    /// shape, formula validity — and silently drop anything that
    /// would crash or render incorrectly later.
    private static func sanitized(_ films: [FilmIdentity]) -> [FilmIdentity] {
        films.filter(isWellFormedCustomFilm)
    }

    private static func isWellFormedCustomFilm(_ film: FilmIdentity) -> Bool {
        guard hasWellFormedFilmIdentity(film),
              let profile = film.profiles.first,
              hasWellFormedProfileIdentity(profile) else {
            return false
        }
        // A custom profile carries exactly one calculation path:
        // formula XOR tableInterpolation (PTIMER-178). The formula
        // branch keeps the pre-existing guards unchanged; the table
        // branch reuses the domain's safe-table contract plus the
        // stricter custom-editor rule that the no-correction knee
        // must be strictly positive (the evaluator feeds it into
        // log-log interpolation, so a persisted 0 would dead-end
        // the first segment).
        let formulaRules = formulaRules(in: profile)
        let tableRules = tableInterpolationRules(in: profile)
        guard profile.rules.count == 1,
              formulaRules.count + tableRules.count == 1 else {
            return false
        }

        if let formula = formulaRules.first {
            return hasWellFormedFormulaCoefficients(formula)
                && hasWellFormedFormulaRange(formula)
                && hasNonShorteningBoundary(formula: formula)
        }
        if let table = tableRules.first {
            return table.hasValidParameters
                && table.noCorrectionThroughSeconds > 0
        }
        return false
    }

    private static func hasWellFormedFilmIdentity(_ film: FilmIdentity) -> Bool {
        guard film.kind == .custom, film.iso > 0 else { return false }
        let trimmedID = film.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = film.canonicalStockName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedID.isEmpty && !trimmedName.isEmpty
    }

    private static func hasWellFormedProfileIdentity(_ profile: ReciprocityProfile) -> Bool {
        guard profile.source.authority == .userDefined else { return false }
        let trimmedID = profile.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedID.isEmpty && !trimmedName.isEmpty
    }

    private static func formulaRules(in profile: ReciprocityProfile) -> [FormulaReciprocityRule] {
        profile.rules.compactMap { rule -> FormulaReciprocityRule? in
            if case .formula(let r) = rule { return r }
            return nil
        }
    }

    private static func tableInterpolationRules(
        in profile: ReciprocityProfile
    ) -> [TableInterpolationReciprocityRule] {
        profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
            if case .tableInterpolation(let r) = rule { return r }
            return nil
        }
    }

    /// Basic-shape check that rejects non-finite values or
    /// non-positive coefficient / reference / exponent before the
    /// analytic shortening guard runs.
    private static func hasWellFormedFormulaCoefficients(_ formula: FormulaReciprocityRule) -> Bool {
        formula.formula.hasValidParameters
    }

    /// Range well-formedness for a custom profile: when the user
    /// supplies a `sourceRangeThroughSeconds`, it must be strictly
    /// greater than `noCorrectionThroughSeconds`. `nil`
    /// (Unlimited) is always well-formed at this layer; the
    /// no-shortening guard is the next stop.
    private static func hasWellFormedFormulaRange(_ formula: FormulaReciprocityRule) -> Bool {
        let noCorrection = formula.formula.noCorrectionThroughSeconds
        guard noCorrection.isFinite, noCorrection >= 0 else { return false }
        if let upper = formula.formula.sourceRangeThroughSeconds {
            return upper.isFinite && upper > noCorrection
        }
        return true
    }

    /// Shared no-shortening guard. Reads the anchor pair directly
    /// off the formula so a custom profile never relies on metadata
    /// side channels.
    private static func hasNonShorteningBoundary(
        formula: FormulaReciprocityRule
    ) -> Bool {
        CustomFilmFormulaGuard.passesUsableRangeCheck(
            .init(
                exponent: formula.formula.exponent,
                referenceMeteredTimeSeconds: formula.formula.referenceMeteredTimeSeconds,
                coefficientSeconds: formula.formula.coefficientSeconds,
                offsetSeconds: formula.formula.offsetSeconds,
                noCorrectionThroughSeconds: formula.formula.noCorrectionThroughSeconds,
                sourceRangeThroughSeconds: formula.formula.sourceRangeThroughSeconds
            )
        )
    }
}
