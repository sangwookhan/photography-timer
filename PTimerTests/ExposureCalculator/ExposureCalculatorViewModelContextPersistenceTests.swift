import XCTest
@testable import PTimer

final class ExposureCalculatorViewModelContextPersistenceTests: XCTestCase {
    @MainActor
    func testSelectingPresetFilmPersistsWorkingContextValues() throws {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1.0 / 15.0
        viewModel.ndStop = 4
        viewModel.selectPresetFilm(film)

        XCTAssertEqual(
            contextStore.snapshot,
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: film.id,
                baseShutterSeconds: 1.0 / 15.0,
                ndStop: 4
            )
        )
    }

    @MainActor
    func testRelaunchRestoresValidFilmModeWorkingContextAndReciprocityBinding() throws {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        let initialViewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )
        // Pin the legacy full-stop scale so the snap-to-full-stop result
        // (1/15 + ND 4 → 1.0s) lands on Tri-X's exact 1s table anchor;
        // the persisted scale token is restored on relaunch so the
        // reciprocity confidence remains "Exact".
        initialViewModel.scaleMode = .fullStop
        let film = try XCTUnwrap(initialViewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        initialViewModel.baseShutter = 1.0 / 15.0
        initialViewModel.ndStop = 4
        initialViewModel.selectPresetFilm(film)

        let relaunchedViewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )
        XCTAssertEqual(relaunchedViewModel.selectedPresetFilm?.id, film.id)
        XCTAssertEqual(relaunchedViewModel.filmSelectionDisplayState.primaryText, "Tri-X 400")
        XCTAssertTrue(relaunchedViewModel.isFilmWorkflowActive)
        XCTAssertEqual(relaunchedViewModel.baseShutter, 1.0 / 15.0, accuracy: 0.000_001)
        XCTAssertEqual(relaunchedViewModel.ndStop, 4)
        let bindingState = try XCTUnwrap(relaunchedViewModel.filmReciprocityBindingState)
        XCTAssertEqual(bindingState.film.id, film.id)
        XCTAssertEqual(bindingState.profile.id, film.profiles.first?.id)
        XCTAssertTrue(bindingState.policyResult.hasCalculatedExposureTime)
        XCTAssertTrue(bindingState.presentation.returnsCalculatedExposureTime)
        XCTAssertEqual(relaunchedViewModel.filmModeExposureResultState?.reciprocityState.badgeText, "Exact")
    }

    @MainActor
    func testRelaunchWithoutStoredPresetFallsBackToNoFilmState() {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )
        XCTAssertNil(viewModel.selectedPresetFilm)
        XCTAssertFalse(viewModel.isFilmWorkflowActive)
        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "No film")
        XCTAssertNil(viewModel.filmReciprocityBindingState)
        XCTAssertNil(viewModel.filmModeExposureResultState)
        XCTAssertNil(contextStore.snapshot)
    }

    @MainActor
    func testRelaunchWithInvalidStoredPresetIdentifierFallsBackSafely() {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        contextStore.saveSnapshot(
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: "missing-preset-id",
                baseShutterSeconds: 1,
                ndStop: 4
            )
        )

        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )
        XCTAssertNil(viewModel.selectedPresetFilm)
        XCTAssertFalse(viewModel.isFilmWorkflowActive)
        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "No film")
        XCTAssertNil(viewModel.filmReciprocityBindingState)
        XCTAssertNil(viewModel.filmModeExposureResultState)
        XCTAssertNil(contextStore.snapshot)
    }

    @MainActor
    func testInvalidStoredPresetFallbackLeavesDigitalWorkflowUnaffected() throws {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        contextStore.saveSnapshot(
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: "missing-preset-id",
                baseShutterSeconds: 1,
                ndStop: 4
            )
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )
        // Pin the legacy full-stop scale so the snap-to-full-stop
        // assertion below stays a model/legacy regression test.
        viewModel.scaleMode = .fullStop
        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6

        XCTAssertNil(viewModel.selectedPresetFilm)
        XCTAssertNil(viewModel.filmModePrimaryResultSeconds)
        XCTAssertNil(viewModel.filmModeExposureResultState)
        XCTAssertEqual(
            viewModel.calculationResult,
            .success(
                ExposureCalculationResult(
                    baseShutterSeconds: 1.0 / 30.0,
                    stop: 6,
                    resultShutterSeconds: 2
                )
            )
        )
    }

    @MainActor
    func testDigitalWorkingContextPersistsWithoutSelectedFilm() {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )
        viewModel.baseShutter = 1
        viewModel.ndStop = 3

        XCTAssertEqual(
            contextStore.snapshot,
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: nil,
                baseShutterSeconds: 1,
                ndStop: 3
            )
        )
    }

    @MainActor
    func testRelaunchRestoresDigitalWorkingContextWithoutSelectedFilm() {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        contextStore.saveSnapshot(
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: nil,
                baseShutterSeconds: 1,
                ndStop: 3
            )
        )

        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )
        XCTAssertNil(viewModel.selectedPresetFilm)
        XCTAssertFalse(viewModel.isFilmWorkflowActive)
        XCTAssertEqual(viewModel.baseShutter, 1, accuracy: 0.000_001)
        XCTAssertEqual(viewModel.ndStop, 3)
        XCTAssertEqual(viewModel.filmSelectionDisplayState.primaryText, "No film")
        XCTAssertEqual(
            viewModel.calculationResult,
            .success(
                ExposureCalculationResult(
                    baseShutterSeconds: 1,
                    stop: 3,
                    resultShutterSeconds: 8
                )
            )
        )
    }

    @MainActor
    func testRelaunchWithInvalidStoredNumericValuesFallsBackToDefaultCalculatorInputs() throws {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        let film = try XCTUnwrap(makeViewModel().availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })
        contextStore.saveSnapshot(
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: film.id,
                baseShutterSeconds: 0.3,
                ndStop: 99
            )
        )

        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )
        XCTAssertEqual(viewModel.selectedPresetFilm?.id, film.id)
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(viewModel.ndStop, 0)
        XCTAssertEqual(
            contextStore.snapshot,
            PersistentExposureCalculatorContextSnapshot(
                selectedPresetFilmID: film.id,
                baseShutterSeconds: 1.0 / 30.0,
                ndStop: 0
            )
        )
    }

    @MainActor
    func testResetFilmModeWorkingContextClearsSelectionInputsAndPersistedSnapshot() throws {
        let contextStore = InMemoryExposureCalculatorContextPersistenceStore()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            ),
            contextPersistenceStore: contextStore
        )
        let film = try XCTUnwrap(viewModel.availablePresetFilms.first { $0.canonicalStockName == "Tri-X 400" })

        viewModel.baseShutter = 1.0 / 15.0
        viewModel.ndStop = 4
        viewModel.selectPresetFilm(film)

        XCTAssertTrue(viewModel.canResetFilmModeWorkingContext)

        viewModel.resetFilmModeWorkingContext()

        XCTAssertNil(viewModel.selectedPresetFilm)
        XCTAssertFalse(viewModel.isFilmWorkflowActive)
        XCTAssertFalse(viewModel.canResetFilmModeWorkingContext)
        XCTAssertEqual(viewModel.baseShutter, 1.0 / 30.0, accuracy: 0.000_001)
        XCTAssertEqual(viewModel.ndStop, 0)
        XCTAssertNil(viewModel.filmModeExposureResultState)
        XCTAssertNil(contextStore.snapshot)
    }

    @MainActor
    func testRelaunchRestoresTimerCardIdentityMetadataForMultipleTimers() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let timerStore = InMemoryTimerPersistenceStore()
        let metadataStore = InMemoryTimerMetadataPersistenceStore()

        let initialTimerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: timerStore
        )
        let initialViewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: initialTimerManager,
            metadataPersistenceStore: metadataStore
        )
        // Pin the legacy full-stop scale so the timer names ("6 stops -
        // 2s", "3 stops - 8s") match the snap-to-full-stop output.
        initialViewModel.scaleMode = .fullStop
        initialViewModel.baseShutter = 1.0 / 30.0
        initialViewModel.ndStop = 6
        initialViewModel.startTimer()

        initialViewModel.baseShutter = 1.0
        initialViewModel.ndStop = 3
        initialViewModel.startTimer()

        let runningTimer = try XCTUnwrap(initialViewModel.timers.first(where: { $0.name == "3 stops - 8s" }))
        let pausedTimer = try XCTUnwrap(initialViewModel.timers.first(where: { $0.name == "6 stops - 2s" }))

        currentDate = startDate.addingTimeInterval(1)
        initialViewModel.pauseTimer(id: pausedTimer.id)

        let relaunchedTimerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            persistenceStore: timerStore
        )
        let relaunchedViewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: relaunchedTimerManager,
            metadataPersistenceStore: metadataStore
        )
        XCTAssertEqual(relaunchedViewModel.timers.map(\.id), [runningTimer.id, pausedTimer.id])
        XCTAssertEqual(relaunchedViewModel.timers.map(\.name), ["3 stops - 8s", "6 stops - 2s"])
        XCTAssertEqual(
            relaunchedViewModel.timers.map(\.basisSummary),
            ["Base 1s · 3 stops", "Base 1/30s · 6 stops"]
        )
        XCTAssertEqual(relaunchedViewModel.timers.map(\.order), [2, 1])
        XCTAssertEqual(relaunchedViewModel.timers.map(\.status), [.running, .paused])
    }

    @MainActor
    func testRelaunchWithCorruptedMetadataSnapshotKeepsTimerRestoreIndependent() throws {
        let suiteName = "ExposureCalculatorViewModelTests.corrupted.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let timerStore = InMemoryTimerPersistenceStore()
        let timerID = UUID()
        timerStore.saveSnapshot(
            PersistentTimerCollectionSnapshot(
                timers: [
                    TimerState(
                        id: timerID,
                        duration: 10,
                        startDate: Date(timeIntervalSince1970: 100),
                        endDate: Date(timeIntervalSince1970: 110),
                        pausedRemainingTime: nil,
                        pausedAt: nil,
                        status: .running
                    )
                ]
            )
        )
        userDefaults.set(Data("corrupted-metadata".utf8), forKey: "ptimer.timer-metadata.snapshot")

        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 104) },
            persistenceStore: timerStore
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            metadataPersistenceStore: UserDefaultsTimerMetadataPersistenceStore(userDefaults: userDefaults)
        )
        XCTAssertEqual(viewModel.timers.map(\.id), [timerID])
        XCTAssertEqual(viewModel.timers.map(\.status), [.running])
        XCTAssertEqual(viewModel.timers.map(\.name), ["Timer - 10s"])
        XCTAssertEqual(viewModel.timers.map(\.basisSummary), ["Manual timer"])
    }

    @MainActor
    func testRelaunchWithoutMetadataSnapshotFallsBackToDefaultCardIdentity() {
        let timerStore = InMemoryTimerPersistenceStore()
        let timerID = UUID()
        timerStore.saveSnapshot(
            PersistentTimerCollectionSnapshot(
                timers: [
                    TimerState(
                        id: timerID,
                        duration: 10,
                        startDate: Date(timeIntervalSince1970: 100),
                        endDate: Date(timeIntervalSince1970: 110),
                        pausedRemainingTime: nil,
                        pausedAt: nil,
                        status: .running
                    )
                ]
            )
        )

        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 104) },
            persistenceStore: timerStore
        )
        let metadataStore = InMemoryTimerMetadataPersistenceStore()
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            metadataPersistenceStore: metadataStore
        )
        XCTAssertEqual(viewModel.timers.map(\.id), [timerID])
        XCTAssertEqual(viewModel.timers.map(\.name), ["Timer - 10s"])
        XCTAssertEqual(viewModel.timers.map(\.basisSummary), ["Manual timer"])
        XCTAssertEqual(viewModel.timers.map(\.order), [0])
        XCTAssertNil(metadataStore.snapshot)
    }

    @MainActor
    func testOrphanedMetadataIsDroppedWhenNoTimersRestore() {
        let timerStore = InMemoryTimerPersistenceStore()
        let metadataStore = InMemoryTimerMetadataPersistenceStore()
        let orphanID = UUID()
        metadataStore.saveSnapshot(
            PersistentTimerMetadataCollectionSnapshot(
                nextTimerOrder: 7,
                timers: [
                    PersistentTimerMetadataSnapshot(
                        id: orphanID,
                        order: 6,
                        name: "Orphan",
                        basisSummary: "Manual timer"
                    )
                ]
            )
        )

        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) },
            persistenceStore: timerStore
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            metadataPersistenceStore: metadataStore
        )
        XCTAssertTrue(viewModel.timers.isEmpty)
        XCTAssertNil(metadataStore.snapshot)
    }

    @MainActor
    func testOrphanedMetadataIsFilteredOutWhenSomeTimersRestore() {
        let timerID = UUID()
        let orphanID = UUID()
        let timerStore = InMemoryTimerPersistenceStore()
        timerStore.saveSnapshot(
            PersistentTimerCollectionSnapshot(
                timers: [
                    TimerState(
                        id: timerID,
                        duration: 8,
                        startDate: Date(timeIntervalSince1970: 100),
                        endDate: Date(timeIntervalSince1970: 108),
                        pausedRemainingTime: nil,
                        pausedAt: nil,
                        status: .running
                    )
                ]
            )
        )

        let metadataStore = InMemoryTimerMetadataPersistenceStore()
        metadataStore.saveSnapshot(
            PersistentTimerMetadataCollectionSnapshot(
                nextTimerOrder: 9,
                timers: [
                    PersistentTimerMetadataSnapshot(
                        id: timerID,
                        order: 3,
                        name: "Matched timer",
                        basisSummary: "Matched summary"
                    ),
                    PersistentTimerMetadataSnapshot(
                        id: orphanID,
                        order: 4,
                        name: "Orphan timer",
                        basisSummary: "Orphan summary"
                    )
                ]
            )
        )

        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 102) },
            persistenceStore: timerStore
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            metadataPersistenceStore: metadataStore
        )
        XCTAssertEqual(viewModel.timers.map(\.id), [timerID])
        XCTAssertEqual(viewModel.timers.map(\.name), ["Matched timer"])
        XCTAssertEqual(viewModel.timers.map(\.basisSummary), ["Matched summary"])
        XCTAssertEqual(metadataStore.snapshot?.timers.map(\.id), [timerID])
    }

    @MainActor
    func testRemovingLastTimerClearsPersistedTimerAndMetadataSnapshots() throws {
        let timerStore = InMemoryTimerPersistenceStore()
        let metadataStore = InMemoryTimerMetadataPersistenceStore()
        let timerManager = TimerManager(
            tickInterval: 60,
            dateProvider: { Date(timeIntervalSince1970: 100) },
            persistenceStore: timerStore
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager,
            metadataPersistenceStore: metadataStore
        )
        viewModel.startTimer(from: 10)
        let id = try XCTUnwrap(viewModel.timers.first?.id)
        XCTAssertNotNil(timerStore.snapshot)
        XCTAssertNotNil(metadataStore.snapshot)

        viewModel.removeTimer(id: id)

        XCTAssertTrue(viewModel.timers.isEmpty)
        XCTAssertNil(timerStore.snapshot)
        XCTAssertNil(metadataStore.snapshot)
    }

    @MainActor
    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: TimerManager(
                tickInterval: 60,
                dateProvider: { Date(timeIntervalSince1970: 100) }
            )
        )
    }
}

