import SwiftUI
import UIKit

struct ExposureCalculatorScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    /// The screen owns `WorkspaceCoordinator` for workspace-lifetime
    /// state. The coordinator itself is wiring-only; redraws are driven
    /// by observed child models and the view-model facade.
    @StateObject private var coordinator: WorkspaceCoordinator
    @StateObject private var viewModel: ExposureCalculatorViewModel
    @StateObject private var bottomSheetStateStore: BottomSheetWorkspaceStateStore
    @StateObject private var bottomSheetSnapshotStore: BottomSheetWorkspaceSnapshotStore

    /// Film selector visibility lives at the screen level so the
    /// overlay can render above both the camera workspace and the
    /// timer card strip. Toggling does not touch the Timers
    /// presentation detent or any timer state.
    @State private var isFilmSelectorPresented = false
    @State private var presentedFilmDetails: FilmModeDetailsDisplayState?
    /// Slot id currently being renamed via the title-tap sheet.
    /// `.sheet(item:)` keys off this so dismissal clears it back to
    /// `nil` automatically. Only the active slot can request a
    /// rename — the title affordance on inactive pages is hidden.
    @State private var slotIDPendingRename: CameraSlotID?

    private let bottomSheetAdapter: BottomSheetWorkspacePresentationAdapter

    @MainActor
    init() {
        // The coordinator owns the four child models and the
        // view-model facade used by current views.
        self.init(
            coordinator: WorkspaceCoordinator(
                dependencies: ViewModelDependencyFactory.production()
            ),
            bottomSheetStateStore: BottomSheetWorkspaceStateStore()
        )
    }

    @MainActor
    init(
        coordinator: WorkspaceCoordinator,
        bottomSheetStateStore: BottomSheetWorkspaceStateStore
    ) {
        let viewModel = coordinator.viewModel
        let adapter = BottomSheetWorkspacePresentationAdapter(
            formatRemaining: viewModel.formatTimerClock,
            timeContext: viewModel.timerTimeContext,
            compactCompletedSupplementaryText: viewModel.compactCompletedSupplementaryText
        )

        _coordinator = StateObject(wrappedValue: coordinator)
        _viewModel = StateObject(wrappedValue: viewModel)
        _bottomSheetStateStore = StateObject(wrappedValue: bottomSheetStateStore)
        self.bottomSheetAdapter = adapter
        _bottomSheetSnapshotStore = StateObject(
            wrappedValue: BottomSheetWorkspaceSnapshotStore(
                initialTimers: viewModel.timers,
                timersPublisher: viewModel.$timers.eraseToAnyPublisher(),
                adapter: adapter
            )
        )

        assertNoKoreanUIStrings([
            "View All"
        ])
    }

    var body: some View {
        GeometryReader { geometry in
            let snapshot = bottomSheetSnapshotStore.snapshot
            let hasTimers = Self.hasTimerPresentation(in: snapshot)
            // PTIMER-126 stability rule: workspace budget and marker
            // y-position never vary with timer presence. The strip's
            // footprint is always reserved; only the strip view's
            // rendering is conditional. Starting the first timer
            // adds the strip without reflowing the calculator.
            let workspaceHeight = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
                screenHeight: geometry.size.height,
                topSafeArea: geometry.safeAreaInsets.top,
                bottomSafeArea: geometry.safeAreaInsets.bottom
            )
            let style = layoutStyle(for: workspaceHeight)

            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ExposureWorkspaceMainContent(
                    style: style,
                    viewModel: viewModel,
                    availableHeight: workspaceHeight,
                    onToggleFilmSelector: {
                        isFilmSelectorPresented.toggle()
                    },
                    onShowFilmDetails: { details in
                        presentedFilmDetails = details
                    },
                    onRequestRename: { slotID in
                        slotIDPendingRename = slotID
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // Page marker — single fixed y-position. Same
                // location whether or not the timer strip is
                // currently rendered.
                CameraSlotPagerIndicator(
                    count: viewModel.availableCameraSlots.count,
                    activeIndex: viewModel.activeCameraSlotIndex
                )
                .padding(
                    .bottom,
                    ExposureWorkspaceLayoutMetrics.pageMarkerBottomOffset(
                        bottomSafeArea: geometry.safeAreaInsets.bottom
                    )
                )
                .frame(maxWidth: .infinity)

                // Screen-level timer strip — only rendered when timers
                // exist. The reservation in the workspace budget is
                // unconditional, so the strip can appear without
                // pushing anything else around.
                if hasTimers {
                    CompactTimerCardStripView(
                        snapshot: snapshot,
                        onItemTap: { id in
                            Self.handleCompactCardTap(
                                id: id,
                                in: snapshot,
                                store: bottomSheetStateStore
                            )
                        },
                        onOverflowTap: {
                            Self.handleOverflowTap(
                                in: snapshot,
                                store: bottomSheetStateStore
                            )
                        }
                    )
                    .padding(
                        .bottom,
                        ExposureWorkspaceLayoutMetrics.timerStripBottomOffset(
                            bottomSafeArea: geometry.safeAreaInsets.bottom
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(!isFilmSelectorPresented)
                    .accessibilityIdentifier("main-screen-timer-strip-container")
                }

                if isFilmSelectorPresented {
                    Button {
                        isFilmSelectorPresented = false
                    } label: {
                        Color.black.opacity(0.06)
                            .ignoresSafeArea()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("film-selector-overlay-dismiss")

                    FilmSelectorOverlay(
                        sections: viewModel.filmSelectorSections,
                        selectedFilmID: viewModel.selectedSelectorEntryID,
                        onSelectEntry: { entry in
                            viewModel.selectEntry(entry)
                            isFilmSelectorPresented = false
                        },
                        style: style
                    )
                    .padding(.top, screenLevelSelectorOverlayTopPadding(
                        topSafeArea: geometry.safeAreaInsets.top,
                        style: style
                    ))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .animation(.easeInOut(duration: 0.16), value: isFilmSelectorPresented)
            .fullScreenCover(isPresented: timersWindowBinding) {
                FullScreenTimersWindow(
                    snapshot: bottomSheetSnapshotStore.snapshot,
                    openFocus: bottomSheetStateStore.openFocus,
                    onPauseTimer: viewModel.pauseTimer,
                    onResumeTimer: viewModel.resumeTimer,
                    onRemoveTimer: viewModel.removeTimer,
                    onStartTimerAgain: { id in
                        // Look the source timer up on the facade rather
                        // than threading the row's full RunningTimerItem
                        // through the snapshot — the snapshot carries
                        // presentation values, not the metadata-bearing
                        // runtime item that the clone path needs.
                        guard let source = viewModel.timers.first(where: { $0.id == id }) else {
                            return
                        }
                        viewModel.startNewTimer(fromCompleted: source)
                    },
                    onClearCompletedTimers: viewModel.clearCompletedTimers,
                    onClose: bottomSheetStateStore.collapse
                )
            }
            .sheet(item: $presentedFilmDetails) { details in
                FilmModeDetailsSheet(details: details)
            }
            .sheet(item: $slotIDPendingRename) { slotID in
                CameraSlotRenameSheet(
                    slotID: slotID,
                    defaultDisplayName: viewModel
                        .cameraSlotIdentity(for: slotID)
                        .defaultDisplayName,
                    initialCustomName: viewModel
                        .cameraSlotIdentity(for: slotID)
                        .customDisplayName,
                    onSave: { newName in
                        viewModel.setCameraSlotCustomName(newName, for: slotID)
                    },
                    onReset: {
                        viewModel.resetCameraSlotCustomName(slotID)
                    }
                )
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }

            // Foreground reactivation reconciles process-alive timers.
            // Relaunch restore is initialization-driven in TimerManager
            // and is not re-triggered from lifecycle observers.
            viewModel.reconcileTimersAfterAppBecomesActive()
        }
    }

    /// Binds `BottomSheetWorkspaceStateStore`'s detent to a Boolean
    /// the `.fullScreenCover` modifier consumes. The store predates
    /// PTIMER-126 and uses `.compact`/`.large` terminology;
    /// `.large` now means "the full-screen Timers window is
    /// presented".
    private var timersWindowBinding: Binding<Bool> {
        Binding(
            get: { bottomSheetStateStore.isExpanded },
            set: { newValue in
                if newValue {
                    bottomSheetStateStore.expand()
                } else {
                    bottomSheetStateStore.collapse()
                }
            }
        )
    }

    /// True when the snapshot should surface a closed-state timer
    /// strip. False when no timers exist — in which case the strip,
    /// the open affordance, and any Timers chrome are all hidden.
    static func hasTimerPresentation(in snapshot: BottomSheetWorkspaceSnapshot) -> Bool {
        !snapshot.compactItems.isEmpty
    }

    /// Routes a compact-card tap to the appropriate full-screen
    /// focus. Active/paused cards focus the row by id so the row
    /// scrolls into view; completed cards focus the
    /// `Recently Completed` section header so the section title
    /// and `Clear` button stay visible (PTIMER-126).
    static func handleCompactCardTap(
        id: UUID,
        in snapshot: BottomSheetWorkspaceSnapshot,
        store: BottomSheetWorkspaceStateStore
    ) {
        let item = snapshot.compactItems.first(where: { $0.id == id })

        switch item?.status {
        case .completed:
            store.expandFocusingCompletedSection()
        case .running, .paused:
            store.expandAndFocusActiveTimer(id)
        case nil:
            store.expand()
        }
    }

    /// Overflow tap routes to a sensible section header depending
    /// on what's in the snapshot:
    ///
    /// - any active or paused timer present → Active section header
    /// - only completed timers present → Recently Completed section header
    /// - empty snapshot → no focus
    ///
    /// Active here is the same as "not completed" so paused timers
    /// also count.
    static func handleOverflowTap(
        in snapshot: BottomSheetWorkspaceSnapshot,
        store: BottomSheetWorkspaceStateStore
    ) {
        let hasActive = snapshot.compactItems.contains { $0.status != .completed }
        let hasAnyCompleted = snapshot.compactItems.contains { $0.status == .completed }

        if hasActive {
            store.expandFocusingActiveSection()
        } else if hasAnyCompleted {
            store.expandFocusingCompletedSection()
        } else {
            store.expand()
        }
    }

    /// Top padding for the screen-level film selector overlay so it
    /// drops underneath the camera title area instead of starting at
    /// the very top of the screen. Mirrors the visual offset the
    /// overlay had when it lived inside the camera workspace.
    private func screenLevelSelectorOverlayTopPadding(
        topSafeArea: CGFloat,
        style: ExposureWorkspaceMainLayoutStyle
    ) -> CGFloat {
        topSafeArea + style.topPadding + style.selectorOverlayTopPadding
    }

    private func layoutStyle(for availableHeight: CGFloat) -> ExposureWorkspaceMainLayoutStyle {
        if availableHeight >= ExposureWorkspaceLayoutMetrics.estimatedMainContentHeight(for: .regular) {
            return .regular
        }

        if availableHeight >= ExposureWorkspaceLayoutMetrics.estimatedMainContentHeight(for: .compact) {
            return .compact
        }

        return .dense
    }
}

private struct ExposureWorkspaceMainContent: View {
    let style: ExposureWorkspaceMainLayoutStyle
    @ObservedObject var viewModel: ExposureCalculatorViewModel
    let availableHeight: CGFloat
    let onToggleFilmSelector: () -> Void
    let onShowFilmDetails: (FilmModeDetailsDisplayState) -> Void
    let onRequestRename: (CameraSlotID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TabView(selection: slotSelectionBinding) {
                ForEach(viewModel.availableCameraSlots, id: \.self) { slotID in
                    CameraSlotCalculatorPage(
                        pageState: viewModel.cameraSlotPageState(for: slotID),
                        viewModel: viewModel,
                        style: style,
                        onToggleFilmSelector: onToggleFilmSelector,
                        onShowFilmDetails: onShowFilmDetails,
                        onRequestRename: {
                            onRequestRename(slotID)
                        }
                    )
                    .tag(slotID)
                }
            }
            // Page style with an always-hidden index strip — the
            // screen-level `CameraSlotPagerIndicator` is the only
            // pager surface. Hosting it here would re-introduce the
            // content-driven marker movement we are deliberately
            // moving away from.
            .tabViewStyle(.page(indexDisplayMode: .never))
            .indexViewStyle(.page(backgroundDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // VoiceOver users get explicit slot-step actions on the
        // workspace container in addition to TabView's
        // gesture-driven paging — the dot indicator stays
        // non-interactive so the slot transition source is
        // single-rooted on the workspace itself.
        .accessibilityAction(named: Text("Next camera slot")) {
            viewModel.selectNextCameraSlot()
        }
        .accessibilityAction(named: Text("Previous camera slot")) {
            viewModel.selectPreviousCameraSlot()
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.top, style.topPadding)
        .padding(.bottom, style.bottomPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: availableHeight,
            maxHeight: availableHeight,
            alignment: .top
        )
        .accessibilityIdentifier("exposure-main-content")
    }

    /// Binding that bridges `TabView`'s selection to the ViewModel's
    /// single state-transition entry point. `selectCameraSlot(_:)`
    /// remains the source of truth — TabView's gesture paging fires
    /// the setter once after the snap completes.
    private var slotSelectionBinding: Binding<CameraSlotID> {
        Binding(
            get: { viewModel.activeCameraSlotID },
            set: { newSelection in
                viewModel.selectCameraSlot(newSelection)
            }
        )
    }
}

/// Single calculator workspace page consumed by the slot `TabView`.
/// Active and inactive pages render the same visual layout — the
/// only difference is binding source: the active page binds its
/// pickers to live `CalculatorModel` state so wheel drags propagate
/// immediately, while inactive pages bind to constants drawn from
/// `pageState`. `.allowsHitTesting(false)` on inactive pages keeps
/// the photographer's swipe-paging gesture clean even on a brief
/// peek where the wheel is partially exposed.
private struct CameraSlotCalculatorPage: View {
    let pageState: CameraSlotPageState
    @ObservedObject var viewModel: ExposureCalculatorViewModel
    let style: ExposureWorkspaceMainLayoutStyle
    let onToggleFilmSelector: () -> Void
    let onShowFilmDetails: (FilmModeDetailsDisplayState) -> Void
    /// Tap handler for the slot title rename affordance. Wired
    /// through only on the active page; inactive pages pass `nil`
    /// so the title renders as plain text.
    let onRequestRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(
                cameraSlotTitle: pageState.cameraDisplayName,
                activeCameraSlotID: pageState.slotID,
                selectorEntries: viewModel.filmSelectorEntries,
                selectedFilmID: pageState.selectedSelectorEntryID,
                filmSelectionDisplayState: pageState.filmSelectionDisplayState,
                onToggleSelector: pageState.isActive ? onToggleFilmSelector : {},
                showsResetAction: pageState.isActive && viewModel.canResetFilmModeWorkingContext,
                onResetFilmModeContext: pageState.isActive ? viewModel.resetFilmModeWorkingContext : {},
                onRequestRename: pageState.isActive ? onRequestRename : nil,
                style: style
            )

            VariableSectionView(
                baseShutter: baseShutterBinding,
                ndStep: ndStepBinding,
                shutterSpeeds: viewModel.pickerShutterStepSeconds(forPage: pageState),
                ndStepValues: viewModel.pickerNDSteps(forPage: pageState),
                formatShutter: viewModel.formatShutterStepLabel,
                formatNDStop: viewModel.formatNDStop,
                onContinuousBaseShutterChange: { value in
                    guard pageState.isActive else { return }
                    Task { @MainActor in
                        viewModel.updateLiveBaseShutter(value)
                    }
                },
                onContinuousNDStepChange: { value in
                    guard pageState.isActive else { return }
                    Task { @MainActor in
                        viewModel.updateLiveNDStep(value)
                    }
                },
                onBaseShutterInteractionEnd: {
                    guard pageState.isActive else { return }
                    Task { @MainActor in
                        viewModel.clearLiveBaseShutterPreview()
                    }
                },
                onNDStopInteractionEnd: {
                    guard pageState.isActive else { return }
                    Task { @MainActor in
                        viewModel.clearLiveNDStopPreview()
                    }
                },
                style: style
            )

            ResultSectionView(
                isFilmWorkflowActive: pageState.isFilmWorkflowActive,
                calculationResult: viewModel.calculationResult(forPage: pageState),
                filmModeExposureResultState: viewModel.filmModeExposureResultState(forPage: pageState),
                canShowFilmDetails: pageState.isActive && viewModel.canShowFilmDetails,
                formatTimeDisplay: viewModel.formatTimeDisplay,
                formatReciprocityTimeDisplay: viewModel.formatReciprocityTimeDisplay,
                canStartTimer: pageState.isActive && viewModel.canStartTimer,
                onStartTimer: pageState.isActive ? viewModel.startTimer : {},
                onStartFilmAdjustedShutterTimer: pageState.isActive
                    ? viewModel.startFilmAdjustedShutterTimer
                    : {},
                onStartFilmCorrectedExposureTimer: pageState.isActive
                    ? viewModel.startFilmCorrectedExposureTimer
                    : {},
                onShowFilmDetails: {
                    guard pageState.isActive,
                          let details = viewModel.filmModeDetailsDisplayState else {
                        return
                    }
                    onShowFilmDetails(details)
                },
                style: style
            )

            Spacer(minLength: style.resultFlowSpacerMinLength)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(pageState.isActive)
        .accessibilityIdentifier("camera-slot-page-\(pageState.slotID.rawValue)")
    }

    /// Routes the wheel picker's `Binding<Double>` to live state when
    /// the page is active and to a constant otherwise.
    private var baseShutterBinding: Binding<Double> {
        if pageState.isActive {
            return Binding(
                get: { viewModel.baseShutter },
                set: { viewModel.baseShutter = $0 }
            )
        }
        return .constant(pageState.baseShutter)
    }

    private var ndStepBinding: Binding<NDStep> {
        if pageState.isActive {
            return Binding(
                get: { viewModel.ndStep },
                set: { viewModel.ndStep = $0 }
            )
        }
        return .constant(pageState.ndStep)
    }
}

private enum ExposureWorkspaceMainLayoutStyle {
    case regular
    case compact
    case dense

    var density: ExposureWorkspaceLayoutDensity {
        switch self {
        case .regular:
            return .regular
        case .compact:
            return .compact
        case .dense:
            return .dense
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .regular:
            return 18
        case .compact, .dense:
            return 16
        }
    }

    var topPadding: CGFloat {
        switch self {
        case .regular:
            return 14
        case .compact:
            return 10
        case .dense:
            return 6
        }
    }

    var bottomPadding: CGFloat {
        switch self {
        case .regular:
            return 6
        case .compact:
            return 4
        case .dense:
            return 2
        }
    }

    var sectionSpacing: CGFloat {
        switch self {
        case .regular:
            return 12
        case .compact:
            return 10
        case .dense:
            return 8
        }
    }

    var resultFlowSpacerMinLength: CGFloat {
        switch self {
        case .regular:
            return 14
        case .compact:
            return 10
        case .dense:
            return 8
        }
    }

    var sectionCardPadding: CGFloat {
        switch self {
        case .regular:
            return 13
        case .compact:
            return 11
        case .dense:
            return 9
        }
    }

    var sectionCornerRadius: CGFloat {
        switch self {
        case .regular:
            return 18
        case .compact, .dense:
            return 16
        }
    }

    var headerTitleFont: Font {
        switch self {
        case .regular:
            return .largeTitle.weight(.bold)
        case .compact:
            return .title.weight(.bold)
        case .dense:
            return .title2.weight(.bold)
        }
    }

    var bodySpacing: CGFloat {
        switch self {
        case .regular:
            return 10
        case .compact, .dense:
            return 8
        }
    }

    var headerContentSpacing: CGFloat {
        switch self {
        case .regular:
            return 10
        case .compact:
            return 8
        case .dense:
            return 6
        }
    }

    var pickerHeight: CGFloat {
        switch self {
        case .regular:
            return 164
        case .compact:
            return 124
        case .dense:
            return 92
        }
    }

    var pickerValueFont: Font {
        switch self {
        case .regular:
            return .system(size: 32, weight: .bold, design: .rounded)
        case .compact:
            return .system(size: 26, weight: .bold, design: .rounded)
        case .dense:
            return .system(size: 19, weight: .semibold, design: .rounded)
        }
    }

    var pickerUnitFont: Font {
        switch self {
        case .regular:
            return .footnote.weight(.medium)
        case .compact:
            return .caption.weight(.medium)
        case .dense:
            return .caption2.weight(.medium)
        }
    }

    var pickerOverlayUnitFont: Font {
        switch self {
        case .regular:
            return .system(size: 22, weight: .medium, design: .rounded)
        case .compact:
            return .system(size: 18, weight: .medium, design: .rounded)
        case .dense:
            return .system(size: 16, weight: .medium, design: .rounded)
        }
    }

    var pickerSelectionBandHeight: CGFloat {
        switch self {
        case .regular:
            return 42
        case .compact:
            return 36
        case .dense:
            return 30
        }
    }

    var resultPrimaryFont: Font {
        switch self {
        case .regular:
            return .system(size: 28, weight: .bold, design: .rounded)
        case .compact:
            return .system(size: 24, weight: .bold, design: .rounded)
        case .dense:
            return .system(size: 22, weight: .bold, design: .rounded)
        }
    }

    var resultBlockPadding: CGFloat {
        switch self {
        case .regular:
            return 12
        case .compact:
            return 11
        case .dense:
            return 8
        }
    }

    var resultActionSpacing: CGFloat {
        switch self {
        case .regular:
            return 12
        case .compact:
            return 10
        case .dense:
            return 8
        }
    }

    var filmResultRowMinHeight: CGFloat {
        switch self {
        case .regular:
            return 52
        case .compact:
            return 48
        case .dense:
            return 44
        }
    }

    var filmResultCardMinHeight: CGFloat {
        switch self {
        case .regular:
            return 152
        case .compact:
            return 140
        case .dense:
            return 126
        }
    }

    var correctedExposurePrimaryFont: Font {
        resultPrimaryFont
    }

    var correctedExposureSecondaryFont: Font {
        .footnote
    }

    var correctedExposureValueMinHeight: CGFloat {
        switch self {
        case .regular:
            return 56
        case .compact:
            return 50
        case .dense:
            return 44
        }
    }

    var timerActionSize: CGFloat {
        switch self {
        case .regular:
            return 44
        case .compact:
            return 42
        case .dense:
            return 40
        }
    }

    var timerActionIconSize: CGFloat {
        switch self {
        case .regular:
            return 15
        case .compact:
            return 14
        case .dense:
            return 13
        }
    }

    var resultActionFootprint: CGFloat {
        timerActionSize
    }

    var resultTopSpacerMinLength: CGFloat {
        switch self {
        case .regular:
            return 10
        case .compact:
            return 8
        case .dense:
            return 6
        }
    }

    var inputColumnSpacing: CGFloat {
        switch self {
        case .regular:
            return 10
        case .compact, .dense:
            return 8
        }
    }

    var pickerLabelSpacing: CGFloat {
        switch self {
        case .regular:
            return 6
        case .compact, .dense:
            return 5
        }
    }

    var workspaceSeparation: CGFloat {
        switch self {
        case .regular:
            return 10
        case .compact:
            return 8
        case .dense:
            return 6
        }
    }

    /// Distance from the top of the camera workspace area down to the
    /// film selector overlay's top edge. Mirrors the offset the
    /// overlay had when it was scoped inside the workspace; used by
    /// the screen-level renderer to drop the overlay underneath the
    /// camera title area.
    var selectorOverlayTopPadding: CGFloat {
        switch self {
        case .regular:
            return 112
        case .compact:
            return 98
        case .dense:
            return 86
        }
    }

    var pickerSelectionBandContentTrailingInset: CGFloat {
        switch self {
        case .regular:
            return 14
        case .compact:
            return 12
        case .dense:
            return 10
        }
    }

    var pickerSelectionBandHorizontalInset: CGFloat {
        10
    }

    func pickerColumnLayout(for column: CalculatorPickerColumn) -> PickerColumnLayout {
        switch (self, column) {
        case (.regular, .ndStop):
            return PickerColumnLayout(
                unitTextWidth: 88,
                unitTextTrailingInset: 6,
                valueAlignmentPolicy: .offsetBeforeWideUnitLabel,
                valueAlignmentCompensation: -8
            )
        case (.compact, .ndStop):
            return PickerColumnLayout(
                unitTextWidth: 72,
                unitTextTrailingInset: 5,
                valueAlignmentPolicy: .offsetBeforeWideUnitLabel,
                valueAlignmentCompensation: -8
            )
        case (.dense, .ndStop):
            return PickerColumnLayout(
                unitTextWidth: 60,
                unitTextTrailingInset: 4,
                valueAlignmentPolicy: .offsetBeforeWideUnitLabel,
                valueAlignmentCompensation: -8
            )
        case (.regular, .shutter):
            return PickerColumnLayout(
                unitTextWidth: 30,
                unitTextTrailingInset: 3,
                valueAlignmentPolicy: .offsetBeforeCompactUnitGlyph,
                valueAlignmentCompensation: 1
            )
        case (.compact, .shutter):
            return PickerColumnLayout(
                unitTextWidth: 26,
                unitTextTrailingInset: 2,
                valueAlignmentPolicy: .offsetBeforeCompactUnitGlyph,
                valueAlignmentCompensation: 0
            )
        case (.dense, .shutter):
            return PickerColumnLayout(
                unitTextWidth: 22,
                unitTextTrailingInset: 2,
                valueAlignmentPolicy: .offsetBeforeCompactUnitGlyph,
                valueAlignmentCompensation: 0
            )
        }
    }
}

private enum CalculatorPickerColumn {
    case ndStop
    case shutter
}

private enum PickerValueAlignmentPolicy {
    case offsetBeforeWideUnitLabel
    case offsetBeforeCompactUnitGlyph
}

private struct PickerColumnLayout {
    let unitTextWidth: CGFloat
    let unitTextTrailingInset: CGFloat
    let valueAlignmentPolicy: PickerValueAlignmentPolicy
    let valueAlignmentCompensation: CGFloat

    func valueTextTrailingInset(selectionBandContentTrailingInset: CGFloat) -> CGFloat {
        let baseInset = unitTextWidth + selectionBandContentTrailingInset

        switch valueAlignmentPolicy {
        case .offsetBeforeWideUnitLabel:
            return baseInset + valueAlignmentCompensation
        case .offsetBeforeCompactUnitGlyph:
            return baseInset + unitTextTrailingInset + valueAlignmentCompensation
        }
    }
}

private struct HeaderView: View {
    /// Active camera slot's display name. Used as the screen's main
    /// title so the workspace itself reads as "the page for this
    /// camera." Sourced from the slot identity's computed
    /// `displayName` so the rename surface can change the displayed
    /// text without touching this view.
    let cameraSlotTitle: String
    /// Identity of the slot driving the title. Wired to
    /// `.contentTransition` so a slot switch crossfades the title
    /// rather than swapping it instantly.
    let activeCameraSlotID: CameraSlotID
    let selectorEntries: [FilmSelectorEntry]
    let selectedFilmID: String?
    let filmSelectionDisplayState: FilmSelectionDisplayState
    let onToggleSelector: () -> Void
    let showsResetAction: Bool
    let onResetFilmModeContext: () -> Void
    /// Tap handler that opens the rename sheet. Non-nil only on the
    /// active page — inactive pages render the title as plain text
    /// so the photographer cannot rename a slot they are not on.
    let onRequestRename: (() -> Void)?
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.headerContentSpacing) {
            slotTitleView
                .font(style.headerTitleFont)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.18), value: activeCameraSlotID)
                .accessibilityIdentifier("camera-slot-title")

            FilmSelectionRow(
                selectorEntries: selectorEntries,
                selectedFilmID: selectedFilmID,
                displayState: filmSelectionDisplayState,
                onToggleSelector: onToggleSelector,
                style: style
            )

            HStack {
                Spacer()

                Button("Reset") {
                    onResetFilmModeContext()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .opacity(showsResetAction ? 1 : 0)
                .allowsHitTesting(showsResetAction)
                .accessibilityHidden(!showsResetAction)
                .accessibilityHint("Clears the restored Film mode setup")
                .accessibilityIdentifier("film-mode-reset-button")
            }
            .frame(maxWidth: .infinity, minHeight: 18, alignment: .trailing)
        }
        .sectionCardStyle(style: style)
    }

    @ViewBuilder
    private var slotTitleView: some View {
        // Inactive pages render the title as plain text — the page
        // itself is `.allowsHitTesting(false)` so even a wrapped
        // Button would not fire, but keeping the view shape distinct
        // matches "rename only on the active page" without relying
        // on a global hit-test guard.
        if let onRequestRename {
            Button(action: onRequestRename) {
                HStack(spacing: 6) {
                    Text(cameraSlotTitle)
                        .foregroundStyle(.primary)
                    Image(systemName: "pencil")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Rename camera slot"))
            .accessibilityValue(Text(cameraSlotTitle))
            .accessibilityHint("Opens a sheet to rename or reset the camera slot label")
            .accessibilityIdentifier("camera-slot-rename-button")
        } else {
            Text(cameraSlotTitle)
        }
    }
}

private struct FilmSelectionRow: View {
    let selectorEntries: [FilmSelectorEntry]
    let selectedFilmID: String?
    let displayState: FilmSelectionDisplayState
    let onToggleSelector: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.pickerLabelSpacing) {
            Text("Film")
                .font(.subheadline.weight(.semibold))

            Button(action: onToggleSelector) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayState.primaryText)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityIdentifier("film-row-selection")

                        if let secondaryText = displayState.secondaryText {
                            Text(secondaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .accessibilityIdentifier("film-row-profile-qualifier")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(style.sectionCardPadding)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Film row")
            .accessibilityValue(selectedFilmAccessibilityValue)
            .accessibilityHint("Opens preset film selection")
            .accessibilityIdentifier("film-row-button")
        }
    }

    private var selectedFilmAccessibilityValue: String {
        selectorEntries.first(where: { $0.id == selectedFilmID })?.primaryText
            ?? displayState.primaryText
    }
}

private struct FilmSelectorOverlay: View {
    let sections: [FilmSelectorSection]
    let selectedFilmID: String?
    let onSelectEntry: (FilmSelectorEntry) -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                // Eager VStack (not LazyVStack) so every section card and
                // every row is registered with the ScrollViewProxy before
                // the .onAppear scroll target is requested. With 34 films
                // across 6 manufacturer groups the eagerness cost is
                // negligible, but the reliability gain is the difference
                // between scrollTo finding a row and silently no-oping
                // when the target row sits below the initial viewport.
                VStack(spacing: groupSpacing) {
                    ForEach(sections) { section in
                        FilmSelectorSectionCard(
                            section: section,
                            selectedFilmID: selectedFilmID,
                            onSelectEntry: onSelectEntry,
                            rowHeight: rowHeight
                        )
                    }
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: overlayWidth, maxHeight: maxOverlayHeight)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityIdentifier("film-selector-overlay")
            .onAppear {
                scrollToSelection(proxy: proxy)
            }
        }
    }

    /// Scrolls the overlay to the currently selected row.
    ///
    /// Two main-queue hops are required for reliability:
    ///  - `.onAppear` fires before SwiftUI completes the overlay's first
    ///    layout pass.
    ///  - The first `DispatchQueue.main.async` lands after view-tree
    ///    insertion but before the ScrollViewProxy has finished
    ///    registering every `.id(...)` from the freshly-materialized
    ///    section cards.
    ///  - The second `DispatchQueue.main.async` lands after the proxy
    ///    registry has settled, so `scrollTo(id:anchor:)` can find any
    ///    row regardless of whether it sits inside the initial viewport.
    ///
    /// The entry id distinguishes official from unofficial variants
    /// because the unofficial selector entry uses the unofficial profile
    /// id, not the film id (see `ExposureCalculatorViewModel
    /// .selectedSelectorEntryID`).
    private func scrollToSelection(proxy: ScrollViewProxy) {
        guard let selectedFilmID, !selectedFilmID.isEmpty else { return }
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                proxy.scrollTo(selectedFilmID, anchor: .center)
            }
        }
    }

    private var overlayWidth: CGFloat {
        switch style {
        case .regular:
            return 440
        case .compact:
            return 404
        case .dense:
            return 372
        }
    }

    private var rowHeight: CGFloat {
        switch style {
        case .regular:
            return 52
        case .compact:
            return 48
        case .dense:
            return 44
        }
    }

    private var maxOverlayHeight: CGFloat {
        switch style {
        case .regular:
            return 520
        case .compact:
            return 460
        case .dense:
            return 420
        }
    }

    private var groupSpacing: CGFloat { 12 }
}

