import Foundation
import PTimerKit

/// Pure presenter for the Film Details legend block. Derives the
/// short list of legend lines (color correction, development
/// adjustment, manufacturer stop-signal) from the active profile's
/// rule + source-evidence adjustments. Kept separate from the main
/// details presenter so the legend wording does not drift when a new
/// secondary-guidance kind is added to the catalog.
struct FilmModeDetailsLegendPresenter {

    func legendDisplayState(for profile: ReciprocityProfile) -> FilmModeDetailsLegendState? {
        let ruleAdjustments = profile.rules.flatMap { rule -> [ReciprocityAdjustment] in
            switch rule {
            case let .threshold(thresholdRule):
                return thresholdRule.adjustments
            case let .formula(formulaRule):
                return formulaRule.additionalAdjustments
            case let .limitedGuidance(rule):
                return rule.adjustments
            case let .tableInterpolation(rule):
                return rule.additionalAdjustments
            }
        }
        let evidenceAdjustments = profile.sourceEvidence.flatMap(\.adjustments)
        let adjustments = ruleAdjustments + evidenceAdjustments
        let presentations = ReciprocitySecondaryGuidanceFormatter.format(adjustments)
        guard !presentations.isEmpty else { return nil }

        var lines: [String] = []

        let colorValues = presentations
            .filter { $0.kind == .colorCorrection }
            .compactMap(\.valueText)
        if !colorValues.isEmpty,
           let line = colorCorrectionLegendLine(for: colorValues) {
            lines.append(line)
        }

        if presentations.contains(where: { $0.kind == .developmentAdjustment }) {
            lines.append("Development adjustment: Dev -10% means adjust development time by -10%.")
        }

        if presentations.contains(where: { $0.kind == .warning && $0.severity == .stop }) {
            lines.append("Warning: Not recommended marks a manufacturer stop-signal.")
        }

        guard !lines.isEmpty else { return nil }
        return FilmModeDetailsLegendState(lines: lines)
    }

    private func colorCorrectionLegendLine(for filterNames: [String]) -> String? {
        if let kodakName = filterNames.first(where: { $0.uppercased().hasPrefix("CC") }) {
            let channelDescription = colorChannelDescription(for: trailingChannelLetter(of: kodakName))
            return "Color correction: \(kodakName) = color-compensating \(channelDescription) filtration."
        }

        let trailingLetters = Set(filterNames.compactMap(trailingChannelLetter))
        if trailingLetters.count == 1, let letter = trailingLetters.first {
            let description = colorChannelDescription(for: letter)
            return "Color correction: \(letter) = \(description) filtration."
        }

        return nil
    }

    private func trailingChannelLetter(of filterName: String) -> String? {
        guard let last = filterName.last,
              last.isLetter else { return nil }
        return String(last).uppercased()
    }

    private func colorChannelDescription(for channel: String?) -> String {
        switch channel?.uppercased() {
        case "M":
            return "magenta"
        case "G":
            return "green"
        case "B":
            return "blue"
        case "Y":
            return "yellow"
        case "C":
            return "cyan"
        case "R":
            return "red"
        default:
            return "color"
        }
    }
}
