// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

public struct CompactRemainingScaleLayer: Equatable {
    public let fraction: Double
}

/// Identity surface a timer presents in the dock and the expanded
/// sheet. Compact cards render the colored capsule
/// (`markerText` + `tintSlot`) and may render `filmDescriptor` as
/// inline text. Large cards compose `fullCameraLabel` and
/// `filmDescriptor` into the row title and route `sourceLabel` into
/// the subtitle. VoiceOver consumers read every field.
///
/// `markerText` stays the only required string — manual / pre-camera-
/// slot timers fall back to `T<order>` so the dock never renders an
/// empty badge.
public struct BottomSheetIdentityCue: Equatable {
    /// Number of distinct identity tint slots. Portable value owned by the
    /// kit; the host app maps a slot index to a concrete color.
    public static let tintSlotCount = 6

    public let markerText: String
    public let tintSlot: Int
    /// Full camera-slot label (e.g. `"Camera 2"`). `nil` when the
    /// timer has no slot identity, in which case the large title
    /// falls through to the timer name.
    public let fullCameraLabel: String?
    /// Film descriptor captured at start time. Either the canonical
    /// film name (with optional profile qualifier) or `"No film"`
    /// for the digital workflow. `nil` indicates a timer that
    /// predates the identity-snapshot fields.
    public let filmDescriptor: String?
    /// Exposure-source label sentence (e.g. `"Adjusted Shutter"`).
    /// `nil` for legacy timers without a captured source.
    public let sourceLabel: String?
}

public struct BottomSheetCompactItem: Identifiable, Equatable {
    public let id: UUID
    public let status: TimerStatus
    public let identityCue: BottomSheetIdentityCue
    public let primaryRemainingText: String
    public let secondaryTotalText: String?
    public let tertiaryStatusText: String?
    /// Inline film/digital descriptor rendered inside the compact
    /// card so the slot badge (`C2`) is paired with the film name
    /// (`CHS 100 II`) without forcing the user to expand the sheet.
    /// `nil` for timers without an identity snapshot — the legacy
    /// rendering shows only the time text in that case.
    public let identityFilmText: String?
    public let showsDecorativeTimeline: Bool
    public let sixtySecondLayer: CompactRemainingScaleLayer
    public let sixtyMinuteLayer: CompactRemainingScaleLayer?
    public let originalScaleLayer: CompactRemainingScaleLayer?

    public var visibleLayerCount: Int {
        [originalScaleLayer, sixtyMinuteLayer, sixtySecondLayer as CompactRemainingScaleLayer?]
            .compactMap { $0 }
            .count
    }
}

public struct BottomSheetLargeItem: Identifiable, Equatable {
    public let id: UUID
    public let title: String?
    /// Identity-first subtitle composed from the exposure source +
    /// the original timer name. e.g. `"Adjusted Shutter · 16 stops"`.
    /// Rendered below `title` on the large row so the camera/film
    /// identity stays at the top of the card.
    public let identitySubtitle: String?
    /// Full VoiceOver label composed from camera + film + source +
    /// status. Captured here so the row view does not have to
    /// re-derive the same composition rule.
    public let voiceOverLabel: String
    public let statusLabel: String
    public let status: TimerStatus
    public let identityCue: BottomSheetIdentityCue
    public let remainingText: String
    public let totalDurationText: String?
    public let timingText: String?
    public let contextText: String?
    public let progress: Double
    public let actions: [BottomSheetLargeAction]
    /// Stable per-timer sequence number (the timer's creation order),
    /// shown as a bare number near the identity badge to distinguish
    /// repeated timers that share the same camera/film/exposure. Stable
    /// across deletion, sorting, and restore — not a volatile list index.
    public let sequenceNumberText: String
}

public struct TimerWorkspaceSection: Identifiable, Equatable {
    /// Section title strings used by both the snapshot factory and
    /// the view layer. Lifted into named constants so the view can
    /// identify the completed section without re-typing the literal
    /// (and so a future copy change does not silently desynchronize
    /// the writer and the reader).
    public static let activeTitle = "Active"
    /// Title for the terminal-records section. Holds both completed and
    /// canceled timers, so it reads "History" rather than naming only
    /// completion.
    public static let historyTitle = "History"

