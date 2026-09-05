@testable import ExpoModulesScanner
import Foundation
import SwiftParser
import Testing

/// Parses a source string and returns the detections the visitor records for it, considering all
/// macros by default. The file name is fixed so location assertions are stable; only `line`/`column`
/// vary per test. `platform`/`defines` form the configuration `#if` conditions are evaluated
/// against; the default answers nothing, matching a scan invoked without options.
private func detect(
  _ source: String,
  macros: Set<DetectedMacro> = Set(DetectedMacro.allCases),
  platform: String? = nil,
  defines: Set<String> = []
) -> [Detection] {
  return visit(source, macros: macros, platform: platform, defines: defines).detections
}

/// `detect`, but returning the whole visitor so tests can also assert on the `#if` warnings.
private func visit(
  _ source: String,
  macros: Set<DetectedMacro> = Set(DetectedMacro.allCases),
  platform: String? = nil,
  defines: Set<String> = []
) -> DetectionVisitor {
  let tree = Parser.parse(source: source)
  let visitor = DetectionVisitor(
    file: "Test.swift",
    tree: tree,
    detectedMacros: macros,
    configuration: ScanBuildConfiguration(platform: platform, defines: defines)
  )
  visitor.walk(tree)
  return visitor
}

/// Convenience matching the production pre-filter: builds the regex for `macros` (all by default)
/// and tests whether the source might contain one.
private func mightContainMacro(in source: String, macros: Set<DetectedMacro> = Set(DetectedMacro.allCases)) -> Bool {
  return mightContainMacro(in: source, prefilter: macroAttributeRegex(for: macros))
}

@Suite("Scanner detection")
struct DetectionVisitorTests {
  @Test
  func `Detects a top-level @ExpoModule class`() throws {
    let detections = detect(
      """
      @ExpoModule
      final class GreeterModule {}
      """
    )
    #expect(detections.count == 1)
    let detection = try #require(detections.first)
    #expect(detection.macro == .expoModule)
    #expect(detection.name == "GreeterModule")
    #expect(detection.declarationKind == "class")
    #expect(detection.jsName == nil)
    #expect(detection.arguments.isEmpty)
    // The location points at the declaration's leading attribute, i.e. the `@ExpoModule` line.
    #expect(detection.line == 1)
  }

  @Test
  func `Detects a top-level @SharedObject class`() {
    let detections = detect(
      """
      @SharedObject
      final class Cache: SharedObject {}
      """
    )
    #expect(detections.count == 1)
    #expect(detections.first?.macro == .sharedObject)
    #expect(detections.first?.name == "Cache")
  }

  @Test
  func `Detects a top-level @ExpoModule struct`() {
    let detections = detect(
      """
      @ExpoModule
      struct Bare {}
      """
    )
    #expect(detections.first?.declarationKind == "struct")
  }

  @Test
  func `Detects a top-level @Record struct`() {
    let detections = detect(
      """
      @Record
      struct Options {
        var name: String
        var count: Int = 0
      }
      """
    )
    #expect(detections.count == 1)
    #expect(detections.first?.macro == .record)
    #expect(detections.first?.name == "Options")
    #expect(detections.first?.declarationKind == "struct")
    #expect(detections.first?.arguments.isEmpty == true)
  }

  @Test(arguments: [
    ("open", "open"),
    ("public", "public"),
    ("package", "package"),
    ("internal", "internal"),
    ("fileprivate", "fileprivate"),
    ("private", "private"),
  ])
  func `Records the spelled access level`(modifier: String, expected: String) {
    let detections = detect(
      """
      @ExpoModule
      \(modifier) final class GreeterModule {}
      """
    )
    #expect(detections.first?.accessLevel == expected)
  }

  @Test
  func `Defaults the access level to internal when none is spelled`() {
    let detections = detect(
      """
      @ExpoModule
      final class GreeterModule {}
      """
    )
    #expect(detections.first?.accessLevel == "internal")
  }

  @Test
  func `Ignores @JS members nested in a type body`() {
    let detections = detect(
      """
      @ExpoModule
      final class GreeterModule {
        @JS
        func greet(name: String) -> String { "Hi" }

        @JS
        var status: String { "ok" }
      }
      """
    )
    // Only the top-level class is reported; the nested @JS members are not.
    #expect(detections.count == 1)
    #expect(detections.first?.macro == .expoModule)
  }

