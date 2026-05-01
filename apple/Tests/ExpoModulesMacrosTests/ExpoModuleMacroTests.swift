import ExpoModulesMacros
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let exposeMacroSpecs: [String: MacroSpec] = [
  "JS": MacroSpec(type: JSMacro.self),
  "ExpoModule": MacroSpec(type: ExpoModuleMacro.self),
]

private func assertExpansion(
  _ original: String,
  expandedSource expected: String,
  sourceLocation: Testing.SourceLocation = #_sourceLocation,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  line: UInt = #line,
  column: UInt = #column
) {
  assertMacroExpansion(
    original,
    expandedSource: expected,
    macroSpecs: exposeMacroSpecs,
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

@Suite("@ExpoModule / @JS macros")
struct ExpoModuleMacroTests {
  @Test
  func `Module with no exposed members emits a Name-only definition derived from the class name`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
      }
      """,
      expandedSource: """
        final class MyModule: Module {

          public func _exposedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }
        }
        """
    )
  }

  @Test
  func `Custom module name overrides the class name`() {
    assertExpansion(
      """
      @ExpoModule("CustomName")
      final class MyModule: Module {
      }
      """,
      expandedSource: """
        final class MyModule: Module {

          public func _exposedDefinition() -> [AnyDefinition] {
            return [
              Name("CustomName")
            ]
          }
        }
        """
    )
  }

  @Test
  func `Sync function generates a Function entry`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        func greet(name: String) -> String { "Hi" }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func greet(name: String) -> String { "Hi" }

          public func _exposedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule"),
              Function("greet", greet)
            ]
          }
        }
        """
    )
  }

  @Test
  func `Async function generates an AsyncFunction entry with custom JS name`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS("doWork")
        func performWork() async throws {}
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          func performWork() async throws {}

          public func _exposedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule"),
              AsyncFunction("doWork", performWork)
            ]
          }
        }
        """
    )
  }

  @Test
  func `Property generates a Property entry that reads self.<name>`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        var status: String { "ok" }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          var status: String { "ok" }

          public func _exposedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule"),
              Property("status") {
                self.status
              }
            ]
          }
        }
        """
    )
  }

  @Test
  func `Mixed members: only @JS-marked ones are picked up`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        func greet(name: String) -> String { "Hi" }

        @JS
        var status: String { "ok" }

        func notExposed() {}
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func greet(name: String) -> String { "Hi" }
          @JavaScriptActor
          var status: String { "ok" }

          func notExposed() {}

          public func _exposedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule"),
              Function("greet", greet),
              Property("status") {
                self.status
              }
            ]
          }
        }
        """
    )
  }

  @Test
  func `nonisolated members are not stamped with @JavaScriptActor`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        nonisolated func compute() -> Int { 42 }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          nonisolated func compute() -> Int { 42 }

          public func _exposedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule"),
              Function("compute", compute)
            ]
          }
        }
        """
    )
  }

  @Test
  func `members already on a global actor are not stamped`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        @MainActor
        func uiOnly() -> Int { 0 }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @MainActor
          func uiOnly() -> Int { 0 }

          public func _exposedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule"),
              Function("uiOnly", uiOnly)
            ]
          }
        }
        """
    )
  }

  @Test
  func `members of an actor-isolated class are not stamped`() {
    assertExpansion(
      """
      @ExpoModule
      @MainActor
      final class MyModule: Module {
        @JS
        func uiOnly() -> Int { 0 }
      }
      """,
      expandedSource: """
        @MainActor
        final class MyModule: Module {
          func uiOnly() -> Int { 0 }

          public func _exposedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule"),
              Function("uiOnly", uiOnly)
            ]
          }
        }
        """
    )
  }
}
