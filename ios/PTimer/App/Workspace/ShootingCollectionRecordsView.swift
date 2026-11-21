// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerKit
import SwiftUI

struct ShootingCollectionRecordsView: View {
    @ObservedObject var model: ShootingCollectionModel
    let collectionID: UUID?
    @Binding var isEditing: Bool
    @State private var selectedIDs: Set<UUID>
    @State private var pendingIDs = Set<UUID>()
    @State private var showRemoval = false
    @State private var showMove = false
    @State private var showError = false

    init(
        model: ShootingCollectionModel, collectionID: UUID?, isEditing: Binding<Bool>,
        initialSelection: Set<UUID> = []
    ) {
        self.model = model
        self.collectionID = collectionID
        _isEditing = isEditing
        _selectedIDs = State(initialValue: initialSelection)
    }

    private var records: [PersistentShootingRecord] { model.records(in: collectionID) }

    var body: some View {
        List(selection: $selectedIDs) {
            if records.isEmpty {
                ContentUnavailableView(
                    "No records", systemImage: "rectangle.stack",
                    description: Text(collectionID == nil
                        ? String(localized: "Records removed from a Collection remain preserved here.")
                        : String(localized: "This Collection has no records."))
                )
            } else {
                ForEach(records) { record in
                    NavigationLink(value: ShootingCollectionRoute.record(record.id)) {
                        ShootingRecordSummaryView(record: record)
                    }
                    .tag(record.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !isEditing && model.isAvailable {
                            if collectionID != nil {
                                Button("Remove", systemImage: "minus.circle") {
                                    requestRemoval([record.id])
                                }
                                .tint(.orange)
                                .accessibilityLabel(Text("Remove from Collection"))
                            }
                            Button("Move", systemImage: "folder") { requestMove([record.id]) }
                                .tint(.accentColor)
                        }
                    }
                    .accessibilityActions {
                        Button("Move") { requestMove([record.id]) }
                        if collectionID != nil {
                            Button("Remove from Collection") { requestRemoval([record.id]) }
                        }
                    }
                }
            }
        }
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .navigationTitle(collectionID.flatMap { id in model.collections.first { $0.id == id }?.title }
            ?? String(localized: "Uncollected records"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditing)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? String(localized: "Done") : String(localized: "Edit")) {
                    isEditing.toggle()
                }
                .fontWeight(isEditing ? .semibold : .regular)
                .disabled(!model.isAvailable || records.isEmpty && !isEditing)
                .accessibilityIdentifier("edit-collection-records")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isEditing {
                HStack {
                    Button {
                        requestMove(selectedIDs)
                    } label: {
                        Text("Move").frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("collection-records-move-selected")
                    if collectionID != nil {
                        Button {
                            requestRemoval(selectedIDs)
                        } label: {
                            Text("Remove").frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel(Text("Remove from Collection"))
                        .accessibilityIdentifier("collection-records-remove-selected")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(selectedIDs.isEmpty || !model.isAvailable)
                .padding()
                .background(.regularMaterial)
            }
        }
        .confirmationDialog("Remove from Collection?", isPresented: $showRemoval, titleVisibility: .visible) {
            Button("Remove from Collection") { remove() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(pendingIDs.count) records will leave this Collection. The Timer list is unchanged. Captured records remain available in Uncollected records.")
        }
        .sheet(isPresented: $showMove) {
            ShootingCollectionMoveView(model: model, sourceID: collectionID, recordIDs: pendingIDs) {
                selectedIDs.subtract(pendingIDs)
            }
        }
        .alert("Records couldn't be removed", isPresented: $showError) {
        } message: {
            Text("Your records and selection are unchanged. Try again or cancel.")
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { selectedIDs.removeAll() }
        }
        .interactiveDismissDisabled(isEditing)
        .accessibilityIdentifier("collection-records-list")
    }

    private func requestRemoval(_ ids: Set<UUID>) {
        pendingIDs = ids
        showRemoval = true
    }

    private func requestMove(_ ids: Set<UUID>) {
        pendingIDs = ids
        showMove = true
    }

    private func remove() {
        guard let collectionID else { return }
        switch model.remove(recordIDs: pendingIDs, from: collectionID) {
        case .success: selectedIDs.subtract(pendingIDs)
        case .failure: showError = true
        }
    }
}
