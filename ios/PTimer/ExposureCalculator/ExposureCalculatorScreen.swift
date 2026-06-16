import SwiftUI
import PTimerKit
import PTimerCore
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
    /// Visibility of the custom-film editor sheet. Toggled by the
    /// header "+" button inside the film selector; the selector
    /// collapses first so the sheet presents over a stable
    /// background.
    @State private var isCustomFilmEditorPresented = false
    /// When non-nil, the editor opens in Edit mode prefilled from
    /// this existing custom film. `.sheet(item:)` keys off this so
    /// dismissal clears it back to nil.
    @State private var customFilmBeingEdited: EditingCustomFilmIdentity?
    /// PTIMER-180: drives the Create-Formula-from-table sheet — a
    /// create-mode formula editor seeded from a saved custom table.
    @State private var customFormulaSeed: CustomFormulaSeedContext?
    /// PTIMER-180: id of a table the photographer asked to turn into a
    /// formula from inside the table editor. The seeded formula editor
    /// is presented only after the table editor sheet dismisses (a new
    /// sheet cannot be presented while another is dismissing), via the
    /// sheet's `onDismiss`.
    @State private var pendingFormulaSeedFilmID: String?

    private let bottomSheetAdapter: BottomSheetWorkspacePresentationAdapter

    /// Persists the (possibly just-edited) table, then queues the
    /// seeded Custom Formula editor to open once the table editor
    /// sheet finishes dismissing. `dismiss` closes the current table
    /// editor sheet.
    private func saveTableThenSeedFormula(_ tableFilm: FilmIdentity, dismiss: () -> Void) {
        viewModel.addCustomFilm(tableFilm)
        pendingFormulaSeedFilmID = tableFilm.id
        dismiss()
    }

    /// Edit-flow editor for a saved custom film. PTIMER-180: re-hydrate
    /// the linked reference table from the formula's persisted
    /// `referenceTableFilmID` so the graph markers and the Calculation
    /// Basis Reference / Error columns reappear (the creation flow holds
    /// the anchors in memory; the edit flow opens from persistence).
    /// Tables and unlinked formulas resolve to no anchors and edit as
    /// before. Anchors come from the table's *current* state, so a
    /// table edited after the formula was saved is reflected here
    /// without changing the saved formula parameters.
    @ViewBuilder
    private func customFilmEditorSheet(
        for editing: EditingCustomFilmIdentity
    ) -> some View {
        let resolution = CustomFilmReferenceTableResolver.resolve(for: editing.film) {
            viewModel.customFilmLibrary.film(withID: $0)
        }
        CustomFilmEditorView(
            editing: editing.film,
            linkedReferenceTableAnchors: resolution.anchors,
            linkedReferenceTableMissing: resolution.isLinkedButMissing,
            onSave: { updated in
                // Upsert by id replaces the existing entry in place, so
                // any running timer's identity snapshot stays frozen at
                // its start-time values while live calculations switch
                // to the edited formula on the next read.
                viewModel.addCustomFilm(updated)
                customFilmBeingEdited = nil
            },
            onCreateFormula: { tableFilm in
                saveTableThenSeedFormula(tableFilm) {
                    customFilmBeingEdited = nil
                }
            },
            onCancel: {
                customFilmBeingEdited = nil
            }
        )
    }

    /// `onDismiss` hook for the table editor sheets: if a Create
    /// Custom Formula action is pending, resolve the saved table and
    /// present the seeded formula editor. Re-resolves the seed from the
    /// persisted table so an unfittable edit safely opens nothing.
    private func presentPendingFormulaSeed() {
        guard let filmID = pendingFormulaSeedFilmID else { return }
        pendingFormulaSeedFilmID = nil
        guard let film = viewModel.customFilmLibrary.film(withID: filmID),
              let seed = CustomFilmEditorFormState.creatingFormula(fromTable: film) else {
            return
        }
        customFormulaSeed = CustomFormulaSeedContext(
            sourceFilmID: film.id,
            seedFormState: seed,
            linkedTableAnchors: customTableAnchors(of: film)
        )
    }

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
            // `geometry.size` is already safe-area-trimmed, so pass
            // it as the workspace area without re-subtracting safe
            // insets. The ZStack below lives in the same trimmed
            // region; bottom paddings measure from its bottom edge.
            let workspaceHeight = ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
                workspaceArea: geometry.size.height
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

                // Page marker — anchored above the rail's reserved
                // band. y-position is independent of timer presence.
                CameraSlotPagerIndicator(
                    count: viewModel.availableCameraSlots.count,
                    activeIndex: viewModel.activeCameraSlotIndex
                )
                .padding(
                    .bottom,
                    ExposureWorkspaceLayoutMetrics.pageMarkerBottomOffset()
                )
                .frame(maxWidth: .infinity)

                // Running timer preview rail boundary. Always
                // rendered so the area reads as a preview surface
                // even when no cards are present.
                TimerPreviewRailBackground()
                    .padding(
                        .bottom,
                        ExposureWorkspaceLayoutMetrics.timerStripBottomOffset()
                    )
                    .frame(maxWidth: .infinity)

                // Compact timer cards — rendered inside the rail
                // band when timers exist.
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
                        ExposureWorkspaceLayoutMetrics.timerStripBottomOffset()
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
                        onCreateCustomFilm: {
                            // Dismiss the selector first so the
                            // editor sheet presents over a stable
                            // background — leaving the selector up
                            // would double-stack a material overlay
                            // behind the form sheet.
                            isFilmSelectorPresented = false
                            isCustomFilmEditorPresented = true
                        },
                        onDeleteCustomFilm: { filmID in
                            // Drop the row immediately so the picker
                            // reflects the deletion; if the deleted
                            // row was active, the ViewModel clears
                            // the selection internally.
                            viewModel.deleteCustomFilm(id: filmID)
                        },
                        onEditCustomFilm: { filmID in
                            // Edit collapses the selector and opens
                            // the editor prefilled from the existing
                            // film.
                            guard let film = viewModel.customFilmLibrary
                                .film(withID: filmID) else {
                                return
                            }
                            isFilmSelectorPresented = false
                            customFilmBeingEdited = EditingCustomFilmIdentity(film: film)
                        },
                        onCreateFormulaFromTable: { filmID in
                            // PTIMER-180: seed a NEW formula from the
                            // saved table's fitted formula and open the
                            // existing formula editor, pre-linked to the
                            // table for reference / error display.
                            guard let film = viewModel.customFilmLibrary.film(withID: filmID),
                                  let seed = CustomFilmEditorFormState.creatingFormula(fromTable: film) else {
                                return
                            }
                            isFilmSelectorPresented = false
                            customFormulaSeed = CustomFormulaSeedContext(
                                sourceFilmID: film.id,
                                seedFormState: seed,
                                linkedTableAnchors: customTableAnchors(of: film)
                            )
                        },
                        style: style
                    )
                    .padding(.top, screenLevelSelectorOverlayTopPadding(style: style))
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
            // Presented via `isPresented` (not `item`) so switching the
            // profile/model inside Details refreshes the snapshot in
            // place. An `item` binding would re-present the sheet when
            // the snapshot identity changes, resetting the detent
            // (PTIMER-159).
            .sheet(
                isPresented: Binding(
                    get: { presentedFilmDetails != nil },
                    set: { if !$0 { presentedFilmDetails = nil } }
                )
            ) {
                if let details = presentedFilmDetails {
                    FilmModeDetailsSheet(
                        details: details,
                        onSelectProfile: { profileID in
                            viewModel.selectProfileVariant(profileID: profileID)
                            // Re-read the recomputed snapshot so the open
                            // sheet reflects the newly active profile/model.
                            presentedFilmDetails = viewModel.filmModeDetailsDisplayState
                        }
                    )
                }
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
            .sheet(isPresented: $isCustomFilmEditorPresented, onDismiss: presentPendingFormulaSeed) {
                CustomFilmEditorView(
                    onSave: { film in
                        viewModel.addCustomFilm(film)
                        // New-custom flow: auto-select the freshly
                        // saved film into the current slot so the
                        // photographer is not dropped back into "No
                        // film" after creating one.
                        viewModel.selectPresetFilm(film)
                        isCustomFilmEditorPresented = false
                    },
                    onCreateFormula: { tableFilm in
                        saveTableThenSeedFormula(tableFilm) {
                            isCustomFilmEditorPresented = false
                        }
                    },
                    onCancel: {
                        isCustomFilmEditorPresented = false
                    }
                )
            }
            .sheet(item: $customFilmBeingEdited, onDismiss: presentPendingFormulaSeed) { editing in
                customFilmEditorSheet(for: editing)
            }
            .sheet(item: $customFormulaSeed) { seed in
                CustomFilmEditorView(
                    seededFormState: seed.seedFormState,
                    linkedReferenceTableAnchors: seed.linkedTableAnchors,
                    isSeededFormulaCreate: true,
                    onSave: { film in
                        // A new, independent custom formula profile.
                        // Auto-select it like the New-custom flow.
                        viewModel.addCustomFilm(film)
                        viewModel.selectPresetFilm(film)
                        customFormulaSeed = nil
                    },
                    onCancel: {
                        // Cancel discards the formula; the saved table
                        // is untouched.
                        customFormulaSeed = nil
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

    /// Top padding for the film selector overlay so it drops below
    /// the camera title row. Measured from the top of the trimmed
    /// ZStack; the top safe area sits above and is owned by SwiftUI.
    private func screenLevelSelectorOverlayTopPadding(
        style: ExposureWorkspaceMainLayoutStyle
    ) -> CGFloat {
        style.topPadding + style.selectorOverlayTopPadding
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
                // The active-model selector is sourced from the live view
                // model and shown only on the active page (the main screen).
                activeModelSummary: pageState.isActive ? viewModel.activeFilmModelSummary : nil,
                modelSelection: pageState.isActive ? viewModel.filmDetailsModelSelection : nil,
                onSelectModel: { profileID in
                    guard pageState.isActive else { return }
                    viewModel.selectProfileVariant(profileID: profileID)
                },
                showsResetAction: pageState.isActive && viewModel.canResetFilmModeWorkingContext,
                onResetFilmModeContext: pageState.isActive ? viewModel.resetFilmModeWorkingContext : {},
                onRequestRename: pageState.isActive ? onRequestRename : nil,
                style: style
            )
            // Header carries required visible content (camera title
            // and film selector), so it shares the priority of the
            // Target Shutter and result cards.
            .layoutPriority(1)

            // Target Shutter goal row — sits between the film/profile
            // card and the Base Shutter / ND Filter controls because
            // the target is a shooting input, not a secondary read of
            // the result. Stop-difference is computed against the
            // Adjusted Shutter (non-film) or Corrected Exposure (film);
            // see `TargetShutterPresenter`.
            //
            // Shares `layoutPriority(1)` with the header and result
            // cards so workspace shortfall is distributed evenly.
            TargetShutterSectionView(
                displayState: viewModel.targetShutterDisplayState(forPage: pageState),
                canStartTimer: pageState.isActive && viewModel.canStartTargetShutterTimer,
                onSetTarget: pageState.isActive
                    ? { seconds in viewModel.setTargetShutter(seconds) }
                    : { _ in },
                onClearTarget: pageState.isActive ? viewModel.clearTargetShutter : {},
                onStartTargetTimer: pageState.isActive ? viewModel.startTargetShutterTimer : {},
                style: style
            )
            .layoutPriority(1)

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
                resultDurationDisplay: viewModel.resultDurationDisplay,
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
            // Result card carries the photographer's primary read.
            // The `filmResultCardMinHeight` floor enforced inside
            // `ResultSectionView` keeps the 3-row film hierarchy
            // from being compressed past its inner clipShape.
            .layoutPriority(1)

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
    /// Compact active-model summary (name + calculation) for the
    /// single-model case; `nil` when no film is selected. PTIMER-159.
    let activeModelSummary: FilmModeActiveModelSummary?
    /// Present only when the selected film exposes more than one model;
    /// drives the inline segmented model selector.
    let modelSelection: FilmModeDetailsModelSelectionState?
    /// Switches the active model inline (main-screen segmented control).
    let onSelectModel: (String) -> Void
    let showsResetAction: Bool
    let onResetFilmModeContext: () -> Void
    /// Tap handler that opens the rename sheet. Non-nil only on the
    /// active page — inactive pages render the title as plain text
    /// so the photographer cannot rename a slot they are not on.
    let onRequestRename: (() -> Void)?
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.headerContentSpacing) {
            HStack(spacing: 8) {
                slotTitleView
                    .font(style.headerTitleFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.18), value: activeCameraSlotID)
                    .accessibilityIdentifier("camera-slot-title")
                    .frame(maxWidth: .infinity, alignment: .leading)

                // PTIMER-172: Reset moved onto the title row so the Film
                // card no longer reserves a trailing strip of vertical
                // space at the bottom solely to hold it. Kept in the tree
                // (opacity/hit-testing gated) rather than conditionally
                // removed so its presence is stable for assistive tech.
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

            FilmSelectionRow(
                selectorEntries: selectorEntries,
                selectedFilmID: selectedFilmID,
                displayState: filmSelectionDisplayState,
                onToggleSelector: onToggleSelector,
                style: style
            )

            if let modelSelection {
                // Compact inline segmented selector for quick switching
                // while the main calculation values stay visible.
                ReciprocityModelSegmentedSelector(
                    selection: modelSelection,
                    onSelect: onSelectModel
                )
            } else if let activeModelSummary {
                // Single-model film: one compact line, no selector.
                ReciprocityModelCompactLabel(summary: activeModelSummary)
            }
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

/// Compact inline segmented model selector on the main calculation
/// screen (PTIMER-159). Switches the active reciprocity model in place
/// — the photographer keeps seeing the calculation values — without a
/// standalone heading or large card. Shown only when the selected film
/// exposes more than one model.
private struct ReciprocityModelSegmentedSelector: View {
    let selection: FilmModeDetailsModelSelectionState
    let onSelect: (String) -> Void

    var body: some View {
        Picker(
            "Reciprocity model",
            selection: Binding(
                get: { selection.activeOptionID },
                set: { onSelect($0) }
            )
        ) {
            ForEach(selection.options) { option in
                Text(option.selectorLabel).tag(option.id)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("reciprocity-model-segmented-selector")
    }
}

/// One-line active-model label for a single-model film. Keeps the
/// active model visible under the film row without any selection
/// affordance or wasted vertical space.
private struct ReciprocityModelCompactLabel: View {
    let summary: FilmModeActiveModelSummary

    var body: some View {
        HStack(spacing: 6) {
            Text("Model")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(summary.name) · \(summary.calculation)")
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reciprocity model")
        .accessibilityValue("\(summary.name), \(summary.calculation)")
        .accessibilityIdentifier("reciprocity-model-compact-label")
    }
}

/// Boundary for the running-timer preview rail. Hairline top edge
/// and a barely-perceptible fill mark the rail as a preview surface
/// without claiming the weight of a card or container.
private struct TimerPreviewRailBackground: View {
    var body: some View {
        Rectangle()
            .fill(Color(.tertiarySystemFill).opacity(0.45))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(.separator).opacity(0.65))
                    .frame(height: hairlineThickness)
            }
            .frame(height: ExposureWorkspaceLayoutMetrics.timerStripHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .accessibilityIdentifier("main-screen-timer-rail-background")
    }

    /// Pixel-accurate 1-physical-pixel divider that scales with the
    /// device's screen scale (e.g. 1/3 pt on @3x displays).
    private var hairlineThickness: CGFloat {
        1.0 / max(UIScreen.main.scale, 1)
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

extension View {
    /// Internal so cross-file result-section views (e.g.,
    /// `TargetShutterSectionView`) can render with the same card
    /// chrome as the in-file result rows.
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

/// `Identifiable` wrapper so the screen can drive the Edit sheet
/// via `.sheet(item:)` (`FilmIdentity` itself is not
/// `Identifiable` because the domain model already uses `id` as a
/// regular field). The wrapper's id mirrors the film id so
/// SwiftUI dismisses correctly when the screen reassigns the
/// state.
private struct EditingCustomFilmIdentity: Identifiable {
    let film: FilmIdentity
    var id: String { film.id }
}

/// PTIMER-180: identifiable context for the Create-Formula-from-table
/// sheet — the seeded create-mode form plus the source table's anchors
/// for the editor's reference / error display.
private struct CustomFormulaSeedContext: Identifiable {
    let sourceFilmID: String
    let seedFormState: CustomFilmEditorFormState
    let linkedTableAnchors: [TableAnchor]
    var id: String { sourceFilmID }
}

/// The table-interpolation anchors of a custom table film's profile,
/// or `[]` when it carries no table rule. Used to feed the linked
/// reference / error display in the Create-Formula editor.
private func customTableAnchors(of film: FilmIdentity) -> [TableAnchor] {
    for rule in film.profiles.first?.rules ?? [] {
        if case let .tableInterpolation(table) = rule {
            return table.anchors
        }
    }
    return []
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
