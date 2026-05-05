import Foundation

struct ExposureCalculationResult: Equatable {
    let baseShutterSeconds: Double
    let ndStep: NDStep
    let resultShutterSeconds: Double

    init(
        baseShutterSeconds: Double,
        ndStep: NDStep,
        resultShutterSeconds: Double
    ) {
        self.baseShutterSeconds = baseShutterSeconds
        self.ndStep = ndStep
        self.resultShutterSeconds = resultShutterSeconds
    }

    /// Convenience initializer for whole-stop callers — wraps the
    /// integer `stop` in a whole-stop `NDStep` so the legacy
    /// `(baseShutterSeconds:, stop:, resultShutterSeconds:)` constructor
    /// keeps working byte-for-byte after PTIMER-80 routes the model
    /// state through `NDStep`.
    init(
        baseShutterSeconds: Double,
        stop: Int,
        resultShutterSeconds: Double
    ) {
        self.init(
            baseShutterSeconds: baseShutterSeconds,
            ndStep: NDStep(stops: Double(stop)),
            resultShutterSeconds: resultShutterSeconds
        )
    }

    /// Whole-stop view of the ND input. Returns the rounded integer for
    /// any fractional `ndStep`; callers that need the exact fractional
    /// identity must read `ndStep` directly.
    var stop: Int {
        ndStep.wholeStops ?? Int(ndStep.stops.rounded())
    }
}

