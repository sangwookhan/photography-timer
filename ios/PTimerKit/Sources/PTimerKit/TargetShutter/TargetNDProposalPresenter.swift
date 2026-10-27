// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

public enum TargetNDProposalPresenter {
    public static func display(_ session: TargetNDProposalSession, locale: Locale) -> TargetNDProposalDisplayState? {
        let korean = locale.language.languageCode?.identifier == "ko"
        guard session.phase != .idle else { return nil }
        if session.phase == .applied { return .init(requiredText: korean ? "ND 적용 완료" : "ND applied", isApplied: true) }
        guard let input = session.input else { return nil }
        let required: Double
        if let profile = input.profile {
            switch ReciprocityInverse().evaluate(profile: profile, targetSeconds: input.targetSeconds) {
            case .available(let metered, _): required = log2(metered) - log2(input.baseSeconds)
            case .unavailable(let reason): return failure(.inverse(reason), korean: korean)
            }
        } else { required = log2(input.targetSeconds) - log2(input.baseSeconds) }
        guard required.isFinite else { return failure(.invalidInput, korean: korean) }
        guard required >= 0 else { return failure(.negativeRequiredTotal, korean: korean) }
        let requiredText = (korean ? "필요 ND: " : "Required ND: ") + String(format: "%.1f", required) + (korean ? " 스톱" : " stops")
        guard let result = session.result else { return .init(requiredText: requiredText, isLive: true) }
        switch result {
        case .unavailable(let reason): return failure(reason, korean: korean)
        case .available(_, let candidate):
            if candidate.isCurrent { return .init(requiredText: korean ? "현재 필터가 적정합니다" : "Current filters are suitable") }
            let rows = candidate.stack.wheels.compactMap { FilterStack.resolvedRow(for: $0, inventory: input.inventory) }
            let names = rows.map { row -> String in
                let display = FilterWheelPresenter.rowDisplay(for: row, notationMode: .stops)
                return display.itemName ?? "ND \(display.compactValueText)"
            }.joined(separator: " + ")
            let compact = "ND " + rows.map { NDNotationFormatter.display(forStops: $0.contributionStops, mode: .stops).value }.joined(separator: "+")
            let error = String(format: "%+.1f", (abs(candidate.remainingError) < 0.05 ? 0 : candidate.remainingError)).replacingOccurrences(of: "-", with: "−")
            let total = NDStackTotalDisplayState(effectiveStep: candidate.stack.effectiveStep, wheelCount: candidate.stack.wheels.count).totalStopsText
            let action = korean ? "합계 \(total) 스톱 적용" : "Apply total \(total) stops"
            return .init(requiredText: requiredText, detailText: names + " · " + (korean ? "오차 " : "Error ") + error + " stop",
                         warningText: candidate.requiresSourceWarning ? (korean ? "출처 범위 밖" : "Beyond source range") : nil, canApply: true, compactCombination: compact, signedErrorText: error + " st", candidateTotalText: total, actionText: action)
        }
    }

    private static func failure(_ failure: TargetNDSelectionFailure, korean: Bool) -> TargetNDProposalDisplayState {
        let text: String
        switch failure {
        case .negativeRequiredTotal: text = korean ? "감광으로 이 Target에 도달할 수 없습니다" : "Attenuation cannot reach this Target"
        case .noCombination:
            return .init(requiredText: korean ? "적합한 ND 조합 없음" : "No suitable ND combination", isNoCombination: true)
        case .inverse(.multipleSolutions): text = korean ? "필요 ND 계산 불가: 역산 해가 여러 개입니다" : "Required ND unavailable: multiple inverse solutions"
        case .inverse(.noQuantifiedSolution): text = korean ? "필요 ND 계산 불가: 정량 역산값이 없습니다" : "Required ND unavailable: no quantified inverse"
        case .inverse(.numericalFailure): text = korean ? "필요 ND 계산 불가: 수치 역산 실패" : "Required ND unavailable: numerical inverse failed"
        default: text = korean ? "필요 ND 계산 불가: 유효하지 않은 계산 입력" : "Required ND unavailable: invalid calculation input"
        }
        return .init(requiredText: text)
    }
}