    public let title: String
    public let items: [BottomSheetLargeItem]

    public var id: String { title }

    /// True when this section contains the terminal (completed +
    /// canceled) history records. Used by the full-screen Timers window
    /// to scope the `Clear` affordance to this section's header instead
    /// of a top-level summary strip.
    public var isCompletedSection: Bool {
        title == Self.historyTitle
    }
}

public struct BottomSheetWorkspaceSnapshot: Equatable {
    public static let compactVisibleLimit = 3

    /// Number of completed timers, used to determine if "Clear" button should be shown in the large workspace.
    public let completedCount: Int

    /// The top-N timers to be shown in the compact mini dock.
    public let compactItems: [BottomSheetCompactItem]

    /// Number of timers not shown in the compact dock due to the visible limit.
    public let hiddenCompactItemCount: Int

    /// Sections for the large workspace list (e.g. "Active", "History").
    public let sections: [TimerWorkspaceSection]

    /// Defines the number of visible remaining scale layers based on timer duration.
    ///
    /// The policy is:
    /// - < 60s: 1 layer (sixtySecondLayer only)
    /// - 60s <= d < 3600s: 2 layers (sixtySecondLayer + sixtyMinuteLayer)
    /// - >= 3600s: 3 layers (sixtySecondLayer + sixtyMinuteLayer + originalScaleLayer)
    public static func compactLayerCount(for duration: TimeInterval) -> Int {
        if duration < 60 {
            return 1
        } else if duration < 3600 {
            return 2
        } else {
            return 3
        }
    }

    public static func make(
        from timers: [RunningTimerItem],
        formatRemaining: (TimeInterval) -> String,
        formatShutter: (TimeInterval) -> String,
        ndNotationMode: NDNotationMode,
        timeContext: (RunningTimerItem) -> String?,
        compactCompletedSupplementaryText: (RunningTimerItem) -> String?
    ) -> BottomSheetWorkspaceSnapshot {
        let orderedTimers = TimerWorkspaceOrdering.sort(timers)

        let compactItems = orderedTimers
            .prefix(Self.compactVisibleLimit)
            .map { timer in
                let identityCue = identityCue(for: timer)

                return BottomSheetCompactItem(
                    id: timer.id,
                    status: timer.status,
                    identityCue: identityCue,
                    primaryRemainingText: compactRemainingText(
                        for: timer,
                        formatRemaining: formatRemaining,
                        compactCompletedSupplementaryText: compactCompletedSupplementaryText
                    ),
                    secondaryTotalText: compactSecondaryText(
                        for: timer,
                        compactCompletedSupplementaryText: compactCompletedSupplementaryText
                    ),
                    tertiaryStatusText: compactTertiaryText(
                        for: timer,
                        compactCompletedSupplementaryText: compactCompletedSupplementaryText
                    ),
                    identityFilmText: compactFilmText(for: timer),
                    showsDecorativeTimeline: timer.status == .running || timer.status == .paused,
                    sixtySecondLayer: compactSixtySecondLayer(for: timer),
                    sixtyMinuteLayer: compactSixtyMinuteLayer(for: timer),
                    originalScaleLayer: compactOriginalScaleLayer(for: timer)
                )
            }

        let sections = makeSections(
            from: orderedTimers,
            formatRemaining: formatRemaining,
            formatShutter: formatShutter,
            ndNotationMode: ndNotationMode,
            timeContext: timeContext
        )

        return BottomSheetWorkspaceSnapshot(
            completedCount: timers.filter { $0.status == .completed }.count,
            compactItems: compactItems,
            hiddenCompactItemCount: max(0, orderedTimers.count - compactItems.count),
            sections: sections
        )
    }

    public var compactOverflowText: String? {
        guard hiddenCompactItemCount > 0 else {
            return nil
        }

        return "+\(hiddenCompactItemCount)"
    }

