import Foundation

struct ReciprocitySecondaryGuidancePresentation: Equatable {
    enum Kind: String, Equatable {
        case colorCorrection
        case developmentAdjustment
        case warning
        case note
    }

    enum Severity: String, Equatable {
        case neutral
        case caution
        case stop
    }

    let kind: Kind
    let title: String
    let valueText: String?
    let detailText: String
    let severity: Severity
}

enum ReciprocitySecondaryGuidanceFormatter {
    static func format(_ adjustments: [ReciprocityAdjustment]) -> [ReciprocitySecondaryGuidancePresentation] {
        adjustments.compactMap { adjustment in
            switch adjustment {
            case let .colorFilter(recommendation):
                return ReciprocitySecondaryGuidancePresentation(
                    kind: .colorCorrection,
                    title: "Color correction",
                    valueText: recommendation.filterName,
                    detailText: recommendation.note ?? "",
                    severity: .neutral
                )
            case let .development(adjustment):
                return ReciprocitySecondaryGuidancePresentation(
                    kind: .developmentAdjustment,
                    title: "Development adjustment",
                    valueText: adjustment.instruction,
                    detailText: adjustment.note ?? "",
                    severity: .neutral
                )
            case let .warning(warning):
                return ReciprocitySecondaryGuidancePresentation(
                    kind: .warning,
                    title: "Warning",
                    valueText: nil,
                    detailText: warning.message,
                    severity: warning.severity == .caution ? .caution : .stop
                )
            case let .note(note):
                guard !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }

                return ReciprocitySecondaryGuidancePresentation(
                    kind: .note,
                    title: "Note",
                    valueText: nil,
                    detailText: note.text,
                    severity: .caution
                )
            case .exposure:
                return nil
            }
        }
    }
}
