import Combine
import SwiftUI

struct CompactRemainingScaleLayer: Equatable {
    let fraction: Double
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
struct BottomSheetIdentityCue: Equatable {
    let markerText: String
    let tintSlot: Int
    /// Full camera-slot label (e.g. `"Camera 2"`). `nil` when the
    /// timer has no slot identity, in which case the large title
    /// falls through to the timer name.
    let fullCameraLabel: String?
    /// Film descriptor captured at start time. Either the canonical
    /// film name (with optional profile qualifier) or `"No film"`
    /// for the digital workflow. `nil` indicates a timer that
    /// predates the identity-snapshot fields.
    let filmDescriptor: String?
    /// Exposure-source label sentence (e.g. `"Adjusted Shutter"`).
    /// `nil` for legacy timers without a captured source.
    let sourceLabel: String?
}

struct BottomSheetCompactItem: Identifiable, Equatable {
    let id: UUID
    let status: TimerStatus
    let identityCue: BottomSheetIdentityCue
    let primaryRemainingText: String
    let secondaryTotalText: String?
    let tertiaryStatusText: String?
    /// Inline film/digital descriptor rendered inside the compact
    /// card so the slot badge (`C2`) is paired with the film name
    /// (`CHS 100 II`) without forcing the user to expand the sheet.
    /// `nil` for timers without an identity snapshot — the legacy
    /// rendering shows only the time text in that case.
    let identityFilmText: String?
    let showsDecorativeTimeline: Bool
    let sixtySecondLayer: CompactRemainingScaleLayer
    let sixtyMinuteLayer: CompactRemainingScaleLayer?
    let originalScaleLayer: CompactRemainingScaleLayer?

    var visibleLayerCount: Int {
        [originalScaleLayer, sixtyMinuteLayer, sixtySecondLayer as CompactRemainingScaleLayer?]
            .compactMap { $0 }
            .count
    }
}

struct BottomSheetLargeItem: Identifiable, Equatable {
    let id: UUID
    let title: String?
    /// Identity-first subtitle composed from the exposure source +
    /// the original timer name. e.g. `"Adjusted Shutter · 16 stops"`.
    /// Rendered below `title` on the large row so the camera/film
    /// identity stays at the top of the card.
    let identitySubtitle: String?
    /// Full VoiceOver label composed from camera + film + source +
    /// status. Captured here so the row view does not have to
    /// re-derive the same composition rule.
    let voiceOverLabel: String
    let statusLabel: String
    let status: TimerStatus
    let identityCue: BottomSheetIdentityCue
    let remainingText: String
    let totalDurationText: String?
    let timingText: String?
    let contextText: String?
    let progress: Double
    let actions: [BottomSheetLargeAction]
}

struct TimerWorkspaceSection: Identifiable, Equatable {
    /// Section title strings used by both the snapshot factory and
    /// the view layer. Lifted into named constants so the view can
    /// identify the completed section without re-typing the literal
    /// (and so a future copy change does not silently desynchronize
    /// the writer and the reader).
    static let activeTitle = "Active"
    static let completedTitle = "Recently Completed"

    let title: String
    let items: [BottomSheetLargeItem]

    var id: String { title }

    /// True when this section contains the recently-completed
    /// timers. Used by the full-screen Timers window to scope the
    /// `Clear` affordance to this section's header instead of a
    /// top-level summary strip.
    var isCompletedSection: Bool {
        title == Self.completedTitle
    }
}

struct BottomSheetWorkspaceSnapshot: Equatable {
    static let compactVisibleLimit = 3

    /// Number of completed timers, used to determine if "Clear" button should be shown in the large workspace.
    let completedCount: Int

    /// The top-N timers to be shown in the compact mini dock.
    let compactItems: [BottomSheetCompactItem]

    /// Number of timers not shown in the compact dock due to the visible limit.
    let hiddenCompactItemCount: Int

    /// Sections for the large workspace list (e.g. "Active", "Recently Completed").
    let sections: [TimerWorkspaceSection]

    /// Defines the number of visible remaining scale layers based on timer duration.
    ///
    /// The policy is:
    /// - < 60s: 1 layer (sixtySecondLayer only)
    /// - 60s <= d < 3600s: 2 layers (sixtySecondLayer + sixtyMinuteLayer)
    /// - >= 3600s: 3 layers (sixtySecondLayer + sixtyMinuteLayer + originalScaleLayer)
    static func compactLayerCount(for duration: TimeInterval) -> Int {
        if duration < 60 {
            return 1
        } else if duration < 3600 {
            return 2
        } else {
            return 3
        }
    }