    private static func makeSections(
        from timers: [RunningTimerItem],
        formatRemaining: (TimeInterval) -> String,
        formatShutter: (TimeInterval) -> String,
        ndNotationMode: NDNotationMode,
        timeContext: (RunningTimerItem) -> String?
    ) -> [TimerWorkspaceSection] {
        let activeTimers = timers.filter { $0.status == .running || $0.status == .paused }
        let completedTimers = timers.filter { $0.status == .completed || $0.status == .canceled }

        return [
            makeSection(
                title: TimerWorkspaceSection.activeTitle,
                timers: activeTimers,
                formatRemaining: formatRemaining,
                formatShutter: formatShutter,
                ndNotationMode: ndNotationMode,
                timeContext: timeContext
            ),
            makeSection(
                title: TimerWorkspaceSection.historyTitle,
                timers: completedTimers,
                formatRemaining: formatRemaining,
                formatShutter: formatShutter,
                ndNotationMode: ndNotationMode,
                timeContext: timeContext
            ),
        ].compactMap { $0 }
    }

    private static func makeSection(
        title: String,
        timers: [RunningTimerItem],
        formatRemaining: (TimeInterval) -> String,
        formatShutter: (TimeInterval) -> String,
        ndNotationMode: NDNotationMode,
        timeContext: (RunningTimerItem) -> String?
    ) -> TimerWorkspaceSection? {
        guard !timers.isEmpty else {
            return nil
        }

        return TimerWorkspaceSection(
            title: title,
            items: timers.map { timer in
                let totalDurationText = largeTotalDurationText(for: timer, formatRemaining: formatRemaining)
                let contextText = largeContextText(
                    for: timer,
                    ndNotationMode: ndNotationMode,
                    formatShutter: formatShutter
                )
                let identityCue = identityCue(for: timer)
                let fallbackTitle = largeTitleText(
                    for: timer,
                    totalDurationText: totalDurationText,
                    contextText: contextText
                )
                let identityTitle = largeIdentityTitle(for: timer, fallback: fallbackTitle)

                return BottomSheetLargeItem(
                    id: timer.id,
                    title: identityTitle,
                    identitySubtitle: largeIdentitySubtitle(
                        for: timer,
                        formatRemaining: formatRemaining
                    ),
                    voiceOverLabel: largeVoiceOverLabel(
                        for: timer,
                        statusLabel: visibleStatusLabel(for: timer.status)
                    ),
                    statusLabel: visibleStatusLabel(for: timer.status),
                    status: timer.status,
                    identityCue: identityCue,
                    remainingText: largeRemainingText(for: timer, formatRemaining: formatRemaining),
                    // The final exposure value now lives on the second
                    // line (`<source> <value>`); the right column shows
                    // timer state only, so no duration is repeated here
                    // (no slash-separated pair). PTIMER-187.
                    totalDurationText: nil,
                    timingText: largeTimingText(for: timer, timeContext: timeContext),
                    contextText: contextText,
                    progress: progress(for: timer),
                    actions: largeActions(for: timer.status),
                    sequenceNumberText: "\(timer.order)"
                )
            }
        )
    }

    private static func identityCue(for timer: RunningTimerItem) -> BottomSheetIdentityCue {
        let snapshot = timer.identitySnapshot
        let markerText = snapshot.flatMap(TimerCardIdentityPresenter.compactCameraLabel(for:))
            ?? "T\(timer.order)"
        // Tint slot for camera-slot timers comes from the slot id —
        // this gives `Camera 1` and `Camera 2` consistent palette
        // colors across the dock, sheet, and process restarts.
        // Pre-snapshot timers fall back to the prior id-derived hash
        // so existing tint behavior is preserved for them.
        let tintSlot: Int
        if let slotID = snapshot?.cameraSlot?.id {
            tintSlot = stableIdentityTintSlot(forSlot: slotID)
        } else {
            tintSlot = stableIdentityTintSlot(for: timer.id)
        }
        return BottomSheetIdentityCue(
            markerText: markerText,
            tintSlot: tintSlot,
            fullCameraLabel: snapshot.flatMap(TimerCardIdentityPresenter.fullCameraLabel(for:)),
            filmDescriptor: snapshot.map(TimerCardIdentityPresenter.filmDescriptor(for:)),
            sourceLabel: snapshot.map { TimerCardIdentityPresenter.sourceLabel(for: $0.exposureSource) }
        )
    }

