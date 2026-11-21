// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerKit
import SwiftUI

enum ShootingCollectionRoute: Hashable {
    case collection(UUID)
    case uncollected
    case record(UUID)
}

struct ShootingCollectionBrowser: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: ShootingCollectionModel
    let history: [RunningTimerItem]
    @State private var path: [ShootingCollectionRoute] = []
    @State private var isSelecting = false
    @State private var isEditing = false

    init(model: ShootingCollectionModel, history: [RunningTimerItem], startsSelecting: Bool = false) {
        self.model = model
        self.history = history
        _isSelecting = State(initialValue: startsSelecting)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isSelecting {
                    ShootingCollectionSelectionView(model: model, history: history) { id in
                        isSelecting = false
                        path = [.collection(id)]
                    } onCancel: {
                        isSelecting = false
                    }
                } else {
                    collectionList
                }
            }
            .navigationTitle(isSelecting ? String(localized: "Select History") : String(localized: "Collections"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isSelecting && path.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                }
            }
            .navigationDestination(for: ShootingCollectionRoute.self) { route in
                switch route {
                case .collection(let id):
                    ShootingCollectionRecordsView(model: model, collectionID: id, isEditing: $isEditing)
                case .uncollected:
                    ShootingCollectionRecordsView(model: model, collectionID: nil, isEditing: $isEditing)
                case .record(let eventID):
                    if let record = model.record(id: eventID) {
                        ShootingRecordDetailView(record: record)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isEditing)
    }

    private var collectionList: some View {
        List {
            if !model.isAvailable {
                Text("Collections couldn't be loaded. Restart the app to try again.")
            } else {
                Section {
                    Button("Select from History", systemImage: "checklist") { isSelecting = true }
                        .disabled(history.isEmpty)
                        .accessibilityIdentifier("collections-select-history")
                    NavigationLink(value: ShootingCollectionRoute.uncollected) {
                        Label("Uncollected records", systemImage: "tray")
                            .badge(model.uncollectedRecords.count)
                    }
                    .accessibilityIdentifier("collections-uncollected-records")
                }
                if model.collections.isEmpty {
                    ContentUnavailableView(
                        "No Collections", systemImage: "rectangle.stack",
                        description: Text("Preserve completed or canceled timers by selecting them from History.")
                    )
                } else {
                    ForEach(model.collections) { collection in
                        NavigationLink(value: ShootingCollectionRoute.collection(collection.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(collection.title).font(.headline)
                                Text(collection.records.count == 1 ? String(localized: "1 record") : String(localized: "\(collection.records.count) records"))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("shooting-collections-list")
    }
}
