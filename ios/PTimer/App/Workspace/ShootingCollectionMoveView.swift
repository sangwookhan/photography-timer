// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerKit
import SwiftUI

struct ShootingCollectionMoveView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: ShootingCollectionModel
    let sourceID: UUID?
    let recordIDs: Set<UUID>
    let onMoved: () -> Void
    @State private var destinationID: UUID?
    @State private var showError = false

    private var destinations: [PersistentShootingCollection] {
        model.collections.filter { $0.id != sourceID }
    }

    var body: some View {
        NavigationStack {
            List {
                if destinations.isEmpty {
                    ContentUnavailableView(
                        "No destination Collection", systemImage: "folder",
                        description: Text("Create another Collection before moving these records.")
                    )
                } else {
                    Section {
                        ForEach(destinations) { collection in
                            Button {
                                destinationID = collection.id
                            } label: {
                                ShootingCollectionDestinationRow(
                                    collection: collection, isSelected: destinationID == collection.id
                                )
                            }
                            .accessibilityAddTraits(destinationID == collection.id ? .isSelected : [])
                        }
                    } header: {
                        Text("Move \(recordIDs.count) records to")
                    }
                }
            }
            .navigationTitle("Move records")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") { move() }
                        .disabled(destinationID == nil || !model.isAvailable)
                        .accessibilityIdentifier("confirm-collection-record-move")
                }
            }
            .alert("Records couldn't be moved", isPresented: $showError) {
            } message: {
                Text("Your records and selection are unchanged. Try again or cancel.")
            }
        }
    }

    private func move() {
        guard let destinationID else { return }
        switch model.move(recordIDs: recordIDs, from: sourceID, to: destinationID) {
        case .success:
            onMoved()
            dismiss()
        case .failure:
            showError = true
        }
    }
}
