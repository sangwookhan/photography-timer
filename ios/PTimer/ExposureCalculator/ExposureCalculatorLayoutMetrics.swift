// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import PTimerKit

enum ExposureWorkspaceLayoutDensity {
    case regular
    case compact
    case dense
}

/// Screen-level layout metrics for the exposure-calculator screen.
///
/// The bottom of the trimmed workspace area is partitioned, top to
/// bottom, into: camera workspace → marker gap → page marker →
/// marker-to-rail gap → timer preview rail → rail bottom margin.
/// The rail footprint is reserved unconditionally so timer presence
/// never reflows the camera workspace; only the rail's *contents*
/// (`CompactTimerCardStripView`) are conditional.
///
/// The screen-level `GeometryReader` is hosted inside the default
/// safe area, so `geometry.size.height` is already safe-area-trimmed
/// and the metrics below partition that trimmed area only.
struct ExposureWorkspaceLayoutMetrics {

    /// Height of the timer preview rail band.
    static let timerStripHeight: CGFloat = BottomSheetCompactDockMetrics.viewportHeight

    /// Distance from the trimmed-area bottom edge to the rail's
    /// bottom edge.
    static let timerStripBottomMargin: CGFloat = 2

    /// Visual gap between the rail's top edge and the page marker's
    /// bottom edge.
    static let pageMarkerToStripGap: CGFloat = 4

    /// Effective vertical footprint of the page marker view.
    static let pageMarkerHeight: CGFloat = 12

    /// Visual gap between the page marker's top edge and the camera
    /// workspace's bottom edge.
    static let workspaceMarkerGap: CGFloat = 4

    /// Total reservation below the camera workspace: marker gap +
    /// marker + marker-to-rail gap + rail + rail bottom margin.
    static let bottomReservation: CGFloat =
        timerStripBottomMargin
        + timerStripHeight
        + pageMarkerToStripGap
        + pageMarkerHeight
        + workspaceMarkerGap

    // MARK: - Page marker

    /// Bottom-anchored y-offset of the page marker. The marker
    /// always sits above the rail's reserved band; its position is
    /// independent of timer presence.
    static func pageMarkerBottomOffset() -> CGFloat {
        timerStripBottomMargin
            + timerStripHeight
            + pageMarkerToStripGap
    }

    // MARK: - Timer rail offset

    /// Bottom-anchored y-offset of the rail (boundary background
    /// and, when present, the compact strip cards).
    static func timerStripBottomOffset() -> CGFloat {
        timerStripBottomMargin
    }

    // MARK: - Camera workspace budget

    /// Available height for the camera workspace, derived from the
    /// trimmed `workspaceArea` minus the unconditional bottom
    /// reservation. Safe-area insets are already excluded from
    /// `workspaceArea` and must not be subtracted again here.
    static func availableMainContentHeight(workspaceArea: CGFloat) -> CGFloat {
        workspaceArea - bottomReservation
    }

    /// Minimum workspace budget at which the given density tier is
    /// allowed to render the page without overflowing required
    /// visible content: the tier's complete worst-case content
    /// budget derived from the same style values the page renders
    /// (SHELL-012). Never a hand-tuned constant.
    static func estimatedMainContentHeight(for density: ExposureWorkspaceLayoutDensity) -> CGFloat {
        ExposureWorkspaceMainLayoutStyle(density: density).worstCaseContentBudget.total
    }

    /// Density tier for an available workspace height: the roomiest
    /// tier whose derived worst-case budget the height satisfies,
    /// falling back to Dense (SHELL-011/012). Exactly the requirement
    /// selects its tier; one point less falls back.
    static func style(forAvailableHeight availableHeight: CGFloat) -> ExposureWorkspaceMainLayoutStyle {
        for style in [ExposureWorkspaceMainLayoutStyle.regular, .compact] where availableHeight >= style.worstCaseContentBudget.total {
            return style
        }
        return .dense
    }
}

/// The complete worst-case visible content of one density tier
/// (SHELL-012): every reserved row and region the tier renders when a
/// film with a model selector is chosen, the Target Shutter is active,
/// the ND card carries its label row and one-row status region, and the film
/// result hierarchy is shown — plus page padding and the required
/// minimum result spacer. Built from the style values the page uses
/// (`ExposureWorkspaceMainLayoutStyle.worstCaseContentBudget`), so a
/// style change moves the tier threshold and the layout tests
/// together. Fields are mutable so a test can vary one contribution
/// and observe the total without a parallel formula.
struct ExposureWorkspaceContentBudget: Equatable {
    // Page
    var topPadding: CGFloat
    var bottomPadding: CGFloat
    var resultSpacer: CGFloat
    /// Card padding applied top and bottom on each of the four cards
    /// (header, Target Shutter, variable, result).
    var cardPadding: CGFloat
    var cardCount: CGFloat = 4

    // Header card: title row, film label + selector button, model row.
    var headerTitleRow: CGFloat
    var headerContentSpacing: CGFloat
    var filmLabelRow: CGFloat
    var filmLabelSpacing: CGFloat
    var filmSelectorButton: CGFloat
    var modelRow: CGFloat

    // Target Shutter card (active target).
    var targetRow: CGFloat

    // Variable card: picker header, label row, picker, one-row status
    // region (FILTER-STACK-008: no second-line capacity).
    var pickerHeader: CGFloat
    var pickerLabelSpacing: CGFloat
    var wheelLabelRow: CGFloat
    var picker: CGFloat
    var wheelBodySpacing: CGFloat
    var statusRegion: CGFloat

    // Result card: the film result hierarchy floor (includes its own
    // block padding).
    var filmResultBlock: CGFloat

    var headerCard: CGFloat {
        headerTitleRow + headerContentSpacing + filmLabelRow + filmLabelSpacing + filmSelectorButton
            + headerContentSpacing + modelRow + 2 * cardPadding
    }

    var targetCard: CGFloat {
        targetRow + 2 * cardPadding
    }

    var variableCard: CGFloat {
        pickerHeader + pickerLabelSpacing + wheelLabelRow + picker + wheelBodySpacing + statusRegion + 2 * cardPadding
    }

    var resultCard: CGFloat {
        filmResultBlock + 2 * cardPadding
    }

    /// The tier's eligibility requirement.
    var total: CGFloat {
        topPadding + headerCard + targetCard + variableCard + resultCard + resultSpacer + bottomPadding
    }
}
