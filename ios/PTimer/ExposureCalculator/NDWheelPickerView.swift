// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerCore
import SwiftUI
import UIKit

/// The OWNED ND wheel picker (PTIMER-199 architecture v2): a
/// `UIViewRepresentable` that creates and keeps its own
/// `UIPickerView`, with the delegate/dataSource under app control.
///
/// This replaces the SwiftUI `Picker(.wheel)` + observation-layer
/// combination for ND wheels. Owning the instance restores the
/// meaning of the delegate events: programmatic `selectRow` never
/// calls the delegate (UIKit contract), reloads happen only under an
/// explicit lock, and the instance survives identity-move reorders
/// (verified in the R2 spike) — so a `didSelectRow` arriving outside
/// the lock under the current generation is a user selection by
/// construction. The ViewModel's state machine remains the single
/// decision point; this type only MEASURES low-level input (row
/// changes, touch state, overscroll distance) and stamps every event
/// with the generation it was issued under.
struct NDWheelPickerView<RowContent: View>: UIViewRepresentable {
    /// Ladder of selectable values, top-truncated to the wheel's
    /// remaining budget. Changing it triggers a locked reload.
    let steps: [NDStep]
    /// The wheel's DISPLAY value (pending selection during an open
    /// set commit, committed value otherwise).
    let selectedStep: NDStep
    /// While false (the wheel's motion has not concluded) the
    /// representable never enforces the displayed row, so it cannot
    /// fight a finger or a decelerating wheel.
    let isResolved: Bool
    /// False during RESHAPING: input is BLOCKED at the view level
    /// (v2 contract 2 — never silently dropped).
    let isInputEnabled: Bool
    /// Generation stamp attached to every emitted event (contract 4).
    let generation: Int
    /// Opaque key for the row RENDERING inputs (notation mode, wheel
    /// count); a change triggers a locked reload even when `steps`
    /// stayed equal.
    let rowConfiguration: AnyHashable
    let rowHeight: CGFloat
    @ViewBuilder let rowContent: (NDStep) -> RowContent

