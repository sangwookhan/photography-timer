import SwiftUI

enum ExposureWorkspaceLayoutDensity {
    case regular
    case compact
    case dense
}

struct ExposureWorkspaceLayoutMetrics {
    static func availableMainContentHeight(
        screenHeight: CGFloat,
        bottomSheetDetent: BottomSheetDetent,
        topSafeArea: CGFloat = 0,
        bottomSafeArea: CGFloat = 34
    ) -> CGFloat {
        screenHeight
            - topSafeArea
            - BottomSheetLayoutMetrics.mainContentReservation(for: bottomSheetDetent)
            - bottomSafeArea
    }

    static func estimatedMainContentHeight(for density: ExposureWorkspaceLayoutDensity) -> CGFloat {
        switch density {
        case .regular:
            return 620
        case .compact:
            return 560
        case .dense:
            return 488
        }
    }
}
