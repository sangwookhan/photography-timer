import SwiftUI
import UIKit

struct ExposureCalculatorScreen: View {
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
            timeContext: viewModel.timerTimeContext
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
            let compactReservedHeight = Self.calculatorReservedHeight(
                screenHeight: geometry.size.height,
                topSafeArea: geometry.safeAreaInsets.top,
                bottomSafeArea: geometry.safeAreaInsets.bottom
            )

            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ExposureWorkspaceMainContent(
                    style: layoutStyle(for: compactReservedHeight),
                    viewModel: viewModel,
                    availableHeight: compactReservedHeight
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
                    onStopTimer: viewModel.stopTimer,
                    onResumeTimer: viewModel.resumeTimer,
                    onRemoveTimer: viewModel.removeTimer,
                    onClearCompletedTimers: viewModel.clearCompletedTimers
                )
                .padding(.bottom, geometry.safeAreaInsets.bottom)
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(style: style)
            VariableSectionView(
                baseShutter: $viewModel.baseShutter,
                ndStop: $viewModel.ndStop,
                shutterSpeeds: ExposureCalculatorViewModel.shutterSpeeds,
                formatShutter: viewModel.formatShutter,
                onContinuousBaseShutterChange: viewModel.updateLiveBaseShutter,
                onContinuousNDStopChange: viewModel.updateLiveNDStop,
                onBaseShutterInteractionEnd: viewModel.clearLiveBaseShutterPreview,
                onNDStopInteractionEnd: viewModel.clearLiveNDStopPreview,
                style: style
            )

            Spacer(minLength: style.resultFlowSpacerMinLength)

            ResultSectionView(
                calculationResult: viewModel.calculationResult,
                formatTimeDisplay: viewModel.formatTimeDisplay,
                canStartTimer: viewModel.canStartTimer,
                onStartTimer: viewModel.startTimer,
                style: style
            )

            Color.clear
                .frame(height: style.workspaceSeparation)
                .accessibilityHidden(true)
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
            - BottomSheetLayoutMetrics.height(for: bottomSheetDetent)
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
    let style: ExposureWorkspaceMainLayoutStyle

    // The segmented control stays visible to preserve the accepted header shape
    // while calculator mode remains intentionally fixed to the current variant.
    private let fixedModeSelection = 0

    var body: some View {
        VStack(alignment: .leading, spacing: style.headerContentSpacing) {
            Text("Exposure")
                .font(style.headerTitleFont)

            Picker("Mode", selection: .constant(fixedModeSelection)) {
                Text("Digital").tag(0)
                Text("Film").tag(1)
            }
            .pickerStyle(.segmented)
            .disabled(true)
            .accessibilityHint("Mode selection is not available in this layout")
        }
        .sectionCardStyle(style: style)
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
    let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError>
    let formatTimeDisplay: (TimeInterval) -> TimeDisplay
    let canStartTimer: Bool
    let onStartTimer: () -> Void
    let style: ExposureWorkspaceMainLayoutStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style.bodySpacing) {
            VStack(alignment: .leading, spacing: style.resultTopSpacerMinLength) {
                if case .success(let result) = calculationResult {
                    let display = formatTimeDisplay(result.resultShutterSeconds)
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
                            style: style
                        )
                    }
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
        .accessibilityLabel("Start Timer")
        .accessibilityHint("Starts a timer using the calculated result")
        .accessibilityIdentifier("start-timer-button")
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
    let onStopTimer: (UUID) -> Void
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
                            onStop: { onStopTimer(timer.id) },
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
    let onStop: () -> Void
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
                        accessibilityLabel: "Stop timer",
                        action: onStop
                    )
                }

                if timer.status == .stopped {
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
        case .running, .stopped:
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
        case .stopped:
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
        case .stopped:
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
        case .stopped:
            return "Stopped"
        case .completed:
            return "Completed"
        }
    }

    private var statusSymbol: String {
        switch timer.status {
        case .running:
            return "circle.fill"
        case .stopped:
            return "square.fill"
        case .completed:
            return "checkmark"
        }
    }

    private var statusColor: Color {
        switch timer.status {
        case .running:
            return .green
        case .stopped:
            return .orange
        case .completed:
            return .gray
        }
    }

    private var primaryTimeColor: Color {
        switch timer.status {
        case .running:
            return .primary
        case .stopped:
            return .orange
        case .completed:
            return .secondary
        }
    }

    private var cardBackgroundColor: Color {
        switch timer.status {
        case .running:
            return Color(.secondarySystemBackground)
        case .stopped:
            return Color(.systemGray6)
        case .completed:
            return Color(.tertiarySystemBackground)
        }
    }

    private var borderColor: Color {
        switch timer.status {
        case .running:
            return .green.opacity(0.18)
        case .stopped:
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
