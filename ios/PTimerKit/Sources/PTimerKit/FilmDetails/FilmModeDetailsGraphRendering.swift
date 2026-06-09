import SwiftUI

/// FilmModeDetailsGraphRendering owns the path geometry and region
/// drawing for the reciprocity formula graph. Splitting it out of
/// `FilmModeDetailsGraphView.swift` keeps the graph's struct body
/// focused on layout composition while these helpers stay grouped
/// under one extension where the coordinate math is easy to read
/// alongside the regions and markers it drives.

extension FilmModeDetailsGraph {
    func graphGrid(in size: CGSize) -> Path {
        Path { path in
            let horizontalFractions: [CGFloat] = [0.25, 0.5, 0.75]
            let verticalFractions: [CGFloat] = [0.25, 0.5, 0.75]

            for fraction in horizontalFractions {
                let y = size.height * fraction
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }

            for fraction in verticalFractions {
                let x = size.width * fraction
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
    }

    func sourcePath(in size: CGSize) -> Path {
        Path { path in
            for (index, point) in graph.sourcePoints.enumerated() {
                let plotted = plottedPoint(for: point, in: size)
                if index == 0 {
                    path.move(to: plotted)
                } else {
                    path.addLine(to: plotted)
                }
            }
        }
    }

    func unsupportedRegion(
        startSeconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(startSeconds, within: graph.xRange, size: size.width)

        return Rectangle()
            .fill(theme.graph.unsupportedRegion.opacity(0.08))
            .frame(width: max(size.width - x, 0), height: size.height)
            .position(x: x + max(size.width - x, 0) / 2, y: size.height / 2)
    }

    func supportedRegion(
        endSeconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(endSeconds, within: graph.xRange, size: size.width)

        return Rectangle()
            .fill(theme.graph.supportedRegion.opacity(0.06))
            .frame(width: max(x, 0), height: size.height)
            .position(x: max(x, 0) / 2, y: size.height / 2)
    }

    /// Persistent pink band marking the metered-exposure region where
    /// the formula prediction sits outside the published manufacturer
    /// source range. Shown for converted formula profiles regardless
    /// of where the current input lands, so the user can always see
    /// which portion of the curve is past the published reference.
    func beyondSourceRangeRegion(
        startSeconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(startSeconds, within: graph.xRange, size: size.width)

        return Rectangle()
            .fill(theme.graph.beyondSourceRegion.opacity(0.10))
            .frame(width: max(size.width - x, 0), height: size.height)
            .position(x: x + max(size.width - x, 0) / 2, y: size.height / 2)
    }

    func supportedBoundary(
        at seconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(seconds, within: graph.xRange, size: size.width)

        return Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        .stroke(theme.graph.guideLine.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
    }

    /// Light-green band covering the no-correction shutter range —
    /// e.g. Provia 100F's 0…128 s. Marks the policy zone where
    /// adjusted shutter equals corrected exposure (Tc = Tm) so the
    /// user reads the area under no-correction guidance, distinct
    /// from the predicted formula segment past the threshold.
    ///
    /// Log-scale graph cannot plot 0 seconds directly. The
    /// no-correction band is intentionally drawn from the visual
    /// leading edge of the plot to represent 0 through the
    /// no-correction threshold, while internal coordinates use
    /// the graph's positive lower bound. The fill rectangle
    /// starts at pixel x = 0 (the plot's leading edge) regardless
    /// of `xRange.lowerBound`, so the band visually reads as
    /// "from 0 to threshold" without exposing the positive
    /// lower-bound value as a user-visible no-correction start.
    func noCorrectionRegion(
        endSeconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(endSeconds, within: graph.xRange, size: size.width)

        return Rectangle()
            .fill(theme.graph.noCorrectionRegion.opacity(0.10))
            .frame(width: max(x, 0), height: size.height)
            .position(x: max(x, 0) / 2, y: size.height / 2)
    }

    /// Dashed vertical at the no-correction upper edge. Uses a tighter
    /// dash than the supported-range boundary so the two boundaries
    /// read distinctly when a profile (e.g. Provia 100F) carries both
    /// a 128 s threshold and a 480 s formula upper bound.
    func noCorrectionBoundary(
        at seconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(seconds, within: graph.xRange, size: size.width)

        return Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        .stroke(theme.graph.noCorrectionRegion.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
    }

    /// Small open green rings (with attached labels) drawn over the
    /// formula curve for each manufacturer source-reference point.
    /// The ring is roughly half the size of the current-result blue
    /// dot so visual priority always sits with the current result,
    /// not the static reference. The label hugs the ring (right
    /// above by default, beside it as a fallback) so the "240s" tag
    /// reads as a piece of the marker rather than a stray annotation.
    @ViewBuilder
    func sourceReferenceMarkers(in size: CGSize) -> some View {
        ZStack {
            ForEach(Array(graph.sourceReferenceMarkers.enumerated()), id: \.offset) { _, marker in
                let plotted = plottedPoint(for: marker.point, in: size)
                let labelPosition = sourceReferenceLabelPosition(
                    for: plotted,
                    in: size
                )

                Circle()
                    .fill(theme.surface)
                    .frame(width: 6, height: 6)
                    .overlay {
                        Circle()
                            .stroke(theme.graph.sourceReference, lineWidth: 1)
                    }
                    .position(plotted)

                Text(marker.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.graph.sourceReference)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 0.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(theme.surface.opacity(0.9))
                    )
                    .fixedSize()
                    .position(labelPosition)
            }
        }
    }

    /// Anchors a source-reference label tight against its small
    /// green ring. The label sits directly above the marker by
    /// default so it reads as part of the marker; it falls back to
    /// directly beside the marker when the marker hugs the top
    /// edge, and it gets pushed inward at the plot's right edge so
    /// the text never clips. The compact offset prevents the label
    /// from drifting onto the formula curve or into the area where
    /// the current-result blue dot could be misread as the labeled
    /// point.
    func sourceReferenceLabelPosition(
        for plotted: CGPoint,
        in size: CGSize
    ) -> CGPoint {
        let verticalOffset: CGFloat = 10
        let sideOffset: CGFloat = 14
        let topGuard: CGFloat = verticalOffset + 6
        let edgePadding: CGFloat = 18

        if plotted.y < topGuard {
            // Marker pinned near the top — place the label beside
            // the marker instead of below, so it does not float
            // onto the curve.
            let x: CGFloat
            if plotted.x + sideOffset + edgePadding > size.width {
                x = max(plotted.x - sideOffset, edgePadding)
            } else {
                x = plotted.x + sideOffset
            }
            return CGPoint(x: x, y: plotted.y)
        }

        let clampedX = max(edgePadding, min(plotted.x, size.width - edgePadding))
        return CGPoint(x: clampedX, y: plotted.y - verticalOffset)
    }

    /// Red dashed vertical at the manufacturer not-recommended
    /// boundary (e.g. Provia 100F's 480 s). Stays visually distinct
    /// from the neutral supported-range boundary so the user reads it
    /// as a stop-signal, not as a generic upper bound.
    func notRecommendedBoundary(
        at seconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(seconds, within: graph.xRange, size: size.width)

        return Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        .stroke(theme.graph.notRecommendedBoundary.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
    }

    func shouldSuppressSupportedBoundary(at seconds: Double) -> Bool {
        guard let notRecommendedBoundarySeconds = graph.notRecommendedBoundarySeconds else {
            return false
        }
        let supportedLog = log10(max(seconds, 0.000_001))
        let boundaryLog = log10(max(notRecommendedBoundarySeconds, 0.000_001))
        return abs(supportedLog - boundaryLog) < 0.02
    }

    @ViewBuilder
    func currentPointGuide(
        for currentPoint: FilmModeDetailsGraphCurrentPoint,
        in size: CGSize
    ) -> some View {
        EmptyView()
    }

    func currentInputGuideOnly(
        currentMeteredExposureSeconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(currentMeteredExposureSeconds, within: graph.xRange, size: size.width)

        return ZStack {
            Rectangle()
                .fill(theme.graph.currentInputGuide.opacity(0.08))
                .frame(width: 14, height: size.height)
                .position(x: x, y: size.height / 2)

            Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            .stroke(theme.graph.currentInputGuide.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 5]))
        }
    }

    /// Every in-range current result on the formula graph is a filled
    /// blue dot regardless of policy basis (no-correction,
    /// formula-derived, beyond-source-range). The status line, region
    /// shading, and source-reference markers carry the state-specific
    /// meaning; the current marker stays one consistent shape so it
    /// never reads as a source reference.
    func currentPointMarker(
        for currentPoint: FilmModeDetailsGraphCurrentPoint,
        in size: CGSize
    ) -> some View {
        let plotted = plottedPoint(for: currentPoint.point, in: size)

        return Circle()
            .fill(theme.graph.currentResultPoint)
            .frame(width: 13, height: 13)
            .overlay {
                Circle()
                    .stroke(theme.surface, lineWidth: 2)
            }
            .position(plotted)
    }

    /// Edge-anchored orange triangle that signals the current
    /// result sits outside the visible graph range. The triangle's
    /// orientation matches whether the value spilled past the right
    /// edge (beyond visible) or the left edge (below visible).
    @ViewBuilder
    func outsideVisibleRangeIndicator(in size: CGSize) -> some View {
        if graph.isBeyondVisibleRange {
            FilmModeDetailsGraphOutsideRangeTriangle()
                .fill(theme.graph.outOfRangeMarker)
                .frame(width: 14, height: 12)
                .overlay { FilmModeDetailsGraphOutsideRangeTriangle().stroke(theme.surface, lineWidth: 2) }
                .rotationEffect(.degrees(90))
                .position(x: size.width - 10, y: size.height / 2)
                .accessibilityIdentifier("film-mode-details-graph-outside-visible")
        } else if graph.isBelowVisibleRange {
            FilmModeDetailsGraphOutsideRangeTriangle()
                .fill(theme.graph.outOfRangeMarker)
                .frame(width: 14, height: 12)
                .overlay { FilmModeDetailsGraphOutsideRangeTriangle().stroke(theme.surface, lineWidth: 2) }
                .rotationEffect(.degrees(-90))
                .position(x: 10, y: size.height / 2)
                .accessibilityIdentifier("film-mode-details-graph-outside-visible")
        }
    }

    @ViewBuilder
    func yAxisTickLabels(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(graph.yAxisTicks) { tick in
                Text(tick.label)
                    .font(.caption2)
                    .foregroundStyle(theme.graph.textSecondary)
                    .frame(width: yTickLabelInset, alignment: .leading)
                    .position(
                        x: yTickLabelInset / 2,
                        y: size.height - scaledValue(tick.value, within: graph.yRange, size: size.height)
                    )
            }
        }
    }

    func xAxisTickLabels(in width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(graph.xAxisTicks) { tick in
                Text(tick.label)
                    .font(.caption2)
                    .foregroundStyle(theme.graph.textSecondary)
                    .position(
                        x: scaledValue(tick.value, within: graph.xRange, size: width),
                        y: 7
                    )
            }
        }
    }

    func plottedPoint(
        for point: FilmModeDetailsGraphPoint,
        in size: CGSize
    ) -> CGPoint {
        let x = scaledValue(
            point.meteredExposureSeconds,
            within: graph.xRange,
            size: size.width
        )
        let y = size.height - scaledValue(
            point.correctedExposureSeconds,
            within: graph.yRange,
            size: size.height
        )

        return CGPoint(x: x, y: y)
    }

    func scaledValue(
        _ value: Double,
        within range: ClosedRange<Double>,
        size: CGFloat
    ) -> CGFloat {
        let lowerLog = log10(range.lowerBound)
        let upperLog = log10(range.upperBound)
        let valueLog = log10(max(value, range.lowerBound))
        let progress = (valueLog - lowerLog) / max(upperLog - lowerLog, 0.000_001)
        return CGFloat(progress) * size
    }
}

private struct FilmModeDetailsGraphOutsideRangeTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
