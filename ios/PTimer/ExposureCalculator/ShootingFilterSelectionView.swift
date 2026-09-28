// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import PTimerKit
import SwiftUI

/// The shooting popup (FILTER-FLOW-002/003, FILTER-AUX-003): what the
/// active camera mounts for the current shot. The Auxiliary tab edits
/// a working selection — mounting, CPL choices, GND modes — that Apply
/// commits atomically and Cancel discards; the ND tab adds an ND wheel
/// from Standard or a candidate set immediately, with the same rules
/// and source memory as Plus. Both tabs route to the camera's
/// candidate Filter Sets and to inventory management; stored item
/// definitions are edited there, never here.
struct ShootingFilterSelectionView: View {
    enum Tab: Hashable {
        case auxiliary
        case nd
    }

    @ObservedObject var viewModel: ExposureCalculatorViewModel
    let onDismiss: () -> Void

    @State private var tab: Tab
    /// The working auxiliary selection, initialized from this camera's
    /// mounted items (FILTER-AUX-003). Nothing changes until Apply.
    @State private var draft: [MountedAuxiliaryFilter]
    @State private var applyRejection: FilterStackRejection?
    @State private var isManagementPresented = false

    init(viewModel: ExposureCalculatorViewModel, initialTab: Tab = .auxiliary, onDismiss: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _tab = State(initialValue: initialTab)
        _draft = State(initialValue: viewModel.mountedAuxiliaryFilters.map(\.mount))
    }

    private var committed: [MountedAuxiliaryFilter] {
        viewModel.mountedAuxiliaryFilters.map(\.mount)
    }

    private var hasChanges: Bool {
        draft != committed
    }

    private var preview: Result<NDStep, FilterStackRejection> {
        viewModel.auxiliaryFiltersPreview(draft)
    }

    private var canApply: Bool {
        guard hasChanges, case .success = preview else { return false }
        return true
    }

