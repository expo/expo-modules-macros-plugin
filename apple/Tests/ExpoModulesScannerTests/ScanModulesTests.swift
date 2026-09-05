@testable import ExpoModulesScanner
import Foundation
import Testing

/// Exercises the `scan-modules` command end to end against a real directory tree: fixture files are
/// written to a temporary directory, scanned, and cleaned up. The visitor-level details are covered
/// by `DetectionVisitorTests`; these tests cover what sits above it: the walk, the pruning, and the
/// mapping into the command's output shape.
@Suite("scan-modules")
struct ScanModulesTests {
  /// Creates a temporary directory with the given files (relative path → source), runs `scanModules`
  /// over it, and removes the directory afterwards.
  private func scan(files: [String: String]) throws -> ScanModulesResult {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
      .appendingPathComponent("ScanModulesTests-\(UUID().uuidString)", isDirectory: true)
    defer {
      try? fileManager.removeItem(at: root)
    }

    for (relativePath, source) in files {
      let url = root.appendingPathComponent(relativePath)
      try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try source.write(to: url, atomically: true, encoding: .utf8)
    }

    return scanModules(paths: [root.path])
  }

  @Test
  func `Reports the schema version`() throws {
    let result = try scan(files: [:])
    #expect(result.schemaVersion == scanModulesSchemaVersion)
    #expect(result.modules.isEmpty)
  }

  @Test
  func `Maps detections to the output shape`() throws {
    let result = try scan(files: [
      "ios/GreeterModule.swift": """
      @ExpoModule
      public final class GreeterModule {}
      """,
      "ios/RenamedModule.swift": """
      @ExpoModule("Renamed")
      final class RenamedModule {}
      """,
    ])

    #expect(result.modules.count == 2)

    let greeter = try #require(result.modules.first { $0.name == "GreeterModule" })
    #expect(greeter.jsName == "GreeterModule")
    #expect(greeter.accessLevel == "public")
    #expect(greeter.file.hasSuffix("ios/GreeterModule.swift"))

    let renamed = try #require(result.modules.first { $0.name == "RenamedModule" })
    #expect(renamed.jsName == "Renamed")
    #expect(renamed.accessLevel == "internal")
  }

  @Test
  func `Prunes dependency and build directories`() throws {
    let module = """
      @ExpoModule
      public final class HiddenModule {}
      """
    let result = try scan(files: [
      "node_modules/some-dep/ios/HiddenModule.swift": module,
      "Pods/SomePod/HiddenModule.swift": module,
      ".build/release/HiddenModule.swift": module,
      "ios/VisibleModule.swift": """
      @ExpoModule
      public final class VisibleModule {}
      """,
    ])

    #expect(result.modules.map(\.name) == ["VisibleModule"])
    // The pruned files are never read, so they don't count as scanned either.
    #expect(result.stats.filesScanned == 1)
  }
}
