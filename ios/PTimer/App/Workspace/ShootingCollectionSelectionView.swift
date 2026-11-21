// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerKit
import SwiftUI

struct ShootingCollectionSelectionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: ShootingCollectionModel
    let history: [RunningTimerItem]
    let onCreated: (UUID) -> Void
    let onCancel: () -> Void
    @State private var selection: ShootingCollectionSelection
    @State private var error: ShootingCollectionError?
    @State private var showError = false
    @State private var preview: ShootingCollectionSuggestion?

    init(
        model: ShootingCollectionModel,
        history: [RunningTimerItem],
        initialSelection: ShootingCollectionSelection = ShootingCollectionSelection(),
        onCreated: @escaping (UUID) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.model = model
        self.history = history
        self.onCreated = onCreated
        self.onCancel = onCancel
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        let suggestion = selection.suggestion(from: history, collectedIDs: model.collectedEventIDs)
        let suggestedIDs = Set(suggestion?.candidates.map(\.id) ?? [])
        ScrollViewReader { proxy in
            List {
                Section("History") {
                    ForEach(history) { timer in
                        if let record = PersistentShootingRecord(timer: timer) {
                            historyRow(timer, record: record, suggestion: suggestion, isSuggested: suggestedIDs.contains(timer.id))
                                .id(timer.id)
                        }
                    }
                }
            }
            .onChange(of: suggestion?.anchor.id, initial: true) { _, anchorID in
                guard let anchorID else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    proxy.scrollTo(anchorID, anchor: .bottom)
                }
            }
        }
        .sheet(item: $preview) { suggestion in
            ShootingCollectionSuggestionView(suggestion: suggestion) { chosenIDs in
                selection.confirmSuggestion(
                    suggestion, choosing: chosenIDs, from: history, collectedIDs: model.collectedEventIDs
                )
                preview = nil
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    let selectedTimers = history.filter { selection.selectedIDs.contains($0.id) }
                    switch model.create(from: selectedTimers, at: Date(), timeZone: .current) {
                    case .success(let id): onCreated(id)
                    case .failure(let failure):
                        error = failure
                        showError = true
                    }
                }
                .disabled(selection.selectedIDs.isEmpty || !model.isAvailable)
                .accessibilityIdentifier("create-shooting-collection")
            }
        }
        .alert("Collection couldn't be saved", isPresented: $showError) {
        } message: {
            if let error { Text(message(for: error)) }
        }
        .interactiveDismissDisabled(!selection.selectedIDs.isEmpty)
    }

    private func historyRow(
        _ timer: RunningTimerItem, record: PersistentShootingRecord,
        suggestion: ShootingCollectionSuggestion?, isSuggested: Bool
    ) -> some View {
        let collection = model.collection(containing: timer.id)
        let isAnchor = suggestion?.anchor.id == timer.id
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                selection.toggle(timer.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selection.selectedIDs.contains(timer.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection.selectedIDs.contains(timer.id) ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        ShootingRecordSummaryView(record: record)
                        if isSuggested {
                            Label("Time suggestion", systemImage: "clock")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }
                        if let collection {
                            Text("In Collection: \(collection.title)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(collection != nil || !model.isAvailable)
            .accessibilityValue(selection.selectedIDs.contains(timer.id) ? String(localized: "Selected") : String(localized: "Not selected"))
            .accessibilityActions {
                if isAnchor && model.isAvailable {
                    Button("View nearby records") { preview = suggestion }
                }
            }
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in preview = suggestion },
                including: isAnchor && model.isAvailable ? .all : .none
            )
            if let suggestion, isAnchor, model.isAvailable {
                Button {
                    preview = suggestion
                } label: {
                    Text("Nearby records: \(suggestion.candidates.count) · View")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .padding(.leading, 32)
                .accessibilityIdentifier("collection-view-suggestions")
            }
        }
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
