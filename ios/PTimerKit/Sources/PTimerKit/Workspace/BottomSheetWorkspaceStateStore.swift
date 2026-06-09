import Combine
import Foundation

/// Presentation state of the Timers workspace.
///
/// Despite the legacy `BottomSheet` prefix on the surrounding types
/// (kept to avoid a wide rename across callers and tests), the
/// PTIMER-126 redesign moved the closed-state Timers UI out of any
/// custom bottom sheet:
///
/// - `.compact` is the **closed** state — the screen-level timer
///   strip plus camera workspace; no Timers chrome on screen.
/// - `.large` means the **full-screen Timers window** is presented
///   (via `.fullScreenCover` from the screen layer). This is no
///   longer a 70%-height bottom sheet.
///
/// The cases are kept under their original names because they are
/// referenced widely; their meaning is fully described above.
public enum BottomSheetDetent: String, CaseIterable, Identifiable {
    case compact
    case large

    public static let `default`: BottomSheetDetent = .compact

    public var id: String { rawValue }

    public var isExpanded: Bool {
        self != .compact
    }

    public var showsLargeWorkspace: Bool {
        self == .large
    }
}

/// What the full-screen Timers window should focus when it opens.
///
/// Both active and completed compact-card taps preserve the section
/// header context: the scroll target is always a section header,
/// never a row. For active timers we additionally remember which row
/// the photographer tapped so the row can be highlighted in place,
/// but that id is not used as a scroll anchor (which would push the
/// `Active` section title above the viewport).
public enum TimersOpenFocus: Equatable {
    case none
    case activeSection(highlightedTimerID: UUID?)
    case recentlyCompletedSection

    /// Active timer id used purely as a row-highlight cue. Returns
    /// `nil` when no specific row was tapped (e.g. the photographer
    /// hit the overflow card) or when the focus targets the
    /// completed section. Never used as a scroll anchor.
    public var activeTimerID: UUID? {
        if case .activeSection(let id) = self {
            return id
        }
        return nil
    }
}

public struct BottomSheetPresentationState: Equatable {
    public var detent: BottomSheetDetent
    public var openFocus: TimersOpenFocus
}

/// Owns the Timers workspace's presentation state — closed/full-
/// screen detent plus the opening-focus enum. Drives the
/// `.fullScreenCover` from `ExposureCalculatorScreen` and the
/// scroll-focus inside `BottomSheetLargeWorkspaceView`.
@MainActor
public final class BottomSheetWorkspaceStateStore: ObservableObject {
    @Published private(set) var presentationState: BottomSheetPresentationState

    public init(detent: BottomSheetDetent = .default) {
        self.presentationState = BottomSheetPresentationState(
            detent: detent,
            openFocus: .none
        )
    }

    public var detent: BottomSheetDetent {
        presentationState.detent
    }

    public var openFocus: TimersOpenFocus {
        presentationState.openFocus
    }

    /// Back-compat surface — historical callers (and the row view)
    /// read the active focus as a UUID. Returns the active id when
    /// the focus is on a specific active timer, otherwise nil.
    public var selectedTimerID: UUID? {
        openFocus.activeTimerID
    }

    public var isExpanded: Bool {
        detent.isExpanded
    }

    public func transition(to detent: BottomSheetDetent) {
        presentationState.detent = detent
        if detent == .compact {
            presentationState.openFocus = .none
        }
    }

    public func expand() {
        transition(to: .large)
    }

    /// Open Timers focused on the `Active` section header, with the
    /// tapped timer id remembered as a row highlight. The scroll
    /// target is the section header — *not* the timer row — so the
    /// section title stays in view (PTIMER-126).
    public func expandAndFocusActiveTimer(_ id: UUID) {
        presentationState.openFocus = .activeSection(highlightedTimerID: id)
        expand()
    }

    /// Open Timers focused on the `Active` section header without
    /// highlighting any specific row. Used by the overflow card
    /// when active timers exist but no individual card was tapped.
    public func expandFocusingActiveSection() {
        presentationState.openFocus = .activeSection(highlightedTimerID: nil)
        expand()
    }

    /// Open Timers focused on the `Recently Completed` section
    /// header so the section title and `Clear` button stay visible
    /// when the photographer drilled in from a completed compact
    /// card. Used instead of focusing the completed row directly,
    /// which would scroll the section header above the viewport.
    public func expandFocusingCompletedSection() {
        presentationState.openFocus = .recentlyCompletedSection
        expand()
    }

    /// Back-compat alias for callers / tests that predate the focus
    /// enum. Treats every id as an active-section focus with
    /// row highlight. Prefer the section-named methods in new code.
    public func expandAndFocusTimer(_ id: UUID) {
        expandAndFocusActiveTimer(id)
    }

    public func focusTimer(_ id: UUID) {
        presentationState.openFocus = .activeSection(highlightedTimerID: id)
    }

    public func collapse() {
        transition(to: .compact)
    }
}
