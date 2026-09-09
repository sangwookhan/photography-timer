// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Builds the human-readable, start-time reference string a timer keeps
/// beside its calculation record (FILTER-PERSIST-003): Filter Set and
/// Filter Item names, registered representations, and calculation
/// modes as they stood when the timer started. Descriptive only — it is
/// generated once from the captured summary, stored with the timer, and
/// never re-derived from the live inventory.
///
/// Example: `Standard 2 stops · Lee holder: Big Stopper ND1000 +
/// Lee GND 0.9 OD 0.9 (Record only) · NiSi kit: NiSi CPL 1.5`
public enum FilterSummaryReferencePresenter {
    public static func referenceText(for summary: [FilterSummaryEntry]) -> String? {
        var segments: [String] = []
        var currentSetName: String?
        var currentItems: [String] = []

        func flushSet() {
            guard let setName = currentSetName, !currentItems.isEmpty else {
                currentSetName = nil
                currentItems = []
                return
            }
            segments.append("\(setName): \(currentItems.joined(separator: " + "))")
            currentSetName = nil
            currentItems = []
        }

        for entry in summary {
            switch entry.sourceKind {
            case .standard:
                flushSet()
                guard entry.contributedStops > 0 else { continue }
                segments.append(String(localized: "Standard \(FilterWheelPresenter.stopsText(entry.contributedStops))"))
            case .filterSet:
                let setName = entry.filterSetName ?? String(localized: "Filter Set")
                if currentSetName != setName {
                    flushSet()
                    currentSetName = setName
                }
                currentItems.append(itemText(for: entry))
            }
        }
        flushSet()
        return segments.isEmpty ? nil : segments.joined(separator: " · ")
    }

    /// `Big Stopper ND1000`, `Lee GND 0.9 OD 0.9 (Record only)`,
    /// `Lee CPL 1.5 stops` — name, registered representation, mode.
    static func itemText(for entry: FilterSummaryEntry) -> String {
        let name = entry.itemName ?? String(localized: "Filter")
        var text = name
        switch entry.calculationMode {
        case .cplLoss:
            if let stops = entry.canonicalStops {
                text += " \(FilterWheelPresenter.stopsText(stops))"
            }
        case .fixed, .gndRecordOnly, .gndApplyFullValue, nil:
            if let value = entry.originalValue, let unit = entry.originalUnit {
                text += " \(FilterWheelPresenter.registeredValueText(FilterRegisteredValue(value: value, unit: unit)))"
            } else if let stops = entry.canonicalStops {
                text += " \(FilterWheelPresenter.stopsText(stops))"
            }
        }
        switch entry.calculationMode {
        case .gndRecordOnly:
            text += " (\(FilterWheelPresenter.gndModeName(.recordOnly)))"
        case .gndApplyFullValue:
            text += " (\(FilterWheelPresenter.gndModeName(.applyFullValue)))"
        case .fixed, .cplLoss, nil:
            break
        }
        return text
    }
}
