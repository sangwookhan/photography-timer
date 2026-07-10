// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest

/// Lightweight in-house display-state snapshot helper.
///
/// Why not pointfreeco/swift-snapshot-testing?
/// The action plan originally pointed at that library, but adding a
/// SPM dependency to a personal-project Xcode workspace is heavy
/// relative to what we actually need. The verification gate here is
/// "same input → same display-state
/// serialized result". Display states are `Equatable` (already)
/// and `Swift.dump` produces a deterministic indented text
/// representation per Swift version. That covers L2 fully and
/// stays diff-friendly in version control.
///
/// Pixel-level SwiftUI rendering snapshots (covering L4 — text vs
/// view layout regressions invisible to display-state diff) can be
/// added later by extending this helper with a UIView render path.
/// Until then, reviews should compare rendered screens manually; the
/// display-state baseline already locks model output.
///
/// ## Baseline files
///
/// Stored at `<TestRoot>/__Snapshots__/<TestClass>/<testMethod>.txt`,
/// where `<TestRoot>` is the nearest supported test root above the test
/// source file — `PTimerTests` (app) or `PTimerKitTests` (package).
/// Resolved relative to the test source file's `#filePath` at runtime.
///
/// ## Recording / replaying
///
/// First run: no baseline exists → helper writes the current value
/// to disk and fails the test with a "baseline recorded" message.
/// Subsequent runs: helper reads the baseline and asserts equality.
///
/// To re-record (after intentional change):
///
/// ```bash
/// SNAPSHOT_RECORD=1 xcodebuild test ...
/// ```
///
/// Every recorded test fails so a deliberate run is required to
/// commit new baselines; this prevents accidental "the test passes
/// because it just rewrote the baseline" regressions.
@MainActor
enum DisplayStateSnapshot {

    /// Asserts that `value`'s deterministic text representation
    /// matches the stored baseline. On first run (or with
    /// `SNAPSHOT_RECORD=1`) it records the baseline and fails.
    static func assert<T>(
        _ value: T,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertSerialized(serialize(value), named: name, file: file, line: line)
    }

    /// Asserts that the verbatim `text` matches the stored baseline.
    ///
    /// Distinct from `assert(_:named:)` (which dumps reflective output of
    /// arbitrary values via `Swift.dump`) because some baselines — for
    /// example a concatenated JSON trace — are already stable text and
    /// should be committed as-is. Wrapping pre-formatted text with
    /// `dump` would escape newlines onto a single line, defeating diff
    /// review.
    static func assertText(
        _ text: String,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertSerialized(text, named: name, file: file, line: line)
    }

    private static func assertSerialized(
        _ serialized: String,
        named name: String,
        file: StaticString,
        line: UInt
    ) {
        let url = baselineURL(testFile: file, name: name)
        let isRecording = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD"] == "1"

        if isRecording {
            do {
                try write(serialized, to: url)
                XCTFail(
                    "Re-recorded baseline → \(url.path). Re-run without SNAPSHOT_RECORD to verify.",
                    file: file,
                    line: line
                )
            } catch {
                XCTFail("Failed to write baseline: \(error)", file: file, line: line)
            }
            return
        }

        guard let baseline = try? String(contentsOf: url, encoding: .utf8) else {
            // No baseline: record and fail so the developer commits the
            // new file deliberately.
            do {
                try write(serialized, to: url)
                XCTFail(
                    "No baseline found. Recorded → \(url.path). Re-run to verify.",
                    file: file,
                    line: line
                )
            } catch {
                XCTFail(
                    "No baseline and write failed: \(error). Tried path: \(url.path)",
                    file: file,
                    line: line
                )
            }
            return
        }

        if serialized != canonicalize(baseline) {
            // Write the actual to a sidecar file for easier diffing.
            let actualURL = url.deletingPathExtension().appendingPathExtension("actual.txt")
            try? write(serialized, to: actualURL)
            XCTFail(
                """
                Snapshot diff for "\(name)".
                Baseline: \(url.path)
                Actual:   \(actualURL.path)
                Re-record with SNAPSHOT_RECORD=1 if change is intentional.
                """,
                file: file,
                line: line
            )
        } else {
            // On match, clean up any stale .actual.txt sidecar.
            let actualURL = url.deletingPathExtension().appendingPathExtension("actual.txt")
            try? FileManager.default.removeItem(at: actualURL)
        }
    }

    // MARK: - Internal helpers

    /// Deterministic text representation. `Swift.dump` writes
    /// reflective output stable per Swift version, but it surfaces
    /// hex memory addresses for anonymous (file-private) nested
    /// types in the form `(unknown context at $1234abcd)`. Those
    /// vary across runs, so canonicalize them to `$XX` before the
    /// baseline comparison.
    private static func serialize<T>(_ value: T) -> String {
        var output = ""
        dump(value, to: &output, indent: 2)
        return canonicalize(output)
    }

