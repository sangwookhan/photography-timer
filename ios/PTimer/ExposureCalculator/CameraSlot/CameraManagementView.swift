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

    private var cameras: [CameraListEntry] { viewModel.cameraList }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                ForEach(Array(cameras.enumerated()), id: \.element.id) { index, camera in
                    row(for: camera, index: index)
                        .tag(camera.id)
                }
                .onMove { source, destination in
                    viewModel.moveCameras(fromOffsets: source, toOffset: destination)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                        .accessibilityIdentifier("camera-management-done-button")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(editMode.isEditing ? "Finish" : "Select") {
                        selection.removeAll()
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                    .disabled(cameras.isEmpty)
                    .accessibilityIdentifier("camera-management-select-button")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if editMode.isEditing {
                        Button("Hide") {
                            viewModel.hideCameras(selection)
                            selection.removeAll()
                            announceResultingCamera()
                        }
                        .disabled(selection.isEmpty)
                        .accessibilityIdentifier("camera-management-bulk-hide-button")
                        Spacer()
                        Button("Delete", role: .destructive) {
                            pendingDelete = selection
                        }
                        .disabled(selection.isEmpty)
                        .accessibilityIdentifier("camera-management-bulk-delete-button")
                    } else {
                        Button {
                            viewModel.addCamera()
                            announceResultingCamera()
                        } label: {
                            Label("Add camera", systemImage: "plus")
                        }
                        .accessibilityIdentifier("camera-management-add-button")
                        Spacer()
                    }
                }
            }
        }
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
                    viewModel.deleteCameras(ids)
                    selection.subtract(ids)
                    announceResultingCamera()
                }
                pendingDelete = nil
            }
            .accessibilityIdentifier("camera-management-confirm-delete-button")
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            deleteMessage
        }
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
                    viewModel.setCameraDisplayed(!camera.isDisplayed, for: camera.id)
                    announceResultingCamera()
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
            viewModel.setCameraDisplayed(!camera.isDisplayed, for: camera.id)
            announceResultingCamera()
        }
        .accessibilityAction(named: Text("Rename camera")) {
            renamingSlotID = camera.id
        }
        .accessibilityAction(named: Text("Move up")) {
            move(camera.id, by: -1)
        }
        .accessibilityAction(named: Text("Move down")) {
            move(camera.id, by: 1)
        }
        .accessibilityAction(named: Text("Delete camera")) {
            pendingDelete = [camera.id]
        }
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

    /// After a hide, delete, or add, tells VoiceOver which camera is now
    /// active, or that the pager is empty.
    private func announceResultingCamera() {
        let message: String
        if let active = viewModel.activeCameraSlot {
            message = String(localized: "Active camera: \(active.displayName)")
        } else {
            message = String(localized: "No cameras shown")
        }
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

/// Shown in place of the pager when no camera is displayed
/// (CAMERA-PAGER-004). Existing timers stay available in the timer
/// strip below; a calculator-bound timer needs a displayed camera.
struct EmptyCameraPagerView: View {
    let onManageCameras: () -> Void
    let onAddCamera: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No cameras shown")
                .font(.headline)
            Text("Show or add a camera to calculate exposures. Running timers are not affected.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Manage cameras", action: onManageCameras)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("empty-pager-manage-cameras-button")
                Button("Add camera", action: onAddCamera)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("empty-pager-add-camera-button")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("empty-camera-pager")
    }
}
