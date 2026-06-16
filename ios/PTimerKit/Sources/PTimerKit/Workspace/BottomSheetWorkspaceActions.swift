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
    /// which deletes the record outright). Surfaced on paused rows.
    case cancel
    case remove
    /// Cancels the current running or paused timer and starts a fresh
    /// timer from the same setup and full duration. Surfaced on active
    /// rows so the photographer can abandon an in-progress exposure and
    /// begin a new one without recomputing it from the calculator.
    case startNew
    /// Starts a fresh timer cloned from a terminal record's duration
    /// and identity snapshot, leaving the source record intact.
    /// Surfaced on completed and canceled rows.
    case startAgain

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
        case .startNew:
            return "Start New"
        case .startAgain:
            return "Start Again"
        }
    }
}
