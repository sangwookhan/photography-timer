import Foundation

/// Resolves the repository-level `shared/test-fixtures/` directory by
/// walking up from the calling test file's location until a parent
/// contains it. Survives repository reorganization that keeps
/// `shared/` at the repo root.
enum SharedFixtureLocator {
    static func fixturesRoot(file: StaticString = #filePath) -> URL {
        var current = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        let fm = FileManager.default
        while current.pathComponents.count > 1 {
            let candidate = current
                .appendingPathComponent("shared", isDirectory: true)
                .appendingPathComponent("test-fixtures", isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDir),
               isDir.boolValue {
                return candidate
            }
            current = current.deletingLastPathComponent()
        }
        fatalError("shared/test-fixtures not found above \(file)")
    }
}