struct TimeDisplay: Equatable {
    let primary: String
    let secondary: String
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
    static let stabilityEpsilon = 0.000_001
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
        try calculate(
            baseShutterSeconds: baseShutterSeconds,
            ndStep: NDStep(stops: Double(stop)),
            scaleMode: .fullStop
        )
    }

    /// Whole-stop ND overload. Preserves the legacy snap-to-full-stop
    /// behavior so any legacy full-stop caller stays byte-for-byte
    /// identical. The fractional-aware `scaleMode`-taking overload
    /// below is the canonical entry point: it gates snap on the
    /// active scale and the ND step's whole-stop status, so a
    /// 1/3-stop shutter input never collapses to the full-stop
    /// ladder when ND happens to be whole.
    func calculate(baseShutterSeconds: Double, ndStep: NDStep) throws -> Double {
        try calculate(
            baseShutterSeconds: baseShutterSeconds,
            ndStep: ndStep,
            scaleMode: .fullStop
        )
    }

    /// Computes the ND-adjusted shutter for a fractional-aware ND input
    /// in the given exposure-scale mode. Snap-to-full-stop applies
    /// only in `.fullStop` mode with a whole-stop ND; in
    /// `.oneThirdStop` mode the result is returned untouched so a
    /// 1/3-stop shutter value (e.g. `(1/30) · 2^(1/3)`) can survive
    /// even when ND is `0` or another whole stop.
    func calculate(
        baseShutterSeconds: Double,
        ndStep: NDStep,
        scaleMode: ExposureScaleMode
    ) throws -> Double {
        guard baseShutterSeconds > 0 else {
            throw ExposureCalculatorError.nonPositiveBaseShutter
        }

        guard ndStep.stops >= -Self.stabilityEpsilon else {
            throw ExposureCalculatorError.nonPositiveND
        }

        let result = baseShutterSeconds * pow(2.0, ndStep.stops)
        guard result.isFinite else {
            throw ExposureCalculatorError.overflow
        }

        let snapAllowed = scaleMode == .fullStop && ndStep.isWholeStop
        return snapAllowed ? snapToFullStop(result) : result
    }

    func formatShutter(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else {
            return "-"
        }

        return formatRawSeconds(seconds)
    }

    func formatTimeDisplay(_ seconds: Double) -> TimeDisplay {
        let safeSeconds = normalizeDuration(seconds)
        return TimeDisplay(
            primary: formatExtendedClock(safeSeconds),
            secondary: formatRawDurationSeconds(safeSeconds)
        )
    }

    func formatExtendedClock(_ seconds: Double) -> String {
        let safeSeconds = normalizeDuration(seconds)

        if safeSeconds < 1 {
            return "\(trimmedMilliseconds(safeSeconds))s"
        }

        if safeSeconds < 60 {
            return shortSecondsText(safeSeconds)
        }

        let secondsPerMinute = 60
        let secondsPerHour = 60 * secondsPerMinute
        let secondsPerDay = 24 * secondsPerHour
        let secondsPerMonth = 30 * secondsPerDay
        let secondsPerYear = 365 * secondsPerDay

        let years = Int(safeSeconds / Double(secondsPerYear))
        var remainder = safeSeconds - (Double(years) * Double(secondsPerYear))
        let months = Int(remainder / Double(secondsPerMonth))
        remainder -= Double(months) * Double(secondsPerMonth)
        let days = Int(remainder / Double(secondsPerDay))
        remainder -= Double(days) * Double(secondsPerDay)
        let hours = Int(remainder / Double(secondsPerHour))
        remainder -= Double(hours) * Double(secondsPerHour)
        let minutes = Int(remainder / Double(secondsPerMinute))
        remainder -= Double(minutes) * Double(secondsPerMinute)
        let secondText = formattedClockSeconds(remainder)

        if years > 0 {
            return formatDatePrefix(
                years: years,
                months: months,
                days: days,
                timeText: String(format: "%02d:%02d:%@", hours, minutes, secondText)
            )
        }

        if months > 0 {
            return formatDatePrefix(
                years: 0,
                months: months,
                days: days,
                timeText: String(format: "%02d:%02d:%@", hours, minutes, secondText)
            )
        }

        if days > 0 {
            return formatDatePrefix(
                years: 0,
                months: 0,
                days: days,
                timeText: String(format: "%02d:%02d:%@", hours, minutes, secondText)
            )
        }

        if safeSeconds >= Double(secondsPerHour) {
            let totalHours = Int(safeSeconds / Double(secondsPerHour))
            return String(format: "%02d:%02d:%@", totalHours, minutes, secondText)
        }

        if safeSeconds >= Double(secondsPerMinute) {
            return String(format: "%02d:%@", minutes, secondText)
        }

        return "00:\(secondText)"
    }

    private func formatRawSeconds(_ seconds: Double) -> String {
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

    private func formatRawDurationSeconds(_ seconds: Double) -> String {
        let normalized = normalizeDuration(seconds)

        if isEffectivelyInteger(normalized) {
            return "\(Int(normalized.rounded()))s"
        }

        return "\(trimmedMilliseconds(normalized))s"
    }

    private func normalizeDuration(_ seconds: Double) -> Double {
        guard seconds.isFinite else {
            return 0
        }

        let clamped = max(0, seconds)
        return clamped < Self.stabilityEpsilon ? 0 : clamped
    }

    private func formattedClockSeconds(_ seconds: Double) -> String {
        if abs(seconds.rounded() - seconds) < 0.0001 {
            return String(format: "%02d", Int(seconds.rounded()))
        }

        let wholeSeconds = Int(seconds)
        let milliseconds = Int(((seconds - Double(wholeSeconds)) * 1_000).rounded())

        if milliseconds == 1_000 {
            return String(format: "%02d", wholeSeconds + 1)
        }

        return String(format: "%02d.%03d", wholeSeconds, milliseconds)
    }

    private func trimmedMilliseconds(_ seconds: Double) -> String {
        let raw = String(format: "%.3f", (seconds * 1_000).rounded() / 1_000)
        return raw.replacingOccurrences(
            of: #"(\.\d*?[1-9])0+$|\.0+$"#,
            with: "$1",
            options: .regularExpression
        )
    }

    private func shortSecondsText(_ seconds: Double) -> String {
        if isEffectivelyInteger(seconds) {
            return "\(Int(seconds.rounded()))s"
        }

        return "\(trimmedMilliseconds(seconds))s"
    }

    private func formatDatePrefix(
        years: Int,
        months: Int,
        days: Int,
        timeText: String
    ) -> String {
        var prefixParts: [String] = []

        if years > 0 {
            prefixParts.append("\(years)y")
        }

        if months > 0 {
            prefixParts.append("\(months)mo")
        }

        if days > 0 {
            prefixParts.append("\(days)d")
        }

        let prefix = prefixParts.joined(separator: " ")
        return prefix.isEmpty ? timeText : "\(prefix) \(timeText)"
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
        let normalized = normalizeDuration(value)
        guard normalized > 0 else {
            return normalized
        }

        if normalized <= 30 + Self.stabilityEpsilon {
            return Self.fullStopShutterSpeeds.min(
                by: { abs($0 - normalized) < abs($1 - normalized) }
            ) ?? normalized
        }

        if normalized < 64 - Self.stabilityEpsilon {
            return abs(normalized - 30) <= abs(64 - normalized) ? 30 : 64
        }

        let lowerExponent = floor(log2(normalized))
        let upperExponent = ceil(log2(normalized))
        let lower = pow(2.0, lowerExponent)
        let upper = pow(2.0, upperExponent)

        return abs(normalized - lower) <= abs(upper - normalized) ? lower : upper
    }

    func reconstructedStop(
        baseShutterSeconds: Double,
        resultShutterSeconds: Double,
        maxStop: Int = 64
    ) -> Int? {
        guard baseShutterSeconds.isFinite,
              resultShutterSeconds.isFinite,
              baseShutterSeconds > 0,
              resultShutterSeconds > 0,
              maxStop >= 0 else {
            return nil
        }

        var bestStop: Int?
        var bestDistance = Double.infinity

        for stop in 0...maxStop {
            guard let candidate = try? calculate(
                baseShutterSeconds: baseShutterSeconds,
                stop: stop
            ) else {
                continue
            }

            let distance = abs(candidate - resultShutterSeconds)
            if distance < bestDistance - Self.stabilityEpsilon {
                bestDistance = distance
                bestStop = stop
            } else if abs(distance - bestDistance) <= Self.stabilityEpsilon,
                      let currentBestStop = bestStop,
                      stop < currentBestStop {
                bestStop = stop
            }
        }

        return bestStop
    }

    private func roundedTenthsText(_ value: Double) -> String {
        let scaled = value * 10
        let rounded = floor(scaled + 0.5 - Self.stabilityEpsilon) / 10
        let text = String(format: "%.1f", rounded)
        return text.replacingOccurrences(of: ".0", with: "")
    }

    private func isEffectivelyInteger(_ value: Double) -> Bool {
        abs(value.rounded() - value) < Self.stabilityEpsilon
    }
}