    /// Low-level measurements, generation-stamped. The parent view
    /// adds the wheel identity and forwards to the ViewModel.
    let onRowObserved: (NDStep, Int) -> Void
    let onSelected: (NDStep, Int) -> Void
    let onTouchBegan: (Int) -> Void
    let onTouchEnded: () -> Void
    let onOverscrollReleased: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(view: self)
    }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.clipsToBounds = true
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator

        // Own pan recognizer: touch-state (blocking-only signal) and
        // the overscroll-past-zero gesture. Recognizing alongside the
        // picker's internal scrolling; never steals or replaces it.
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        picker.addGestureRecognizer(pan)

        context.coordinator.attach(to: picker)
        return picker
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.update(from: self, picker: picker)
    }

    /// UIPickerView's intrinsic size is ~320×216 and it ignores the
    /// proposed size by default — honor SwiftUI's proposal so 1–4
    /// wheels share the row at the layout's widths.
    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: UIPickerView, context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? uiView.intrinsicContentSize.width,
            height: proposal.height ?? uiView.intrinsicContentSize.height
        )
    }

    static func dismantleUIView(_ picker: UIPickerView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIPickerViewDataSource,
        UIPickerViewDelegate, UIGestureRecognizerDelegate {
        private var view: NDWheelPickerView
        private weak var picker: UIPickerView?
        private var displayLink: CADisplayLink?

        /// Reload lock: `didSelectRow` and row polling are inert
        /// while the app itself mutates the picker (reload or
        /// programmatic selection), so reload artifacts can never
        /// masquerade as user input.
        private var isPerformingProgrammaticChange = false
        private var lastObservedRow: Int?
        private var isTouchActive = false

        /// Overscroll gesture state (§4.2.3): armed only when the
        /// touch BEGINS with the wheel settled on a 0-stop row.
        private var isOverscrollArmed = false
        private var isOverscrollPastThreshold = false
        private let overscrollThreshold: CGFloat = 34
        private let overscrollHaptic = UIImpactFeedbackGenerator(style: .medium)

        init(view: NDWheelPickerView) {
            self.view = view
        }

        func attach(to picker: UIPickerView) {
            self.picker = picker
            performProgrammaticChange {
                picker.reloadAllComponents()
                applySelection(on: picker, animated: false)
            }
            let link = CADisplayLink(target: self, selector: #selector(handleTick))
            link.preferredFramesPerSecond = 30
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func detach() {
            displayLink?.invalidate()
            displayLink = nil
            picker = nil
        }

        func update(from newView: NDWheelPickerView, picker: UIPickerView) {
            let stepsChanged = newView.steps != view.steps
            let renderingChanged = newView.rowConfiguration != view.rowConfiguration
            view = newView
            picker.isUserInteractionEnabled = newView.isInputEnabled
            if stepsChanged || renderingChanged {
                performProgrammaticChange {
                    picker.reloadAllComponents()
                    applySelection(on: picker, animated: false)
                }
                return
            }
            // Display re-sync (v2 §7): only a RESOLVED, untouched
            // wheel is ever snapped to its display value — this is
            // the explicit revert path for barrier-rejected wheels,
            // not a polling heuristic.
            if newView.isResolved, !isTouchActive {
                applySelection(on: picker, animated: true)
            }
        }

        private func applySelection(on picker: UIPickerView, animated: Bool) {
            guard let target = view.steps.firstIndex(of: view.selectedStep),
                  picker.selectedRow(inComponent: 0) != target else {
                return
            }
            performProgrammaticChange {
                picker.selectRow(target, inComponent: 0, animated: animated)
            }
            lastObservedRow = target
        }

        private func performProgrammaticChange(_ body: () -> Void) {
            let wasLocked = isPerformingProgrammaticChange
            isPerformingProgrammaticChange = true
            body()
            isPerformingProgrammaticChange = wasLocked
        }

        // MARK: UIPickerViewDataSource / Delegate

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            view.steps.count
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {
            view.rowHeight
        }

        func pickerView(
            _ pickerView: UIPickerView,
            viewForRow row: Int,
            forComponent component: Int,
            reusing reusingView: UIView?
        ) -> UIView {
            guard view.steps.indices.contains(row) else {
                return reusingView ?? UIView()
            }
            let content = view.rowContent(view.steps[row])
            if let cell = reusingView as? NDWheelRowHostView<RowContent> {
                cell.update(rootView: content)
                return cell
            }
            return NDWheelRowHostView(rootView: content)
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            guard !isPerformingProgrammaticChange,
                  view.steps.indices.contains(row) else {
                return
            }
            view.onSelected(view.steps[row], view.generation)
        }

        // MARK: Row polling (live preview)

        @objc private func handleTick() {
            guard let picker, !isPerformingProgrammaticChange else {
                return
            }
            let row = picker.selectedRow(inComponent: 0)
            guard row >= 0, row != lastObservedRow else {
                return
            }
            lastObservedRow = row
            guard view.steps.indices.contains(row) else {
                return
            }
            view.onRowObserved(view.steps[row], view.generation)
        }

        // MARK: Own pan (touch state + overscroll)

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began:
                isTouchActive = true
                view.onTouchBegan(view.generation)
                isOverscrollArmed = picker?.selectedRow(inComponent: 0) == 0
                    && view.steps.first?.stops == 0
                isOverscrollPastThreshold = false
                if isOverscrollArmed {
                    overscrollHaptic.prepare()
                }

            case .changed:
                guard isOverscrollArmed, let picker else {
                    return
                }
                guard picker.selectedRow(inComponent: 0) == 0 else {
                    isOverscrollArmed = false
                    isOverscrollPastThreshold = false
                    return
                }
                let isPast = pan.translation(in: picker).y >= overscrollThreshold
                if isPast, !isOverscrollPastThreshold {
                    overscrollHaptic.impactOccurred()
                }
                isOverscrollPastThreshold = isPast

            case .ended, .cancelled, .failed:
                let fired = isOverscrollArmed
                    && isOverscrollPastThreshold
                    && pan.state == .ended
                isOverscrollArmed = false
                isOverscrollPastThreshold = false
                isTouchActive = false
                view.onTouchEnded()
                if fired {
                    view.onOverscrollReleased(view.generation)
                }

            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

/// Reusable UIPickerView row hosting a SwiftUI row view, so the
/// owned picker renders pixel-identical rows to the previous SwiftUI
/// `Picker` implementation.
private final class NDWheelRowHostView<Content: View>: UIView {
    private let host: UIHostingController<Content>

    init(rootView: Content) {
        host = UIHostingController(rootView: rootView)
        super.init(frame: .zero)
        host.view.backgroundColor = .clear
        addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(rootView: Content) {
        host.rootView = rootView
    }
}
