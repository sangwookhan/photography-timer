// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import PTimerKit
import SwiftUI

/// The Plus wheel (Filter Set contract, FILTER-PLUS): the trailing-edge
/// control of the wheel row while fewer than four actual wheels exist.
/// It is NOT an actual filter wheel — it selects the Filter Source the
/// next wheel is created from:
///
/// - tap adds a Standard 0 or Filter Set Empty wheel for the displayed
///   source, exactly once (FILTER-PLUS-003);
/// - vertical drag or fling browses Standard / Filter Sets in inventory
///   order, reporting the candidate name so the parent can show it in
///   the status row; releasing on a different source adds exactly one
///   wheel from that final source, while a return to the starting
///   source adds nothing (FR-1.13). The camera's remembered source
///   changes only when the add succeeds; a refused add shows its
///   reason in the status row and changes nothing;
/// - a stationary long press opens Filter Set management; movement
///   past the stationary tolerance cancels it, and once the drag
///   threshold is crossed browsing has won for the rest of the touch
///   (FILTER-PLUS-001).
///
/// At rest the compact control shows the candidate source's color as a
/// secondary cue; VoiceOver exposes it as an adjustable element with
/// explicit Add and Manage actions.
struct FilterSourcePlusControl: View {
    let sources: [FilterSource]
    let selectedSource: FilterSource
    let sourceName: (FilterSource) -> String
    let sourceColor: (FilterSource) -> FilterSetColor?
    let pickerHeight: CGFloat
    /// False while adding is unavailable (interaction in flight or the
    /// settled source has no usable row). Browsing stays enabled.
    let isAddEnabled: Bool
    let addUnavailabilityText: String?
    /// Explicit assistive-technology source selection (the adjustable
    /// value); it never adds.
    let onSelectSource: (FilterSource) -> Void
    /// Adds one wheel for the given source; the view model refuses and
    /// reports when the source cannot add.
    let onAdd: (FilterSource) -> Void
    let onManage: () -> Void
    /// Candidate source while browsing, `nil` when idle. The parent
    /// renders the expanded, non-blocking label.
    let onBrowsingChanged: (FilterSource?) -> Void

    /// Classifies the current touch (tap / long press / browse); `nil`
    /// between touches.
    @State private var gesture: FilterSourcePlusGestureArbiter?
    @State private var longPressTask: Task<Void, Never>?
    @State private var browsingHaptic = UISelectionFeedbackGenerator()

    private var browsingIndex: Int? {
        gesture?.phase == .browsing ? gesture?.candidateIndex : nil
    }

    private var settledIndex: Int {
        sources.firstIndex(of: selectedSource) ?? 0
    }

    private var candidateSource: FilterSource {
        if let browsingIndex, sources.indices.contains(browsingIndex) {
            return sources[browsingIndex]
        }
        return selectedSource
    }

    private var tint: Color {
        sourceColor(candidateSource).map(Color.filterSet) ?? Color.secondary
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
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isAddEnabled ? tint : tint.opacity(0.35))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(tint.opacity(0.7))
                }
            }
            .frame(width: 20, height: pickerHeight)
            .contentShape(Rectangle().inset(by: -12))
            // One gesture decides tap / long press / browse from the
            // touch's travel and duration, so the three never compete:
            // a press that stays within the stationary tolerance is a
            // tap (add) or, held half a second, a long press (manage);
            // travel to the drag threshold cancels the long press and
            // browses sources until release (FILTER-PLUS-001).
            .gesture(pressGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Add filter"))
            .accessibilityValue(Text(sourceName(selectedSource)))
            .accessibilityHint(Text(addUnavailabilityText ?? FilterWheelPresenter.plusAccessibilityHint(sourceName: sourceName(selectedSource))))
            .accessibilityAddTraits(.isButton)
            // Activation (double-tap) adds the displayed source once;
            // no touch drag or long press is needed with VoiceOver.
            .accessibilityAction { onAdd(selectedSource) }
            .accessibilityAdjustableAction { direction in
                let next: Int
                switch direction {
                case .increment: next = settledIndex + 1
                case .decrement: next = settledIndex - 1
                @unknown default: return
                }
                guard sources.indices.contains(next) else { return }
                onSelectSource(sources[next])
            }
            .accessibilityAction(named: Text("Add filter")) { onAdd(selectedSource) }
            .accessibilityAction(named: Text("Manage Filter Sets"), onManage)
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if gesture == nil {
                    gesture = FilterSourcePlusGestureArbiter(settledIndex: settledIndex, sourceCount: sources.count)
                    browsingHaptic.prepare()
                    longPressTask?.cancel()
                    longPressTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(FilterSourcePlusGestureArbiter.longPressDuration * 1_000_000_000))
                        guard !Task.isCancelled, gesture?.deadlineElapsed() == true else { return }
                        onManage()
                    }
                }
                let wasBrowsing = gesture?.phase == .browsing
                guard gesture?.moved(translation: value.translation) == true else {
                    if gesture?.phase != .pressing {
                        // Past the stationary tolerance: the long press
                        // can no longer complete.
                        longPressTask?.cancel()
                    }
                    return
                }
                longPressTask?.cancel()
                if wasBrowsing {
                    browsingHaptic.selectionChanged()
                }
                let candidate = gesture?.candidateIndex
                onBrowsingChanged(candidate.flatMap { sources.indices.contains($0) ? sources[$0] : nil })
            }
            .onEnded { _ in
                longPressTask?.cancel()
                longPressTask = nil
                let outcome = gesture?.released() ?? .none
                gesture = nil
                onBrowsingChanged(nil)
                switch outcome {
                case .addBrowsed(let index):
                    // The browse settled on a different source: add
                    // exactly one wheel from it. The view model refuses
                    // and reports when it cannot add.
                    if sources.indices.contains(index) {
                        onAdd(sources[index])
                    }
                case .add:
                    // A tap adds the displayed source; when adding is
                    // unavailable the view model shows the reason.
                    onAdd(selectedSource)
                case .managed, .none:
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
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        }
    }
}

extension FilterSetColor {
    /// Localized color name — color is never the only identifying cue
    /// (FILTER-SET-005 / FILTER-A11Y-002).
    var localizedName: String {
        switch self {
        case .red: return String(localized: "Red")
        case .orange: return String(localized: "Orange")
        case .yellow: return String(localized: "Yellow")
        case .green: return String(localized: "Green")
        case .mint: return String(localized: "Mint")
        case .teal: return String(localized: "Teal")
        case .cyan: return String(localized: "Cyan")
        case .blue: return String(localized: "Blue")
        case .indigo: return String(localized: "Indigo")
        case .purple: return String(localized: "Purple")
        case .pink: return String(localized: "Pink")
        case .brown: return String(localized: "Brown")
        }
    }
}