    private static let hexAddressPattern = try? NSRegularExpression(
        pattern: #"\$[0-9a-fA-F]{6,16}"#
    )

    /// `ReciprocityProfile.sourcePageUrl` / `.downloadUrl` (PTIMER-158) are
    /// display-only catalog reference links, not read by the calculation
    /// policy. They can change when a manufacturer moves a page (PTIMER-212:
    /// a Kodak link fix invalidated snapshots whose only diff was these
    /// URLs), so the baseline pins field presence, not the current URL text.
    private static let catalogProvenanceURLFieldNames = ["sourcePageUrl", "downloadUrl"]
    private static let redactedURLPlaceholder = "<redacted-for-snapshot>"

    private static func catalogProvenanceURLPairPattern(field: String) -> NSRegularExpression? {
        try? NSRegularExpression(
            pattern: #"▿ \#(field): Optional\("[^"]*"\)\n(\s*)- some: "[^"]*""#
        )
    }

    private static func catalogProvenanceURLInlinePattern(field: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: #"\#(field): Optional\("[^"]*"\)"#)
    }

    private static func redactCatalogProvenanceURLs(_ output: String) -> String {
        var result = output
        for field in catalogProvenanceURLFieldNames {
            if let pairPattern = catalogProvenanceURLPairPattern(field: field) {
                let range = NSRange(result.startIndex..., in: result)
                result = pairPattern.stringByReplacingMatches(
                    in: result,
                    range: range,
                    withTemplate: "▿ \(field): Optional(\"\(redactedURLPlaceholder)\")\n$1- some: \"\(redactedURLPlaceholder)\""
                )
            }
            if let inlinePattern = catalogProvenanceURLInlinePattern(field: field) {
                let range = NSRange(result.startIndex..., in: result)
                result = inlinePattern.stringByReplacingMatches(
                    in: result,
                    range: range,
                    withTemplate: "\(field): Optional(\"\(redactedURLPlaceholder)\")"
                )
            }
        }
        return result
    }

    /// `internal` (not `private`) so `DisplayStateSnapshotCanonicalizationTests`
    /// can assert on this observable text transform directly, without
    /// writing throwaway snapshot baseline files.
    static func canonicalize(_ output: String) -> String {
        // Strip the test-module qualifier `Swift.dump` prepends to
        // file-private (anonymous-context) helper types, so a baseline is
        // portable between the app (PTimerTests) and package
        // (PTimerKitTests) test targets: the dumped DATA is identical and
        // only the owning test module's name differs. Applied to both the
        // serialized value and the stored baseline at compare time, so the
        // committed `.txt` files stay byte-identical.
        var result = output
            .replacingOccurrences(of: "PTimerTests.(unknown context", with: "(unknown context")
            .replacingOccurrences(of: "PTimerKitTests.(unknown context", with: "(unknown context")
        result = redactCatalogProvenanceURLs(result)
        guard let regex = hexAddressPattern else {
            return result
        }
        let range = NSRange(result.startIndex..., in: result)
        // NSRegularExpression treats `$` in templates as a back-
        // reference prefix, so literal `$` must be escaped with a
        // single backslash — `\$` in the template, `"\\$"` in the
        // Swift string literal.
        result = regex.stringByReplacingMatches(
            in: result,
            range: range,
            withTemplate: "\\$XX"
        )
        return result
    }

    /// `<TestRoot>/__Snapshots__/<TestClassDir>/<name>.txt`. The test
    /// class dir name is derived from the test file's basename minus
    /// ".swift".
    private static func baselineURL(testFile: StaticString, name: String) -> URL {
        let testFileURL = URL(fileURLWithPath: "\(testFile)")
        let testDir = testFileURL.deletingLastPathComponent()
        let testClass = testFileURL.deletingPathExtension().lastPathComponent

        // Walk up to the owning test root so all snapshots live in a
        // single __Snapshots__ tree per target, mirroring the test layout.
        let snapshotsRoot = locateSnapshotsRoot(startingAt: testDir)
        return snapshotsRoot
            .appendingPathComponent(testClass, isDirectory: true)
            .appendingPathComponent("\(name).txt")
    }

    private static func locateSnapshotsRoot(startingAt directory: URL) -> URL {
        // The suites live in either the app test target (PTimerTests) or
        // the package test target (PTimerKitTests). Walk up to whichever
        // test root owns the caller so snapshots live in a single
        // `__Snapshots__` tree per target, mirroring the test layout.
        let testRoots: Set<String> = ["PTimerTests", "PTimerKitTests"]
        var current = directory
        while current.pathComponents.count > 1 {
            if testRoots.contains(current.lastPathComponent) {
                return current.appendingPathComponent("__Snapshots__", isDirectory: true)
            }
            current = current.deletingLastPathComponent()
        }
        // Fallback: alongside the test file.
        return directory.appendingPathComponent("__Snapshots__", isDirectory: true)
    }

    private static func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
