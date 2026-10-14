// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Pure-value transform from a `ExposureTimerIdentitySnapshot` into
/// the presentation strings the screen-level timer card strip and
/// the full-screen Timers window render. Lives in `App/Workspace/`
/// because the consumer is the timer-workspace snapshot factory;
/// keeping it here means the timer runtime layer (`Timers/`) has no
/// UI copy in it.
///
/// All methods are static and side-effect-free — this is a pure
/// formatter, not a stateful object. Add cases here when a new UI
/// surface needs another formatted shape rather than reaching into
/// the snapshot fields directly.
public enum TimerCardIdentityPresenter {
    /// Compact camera label rendered as the colored capsule badge on
    /// timer cards (`"C2"`). Returns `nil` when the timer has no camera
    /// identity — the caller falls back to a non-camera marker (e.g.
    /// `"T<order>"`). Legacy identities keep `"C1"`...`"C4"`; any other
    /// camera derives its badge from the captured name, so the badge
    /// never depends on the current camera list: the first letter plus
    /// the last two digits of a trailing number (`"Leica M6"` -> `"L6"`,
    /// `"Camera 123"` -> `"C23"`), the last two digits of a name made
    /// only of digits (`"35"` -> `"35"`), otherwise the first two letters.
    public static func compactCameraLabel(for snapshot: ExposureTimerIdentitySnapshot) -> String? {
        guard let slot = snapshot.cameraSlot else { return nil }
        if let index = CameraSlotID.legacyOrdered.firstIndex(of: slot.id) {
            return "C\(index + 1)"
        }
        let name = slot.displayName
        let trailingDigits = String(name.reversed().prefix { $0.isNumber }.reversed())
        if !trailingDigits.isEmpty {
            let shown = String(trailingDigits.suffix(2))
            if trailingDigits.count == name.count {
                return shown
            }
            return "\(name.first.map(String.init) ?? "")\(shown)".uppercased()
        }
        guard !name.isEmpty else { return nil }
        return String(name.prefix(2)).uppercased()
    }

    /// Full slot label used as the leading title segment on the
    /// expanded sheet's row title. `nil` when no slot identity is
    /// present — the caller uses the legacy timer name fallback.
    public static func fullCameraLabel(for snapshot: ExposureTimerIdentitySnapshot) -> String? {
        snapshot.cameraSlot?.displayName
    }

    /// Inline film/digital descriptor. `"CHS 100 II"` when a film is
    /// selected, `"CHS 100 II · App formula"` when a non-default model
    /// was chosen (PTIMER-171), `"Portra 400 · Unofficial"` when only
    /// the authority qualifier identifies the choice, `"No film"`
    /// otherwise. A captured model label takes precedence over the
    /// generic qualifier because it is strictly more specific (e.g.
    /// `"Ohzart"` over `"Unofficial"`). The separator (`·`) and
    /// "No film" wording stay here so changing them never requires
    /// editing the runtime snapshot type.
    public static func filmDescriptor(for snapshot: ExposureTimerIdentitySnapshot) -> String {
        guard let filmName = snapshot.filmDisplayName, !filmName.isEmpty else {
            return String(localized: "No film")
        }
        let trimmedModelLabel = snapshot.selectedModelLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQualifier = snapshot.filmProfileQualifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let modelSegment = [trimmedModelLabel, trimmedQualifier]
            .compactMap { $0 }
            .first { !$0.isEmpty }
        if let modelSegment {
            return "\(filmName) · \(modelSegment)"
        }
        return filmName
    }

    /// Human-readable source label used in the expanded sheet's
    /// subtitle (`"Adjusted Shutter · 16 stops - 1/30s"`). Centralised
    /// so the same wording appears wherever the source is rendered.
    public static func sourceLabel(for source: ExposureTimerSource) -> String {
        switch source {
        case .digitalResult: return String(localized: "Calculated")
        case .filmAdjustedShutter: return String(localized: "Adjusted Exposure")
        // PTIMER-183: the compact Timers/history row uses the shorter
        // "Reciprocity" label; the main result card and Reciprocity
        // Details keep "Corrected Exposure".
        case .filmCorrectedExposure: return String(localized: "Reciprocity")
        case .targetShutter: return String(localized: "Target Exposure")
        }
    }
}