/// One manufacturer group rendered as a subtle grouped card. The
/// "No film" sentinel section has `manufacturer == nil` and renders
/// as a plain card-less row at the top so it stays distinct from the
/// preset groups. The view layout is intentionally header-on-top /
/// rows-below (rather than interleaved headers + rows) so a future
/// fold/unfold gesture can be added by toggling the rows region
/// without touching the header.
private struct FilmSelectorSectionCard: View {
    let section: FilmSelectorSection
    let selectedFilmID: String?
    let onSelectEntry: (FilmSelectorEntry) -> Void
    let rowHeight: CGFloat

    private let cardCornerRadius: CGFloat = 14
    private let cardInnerPadding: CGFloat = 12
    private let rowSpacing: CGFloat = 4

    var body: some View {
        if let manufacturer = section.manufacturer {
            VStack(alignment: .leading, spacing: rowSpacing) {
                // Header pill — a small rounded label that sits inside
                // the card with a slightly stronger tint than the card
                // surface itself, plus near-primary text contrast. The
                // pill keeps the manufacturer name immediately readable
                // while staying visually subordinate to film rows by
                // size and uppercase styling.
                Text(manufacturer)
                    .font(.subheadline.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(Color.primary.opacity(0.92))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Color.primary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .padding(.bottom, 2)
                    .accessibilityIdentifier("film-selector-section-\(manufacturer)")

                ForEach(section.entries) { entry in
                    rowButton(for: entry)
                }
            }
            .padding(cardInnerPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.primary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
            )
        } else {
            // "No film" sentinel: rendered card-less so it visually
            // separates from the manufacturer groups.
            VStack(spacing: rowSpacing) {
                ForEach(section.entries) { entry in
                    rowButton(for: entry)
                }
            }
            .padding(.horizontal, cardInnerPadding)
        }
    }

    @ViewBuilder
    private func rowButton(for entry: FilmSelectorEntry) -> some View {
        Button {
            onSelectEntry(entry)
        } label: {
            HStack(spacing: 12) {
                Text(entry.primaryText)
                    .font(.body.weight(isSelected(entry) ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(0)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let secondaryText = entry.secondaryText {
                    Text(secondaryText)
                        .font(.caption)
                        .foregroundStyle(Color.primary.opacity(0.68))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
            .background(rowBackground(for: entry))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .id(entry.id)
        .accessibilityIdentifier("film-selector-entry-\(entry.id)")
    }

    private func isSelected(_ entry: FilmSelectorEntry) -> Bool {
        entry.id == selectedFilmID
    }

    @ViewBuilder
    private func rowBackground(for entry: FilmSelectorEntry) -> some View {
        if isSelected(entry) {
            Color.primary.opacity(0.08)
        } else {
            Color.clear
        }
    }
}

private struct VariableSectionView: View {
    @Binding var baseShutter: Double
    @Binding var ndStep: NDStep
    let shutterSpeeds: [Double]
    let ndStepValues: [NDStep]
    let formatShutter: (TimeInterval) -> String
    let formatNDStop: (NDStep) -> String
    let onContinuousBaseShutterChange: (Double) -> Void
    let onContinuousNDStepChange: (NDStep) -> Void
    let onBaseShutterInteractionEnd: () -> Void
    let onNDStopInteractionEnd: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.bodySpacing) {
            HStack(alignment: .top, spacing: style.inputColumnSpacing) {
                ShutterSelectionRow(
                    baseShutter: $baseShutter,
                    shutterSpeeds: shutterSpeeds,
                    formatShutter: formatShutter,
                    onContinuousSelectionChange: onContinuousBaseShutterChange,
                    onInteractionEnd: onBaseShutterInteractionEnd,
                    pickerHeight: style.pickerHeight,
                    style: style
                )

                NDStopSelectionRow(
                    ndStep: $ndStep,
                    ndStepValues: ndStepValues,
                    formatNDStop: formatNDStop,
                    onContinuousSelectionChange: onContinuousNDStepChange,
                    onInteractionEnd: onNDStopInteractionEnd,
                    pickerHeight: style.pickerHeight,
                    style: style
                )
            }
        }
        .sectionCardStyle(style: style)
    }
}

private struct ResultSectionView: View {
    let isFilmWorkflowActive: Bool
    let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError>
    let filmModeExposureResultState: FilmModeExposureResultState?
    let canShowFilmDetails: Bool
    let formatTimeDisplay: (TimeInterval) -> TimeDisplay
    let formatReciprocityTimeDisplay: (TimeInterval) -> TimeDisplay
    let canStartTimer: Bool
    let onStartTimer: () -> Void
    let onStartFilmAdjustedShutterTimer: () -> Void
    let onStartFilmCorrectedExposureTimer: () -> Void
    let onShowFilmDetails: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.bodySpacing) {
            VStack(alignment: .leading, spacing: style.resultTopSpacerMinLength) {
                if isFilmWorkflowActive,
                   let filmModeExposureResultState {
                    FilmModeResultHierarchyView(
                        resultState: filmModeExposureResultState,
                        canShowDetails: canShowFilmDetails,
                        formatReciprocityTimeDisplay: formatReciprocityTimeDisplay,
                        onStartAdjustedShutterTimer: onStartFilmAdjustedShutterTimer,
                        onStartCorrectedExposureTimer: onStartFilmCorrectedExposureTimer,
                        onShowDetails: onShowFilmDetails,
                        style: style
                    )
                } else if case .success(let result) = calculationResult {
                    DigitalModeResultView(
                        resultShutterSeconds: result.resultShutterSeconds,
                        formatTimeDisplay: formatTimeDisplay,
                        canStartTimer: canStartTimer,
                        onStartTimer: onStartTimer,
                        style: style
                    )
                } else {
                    Text(primaryResultText)
                        .font(.title3.weight(.semibold))
                }

                if let validationMessage {
                    Divider()

                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(style.resultBlockPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: isFilmWorkflowActive ? style.filmResultCardMinHeight : nil,
                alignment: .topLeading
            )
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .sectionCardStyle(style: style)
    }

    private var primaryResultText: String {
        switch calculationResult {
        case .success(let result):
            return formatTimeDisplay(result.resultShutterSeconds).primary
        case .failure:
            return "Result unavailable"
        }
    }

    private var validationMessage: String? {
        switch calculationResult {
        case .success:
            return nil
        case .failure(let error):
            return error.errorDescription
        }
    }

}

private struct DigitalModeResultView: View {
    let resultShutterSeconds: TimeInterval
    let formatTimeDisplay: (TimeInterval) -> TimeDisplay
    let canStartTimer: Bool
    let onStartTimer: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        let display = formatTimeDisplay(resultShutterSeconds)

        HStack(alignment: .center, spacing: style.resultActionSpacing) {
            Color.clear
                .frame(width: style.resultActionFootprint, height: 1)
                .accessibilityHidden(true)

            DurationDisplayBlock(
                primaryText: display.primary,
                secondaryText: display.secondary,
                primaryColor: .primary,
                primaryFont: style.resultPrimaryFont,
                secondaryFont: .footnote
            )
            .frame(maxWidth: .infinity)

            TimerActionView(
                canStartTimer: canStartTimer,
                onStart: onStartTimer,
                style: style,
                accessibilityIdentifier: "digital-result-start-timer-button",
                accessibilityLabel: "Start timer from calculated result",
                accessibilityHint: "Starts a timer using the calculated result"
            )
        }
    }
}

private struct FilmModeResultHierarchyView: View {
    let resultState: FilmModeExposureResultState
    let canShowDetails: Bool
    let formatReciprocityTimeDisplay: (TimeInterval) -> TimeDisplay
    let onStartAdjustedShutterTimer: () -> Void
    let onStartCorrectedExposureTimer: () -> Void
    let onShowDetails: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.bodySpacing) {
            FilmModeResultRow(
                title: "Adjusted Shutter",
                display: formatReciprocityTimeDisplay(resultState.adjustedShutterSeconds),
                primaryFont: .headline.weight(.semibold),
                secondaryFont: .footnote,
                primaryColor: .primary.opacity(0.88),
                actionState: resultState.adjustedShutterAction,
                onStartTimer: onStartAdjustedShutterTimer,
                style: style
            )

            Divider()

            FilmModeReciprocityStateRow(
                reciprocityState: resultState.reciprocityState,
                showsDetailsEntry: canShowDetails,
                onShowDetails: onShowDetails,
                style: style
            )

            Divider()

            FilmModeCorrectedExposureRow(
                correctedExposure: resultState.correctedExposure,
                actionState: resultState.correctedExposureAction,
                onStartTimer: onStartCorrectedExposureTimer,
                style: style
            )

        }
    }
}

private struct FilmModeResultRow: View {
    let title: String
    let display: TimeDisplay
    let primaryFont: Font
    let secondaryFont: Font
    let primaryColor: Color
    let actionState: FilmModeTimerActionState
    let onStartTimer: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        HStack(alignment: .top, spacing: style.resultActionSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                DurationDisplayBlock(
                    primaryText: display.primary,
                    secondaryText: display.secondary,
                    primaryColor: primaryColor,
                    primaryFont: primaryFont,
                    secondaryFont: secondaryFont
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TimerActionView(
                canStartTimer: actionState.canStartTimer,
                onStart: onStartTimer,
                style: style,
                accessibilityIdentifier: "adjusted-shutter-start-timer-button",
                accessibilityLabel: actionState.accessibilityLabel,
                accessibilityHint: actionState.accessibilityHint
            )
        }
        .frame(minHeight: style.filmResultRowMinHeight, alignment: .top)
    }
}

private struct FilmModeReciprocityStateRow: View {
    let reciprocityState: FilmModeReciprocityStateDisplayState
    let showsDetailsEntry: Bool
    let onShowDetails: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Reciprocity")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            if showsDetailsEntry {
                Button(action: onShowDetails) {
                    HStack(spacing: 8) {
                        Text(reciprocityState.badgeText)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(badgeForegroundColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(badgeBackgroundColor)
                            .clipShape(Capsule())
                            .accessibilityIdentifier("film-mode-reciprocity-badge")

                        if reciprocityState.showsInfoAffordance {
                            Image(systemName: "info.circle")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("film-mode-reciprocity-info")
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.leading, 8)
                    .padding(.trailing, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("film-mode-reciprocity-details-button")
                .accessibilityLabel("Open reciprocity details")
                .accessibilityValue(reciprocityState.badgeText)
                .accessibilityHint(reciprocityState.infoText)
            } else {
                HStack(spacing: 8) {
                    Text(reciprocityState.badgeText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(badgeForegroundColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(badgeBackgroundColor)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("film-mode-reciprocity-badge")

                    if reciprocityState.showsInfoAffordance {
                        Image(systemName: "info.circle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("film-mode-reciprocity-info")
                    }
                }
            }
        }
        .frame(minHeight: style.filmResultRowMinHeight, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reciprocity")
        .accessibilityValue(reciprocityState.badgeText)
        .accessibilityHint(reciprocityState.infoText)
    }

    private var badgeForegroundColor: Color {
        switch reciprocityState.tone {
        case .trusted:
            return Color(.systemGreen)
        case .measured:
            return Color(.systemBlue)
        case .caution:
            return Color(.systemOrange)
        case .advisory:
            return Color(.systemBrown)
        case .unsupported:
            return Color(.systemRed)
        }
    }

    private var badgeBackgroundColor: Color {
        switch reciprocityState.tone {
        case .trusted:
            return Color(.systemGreen).opacity(0.14)
        case .measured:
            return Color(.systemBlue).opacity(0.14)
        case .caution:
            return Color(.systemOrange).opacity(0.16)
        case .advisory:
            return Color(.systemBrown).opacity(0.14)
        case .unsupported:
            return Color(.systemRed).opacity(0.14)
        }
    }
}

private struct FilmModeCorrectedExposureRow: View {
    let correctedExposure: FilmModeCorrectedExposureDisplayState
    let actionState: FilmModeTimerActionState
    let onStartTimer: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        HStack(alignment: .top, spacing: style.resultActionSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Corrected Exposure")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                CorrectedExposureDisplayBlock(
                    kind: correctedExposure.kind,
                    primaryText: correctedExposure.primaryText,
                    secondaryText: correctedExposure.secondaryText,
                    style: style
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: style.filmResultRowMinHeight, alignment: .topLeading)

            TimerActionView(
                canStartTimer: actionState.canStartTimer,
                onStart: onStartTimer,
                style: style,
                accessibilityIdentifier: "corrected-exposure-start-timer-button",
                accessibilityLabel: actionState.accessibilityLabel,
                accessibilityHint: actionState.accessibilityHint
            )
        }
    }
}

private struct CorrectedExposureDisplayBlock: View {
    let kind: FilmModeCorrectedExposureDisplayKind
    let primaryText: String
    let secondaryText: String
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(primaryText)
                .font(primaryFont)
                .foregroundStyle(primaryColor)
                .monospacedDigit()
                .lineLimit(kind == .quantified ? 1 : 2)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("film-mode-corrected-exposure-primary")

            if !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(style.correctedExposureSecondaryFont)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .accessibilityIdentifier("film-mode-corrected-exposure-secondary")
            }
        }
        .frame(maxWidth: .infinity, minHeight: style.correctedExposureValueMinHeight, alignment: .topLeading)
    }

    private var primaryFont: Font {
        switch kind {
        case .quantified:
            return style.correctedExposurePrimaryFont
        case .advisory, .unsupported, .noFilmSelected:
            return .headline.weight(.semibold)
        }
    }

    private var primaryColor: Color {
        switch kind {
        case .quantified:
            return .primary
        case .advisory:
            return Color(.systemOrange)
        case .unsupported:
            return Color(.systemRed)
        case .noFilmSelected:
            return .secondary
        }
    }
}

private struct NDStopSelectionRow: View {
    @Binding var ndStep: NDStep
    let ndStepValues: [NDStep]
    let formatNDStop: (NDStep) -> String
    let onContinuousSelectionChange: (NDStep) -> Void
    let onInteractionEnd: () -> Void
    let pickerHeight: CGFloat
    let style: ExposureWorkspaceMainLayoutStyle

    private var layout: PickerColumnLayout {
        style.pickerColumnLayout(for: .ndStop)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.pickerLabelSpacing) {
            Text("ND Filter")
                .font(.subheadline.weight(.semibold))

            Picker("ND Filter", selection: $ndStep) {
                ForEach(ndStepValues, id: \.self) { step in
                    NDStopPickerValue(
                        valueText: formatNDStop(step),
                        style: style,
                        layout: layout
                    )
                    .tag(step)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: pickerHeight)
            .clipped()
            .background {
                WheelPickerContinuousObserver(
                    onSelectedRowChange: { row in
                        guard ndStepValues.indices.contains(row) else {
                            return
                        }

                        onContinuousSelectionChange(ndStepValues[row])
                    },
                    onInteractionEnd: onInteractionEnd
                )
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                PickerUnitSelectionBand(
                    unitText: "stops",
                    style: style,
                    layout: layout
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ShutterSelectionRow: View {
    @Binding var baseShutter: Double
    let shutterSpeeds: [Double]
    let formatShutter: (TimeInterval) -> String
    let onContinuousSelectionChange: (Double) -> Void
    let onInteractionEnd: () -> Void
    let pickerHeight: CGFloat
    let style: ExposureWorkspaceMainLayoutStyle

    private var layout: PickerColumnLayout {
        style.pickerColumnLayout(for: .shutter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.pickerLabelSpacing) {
            Text("Base Shutter")
                .font(.subheadline.weight(.semibold))

            Picker("Base Shutter", selection: $baseShutter) {
                ForEach(shutterSpeeds, id: \.self) { speed in
                    ShutterPickerValue(
                        valueText: shutterValueText(for: speed),
                        style: style,
                        layout: layout
                    )
                    .tag(speed)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: pickerHeight)
            .clipped()
            .background {
                WheelPickerContinuousObserver(
                    onSelectedRowChange: { row in
                        guard shutterSpeeds.indices.contains(row) else {
                            return
                        }

                        onContinuousSelectionChange(shutterSpeeds[row])
                    },
                    onInteractionEnd: onInteractionEnd
                )
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                PickerUnitSelectionBand(
                    unitText: "s",
                    style: style,
                    layout: layout
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func shutterValueText(for speed: TimeInterval) -> String {
        formatShutter(speed)
            .replacingOccurrences(of: "s", with: "")
    }
}

private struct NDStopPickerValue: View {
    let valueText: String
    let style: ExposureWorkspaceMainLayoutStyle
    let layout: PickerColumnLayout

    var body: some View {
        Text(valueText)
            .font(style.pickerValueFont)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(
                .trailing,
                layout.valueTextTrailingInset(
                    selectionBandContentTrailingInset: style.pickerSelectionBandContentTrailingInset
                )
            )
    }
}

private struct ShutterPickerValue: View {
    let valueText: String
    let style: ExposureWorkspaceMainLayoutStyle
    let layout: PickerColumnLayout

    var body: some View {
        Text(valueText)
            .font(style.pickerValueFont)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(
                .trailing,
                layout.valueTextTrailingInset(
                    selectionBandContentTrailingInset: style.pickerSelectionBandContentTrailingInset
                )
            )
    }
}

private struct PickerUnitSelectionBand: View {
    let unitText: String
    let style: ExposureWorkspaceMainLayoutStyle
    let layout: PickerColumnLayout

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(height: style.pickerSelectionBandHeight)
            .overlay {
                HStack {
                    Spacer()

                    Text(unitText)
                        .font(style.pickerOverlayUnitFont)
                        .foregroundStyle(.secondary)
                        .opacity(unitText == "s" ? 0.92 : 0.96)
                        .frame(width: layout.unitTextWidth, alignment: .trailing)
                        .padding(.trailing, layout.unitTextTrailingInset)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                .padding(.trailing, style.pickerSelectionBandContentTrailingInset)
            }
            .padding(.horizontal, style.pickerSelectionBandHorizontalInset)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct TimerActionView: View {
    let canStartTimer: Bool
    let onStart: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle
    let accessibilityIdentifier: String
    let accessibilityLabel: String
    let accessibilityHint: String

    var body: some View {
        Button {
            onStart()
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: style.timerActionIconSize, weight: .semibold))
                .foregroundStyle(canStartTimer ? Color.accentColor : Color.secondary.opacity(0.8))
                .frame(width: style.timerActionSize, height: style.timerActionSize)
                .background(
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                )
                .overlay(
                    Circle()
                        .stroke(Color(.separator).opacity(0.55), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canStartTimer)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}


struct DurationDisplayBlock: View {
    let primaryText: String
    let secondaryText: String?
    let primaryColor: Color
    let primaryFont: Font
    let secondaryFont: Font

    var body: some View {
        VStack(spacing: 2) {
            Text(primaryText)
                .font(primaryFont)
                .foregroundStyle(primaryColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let secondaryText, !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(secondaryFont)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
private extension View {
    func sectionCardStyle(style: ExposureWorkspaceMainLayoutStyle = .regular) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(style.sectionCardPadding)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: style.sectionCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: style.sectionCornerRadius, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 1)
            )
    }
}

private extension String {
    var containsKoreanCharacters: Bool {
        unicodeScalars.contains { scalar in
            (0xAC00...0xD7A3).contains(scalar.value)
        }
    }
}

private func assertNoKoreanUIStrings(_ strings: [String]) {
#if DEBUG
    assert(strings.allSatisfy { !$0.containsKoreanCharacters })
#endif
}
