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

    var title: String {
        switch self {
        case .pause:
            return "Pause"
        case .resume:
            return "Resume"
        case .remove:
            return "Remove"
        }
    }
}