    private static func stableIdentityTintSlot(forSlot slotID: CameraSlotID) -> Int {
        slotID.rawValue.utf8.reduce(0) { partial, byte in
            ((partial * 33) + Int(byte)) % BottomSheetIdentityCue.tintSlotCount
        }
    }

    private static func compactFilmText(for timer: RunningTimerItem) -> String? {
        timer.identitySnapshot.map(TimerCardIdentityPresenter.filmDescriptor(for:))
    }

    /// Identity-first title for the large card. Format examples:
    ///   - `"Camera 2 · CHS 100 II"`
    ///   - `"Camera 4 · No film"`
    /// Falls back to the legacy timer-name-derived title when the
    /// timer has no identity snapshot.
    private static func largeIdentityTitle(
        for timer: RunningTimerItem,
        fallback: String?
    ) -> String? {
        guard let snapshot = timer.identitySnapshot else {
            return fallback
        }

        let cameraLabel = TimerCardIdentityPresenter.fullCameraLabel(for: snapshot)
        let filmLabel = TimerCardIdentityPresenter.filmDescriptor(for: snapshot)

        switch (cameraLabel, filmLabel.isEmpty) {
        case (let label?, false):
            return "\(label) · \(filmLabel)"
        case (let label?, true):
            return label
        case (nil, false):
            return filmLabel
        case (nil, true):
            return fallback
        }
    }

    /// Second line: the exposure source paired with the final exposure
    /// value (the timer's total duration), e.g. `"Corrected Exposure
    /// 01:40.617"`. The film name and profile qualifier are not
    /// repeated here — they live in the title — and the duration
    /// appears only on this line, never again in the right column
    /// (PTIMER-187). `nil` for timers without a captured source.
    private static func largeIdentitySubtitle(
        for timer: RunningTimerItem,
        formatRemaining: (TimeInterval) -> String
    ) -> String? {
        guard let source = timer.identitySnapshot?.exposureSource else {
            return nil
        }

        let sourceLabel = TimerCardIdentityPresenter.sourceLabel(for: source)
        guard timer.duration > 0 else {
            return sourceLabel
        }

        return String(format: Copy.exposureLine, sourceLabel, formatRemaining(timer.duration))
    }

    /// Localization-ready templates for composed card copy. Positional
    /// placeholders so source/value order can move when localized.
    private enum Copy {
        static let exposureLine = "%1$@ %2$@"
        static let remainingSuffix = "%1$@ left"
    }

    /// VoiceOver label combining slot, film, source, and status.
    /// Example: `"Camera 2, CHS 100 II, Adjusted Shutter timer, running"`.
    /// Status text is appended; the row view inserts the remaining
    /// time after this label so screen readers hear duration last.
    private static func largeVoiceOverLabel(
        for timer: RunningTimerItem,
        statusLabel: String
    ) -> String {
        var components: [String] = []

        if let snapshot = timer.identitySnapshot {
            if let camera = TimerCardIdentityPresenter.fullCameraLabel(for: snapshot) {
                components.append(camera)
            }
            components.append(TimerCardIdentityPresenter.filmDescriptor(for: snapshot))
            components.append(
                "\(TimerCardIdentityPresenter.sourceLabel(for: snapshot.exposureSource)) timer"
            )
        } else {
            // Pre-snapshot timer: fall back to the legacy name so
            // VoiceOver still has something concrete to say.
            let trimmed = timer.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                components.append(trimmed)
            }
        }

