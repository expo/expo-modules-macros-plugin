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
          func greet(name: String) -> String { "Hi" }
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
}
