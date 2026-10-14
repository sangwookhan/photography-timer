// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import PTimerKit

/// Lightweight sheet that lets the photographer rename a camera.
/// Presented from the camera title and the camera management rows via
/// `.sheet(item:)` keyed off the camera id pending rename.
///
/// The sheet does not own camera state — it collects a draft name and
/// forwards it to the ViewModel facade through `onSave`. A blank or
/// whitespace-only name is rejected: Save stays disabled and the
/// stored name is left unchanged.
struct CameraSlotRenameSheet: View {
    let slotID: CameraSlotID
    /// The camera's current name; seeds the text field.
    let initialName: String
    /// Returns whether the rename applied.
    let onSave: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Camera name", text: $draftName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .submitLabel(.done)
                        .focused($isFieldFocused)
                        .onSubmit(performSave)
                        .accessibilityIdentifier("camera-slot-rename-text-field")
                } header: {
                    Text("Camera name")
                }
            }
            .navigationTitle("Rename camera")
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
                        .disabled(trimmedDraft.isEmpty)
                        .accessibilityIdentifier("camera-slot-rename-save-button")
                }
            }
            .onAppear {
                draftName = initialName
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

    private func performSave() {
        guard !trimmedDraft.isEmpty else { return }
        if onSave(trimmedDraft) {
            dismiss()
        }
    }
}