        components.append(statusLabel.lowercased())
        return components.joined(separator: ", ")
    }

    private static func stableIdentityTintSlot(for id: UUID) -> Int {
        id.uuidString.utf8.reduce(0) { partial, byte in
            ((partial * 33) + Int(byte)) % BottomSheetIdentityCue.tintSlotCount
        }
    }

    private static func progress(for timer: RunningTimerItem) -> Double {
        guard timer.duration > 0 else {
            return 0
        }

        return min(max(timer.elapsedTime / timer.duration, 0), 1)
    }

    private static func compactSixtySecondLayer(for timer: RunningTimerItem) -> CompactRemainingScaleLayer {
        CompactRemainingScaleLayer(
            fraction: repeatingRemainingFraction(
                remainingTime: timer.remainingTime,
                unitDuration: 60,
                status: timer.status
            )
        )
    }

    private static func compactSixtyMinuteLayer(for timer: RunningTimerItem) -> CompactRemainingScaleLayer? {
        guard compactLayerCount(for: timer.duration) >= 2 else {
            return nil
        }

        return CompactRemainingScaleLayer(
            fraction: repeatingRemainingFraction(
                remainingTime: timer.remainingTime,
                unitDuration: 3_600,
                status: timer.status
            )
        )
    }

    private static func compactOriginalScaleLayer(for timer: RunningTimerItem) -> CompactRemainingScaleLayer? {
        guard compactLayerCount(for: timer.duration) >= 3 else {
            return nil
        }

        switch timer.status {
        case .completed, .canceled:
            return CompactRemainingScaleLayer(fraction: 0)
        case .running, .paused:
            let cappedOriginalDuration = min(max(timer.duration, 0), 86_400)
            let cappedRemainingTime = min(max(timer.remainingTime, 0), cappedOriginalDuration)
            let fraction = cappedOriginalDuration > 0 ? cappedRemainingTime / 86_400 : 0
            return CompactRemainingScaleLayer(fraction: min(max(fraction, 0), 1))
        }
    }

    private static func repeatingRemainingFraction(
        remainingTime: TimeInterval,
        unitDuration: TimeInterval,
        status: TimerStatus
    ) -> Double {
        switch status {
        case .completed, .canceled:
            return 0
        case .running, .paused:
            guard unitDuration > 0 else {
                return 0
            }

            let clampedRemaining = max(0, remainingTime)
            guard clampedRemaining > 0 else {
                return 0
            }

            let remainder = clampedRemaining.truncatingRemainder(dividingBy: unitDuration)
            if remainder == 0 {
                return 1
            }

            return min(max(remainder / unitDuration, 0), 1)
        }
    }

    private static func largeActions(for status: TimerStatus) -> [BottomSheetLargeAction] {
        switch status {
        case .running:
            return [.pause, .clone, .cancel]
        case .paused:
            return [.resume, .clone, .cancel, .remove]
        case .completed, .canceled:
            return [.clone, .remove]
        }
    }

    private static func compactRemainingText(
        for timer: RunningTimerItem,
        formatRemaining: (TimeInterval) -> String,
        compactCompletedSupplementaryText: (RunningTimerItem) -> String?
    ) -> String {
        switch timer.status {
        case .running, .paused:
            return compactDurationText(timer.remainingTime)
        case .completed:
            return "Done"
        case .canceled:
            return "Canceled"
        }
    }

    private static func compactSecondaryText(
        for timer: RunningTimerItem,
        compactCompletedSupplementaryText: (RunningTimerItem) -> String?
    ) -> String? {
        switch timer.status {
        case .completed, .canceled:
            guard timer.duration > 0 else {
                return nil
            }

            return compactDurationText(timer.duration)
        case .running, .paused:
            guard timer.duration > 0 else {
                return nil
            }

            return compactDurationText(timer.duration)
        }
    }

    private static func compactTertiaryText(
        for timer: RunningTimerItem,
        compactCompletedSupplementaryText: (RunningTimerItem) -> String?
    ) -> String? {
        guard timer.status == .completed else {
            return nil
        }

        return compactCompletedSupplementaryText(timer)
    }

    private static func largeRemainingText(
        for timer: RunningTimerItem,
        formatRemaining: (TimeInterval) -> String
    ) -> String {
        switch timer.status {
        case .running, .paused:
            // Right column shows timer state only; the total/final
            // value lives on the second line, so the remaining time
            // carries a `left` qualifier and never forms a duration
            // pair (PTIMER-187).
            return String(format: Copy.remainingSuffix, formatRemaining(timer.remainingTime))
        case .completed:
            return "Done"
        case .canceled:
            // Terminal state only as the primary value; the
            // remaining-at-cancel moves to the meta line so the big
            // value is not a combined "Canceled · N left" string
            // (PTIMER-198).
            return "Canceled"
        }
    }

    /// Meta/timing line. For canceled timers the remaining-at-cancel
    /// ("N left") is appended here rather than fused into the primary
    /// state value (PTIMER-198).
    private static func largeTimingText(
        for timer: RunningTimerItem,
        timeContext: (RunningTimerItem) -> String?
    ) -> String? {
        let base = timeContext(timer)
        guard timer.status == .canceled,
              let remaining = timer.canceledRemainingTime,
              remaining > 0 else {
            return base
        }
        let remainingMeta = "\(compactDurationText(remaining)) left"
        guard let base, !base.isEmpty else {
            return remainingMeta
        }
        return "\(base) · \(remainingMeta)"
    }

    private static func largeTotalDurationText(
        for timer: RunningTimerItem,
        formatRemaining: (TimeInterval) -> String
    ) -> String? {
        guard timer.duration > 0 else {
            return nil
        }

        return formatRemaining(timer.duration)
    }

    /// Basis line rendered from structured exposure inputs in the
    /// current ND notation mode — inputs only, never the final value
    /// (PTIMER-187). `nil` when the timer has no structured ND/base
    /// values (legacy/manual), which omits the line.
    private static func largeContextText(
        for timer: RunningTimerItem,
        ndNotationMode: NDNotationMode,
        formatShutter: (TimeInterval) -> String
    ) -> String? {
        TimerBasisPresenter.basisText(
            for: timer,
            notationMode: ndNotationMode,
            formatShutter: formatShutter
        )
    }

    private static func largeTitleText(
        for timer: RunningTimerItem,
        totalDurationText: String?,
        contextText: String?
    ) -> String? {
        let rawTitle = timer.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTitle.isEmpty else {
            return nil
        }

        var normalizedTitle = rawTitle

        if let totalDurationText, normalizedTitle.contains(totalDurationText) {
            normalizedTitle = normalizedTitle
                .replacingOccurrences(of: totalDurationText, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " -:."))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !normalizedTitle.isEmpty else {
            return nil
        }

        if let contextText, contextText.localizedCaseInsensitiveContains(normalizedTitle) {
            return nil
        }

        if normalizedTitle == "Timer" || normalizedTitle == "Manual timer" {
            return nil
        }

        return normalizedTitle
    }

    private static func visibleStatusLabel(for status: TimerStatus) -> String {
        switch status {
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .completed:
            return "Done"
        case .canceled:
            return "Canceled"
        }
    }

    public static func compactDurationText(_ duration: TimeInterval) -> String {
        let clamped = max(duration, 0)

        if clamped < 10 {
            let roundedToTenth = (clamped * 10).rounded() / 10
            return String(format: "%.1fs", roundedToTenth)
        }

        let roundedDown = Int(clamped.rounded(.down))

        if roundedDown < 60 {
            return "\(roundedDown)s"
        }

        if roundedDown < 3_600 {
            let minutes = roundedDown / 60
            let seconds = roundedDown % 60
            return String(format: "%02d:%02d", minutes, seconds)
        }

        let units: [(label: String, seconds: Int)] = [
            ("y", 31_536_000),
            ("m", 2_592_000),
            ("d", 86_400),
            ("h", 3_600),
            ("m", 60),
        ]

        var remaining = roundedDown
        var parts: [String] = []

        for unit in units {
            guard remaining >= unit.seconds else {
                continue
            }

            let value = remaining / unit.seconds
            remaining %= unit.seconds
            parts.append("\(value)\(unit.label)")

            if parts.count == 2 {
                break
            }
        }

        if parts.isEmpty {
            return "\(roundedDown)s"
        }

        return parts.joined(separator: " ")
    }
}
