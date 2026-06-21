// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import PTimerKit

/// Lightweight sheet that lets the photographer rename a camera slot
/// or reset its custom name back to the canonical `Camera N` default.
/// Driven from `ExposureWorkspaceMainContent` via `.sheet(item:)`
/// keyed off the slot id pending rename.
///
/// The sheet does not own slot state — it just collects a draft name,
/// then forwards the result to the ViewModel facade through the
/// `onSave` / `onReset` closures. Whitespace-only or empty input is
/// treated as a reset request so the editing path round-trips with
/// the rendering path on `CameraSlotIdentity`.
struct CameraSlotRenameSheet: View {
    let slotID: CameraSlotID
    /// Canonical `Camera N` label for `slotID`. Shown both as the
    /// text-field placeholder and inside the Reset button so the
    /// photographer always sees the value the slot would fall back
    /// to, even before tapping Reset.
    let defaultDisplayName: String
    /// Pre-existing custom name for the slot, if any. The text field
    /// seeds with this so re-opening the sheet on a renamed slot
    /// shows the current value.
    let initialCustomName: String?
    let onSave: (String?) -> Void
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(defaultDisplayName, text: $draftName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .submitLabel(.done)
                        .focused($isFieldFocused)
                        .onSubmit(performSave)
                        .accessibilityIdentifier("camera-slot-rename-text-field")
                } header: {
                    Text("Slot name")
                } footer: {
                    Text("Leave blank to use the default \(defaultDisplayName).")
                }

                if hasCustomName {
                    Section {
                        Button(role: .destructive, action: performReset) {
                            Text("Reset to \(defaultDisplayName)")
                        }
                        .accessibilityIdentifier("camera-slot-rename-reset-button")
                    }
                }
            }
            .navigationTitle("Rename slot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("camera-slot-rename-cancel-button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: performSave)
                        .accessibilityIdentifier("camera-slot-rename-save-button")
                }
            }
            .onAppear {
                draftName = initialCustomName ?? ""
                // Focus on the text field after appearing so the
                // photographer can start typing immediately. The
                // dispatch defer matches the standard SwiftUI
                // recipe: setting `@FocusState` synchronously inside
                // `onAppear` drops the focus on iOS 17+.
                DispatchQueue.main.async {
                    isFieldFocused = true
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("camera-slot-rename-sheet-\(slotID.rawValue)")
    }

    private var trimmedDraft: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasCustomName: Bool {
        !(initialCustomName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func performSave() {
        if trimmedDraft.isEmpty {
            // Whitespace-only input is the editing path's "clear"
            // signal — fall back to the same path as the explicit
            // Reset button so the rules stay single-rooted.
            onReset()
        } else {
            onSave(trimmedDraft)
        }
        dismiss()
    }

    private func performReset() {
        onReset()
        dismiss()
    }
}
