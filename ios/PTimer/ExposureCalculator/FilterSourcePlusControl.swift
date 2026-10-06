// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import PTimerKit
import SwiftUI

/// The Plus wheel (Filter Set contract, FILTER-PLUS): the trailing-edge
/// control of the wheel row while the applicable ND-wheel limit permits
/// another wheel. It is NOT an actual filter wheel — it selects the ND
/// Filter Source the next wheel is created from, or the Shooting
/// filters action that opens the Shooting Filters sheet:
///
/// - tap adds a Standard 0 or Filter Set Empty wheel for the displayed
///   ND source, exactly once (FILTER-PLUS-003);
/// - vertical drag or fling browses Standard, the camera's candidate
///   ND sources, and the Shooting filters action, reporting the
///   candidate name so the parent can show it in the status row;
///   releasing on a different ND source adds exactly one wheel from
///   it, releasing on the Shooting filters action opens the sheet
///   without adding, and a return to the starting source does nothing
///   (FR-1.13). The camera's remembered source changes only when an
///   add succeeds; a refused add shows its reason in the status row;
/// - once the drag threshold is crossed browsing has won for the rest
///   of the touch. Plus has no long press; Filter Sets are managed
///   from Shooting Filters and the Settings menu (FILTER-FLOW-005/006).
///
/// At rest the compact control shows the candidate source's color as a
/// secondary cue. VoiceOver exposes ONE focusable element: its
/// adjustable value steps a transient displayed candidate through the
/// choices without adding or touching the camera's remembered source,
/// Open shooting filters is always a named action, and Add — activation and the named action — exists only
/// while the DISPLAYED source can add right now; otherwise the hint
/// carries the reason and the element stays focusable and adjustable
/// so the user can browse away (FILTER-A11Y-001, FILTER-PLUS-004,
/// ND-A11Y-002).
struct FilterSourcePlusControl: View {
    /// The vertical choices in browse order (FILTER-PLUS-001).
    let choices: [FilterPlusChoice]
    let selectedSource: FilterSource
    let sourceName: (FilterSource) -> String
    let sourceColor: (FilterSource) -> FilterSetColor?
    let pickerHeight: CGFloat
    /// False while a wheel is moving, reshaping, or touched; adding
    /// waits for quiet. Browsing stays enabled.
    let isInteractionQuiet: Bool
    /// Localized reason a given source cannot add right now (`nil`
    /// when it can). Asked for the DISPLAYED source, so a transient
    /// assistive candidate shows and speaks its own availability.
    let addUnavailabilityText: (FilterSource) -> String?
    /// Adds one wheel for the given source; the view model refuses and
    /// reports when the source cannot add.
    let onAdd: (FilterSource) -> Void
    /// Opens Shooting Filters; adds nothing and
    /// leaves the remembered source alone (FILTER-PLUS-003).
    let onOpenAuxiliaryFilters: () -> Void
    /// Candidate choice while browsing, `nil` when idle. The parent
    /// renders the expanded, non-blocking label.
    let onBrowsingChanged: (FilterPlusChoice?) -> Void

    /// Classifies the current touch (tap / browse); `nil` between
    /// touches.
    @State private var gesture: FilterSourcePlusGestureArbiter?
    @State private var browsingHaptic = UISelectionFeedbackGenerator()
    /// The choice an assistive increment / decrement is browsing —
    /// displayed and announced, never persisted. Cleared when the
    /// camera's settled source changes (a successful add) or when the
    /// auxiliary popup opens, so the element follows the remembered
    /// source again.
    @State private var assistiveCandidate: FilterPlusChoice?

    private var browsingIndex: Int? {
        gesture?.phase == .browsing ? gesture?.candidateIndex : nil
    }

    private var settledIndex: Int {
        choices.firstIndex(of: .source(selectedSource)) ?? 0
    }

    private var candidateChoice: FilterPlusChoice {
        if let browsingIndex, choices.indices.contains(browsingIndex) {
            return choices[browsingIndex]
        }
        return displayedChoice
    }

    /// What a tap or an assistive activation acts on: the assistive
    /// candidate while one is being browsed, else the settled source.
    private var displayedChoice: FilterPlusChoice {
        if let assistiveCandidate, choices.contains(assistiveCandidate) {
            return assistiveCandidate
        }
        return .source(selectedSource)
    }

    private func name(of choice: FilterPlusChoice) -> String {
        switch choice {
        case .source(let source):
            return sourceName(source)
        case .auxiliaryFilters:
            return String(localized: "Shooting filters")
        }
    }

    private var tint: Color {
        switch candidateChoice {
        case .source(let source):
            return sourceColor(source).map(Color.filterSet) ?? Color.secondary
        case .auxiliaryFilters:
            return Color.accentColor
        }
    }

    /// The displayed source's reason, or `nil` when it can add. The
    /// auxiliary action is always available.
    private var displayedUnavailabilityText: String? {
        displayedChoice.source.flatMap(addUnavailabilityText)
    }

    private var isAddEnabled: Bool {
        isInteractionQuiet && displayedUnavailabilityText == nil
    }

