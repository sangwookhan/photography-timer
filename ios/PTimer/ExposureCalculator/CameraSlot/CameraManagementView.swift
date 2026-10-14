// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UIKit
import PTimerKit

/// Camera management: add, rename, show/hide, reorder, delete, and
/// multi-select hide/delete over the managed camera list. Holds no
/// camera state — every action forwards to the ViewModel facade.
struct CameraManagementView: View {
    @ObservedObject var viewModel: ExposureCalculatorViewModel
    let onDismiss: () -> Void

    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<CameraSlotID>()
    @State private var renamingSlotID: CameraSlotID?
    @State private var pendingDelete: Set<CameraSlotID>?
    /// Assistive-technology focus after a list change: the resulting
    /// active camera's row, or the status row when none is active.
    @AccessibilityFocusState private var focus: CameraAccessibilityFocusTarget?
    @State private var focusRequest: CameraFocusRequest?
    /// Edit mode only: the one-shot request whose target row posts a UIKit
    /// focus move, because SwiftUI focus state does not reach edit-mode cells.
    @State private var editModeFocus = CameraFocusLatch()

    private var cameras: [CameraListEntry] { viewModel.cameraList }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                if viewModel.activeCameraSlotID == nil {
                    Text("No cameras shown")
                        .foregroundStyle(.secondary)
                        .accessibilityFocused($focus, equals: .emptyState)
                        .background(CellFocusAnchor(requestID: editModeFocus.requestID(for: .emptyState), consume: consumeEditModeFocus))
                        .accessibilityIdentifier("camera-management-empty-status")
                }
                Section {
                    ForEach(Array(cameras.enumerated()), id: \.element.id) { index, camera in
                        row(for: camera, index: index)
                            .tag(camera.id)
                    }
                    .onMove { source, destination in
                        viewModel.moveCameras(fromOffsets: source, toOffset: destination)
                    }
                }
            }
            .overlay {
                if cameras.isEmpty {
                    Text("No cameras. Add a camera to start shooting.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("Cameras")
            .navigationBarTitleDisplayMode(.inline)
            // Edit mode removes the leading close action and the interactive
            // sheet dismissal; Done only leaves edit mode (CAMERA-PAGER-008).
            .interactiveDismissDisabled(editMode.isEditing)
            .toolbar {
                // The title stays centered and visible in normal and edit
                // mode; without a leading item the system title drifts
                // and can read as missing next to Done.
                ToolbarItem(placement: .principal) {
                    Text("Cameras")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("camera-management-title")
                }
                if !editMode.isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCloseButton(action: onDismiss)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        selection.removeAll()
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                    // Standard toolbar appearance, like the app's other
                    // sheets; Done uses the emphasized weight
                    // (CAMERA-PAGER-009, CAMERA-PAGER-012).
                    .fontWeight(editMode.isEditing ? .semibold : nil)
                    .disabled(cameras.isEmpty && !editMode.isEditing)
                    .accessibilityIdentifier("camera-management-edit-button")
                }
            }
            .safeAreaInset(edge: .bottom) { bottomActions }
        }
        .task(id: focusRequest?.id) { await applyFocusRequest() }
        .sheet(item: $renamingSlotID) { slotID in
            CameraSlotRenameSheet(
                slotID: slotID,
                initialName: viewModel.cameraSlotIdentity(for: slotID)?.displayName ?? "",
                onSave: { viewModel.renameCamera(slotID, to: $0) }
            )
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let ids = pendingDelete {
                    performEdit(isDeletion: true) { viewModel.deleteCameras(ids) }
                    selection.subtract(ids)
                }
                pendingDelete = nil
            }
            .accessibilityIdentifier("camera-management-confirm-delete-button")
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            deleteMessage
        }
    }

    // MARK: - Bottom actions

    /// A visibly labelled bottom action area (CAMERA-PAGER-008): `Add camera`
    /// in normal mode; side-by-side `Hide` and `Delete` in edit mode. A
    /// toolbar bottom bar would render the label icon-only.
    private var bottomActions: some View {
        HStack(spacing: 12) {
            if editMode.isEditing {
                Button {
                    performEdit { viewModel.hideCameras(selection) }
                    selection.removeAll()
                } label: {
                    Text("Hide").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(selection.isEmpty)
                .accessibilityIdentifier("camera-management-bulk-hide-button")
                Button(role: .destructive) {
                    pendingDelete = selection
                } label: {
                    Text("Delete").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(selection.isEmpty)
                .accessibilityIdentifier("camera-management-bulk-delete-button")
            } else {
                Button {
                    performEdit { _ = viewModel.addCamera() }
                } label: {
                    // Only the plus uses the accent color; the label keeps
                    // the standard text color. The label height brings the
                    // visible button to 44-48 pt.
                    Label {
                        Text("Add camera").foregroundStyle(Color.primary)
                    } icon: {
                        Image(systemName: "plus").foregroundStyle(Color.accentColor)
                    }
                    .frame(maxWidth: .infinity, minHeight: 45)
                    .contentShape(Capsule())
                }
                // Bordered without a fill: an explicit solid stroke reaches
                // 3:1 against the bar, and no opacity reduction is used, so
                // the button does not look disabled (CAMERA-PAGER-012).
                .buttonStyle(.plain)
                .overlay(Capsule().stroke(Color.addCameraBorder, lineWidth: 1.5))
                .accessibilityIdentifier("camera-management-add-button")
            }
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for camera: CameraListEntry, index: Int) -> some View {
        HStack(spacing: 12) {
            Button {
                if !editMode.isEditing {
                    renamingSlotID = camera.id
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    // Wraps instead of truncating so long names stay
                    // readable at accessibility Dynamic Type sizes.
                    Text(camera.name)
                        .foregroundStyle(camera.isDisplayed ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // Position and state stay visible so cameras with the
                    // same name remain distinguishable (CAMERA-NAME-003).
                    Text("\(index + 1) of \(cameras.count) · \(stateLabel(camera))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if !editMode.isEditing {
                Button {
                    performEdit { viewModel.setCameraDisplayed(!camera.isDisplayed, for: camera.id) }
                } label: {
                    Image(systemName: camera.isDisplayed ? "eye" : "eye.slash")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(camera.isDisplayed ? Text("Hide camera") : Text("Show camera"))
                .accessibilityIdentifier("camera-management-visibility-\(index)")
            }
        }
        .contentShape(Rectangle())
        .background(CellFocusAnchor(requestID: editModeFocus.requestID(for: .camera(camera.id)), consume: consumeEditModeFocus))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = [camera.id]
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel(camera, index: index))
        .accessibilityAction(named: Text(camera.isDisplayed ? "Hide camera" : "Show camera")) {
            performEdit { viewModel.setCameraDisplayed(!camera.isDisplayed, for: camera.id) }
        }
        .accessibilityAction(named: Text("Rename camera")) {
            renamingSlotID = camera.id
        }
        .accessibilityActions {
            // Reordering and its non-drag alternatives belong to edit
            // mode (CAMERA-PAGER-006/008).
            if editMode.isEditing {
                Button("Move up") { move(camera.id, by: -1) }
                Button("Move down") { move(camera.id, by: 1) }
            }
        }
        .accessibilityAction(named: Text("Delete camera")) {
            pendingDelete = [camera.id]
        }
        .accessibilityFocused($focus, equals: .camera(camera.id))
        .accessibilityIdentifier("camera-management-row-\(index)")
    }

    private func stateLabel(_ camera: CameraListEntry) -> String {
        camera.isDisplayed ? String(localized: "Shown") : String(localized: "Hidden")
    }

    private func rowAccessibilityLabel(_ camera: CameraListEntry, index: Int) -> Text {
        return Text("\(camera.name), \(stateLabel(camera)), \(index + 1) of \(cameras.count)")
    }

    // MARK: - Delete confirmation

    private var deleteTitle: LocalizedStringKey {
        (pendingDelete?.count ?? 0) > 1 ? "Delete cameras?" : "Delete camera?"
    }

    private var deleteMessage: Text {
        let ids = pendingDelete ?? []
        if ids.count > 1 {
            return Text("Deletes \(ids.count) cameras and their calculator settings. This cannot be undone.")
        }
        let name = ids.first.flatMap { viewModel.cameraSlotIdentity(for: $0)?.displayName } ?? ""
        return Text("Deletes \(name) and its calculator settings. A new camera with the same name will not reconnect them or this camera's timers. This cannot be undone.")
    }

    /// Non-drag reorder; announces the camera's resulting position.
    private func move(_ slotID: CameraSlotID, by delta: Int) {
        viewModel.moveCamera(slotID, by: delta)
        guard let position = viewModel.cameraList.firstIndex(where: { $0.id == slotID }) else {
            return
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: String(localized: "Moved to position \(position + 1) of \(viewModel.cameraList.count)")
        )
    }

    /// Runs a list edit and, after a confirmed deletion or an active-camera
    /// change, announces and focuses the result. A plain hide or show of
    /// another camera leaves VoiceOver on the row it just operated
    /// (CAMERA-PAGER-006).
    private func performEdit(isDeletion: Bool = false, _ edit: () -> Void) {
        let activeBefore = viewModel.activeCameraSlotID
        edit()
        if isDeletion || viewModel.activeCameraSlotID != activeBefore {
            announceResultingCamera()
        }
    }

    /// Tells VoiceOver which camera is now active, or that the pager is
    /// empty, and moves focus to that camera's row or to the empty-state
    /// status (CAMERA-PAGER-006).
    private func announceResultingCamera() {
        let message: String
        if let active = viewModel.activeCameraSlot {
            message = String(localized: "Active camera: \(active.displayName)")
        } else {
            message = String(localized: "No cameras shown")
        }
        focusRequest = CameraFocusRequest(
            target: viewModel.accessibilityFocusTarget,
            message: message
        )
    }

    /// Moves focus and announces once the edit, the dismissing
    /// confirmation, and the list's own focus restoration have settled.
    /// Edit mode needs the wait: the dialog's dismissal otherwise returns
    /// focus to the bulk Delete button after the move.
    private func applyFocusRequest() async {
        guard let request = focusRequest else { return }
        while !request.isReady(isConfirmationPresented: pendingDelete != nil) {
            guard await pause(nanoseconds: 50_000_000) else { return }
        }
        guard await pause(nanoseconds: 600_000_000) else { return }
        focus = nil
        await Task.yield()
        if editMode.isEditing {
            editModeFocus.arm(id: request.id, target: request.target)
            guard await pause(nanoseconds: 100_000_000) else { return }
            // An unclaimed request expires here, so a row created later
            // cannot fire it.
            editModeFocus.consume(request.id)
        } else {
            focus = request.target
        }
        UIAccessibility.post(notification: .announcement, argument: request.message)
        if focusRequest?.id == request.id {
            focusRequest = nil
        }
    }

    /// Sleeps; returns `false` when the task was cancelled (view teardown
    /// or a newer request), so the caller stops instead of spinning.
    private func pause(nanoseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
        } catch {
            return false
        }
        return !Task.isCancelled
    }

    private func consumeEditModeFocus(_ id: UUID) -> Bool {
        editModeFocus.consume(id)
    }
}

/// Posts a VoiceOver focus move to the list cell hosting this view when
/// `requestID` changes to a new value.
private struct CellFocusAnchor: UIViewRepresentable {
    let requestID: UUID?
    /// Claims the request; only the first claimant may post the focus move.
    let consume: (UUID) -> Bool

    final class Coordinator { var last: UUID? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard let id = requestID, context.coordinator.last != id else { return }
        context.coordinator.last = id
        DispatchQueue.main.async {
            guard consume(id) else { return }
            var node: UIView? = view
            while let current = node, !(current is UICollectionViewCell || current is UITableViewCell) {
                node = current.superview
            }
            if let cell = node {
                UIAccessibility.post(notification: .layoutChanged, argument: cell)
            }
        }
    }
}

extension Color {
    /// Solid border of the camera-management `Add camera` button; the
    /// separator color is too faint to reach 3:1 against the bar.
    fileprivate static let addCameraBorder = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.60, alpha: 1) : UIColor(white: 0.45, alpha: 1)
    })
}

/// `Add camera`, shared by the utility page and the empty state.
private struct AddCameraButton: View {
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Add camera", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier(identifier)
    }
}

