import SwiftUI
import UIKit

struct ExposureCalculatorScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel: ExposureCalculatorViewModel
    @StateObject private var bottomSheetStateStore: BottomSheetWorkspaceStateStore
    @StateObject private var bottomSheetSnapshotStore: BottomSheetWorkspaceSnapshotStore

    private let bottomSheetAdapter: BottomSheetWorkspacePresentationAdapter

    @MainActor
    init() {
        self.init(
            viewModel: ExposureCalculatorViewModel(
                dependencies: ViewModelDependencyFactory.production()
            ),
            bottomSheetStateStore: BottomSheetWorkspaceStateStore()
        )
    }

    @MainActor
    init(
        viewModel: ExposureCalculatorViewModel,
        bottomSheetStateStore: BottomSheetWorkspaceStateStore
    ) {
        let adapter = BottomSheetWorkspacePresentationAdapter(
            formatRemaining: viewModel.formatTimerClock,
            timeContext: viewModel.timerTimeContext,
            compactCompletedSupplementaryText: viewModel.compactCompletedSupplementaryText
        )

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
            "Exposure",
            "View All"
        ])
    }

    var body: some View {
        GeometryReader { geometry in
            // Keep the calculator on a stable footprint so sheet detent changes do
            // not cause the core exposure workflow to relayout underneath runtime UI.
            let compactMainContentReservation = Self.calculatorReservedHeight(
                screenHeight: geometry.size.height,
                topSafeArea: geometry.safeAreaInsets.top,
                bottomSafeArea: geometry.safeAreaInsets.bottom
            )

            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ExposureWorkspaceMainContent(
                    style: layoutStyle(for: compactMainContentReservation),
                    viewModel: viewModel,
                    availableHeight: compactMainContentReservation
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if bottomSheetStateStore.isExpanded {
                    Button {
                        bottomSheetStateStore.collapse()
                    } label: {
                        Color.black
                            .opacity(BottomSheetLayoutMetrics.dimOpacity(for: bottomSheetStateStore.detent))
                            .ignoresSafeArea()
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                    .accessibilityIdentifier("bottom-sheet-dim-background")
                }

                BottomSheetWorkspaceShell(
                    stateStore: bottomSheetStateStore,
                    snapshot: bottomSheetSnapshotStore.snapshot,
                    onPauseTimer: viewModel.pauseTimer,
                    onResumeTimer: viewModel.resumeTimer,
                    onRemoveTimer: viewModel.removeTimer,
                    onClearCompletedTimers: viewModel.clearCompletedTimers
                )
                .padding(.bottom, geometry.safeAreaInsets.bottom)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }

            // PTIMER-67: process-alive foreground reactivation only.
            // PTIMER-70 relaunch restore is init-driven in TimerManager and is
            // deliberately not re-triggered from lifecycle observers.
            viewModel.reconcileTimersAfterAppBecomesActive()
        }
    }

    static func calculatorReservedHeight(
        screenHeight: CGFloat,
        topSafeArea: CGFloat,
        bottomSafeArea: CGFloat
    ) -> CGFloat {
        ExposureWorkspaceLayoutMetrics.availableMainContentHeight(
            screenHeight: screenHeight,
            bottomSheetDetent: .compact,
            topSafeArea: topSafeArea,
            bottomSafeArea: bottomSafeArea
        )
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
    @State private var presentedFilmDetails: FilmModeDetailsDisplayState?
    @State private var isFilmSelectorPresented = false

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                HeaderView(
                    selectorEntries: viewModel.filmSelectorEntries,
                    selectedFilmID: viewModel.selectedSelectorEntryID,
                    filmSelectionDisplayState: viewModel.filmSelectionDisplayState,
                    onToggleSelector: { isFilmSelectorPresented.toggle() },
                    showsResetAction: viewModel.canResetFilmModeWorkingContext,
                    onResetFilmModeContext: viewModel.resetFilmModeWorkingContext,
                    style: style
                )
                VariableSectionView(
                    baseShutter: $viewModel.baseShutter,
                    ndStop: $viewModel.ndStop,
                    shutterSpeeds: ExposureCalculatorViewModel.shutterSpeeds,
                    formatShutter: viewModel.formatShutter,
                    onContinuousBaseShutterChange: { value in
                        Task { @MainActor in
                            viewModel.updateLiveBaseShutter(value)
                        }
                    },
                    onContinuousNDStopChange: { value in
                        Task { @MainActor in
                            viewModel.updateLiveNDStop(value)
                        }
                    },
                    onBaseShutterInteractionEnd: {
                        Task { @MainActor in
                            viewModel.clearLiveBaseShutterPreview()
                        }
                    },
                    onNDStopInteractionEnd: {
                        Task { @MainActor in
                            viewModel.clearLiveNDStopPreview()
                        }
                    },
                    style: style
                )

                ResultSectionView(
                    isFilmWorkflowActive: viewModel.isFilmWorkflowActive,
                    calculationResult: viewModel.calculationResult,
                    filmModeExposureResultState: viewModel.filmModeExposureResultState,
                    canShowFilmDetails: viewModel.canShowFilmDetails,
                    formatTimeDisplay: viewModel.formatTimeDisplay,
                    formatReciprocityTimeDisplay: viewModel.formatReciprocityTimeDisplay,
                    canStartTimer: viewModel.canStartTimer,
                    onStartTimer: viewModel.startTimer,
                    onStartFilmAdjustedShutterTimer: viewModel.startFilmAdjustedShutterTimer,
                    onStartFilmCorrectedExposureTimer: viewModel.startFilmCorrectedExposureTimer,
                    onShowFilmDetails: { presentedFilmDetails = viewModel.filmModeDetailsDisplayState },
                    style: style
                )

                Spacer(minLength: style.resultFlowSpacerMinLength)

                Color.clear
                    .frame(height: style.workspaceSeparation)
                    .accessibilityHidden(true)
            }

            if isFilmSelectorPresented {
                Button {
                    isFilmSelectorPresented = false
                } label: {
                    Color.black.opacity(0.06)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("film-selector-overlay-dismiss")

                FilmSelectorOverlay(
                    entries: viewModel.filmSelectorEntries,
                    selectedFilmID: viewModel.selectedSelectorEntryID,
                    onSelectEntry: { entry in
                        viewModel.selectEntry(entry)
                        isFilmSelectorPresented = false
                    },
                    style: style
                )
                .padding(.top, selectorOverlayTopPadding)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                .zIndex(1)
            }
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
        .sheet(item: $presentedFilmDetails) { details in
            FilmModeDetailsSheet(details: details)
        }
        .animation(.easeInOut(duration: 0.16), value: isFilmSelectorPresented)
    }

    private var selectorOverlayTopPadding: CGFloat {
        switch style {
        case .regular:
            return 112
        case .compact:
            return 98
        case .dense:
            return 86
        }
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
    let selectorEntries: [FilmSelectorEntry]
    let selectedFilmID: String?
    let filmSelectionDisplayState: FilmSelectionDisplayState
    let onToggleSelector: () -> Void
    let showsResetAction: Bool
    let onResetFilmModeContext: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.headerContentSpacing) {
            Text("Exposure")
                .font(style.headerTitleFont)

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
    let entries: [FilmSelectorEntry]
    let selectedFilmID: String?
    let onSelectEntry: (FilmSelectorEntry) -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
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
                    .padding(.horizontal, 18)
                    .frame(height: rowHeight)
                    .background(rowBackground(for: entry))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("film-selector-entry-\(entry.id)")

                if index < entries.count - 1 {
                    Color.clear.frame(height: 6)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: overlayWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityIdentifier("film-selector-overlay")
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
            return 56
        case .compact:
            return 52
        case .dense:
            return 48
        }
    }

    private func isSelected(_ entry: FilmSelectorEntry) -> Bool {
        entry.id == selectedFilmID
    }

    @ViewBuilder
    private func rowBackground(for entry: FilmSelectorEntry) -> some View {
        if isSelected(entry) {
            Color.primary.opacity(0.06)
        } else {
            Color.clear
        }
    }
}

