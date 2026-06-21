// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest

/// Baseline read/write/diff for record-replay traces. Mirrors
/// `DisplayStateSnapshot` but stores under
/// `PTimerTests/__RecordReplay__/<TestClass>/<name>.txt` and is
/// driven by the `RECORD_REPLAY=1` environment variable.
///
/// Why a sibling helper instead of generalising `DisplayStateSnapshot`?
/// The two helpers serve subtly different purposes — `DisplayStateSnapshot`
/// locks a *single value's* serialized form, whereas record-replay
/// locks an *ordered event sequence*. Keeping them separate keeps each
/// helper's call site obvious in the test file. The on-disk diff
/// machinery is intentionally identical so re-record / verify
/// ergonomics are familiar.
@MainActor
enum RecordReplayBaseline {

    /// Asserts that `recorder.renderTrace()` matches the stored
    /// baseline. On first run (or with `RECORD_REPLAY=1`) writes the
    /// baseline and fails so the file is committed deliberately —
    /// same "fail-on-record" guard as `DisplayStateSnapshot`.
    static func assert(
        _ recorder: RecordReplayRecorder,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let serialized = recorder.renderTrace()
        let url = baselineURL(testFile: file, name: name)
        let isRecording = ProcessInfo.processInfo.environment["RECORD_REPLAY"] == "1"

        if isRecording {
            do {
                try write(serialized, to: url)
                XCTFail(
                    "Re-recorded trace baseline → \(url.path). Re-run without RECORD_REPLAY to verify.",
                    file: file,
                    line: line
                )
            } catch {
                XCTFail("Failed to write trace baseline: \(error)", file: file, line: line)
            }
            return
        }

        guard let baseline = try? String(contentsOf: url, encoding: .utf8) else {
            do {
                try write(serialized, to: url)
                XCTFail(
                    "No trace baseline found. Recorded → \(url.path). Re-run to verify.",
                    file: file,
                    line: line
                )
            } catch {
                XCTFail(
                    "No trace baseline and write failed: \(error). Tried path: \(url.path)",
                    file: file,
                    line: line
                )
            }
            return
        }

        if serialized != baseline {
            let actualURL = url.deletingPathExtension().appendingPathExtension("actual.txt")
            try? write(serialized, to: actualURL)
            XCTFail(
                """
                Record-replay trace diff for "\(name)".
                Baseline: \(url.path)
                Actual:   \(actualURL.path)
                Re-record with RECORD_REPLAY=1 if change is intentional.
                """,
                file: file,
                line: line
            )
        } else {
            let actualURL = url.deletingPathExtension().appendingPathExtension("actual.txt")
            try? FileManager.default.removeItem(at: actualURL)
        }
    }

    // MARK: - Internal helpers

    /// `__RecordReplay__/<TestClassDir>/<name>.txt` rooted at the
    /// `PTimerTests/` directory containing the calling test file.
    private static func baselineURL(testFile: StaticString, name: String) -> URL {
        let testFileURL = URL(fileURLWithPath: "\(testFile)")
        let testDir = testFileURL.deletingLastPathComponent()
        let testClass = testFileURL.deletingPathExtension().lastPathComponent

        let baselinesRoot = locateBaselinesRoot(startingAt: testDir)
        return baselinesRoot
            .appendingPathComponent(testClass, isDirectory: true)
            .appendingPathComponent("\(name).txt")
    }

    private static func locateBaselinesRoot(startingAt directory: URL) -> URL {
        var current = directory
        while current.pathComponents.count > 1 {
            if current.lastPathComponent == "PTimerTests" {
                return current.appendingPathComponent("__RecordReplay__", isDirectory: true)
            }
            current = current.deletingLastPathComponent()
        }
        return directory.appendingPathComponent("__RecordReplay__", isDirectory: true)
    }

    private static func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
