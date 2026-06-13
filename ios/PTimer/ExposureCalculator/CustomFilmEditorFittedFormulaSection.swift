import SwiftUI
import PTimerKit
import PTimerCore

/// Seconds-first label for anchor/source/comparison values in the
/// fitted-formula tables. Values ≥ 60 s render as `Xs (NmYs)` so
/// the raw seconds value the photographer entered is always visible
/// alongside the compact clock context. Delegates to
/// `CustomFilmEditorFormState.formatAnchorSeconds`.
func customFilmEditorCompactSeconds(_ seconds: Double) -> String {
    CustomFilmEditorFormState.formatAnchorSeconds(seconds)
}

/// Inspection-only body of the "App-derived formula preview" section
/// (PTIMER-179). Derives the fit from the form's table rule and shows
/// the generated formula, its boundaries, a per-anchor source-vs-fitted
/// comparison, the worst residual, and a fit-quality classification —
/// or a calm "unusable here" message when the fit shortens exposure or
/// cannot be formed. Never alters the active shooting calculation.
struct CustomTableFittedFormulaPreviewContent: View {
    let form: CustomFilmEditorFormState

    private var outcome: CustomTableFittedFormulaPresenter.Outcome? {
        form.parsedTableInterpolationRule()
            .map(CustomTableFittedFormulaPresenter.outcome(for:))
    }

    var body: some View {
        switch outcome {
        case let .available(fit):
            availableContent(fit)
        case let .unavailable(reason):
            unavailableContent(reason)
        case nil:
            EmptyView()
        }
    }

    // MARK: - Available

    @ViewBuilder
    private func availableContent(
        _ fit: CustomTableFittedFormulaPresenter.FittedFormula
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            formulaBlock(fit)
            boundariesBlock(fit)
            comparisonTable(fit)
            qualityBlock(fit)
            Text(CustomTableFittedFormulaPresenter.notManufacturerNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("custom-film-editor-fitted-formula")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(CustomTableFittedFormulaPresenter.appDerivedLabel)
                .font(.footnote.weight(.semibold))
            Spacer(minLength: 8)
            Text(CustomTableFittedFormulaPresenter.formulaFamilyLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func formulaBlock(
        _ fit: CustomTableFittedFormulaPresenter.FittedFormula
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tc = \(numeric(fit.coefficientSeconds)) × Tm^\(numeric(fit.exponent))")
                .font(.footnote.monospaced())
                .accessibilityIdentifier("custom-film-editor-fitted-formula-expression")
            Text("a \(numeric(fit.coefficientSeconds))  ·  p \(numeric(fit.exponent))  ·  b 0")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func boundariesBlock(
        _ fit: CustomTableFittedFormulaPresenter.FittedFormula
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            keyValueRow(
                "No correction",
                customFilmEditorCompactSeconds(fit.noCorrectionThroughSeconds)
            )
            keyValueRow(
                "Source data through",
                customFilmEditorCompactSeconds(fit.sourceRangeThroughSeconds)
            )
        }
    }

    private func keyValueRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }

    @ViewBuilder
    private func comparisonTable(
        _ fit: CustomTableFittedFormulaPresenter.FittedFormula
    ) -> some View {
        VStack(spacing: 3) {
            comparisonHeaderRow
            ForEach(fit.comparisonRows, id: \.meteredSeconds) { row in
                comparisonRow(row)
            }
        }
        .accessibilityIdentifier("custom-film-editor-fitted-formula-comparison")
    }

    private var comparisonHeaderRow: some View {
        HStack {
            Text("Metered").frame(width: 110, alignment: .leading)
            Text("Source").frame(maxWidth: .infinity, alignment: .leading)
            Text("App").frame(maxWidth: .infinity, alignment: .leading)
            Text("Error").frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func comparisonRow(
        _ row: CustomTableFittedFormulaPresenter.ComparisonRow
    ) -> some View {
        HStack {
            Text(customFilmEditorCompactSeconds(row.meteredSeconds))
                .frame(width: 110, alignment: .leading)
            Text(customFilmEditorCompactSeconds(row.sourceCorrectedSeconds))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(customFilmEditorCompactSeconds(row.fittedCorrectedSeconds))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(signedPercent(row.percentError)) / \(signedStop(row.stopError))")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption2.monospacedDigit())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func qualityBlock(
        _ fit: CustomTableFittedFormulaPresenter.FittedFormula
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(fit.quality.displayLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(qualityColor(fit.quality))
                Spacer(minLength: 8)
                Text("Worst \(signedStop(fit.worstAbsoluteStopError, signed: false))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("custom-film-editor-fitted-formula-quality")

            if fit.isTwoAnchorExactFit {
                Text(CustomTableFittedFormulaPresenter.twoAnchorNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if fit.quality != .good {
                Text("This formula misses the table by up to "
                    + "\(signedStop(fit.worstAbsoluteStopError, signed: false)). "
                    + "The table stays your reliable calculation.")
                    .font(.caption2)
                    .foregroundStyle(qualityColor(fit.quality))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("custom-film-editor-fitted-formula-warning")
            }
        }
    }

    private func qualityColor(
        _ quality: CustomTableFittedFormulaPresenter.FitQuality
    ) -> Color {
        switch quality {
        case .good: return .green
        case .borderline: return .orange
        case .poor: return .red.opacity(0.85)
        }
    }

    // MARK: - Unavailable

    @ViewBuilder
    private func unavailableContent(
        _ reason: CustomTableFittedFormulaPresenter.Unavailable
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CustomTableFittedFormulaPresenter.appDerivedLabel)
                .font(.footnote.weight(.semibold))
            Text(reason.displayMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("custom-film-editor-fitted-formula-unavailable")
    }

    // MARK: - Formatting

    private func numeric(_ value: Double) -> String {
        CustomTableFittedFormulaPresenter.parameterText(value)
    }

    private func signedPercent(_ value: Double) -> String {
        String(format: "%+.0f%%", value)
    }

    private func signedStop(_ value: Double, signed: Bool = true) -> String {
        String(format: signed ? "%+.2f st" : "%.2f st", value)
    }
}