  @Test
  func `Ignores a nested type even when it carries a recognized macro`() {
    let detections = detect(
      """
      enum Namespace {
        @SharedObject
        final class Cache: SharedObject {}
      }
      """
    )
    #expect(detections.isEmpty)
  }

  @Test
  func `Captures the positional string argument as jsName and as an argument`() throws {
    let detections = detect(
      """
      @ExpoModule("Greeter")
      final class GreeterModule {}
      """
    )
    let detection = try #require(detections.first)
    #expect(detection.jsName == "Greeter")
    #expect(detection.arguments == [MacroArgument(label: nil, value: "\"Greeter\"")])
  }

  @Test
  func `Captures positional and labeled arguments in source order`() throws {
    let detections = detect(
      """
      @ExpoModule("Greeter", classes: [Cache.self, Store.self])
      final class GreeterModule {}
      """
    )
    let detection = try #require(detections.first)
    #expect(detection.jsName == "Greeter")
    #expect(detection.arguments == [
      MacroArgument(label: nil, value: "\"Greeter\""),
      MacroArgument(label: "classes", value: "[Cache.self, Store.self]"),
    ])
  }

  @Test
  func `A bare attribute has no arguments and no jsName`() {
    let detections = detect(
      """
      @ExpoModule
      final class GreeterModule {}
      """
    )
    #expect(detections.first?.arguments.isEmpty == true)
    #expect(detections.first?.jsName == nil)
  }

  @Test
  func `Ignores unannotated top-level declarations`() {
    let detections = detect(
      """
      final class PlainClass {}
      struct PlainStruct {}
      @objc final class ObjCClass {}
      """
    )
    #expect(detections.isEmpty)
  }

  @Test
  func `Does not match a macro name appearing inside a string literal`() {
    let detections = detect(
      """
      let source = "@ExpoModule final class Fake {}"
      """
    )
    #expect(detections.isEmpty)
  }

  @Test
  func `Detects multiple top-level types in one file`() {
    let detections = detect(
      """
      @ExpoModule
      final class ModuleA {}

      @SharedObject
      final class ObjectB: SharedObject {}
      """
    )
    #expect(detections.map(\.name) == ["ModuleA", "ObjectB"])
    #expect(detections.map(\.macro) == [.expoModule, .sharedObject])
  }
}

@Suite("Macro pre-filter")
struct MacroPrefilterTests {
  @Test
  func `Recognizes each spelled macro attribute`() {
    #expect(mightContainMacro(in: "@ExpoModule\nclass M {}"))
    #expect(mightContainMacro(in: "@SharedObject\nclass C: SharedObject {}"))
    #expect(mightContainMacro(in: "struct S {\n  @JS func f() {}\n}"))
    #expect(mightContainMacro(in: "@Record\nstruct Options {}"))
  }

  @Test
  func `Skips source with no macro attribute`() {
    #expect(!mightContainMacro(in: "final class Plain {}\nlet x = 1"))
  }

  @Test
  func `Does not collide with similar bare identifiers`() {
    // `JS` appears as a substring here, but only inside identifiers — not as the `@JS` attribute,
    // which is what keeps the `@`-prefixed pattern from force-parsing every file that uses JSON.
    #expect(!mightContainMacro(in: "let data = JSONDecoder()\nstruct JSValue {}"))
  }

  @Test
  func `Over-approximates: matches the attribute inside a string literal`() {
    // A false positive here is acceptable — the file is parsed and then yields no detections.
    #expect(mightContainMacro(in: #"let s = "@ExpoModule""#))
  }
}


@Suite("#if evaluation")
struct IfConfigTests {
  @Test
  func `Detects a module inside a matching os condition`() {
    let source = """
      #if os(tvOS)
      @ExpoModule
      final class TVModule {}
      #endif
      """
    #expect(detect(source, platform: "tvOS").map(\.name) == ["TVModule"])
    // The comparison is case-insensitive, matching how the platform is spelled by the caller.
    #expect(detect(source, platform: "tvos").map(\.name) == ["TVModule"])
    #expect(detect(source, platform: "iOS").isEmpty)
  }

