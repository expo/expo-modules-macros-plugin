@testable import ExpoModulesScanner
import Foundation
import SwiftParser
import Testing

/// Parses a source string and returns the exported surface the visitor extracts. The file name is
/// fixed so any per-type `file` field is stable across runs.
private func surface(_ source: String) -> SurfaceVisitor {
  let tree = Parser.parse(source: source)
  let visitor = SurfaceVisitor(file: "Test.swift")
  visitor.walk(tree)
  return visitor
}

@Suite("Exports surface: modules")
struct ModuleSurfaceTests {
  @Test
  func `Extracts a module's @JS functions with names, params, and effects`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule("Greeter")
        final class GreeterModule {
          @JS
          func greet(name: String, loud: Bool = false) -> String { "" }

          @JS("doWork")
          func performWork() async throws {}

          // Not exported: no @JS.
          func helper() {}
        }
        """
      ).modules.first)

    #expect(module.name == "GreeterModule")
    #expect(module.jsName == "Greeter")
    #expect(module.functions.map(\.name) == ["greet", "performWork"])

    let greet = try #require(module.functions.first { $0.name == "greet" })
    #expect(greet.jsName == "greet")
    #expect(greet.returns == .primitive(name: "String", jsType: .string))
    #expect(greet.isAsync == false)
    #expect(greet.isThrowing == false)
    #expect(greet.parameters.map(\.name) == ["name", "loud"])
    #expect(greet.parameters.map(\.type) == [.primitive(name: "String", jsType: .string), .primitive(name: "Bool", jsType: .boolean)])
    // A defaulted parameter is omittable, so it's reported optional.
    #expect(greet.parameters.map(\.isOptional) == [false, true])

    let work = try #require(module.functions.first { $0.name == "performWork" })
    // The @JS("doWork") override becomes the JS name; the Swift name is kept separately.
    #expect(work.jsName == "doWork")
    #expect(work.isAsync == true)
    #expect(work.isThrowing == true)
    // A Void return is dropped to nil.
    #expect(work.returns == nil)
  }

  @Test
  func `Extracts @JS properties with type and settability`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule
        final class M {
          @JS var counter = 0
          @JS var status: String { "ok" }
          @JS let id: String
          @JS var name: String {
            get { "" }
            set {}
          }
          @JS var observed: Int = 0 {
            didSet {}
          }
        }
        """
      ).modules.first)

    let byName = Dictionary(uniqueKeysWithValues: module.properties.map { ($0.name, $0) })

    // Stored var: typed from its literal default, settable.
    #expect(byName["counter"]?.type == .primitive(name: "Int", jsType: .number))
    #expect(byName["counter"]?.isSettable == true)
    // Getter-only computed var: read-only.
    #expect(byName["status"]?.type == .primitive(name: "String", jsType: .string))
    #expect(byName["status"]?.isSettable == false)
    // let: never settable.
    #expect(byName["id"]?.isSettable == false)
    // Computed var with an explicit set: settable.
    #expect(byName["name"]?.isSettable == true)
    // Observed stored var (`didSet`): still backed by storage, so settable.
    #expect(byName["observed"]?.isSettable == true)
  }

  @Test
  func `Resolves a module's jsName: explicit override, else the class name`() {
    #expect(surface("@ExpoModule\nfinal class Plain {}").modules.first?.jsName == "Plain")
    #expect(surface("@ExpoModule(\"JS\")\nfinal class Renamed {}").modules.first?.jsName == "JS")
  }
}

@Suite("Exports surface: shared objects")
struct SharedObjectSurfaceTests {
  @Test
  func `Extracts a shared object's constructor, functions, and properties`() throws {
    let shared = try #require(
      surface(
        """
        @SharedObject
        final class Cache: SharedObject {
          @JS
          init(name: String, size: Int?) {}

          @JS
          func clear() {}

          @JS
          let id: String
        }
        """
      ).sharedObjects.first)

    #expect(shared.name == "Cache")
    #expect(shared.jsName == "Cache")
    #expect(shared.constructorParameters?.map(\.name) == ["name", "size"])
    // An optional-typed parameter is omittable.
    #expect(shared.constructorParameters?.map(\.isOptional) == [false, true])
    #expect(shared.functions.map(\.name) == ["clear"])
    #expect(shared.properties.map(\.name) == ["id"])
    #expect(shared.properties.first?.isSettable == false)
  }

  @Test
  func `Reports a nil constructor when there's no @JS init`() throws {
    let shared = try #require(
      surface(
        """
        @SharedObject
        final class Cache: SharedObject {
          @JS func clear() {}
        }
        """
      ).sharedObjects.first)
    #expect(shared.constructorParameters == nil)
  }
}

