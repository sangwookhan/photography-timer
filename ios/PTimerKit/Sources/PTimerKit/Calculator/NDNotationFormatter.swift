// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Pure transform from a canonical ND value (`stops`) into the three
/// surface-specific display fragments every ND surface needs:
///
/// - `value`: the number text the picker wheel shows (`9`, `2.7`, `512`).
/// - `unit`: the picker unit/band text (`stops`, `OD`, `ND`).
/// - `inline`: the standalone label used in result/basis text
///   (`9 stops`, `OD 2.7`, `ND512`).
///
/// The inline form is never the picker value glued to the unit, so a
/// surface that already shows the unit (the picker band) does not
/// render duplicated forms like `512 ND` / `ND512 ND`.
///
/// Strings are assembled through positional `String(format:)`
/// templates (not sentence concatenation) so number/unit placement
/// can move when these defaults are localized later.
///
/// Rounding policy (deterministic; exercised by `NDNotationFormatterTests`):
/// - Optical density: `stops × 0.3`, one decimal (`OD 0.0`, `OD 2.7`,
///   `OD 3.0`).
/// - Filter factor: `2^stops`, via PTIMER's compact app display policy
///   (not an external standard):
///   - 0–9 stops (factor < 1000): the exact factor — `ND1`, `ND2`,
///     `ND8`, `ND512`.
///   - 10–13 stops (factor < 10000): commercial-familiar thousands —
///     `ND1000`, `ND2000`, `ND4000`, `ND8000` (2^10 stays `ND1000`).
///   - 14 stops and up: the factor against the nearest power-of-two
///     unit (K = 2^10, M = 2^20, G = 2^30) with an uppercase suffix, so
///     exact stops land on clean labels — `ND16K` (14), `ND64K` (16),
///     `ND512K` (19), `ND1M` (20). Deliberately not one-significant-
///     figure rounding, which would mislabel 2^14 as `ND20k`.
public enum NDNotationFormatter {
    public struct Display: Equatable, Sendable {
        public let value: String
        public let unit: String
        public let inline: String

        public init(value: String, unit: String, inline: String) {
            self.value = value
            self.unit = unit
            self.inline = inline
        }
    }

    public static func display(forStops stops: Double, mode: NDNotationMode) -> Display {
        switch mode {
        case .stops:
            let value = stopsValueText(forStops: stops)
            return Display(
                value: value,
                unit: Template.stopsUnit,
                inline: stopsInlineText(forStops: stops, value: value)
            )
        case .opticalDensity:
            let value = opticalDensityValueText(forStops: stops)
            return Display(
                value: value,
                unit: Template.opticalDensityUnit,
                inline: String(format: Template.opticalDensityInline, value)
            )
        case .filterFactor:
            let value = filterFactorValueText(forStops: stops)
            return Display(
                value: value,
                unit: Template.filterFactorUnit,
                inline: String(format: Template.filterFactorInline, value)
            )
        }
    }

    public static func display(for ndStep: NDStep, mode: NDNotationMode) -> Display {
        display(forStops: ndStep.stops, mode: mode)
    }

    // MARK: - Stops

    /// Whole stops render as an integer (`9`); the reserved fractional
    /// path renders as a mixed fraction (`1 1/3`) so a future
    /// fractional-ND surface keeps its third-stop component. Mirrors
    /// the legacy picker formatting so the stops mode is unchanged.
    private static func stopsValueText(forStops stops: Double) -> String {
        let step = NDStep(stops: stops)
        if let wholeStops = step.wholeStops {
            return "\(wholeStops)"
        }

        let totalThirds = step.thirdStopCount
        let wholePart = totalThirds / 3
        let fractionalThirds = totalThirds % 3
        let fractionLabel = fractionalThirds == 1 ? "1/3" : "2/3"

        if wholePart == 0 {
            return fractionLabel
        }
        return "\(wholePart) \(fractionLabel)"
    }

    private static func stopsInlineText(forStops stops: Double, value: String) -> String {
        // Singular only on the exact one-whole-stop boundary.
        let isSingular = NDStep(stops: stops).wholeStops == 1
        let template = isSingular ? Template.stopsSingularInline : Template.stopsPluralInline
        return String(format: template, value)
    }

    // MARK: - Optical density

    private static func opticalDensityValueText(forStops stops: Double) -> String {
        let density = stops * 0.3
        return String(format: "%.1f", density)
    }

    // MARK: - Filter factor

    private static func filterFactorValueText(forStops stops: Double) -> String {
        let factor = pow(2.0, stops)

        // 0–9 stops: the exact factor (1, 2, 4, … 512).
        if factor < 1000 {
            return "\(Int(factor.rounded()))"
        }

        // 10–13 stops (factor < 10000): commercial-familiar thousands —
        // 1000 / 2000 / 4000 / 8000. 2^10 stays ND1000 (not ND1K).
        if factor < 10_000 {
            return "\(Int((factor / 1000).rounded()) * 1000)"
        }

        // 14 stops and up: PTIMER's compact app display policy (not an
        // external standard). Express the factor against the nearest
        // power-of-two unit — K = 2^10, M = 2^20, G = 2^30 — so exact
        // stop values land on clean labels: 2^14 = ND16K, 2^16 = ND64K,
        // 2^20 = ND1M. This deliberately avoids one-significant-figure
        // rounding, which would mislabel 2^14 as ND20k and 2^16 as
        // ND70k. Uppercase suffix.
        let units: [(threshold: Double, suffix: String)] = [
            (1_073_741_824, "G"),  // 2^30
            (1_048_576, "M"),      // 2^20
            (1024, "K"),           // 2^10
        ]
        for unit in units where factor >= unit.threshold {
            return "\(Int((factor / unit.threshold).rounded()))\(unit.suffix)"
        }

        // Unreachable for factor >= 10000; deterministic fallback.
        return "\(Int(factor.rounded()))"
    }

    // MARK: - Localization templates

    /// English-default templates with positional placeholders. Lifted
    /// into one place so the only localization step later is providing
    /// translated templates — no code path assumes English word order.
    private enum Template {
        static let stopsUnit = "stops"
        static let stopsSingularInline = "%@ stop"
        static let stopsPluralInline = "%@ stops"
        static let opticalDensityUnit = "OD"
        static let opticalDensityInline = "OD %@"
        static let filterFactorUnit = "ND"
        static let filterFactorInline = "ND%@"
    }
}
