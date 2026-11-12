// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerKit
import SwiftUI

struct ShootingCollectionSelectionView: View {
    @ObservedObject var model: ShootingCollectionModel
    let history: [RunningTimerItem]
    let onCreated: (UUID) -> Void
    let onCancel: () -> Void
    @State private var selectedIDs = Set<UUID>()
    @State private var error: ShootingCollectionError?
    @State private var showError = false

    var body: some View {
        List {
            Section("History") {
                ForEach(history) { timer in
                    if let record = PersistentShootingRecord(timer: timer) {
                        let collection = model.collection(containing: timer.id)
                        Button {
                            if selectedIDs.contains(timer.id) {
                                selectedIDs.remove(timer.id)
                            } else {
                                selectedIDs.insert(timer.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedIDs.contains(timer.id) ? "checkmark.circle.fill" : "circle")
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    ShootingRecordSummaryView(record: record)
                                    if let collection {
                                        Text("In Collection: \(collection.title)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                        .disabled(collection != nil || !model.isAvailable)
                        .accessibilityValue(selectedIDs.contains(timer.id) ? String(localized: "Selected") : String(localized: "Not selected"))
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    let selection = history.filter { selectedIDs.contains($0.id) }
                    switch model.create(from: selection, at: Date(), timeZone: .current) {
                    case .success(let id): onCreated(id)
                    case .failure(let failure):
                        error = failure
                        showError = true
                    }
                }
                .disabled(selectedIDs.isEmpty || !model.isAvailable)
                .accessibilityIdentifier("create-shooting-collection")
            }
        }
        .alert("Collection couldn't be saved", isPresented: $showError) {
        } message: {
            if let error { Text(message(for: error)) }
        }
        .interactiveDismissDisabled(!selectedIDs.isEmpty)
    }

    private func message(for error: ShootingCollectionError) -> String {
        switch error {
        case .saveFailed: String(localized: "Collection couldn't be saved. Your selection is kept. Try again or cancel.")
        case .alreadyCollected: String(localized: "A selected event is already in a Collection. Review your selection.")
        case .invalidSelection: String(localized: "Select completed or canceled History events.")
        case .unavailable: String(localized: "Collections couldn't be loaded. Restart the app to try again.")
        }
    }
}
