@testable import ExpoModulesScanner
import Foundation
import SwiftParser
import Testing

/// Parses a source string and returns the detections the visitor records for it, considering all
/// macros by default. The file name is fixed so location assertions are stable; only `line`/`column`
/// vary per test.
private func detect(_ source: String, macros: Set<DetectedMacro> = Set(DetectedMacro.allCases)) -> [Detection] {
  let tree = Parser.parse(source: source)
  let visitor = DetectionVisitor(file: "Test.swift", tree: tree, detectedMacros: macros)
  visitor.walk(tree)
  return visitor.detections
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
  func `Prunes .build, Pods, and .git directories`() throws {
    try withTree([
      ("Real.swift", "@ExpoModule\nfinal class RealModule {}"),
      (".build/Generated.swift", "@ExpoModule\nfinal class BuildArtifact {}"),
      ("Pods/Vendored.swift", "@ExpoModule\nfinal class Vendored {}"),
      (".git/hooks/Sneaky.swift", "@ExpoModule\nfinal class Sneaky {}"),
    ]) { result in
      // Only the file outside the pruned directories is seen at all.
      #expect(result.modules.map(\.name) == ["RealModule"])
      #expect(result.stats.filesScanned == 1)
      #expect(result.stats.filesParsed == 1)
    }
  }
}
