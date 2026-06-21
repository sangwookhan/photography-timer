// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// PTIMER-180: resolves the linked reference-table anchors for a saved
/// custom **formula** film from its persisted
/// `UserEditableMetadata.referenceTableFilmID`.
///
/// The creation flow already holds the table anchors in memory; the
/// **edit** flow opens from persisted metadata and must re-hydrate them
/// so the formula editor's graph markers and the Calculation Basis
/// Reference / Error columns reappear.
///
/// Display-only: the anchors drive comparison / error rendering and are
/// never fed into calculation. Errors recompute from the table's
/// *current* anchors, so a table edited after the formula was saved is
/// reflected on the next open without touching the formula parameters.
public enum CustomFilmReferenceTableResolver {

    public struct Resolution: Equatable {
        /// Current anchors of the linked table, or empty when the
        /// formula is unlinked or the link cannot be resolved.
        public let anchors: [TableAnchor]
        /// `true` when the formula carries a `referenceTableFilmID` but
        /// it no longer resolves to a custom table (deleted, or not a
        /// table) — the editor then shows "reference table unavailable"
        /// rather than reference / error columns.
        public let isLinkedButMissing: Bool

        public init(anchors: [TableAnchor], isLinkedButMissing: Bool) {
            self.anchors = anchors
            self.isLinkedButMissing = isLinkedButMissing
        }
    }

    /// Resolves the reference table for `formulaFilm`. `lookup` maps a
    /// film id to the current `FilmIdentity` in the library (so an
    /// edited table surfaces its latest anchors). Unlinked formulas
    /// return an empty, not-missing resolution so the editor behaves
    /// exactly like the pre-PTIMER-180 unlinked editor.
    public static func resolve(
        for formulaFilm: FilmIdentity,
        lookup: (String) -> FilmIdentity?
    ) -> Resolution {
        guard let tableID = formulaFilm.userMetadata?.referenceTableFilmID else {
            return Resolution(anchors: [], isLinkedButMissing: false)
        }
        guard let table = lookup(tableID) else {
            return Resolution(anchors: [], isLinkedButMissing: true)
        }
        let anchors = tableAnchors(of: table)
        return anchors.isEmpty
            ? Resolution(anchors: [], isLinkedButMissing: true)
            : Resolution(anchors: anchors, isLinkedButMissing: false)
    }

    private static func tableAnchors(of film: FilmIdentity) -> [TableAnchor] {
        for rule in film.profiles.first?.rules ?? [] {
            if case let .tableInterpolation(table) = rule {
                return table.anchors
            }
        }
        return []
    }
}
