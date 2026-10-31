// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Accessibility
import PTimerCore
import PTimerKit
import SwiftUI
import UIKit
import XCTest
@testable import PTimer

/// FILTER-A11Y-005 / FILTER-STACK-008: the one-row status region exposes
/// its leading text and the complete Total as two separate accessibility
/// elements, so Total is focusable directly without listening through the
/// source summary or item detail first. Hosted in a window so the real
/// UIKit accessibility tree SwiftUI produces is inspected.
@MainActor
final class FilterStatusRegionAccessibilityTests: XCTestCase {
    private let style = ExposureWorkspaceMainLayoutStyle(density: .regular)

    func testMixedSourceIdleSummaryAndTotalAreSeparateElements() throws {
        let summary = [
            FilterStatusSourceSummaryItem(source: .filterSet(FilterSetID(rawValue: "nisi")), name: "NiSi kit", count: 1, color: .red),
            FilterStatusSourceSummaryItem(source: .filterSet(FilterSetID(rawValue: "lee")), name: "Lee holder", count: 2, color: .green),
            FilterStatusSourceSummaryItem(source: .standard, name: "Standard", count: 1, color: nil),
        ]
        let content = FilterStatusRegionContent(
            primaryText: FilterStatusRegionPresenter.summaryText(summary),
            secondaryText: "Total 13 stops",
            isHeld: true,
            isSecondaryEmphasis: true,
            idleSourceSummary: summary
        )
        let host = try hosted(FilterStatusRegionView(content: content, occupiedSpaceCount: 2, style: style))
        defer { host.window.isHidden = true }

        let labels = try accessibilityLabels(in: host)
        let total = try XCTUnwrap(labels.first { $0 == "Total 13 stops" }, "Total is its own focusable element: \(labels)")
        let leading = try XCTUnwrap(labels.first { $0.hasPrefix("NiSi kit") }, "The leading summary is its own element: \(labels)")
        XCTAssertEqual(leading, "NiSi kit · Lee holder ×2 · Standard", "The leading element carries the complete summary.")
        XCTAssertFalse(leading.contains(total), "Total is not appended to the summary element.")
        XCTAssertEqual(labels.count, 2, "Exactly two elements, in leading-then-total order: \(labels)")
        XCTAssertEqual(labels, [leading, total])
    }

    func testMovingDetailAndTotalAreSeparateElements() throws {
        let content = FilterStatusRegionContent(
            primaryText: "Big Stopper · ND1000 · 10 stops",
            secondaryText: "Total 16 stops",
            isHeld: true
        )
        let host = try hosted(FilterStatusRegionView(content: content, occupiedSpaceCount: 2, style: style))
        defer { host.window.isHidden = true }

        let labels = try accessibilityLabels(in: host)
        XCTAssertEqual(labels, ["Big Stopper · ND1000 · 10 stops", "Total 16 stops"], "Held detail keeps the same two-element shape.")
    }