    static func make(
        from timers: [RunningTimerItem],
        formatRemaining: (TimeInterval) -> String,
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
                    showsDecorativeTimeline: timer.status != .completed,
                    sixtySecondLayer: compactSixtySecondLayer(for: timer),
                    sixtyMinuteLayer: compactSixtyMinuteLayer(for: timer),
                    originalScaleLayer: compactOriginalScaleLayer(for: timer)
                )
            }

        let sections = makeSections(
            from: orderedTimers,
            formatRemaining: formatRemaining,
            timeContext: timeContext
        )

        return BottomSheetWorkspaceSnapshot(
            completedCount: timers.filter { $0.status == .completed }.count,
            compactItems: compactItems,
            hiddenCompactItemCount: max(0, orderedTimers.count - compactItems.count),
            sections: sections
        )
    }

    var compactOverflowText: String? {
        guard hiddenCompactItemCount > 0 else {
            return nil
        }

        return "+\(hiddenCompactItemCount)"
    }

    private static func makeSections(
        from timers: [RunningTimerItem],
        formatRemaining: (TimeInterval) -> String,
        timeContext: (RunningTimerItem) -> String?
    ) -> [TimerWorkspaceSection] {
        let activeTimers = timers.filter { $0.status != .completed }
        let completedTimers = timers.filter { $0.status == .completed }

        return [
            makeSection(
                title: TimerWorkspaceSection.activeTitle,
                timers: activeTimers,
                formatRemaining: formatRemaining,
                timeContext: timeContext
            ),
            makeSection(
                title: TimerWorkspaceSection.completedTitle,
                timers: completedTimers,
                formatRemaining: formatRemaining,
                timeContext: timeContext
            ),
        ].compactMap { $0 }
    }

    private static func makeSection(
        title: String,
        timers: [RunningTimerItem],
        formatRemaining: (TimeInterval) -> String,
        timeContext: (RunningTimerItem) -> String?
    ) -> TimerWorkspaceSection? {
        guard !timers.isEmpty else {
            return nil
        }

        return TimerWorkspaceSection(
            title: title,
            items: timers.map { timer in
                let totalDurationText = largeTotalDurationText(for: timer, formatRemaining: formatRemaining)
                let contextText = largeContextText(for: timer)
                let identityCue = identityCue(for: timer)
                let identityTitle = largeIdentityTitle(for: timer, fallback: largeTitleText(
                    for: timer,
                    totalDurationText: totalDurationText,
                    contextText: contextText
                ))

                return BottomSheetLargeItem(
                    id: timer.id,
                    title: identityTitle,
                    identitySubtitle: largeIdentitySubtitle(
                        for: timer,
                        fallback: largeTitleText(
                            for: timer,
                            totalDurationText: totalDurationText,
                            contextText: contextText
                        )
                    ),
                    voiceOverLabel: largeVoiceOverLabel(
                        for: timer,
                        statusLabel: visibleStatusLabel(for: timer.status)
                    ),
                    statusLabel: visibleStatusLabel(for: timer.status),
                    status: timer.status,
                    identityCue: identityCue,
                    remainingText: largeRemainingText(for: timer, formatRemaining: formatRemaining),
                    totalDurationText: totalDurationText,
                    timingText: timeContext(timer),
                    contextText: contextText,
                    progress: progress(for: timer),
                    actions: largeActions(for: timer.status)
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
            ((partial * 33) + Int(byte)) % BottomSheetIdentityPalette.slotCount
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

    /// Identity-first subtitle composed from exposure source and the
    /// legacy timer name. Renders as `"Adjusted Shutter · 16 stops - 832255.3s"`,
    /// keeping calculation/source detail visible without burying the
    /// camera/film identity above it. `nil` when nothing meaningful
    /// is available to compose.
    private static func largeIdentitySubtitle(
        for timer: RunningTimerItem,
        fallback: String?
    ) -> String? {
        guard let source = timer.identitySnapshot?.exposureSource else {
            return nil
        }

        let sourceLabel = TimerCardIdentityPresenter.sourceLabel(for: source)
        let trimmedName = (fallback ?? timer.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return sourceLabel
        }

        return "\(sourceLabel) · \(trimmedName)"
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
            ((partial * 33) + Int(byte)) % BottomSheetIdentityPalette.slotCount
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
        case .completed:
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
        case .completed:
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
            return [.pause]
        case .paused:
            return [.resume, .remove]
        case .completed:
            return [.startAgain, .remove]
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
        }
    }

    private static func compactSecondaryText(
        for timer: RunningTimerItem,
        compactCompletedSupplementaryText: (RunningTimerItem) -> String?
    ) -> String? {
        switch timer.status {
        case .completed:
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
            return formatRemaining(timer.remainingTime)
        case .completed:
            return "Done"
        }
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

    private static func largeContextText(for timer: RunningTimerItem) -> String? {
        let summary = timer.basisSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
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
        }
    }

    static func compactDurationText(_ duration: TimeInterval) -> String {
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
