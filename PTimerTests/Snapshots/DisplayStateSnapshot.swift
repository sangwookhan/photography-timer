import Foundation
import XCTest

/// Lightweight in-house display-state snapshot helper (B8).
///
/// Why not pointfreeco/swift-snapshot-testing?
/// The action plan originally pointed at that library, but adding a
/// SPM dependency to a personal-project Xcode workspace is heavy
/// relative to what we actually need. The L2 verification gate
/// described in B1's spec is "same input → same display-state
/// serialized result". Display states are `Equatable` (already)
/// and `Swift.dump` produces a deterministic indented text
/// representation per Swift version. That covers L2 fully and
/// stays diff-friendly in version control.
///
/// Pixel-level SwiftUI rendering snapshots (covering L4 — text vs
/// view layout regressions invisible to display-state diff) can be
/// added later by extending this helper with a UIView render path.
/// Until then, B1 PR 5 (view migration) should manually compare
/// rendered screens during review; the display-state baseline
/// already locks the model output.
///
/// ## Baseline files
///
/// Stored at `PTimerTests/__Snapshots__/<TestClass>/<testMethod>.txt`.
/// Resolved relative to the test source file at runtime.
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
        let serialized = serialize(value)
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

        if serialized != baseline {
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
    /// reflective output stable per Swift version.
    private static func serialize<T>(_ value: T) -> String {
        var output = ""
        dump(value, to: &output, indent: 2)
        return output
    }

    /// `__Snapshots__/<TestClassDir>/<name>.txt` next to the test
    /// file. The test class dir name is derived from the test
    /// file's basename minus ".swift".
    private static func baselineURL(testFile: StaticString, name: String) -> URL {
        let testFileURL = URL(fileURLWithPath: "\(testFile)")
        let testDir = testFileURL.deletingLastPathComponent()
        let testClass = testFileURL.deletingPathExtension().lastPathComponent

        // Walk up to the PTimerTests root so all snapshots live in
        // a single __Snapshots__ tree, mirroring the test layout.
        let snapshotsRoot = locateSnapshotsRoot(startingAt: testDir)
        return snapshotsRoot
            .appendingPathComponent(testClass, isDirectory: true)
            .appendingPathComponent("\(name).txt")
    }

    private static func locateSnapshotsRoot(startingAt directory: URL) -> URL {
        var current = directory
        while current.pathComponents.count > 1 {
            if current.lastPathComponent == "PTimerTests" {
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
