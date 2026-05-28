import SwiftUI

/// Compact `Tm → Tc` snapshot rendered inside the Formula card of
/// `CustomFilmEditorView`. Reuses
/// `CustomFilmEditorPreviewPresenter.rows(form:samples:)` with the
/// `liveCheckSampleSeconds` ladder (1s, 10s, 1m) so the live result
/// reads with the same evaluation semantics as the full Preview
/// graph/table and the Details surface — only the surrounding
/// chrome changes.
///
/// Rows whose status is `.invalidFormulaResult` (which means
/// `correctedSeconds == nil`) are filtered out so the block stays
/// compact and the Preview card's "Preview unavailable" panel is
/// the single recovery surface in the invalid-form state.
struct CustomFilmEditorLiveCheckView: View {
    let form: CustomFilmEditorFormState

    var body: some View {
        let rows = CustomFilmEditorPreviewPresenter.rows(
            form: form,
            samples: CustomFilmEditorPreviewPresenter.liveCheckSampleSeconds
        )
        let renderable = rows.filter { $0.correctedSeconds != nil }
        if !renderable.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Live check")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                ForEach(renderable, id: \.meteredSeconds) { row in
                    HStack(spacing: 6) {
                        Text(Self.text(for: row))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Self.color(for: row.status))
                        if row.status == .beyondSourceRange {
                            Text("· beyond")
                                .font(.caption2)
                                .foregroundStyle(Color.orange)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier("custom-film-editor-formula-live-check")
        }
    }

    /// Static so the formatting policy can be exercised by tests
    /// without instantiating a SwiftUI view.
    static func text(
        for row: CustomFilmEditorPreviewPresenter.Row
    ) -> String {
        let tm = label(seconds: row.meteredSeconds)
        let tc = row.correctedSeconds.map(label(seconds:)) ?? "—"
        return "\(tm) → \(tc)"
    }

    /// Mirrors the Preview table's `metricLabel` policy:
    /// - whole-minute durations render as `Nm`
    /// - fractional minutes render with one decimal (`3.4m`)
    /// - sub-second durations render with two decimals (`0.50s`)
    /// - whole seconds render as `Ns`; fractional seconds as `N.Ns`
    static func label(seconds: Double) -> String {
        if seconds >= 60 {
            let minutes = seconds / 60
            return minutes == minutes.rounded()
                ? "\(Int(minutes))m"
                : String(format: "%.1fm", minutes)
        }
        if seconds < 1 {
            return String(format: "%.2fs", seconds)
        }
        return seconds == seconds.rounded()
            ? "\(Int(seconds))s"
            : String(format: "%.1fs", seconds)
    }

    /// No-correction rows render muted (the metered value passes
    /// through unchanged), formula-applied / beyond-source rows
    /// render in the primary text color so the numeric consequence
    /// stays readable. Beyond-source rows additionally carry a
    /// subtle orange "· beyond" trailing chip.
    static func color(
        for status: CustomFilmEditorPreviewPresenter.RowStatus
    ) -> Color {
        switch status {
        case .noCorrection:
            return Color.secondary
        case .formulaApplied, .beyondSourceRange:
            return Color.primary
        case .invalidFormulaResult:
            return Color.secondary
        }
    }
}
