// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The one commercial filter-factor mapping shared by the Standard ND
/// notation formatter and Filter Item registration (Filter Set
/// contract, FILTER-ITEM-004): for every value on the shipping ND
/// ladder it yields the numeric factor the Standard `ND` label shows,
/// and the inverse recovers the canonical ladder stops from such a
/// factor — so a registered ND1000 is exactly 10 stops, not
/// `log2(1000)`.
///
/// Factor policy (identical to the formatter's rendering rules):
/// - the three commercial presets: 6.6 → 100, 7.6 → 200, 16.6 → 100 000;
/// - 0–9 stops: the exact power of two (1 … 512);
/// - 10–13 stops: commercial thousands (1000, 2000, 4000, 8000);
/// - 14 stops and up: the exact power of two (the `K` / `M` / `G`
///   labels are exact binary units, so 2^14 = 16 384 reads `ND16K`).
public enum NDCommercialFactorMapping {
    /// Numeric filter factor of the Standard `ND` label for a canonical
    /// ladder value, or `nil` when `stops` is not on the ladder (no
    /// label exists for it).
    public static func commercialFactor(forStops stops: Double) -> Double? {
        if let preset = ExposureScale.commercialNDPresetStop(matching: stops) {
            switch preset {
            case 6.6: return 100
            case 7.6: return 200
            default: return 100_000
            }
        }
        guard let whole = NDStep(stops: stops).wholeStops,
              (0...ExposureScale.maximumWholeNDStops).contains(whole) else {
            return nil
        }
        let factor = pow(2.0, Double(whole))
        if factor < 1000 {
            return factor
        }
        if factor < 10_000 {
            return (factor / 1000).rounded() * 1000
        }
        return factor
    }

    /// Canonical ladder stops whose Standard label factor equals
    /// `factor` (within the shared stability epsilon), or `nil` when no
    /// label matches — callers then fall back to `log2(factor)`.
    public static func canonicalStops(matchingCommercialFactor factor: Double) -> Double? {
        guard factor.isFinite, factor > 0 else {
            return nil
        }
        let candidates = (0...ExposureScale.maximumWholeNDStops).map(Double.init)
            + ExposureScale.commercialFractionalNDStops
        return candidates.first { stops in
            guard let labelFactor = commercialFactor(forStops: stops) else { return false }
            return abs(labelFactor - factor) <= ExposureCalculator.stabilityEpsilon
        }
    }
}