@Suite("Exports surface: records")
struct RecordSurfaceTests {
  @Test
  func `Extracts record properties, excluding non-stored and non-eligible ones`() throws {
    let record = try #require(
      surface(
        """
        @Record
        struct Options {
          var name: String
          var retries: Int = 3
          var note: String?
          private var secret: Int = 0
          static var shared: Int = 0
          var computed: Int { 1 }
        }
        """
      ).records.first)

    #expect(record.name == "Options")
    // private, static, and computed properties are excluded.
    #expect(record.properties.map(\.name) == ["name", "retries", "note"])

    let byName = Dictionary(uniqueKeysWithValues: record.properties.map { ($0.name, $0) })
    // A property is required only when it has no default and isn't optional.
    #expect(byName["name"]?.isOptional == false)
    #expect(byName["name"]?.hasDefault == false)
    #expect(byName["name"]?.isRequired == true)
    // A defaulted property is not required.
    #expect(byName["retries"]?.hasDefault == true)
    #expect(byName["retries"]?.isOptional == false)
    #expect(byName["retries"]?.isRequired == false)
    // An optional property is not required (decodes to nil when omitted), even with no written default.
    #expect(byName["note"]?.isOptional == true)
    #expect(byName["note"]?.hasDefault == false)
    #expect(byName["note"]?.isRequired == false)
  }
}

@Suite("Exports surface: scoping")
struct SurfaceScopingTests {
  @Test
  func `Ignores non-Expo types and nested types`() {
    let visitor = surface(
      """
      final class Plain {
        @JS func notExported() {}
      }
      @ExpoModule
      final class Outer {
        @JS func exported() {}
        @ExpoModule
        final class Nested {
          @JS func nested() {}
        }
      }
      """
    )
    // A plain class contributes nothing, and a nested @ExpoModule isn't descended into.
    #expect(visitor.modules.map(\.name) == ["Outer"])
    #expect(visitor.modules.first?.functions.map(\.name) == ["exported"])
  }

  @Test
  func `Routes each macro to its own bucket`() {
    let visitor = surface(
      """
      @ExpoModule final class M {}
      @SharedObject final class S: SharedObject {}
      @Record struct R { var x: Int = 0 }
      """
    )
    #expect(visitor.modules.map(\.name) == ["M"])
    #expect(visitor.sharedObjects.map(\.name) == ["S"])
    #expect(visitor.records.map(\.name) == ["R"])
  }
}

@Suite("scan-exports over a directory")
struct ScanExportsTests {
  /// Writes `files` (relative path, contents) into a fresh temp tree, runs `scanExports` over its
  /// root, and hands the result to `body`. The tree is removed afterward.
  private func withTree(
    _ files: [(String, String)],
    _ body: (ScanExportsResult) throws -> Void
  ) throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("scanner-exports-\(ProcessInfo.processInfo.globallyUniqueString)")
    defer { try? fileManager.removeItem(at: root) }

    for (relativePath, contents) in files {
      let url = root.appendingPathComponent(relativePath)
      try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    try body(scanExports(paths: [root.path]))
  }

  @Test
  func `Collects every kind across a tree, with absolute file paths and stats`() throws {
    try withTree([
      ("Module.swift", "@ExpoModule\nfinal class M { @JS func f() {} }"),
      ("Shared.swift", "@SharedObject\nfinal class S: SharedObject { @JS init() {} }"),
      ("Options.swift", "@Record\nstruct R { var name: String }"),
      ("Plain.swift", "final class Plain {}"),
    ]) { result in
      #expect(result.exports.modules.map(\.name) == ["M"])
      #expect(result.exports.sharedObjects.map(\.name) == ["S"])
      #expect(result.exports.records.map(\.name) == ["R"])
      // Reported paths are absolute.
      #expect(result.exports.modules.first?.file.hasPrefix("/") == true)
      // All four files are read; the plain one (no macro) isn't parsed.
      #expect(result.stats.filesScanned == 4)
      #expect(result.stats.filesParsed == 3)
    }
  }
}
