// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct ShootingCollectionSummaryDisplayState: Equatable {
    public let recordCount: Int
    public let startDate: Date?
    public let endDate: Date?
    public let missingEndCount: Int
    public let representativeCameraName: String?
    public let additionalCameraCount: Int
    public let missingCameraCount: Int
}
