// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UIKit

/// Own the Base picker delegate: programmatic restores/reloads never count as
/// manual commits. Live rows come from rendered centers; final commitment
/// waits for touch, scrolling and snap geometry to be quiet together.
struct BaseWheelPickerView<RowContent: View>: UIViewRepresentable {
    let steps: [Double]
    let selected: Double
    let rowHeight: CGFloat
    let renderingKey: AnyHashable
    @ViewBuilder let rowContent: (Double) -> RowContent
    let onBegin: () -> Void
    let onPreview: (Double) -> Void
    let onCommit: (Double) -> Void
    var accessibilityValue: (Double) -> String = { String($0) }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        let touch = BaseWheelTouchRecognizer(target: context.coordinator, action: #selector(Coordinator.touchChanged(_:)))
        touch.cancelsTouchesInView = false
        touch.delegate = context.coordinator
        picker.addGestureRecognizer(touch)
        context.coordinator.attach(picker)
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) { context.coordinator.update(self, picker: picker) }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIPickerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 100, height: proposal.height ?? 160)
    }

    static func dismantleUIView(_ uiView: UIPickerView, coordinator: Coordinator) { coordinator.detach() }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate, UIGestureRecognizerDelegate {
        private var view: BaseWheelPickerView
        private weak var picker: UIPickerView?
        private var link: CADisplayLink?
        private var touching = false
        private var interacting = false
        private var locked = false
        private var lastGeometry: [CGFloat] = []
        private var quietTicks = 0
        private var lastRow: Int?
        private var needsRenderingReload = false

        init(_ view: BaseWheelPickerView) { self.view = view }

        func attach(_ picker: UIPickerView) {
            self.picker = picker
            restore(picker)
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFramesPerSecond = 30
            link.isPaused = true
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func detach() { link?.invalidate(); link = nil; picker = nil }

        func update(_ new: BaseWheelPickerView, picker: UIPickerView) {
            let externalChange = new.steps != view.steps || new.selected != view.selected
            let renderingChanged = new.renderingKey != view.renderingKey || new.rowHeight != view.rowHeight
            needsRenderingReload = needsRenderingReload || renderingChanged
            view = new
            // Never enforce the old committed binding during drag/deceleration.
            if externalChange { interacting = false; touching = false; link?.isPaused = true; restore(picker) } else if needsRenderingReload, !interacting { restore(picker) }
        }

        private func restore(_ picker: UIPickerView) {
            locked = true
            picker.reloadAllComponents()
            if let row = view.steps.firstIndex(of: view.selected) { picker.selectRow(row, inComponent: 0, animated: false) }
            picker.accessibilityValue = view.accessibilityValue(view.selected)
            locked = false
            needsRenderingReload = false
            lastRow = nil
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { view.steps.count }
        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { view.rowHeight }
        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat { max(1, pickerView.bounds.width) }
        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing: UIView?) -> UIView {
            guard view.steps.indices.contains(row) else { return UIView() }
            if let host = reusing as? BaseWheelRowHost<RowContent> {
                host.accessibilityLabel = view.accessibilityValue(view.steps[row])
                host.row = row
                host.controller.rootView = view.rowContent(view.steps[row])
                return host
            }
            let host = BaseWheelRowHost(row: row, content: view.rowContent(view.steps[row]))
            host.accessibilityLabel = view.accessibilityValue(view.steps[row])
            return host
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            guard !locked, view.steps.indices.contains(row) else { return }
            // VoiceOver can commit without a touch recognizer. It uses the
            // same final-snap barrier, never a programmatic binding observer.
            if !interacting { begin() }
            quietTicks = 0
        }

        func begin() {
            interacting = true
            quietTicks = 0
            lastGeometry = []
            lastRow = nil
            link?.isPaused = false
            view.onBegin()
        }

        @objc func touchChanged(_ recognizer: UIGestureRecognizer) {
            switch recognizer.state {
            case .began: touching = true; begin()
            case .ended, .cancelled, .failed: touching = false; quietTicks = 0
            default: break
            }
        }

        /// Test seam uses the same geometry/scroll/delegate barrier as the
        /// display link. Continuous movement within one row resets the gate.
        func sample(row: Int, selectedRow: Int, geometry: [CGFloat], scrolling: Bool) {
            guard interacting, view.steps.indices.contains(row) else { return }
            if row != lastRow { lastRow = row; view.onPreview(view.steps[row]) }
            let stable = !geometry.isEmpty && geometry == lastGeometry
            lastGeometry = geometry
            if !touching, !scrolling, stable, row == selectedRow { quietTicks += 1 } else { quietTicks = 0 }
            guard quietTicks >= 15 else { return }
            interacting = false
            link?.isPaused = true
            picker?.accessibilityValue = view.accessibilityValue(view.steps[row])
            view.onCommit(view.steps[row])
            if needsRenderingReload, let picker { restore(picker) }
        }

        @objc func tick() {
            guard let picker, interacting else { return }
            var rows: [(Int, CGFloat)] = []
            var scrolling = false
            func visit(_ current: UIView) {
                if let scroll = current as? UIScrollView {
                    scrolling = scrolling || scroll.isTracking || scroll.isDragging || scroll.isDecelerating
                }
                if current.layer.animationKeys()?.isEmpty == false { scrolling = true }
                if let host = current as? BaseWheelRowHost<RowContent> {
                    rows.append((host.row, host.convert(host.bounds, to: picker).midY))
                } else { current.subviews.forEach(visit) }
            }
            visit(picker)
            rows.sort { $0.0 < $1.0 }
            let selected = picker.selectedRow(inComponent: 0)
            guard let nearest = rows.min(by: { abs($0.1 - picker.bounds.midY) < abs($1.1 - picker.bounds.midY) }) else { return }
            // Actual centers must be motionless and the final row centered;
            // a stable selectedRow by itself says nothing about momentum.
            let centered = abs(nearest.1 - picker.bounds.midY) <= 1
            sample(row: nearest.0, selectedRow: selected, geometry: rows.flatMap { [CGFloat($0.0), $0.1] }, scrolling: scrolling || !centered)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}

private final class BaseWheelTouchRecognizer: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { state = .began }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { state = .changed }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { state = .ended }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .cancelled }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

private final class BaseWheelRowHost<Content: View>: UIView {
    var row: Int
    let controller: UIHostingController<Content>
    init(row: Int, content: Content) {
        self.row = row
        controller = UIHostingController(rootView: content)
        super.init(frame: .zero)
        controller.view.backgroundColor = .clear
        addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
