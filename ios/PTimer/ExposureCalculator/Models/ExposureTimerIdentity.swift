import Foundation
import PTimerKit

/// Which exposure stream a timer was started from. Stored on
/// `RunningTimerItem` and persisted via
/// `PersistentTimerMetadataSnapshot.exposureSourceRaw` (raw value
/// only). Manual timers do not carry an exposure source — see
/// `RunningTimerItem.exposureSource`'s optionality.
///
/// `digitalResult` covers the non-film calculator (no film selected,
/// timer started from the calculated shutter). `filmAdjustedShutter`
/// and `filmCorrectedExposure` cover the two film-mode timer entry
/// points; both still carry slot + film identity, but the
/// presentation layer's source-label string distinguishes which row
/// the user tapped. `targetShutter` covers timers started from a
/// photographer-supplied Target Shutter duration; the timer's
/// duration is the target itself, not a calculated result, so the
/// dock and expanded sheet can render a distinct source label.
///
/// This type lives in the ExposureCalculator domain (not the generic
/// `Timers/` runtime layer) because it describes which exposure
/// computation produced the timer, not a property of timer state
/// itself. Presentation strings (`"Adjusted Shutter"` / `"Corrected
/// Exposure"` / `"Target Shutter"`) live in the workspace presentation
/// layer (`TimerCardIdentityPresenter`) so the runtime layer stays
/// free of UI copy.
enum ExposureTimerSource: String, Codable, Equatable, Hashable {
    case digitalResult
    case filmAdjustedShutter
    case filmCorrectedExposure
    case targetShutter
}

/// Identity snapshot stamped on a timer at start time. Pure value —
/// once a timer starts, its identity must not drift if the user
/// later switches camera slots or changes the active film. Display
/// strings (camera label, film name, profile qualifier, source
/// label) live in the presentation layer (e.g.
/// `TimerCardIdentityPresenter`); this struct holds only the raw
/// fields so domain code stays free of UI copy.
///
/// Manual timers have no exposure identity (`RunningTimerItem
/// .identitySnapshot` returns nil for them); this struct only ever
/// represents an exposure-calculator-originated timer.
struct ExposureTimerIdentitySnapshot: Equatable, Hashable {
    let cameraSlot: CameraSlotIdentity?
    /// Film canonical stock name at the moment the timer started.
    /// `nil` indicates the timer was started without a film selected
    /// (digital workflow).
    let filmDisplayName: String?
    /// Optional profile qualifier (e.g., `"Unofficial"`, `"Custom"`)
    /// when the user chose a non-primary or user-authored profile.
    let filmProfileQualifier: String?
    let exposureSource: ExposureTimerSource
    /// True when the timer was started from a formula prediction that
    /// sits outside the manufacturer-supported source range. Captured
    /// at start time so a later film switch or policy change does not
    /// retroactively rewrite the basis the user committed to. Defaults
    /// to `false` for the supported quantified path and for non-film
    /// timers.
    let isOutsideManufacturerGuidance: Bool
    /// Identity summary for a timer started from a
    /// user-authored custom profile. Carries `profile name · ISO ·
    /// source type · formula` as one display-ready string so the
    /// timer card stays understandable even if the photographer later
    /// deletes the source profile. `nil` for preset / unofficial /
    /// non-film timers — the existing `filmProfileQualifier` carries
    /// the qualifier in those cases.
    let customProfileSummary: String?

    init(
        cameraSlot: CameraSlotIdentity?,
        filmDisplayName: String?,
        filmProfileQualifier: String?,
        exposureSource: ExposureTimerSource,
        isOutsideManufacturerGuidance: Bool = false,
        customProfileSummary: String? = nil
    ) {
        self.cameraSlot = cameraSlot
        self.filmDisplayName = filmDisplayName
        self.filmProfileQualifier = filmProfileQualifier
        self.exposureSource = exposureSource
        self.isOutsideManufacturerGuidance = isOutsideManufacturerGuidance
        self.customProfileSummary = customProfileSummary
    }
}
