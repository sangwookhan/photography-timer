import Combine
import SwiftUI

@MainActor
final class BottomSheetWorkspaceSnapshotStore: ObservableObject {
    @Published private(set) var snapshot: BottomSheetWorkspaceSnapshot

    private var cancellables: Set<AnyCancellable> = []

    init(
        initialTimers: [RunningTimerItem] = [],
        timersPublisher: AnyPublisher<[RunningTimerItem], Never>,
        adapter: BottomSheetWorkspacePresentationAdapter
    ) {
        self.snapshot = adapter.makeSnapshot(from: initialTimers)

        timersPublisher
            .map { adapter.makeSnapshot(from: $0) }
            .removeDuplicates()
            .sink { [weak self] snapshot in
                self?.snapshot = snapshot
            }
            .store(in: &cancellables)
    }
}
