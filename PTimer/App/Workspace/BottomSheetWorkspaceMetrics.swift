import Combine
import SwiftUI

struct BottomSheetLayoutMetrics {
    static let compactMainContentReservation: CGFloat = 152
    static let largeFixedHeight: CGFloat = 560

    static func fixedHeight(for detent: BottomSheetDetent) -> CGFloat? {
        switch detent {
        case .compact:
            return nil
        case .large:
            return largeFixedHeight
        }
    }

    static func mainContentReservation(for detent: BottomSheetDetent) -> CGFloat {
        switch detent {
        case .compact:
            return compactMainContentReservation
        case .large:
            return largeFixedHeight
        }
    }

    static func dimOpacity(for detent: BottomSheetDetent) -> Double {
        switch detent {
        case .compact:
            return 0
        case .large:
            return 0.2
        }
    }
}

enum BottomSheetWorkspaceCopy {
    static let title = "Timers"
}

enum BottomSheetCompactDockMetrics {
    static let scrollsHorizontally = true
    static let contentInsets = EdgeInsets(top: 1, leading: 18, bottom: 1, trailing: 18)
    static let cardSpacing: CGFloat = 10
    static let timerCardWidth: CGFloat = 96
    static let timerCardHeight: CGFloat = 116
    static let overflowCardWidth: CGFloat = 86
    static let viewportHeight: CGFloat = timerCardHeight + contentInsets.top + contentInsets.bottom
    static let viewportCornerRadius: CGFloat = 22
}
