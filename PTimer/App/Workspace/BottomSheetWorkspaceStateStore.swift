import Combine
import SwiftUI

enum BottomSheetDetent: String, CaseIterable, Identifiable {
    case compact
    case large

    static let `default`: BottomSheetDetent = .compact

    var id: String { rawValue }

    var isExpanded: Bool {
        self != .compact
    }

    var showsLargeWorkspace: Bool {
        self == .large
    }
}

struct BottomSheetPresentationState: Equatable {
    var detent: BottomSheetDetent
    var selectedTimerID: UUID?

    static let `default` = BottomSheetPresentationState(
        detent: .default,
        selectedTimerID: nil
    )
}

@MainActor
final class BottomSheetWorkspaceStateStore: ObservableObject {
    private enum DragThreshold {
        static let compactExpand: CGFloat = 92
        static let largeCollapse: CGFloat = 64
    }

    @Published private(set) var presentationState: BottomSheetPresentationState

    init(detent: BottomSheetDetent = .default) {
        self.presentationState = BottomSheetPresentationState(
            detent: detent,
            selectedTimerID: nil
        )
    }

    var detent: BottomSheetDetent {
        presentationState.detent
    }

    var selectedTimerID: UUID? {
        presentationState.selectedTimerID
    }

    var isExpanded: Bool {
        detent.isExpanded
    }

    func transition(to detent: BottomSheetDetent) {
        presentationState.detent = detent
        if detent == .compact {
            presentationState.selectedTimerID = nil
        }
    }

    func expand() {
        transition(to: .large)
    }

    func expandAndFocusTimer(_ id: UUID) {
        presentationState.selectedTimerID = id
        expand()
    }

    func focusTimer(_ id: UUID) {
        presentationState.selectedTimerID = id
    }

    func collapse() {
        transition(to: .compact)
    }

    func handleDragEnd(translation: CGFloat) {
        switch detent {
        case .compact:
            if translation <= -DragThreshold.compactExpand {
                expand()
            }
        case .large:
            if translation >= DragThreshold.largeCollapse {
                collapse()
            }
        }
    }
}
