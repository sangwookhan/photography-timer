import SwiftUI
import UIKit

/// `WheelPickerContinuousObserver` is a UIKit bridge that lets SwiftUI's
/// wheel picker emit drag-state callbacks (`onChange`) and live-preview
/// updates while the user spins the wheel, before the gesture commits
/// to a value. Extracted from `ExposureCalculatorScreen.swift` so the
/// screen does not carry a 220+ line UIViewRepresentable inline.
///
/// Used by `NDStopSelectionRow` and `ShutterSelectionRow` (both still
/// in Screen.swift) so the type is internal to the module rather than
/// file-private.

struct WheelPickerContinuousObserver: UIViewRepresentable {
    let onSelectedRowChange: (Int) -> Void
    let onInteractionEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSelectedRowChange: onSelectedRowChange,
            onInteractionEnd: onInteractionEnd
        )
    }

    func makeUIView(context: Context) -> ObservationView {
        let view = ObservationView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onMoveOrLayout = { observedView in
            context.coordinator.attachIfNeeded(from: observedView)
        }
        return view
    }

    func updateUIView(_ uiView: ObservationView, context: Context) {
        context.coordinator.onSelectedRowChange = onSelectedRowChange
        context.coordinator.onInteractionEnd = onInteractionEnd
        context.coordinator.attachIfNeeded(from: uiView)
    }

    static func dismantleUIView(_ uiView: ObservationView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        var onSelectedRowChange: (Int) -> Void
        var onInteractionEnd: () -> Void

        private weak var pickerView: UIPickerView?
        private weak var panGestureRecognizer: UIPanGestureRecognizer?
        private var displayLink: CADisplayLink?
        private var lastObservedRow: Int?

        init(
            onSelectedRowChange: @escaping (Int) -> Void,
            onInteractionEnd: @escaping () -> Void
        ) {
            self.onSelectedRowChange = onSelectedRowChange
            self.onInteractionEnd = onInteractionEnd
        }

        func attachIfNeeded(from observedView: UIView) {
            guard let picker = locatePicker(near: observedView) else {
                DispatchQueue.main.async { [weak self, weak observedView] in
                    guard let self, let observedView else {
                        return
                    }

                    self.attachIfNeeded(from: observedView)
                }
                return
            }

            if picker !== pickerView {
                detachPanObservation()
                pickerView = picker
                lastObservedRow = nil
                attachPanObservation(to: picker)
            }

            startDisplayLinkIfNeeded()
            emitSelectionIfNeeded()
        }

        func detach() {
            displayLink?.invalidate()
            displayLink = nil
            detachPanObservation()
            pickerView = nil
            lastObservedRow = nil
        }

        private func startDisplayLinkIfNeeded() {
            guard displayLink == nil else {
                return
            }

            let displayLink = CADisplayLink(target: self, selector: #selector(handleDisplayLinkTick))
            displayLink.preferredFramesPerSecond = 30
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }

        private func attachPanObservation(to picker: UIPickerView) {
            guard let panGestureRecognizer = picker.gestureRecognizers?
                .compactMap({ $0 as? UIPanGestureRecognizer })
                .first else {
                return
            }

            panGestureRecognizer.addTarget(self, action: #selector(handlePanGestureChange(_:)))
            self.panGestureRecognizer = panGestureRecognizer
        }

        private func detachPanObservation() {
            panGestureRecognizer?.removeTarget(self, action: #selector(handlePanGestureChange(_:)))
            panGestureRecognizer = nil
        }

        private func emitSelectionIfNeeded() {
            guard let pickerView else {
                return
            }

            let selectedRow = pickerView.selectedRow(inComponent: 0)
            guard selectedRow >= 0, selectedRow != lastObservedRow else {
                return
            }

            lastObservedRow = selectedRow
            onSelectedRowChange(selectedRow)
        }

        private func locatePicker(near observedView: UIView) -> UIPickerView? {
            var ancestor: UIView? = observedView

            while let currentAncestor = ancestor {
                let pickers = pickerViews(in: currentAncestor)
                if let matchedPicker = bestMatch(
                    in: pickers,
                    ancestor: currentAncestor,
                    observedView: observedView
                ) {
                    return matchedPicker
                }

                ancestor = currentAncestor.superview
            }

            return nil
        }

        private func pickerViews(in root: UIView) -> [UIPickerView] {
            var result: [UIPickerView] = []

            if let picker = root as? UIPickerView {
                result.append(picker)
            }

            for subview in root.subviews {
                result.append(contentsOf: pickerViews(in: subview))
            }

            return result
        }

        private func bestMatch(
            in pickers: [UIPickerView],
            ancestor: UIView,
            observedView: UIView
        ) -> UIPickerView? {
            let targetPoint = observedView.convert(
                CGPoint(x: observedView.bounds.midX, y: observedView.bounds.midY),
                to: ancestor
            )

            let matches = pickers.filter { picker in
                picker.convert(picker.bounds, to: ancestor).contains(targetPoint)
            }

            if let exactMatch = matches.min(by: { lhs, rhs in
                let lhsArea = pickerArea(lhs, in: ancestor)
                let rhsArea = pickerArea(rhs, in: ancestor)
                return lhsArea < rhsArea
            }) {
                return exactMatch
            }

            return pickers.min(by: { lhs, rhs in
                distanceSquared(from: lhs, to: targetPoint, in: ancestor)
                    < distanceSquared(from: rhs, to: targetPoint, in: ancestor)
            })
        }

        private func pickerArea(_ picker: UIPickerView, in ancestor: UIView) -> CGFloat {
            let frame = picker.convert(picker.bounds, to: ancestor)
            return frame.width * frame.height
        }

        private func distanceSquared(
            from picker: UIPickerView,
            to targetPoint: CGPoint,
            in ancestor: UIView
        ) -> CGFloat {
            let frame = picker.convert(picker.bounds, to: ancestor)
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let dx = center.x - targetPoint.x
            let dy = center.y - targetPoint.y
            return (dx * dx) + (dy * dy)
        }

        @objc
        private func handleDisplayLinkTick() {
            emitSelectionIfNeeded()
        }

        @objc
        private func handlePanGestureChange(_ gestureRecognizer: UIPanGestureRecognizer) {
            if gestureRecognizer.state == .ended
                || gestureRecognizer.state == .cancelled
                || gestureRecognizer.state == .failed {
                onInteractionEnd()
            }
        }
    }

    final class ObservationView: UIView {
        var onMoveOrLayout: ((UIView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onMoveOrLayout?(self)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            onMoveOrLayout?(self)
        }
    }
}