  @Test
  func `Follows the active branch of an #if / #else`() {
    let source = """
      #if os(macOS)
      @ExpoModule
      final class MacModule {}
      #else
      @ExpoModule
      final class DefaultModule {}
      #endif
      """
    #expect(detect(source, platform: "macOS").map(\.name) == ["MacModule"])
    #expect(detect(source, platform: "iOS").map(\.name) == ["DefaultModule"])
  }

  @Test
  func `Evaluates custom flags from defines, including in compound conditions`() {
    let source = """
      #if DEBUG && os(iOS)
      @ExpoModule
      final class DebugModule {}
      #endif
      """
    #expect(detect(source, platform: "iOS", defines: ["DEBUG"]).map(\.name) == ["DebugModule"])
    #expect(detect(source, platform: "iOS").isEmpty)
    #expect(detect(source, platform: "macOS", defines: ["DEBUG"]).isEmpty)
  }

  @Test
  func `Detects a module nested in #if blocks`() {
    let source = """
      #if os(iOS)
      #if DEBUG
      @ExpoModule
      final class NestedModule {}
      #endif
      #endif
      """
    #expect(detect(source, platform: "iOS", defines: ["DEBUG"]).map(\.name) == ["NestedModule"])
    #expect(detect(source, platform: "iOS").isEmpty)
  }

  @Test
  func `An os condition with no platform given skips the region and warns`() {
    let visitor = visit(
      """
      #if os(iOS)
      @ExpoModule
      final class ConditionalModule {}
      #endif
      """
    )
    #expect(visitor.detections.isEmpty)
    #expect(visitor.warnings.count == 1)
    #expect(visitor.warnings.first?.message.contains("os(iOS)") == true)
    #expect(visitor.warnings.first?.line == 1)
  }

  @Test
  func `A condition the scan can't answer skips the region and warns`() {
    let visitor = visit(
      """
      #if canImport(UIKit)
      @ExpoModule
      final class UIKitModule {}
      #endif
      """,
      platform: "iOS"
    )
    #expect(visitor.detections.isEmpty)
    #expect(visitor.warnings.first?.message.contains("canImport(UIKit)") == true)
  }

  @Test
  func `An unconditional module produces no warnings`() {
    let visitor = visit(
      """
      @ExpoModule
      final class PlainModule {}
      """
    )
    #expect(visitor.detections.count == 1)
    #expect(visitor.warnings.isEmpty)
  }
}

@Suite("Scanning a directory")
struct ScanTests {
  /// Creates a temporary directory tree of `(relativePath, contents)` files, runs `scanModules` on
  /// it, and removes the tree afterward.
  private func withTree(
    _ files: [(String, String)],
    _ body: (ScanModulesResult) throws -> Void
  ) throws {
    try withTreeRoot(files) { root in
      try body(scanModules(paths: [root.path]))
    }
  }

  /// Materializes a temporary tree and hands its root to `body`, removing it afterward.
  private func withTreeRoot(
    _ files: [(String, String)],
    _ body: (URL) throws -> Void
  ) throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("scanner-test-\(ProcessInfo.processInfo.globallyUniqueString)")
    defer { try? fileManager.removeItem(at: root) }

    for (relativePath, contents) in files {
      let url = root.appendingPathComponent(relativePath)
      try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    try body(root)
  }

  @Test
  func `Reports detections and stats over a tree`() throws {
    try withTree([
      ("Module.swift", "@ExpoModule\nfinal class MyModule {}"),
      ("Plain.swift", "final class Plain {}"),
      ("Notes.swift", "// just a comment, no macros here"),
    ]) { result in
      #expect(result.modules.map(\.name) == ["MyModule"])
      // Reported paths are absolute.
      #expect(result.modules.first?.file.hasPrefix("/") == true)
      #expect(result.schemaVersion == scanModulesSchemaVersion)
      // All three .swift files are read; only the one mentioning a macro is parsed.
      #expect(result.stats.filesScanned == 3)
      #expect(result.stats.filesParsed == 1)
      #expect(result.stats.durationMs >= 0)
    }
  }

