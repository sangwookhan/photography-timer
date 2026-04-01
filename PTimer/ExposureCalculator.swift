import Foundation

struct ExposureCalculationResult: Equatable {
    let baseShutterSeconds: Double
    let stop: Int
    let resultShutterSeconds: Double
}

enum ExposureCalculatorError: LocalizedError, Equatable {
    case emptyBaseShutter
    case invalidBaseShutter
    case nonPositiveBaseShutter
    case nonPositiveND
    case overflow

    var errorDescription: String? {
        switch self {
        case .emptyBaseShutter:
            return "Base shutter is required."
        case .invalidBaseShutter:
            return "Enter shutter like 1/30, 0.5, or 2s."
        case .nonPositiveBaseShutter:
            return "Base shutter must be greater than 0."
        case .nonPositiveND:
            return "ND stop must be 0 or greater."
        case .overflow:
            return "Calculated shutter is too large to display."
        }
    }
}

struct ExposureCalculator {
    static let fullStopShutterSpeeds: [Double] = [
        1.0 / 8000, 1.0 / 4000, 1.0 / 2000, 1.0 / 1000,
        1.0 / 500, 1.0 / 250, 1.0 / 125, 1.0 / 60,
        1.0 / 30, 1.0 / 15, 1.0 / 8, 1.0 / 4,
        1.0 / 2, 1, 2, 4, 8, 15, 30
    ]

    func parseBaseShutter(_ input: String) throws -> Double {
        let trimmed = normalize(input)
        guard !trimmed.isEmpty else {
            throw ExposureCalculatorError.emptyBaseShutter
        }

        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/", omittingEmptySubsequences: true)
            guard parts.count == 2,
                  let numerator = Double(parts[0]),
                  let denominator = Double(parts[1]) else {
                throw ExposureCalculatorError.invalidBaseShutter
            }

            guard numerator > 0, denominator > 0 else {
                throw ExposureCalculatorError.nonPositiveBaseShutter
            }

            return numerator / denominator
        }

        guard let seconds = Double(trimmed) else {
            throw ExposureCalculatorError.invalidBaseShutter
        }

        guard seconds > 0 else {
            throw ExposureCalculatorError.nonPositiveBaseShutter
        }

        return seconds
    }

    func calculate(baseShutterSeconds: Double, stop: Int) throws -> Double {
        guard baseShutterSeconds > 0 else {
            throw ExposureCalculatorError.nonPositiveBaseShutter
        }

        guard stop >= 0 else {
            throw ExposureCalculatorError.nonPositiveND
        }

        let result = baseShutterSeconds * pow(2.0, Double(stop))
        guard result.isFinite else {
            throw ExposureCalculatorError.overflow
        }

        return snapToFullStop(result)
    }

    func formatShutter(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else {
            return "-"
        }

        if seconds >= 1 {
            if abs(seconds.rounded() - seconds) < 0.0001 {
                return "\(Int(seconds.rounded()))s"
            }

            return String(format: "%.1fs", seconds)
        }

        let reciprocal = 1 / seconds
        if abs(reciprocal.rounded() - reciprocal) < 0.05 {
            return "1/\(Int(reciprocal.rounded()))s"
        }

        return String(format: "%.3fs", seconds)
    }

    private func normalize(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "seconds", with: "")
            .replacingOccurrences(of: "second", with: "")
            .replacingOccurrences(of: "sec", with: "")
            .replacingOccurrences(of: "s", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func snapToFullStop(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else {
            return value
        }

        if value <= 30 {
            return Self.fullStopShutterSpeeds.min(
                by: { abs($0 - value) < abs($1 - value) }
            ) ?? value
        }

        if value < 64 {
            return abs(value - 30) <= abs(64 - value) ? 30 : 64
        }

        let lowerExponent = floor(log2(value))
        let upperExponent = ceil(log2(value))
        let lower = pow(2.0, lowerExponent)
        let upper = pow(2.0, upperExponent)

        return abs(value - lower) <= abs(upper - value) ? lower : upper
    }
}
