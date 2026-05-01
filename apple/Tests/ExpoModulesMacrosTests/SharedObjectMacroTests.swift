import ExpoModulesMacros
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let sharedObjectMacroSpecs: [String: MacroSpec] = [
  "JS": MacroSpec(type: JSMacro.self),
  "ExpoModule": MacroSpec(type: ExpoModuleMacro.self),
  "SharedObject": MacroSpec(type: SharedObjectMacro.self),
]

private func assertExpansion(
  _ original: String,
  expandedSource expected: String,
  diagnostics: [DiagnosticSpec] = [],
  sourceLocation: Testing.SourceLocation = #_sourceLocation,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  line: UInt = #line,
  column: UInt = #column
) {
  assertMacroExpansion(
    original,
    expandedSource: expected,
    diagnostics: diagnostics,
    macroSpecs: sharedObjectMacroSpecs,
    indentationWidth: .spaces(2),
    failureHandler: { spec in
      Issue.record(Comment(rawValue: spec.message), sourceLocation: sourceLocation)
    },
    fileID: fileID,
    filePath: filePath,
    line: line,
    column: column
  )
}

@Suite("@SharedObject macro")
struct SharedObjectMacroTests {
  @Test
  func `Class without : SharedObject inheritance produces a diagnostic`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache {
      }
      """,
      expandedSource: """
        final class Cache {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@SharedObject class must inherit from SharedObject. Add `: SharedObject` to the class declaration.",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `Empty class emits a Class block with no elements`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {

          public static func _exposedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
            }
          }
        }
        """
    )
  }

  @Test
  func `Custom JS name overrides the class name`() {
    assertExpansion(
      """
      @SharedObject("MyCache")
      final class Cache: SharedObject {
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {

          public static func _exposedClassDefinition() -> ClassDefinition {
            return Class("MyCache", Cache.self) {
            }
          }
        }
        """
    )
  }

  @Test
  func `Sync method emits a class-scope Function entry`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        func get(_ key: String) -> String? { nil }
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          func get(_ key: String) -> String? { nil }

          public static func _exposedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
              Function("get") { (this: Cache, _ arg0: String) in
                this.get(arg0)
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `Async method emits an AsyncFunction entry`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS("loadAsync")
        func load() async throws {}
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          func load() async throws {}

          public static func _exposedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
              AsyncFunction("loadAsync") { (this: Cache) in
                try await this.load()
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `Property emits a class-scope Property entry that takes the owner`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        var size: Int { 42 }
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          var size: Int { 42 }

          public static func _exposedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
              Property("size") { (this: Cache) in
                this.size
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `@JS init becomes a Constructor block`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        init(name: String) {}
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          init(name: String) {}

          public static func _exposedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
              Constructor { (_ arg0: String) in
                Cache(name: arg0)
              }
            }
          }
        }
        """
    )
  }

  @Test
  func `Mixed members: init + method + property all flow into the Class block`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        init(name: String) {}

        @JS
        func get(_ key: String) -> String? { nil }

        @JS
        var size: Int { 42 }
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          init(name: String) {}
          @JavaScriptActor
          func get(_ key: String) -> String? { nil }
          @JavaScriptActor
          var size: Int { 42 }

          public static func _exposedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
              Constructor { (_ arg0: String) in
                Cache(name: arg0)
              }
              Function("get") { (this: Cache, _ arg0: String) in
                this.get(arg0)
              }
              Property("size") { (this: Cache) in
                this.size
              }
            }
          }
        }
        """
    )
  }
}

@Suite("@ExpoModule classes: argument")
struct ExpoModuleClassesTests {
  @Test
  func `classes: list emits _exposedClassDefinition() entries`() {
    assertExpansion(
      """
      @ExpoModule(classes: [Cache.self, UserSession.self])
      final class MyModule: Module {
      }
      """,
      expandedSource: """
        final class MyModule: Module {

          public func _exposedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule"),
              Cache._exposedClassDefinition(),
              UserSession._exposedClassDefinition()
            ]
          }
        }
        """
    )
  }

  @Test
  func `classes: combines with custom module name and exposed members`() {
    assertExpansion(
      """
      @ExpoModule("CustomName", classes: [Cache.self])
      final class MyModule: Module {
        @JS
        func ping() -> String { "pong" }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func ping() -> String { "pong" }

          public func _exposedDefinition() -> [AnyDefinition] {
            return [
              Name("CustomName"),
              Cache._exposedClassDefinition(),
              Function("ping", ping)
            ]
          }
        }
        """
    )
  }
}
