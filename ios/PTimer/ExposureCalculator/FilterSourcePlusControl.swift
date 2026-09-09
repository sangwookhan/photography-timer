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
/// - vertical drag browses Standard / Filter Sets in inventory order,
///   reporting the candidate name so the parent can show the expanded
///   label; releasing settles the source without touching the stack;
/// - tap adds a Standard 0 or Filter Set Empty wheel for the settled
///   source (dimmed, with a reason, while adding is unavailable —
///   browsing stays enabled);
/// - long press opens Filter Set management.
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
    let onSelectSource: (FilterSource) -> Void
    let onAdd: () -> Void
    let onManage: () -> Void
    /// Candidate source while browsing, `nil` when idle. The parent
    /// renders the expanded, non-blocking label.
    let onBrowsingChanged: (FilterSource?) -> Void

    /// Vertical travel per source step while browsing.
    private static let stepDistance: CGFloat = 26
    /// Movement below this stays a press (tap or long press); at or
    /// above it the touch becomes a browse.
    private static let browseThreshold: CGFloat = 8

    @State private var browsingIndex: Int?
    @State private var pressStart: Date?
    @State private var maxTravel: CGFloat = 0
    @State private var didLongPress = false
    @State private var longPressTask: Task<Void, Never>?
    @State private var browsingHaptic = UISelectionFeedbackGenerator()

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
            .frame(width: 26, height: pickerHeight)
            .contentShape(Rectangle().inset(by: -9))
            // One gesture decides tap / long press / browse from the
            // touch's travel and duration, so the three never compete:
            // a press that stays put is a tap (add) or, held half a
            // second, a long press (manage); travel beyond the
            // threshold browses sources and settles on release.
            .gesture(pressGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Add filter"))
            .accessibilityValue(Text(sourceName(selectedSource)))
            .accessibilityHint(Text(addUnavailabilityText ?? String(localized: "Swipe up or down to choose Standard or a Filter Set, double-tap to add")))
            .accessibilityAddTraits(.isButton)
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
            .accessibilityAction(named: Text("Add filter")) {
                guard isAddEnabled else { return }
                onAdd()
            }
            .accessibilityAction(named: Text("Manage Filter Sets"), onManage)
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if pressStart == nil {
                    pressStart = Date()
                    maxTravel = 0
                    didLongPress = false
                    browsingHaptic.prepare()
                    longPressTask?.cancel()
                    longPressTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled, pressStart != nil, maxTravel < Self.browseThreshold else { return }
                        didLongPress = true
                        onManage()
                    }
                }
                maxTravel = max(maxTravel, abs(value.translation.height), abs(value.translation.width))
                guard maxTravel >= Self.browseThreshold, !didLongPress else { return }
                longPressTask?.cancel()
                // Drag up reveals the next source, drag down the
                // previous one, mirroring a wheel's row travel.
                let steps = Int((-value.translation.height / Self.stepDistance).rounded())
                let next = min(max(settledIndex + steps, 0), max(sources.count - 1, 0))
                if next != browsingIndex {
                    if browsingIndex != nil {
                        browsingHaptic.selectionChanged()
                    }
                    browsingIndex = next
                    onBrowsingChanged(sources.indices.contains(next) ? sources[next] : nil)
                }
            }
            .onEnded { _ in
                longPressTask?.cancel()
                longPressTask = nil
                defer {
                    pressStart = nil
                    maxTravel = 0
                    didLongPress = false
                    browsingIndex = nil
                    onBrowsingChanged(nil)
                }
                if didLongPress {
                    return
                }
                if let browsingIndex, sources.indices.contains(browsingIndex) {
                    onSelectSource(sources[browsingIndex])
                    return
                }
                if maxTravel < Self.browseThreshold, isAddEnabled {
                    onAdd()
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
