import Foundation

struct ExposureCalculationResult: Equatable {
    let baseShutterSeconds: Double
    let ndFactor: Double
    let resultShutterSeconds: Double
}

enum ExposureCalculatorError: LocalizedError, Equatable {
    case emptyBaseShutter
    case invalidBaseShutter
    case nonPositiveBaseShutter
    case emptyND
    case invalidND
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
        case .emptyND:
            return "ND value is required."
        case .invalidND:
            return "Enter ND like 8, 64, or ND1000."
        case .nonPositiveND:
            return "ND value must be greater than 0."
        case .overflow:
            return "Calculated shutter is too large to display."
        }
    }
}

struct ExposureCalculator {
    private let ndStopMappings: [Double: Double] = [
        1: 0,
        2: 1,
        4: 2,
        8: 3,
        16: 4,
        32: 5,
        64: 6,
        128: 7,
        200: 8,
        256: 8,
        400: 9,
        512: 9,
        1000: 10
    ]

    private let subsecondShutterStops: [(seconds: Double, stopOffset: Double)] = [
        (1.0 / 2.0, -1),
        (1.0 / 4.0, -2),
        (1.0 / 8.0, -3),
        (1.0 / 15.0, -4),
        (1.0 / 30.0, -5),
        (1.0 / 60.0, -6),
        (1.0 / 125.0, -7),
        (1.0 / 250.0, -8),
        (1.0 / 500.0, -9),
        (1.0 / 1000.0, -10),
        (1.0 / 2000.0, -11)
    ]

    func calculate(baseShutterInput: String, ndInput: String) -> Result<ExposureCalculationResult, ExposureCalculatorError> {
        do {
            let baseShutter = try parseBaseShutter(baseShutterInput)
            let ndFactor = try parseNDFactor(ndInput)
            let resultShutter = try calculate(baseShutterSeconds: baseShutter, ndFactor: ndFactor)

            return .success(
                ExposureCalculationResult(
                    baseShutterSeconds: baseShutter,
                    ndFactor: ndFactor,
                    resultShutterSeconds: resultShutter
                )
            )
        } catch let error as ExposureCalculatorError {
            return .failure(error)
        } catch {
            return .failure(.overflow)
        }
    }

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

    func parseNDFactor(_ input: String) throws -> Double {
        let normalized = normalize(input).replacingOccurrences(of: "nd", with: "")
        guard !normalized.isEmpty else {
            throw ExposureCalculatorError.emptyND
        }

        guard let ndFactor = Double(normalized) else {
            throw ExposureCalculatorError.invalidND
        }

        guard ndFactor > 0 else {
            throw ExposureCalculatorError.nonPositiveND
        }

        return ndFactor
    }

    func calculate(baseShutterSeconds: Double, ndFactor: Double) throws -> Double {
        guard baseShutterSeconds > 0 else {
            throw ExposureCalculatorError.nonPositiveBaseShutter
        }

        guard ndFactor > 0 else {
            throw ExposureCalculatorError.nonPositiveND
        }

        let shutterStop = try shutterStopOffset(for: baseShutterSeconds)
        let ndStop = try ndStops(for: ndFactor)
        let result = pow(2, shutterStop + ndStop)
        guard result.isFinite else {
            throw ExposureCalculatorError.overflow
        }

        return result
    }

    func ndStops(for ndFactor: Double) throws -> Double {
        guard ndFactor.isFinite else {
            throw ExposureCalculatorError.invalidND
        }

        guard ndFactor > 0 else {
            throw ExposureCalculatorError.nonPositiveND
        }

        let roundedFactor = ndFactor.rounded()
        if abs(roundedFactor - ndFactor) < 0.0001,
           let mappedStop = ndStopMappings[roundedFactor] {
            return mappedStop
        }

        let computedStop = log2(ndFactor)
        guard computedStop.isFinite else {
            throw ExposureCalculatorError.overflow
        }

        return computedStop
    }

    func shutterStopOffset(for seconds: Double) throws -> Double {
        guard seconds.isFinite else {
            throw ExposureCalculatorError.invalidBaseShutter
        }

        guard seconds > 0 else {
            throw ExposureCalculatorError.nonPositiveBaseShutter
        }

        if seconds >= 1 {
            let computedStop = log2(seconds)
            guard computedStop.isFinite else {
                throw ExposureCalculatorError.overflow
            }
            return computedStop
        }

        guard let nearest = subsecondShutterStops.min(by: { lhs, rhs in
            abs(lhs.seconds - seconds) < abs(rhs.seconds - seconds)
        }) else {
            throw ExposureCalculatorError.invalidBaseShutter
        }

        return nearest.stopOffset
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
}
