// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

public enum ShootingRecordPresenter {
    public static func display(_ record: PersistentShootingRecord) -> ShootingRecordDisplayState {
        let metadata = record.metadata
        let calculator = ExposureCalculator()
        let status = record.outcome == .completed ? String(localized: "Done") : String(localized: "Canceled")
        let title = [metadata.cameraSlotDisplayName, metadata.filmDisplayName]
            .compactMap { $0 }.joined(separator: " · ")
        var fields: [ShootingRecordDisplayState.Field] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { fields.append(.init(label: label, value: value)) }
        }
        add(String(localized: "State"), status)
        add(String(localized: "Started"), record.startDate.formatted(date: .abbreviated, time: .standard))
        add(String(localized: "Ended"), record.terminalDate?.formatted(date: .abbreviated, time: .standard))
        add(String(localized: "Duration"), calculator.formatExtendedClock(record.duration))
        add(String(localized: "Remaining at cancel"), record.remainingAtCancel.map(calculator.formatExtendedClock))
        add(String(localized: "Camera"), metadata.cameraSlotDisplayName)
        add(String(localized: "Film"), metadata.filmDisplayName)
        let source = metadata.exposureSourceRaw.flatMap(ExposureTimerSource.init(rawValue:))
        add(String(localized: "Exposure source"), source.map(TimerCardIdentityPresenter.sourceLabel))
        add(String(localized: "Base Shutter"), metadata.baseShutterSeconds.map(calculator.formatShutter))
        add(String(localized: "ND"), metadata.ndStops.map { String(localized: "\($0.formatted()) stops") })
        add(String(localized: "Adjusted Exposure"), metadata.adjustedShutterSeconds.map(calculator.formatShutter))
        let filterText = metadata.filterReferenceText ?? metadata.filterSummary.flatMap {
            FilterSummaryReferencePresenter.referenceText(for: $0)
        }
        add(String(localized: "Filters"), filterText)
        add(String(localized: "Profile"), metadata.filmProfileQualifier)
        add(String(localized: "Model"), metadata.selectedModelLabel)
        add(String(localized: "Custom profile"), metadata.customProfileSummary)
        if metadata.isOutsideManufacturerGuidance == true {
            add(String(localized: "Guidance"), String(localized: "Outside manufacturer guidance"))
        }
        add(String(localized: "Captured basis"), metadata.basisSummary)
        return ShootingRecordDisplayState(
            title: title.isEmpty ? metadata.name : title,
            subtitle: "\(status) · \(calculator.formatExtendedClock(record.duration))", fields: fields
        )
    }
}
