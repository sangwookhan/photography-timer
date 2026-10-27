// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Explicit, static UI fixtures. Never evaluate or apply a real filter stack.
public enum TargetNDProposalPreview: String, CaseIterable, Sendable {
    case live, ordinary, warning, suitable, unavailable, noCombination, applied

    public func displayState(locale: Locale) -> TargetNDProposalDisplayState {
        let korean = locale.language.languageCode?.identifier == "ko"
        let required = korean ? "필요 ND: 8.7 stops" : "Required ND: 8.7 stops"
        switch self {
        case .live:
            return .init(requiredText: required)
        case .ordinary, .warning:
            return .init(
                requiredText: required,
                detailText: korean ? "ND 6 + 3 · 오차 −0.3 stop" : "ND 6 + 3 · Error −0.3 stop",
                warningText: self == .warning ? (korean ? "출처 범위 밖" : "Beyond source range") : nil,
                canApply: true
            )
        case .suitable:
            return .init(requiredText: korean ? "현재 필터가 적정합니다" : "Current filters are suitable")
        case .unavailable:
            return .init(requiredText: korean ? "필요 ND 계산 불가: 역산 해가 여러 개입니다" : "Required ND unavailable: multiple inverse solutions")
        case .noCombination:
            return .init(requiredText: korean ? "허용 오차 내 ND 조합이 없습니다" : "No ND combination within allowed error")
        case .applied:
            return .init(requiredText: korean ? "미리보기 적용 완료 · 실제 필터는 유지됩니다" : "Preview applied · actual filters unchanged")
        }
    }
}

private struct TargetNDProposalPreviewKey: EnvironmentKey {
    static let defaultValue: TargetNDProposalPreview? = nil
}

public extension EnvironmentValues {
    var targetNDProposalPreview: TargetNDProposalPreview? {
        get { self[TargetNDProposalPreviewKey.self] }
        set { self[TargetNDProposalPreviewKey.self] = newValue }
    }
}