  @Test
  func `Resolves jsName: explicit override, else the class name`() throws {
    try withTree([
      ("Plain.swift", "@ExpoModule\nfinal class PlainModule {}"),
      ("Renamed.swift", "@ExpoModule(\"JSName\")\nfinal class RenamedModule {}"),
    ]) { result in
      let byName = Dictionary(uniqueKeysWithValues: result.modules.map { ($0.name, $0.jsName) })
      // No override -> jsName falls back to the class name.
      #expect(byName["PlainModule"] == "PlainModule")
      // Override -> jsName is the argument.
      #expect(byName["RenamedModule"] == "JSName")
    }
  }

  @Test
  func `scanModules reports only @ExpoModule, ignoring other macros`() throws {
    let files = [
      ("Module.swift", "@ExpoModule\nfinal class MyModule {}"),
      ("Shared.swift", "@SharedObject\nfinal class Cache: SharedObject {}"),
      ("Options.swift", "@Record\nstruct Options { var name: String }"),
    ]
    try withTreeRoot(files) { root in
      let result = scanModules(paths: [root.path])
      #expect(result.modules.map(\.name) == ["MyModule"])
      // @SharedObject / @Record files aren't even parsed: the modules pre-filter is @ExpoModule-only.
      #expect(result.stats.filesParsed == 1)

      // The shared core, given the full macro set, surfaces all three — confirming it's the
      // @ExpoModule-only filter, not the walk, that scopes scanModules.
      let all = collectDetections(paths: [root.path], macros: Set(DetectedMacro.allCases))
      #expect(all.detections.map(\.name).sorted() == ["Cache", "MyModule", "Options"])
      #expect(all.stats.filesParsed == 3)
    }
  }

  @Test
  func `Prunes .build, Pods, .git, and node_modules directories`() throws {
    try withTree([
      ("Real.swift", "@ExpoModule\nfinal class RealModule {}"),
      (".build/Generated.swift", "@ExpoModule\nfinal class BuildArtifact {}"),
      ("Pods/Vendored.swift", "@ExpoModule\nfinal class Vendored {}"),
      (".git/hooks/Sneaky.swift", "@ExpoModule\nfinal class Sneaky {}"),
      ("node_modules/some-dep/ios/Nested.swift", "@ExpoModule\nfinal class Nested {}"),
    ]) { result in
      // Only the file outside the pruned directories is seen at all.
      #expect(result.modules.map(\.name) == ["RealModule"])
      #expect(result.stats.filesScanned == 1)
      #expect(result.stats.filesParsed == 1)
    }
  }

  @Test
  func `Evaluates #if conditions and carries warnings in the result`() throws {
    try withTreeRoot([
      ("TV.swift", "#if os(tvOS)\n@ExpoModule\nfinal class TVModule {}\n#endif"),
      ("UIKit.swift", "#if canImport(UIKit)\n@ExpoModule\nfinal class UIKitModule {}\n#endif"),
      ("Plain.swift", "@ExpoModule\nfinal class PlainModule {}"),
    ]) { root in
      let configuration = ScanBuildConfiguration(platform: "tvOS", defines: [])
      let result = scanModules(paths: [root.path], configuration: configuration)
      #expect(result.modules.map(\.name) == ["PlainModule", "TVModule"])
      // The unanswerable canImport lands in the report as a warning with its location.
      #expect(result.warnings.count == 1)
      #expect(result.warnings.first?.message.contains("canImport(UIKit)") == true)
      #expect(result.warnings.first?.file.hasSuffix("UIKit.swift") == true)
      #expect(result.warnings.first?.line == 1)
    }
  }

  @Test
  func `Maps the access level into the output`() throws {
    try withTree([
      ("Public.swift", "@ExpoModule\npublic final class PublicModule {}"),
      ("Unspelled.swift", "@ExpoModule\nfinal class UnspelledModule {}"),
    ]) { result in
      let byName = Dictionary(uniqueKeysWithValues: result.modules.map { ($0.name, $0.accessLevel) })
      #expect(byName["PublicModule"] == "public")
      #expect(byName["UnspelledModule"] == "internal")
    }
  }
}
