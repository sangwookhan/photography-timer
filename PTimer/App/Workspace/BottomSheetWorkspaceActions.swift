import Combine
import SwiftUI

enum BottomSheetQuickAction: String, Equatable {
    case pause
    case resume

    var title: String {
        switch self {
        case .pause:
            return "Pause"
        case .resume:
            return "Resume"
        }
    }

    var systemImageName: String {
        switch self {
        case .pause:
            return "pause.fill"
        case .resume:
            return "play.fill"
        }
    }
}

enum BottomSheetLargeAction: String, Equatable {
    case pause
    case resume
    case remove
    /// Starts a new timer cloned from this completed timer's
    /// duration and identity snapshot. Surfaced only on completed
    /// rows so the photographer can repeat a long exposure without
    /// recomputing it from the calculator.
    case startAgain

    var title: String {
        switch self {
        case .pause:
            return "Pause"
        case .resume:
            return "Resume"
        case .remove:
            return "Remove"
        case .startAgain:
            return "Start Again"
        }
    }
}