    /// Performs the displayed choice: add the ND source, or open the
    /// auxiliary popup.
    private func activate(_ choice: FilterPlusChoice) {
        switch choice {
        case .source(let source):
            onAdd(source)
        case .auxiliaryFilters:
            // Closing the popup returns Plus to its preceding ND source.
            assistiveCandidate = nil
            onOpenAuxiliaryFilters()
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(tint.opacity(browsingIndex == nil ? 0.55 : 0.9), lineWidth: 1.5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(browsingIndex == nil ? 0.12 : 0.22))
            )
            .overlay {
                VStack(spacing: 3) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(tint.opacity(0.7))
                    Image(systemName: candidateChoice == .auxiliaryFilters ? "camera.filters" : "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isAddEnabled ? tint : tint.opacity(0.35))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(tint.opacity(0.7))
                }
            }
            .frame(width: 20, height: pickerHeight)
            .contentShape(Rectangle().inset(by: -12))
            // One gesture decides tap / browse from the touch's travel,
            // so the two never compete: a press that stays within the
            // stationary tolerance is a tap (add); travel to the drag
            // threshold browses sources until release (FILTER-PLUS-001).
            .gesture(pressGesture)
            .onChange(of: selectedSource) { _, _ in
                // A successful add moved the remembered source; the
                // element follows it again.
                assistiveCandidate = nil
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Add filter"))
            .accessibilityValue(Text(name(of: displayedChoice)))
            .accessibilityHint(Text(accessibilityHintText))
            // Add is assistive-visible only while the displayed source
            // can add (ND-A11Y-002): the button trait, the activation,
            // and the named action all follow `isAddEnabled`. The
            // element itself keeps one identity across that change so
            // VoiceOver focus survives stepping onto an unavailable
            // source; activation is therefore guarded rather than
            // removed. The auxiliary action is always activatable.
            .accessibilityAction {
                guard isAddEnabled else { return }
                activate(displayedChoice)
            }
            // The activation handler implies the button trait; take it
            // back while Add is unavailable so the element is not
            // presented as activatable.
            .accessibilityRemoveTraits(isAddEnabled ? [] : .isButton)
            // Stepping browses a transient displayed candidate
            // (FILTER-PLUS-004): nothing is added and the camera's
            // remembered source does not change until an add succeeds.
            .accessibilityAdjustableAction { direction in
                let current = choices.firstIndex(of: displayedChoice) ?? settledIndex
                let next: Int
                switch direction {
                case .increment: next = current + 1
                case .decrement: next = current - 1
                @unknown default: return
                }
                guard choices.indices.contains(next) else { return }
                assistiveCandidate = choices[next]
            }
            .accessibilityActions {
                if isAddEnabled, let source = displayedChoice.source {
                    Button("Add filter") { onAdd(source) }
                }
                Button("Open shooting filters") { activate(.auxiliaryFilters) }
            }
    }

    /// The reason the displayed source cannot add, else the usage hint
    /// for the displayed choice.
    private var accessibilityHintText: String {
        if let displayedUnavailabilityText {
            return displayedUnavailabilityText
        }
        switch displayedChoice {
        case .source(let source):
            return FilterWheelPresenter.plusAccessibilityHint(sourceName: sourceName(source))
        case .auxiliaryFilters:
            return String(localized: "Double-tap to open Shooting filters.")
        }
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if gesture == nil {
                    gesture = FilterSourcePlusGestureArbiter(settledIndex: settledIndex, sourceCount: choices.count)
                    browsingHaptic.prepare()
                }
                let wasBrowsing = gesture?.phase == .browsing
                guard gesture?.moved(translation: value.translation) == true else {
                    return
                }
                if wasBrowsing {
                    browsingHaptic.selectionChanged()
                }
                let candidate = gesture?.candidateIndex
                onBrowsingChanged(candidate.flatMap { choices.indices.contains($0) ? choices[$0] : nil })
            }
            .onEnded { _ in
                let outcome = gesture?.released() ?? .none
                gesture = nil
                onBrowsingChanged(nil)
                switch outcome {
                case .addBrowsed(let index):
                    // The browse settled on a different choice: add
                    // exactly one wheel from that source, or open the
                    // auxiliary popup. The view model refuses and
                    // reports when a source cannot add.
                    if choices.indices.contains(index) {
                        activate(choices[index])
                    }
                case .add:
                    // A tap acts on the displayed choice; when adding is
                    // unavailable the view model shows the reason.
                    activate(displayedChoice)
                case .none:
                    break
                }
            }
    }
}

extension Color {
    /// Maps the platform-neutral Filter Set color token to SwiftUI's
    /// system colors so both platforms read the same token.
    static func filterSet(_ token: FilterSetColor) -> Color {
        switch token {
        case .red: return .red
        // Red-orange and Yellow-orange sit visibly between their
        // neighbors; Yellow is a bright photographic yellow rather than
        // the system yellow, which reads as mustard beside them.
        case .redOrange: return Color(red: 0.98, green: 0.38, blue: 0.12)
        case .orange: return .orange
        case .yellowOrange: return Color(red: 1.0, green: 0.71, blue: 0.0)
        case .yellow: return Color(red: 1.0, green: 0.90, blue: 0.08)
        // No system yellow-green; a mid yellow-green that stays distinct
        // from both neighbors in light and dark appearance.
        case .yellowGreen: return Color(red: 0.60, green: 0.80, blue: 0.18)
        case .green: return .green
        case .teal: return .teal
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        }
    }
}

extension FilterSetColor {
    /// Localized color name — color is never the only identifying cue
    /// (FILTER-SET-005 / FILTER-A11Y-002).
    var localizedName: String {
        FilterWheelPresenter.opticalColorName(self)
    }
}
