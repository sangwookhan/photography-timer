import SwiftUI

struct ExposureCalculatorScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HeaderView()
                VariableSectionView()
                ResultSectionView()
                TimerActionView()
                RunningTimerPanelView()
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
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
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Variable Controls")
                .font(.headline)

            VStack(spacing: 14) {
                ExposureFieldPlaceholderRow(
                    title: "Shutter",
                    value: "1/30s",
                    detail: "Preset or manual input placeholder",
                    roleLabel: "Fixed",
                    roleSystemImage: "lock.fill"
                )

                Divider()

                ExposureFieldPlaceholderRow(
                    title: "ND",
                    value: "ND64",
                    detail: "Preset or manual input placeholder",
                    roleLabel: "Fixed",
                    roleSystemImage: "lock.fill"
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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Result Set")
                .font(.headline)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Final Shutter")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text("Result will appear here")
                        .font(.title3.weight(.semibold))
                }

                Divider()

                ResultPlaceholderRow(label: "Aperture", value: "Placeholder")
                ResultPlaceholderRow(label: "ISO", value: "Placeholder")
                ResultPlaceholderRow(label: "ND", value: "Placeholder")
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .sectionCardStyle()
    }
}

struct TimerActionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timer Action")
                .font(.headline)

            Button("Start Timer") {
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(true)
        }
        .sectionCardStyle()
    }
}

struct RunningTimerPanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("실행 중 타이머 0개")
                    .font(.headline)

                Spacer()

                Button("보기") {
                }
                .font(.footnote.weight(.semibold))
                .disabled(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("No running timers")
                    .font(.subheadline.weight(.semibold))

                Text("Compact running timer summary cards will appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
}

private struct ExposureFieldPlaceholderRow: View {
    let title: String
    let value: String
    let detail: String
    let roleLabel: String
    let roleSystemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Label(roleLabel, systemImage: roleSystemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                Text(value)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                HStack(spacing: 8) {
                    Label("Preset", systemImage: "list.bullet")
                    Image(systemName: "chevron.right")
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
