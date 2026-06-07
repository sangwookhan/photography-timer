import Foundation

public struct ReciprocitySecondaryGuidancePresentation: Equatable {
    public enum Kind: String, Equatable {
        case colorCorrection
        case developmentAdjustment
        case warning
        case note
    }

    public enum Severity: String, Equatable {
        case neutral
        case caution
        case stop
    }

    public let kind: Kind
    public let title: String
    public let valueText: String?
    public let detailText: String
    public let severity: Severity

    public init(
        kind: Kind,
        title: String,
        valueText: String? = nil,
        detailText: String,
        severity: Severity
    ) {
        self.kind = kind
        self.title = title
        self.valueText = valueText
        self.detailText = detailText
        self.severity = severity
    }
}

public enum ReciprocitySecondaryGuidanceFormatter {
    public static func format(_ adjustments: [ReciprocityAdjustment]) -> [ReciprocitySecondaryGuidancePresentation] {
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
