// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

public enum BottomSheetQuickAction: String, Equatable {
    case pause
    case resume

    public var title: String {
        switch self {
        case .pause:
            return "Pause"
        case .resume:
            return "Resume"
        }
    }

    public var systemImageName: String {
        switch self {
        case .pause:
            return "pause.fill"
        case .resume:
            return "play.fill"
        }
    }
}

public enum BottomSheetLargeAction: String, Equatable {
    case pause
    case resume
    /// Cancels a running or paused timer, keeping it as a terminal
    /// canceled record in the history area (distinct from `remove`,
    /// which deletes the record outright).
    case cancel
    case remove
    /// Starts a fresh timer from the selected timer's setup and full
    /// duration, leaving the source timer untouched — a timer is canceled
    /// only by an explicit Cancel, never implicitly by Clone. Surfaced on
    /// every timer state.
    case clone

    public var title: String {
        switch self {
        case .pause:
            return "Pause"
        case .resume:
            return "Resume"
        case .cancel:
            return "Cancel"
        case .remove:
            return "Remove"
        case .clone:
            return "Clone"
        }
    }
}
