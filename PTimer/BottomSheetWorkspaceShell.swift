import SwiftUI

struct BottomSheetWorkspaceShell: View {
    @ObservedObject var stateStore: BottomSheetWorkspaceStateStore
    let snapshot: BottomSheetWorkspaceSnapshot

    var body: some View {
        BottomSheetContainer(
            detent: stateStore.detent,
            onExpand: stateStore.expand,
            onCollapse: stateStore.collapse,
            onDragEnded: stateStore.handleDragEnd(translation:),
            content: {
                BottomSheetContentHost(
                    detent: stateStore.detent,
                    snapshot: snapshot,
                    onExpand: stateStore.expand,
                    onCollapse: stateStore.collapse
                )
            }
        )
    }
}

enum BottomSheetDetent: String, CaseIterable, Identifiable {
    case compact
    case medium
    case large

    static let `default`: BottomSheetDetent = .compact

    var id: String { rawValue }

    var isExpanded: Bool {
        self != .compact
    }
}

@MainActor
final class BottomSheetWorkspaceStateStore: ObservableObject {
    @Published private(set) var detent: BottomSheetDetent

    init(detent: BottomSheetDetent = .default) {
        self.detent = detent
    }

    var isExpanded: Bool {
        detent.isExpanded
    }

    func transition(to detent: BottomSheetDetent) {
        self.detent = detent
    }

    func expand() {
        detent = .large
    }

    func collapse() {
        detent = .compact
    }

    func handleDragEnd(translation: CGFloat) {
        if translation < -56 {
            expand()
        } else if translation > 56 {
            collapse()
        }
    }
}

struct BottomSheetLayoutMetrics {
    static func height(for detent: BottomSheetDetent) -> CGFloat {
        switch detent {
        case .compact:
            return 160
        case .medium:
            return 288
        case .large:
            return 440
        }
    }

    static func dimOpacity(for detent: BottomSheetDetent) -> Double {
        switch detent {
        case .compact:
            return 0
        case .medium:
            return 0.12
        case .large:
            return 0.2
        }
    }
}

struct BottomSheetWorkspaceSnapshot: Equatable {
    let totalCount: Int
    let runningCount: Int
    let stoppedCount: Int
    let completedCount: Int

    static func make(from timers: [RunningTimerItem]) -> BottomSheetWorkspaceSnapshot {
        BottomSheetWorkspaceSnapshot(
            totalCount: timers.count,
            runningCount: timers.filter { $0.status == .running }.count,
            stoppedCount: timers.filter { $0.status == .stopped }.count,
            completedCount: timers.filter { $0.status == .completed }.count
        )
    }

    var summaryText: String {
        "Running \(runningCount) · Stopped \(stoppedCount) · Completed \(completedCount)"
    }

    var compactPrompt: String {
        totalCount == 0 ? "No active timers yet" : "Open workspace to manage timers"
    }
}

private struct BottomSheetContainer<Content: View>: View {
    let detent: BottomSheetDetent
    let onExpand: () -> Void
    let onCollapse: () -> Void
    let onDragEnded: (CGFloat) -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Capsule()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity)

                if detent.isExpanded {
                    Button {
                        onCollapse()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 34, height: 34)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("bottom-sheet-collapse-button")
                }
            }
            .padding(.top, 10)
            .padding(.bottom, detent.isExpanded ? 10 : 14)
            .padding(.horizontal, 18)
            .contentShape(Rectangle())
            .onTapGesture {
                if !detent.isExpanded {
                    onExpand()
                }
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .frame(height: BottomSheetLayoutMetrics.height(for: detent))
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(detent.isExpanded ? 0.45 : 0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(detent.isExpanded ? 0.22 : 0.12), radius: detent.isExpanded ? 30 : 18, x: 0, y: -6)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 0)
        .offset(y: detent == .medium ? -8 : 0)
        .accessibilityIdentifier("bottom-sheet-shell")
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: detent)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    onDragEnded(value.translation.height)
                }
        )
    }
}

private struct BottomSheetContentHost: View {
    let detent: BottomSheetDetent
    let snapshot: BottomSheetWorkspaceSnapshot
    let onExpand: () -> Void
    let onCollapse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: detent.isExpanded ? 16 : 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Timer Workspace")
                        .font(.headline)

                    Text(snapshot.summaryText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if detent == .compact {
                    Button("Open") {
                        onExpand()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("bottom-sheet-expand-button")
                }
            }

            Group {
                switch detent {
                case .compact:
                    CompactBottomSheetPlaceholder(
                        snapshot: snapshot,
                        onExpand: onExpand
                    )
                case .medium, .large:
                    ExpandedBottomSheetPlaceholder(
                        snapshot: snapshot,
                        onCollapse: onCollapse
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CompactBottomSheetPlaceholder: View {
    let snapshot: BottomSheetWorkspaceSnapshot
    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PlaceholderMetricCard(title: "Quick Summary", detail: snapshot.compactPrompt)
            Button {
                onExpand()
            } label: {
                PlaceholderMetricCard(
                    title: "Workspace",
                    detail: "Expand for timer management"
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ExpandedBottomSheetPlaceholder: View {
    let snapshot: BottomSheetWorkspaceSnapshot
    let onCollapse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlaceholderBand(label: "Summary Zone", value: "PTIMER-47 summary content mounts here")
            PlaceholderBand(label: "List Zone", value: "Expanded timer list shell is reserved for PTIMER-47 and PTIMER-48")
            PlaceholderBand(label: "Return Path", value: "Drag down, use the chevron, or tap the dimmed background to collapse")

            HStack(spacing: 10) {
                SmallWorkspaceTag(text: "Expanded workspace")
                SmallWorkspaceTag(text: snapshot.summaryText)
            }

            Spacer(minLength: 0)

            Button("Back to Calculator") {
                onCollapse()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }
}

private struct SmallWorkspaceTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
    }
}

private struct PlaceholderMetricCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(detail)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct PlaceholderBand: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