    func testRequiredNDMainKeepsPickerFramesAndProducesReviewImages() throws {
        for theme in [ColorScheme.light, .dark] {
            let coordinator = WorkspaceCoordinator(dependencies: ViewModelDependencyFactory.test(), isFilterStackOrderingSuspended: false)
            let vm = coordinator.viewModel
            vm.baseShutter = 1
            vm.setTargetShutter(1024)
            vm.startTargetShutterTimer()
            let running = try XCTUnwrap(vm.timers.first)
            XCTAssertEqual(running.duration, 1024)
            let screen = ExposureCalculatorScreen(coordinator: coordinator, bottomSheetStateStore: BottomSheetWorkspaceStateStore())
            let host = UIHostingController(rootView: screen.preferredColorScheme(theme))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
            let window = UIWindow(windowScene: scene)
            window.frame = scene.coordinateSpace.bounds
            window.windowLevel = .alert + 1
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                previousKeyWindow?.makeKey()
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))
            host.view.layoutIfNeeded()
            let ordinary = pickerFrames(in: host.view)
            XCTAssertFalse(ordinary.isEmpty)
            capture(host.view, name: "ordinary-\(theme)")
            vm.beginBaseShutterInteraction()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            host.view.layoutIfNeeded()
            XCTAssertEqual(vm.requiredNDGuidanceDisplayState?.valueText, "10")
            XCTAssertEqual(pickerFrames(in: host.view), ordinary, "Guidance cannot move or resize a picker")
            capture(host.view, name: "required-nd-\(theme)")
            let film = try XCTUnwrap(LaunchPresetFilmCatalogV2.films.first { $0.id == "foma-fomapan-100" })
            vm.selectPresetFilm(film)
            vm.setTargetShutter(4000)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            vm.beginBaseShutterInteraction()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            host.view.layoutIfNeeded()
            XCTAssertTrue(try XCTUnwrap(vm.requiredNDGuidanceDisplayState).isWarning)
            capture(host.view, name: "source-range-warning-\(theme)")
            vm.setTargetShutter(0.5)
            vm.beginBaseShutterInteraction()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            capture(host.view, name: "negative-attenuation-\(theme)")
            XCTAssertEqual(vm.timers.count, 1)
            XCTAssertEqual(vm.timers.first?.id, running.id)
            XCTAssertEqual(vm.timers.first?.basisSummary, running.basisSummary)
            XCTAssertEqual(vm.timers.first?.status, .running)
        }
    }

    func testRequiredNDExportsActualTotalAndReasonsAcrossSupportedTextSizesAndThemes() throws {
        let sizes: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge]
        let results: [RequiredNDResult] = [.value(stops: 10, beyondSourceRange: false),
            .value(stops: 10.3, beyondSourceRange: true), .unavailable(.multipleSolutions),
            .unavailable(.noQuantifiedInverse), .unavailable(.negativeAttenuation),
        ]
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for size in sizes {
            for theme in [ColorScheme.light, .dark] {
                for (index, result) in results.enumerated() {
                    let guidance = RequiredNDGuidanceDisplayState(result: result)
                    let region = FilterStatusRegionView(
                        content: .init(primaryText: "Long source summary", secondaryText: "Total 8 stops", isHeld: true),
                        occupiedSpaceCount: 4, style: style, requiredND: guidance,
                        guidancePhase: .tracking, guidanceGeneration: 1,
                        guidanceSourceSummary: [.init(source: .standard, name: "Long source summary", count: 3, color: nil)],
                        actualTotal: "Total 8 stops")
                    let host = UIHostingController(rootView: region.frame(width: 320)
                        .environment(\.dynamicTypeSize, size).preferredColorScheme(theme))
                    let window = UIWindow(windowScene: scene)
                    window.frame = CGRect(x: 0, y: 0, width: 360, height: 200)
                    window.windowLevel = .alert + 1
                    window.rootViewController = host
                    window.makeKeyAndVisible()
                    defer { window.isHidden = true }
                    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                    host.view.layoutIfNeeded()
                    var nodes: [NSObject] = []
                    func collectNodes(_ node: NSObject) {
                        if node.isAccessibilityElement { nodes.append(node); return }
                        (node.accessibilityElements as? [NSObject])?.forEach(collectNodes)
                        (node as? UIView)?.subviews.forEach(collectNodes)
                    }
                    collectNodes(host.view)
                    func identifier(_ node: NSObject) -> String? {
                        guard node.responds(to: NSSelectorFromString("accessibilityIdentifier")) else { return nil }
                        return node.value(forKey: "accessibilityIdentifier") as? String
                    }
                    let value = try XCTUnwrap(nodes.first { $0.accessibilityLabel == guidance.spokenValue },
                        "Rendered focus objects: \(nodes.map { [identifier($0) ?? "nil", $0.accessibilityLabel ?? "nil"].joined(separator: ": ") })")
                    XCTAssertEqual(nodes.filter { $0.accessibilityLabel == guidance.spokenValue }.count, 1)
                    XCTAssertFalse(nodes.contains { $0.accessibilityLabel == "Total 8 stops" }, "Hidden ordinary row adds no focus")
                    XCTAssertEqual(value.accessibilityLabel, guidance.spokenValue)
                    let customSelector = NSSelectorFromString("accessibilityCustomContent")
                    let exported = value.responds(to: customSelector) ? value.value(forKey: "accessibilityCustomContent") as? [AXCustomContent] : nil
                    let content = try XCTUnwrap(exported, "Focus class \(type(of: value)), responds to public custom content: \(value.responds(to: customSelector)); label=\(value.accessibilityLabel ?? "nil")")
                    XCTAssertTrue(content.contains { $0.label == "Current Total" && $0.value == "Total 8 stops" })
                    if let reason = guidance.reason {
                        XCTAssertTrue(nodes.contains { $0.accessibilityLabel == reason }, "Full reason remains readable to accessibility")
                    }
                    let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
                        host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "required-nd-\(size)-\(theme)-\(index)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testFinalCommitStartsTransitionAfterLiveInertiaWithoutLayoutChanges() throws {
        let transition = try transitionHost()
        let vm = transition.vm
        let host = transition.host
        let window = transition.window
        defer { window.isHidden = true }
        vm.beginBaseShutterInteraction()
        vm.updateLiveBaseShutter(2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let frames = pickerFrames(in: host.view)
        vm.releaseBaseShutterInteraction()
        vm.updateLiveBaseShutter(4)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(vm.requiredNDGuidancePhase, .tracking)
        XCTAssertEqual(vm.requiredNDGuidanceDisplayState?.valueText, "8")
        XCTAssertEqual(vm.baseShutter, 1)
        vm.baseShutter = 8
        let settlement = Date()
        vm.finishBaseShutterInteraction()
        XCTAssertEqual(vm.requiredNDGuidanceDisplayState?.valueText, "7")
        XCTAssertEqual(vm.requiredNDGuidancePhase, .crossfading)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(vm.requiredNDGuidanceDisplayState?.valueText, "7", "Final outgoing value survives the crossfade")
        while vm.requiredNDGuidancePhase != .ordinary, Date().timeIntervalSince(settlement) < 1 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        let duration = Date().timeIntervalSince(settlement)
        XCTAssertEqual(vm.requiredNDGuidancePhase, .ordinary)
        XCTAssertNil(vm.requiredNDGuidanceDisplayState)
        XCTAssertGreaterThanOrEqual(duration, 0.40)
        // Renderer completion delivery includes hosting/run-loop latency.
        // Verify visible out/in duration separately from recorded Main frames.
        XCTAssertLessThan(duration, 0.85)
        XCTAssertEqual(pickerFrames(in: host.view), frames)
        print("Required ND crossfade completion delivery: \(duration)s")
        vm.baseShutter = 4
        vm.finishBaseShutterInteraction()
        XCTAssertNil(vm.requiredNDGuidanceDisplayState)
    }

    func testReducedMotionRestoresOrdinaryWithoutWaitingForAReadingHold() throws {
        let model = RequiredNDGuidanceModel()
        let host = UIHostingController(rootView: ReducedMotionHarness(model: model))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        model.begin(base: 1, target: 1024, profile: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        model.release()
        model.settle(base: 1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(model.phase, .ordinary)
        XCTAssertNil(model.result)
    }

    func testInterruptedFadeRestoresFullOpacityAndIgnoresOldCompletion() throws {
        let model = RequiredNDGuidanceModel()
        let host = UIHostingController(rootView: OpacityHarness(model: model))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        for offset in [0.08, 0.35] {
            let phase = RequiredNDGuidanceModel.Phase.crossfading
            for invalidate in [false, true] {
                model.begin(base: 1, target: 1024, profile: nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                model.release()
                model.settle(base: 1)
                let deadline = Date().addingTimeInterval(1)
                while model.phase != phase, Date() < deadline {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.005))
                }
                XCTAssertEqual(model.phase, phase)
                RunLoop.main.run(until: Date().addingTimeInterval(offset))
                if invalidate {
                    model.invalidate()
                } else {
                    model.begin(base: 2, target: 1024, profile: nil)
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                let pixel = try XCTUnwrap(image.cgImage).cropping(to: CGRect(x: image.size.width * image.scale / 2,
                    y: image.size.height * image.scale / 2, width: 1, height: 1))
                let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(try XCTUnwrap(pixel), in: CGRect(x: 0, y: 0, width: 1, height: 1))
                let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
                if invalidate {
                    XCTAssertGreaterThan(bytes[0], 245, "Context restores the opaque ordinary layer")
                } else {
                    XCTAssertLessThan(bytes[0], 10, "Re-touch restores the opaque guidance layer")
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                XCTAssertEqual(model.phase, invalidate ? .ordinary : .tracking)
                if !invalidate { XCTAssertNotNil(model.result) }
            }
        }
    }

    func testBothStatusTextsHaveSimultaneousIntermediateBrightness() throws {
        let model = RequiredNDGuidanceModel()
        let host = UIHostingController(rootView: StatusRowHarness(model: model))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 360, height: 100)
        window.windowLevel = .alert + 1
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        model.begin(base: 1, target: 1024, profile: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let before = capturePixels(host.view, name: "crossfade-before")
        model.release()
        model.settle(base: 1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        let middle = capturePixels(host.view, name: "crossfade-middle")
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let after = capturePixels(host.view, name: "crossfade-after")
        XCTAssertEqual(model.phase, .ordinary)
        XCTAssertEqual(before.count, middle.count)
        XCTAssertEqual(before.count, after.count)
        var outgoing = 0
        var incoming = 0
        for index in stride(from: 0, to: before.count, by: 4) {
            let start = Int(before[index]); let mid = Int(middle[index]); let end = Int(after[index])
            let blue = Int(before[index + 2]) - start
            let midBlue = Int(middle[index + 2]) - mid
            if blue > 64 && end > 240 && midBlue > 5 && midBlue < blue - 5 { outgoing += 1 }
            if start > 240 && Int(before[index + 1]) > 240 && Int(before[index + 2]) > 240 &&
                end < 160 && mid > end + 5 && mid < 245 { incoming += 1 }
        }
        XCTAssertGreaterThan(outgoing, 5, "Outgoing blue glyph pixels have intermediate opacity")
        XCTAssertGreaterThan(incoming, 5, "Incoming Total glyph pixels brighten in the same frame")
    }

    private func capturePixels(_ view: UIView, name: String) -> [UInt8] {
        let image = UIGraphicsImageRenderer(size: view.bounds.size).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let cgImage = image.cgImage!
        var bytes = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return bytes
    }

    private struct StatusRowHarness: View {
        @ObservedObject var model: RequiredNDGuidanceModel
        var body: some View {
            FilterStatusRegionView(content: .init(primaryText: nil, secondaryText: "Total 2 stops", isHeld: true),
                occupiedSpaceCount: 2, style: .init(density: .regular),
                requiredND: model.result.map(RequiredNDGuidanceDisplayState.init),
                guidancePhase: model.phase, guidanceGeneration: model.generation,
                onTransitionComplete: { model.complete($0, token: $1) })
                .frame(width: 320).padding().background(Color.white).preferredColorScheme(.light)
        }
    }

    private struct OpacityHarness: View {
        @ObservedObject var model: RequiredNDGuidanceModel
        var body: some View {
            RequiredNDStatusTransition(reduceMotion: false, phase: model.phase,
                generation: model.generation, onComplete: { model.complete($0, token: $1) },
                outgoing: { Color.black }, incoming: { Color.white })
                .id(model.generation)
                .background(Color.white)
                .ignoresSafeArea()
        }
    }

    private struct ReducedMotionHarness: View {
        @ObservedObject var model: RequiredNDGuidanceModel
        var body: some View {
            RequiredNDStatusTransition(reduceMotion: true, phase: model.phase,
                generation: model.generation, onComplete: { model.complete($0, token: $1) },
                outgoing: { Text("Required") }, incoming: { Text("Ordinary") })
                .id(model.generation)
        }
    }

    private struct TransitionHost {
        let vm: ExposureCalculatorViewModel
        let host: UIHostingController<AnyView>
        let window: UIWindow
    }

    private func transitionHost() throws -> TransitionHost {
        let coordinator = WorkspaceCoordinator(dependencies: ViewModelDependencyFactory.test(), isFilterStackOrderingSuspended: false)
        let vm = coordinator.viewModel
        vm.baseShutter = 1
        vm.setTargetShutter(1024)
        let screen = ExposureCalculatorScreen(coordinator: coordinator, bottomSheetStateStore: BottomSheetWorkspaceStateStore())
        let host = UIHostingController(rootView: AnyView(screen))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .alert + 1
        window.rootViewController = host
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        return TransitionHost(vm: vm, host: host, window: window)
    }

    private func capture(_ view: UIView, name: String) {
        _ = capturePixels(view, name: name)
        // Optional simulator capture handshake. Normal test runs never wait;
        // a review runner captures the real screen while this state is held.
        guard let directory = ProcessInfo.processInfo.environment["REQUIRED_ND_REVIEW_DIR"] else { return }
        let ready = URL(fileURLWithPath: directory).appendingPathComponent(name + ".ready")
        try? Data().write(to: ready)
        let deadline = Date().addingTimeInterval(15)
        while FileManager.default.fileExists(atPath: ready.path), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
    }

    private func pickerFrames(in root: UIView) -> [CGRect] {
        var frames: [CGRect] = []
        func walk(_ view: UIView) {
            if view is UIPickerView { frames.append(view.convert(view.bounds, to: root)) }
            view.subviews.forEach(walk)
        }
        walk(root)
        return frames
    }

    // MARK: Hosting

    private struct Host {
        let controller: UIViewController
        let window: UIWindow
    }

    private func hosted(_ view: FilterStatusRegionView) throws -> Host {
        let host = UIHostingController(rootView: view.frame(width: 320))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 360, height: 200))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return Host(controller: host, window: window)
    }

    /// Labels of every accessibility element in tree order. An empty
    /// tree means the simulator's accessibility runtime is off — a
    /// missing prerequisite, not a defect — so the test skips and names
    /// the one-time enabling step.
    private func accessibilityLabels(in host: Host) throws -> [String] {
        var found: [String] = []
        collect(from: host.controller.view, into: &found)
        if found.isEmpty {
            throw XCTSkip(
                "The simulator's accessibility runtime is off (empty hosted accessibility tree). "
                    + "Enable it once per simulator: xcrun simctl spawn <udid> defaults write "
                    + "com.apple.Accessibility AccessibilityEnabled -bool true; xcrun simctl spawn <udid> "
                    + "defaults write com.apple.Accessibility ApplicationAccessibilityEnabled -int 1"
            )
        }
        return found
    }

    private func collect(from object: NSObject, into found: inout [String]) {
        if object.isAccessibilityElement {
            found.append(object.accessibilityLabel ?? "")
            return
        }
        if let elements = object.accessibilityElements as? [NSObject] {
            for element in elements {
                collect(from: element, into: &found)
            }
        }
        if let view = object as? UIView {
            for subview in view.subviews {
                collect(from: subview, into: &found)
            }
        }
    }
}