/// `Manage cameras` then `Add camera`, side by side while they fit and
/// stacked in the same order at accessibility Dynamic Type sizes.
private struct PagerMessageActions: View {
    let manageIdentifier: String
    let addIdentifier: String
    let onManageCameras: () -> Void
    let onAddCamera: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { buttons }
            VStack(spacing: 12) { buttons }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Manage cameras", action: onManageCameras)
            .buttonStyle(.bordered)
            .lineLimit(1)
            .accessibilityIdentifier(manageIdentifier)
        AddCameraButton(identifier: addIdentifier, action: onAddCamera)
            .lineLimit(1)
    }
}

/// Centers a pager message and lets it scroll when accessibility text
/// sizes make it taller than the page, instead of truncating it.
private struct PagerMessageLayout<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// The pager's trailing utility page (CAMERA-PAGER-007): not a camera, so
/// it changes no camera, calculator, or timer state. On arrival
/// accessibility identifies it as `Camera management`.
struct CameraManagementUtilityPage: View {
    let isShowing: Bool
    let onManageCameras: () -> Void
    let onAddCamera: () -> Void

    @AccessibilityFocusState private var isTitleFocused: Bool

    var body: some View {
        PagerMessageLayout {
            VStack(spacing: 16) {
                Image(systemName: "camera.on.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Camera management")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isTitleFocused)
                Text("Manage existing cameras or add a new one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                PagerMessageActions(
                    manageIdentifier: "utility-page-manage-cameras-button",
                    addIdentifier: "utility-page-add-camera-button",
                    onManageCameras: onManageCameras,
                    onAddCamera: onAddCamera
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Camera management"))
        .accessibilityIdentifier("camera-utility-page")
        .onChange(of: isShowing) { _, showing in
            if showing {
                DispatchQueue.main.async { isTitleFocused = true }
            }
        }
    }
}

/// Shown in place of the pager when no camera is displayed
/// (CAMERA-PAGER-004). Existing timers stay available in the timer
/// strip below; a calculator-bound timer needs a displayed camera.
struct EmptyCameraPagerView: View {
    let onManageCameras: () -> Void
    let onAddCamera: () -> Void

    /// VoiceOver lands on the message when the empty state appears
    /// (CAMERA-PAGER-006).
    @AccessibilityFocusState private var isMessageFocused: Bool

    var body: some View {
        PagerMessageLayout {
            VStack(spacing: 16) {
                Image(systemName: "camera")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("No cameras shown")
                    .font(.headline)
                    .accessibilityFocused($isMessageFocused)
                Text("Show or add a camera to calculate exposures. Running timers are not affected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                PagerMessageActions(
                    manageIdentifier: "empty-pager-manage-cameras-button",
                    addIdentifier: "empty-pager-add-camera-button",
                    onManageCameras: onManageCameras,
                    onAddCamera: onAddCamera
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("empty-camera-pager")
        .onAppear {
            DispatchQueue.main.async { isMessageFocused = true }
        }
    }
}

/// Shown in place of the pager while camera data could not be read
/// (CAMERA-PERSIST-004): no camera surface, no camera actions, and the same
/// explanation on both platforms. Timers stay available below.
struct CameraDataUnavailableView: View {
    var body: some View {
        PagerMessageLayout {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Camera data couldn't be loaded. Restart the app.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("camera-data-unavailable-message")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("camera-data-unavailable")
    }
}