private final class InMemoryExposureCalculatorContextPersistenceStore: ExposureCalculatorContextPersistenceStoring {
    private(set) var snapshot: PersistentExposureCalculatorContextSnapshot?

    func loadSnapshot() -> PersistentExposureCalculatorContextSnapshot? {
        snapshot
    }

    func saveSnapshot(_ snapshot: PersistentExposureCalculatorContextSnapshot) {
        self.snapshot = snapshot
    }

    func clearSnapshot() {
        snapshot = nil
    }
}

private final class InMemoryTimerMetadataPersistenceStore: TimerMetadataPersistenceStoring {
    private(set) var snapshot: PersistentTimerMetadataCollectionSnapshot?

    func loadSnapshot() -> PersistentTimerMetadataCollectionSnapshot? {
        snapshot
    }

    func saveSnapshot(_ snapshot: PersistentTimerMetadataCollectionSnapshot) {
        self.snapshot = snapshot
    }

    func clearSnapshot() {
        snapshot = nil
    }
}

private final class InMemoryTimerPersistenceStore: TimerPersistenceStoring {
    private(set) var snapshot: PersistentTimerCollectionSnapshot?

    func loadSnapshot() -> PersistentTimerCollectionSnapshot? {
        snapshot
    }

    func saveSnapshot(_ snapshot: PersistentTimerCollectionSnapshot) {
        self.snapshot = snapshot
    }

    func clearSnapshot() {
        snapshot = nil
    }
}
