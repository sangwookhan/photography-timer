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
            viewModel: ExposureCalculatorViewModel(),
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
                    selectedFilmID: viewModel.selectedPresetFilm?.id,
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
                    selectedFilmID: viewModel.selectedPresetFilm?.id,
                    onSelectEntry: { entry in
                        if let film = entry.film {
                            viewModel.selectPresetFilm(film)
                        } else {
                            viewModel.clearSelectedPresetFilm()
                        }

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
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
                    Text(displayState.primaryText)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("film-row-selection")

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
                        formatTimeDisplay: formatTimeDisplay,
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
    let formatTimeDisplay: (TimeInterval) -> TimeDisplay
    let onStartAdjustedShutterTimer: () -> Void
    let onStartCorrectedExposureTimer: () -> Void
    let onShowDetails: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.bodySpacing) {
            FilmModeResultRow(
                title: "Adjusted Shutter",
                display: formatTimeDisplay(resultState.adjustedShutterSeconds),
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

private struct FilmModeDetailsSheet: View {
    let details: FilmModeDetailsDisplayState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(details.sections) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(section.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

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
                                                detailRowText(for: row)
                                                    .foregroundStyle(.tint)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        } else {
                                            detailRowText(for: row)
                                                .foregroundStyle(.primary.opacity(0.9))
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

                        if details.showsGraphPlaceholder && section.title == "Reference" {
                            FilmModeDetailsGraphPlaceholder()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("film-mode-details-sheet-content")
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(details.title)
            .navigationBarTitleDisplayMode(.inline)
        }
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
        case .standard, .referenceBlock:
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
}

private struct FilmModeDetailsGraphPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Graph")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text("Graph area reserved for PTIMER-100")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
                .frame(height: 132)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Graph placeholder")
                .accessibilityValue("Reserved for PTIMER-100")
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

            Text(secondaryText)
                .font(style.correctedExposureSecondaryFont)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .accessibilityIdentifier("film-mode-corrected-exposure-secondary")
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

struct RunningTimerPanelView: View {
    let timers: [RunningTimerItem]
    let runningTimerCount: Int
    let formattedDuration: (TimeInterval) -> String
    let formatTimeDisplay: (TimeInterval) -> TimeDisplay
    let formatClockTime: (Date) -> String
    let formatDateTime: (Date) -> String
    let onPauseTimer: (UUID) -> Void
    let onResumeTimer: (UUID) -> Void
    let onRemoveTimer: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(panelTitle)
                    .font(.headline)

                Spacer()

                Button("View All") {
                }
                    .font(.footnote.weight(.semibold))
                    .disabled(true)
            }

            if timers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.title3)
                        .foregroundStyle(.tertiary)

                    Text("No active timers")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(timers) { timer in
                        TimerSummaryCard(
                            timer: timer,
                            formattedDuration: formattedDuration,
                            formatTimeDisplay: formatTimeDisplay,
                            formatClockTime: formatClockTime,
                            formatDateTime: formatDateTime,
                            onPause: { onPauseTimer(timer.id) },
                            onResume: { onResumeTimer(timer.id) },
                            onRemove: { onRemoveTimer(timer.id) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }

    private var panelTitle: String {
        "Running Timers: \(runningTimerCount)"
    }
}

private struct TimerSummaryCard: View {
    let timer: RunningTimerItem
    let formattedDuration: (TimeInterval) -> String
    let formatTimeDisplay: (TimeInterval) -> TimeDisplay
    let formatClockTime: (Date) -> String
    let formatDateTime: (Date) -> String
    let onPause: () -> Void
    let onResume: () -> Void
    let onRemove: () -> Void

    var body: some View {
        let primaryDisplay = formatTimeDisplay(primaryDuration)
        let targetDisplay = formatTimeDisplay(timer.duration)

        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Timer \(timer.order)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    statusBadge
                }

                VStack(alignment: .leading, spacing: 2) {
                    DurationDisplayBlock(
                        primaryText: primaryDisplay.primary,
                        secondaryText: primaryDisplay.secondary,
                        primaryColor: primaryTimeColor,
                        primaryFont: .system(size: 28, weight: .bold, design: .rounded),
                        secondaryFont: .footnote
                    )
                }

                if let targetContextText = targetContextText(targetDisplay: targetDisplay) {
                    Text(targetContextText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                if let timeContextText {
                    Text(timeContextText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Text(timer.basisSummary)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 10) {
                if timer.status == .running {
                    iconActionButton(
                        systemName: "pause.circle",
                        tint: .orange,
                        accessibilityLabel: "Pause timer",
                        action: onPause
                    )
                }

                if timer.status == .paused {
                    iconActionButton(
                        systemName: "play.circle",
                        tint: .blue,
                        accessibilityLabel: "Resume timer",
                        action: onResume
                    )
                }

                if timer.status != .running {
                    iconActionButton(
                        systemName: "trash",
                        tint: .secondary,
                        accessibilityLabel: "Remove timer",
                        action: onRemove
                    )
                }

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private var primaryDuration: TimeInterval {
        switch timer.status {
        case .running, .paused:
            return timer.remainingTime
        case .completed:
            return timer.duration
        }
    }

    private func targetContextText(targetDisplay: TimeDisplay) -> String? {
        switch timer.status {
        case .running:
            return "\(targetDisplay.primary) · \(targetDisplay.secondary)"
        case .completed:
            return nil
        case .paused:
            return "\(targetDisplay.primary) · \(targetDisplay.secondary)"
        }
    }

    private var timeContextText: String? {
        switch timer.status {
        case .running:
            let completionText = timer.endDate.map(formatDateTime) ?? "--"
            return "Ends \(completionText)"
        case .completed:
            let completionText = timer.completedAt.map(formatDateTime) ?? "--"
            return "Completed \(completionText)"
        case .paused:
            let pausedText = timer.pausedAt.map(formatDateTime) ?? "--"
            return "Paused \(pausedText)"
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: statusSymbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(statusColor)

            Text(statusText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private func iconActionButton(
        systemName: String,
        tint: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .background(
            Circle()
                .fill(tint.opacity(0.12))
        )
        .accessibilityLabel(accessibilityLabel)
    }

    private var statusText: String {
        switch timer.status {
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .completed:
            return "Completed"
        }
    }

    private var statusSymbol: String {
        switch timer.status {
        case .running:
            return "circle.fill"
        case .paused:
            return "square.fill"
        case .completed:
            return "checkmark"
        }
    }

    private var statusColor: Color {
        switch timer.status {
        case .running:
            return .green
        case .paused:
            return .orange
        case .completed:
            return .gray
        }
    }

    private var primaryTimeColor: Color {
        switch timer.status {
        case .running:
            return .primary
        case .paused:
            return .orange
        case .completed:
            return .secondary
        }
    }

    private var cardBackgroundColor: Color {
        switch timer.status {
        case .running:
            return Color(.secondarySystemBackground)
        case .paused:
            return Color(.systemGray6)
        case .completed:
            return Color(.tertiarySystemBackground)
        }
    }

    private var borderColor: Color {
        switch timer.status {
        case .running:
            return .green.opacity(0.18)
        case .paused:
            return .orange.opacity(0.18)
        case .completed:
            return .gray.opacity(0.18)
        }
    }
}

private struct DurationDisplayBlock: View {
    let primaryText: String
    let secondaryText: String
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

            Text(secondaryText)
                .font(secondaryFont)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
