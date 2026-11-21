// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerKit
import SwiftUI

struct ShootingCollectionSuggestionView: View {
    @Environment(\.dismiss) private var dismiss
    let suggestion: ShootingCollectionSuggestion
    let onConfirm: (Set<UUID>) -> Void
    @State private var chosenIDs: Set<UUID>

    init(suggestion: ShootingCollectionSuggestion, onConfirm: @escaping (Set<UUID>) -> Void) {
        self.suggestion = suggestion
        self.onConfirm = onConfirm
        _chosenIDs = State(initialValue: Set(suggestion.candidates.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(suggestion.candidates) { timer in
                        if let record = PersistentShootingRecord(timer: timer) {
                            Button {
                                if chosenIDs.contains(timer.id) {
                                    chosenIDs.remove(timer.id)
                                } else {
                                    chosenIDs.insert(timer.id)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: chosenIDs.contains(timer.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 6) {
                                        ShootingRecordSummaryView(record: record)
                                        Text(ShootingCollectionSuggestionPresenter.offsetText(
                                            start: timer.startDate, anchor: suggestion.anchor.startDate
                                        ))
                                        .font(.subheadline.weight(.semibold))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(chosenIDs.contains(timer.id) ? String(localized: "Selected") : String(localized: "Not selected"))
                        }
                    }
                } header: {
                    Text("Start time difference from the selected record")
                }
            }
            .navigationTitle("Nearby records")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onConfirm(chosenIDs)
                } label: {
                    Text("Select together (\(chosenIDs.count))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(chosenIDs.isEmpty)
                .padding()
                .background(.regularMaterial)
                .accessibilityIdentifier("confirm-suggested-records")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("collection-suggestion-preview")
    }
}
