// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// An archive owns its captured values, independently of Timer History.
public struct PersistentShootingRecord: Codable, Equatable, Identifiable {
    public enum Outcome: String, Codable {
        case completed, canceled
    }

    public var id: UUID { metadata.id }
    public let outcome: Outcome
    public let startDate: Date
    public let terminalDate: Date?
    public let duration: TimeInterval
    public let remainingAtCancel: TimeInterval?
    public let metadata: PersistentTimerMetadataSnapshot

    public init?(timer: RunningTimerItem) {
        switch timer.status {
        case .completed: outcome = .completed
        case .canceled: outcome = .canceled
        case .running, .paused: return nil
        }
        startDate = timer.startDate
        terminalDate = timer.endDate
        duration = timer.duration
        remainingAtCancel = timer.canceledRemainingTime
        metadata = PersistentTimerMetadataSnapshot(
            id: timer.id, order: timer.order, name: timer.name,
            basisSummary: timer.basisSummary,
            cameraSlotIDRaw: timer.cameraSlot?.id.rawValue,
            cameraSlotDisplayName: timer.cameraSlot?.displayName,
            filmDisplayName: timer.filmDisplayName,
            filmProfileQualifier: timer.filmProfileQualifier,
            exposureSourceRaw: timer.exposureSource?.rawValue,
            isOutsideManufacturerGuidance: timer.isOutsideManufacturerGuidance,
            customProfileSummary: timer.customProfileSummary,
            selectedModelLabel: timer.selectedModelLabel,
            ndStops: timer.ndStops, baseShutterSeconds: timer.baseShutterSeconds,
            adjustedShutterSeconds: timer.adjustedShutterSeconds,
            filterSummary: timer.filterSummary, filterReferenceText: timer.filterReferenceText
        )
    }
}
