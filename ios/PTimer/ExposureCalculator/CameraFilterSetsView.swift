// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import PTimerKit
import SwiftUI

/// The active camera's candidate Filter Sets (FILTER-CAMERA-001/002):
/// the inventory sets this camera can draw auxiliary filters and ND
/// wheels from. Assignment saves immediately, mounts nothing, and
/// infers no diameter, holder, or adapter compatibility; the same set
/// may be assigned to several cameras. A set this camera still
/// references cannot be excluded until its selections are cleared.
struct CameraFilterSetsView: View {
    @ObservedObject var viewModel: ExposureCalculatorViewModel

    @State private var blockedFilterSetNames: [String]?

    private var referenced: Set<FilterSetID> {
        viewModel.filterSetIDsReferencedByActiveCamera
    }

    var body: some View {
        List {
            if viewModel.filterInventory.filterSets.isEmpty {
                Section {
                    Text("No Filter Sets yet. Register the physical filters you carry in Manage Filter Sets first.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(viewModel.filterInventory.filterSets) { filterSet in
                    let isCandidate = viewModel.candidateFilterSetIDs.contains(filterSet.id)
                    Button {
                        toggle(filterSet)
                    } label: {
                        HStack(spacing: 12) {
                            FilterSetColorSwatch(color: filterSet.color, size: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(filterSet.name)
                                    .foregroundStyle(.primary)
                                Text(detailText(for: filterSet))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isCandidate {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(isCandidate ? [.isSelected] : [])
                    .accessibilityIdentifier("camera-filter-set-row-\(filterSet.id.rawValue)")
                }
            } footer: {
                Text("Assigned Filter Sets are available on this camera for auxiliary filters and ND wheels. Assigning mounts nothing and does not check size or holder compatibility. Standard is always available.")
            }
        }
        .navigationTitle("Camera Filter Sets")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            Text("Filter Set in use"),
            isPresented: Binding(
                get: { blockedFilterSetNames != nil },
                set: { if !$0 { blockedFilterSetNames = nil } }
            ),
            presenting: blockedFilterSetNames
        ) { _ in
            Button("OK", role: .cancel) { blockedFilterSetNames = nil }
        } message: { names in
            Text("Clear the filters and ND wheels mounted from \(names.joined(separator: ", ")) on this camera before excluding it.")
        }
    }

    /// `2 auxiliary · 3 ND`, plus whether this camera currently uses the set.
    private func detailText(for filterSet: FilterSet) -> String {
        var text = String(localized: "\(filterSet.auxiliaryItems.count) auxiliary · \(filterSet.ndItems.count) ND")
        if referenced.contains(filterSet.id) {
            text += " · " + String(localized: "In use on this camera")
        }
        return text
    }

    private func toggle(_ filterSet: FilterSet) {
        var ids = viewModel.candidateFilterSetIDs
        if let index = ids.firstIndex(of: filterSet.id) {
            ids.remove(at: index)
        } else {
            ids.append(filterSet.id)
        }
        if case .blocked(let names) = viewModel.setCandidateFilterSetIDs(ids) {
            blockedFilterSetNames = names
        }
    }
}
