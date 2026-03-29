import SwiftUI

struct ExposureCalculatorScreen: View {
    @State private var baseShutterInput = "1/30"
    @State private var ndInput = "ND64"
    @StateObject private var timerManager = TimerManager()

    private let calculator = ExposureCalculator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderView()
                VariableSectionView(
                    baseShutterInput: $baseShutterInput,
                    ndInput: $ndInput
                )
                ResultSectionView(calculationResult: calculationResult)
                TimerActionView(
                    calculationResult: calculationResult,
                    onStart: startTimer
                )
                RunningTimerPanelView(
                    timerState: timerManager.state,
                    formattedDuration: formattedDuration
                )
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError> {
        calculator.calculate(baseShutterInput: baseShutterInput, ndInput: ndInput)
    }

    private func startTimer() {
        guard case .success(let result) = calculationResult else {
            return
        }

        let snapshot = TimerSnapshot(
            name: "ND\(Int(result.ndFactor.rounded())) - \(calculator.formatShutter(result.resultShutterSeconds))",
            totalDuration: result.resultShutterSeconds,
            baseShutterSeconds: result.baseShutterSeconds,
            ndFactor: result.ndFactor,
            resultShutterSeconds: result.resultShutterSeconds
        )

        timerManager.start(snapshot: snapshot)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        calculator.formatShutter(seconds)
    }
}

struct HeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("계산")
                .font(.largeTitle.weight(.bold))

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Mode", selection: .constant(0)) {
                        Text("Digital").tag(0)
                        Text("Film").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .disabled(true)

                    Text("Film mode: placeholder")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                .disabled(true)
            }
        }
        .sectionCardStyle()
    }
}

struct VariableSectionView: View {
    @Binding var baseShutterInput: String
    @Binding var ndInput: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Variable Controls")
                .font(.headline)

            VStack(spacing: 14) {
                ExposureFieldInputRow(
                    title: "Shutter",
                    text: $baseShutterInput,
                    prompt: "1/30 or 2s",
                    detail: "Base shutter reference input"
                )

                Divider()

                ExposureFieldInputRow(
                    title: "ND",
                    text: $ndInput,
                    prompt: "ND64 or 64",
                    detail: "ND filter factor input"
                )

                Divider()

                HStack {
                    Text("고급 옵션 펼치기")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Label("Aperture / ISO", systemImage: "chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Aperture and ISO placeholders will expand here later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .sectionCardStyle()
    }
}

struct ResultSectionView: View {
    let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError>

    private let calculator = ExposureCalculator()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Result Set")
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Final Shutter")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text(primaryResultText)
                        .font(.title3.weight(.semibold))
                }

                Divider()

                ResultPlaceholderRow(label: "Base Shutter", value: baseShutterText)
                ResultPlaceholderRow(label: "ND", value: ndText)
                ResultPlaceholderRow(label: "Status", value: statusText)

                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .sectionCardStyle()
    }

    private var primaryResultText: String {
        switch calculationResult {
        case .success(let result):
            return calculator.formatShutter(result.resultShutterSeconds)
        case .failure:
            return "Result unavailable"
        }
    }

    private var baseShutterText: String {
        switch calculationResult {
        case .success(let result):
            return calculator.formatShutter(result.baseShutterSeconds)
        case .failure:
            return "-"
        }
    }

    private var ndText: String {
        switch calculationResult {
        case .success(let result):
            if abs(result.ndFactor.rounded() - result.ndFactor) < 0.0001 {
                return "ND\(Int(result.ndFactor.rounded()))"
            }

            return "ND\(result.ndFactor)"
        case .failure:
            return "-"
        }
    }

    private var statusText: String {
        switch calculationResult {
        case .success:
            return "Updated instantly"
        case .failure:
            return "Needs valid input"
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

struct TimerActionView: View {
    let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError>
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timer Action")
                .font(.headline)

            Button("Start Timer") {
                onStart()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(!canStartTimer)
        }
        .sectionCardStyle()
    }

    private var canStartTimer: Bool {
        switch calculationResult {
        case .success(let result):
            return result.resultShutterSeconds > 0
        case .failure:
            return false
        }
    }
}

struct RunningTimerPanelView: View {
    let timerState: TimerState
    let formattedDuration: (TimeInterval) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(panelTitle)
                    .font(.headline)

                Spacer()

                Button("보기") {
                }
                .font(.footnote.weight(.semibold))
                .disabled(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let snapshot = timerState.snapshot {
                    Text(snapshot.name)
                        .font(.subheadline.weight(.semibold))

                    ResultPlaceholderRow(
                        label: "Total",
                        value: formattedDuration(timerState.duration)
                    )
                    ResultPlaceholderRow(
                        label: "Elapsed",
                        value: formattedDuration(timerState.elapsedTime)
                    )
                    ResultPlaceholderRow(
                        label: "Remaining",
                        value: formattedDuration(timerState.remainingTime)
                    )
                    ResultPlaceholderRow(
                        label: "Status",
                        value: statusText
                    )
                    ProgressView(value: progressValue)
                        .tint(timerState.status == .completed ? .green : .accentColor)
                } else {
                    Text("No running timers")
                        .font(.subheadline.weight(.semibold))

                    Text("Compact running timer summary cards will appear here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
        timerState.snapshot == nil ? "실행 중 타이머 0개" : "실행 중 타이머 1개"
    }

    private var statusText: String {
        switch timerState.status {
        case .idle:
            return "Idle"
        case .running:
            return "Running"
        case .completed:
            return "Completed"
        }
    }

    private var progressValue: Double {
        guard timerState.duration > 0 else {
            return timerState.status == .completed ? 1 : 0
        }

        return min(max(timerState.elapsedTime / timerState.duration, 0), 1)
    }
}

private struct ExposureFieldInputRow: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Label("Fixed", systemImage: "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                TextField(prompt, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    .font(.body.weight(.medium))

                Spacer()

                HStack(spacing: 8) {
                    Label("Input", systemImage: "slider.horizontal.3")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ResultPlaceholderRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
        }
    }
}

private extension View {
    func sectionCardStyle() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 1)
            )
    }
}
