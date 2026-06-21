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
    /// Compact slot label rendered as the colored capsule badge on
    /// timer cards (`"C2"`). Returns `nil` when the timer has no slot
    /// identity — the caller falls back to a non-slot marker (e.g.
    /// `"T<order>"`). A `switch` on the enum is used (rather than a
    /// rawValue prefix-strip) so adding a future `CameraSlotID` case
    /// surfaces as a compile error instead of a silently-wrong label.
    public static func compactCameraLabel(for snapshot: ExposureTimerIdentitySnapshot) -> String? {
        guard let slotID = snapshot.cameraSlot?.id else { return nil }
        switch slotID {
        case .camera1: return "C1"
        case .camera2: return "C2"
        case .camera3: return "C3"
        case .camera4: return "C4"
        }
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
            return "No film"
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
        case .digitalResult: return "Calculated"
        case .filmAdjustedShutter: return "Adjusted Shutter"
        case .filmCorrectedExposure: return "Corrected Exposure"
        case .targetShutter: return "Target Shutter"
        }
    }
}
