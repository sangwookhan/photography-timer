// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// How ND-filter strength is *displayed*. This is a presentation
/// choice only — ND strength is always stored and calculated as
/// stops (`NDStep.stops`); switching the notation never changes the
/// canonical value or any exposure result.
///
/// - `stops`: native stop count (`9 stops`).
/// - `opticalDensity`: optical density, `stops × 0.3` (`OD 2.7`).
/// - `filterFactor`: light-reduction factor, `2^stops` (`ND512`).
///
/// `stops` is the shipping default. Persisted by its `rawValue`, so
/// the case names are part of the on-disk contract.
public enum NDNotationMode: String, Codable, CaseIterable, Sendable {
    case stops
    case opticalDensity
    case filterFactor
}