private struct VariableSectionView: View {
    @Binding var baseShutter: Double
    @Binding var ndStop: Int
    let shutterSpeeds: [Double]
    let formatShutter: (TimeInterval) -> String
    let onContinuousBaseShutterChange: (Double) -> Void
    let onContinuousNDStopChange: (Int) -> Void
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
                    ndStop: $ndStop,
                    onContinuousSelectionChange: onContinuousNDStopChange,
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

/// Stable initial detent for the Reciprocity Details bottom sheet.
/// Using a single named constant ensures every profile type (official, unofficial,
/// formula, table, advisory) presents the sheet at the same initial height.
private let reciprocityDetailsInitialDetent: PresentationDetent = .fraction(0.85)

private struct FilmModeDetailsSheet: View {
    let details: FilmModeDetailsDisplayState
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedDetent: PresentationDetent = reciprocityDetailsInitialDetent
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: FilmModeDetailsScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .named("film-mode-details-scroll")).minY
                            )
                    }
                    .frame(height: 0)

                    FilmModeDetailsSummary(summary: details.summary)

                    FilmModeDetailsCurrentResultBlock(
                        currentResult: details.currentResult,
                        summary: details.summary
                    )

                    // Evidence sections (Profile, Formula, Reference) before graph
                    ForEach(details.sections.filter { $0.title != "Sources" }) { section in
                        FilmModeDetailsSectionCard(
                            title: sectionDisplayTitle(for: section.title),
                            section: section,
                            detailRowText: detailRowText(for:)
                        )
                    }

                    if let graph = details.graph {
                        FilmModeDetailsGraph(graph: graph)
                    } else if details.summary.tone != .advisory && details.currentResult.layout != .compactValue {
                        FilmModeDetailsGraphUnavailableNote()
                    }

                    // Sources section after graph
                    ForEach(details.sections.filter { $0.title == "Sources" }) { section in
                        FilmModeDetailsSectionCard(
                            title: sectionDisplayTitle(for: section.title),
                            section: section,
                            detailRowText: detailRowText(for:)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("film-mode-details-sheet-content")
            }
            .coordinateSpace(name: "film-mode-details-scroll")
            .background(Color(.systemGroupedBackground))
            .onPreferenceChange(FilmModeDetailsScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showsStickySummary {
                    FilmModeDetailsStickySummary(
                        summary: details.summary,
                        currentResult: details.currentResult
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle(details.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .animation(.easeInOut(duration: 0.18), value: showsStickySummary)
        .presentationDetents([reciprocityDetailsInitialDetent, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
    }

    private func detailRowFont(for row: FilmModeDetailsRowState) -> Font {
        switch row.style {
        case .standard:
            return .callout
        case .referenceBlock:
            return .system(.callout, design: .monospaced)
        case .formulaExpression:
            return .callout.weight(.medium)
        }
    }

    @ViewBuilder
    private func detailRowText(for row: FilmModeDetailsRowState) -> some View {
        switch row.style {
        case .formulaExpression:
            formulaExpressionText(row.value)
        case .referenceBlock:
            Text(row.value)
                .font(.system(.footnote, design: .monospaced))
                .minimumScaleFactor(0.75)
                .lineLimit(nil)
        case .standard:
            Text(row.value)
                .font(detailRowFont(for: row))
        }
    }

    private func formulaExpressionText(_ value: String) -> Text {
        guard
            let caretIndex = value.firstIndex(of: "^"),
            value.index(after: caretIndex) < value.endIndex
        else {
            return Text(value)
                .font(.callout.weight(.medium))
        }

        let base = String(value[..<caretIndex])
        let exponent = String(value[value.index(after: caretIndex)...])

        return Text(base)
            .font(.callout.weight(.medium))
        + Text(exponent)
            .font(.caption.weight(.semibold))
            .baselineOffset(7)
    }

    private func sectionDisplayTitle(for title: String) -> String {
        switch title {
        case "Reference":
            return "Reference data"
        default:
            return title
        }
    }

    private var showsStickySummary: Bool {
        verticalSizeClass != .compact && scrollOffset < -110
    }
}

private struct FilmModeDetailsScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct FilmModeDetailsStickySummary: View {
    let summary: FilmModeDetailsSummaryState
    let currentResult: FilmModeDetailsCurrentResultState

    var body: some View {
        HStack(spacing: 10) {
            Text(summary.badgeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(badgeForegroundColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(badgeBackgroundColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let secondaryLine {
                    Text(secondaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 3)
    }

    private var primaryLine: String {
        if currentResult.layout == .comparison,
           currentResult.correctedExposure.emphasizesValue {
            return "\(currentResult.correctedExposure.valueText) corrected"
        }

        return summary.summaryText
    }

    private var secondaryLine: String? {
        switch currentResult.layout {
        case .compactValue:
            return nil
        case .compactPair, .comparison:
            return "\(currentResult.adjustedShutter.valueText) adjusted"
        }
    }

    private var badgeBackgroundColor: Color {
        switch summary.tone {
        case .trusted:
            return Color.green.opacity(0.16)
        case .measured:
            return Color.blue.opacity(0.14)
        case .caution:
            return Color.orange.opacity(0.16)
        case .advisory:
            return Color.yellow.opacity(0.18)
        case .unsupported:
            return Color.red.opacity(0.14)
        }
    }

    private var badgeForegroundColor: Color {
        switch summary.tone {
        case .trusted:
            return .green
        case .measured:
            return .blue
        case .caution:
            return .orange
        case .advisory:
            return .yellow.opacity(0.9)
        case .unsupported:
            return .red
        }
    }
}

private struct FilmModeDetailsSectionCard<RowContent: View>: View {
    let title: String
    let section: FilmModeDetailsSectionState
    let detailRowText: (FilmModeDetailsRowState) -> RowContent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(section.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        if !row.title.isEmpty {
                            Text(row.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        if let destinationURL = row.destinationURL {
                            Link(destination: destinationURL) {
                                detailRowText(row)
                                    .foregroundStyle(.tint)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            detailRowText(row)
                                .foregroundStyle(.primary.opacity(0.84))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(row.title.isEmpty ? section.title : row.title)
                    .accessibilityValue(row.value)

                    if row.id != section.rows.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FilmModeDetailsGraphUnavailableNote: View {
    var body: some View {
        Text("No quantified reference graph is available.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private struct FilmModeDetailsSummary: View {
    let summary: FilmModeDetailsSummaryState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.badgeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(badgeForegroundColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(badgeBackgroundColor)
                )

            Text(summary.summaryText)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            if let detailText = summary.detailText {
                Text(detailText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var badgeBackgroundColor: Color {
        switch summary.tone {
        case .trusted:
            return Color.green.opacity(0.16)
        case .measured:
            return Color.blue.opacity(0.14)
        case .caution:
            return Color.orange.opacity(0.16)
        case .advisory:
            return Color.yellow.opacity(0.18)
        case .unsupported:
            return Color.red.opacity(0.14)
        }
    }

    private var badgeForegroundColor: Color {
        switch summary.tone {
        case .trusted:
            return .green
        case .measured:
            return .blue
        case .caution:
            return .orange
        case .advisory:
            return .yellow.opacity(0.9)
        case .unsupported:
            return .red
        }
    }
}

private struct FilmModeDetailsCurrentResultBlock: View {
    let currentResult: FilmModeDetailsCurrentResultState
    let summary: FilmModeDetailsSummaryState

    var body: some View {
        Group {
            switch currentResult.layout {
            case .compactValue:
                compactValueBody
            case .compactPair:
                compactPairBody
            case .comparison:
                comparisonBody
            }
        }
    }

    private func valueColumn(
        for value: FilmModeDetailsCurrentResultValueState
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value.valueText)
                .font(value.emphasizesValue ? .system(.title2, design: .rounded).weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(value.emphasizesValue ? .primary : secondaryValueColor(for: value))
                .minimumScaleFactor(0.75)
                .lineLimit(2)

            if let detailText = value.detailText {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactValueBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let note = currentResult.correctedExposure.detailText, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var compactPairBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            compactLine(
                title: currentResult.adjustedShutter.title,
                value: currentResult.adjustedShutter.valueText,
                valueColor: .primary
            )

            compactLine(
                title: currentResult.correctedExposure.title,
                value: currentResult.correctedExposure.valueText,
                valueColor: secondaryValueColor(for: currentResult.correctedExposure)
            )

            if let detailText = currentResult.correctedExposure.detailText, !detailText.isEmpty {
                Text(detailText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var comparisonBody: some View {
        HStack(spacing: 12) {
            valueColumn(for: currentResult.adjustedShutter)

            Divider()

            valueColumn(for: currentResult.correctedExposure)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func compactLine(
        title: String,
        value: String,
        valueColor: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .minimumScaleFactor(0.8)
        }
    }

    private func secondaryValueColor(
        for value: FilmModeDetailsCurrentResultValueState
    ) -> Color {
        guard value.title == "Corrected Exposure" else {
            return .primary
        }

        switch summary.tone {
        case .unsupported, .advisory:
            return .orange
        case .trusted, .measured, .caution:
            return .primary
        }
    }
}

private struct FilmModeDetailsLegendChip: View {
    let symbol: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct FilmModeDetailsLegendFlow: View {
    let items: [(symbol: String, color: Color, text: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(rows[rowIndex], id: \.text) { item in
                        FilmModeDetailsLegendChip(
                            symbol: item.symbol,
                            color: item.color,
                            text: item.text
                        )
                    }
                }
            }
        }
    }

    private var rows: [[(symbol: String, color: Color, text: String)]] {
        guard !items.isEmpty else {
            return []
        }

        var result: [[(symbol: String, color: Color, text: String)]] = []
        var currentRow: [(symbol: String, color: Color, text: String)] = []

        for item in items {
            if currentRow.count == 2 {
                result.append(currentRow)
                currentRow = [item]
            } else {
                currentRow.append(item)
            }
        }

        if !currentRow.isEmpty {
            result.append(currentRow)
        }

        return result
    }
}

private struct FilmModeDetailsGraphAxisLabel: View {
    let text: String
    let vertical: Bool

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .rotationEffect(vertical ? .degrees(-90) : .zero)
            .fixedSize()
            .frame(
                width: vertical ? 24 : nil,
                height: vertical ? 196 : nil,
                alignment: .center
            )
    }
}

private struct FilmModeDetailsGraphStateNote: View {
    let symbol: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FilmModeDetailsGraph: View {
    let graph: FilmModeDetailsGraphDisplayState

    private let graphHeight: CGFloat = 196
    private let plotInset: CGFloat = 28
    private let yAxisColumnWidth: CGFloat = 28
    private let yTickLabelInset: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(graph.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text("Corrected exposure vs adjusted shutter")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    FilmModeDetailsGraphAxisLabel(text: graph.yAxisLabel, vertical: true)
                        .frame(width: yAxisColumnWidth)

                    VStack(alignment: .leading, spacing: 10) {
                        GeometryReader { geometry in
                            let plotSize = CGSize(
                                width: max(geometry.size.width - (plotInset * 2), 1),
                                height: max(geometry.size.height - (plotInset * 2), 1)
                            )

                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))

                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)

                                if let supportedRangeUpperBoundSeconds = graph.supportedRangeUpperBoundSeconds,
                                   graph.usesCurrentInputGuideOnly {
                                    supportedRegion(
                                        endSeconds: supportedRangeUpperBoundSeconds,
                                        in: plotSize
                                    )
                                    .padding(plotInset)
                                }

                                if let unsupportedStart = graph.unsupportedRegionStartSeconds {
                                    unsupportedRegion(
                                        startSeconds: unsupportedStart,
                                        in: plotSize
                                    )
                                    .padding(plotInset)
                                }

                                graphGrid(in: plotSize)
                                    .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .padding(plotInset)

                                yAxisTickLabels(in: plotSize)
                                    .padding(plotInset)

                                sourcePath(in: plotSize)
                                    .stroke(
                                        graph.kind == .formula ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.82),
                                        style: StrokeStyle(
                                            lineWidth: graph.kind == .formula ? 2.4 : 1.8,
                                            lineCap: .round,
                                            lineJoin: .round
                                        )
                                    )
                                    .padding(plotInset)

                                if let supportedRangeUpperBoundSeconds = graph.supportedRangeUpperBoundSeconds {
                                    supportedBoundary(
                                        at: supportedRangeUpperBoundSeconds,
                                        in: plotSize
                                    )
                                    .padding(plotInset)
                                }

                                if graph.kind == .table {
                                    tableAnchorMarkers(in: plotSize)
                                        .padding(plotInset)
                                }

                                if graph.usesCurrentInputGuideOnly,
                                   let currentMeteredExposureSeconds = graph.currentMeteredExposureSeconds {
                                    currentInputGuideOnly(
                                        currentMeteredExposureSeconds: currentMeteredExposureSeconds,
                                        in: plotSize
                                    )
                                    .padding(plotInset)
                                } else if let currentPoint = graph.currentPoint {
                                    currentPointGuide(
                                        for: currentPoint,
                                        in: plotSize
                                    )
                                    .padding(plotInset)

                                    currentPointMarker(
                                        for: currentPoint,
                                        in: plotSize
                                    )
                                    .padding(plotInset)
                                }
                            }
                        }
                        .frame(height: graphHeight)

                        GeometryReader { geometry in
                            xAxisTickLabels(in: geometry.size.width)
                        }
                        .frame(height: 20)

                        FilmModeDetailsGraphAxisLabel(text: graph.xAxisLabel, vertical: false)
                    }
                }

                FilmModeDetailsLegendFlow(items: graphLegendItems)

                FilmModeDetailsGraphStateNote(
                    symbol: graphExplanationSymbol,
                    tint: graphExplanationTint,
                    text: graphExplanationText
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(graphAccessibilityLabel)
            .accessibilityValue(graphAccessibilityValue)
        }
    }

    private func graphGrid(in size: CGSize) -> Path {
        Path { path in
            let horizontalFractions: [CGFloat] = [0.25, 0.5, 0.75]
            let verticalFractions: [CGFloat] = [0.25, 0.5, 0.75]

            for fraction in horizontalFractions {
                let y = size.height * fraction
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }

            for fraction in verticalFractions {
                let x = size.width * fraction
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
    }

    private func sourcePath(in size: CGSize) -> Path {
        Path { path in
            for (index, point) in graph.sourcePoints.enumerated() {
                let plotted = plottedPoint(for: point, in: size)
                if index == 0 {
                    path.move(to: plotted)
                } else {
                    path.addLine(to: plotted)
                }
            }
        }
    }

    private func unsupportedRegion(
        startSeconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(startSeconds, within: graph.xRange, size: size.width)

        return Rectangle()
            .fill(Color.red.opacity(0.08))
            .frame(width: max(size.width - x, 0), height: size.height)
            .position(x: x + max(size.width - x, 0) / 2, y: size.height / 2)
    }

    private func supportedRegion(
        endSeconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(endSeconds, within: graph.xRange, size: size.width)

        return Rectangle()
            .fill(Color.green.opacity(0.06))
            .frame(width: max(x, 0), height: size.height)
            .position(x: max(x, 0) / 2, y: size.height / 2)
    }

    private func supportedBoundary(
        at seconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(seconds, within: graph.xRange, size: size.width)

        return Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        .stroke(Color.primary.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
    }

    @ViewBuilder
    private func tableAnchorMarkers(in size: CGSize) -> some View {
        ZStack {
            ForEach(Array(graph.sourcePoints.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle()
                            .stroke(Color.secondary.opacity(0.8), lineWidth: 1.5)
                    }
                    .position(plottedPoint(for: point, in: size))
            }
        }
    }

    @ViewBuilder
    private func currentPointGuide(
        for currentPoint: FilmModeDetailsGraphCurrentPoint,
        in size: CGSize
    ) -> some View {
        if graph.kind == .table,
           currentPoint.style == .extrapolated,
           let lastSourcePoint = graph.sourcePoints.last {
            Path { path in
                path.move(to: plottedPoint(for: lastSourcePoint, in: size))
                path.addLine(to: plottedPoint(for: currentPoint.point, in: size))
            }
            .stroke(
                Color.orange.opacity(0.7),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4])
            )
        }
    }

    private func currentInputGuideOnly(
        currentMeteredExposureSeconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(currentMeteredExposureSeconds, within: graph.xRange, size: size.width)

        return ZStack {
            Rectangle()
                .fill(Color.red.opacity(0.08))
                .frame(width: 14, height: size.height)
                .position(x: x, y: size.height / 2)

            Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            .stroke(Color.red.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 5]))
        }
    }

    @ViewBuilder
    private func currentPointMarker(
        for currentPoint: FilmModeDetailsGraphCurrentPoint,
        in size: CGSize
    ) -> some View {
        let plotted = plottedPoint(for: currentPoint.point, in: size)

        switch currentPoint.style {
        case .exact:
            Circle()
                .fill(Color.green)
                .frame(width: 14, height: 14)
                .overlay {
                    Circle()
                        .stroke(Color(.systemBackground), lineWidth: 2)
                }
                .position(plotted)
        case .estimated:
            Diamond()
                .fill(Color.blue)
                .frame(width: 15, height: 15)
                .overlay {
                    Diamond()
                        .stroke(Color.blue.opacity(0.25), lineWidth: 5)
                }
                .overlay {
                    Diamond()
                        .stroke(Color(.systemBackground), lineWidth: 2)
                }
                .position(plotted)
        case .extrapolated:
            Triangle()
                .fill(Color.orange)
                .frame(width: 16, height: 15)
                .overlay {
                    Triangle()
                        .stroke(Color(.systemBackground), lineWidth: 2)
                }
                .position(plotted)
        case .formulaDerived:
            Circle()
                .fill(Color.accentColor)
                .frame(width: 15, height: 15)
                .overlay {
                    Circle()
                        .stroke(Color(.systemBackground), lineWidth: 2)
                }
                .overlay {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 5)
                }
                    .position(plotted)
        }
    }

    @ViewBuilder
    private func yAxisTickLabels(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(graph.yAxisTicks) { tick in
                Text(tick.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: yTickLabelInset, alignment: .leading)
                    .position(
                        x: yTickLabelInset / 2,
                        y: size.height - scaledValue(tick.value, within: graph.yRange, size: size.height)
                    )
            }
        }
    }

    private func xAxisTickLabels(in width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(graph.xAxisTicks) { tick in
                Text(tick.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(
                        x: scaledValue(tick.value, within: graph.xRange, size: width),
                        y: 7
                    )
            }
        }
    }

    private func plottedPoint(
        for point: FilmModeDetailsGraphPoint,
        in size: CGSize
    ) -> CGPoint {
        let x = scaledValue(
            point.meteredExposureSeconds,
            within: graph.xRange,
            size: size.width
        )
        let y = size.height - scaledValue(
            point.correctedExposureSeconds,
            within: graph.yRange,
            size: size.height
        )

        return CGPoint(x: x, y: y)
    }

    private func scaledValue(
        _ value: Double,
        within range: ClosedRange<Double>,
        size: CGFloat
    ) -> CGFloat {
        let lowerLog = log10(range.lowerBound)
        let upperLog = log10(range.upperBound)
        let valueLog = log10(max(value, range.lowerBound))
        let progress = (valueLog - lowerLog) / max(upperLog - lowerLog, 0.000_001)
        return CGFloat(progress) * size
    }

    private var graphAccessibilityLabel: String {
        switch graph.kind {
        case .formula:
            return "Reciprocity formula graph"
        case .table:
            return "Reciprocity reference table graph"
        }
    }

    private var graphAccessibilityValue: String {
        let sourceDescription: String
        switch graph.kind {
        case .formula:
            sourceDescription = "Shows formula curve and current point"
        case .table:
            sourceDescription = "Shows neutral reference anchors and current point"
        }

        let pointDescription = graph.currentPoint.map {
            switch $0.style {
            case .exact:
                return "Current point exact"
            case .estimated:
                return "Current point estimated"
            case .extrapolated:
                return "Current point extrapolated"
            case .formulaDerived:
                return "Current point on formula curve"
            }
        } ?? (graph.usesCurrentInputGuideOnly ? "Current input shown as x position only" : "No current point")

        return "\(graph.caption). \(sourceDescription). \(pointDescription)."
    }

    private var graphLegendItems: [(symbol: String, color: Color, text: String)] {
        switch graph.kind {
        case .formula:
            if graph.usesCurrentInputGuideOnly {
                return [
                    ("line.horizontal.3", .accentColor, "Formula curve"),
                    ("line.diagonal", .red, "Current input")
                ]
            }
            return [
                ("line.horizontal.3", .accentColor, "Formula curve"),
                ("circle.fill", .accentColor, "Current point")
            ]
        case .table:
            var items: [(symbol: String, color: Color, text: String)] = [
                ("circle", .secondary, "Reference")
            ]

            if graph.usesCurrentInputGuideOnly {
                items.append(("square.fill", .green.opacity(0.5), "Range limit"))
                items.append(("line.diagonal", .red, "Current input"))
                return items
            }

            if let currentPoint = graph.currentPoint {
                items.append(currentPointLegendItem(for: currentPoint.style))
            }

            return items
        }
    }

    private func currentPointLegendItem(
        for style: FilmModeDetailsGraphCurrentPointStyle
    ) -> (symbol: String, color: Color, text: String) {
        switch style {
        case .exact:
            return ("circle.fill", .green, "Exact")
        case .estimated:
            return ("diamond.fill", .blue, "Estimated")
        case .extrapolated:
            return ("triangle.fill", .orange, "Extrapolated")
        case .formulaDerived:
            return ("circle.fill", .accentColor, "Current point")
        }
    }

    private var graphExplanationSymbol: String {
        if graph.usesCurrentInputGuideOnly {
            return "info.circle"
        }

        switch graph.currentPoint?.style {
        case .exact:
            return "checkmark.circle"
        case .estimated:
            return "slider.horizontal.below.square.and.square.filled"
        case .extrapolated:
            return "arrow.up.forward.circle"
        case .formulaDerived:
            return "function"
        case .none:
            return "info.circle"
        }
    }

    private var graphExplanationTint: Color {
        if graph.usesCurrentInputGuideOnly {
            return .orange
        }

        switch graph.currentPoint?.style {
        case .exact:
            return .green
        case .estimated, .formulaDerived:
            return .blue
        case .extrapolated:
            return .orange
        case .none:
            return .secondary
        }
    }

    private var graphExplanationText: String {
        if let unsupportedExplanation = graph.unsupportedExplanation {
            return unsupportedExplanation
        }

        return graph.caption
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
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
    @Binding var ndStop: Int
    let onContinuousSelectionChange: (Int) -> Void
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

            Picker("ND Filter", selection: $ndStop) {
                ForEach(0...30, id: \.self) { stop in
                    NDStopPickerValue(
                        valueText: "\(stop)",
                        style: style,
                        layout: layout
                    )
                    .tag(stop)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: pickerHeight)
            .clipped()
            .background {
                WheelPickerContinuousObserver(
                    onSelectedRowChange: { row in
                        guard (0...30).contains(row) else {
                            return
                        }

                        onContinuousSelectionChange(row)
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

private struct WheelPickerContinuousObserver: UIViewRepresentable {
    let onSelectedRowChange: (Int) -> Void
    let onInteractionEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSelectedRowChange: onSelectedRowChange,
            onInteractionEnd: onInteractionEnd
        )
    }

    func makeUIView(context: Context) -> ObservationView {
        let view = ObservationView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onMoveOrLayout = { observedView in
            context.coordinator.attachIfNeeded(from: observedView)
        }
        return view
    }

    func updateUIView(_ uiView: ObservationView, context: Context) {
        context.coordinator.onSelectedRowChange = onSelectedRowChange
        context.coordinator.onInteractionEnd = onInteractionEnd
        context.coordinator.attachIfNeeded(from: uiView)
    }

    static func dismantleUIView(_ uiView: ObservationView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        var onSelectedRowChange: (Int) -> Void
        var onInteractionEnd: () -> Void

        private weak var pickerView: UIPickerView?
        private weak var panGestureRecognizer: UIPanGestureRecognizer?
        private var displayLink: CADisplayLink?
        private var lastObservedRow: Int?

        init(
            onSelectedRowChange: @escaping (Int) -> Void,
            onInteractionEnd: @escaping () -> Void
        ) {
            self.onSelectedRowChange = onSelectedRowChange
            self.onInteractionEnd = onInteractionEnd
        }

        func attachIfNeeded(from observedView: UIView) {
            guard let picker = locatePicker(near: observedView) else {
                DispatchQueue.main.async { [weak self, weak observedView] in
                    guard let self, let observedView else {
                        return
                    }

                    self.attachIfNeeded(from: observedView)
                }
                return
            }

            if picker !== pickerView {
                detachPanObservation()
                pickerView = picker
                lastObservedRow = nil
                attachPanObservation(to: picker)
            }

            startDisplayLinkIfNeeded()
            emitSelectionIfNeeded()
        }

        func detach() {
            displayLink?.invalidate()
            displayLink = nil
            detachPanObservation()
            pickerView = nil
            lastObservedRow = nil
        }

        private func startDisplayLinkIfNeeded() {
            guard displayLink == nil else {
                return
            }

            let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLinkTick))
            displayLink.preferredFramesPerSecond = 30
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }

        private func attachPanObservation(to picker: UIPickerView) {
            guard let panGestureRecognizer = picker.gestureRecognizers?
                .compactMap({ $0 as? UIPanGestureRecognizer })
                .first else {
                return
            }

            panGestureRecognizer.addTarget(self, action: #selector(handlePanGestureChange(_:)))
            self.panGestureRecognizer = panGestureRecognizer
        }

        private func detachPanObservation() {
            panGestureRecognizer?.removeTarget(self, action: #selector(handlePanGestureChange(_:)))
            panGestureRecognizer = nil
        }

        private func emitSelectionIfNeeded() {
            guard let pickerView else {
                return
            }

            let selectedRow = pickerView.selectedRow(inComponent: 0)
            guard selectedRow >= 0, selectedRow != lastObservedRow else {
                return
            }

            lastObservedRow = selectedRow
            onSelectedRowChange(selectedRow)
        }

        private func locatePicker(near observedView: UIView) -> UIPickerView? {
            var ancestor: UIView? = observedView

            while let currentAncestor = ancestor {
                let pickers = pickerViews(in: currentAncestor)
                if let matchedPicker = bestMatch(
                    in: pickers,
                    ancestor: currentAncestor,
                    observedView: observedView
                ) {
                    return matchedPicker
                }

                ancestor = currentAncestor.superview
            }

            return nil
        }

        private func pickerViews(in root: UIView) -> [UIPickerView] {
            var result: [UIPickerView] = []

            if let picker = root as? UIPickerView {
                result.append(picker)
            }

            for subview in root.subviews {
                result.append(contentsOf: pickerViews(in: subview))
            }

            return result
        }

        private func bestMatch(
            in pickers: [UIPickerView],
            ancestor: UIView,
            observedView: UIView
        ) -> UIPickerView? {
            let targetPoint = observedView.convert(
                CGPoint(x: observedView.bounds.midX, y: observedView.bounds.midY),
                to: ancestor
            )

            let matches = pickers.filter { picker in
                picker.convert(picker.bounds, to: ancestor).contains(targetPoint)
            }

            if let exactMatch = matches.min(by: { lhs, rhs in
                let lhsArea = pickerArea(lhs, in: ancestor)
                let rhsArea = pickerArea(rhs, in: ancestor)
                return lhsArea < rhsArea
            }) {
                return exactMatch
            }

            return pickers.min(by: { lhs, rhs in
                distanceSquared(from: lhs, to: targetPoint, in: ancestor)
                    < distanceSquared(from: rhs, to: targetPoint, in: ancestor)
            })
        }

        private func pickerArea(_ picker: UIPickerView, in ancestor: UIView) -> CGFloat {
            let frame = picker.convert(picker.bounds, to: ancestor)
            return frame.width * frame.height
        }

        private func distanceSquared(
            from picker: UIPickerView,
            to targetPoint: CGPoint,
            in ancestor: UIView
        ) -> CGFloat {
            let frame = picker.convert(picker.bounds, to: ancestor)
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let dx = center.x - targetPoint.x
            let dy = center.y - targetPoint.y
            return (dx * dx) + (dy * dy)
        }

        @objc
        private func handleDisplayLinkTick() {
            emitSelectionIfNeeded()
        }

        @objc
        private func handlePanGestureChange(_ gestureRecognizer: UIPanGestureRecognizer) {
            if gestureRecognizer.state == .ended
                || gestureRecognizer.state == .cancelled
                || gestureRecognizer.state == .failed {
                onInteractionEnd()
            }
        }
    }

    final class ObservationView: UIView {
        var onMoveOrLayout: ((UIView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onMoveOrLayout?(self)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            onMoveOrLayout?(self)
        }
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