    /// Candidate sets that hold at least one auxiliary item, in
    /// user-defined order.
    private var auxiliarySets: [FilterSet] {
        viewModel.candidateFilterSetIDs
            .compactMap(viewModel.filterSet(withID:))
            .filter { !$0.auxiliaryItems.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $tab) {
                    Text(AuxiliaryFilterSummaryPresenter.title).tag(Tab.auxiliary)
                    Text("ND").tag(Tab.nd)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .accessibilityIdentifier("shooting-filters-tab")

                switch tab {
                case .auxiliary:
                    auxiliaryList
                case .nd:
                    ndList
                }
            }
            .navigationTitle("Shooting filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .accessibilityIdentifier("shooting-filters-cancel-button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: apply)
                        .disabled(!canApply)
                        .accessibilityIdentifier("shooting-filters-apply-button")
                }
            }
            .alert(
                Text("Cannot apply"),
                isPresented: Binding(
                    get: { applyRejection != nil },
                    set: { if !$0 { applyRejection = nil } }
                ),
                presenting: applyRejection
            ) { _ in
                Button("OK", role: .cancel) { applyRejection = nil }
            } message: { rejection in
                Text(FilterWheelPresenter.rejectionText(for: rejection))
            }
            .sheet(isPresented: $isManagementPresented) {
                FilterSetManagementView(viewModel: viewModel) {
                    isManagementPresented = false
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Auxiliary tab

    private var auxiliaryList: some View {
        List {
            if auxiliarySets.isEmpty {
                Section {
                    Text("No auxiliary filters are available on this camera. Choose the camera's Filter Sets, or register CPL, GND, Color, or Effect filters first.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(auxiliarySets) { filterSet in
                Section {
                    ForEach(filterSet.auxiliaryItems) { item in
                        AuxiliaryItemSelectionRow(
                            item: item,
                            filterSetID: filterSet.id,
                            mount: binding(for: item, in: filterSet)
                        )
                    }
                } header: {
                    HStack(spacing: 6) {
                        FilterSetColorSwatch(color: filterSet.color, size: 10)
                        Text(filterSet.name)
                    }
                }
            }
            if !auxiliarySets.isEmpty {
                Section {
                    previewRow
                } footer: {
                    Text("Apply mounts the selected filters together for this camera's current shot. Cancel keeps the current shot unchanged.")
                }
            }
            routesSection
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var previewRow: some View {
        switch preview {
        case .success(let total):
            let state = NDStackTotalDisplayState(effectiveStep: total, wheelCount: 1)
            HStack {
                Text(FilterStatusRegionPresenter.totalLeadingWord())
                Spacer()
                Text("\(state.totalStopsText) \(FilterStatusRegionPresenter.totalTrailingWords(isAtMaximum: state.isAtMaximum))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(FilterStatusRegionPresenter.totalText(state)))
            .accessibilityIdentifier("shooting-filters-total")
        case .failure(let rejection):
            Label(FilterWheelPresenter.rejectionText(for: rejection), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityIdentifier("shooting-filters-rejection")
        }
    }

    /// The working mount of `item`, or `nil` when it is not selected.
    private func binding(for item: FilterItem, in filterSet: FilterSet) -> Binding<MountedAuxiliaryFilter?> {
        Binding(
            get: { draft.first { $0.itemID == item.id } },
            set: { newValue in
                draft.removeAll { $0.itemID == item.id }
                if let newValue {
                    draft.append(newValue)
                }
            }
        )
    }

    private func apply() {
        if let rejection = viewModel.applyAuxiliaryFilters(draft) {
            applyRejection = rejection
        } else {
            onDismiss()
        }
    }

    // MARK: ND tab

    private var ndList: some View {
        List {
            Section {
                ForEach(viewModel.filterSources, id: \.self) { source in
                    NDSourceRow(
                        name: viewModel.filterSourceName(source),
                        color: viewModel.filterSetColor(for: source),
                        unavailabilityText: viewModel.filterAddUnavailabilityText(for: source),
                        isInteractionQuiet: viewModel.isNDWheelInteractionQuiet,
                        onAdd: { viewModel.addFilterWheel(from: source) }
                    )
                }
            } header: {
                Text("ND sources")
            } footer: {
                Text("Adding an ND wheel takes effect immediately and becomes the source Plus adds next. Only a candidate Filter Set with ND filters is listed.")
            }
            routesSection
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Shared routes (FILTER-CAMERA-003)

    private var routesSection: some View {
        Section {
            NavigationLink {
                CameraFilterSetsView(viewModel: viewModel)
            } label: {
                Label("Camera Filter Sets", systemImage: "camera")
            }
            .accessibilityIdentifier("shooting-filters-camera-sets-link")
            Button {
                isManagementPresented = true
            } label: {
                Label("Manage Filter Sets", systemImage: "square.stack.3d.up")
            }
            .accessibilityIdentifier("shooting-filters-manage-button")
        }
    }
}

/// One auxiliary item of a candidate set: a mount toggle, and — while
/// mounted — the CPL exposure-loss choice or the GND calculation mode
/// (FILTER-CPL-005, FILTER-GND-001/002/003). Color and Effect items
/// show their registered loss; nothing is inferred.
private struct AuxiliaryItemSelectionRow: View {
    let item: FilterItem
    /// The set the item belongs to; a fresh mount names it.
    let filterSetID: FilterSetID
    @Binding var mount: MountedAuxiliaryFilter?

    private var isMounted: Binding<Bool> {
        Binding(
            get: { mount != nil },
            set: { on in
                if on {
                    mount = MountedAuxiliaryFilter(
                        filterSetID: filterSetID,
                        itemID: item.id,
                        choice: MountedAuxiliaryFilter.initialChoice(for: item) ?? .registeredLoss
                    )
                } else {
                    mount = nil
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: isMounted) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if let color = item.behavior.opticalColor {
                            Circle()
                                .fill(Color.filterOptical(color))
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                        }
                        Text(item.name)
                    }
                    Text(registeredDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("auxiliary-item-toggle-\(item.id.rawValue)")

            if let current = mount {
                switch item.behavior {
                case .cpl(let choices):
                    Picker("Exposure loss", selection: cplChoiceBinding(current: current, choices: choices)) {
                        ForEach(choices.shootingChoices, id: \.self) { loss in
                            Text(FilterWheelPresenter.stopsText(loss)).tag(loss)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("auxiliary-item-cpl-choice-\(item.id.rawValue)")
                case .gnd:
                    Picker("Calculation mode", selection: gndModeBinding(current: current)) {
                        ForEach(GNDCalculationMode.allCases, id: \.self) { mode in
                            Text(FilterWheelPresenter.gndModeName(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("auxiliary-item-gnd-mode-\(item.id.rawValue)")
                    if case .gnd(.applyFullValue) = current.choice {
                        Text("Apply full value suits a composition where the dark region covers nearly the entire metered frame. A base shutter metered through the mounted GND may already include its attenuation.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                case .fixed, .color, .effect:
                    EmptyView()
                }
            }
        }
    }

    /// `CPL · 1 / 1.5 / 2 stops`, `GND · OD 0.9 · 3 stops`, `Color · Red ·
    /// 2 stops`, `Effect · 0.5 stops` — the registered definition, so a
    /// GND's density is read as density, not as its contribution.
    private var registeredDetail: String {
        let kind = FilterWheelPresenter.kindName(item.behavior.kind)
        switch item.behavior {
        case .cpl(let choices):
            let list = choices.shootingChoices.map(FilterWheelPresenter.decimalStopsValue).joined(separator: " / ")
            return "\(kind) · \(list) \(String(localized: "stops"))"
        case .gnd(let value), .fixed(let value):
            var text = "\(kind) · \(FilterWheelPresenter.registeredValueText(value))"
            if value.unit != .stops, let stops = value.canonicalStops {
                text += " · \(FilterWheelPresenter.stopsText(stops))"
            }
            return text
        case .color, .effect:
            return "\(kind) · \(FilterWheelPresenter.auxiliaryLossDetailText(for: item.behavior) ?? "")"
        }
    }

    private func cplChoiceBinding(current: MountedAuxiliaryFilter, choices: CPLExposureLossChoices) -> Binding<Double> {
        Binding(
            get: {
                if case .cplLoss(let loss) = current.choice { return loss }
                return choices.shootingChoices.first ?? 0
            },
            set: { loss in
                mount = MountedAuxiliaryFilter(filterSetID: current.filterSetID, itemID: current.itemID, choice: .cplLoss(loss))
            }
        )
    }

    private func gndModeBinding(current: MountedAuxiliaryFilter) -> Binding<GNDCalculationMode> {
        Binding(
            get: {
                if case .gnd(let mode) = current.choice { return mode }
                return .recordOnly
            },
            set: { mode in
                mount = MountedAuxiliaryFilter(filterSetID: current.filterSetID, itemID: current.itemID, choice: .gnd(mode))
            }
        )
    }
}

/// One ND source of the popup's ND tab with its explicit add action
/// (FILTER-FLOW-003, FILTER-PLUS-004/005).
private struct NDSourceRow: View {
    let name: String
    let color: FilterSetColor?
    let unavailabilityText: String?
    let isInteractionQuiet: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if let color {
                    FilterSetColorSwatch(color: color, size: 10)
                }
                Text(name)
                Spacer()
                Button("Add ND wheel", action: onAdd)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(unavailabilityText != nil || !isInteractionQuiet)
            }
            if let unavailabilityText {
                Text(unavailabilityText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
