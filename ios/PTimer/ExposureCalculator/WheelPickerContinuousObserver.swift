// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UIKit

/// `WheelPickerContinuousObserver` is a UIKit bridge that lets SwiftUI's
/// wheel picker emit drag-state callbacks (`onChange`) and live-preview
/// updates while the user spins the wheel, before the gesture commits
/// to a value.
///
/// Used ONLY by the Base Shutter wheel (`ShutterSelectionRow` in
/// Screen.swift). The ND wheels moved to the OWNED picker
/// (`NDWheelPickerView`, PTIMER-199 v2) and no longer observe
/// through this bridge.

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
        /// The SwiftUI-side anchor this coordinator observes from.
        /// Kept so the display link can RE-LOCATE the picker when
        /// SwiftUI recreates the UIPickerView instance outside any
        /// layout pass of the anchor (observed after identity-move
        /// reorders) — a dead weak `pickerView` would otherwise
        /// leave the wheel permanently unobserved.
        private weak var observedView: UIView?
        private var panGestureRecognizers: [UIPanGestureRecognizer] = []

        /// Periodic pairing re-validation: geometric matching can
        /// transiently pair an observer with a NEIGHBOR's picker
        /// while wheels animate, and if the last SwiftUI render lands
        /// mid-flight the wrong pairing would otherwise stick,
        /// leaving the wheel unobserved. Re-running the match on a
        /// slow cadence heals any mispairing within a second.
        private var revalidateTicks = 0
        private let revalidateTickThreshold = 30
        private var displayLink: CADisplayLink?
        private var lastObservedRow: Int?
        private var isPanActive = false

        init(
            onSelectedRowChange: @escaping (Int) -> Void,
            onInteractionEnd: @escaping () -> Void
        ) {
            self.onSelectedRowChange = onSelectedRowChange
            self.onInteractionEnd = onInteractionEnd
        }

        func attachIfNeeded(from observedView: UIView) {
            self.observedView = observedView
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
            }
            // Re-scan on every layout pass, not just on a picker
            // change: UIPickerView RECREATES its internal pan
            // recognizers when it resizes (wheel count changes), which
            // silently orphans previously added targets.
            refreshPanObservationIfNeeded(on: picker)

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

        private func refreshPanObservationIfNeeded(on picker: UIPickerView) {
            // iOS moves the wheel's pan between internal views across
            // releases: directly on the picker historically, on
            // `UIPickerColumnView` / `UIPickerTableView` on current
            // builds. Hook every descendant pan — a given touch is
            // driven by exactly one of them.
            let pans = descendantPanGestureRecognizers(of: picker)
            guard pans != panGestureRecognizers else {
                return
            }
            detachPanObservation()
            for pan in pans {
                pan.addTarget(self, action: #selector(handlePanGestureChange(_:)))
            }
            panGestureRecognizers = pans
        }

        /// True when any hooked recognizer's view has left the window
        /// — the picker rebuilt its internals and our targets died
        /// with them. Cheap enough to poll from the display link.
        private var hooksAreStale: Bool {
            panGestureRecognizers.isEmpty
                || panGestureRecognizers.contains { $0.view?.window == nil }
        }

        private func detachPanObservation() {
            for pan in panGestureRecognizers {
                pan.removeTarget(self, action: #selector(handlePanGestureChange(_:)))
            }
            panGestureRecognizers = []
        }

        private func descendantPanGestureRecognizers(of view: UIView) -> [UIPanGestureRecognizer] {
            var found = (view.gestureRecognizers ?? [])
                .compactMap { $0 as? UIPanGestureRecognizer }
            for subview in view.subviews {
                found.append(contentsOf: descendantPanGestureRecognizers(of: subview))
            }
            return found
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
            // The picker can rebuild its internal recognizers OUTSIDE
            // a layout pass of the observation view (e.g. at the end
            // of a width-change animation); re-hook as soon as the
            // current hooks go stale so the next touch is observed.
            if pickerView == nil || pickerView?.window == nil {
                // The picker instance died or left the hierarchy
                // (SwiftUI recreates pickers around identity-move
                // reorders): re-locate from the anchor.
                if let observedView, observedView.window != nil {
                    attachIfNeeded(from: observedView)
                }
            } else if let pickerView, hooksAreStale {
                refreshPanObservationIfNeeded(on: pickerView)
            } else if !isPanActive {
                revalidateTicks += 1
                if revalidateTicks >= revalidateTickThreshold {
                    revalidateTicks = 0
                    if let observedView, observedView.window != nil {
                        attachIfNeeded(from: observedView)
                    }
                }
            }
            emitSelectionIfNeeded()
        }

        @objc
        private func handlePanGestureChange(_ gestureRecognizer: UIPanGestureRecognizer) {
            // A stale hook can deliver events from a recognizer that
            // now belongs to a DIFFERENT (reused) picker; acting on
            // them would fire against the wrong wheel.
            guard let pickerView,
                  gestureRecognizer.view?.isDescendant(of: pickerView) == true else {
                return
            }
            switch gestureRecognizer.state {
            case .began:
                isPanActive = true

            case .ended, .cancelled, .failed:
                isPanActive = false
                onInteractionEnd()

            default:
                break
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
