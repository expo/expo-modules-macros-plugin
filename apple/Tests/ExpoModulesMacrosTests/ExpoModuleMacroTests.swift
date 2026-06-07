import ExpoModulesMacros
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macroSpecs: [String: MacroSpec] = [
  "JS": MacroSpec(type: JSMacro.self),
  "ExpoModule": MacroSpec(type: ExpoModuleMacro.self, conformances: ["AnyModule"]),
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
    macroSpecs: macroSpecs,
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

          public func _synthesizedDefinition() -> [AnyDefinition] {
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

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("CustomName")
            ]
          }
        }
        """
    )
  }

  @Test
  func `Sync function is bound directly into the JS object, not described with a Function entry`() {
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

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime, appContext: AppContext) throws {
            object.setProperty("greet") { [self] this, arguments in
              guard arguments.count == 1 else {
                throw Exception(name: "InvalidArgumentCount", description: "Function 'greet' expects 1 argument(s), but got \\(arguments.count)")
              }
              let arg0 = try arguments.unownedValue(at: 0).asString()
              let result = self.greet(name: arg0)
              return result.toJavaScriptValue(in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Multi-argument function decodes each argument by its static type and preserves labels`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        func add(_ a: Double, to b: Double) -> Double { a + b }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func add(_ a: Double, to b: Double) -> Double { a + b }

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime, appContext: AppContext) throws {
            object.setProperty("add") { [self] this, arguments in
              guard arguments.count == 2 else {
                throw Exception(name: "InvalidArgumentCount", description: "Function 'add' expects 2 argument(s), but got \\(arguments.count)")
              }
              let arg0 = try arguments.unownedValue(at: 0).asDouble()
              let arg1 = try arguments.unownedValue(at: 1).asDouble()
              let result = self.add(arg0, to: arg1)
              return result.toJavaScriptValue(in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Non-primitive argument and return types get a conformance-assertion peer`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        func transform(value: MyRecord, count: Int) -> [MyRecord] { [] }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func transform(value: MyRecord, count: Int) -> [MyRecord] { [] }

          private func _assertTypesConformance_transform() {
            func transform<T: AnyArgument>(_: T.Type) {
            }
            transform(MyRecord.self)
            transform([MyRecord].self)
          }

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime, appContext: AppContext) throws {
            object.setProperty("transform") { [weak appContext, self] this, arguments in
              guard let appContext else {
                throw Exceptions.AppContextLost()
              }
              guard arguments.count == 2 else {
                throw Exception(name: "InvalidArgumentCount", description: "Function 'transform' expects 2 argument(s), but got \\(arguments.count)")
              }
              let arg0 = try MyRecord.getDynamicType().cast(jsValue: arguments[0], appContext: appContext) as! MyRecord
              let arg1 = try arguments.unownedValue(at: 1).asInt()
              let result = self.transform(value: arg0, count: arg1)
              return try [MyRecord].getDynamicType().castToJS(result, appContext: appContext, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Static function emits a static conformance-assertion peer`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        static func describe(_ value: MyRecord) -> String { "" }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          static func describe(_ value: MyRecord) -> String { "" }

          private static func _assertTypesConformance_describe() {
            func describe<T: AnyArgument>(_: T.Type) {
            }
            describe(MyRecord.self)
          }

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime, appContext: AppContext) throws {
            object.setProperty("describe") { [weak appContext, self] this, arguments in
              guard let appContext else {
                throw Exceptions.AppContextLost()
              }
              guard arguments.count == 1 else {
                throw Exception(name: "InvalidArgumentCount", description: "Function 'describe' expects 1 argument(s), but got \\(arguments.count)")
              }
              let arg0 = try MyRecord.getDynamicType().cast(jsValue: arguments[0], appContext: appContext) as! MyRecord
              let result = self.describe(arg0)
              return result.toJavaScriptValue(in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Void throwing function calls through with try and returns undefined`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS("doReset")
        func reset() throws {}
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func reset() throws {}

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime, appContext: AppContext) throws {
            object.setProperty("doReset") { [self] this, arguments in
              guard arguments.count == 0 else {
                throw Exception(name: "InvalidArgumentCount", description: "Function 'doReset' expects 0 argument(s), but got \\(arguments.count)")
              }
              try self.reset()
              return .undefined
            }
          }
        }
        """
    )
  }

  @Test
  func `Async function is bound with an async binding and the async setProperty overload`() {
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

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime, appContext: AppContext) throws {
            object.setProperty("doWork") { [self] this, arguments in
              guard arguments.count == 0 else {
                throw Exception(name: "InvalidArgumentCount", description: "Function 'doWork' expects 0 argument(s), but got \\(arguments.count)")
              }
              try await self.performWork()
              return .undefined
            }
          }
        }
        """
    )
  }

  @Test
  func `Async function with arguments and a return value awaits the call and converts the result`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        func fetchValue(key: String) async throws -> Int { 0 }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          func fetchValue(key: String) async throws -> Int { 0 }

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime, appContext: AppContext) throws {
            object.setProperty("fetchValue") { [self] this, arguments in
              guard arguments.count == 1 else {
                throw Exception(name: "InvalidArgumentCount", description: "Function 'fetchValue' expects 1 argument(s), but got \\(arguments.count)")
              }
              let arg0 = try arguments.unownedValue(at: 0).asString()
              let result = try await self.fetchValue(key: arg0)
              return result.toJavaScriptValue(in: runtime)
            }
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

          public func _synthesizedDefinition() -> [AnyDefinition] {
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

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule"),
              Property("status") {
                self.status
              }
            ]
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime, appContext: AppContext) throws {
            object.setProperty("greet") { [self] this, arguments in
              guard arguments.count == 1 else {
                throw Exception(name: "InvalidArgumentCount", description: "Function 'greet' expects 1 argument(s), but got \\(arguments.count)")
              }
              let arg0 = try arguments.unownedValue(at: 0).asString()
              let result = self.greet(name: arg0)
              return result.toJavaScriptValue(in: runtime)
            }
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

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime, appContext: AppContext) throws {
            object.setProperty("compute") { [self] this, arguments in
              guard arguments.count == 0 else {
                throw Exception(name: "InvalidArgumentCount", description: "Function 'compute' expects 0 argument(s), but got \\(arguments.count)")
              }
              let result = self.compute()
              return result.toJavaScriptValue(in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Class without inheritance gets appContext storage, init, and an AnyModule conformance`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule {
      }
      """,
      expandedSource: """
        final class MyModule {

          public weak var appContext: AppContext?

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }
        }

        extension MyModule: AnyModule {
        }
        """
    )
  }

  @Test
  func `Class with another superclass gets appContext storage, init, and an AnyModule conformance`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: SomeOtherBase {
      }
      """,
      expandedSource: """
        final class MyModule: SomeOtherBase {

          public weak var appContext: AppContext?

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }
        }

        extension MyModule: AnyModule {
        }
        """
    )
  }

  @Test
  func `: Module does not get redundant storage, init, or AnyModule conformance`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
      }
      """,
      expandedSource: """
        final class MyModule: Module {

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }
        }
        """
    )
  }

  @Test
  func `: BaseModule does not get a redundant AnyModule conformance`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: BaseModule {
      }
      """,
      expandedSource: """
        final class MyModule: BaseModule {

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }
        }
        """
    )
  }

  @Test
  func `: AnyModule gets storage and init but no redundant conformance`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: AnyModule {
      }
      """,
      expandedSource: """
        final class MyModule: AnyModule {

          public weak var appContext: AppContext?

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }
        }
        """
    )
  }

  @Test
  func `User-provided appContext property is not overridden`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule {
        public weak var appContext: AppContext?
      }
      """,
      expandedSource: """
        final class MyModule {
          public weak var appContext: AppContext?

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }
        }

        extension MyModule: AnyModule {
        }
        """
    )
  }

  @Test
  func `User-provided init(appContext:) is not overridden`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule {
        public required init(appContext: AppContext) {}
      }
      """,
      expandedSource: """
        final class MyModule {
          public required init(appContext: AppContext) {}

          public weak var appContext: AppContext?

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }
        }

        extension MyModule: AnyModule {
        }
        """
    )
  }

  @Test
  func `init with the right type but a different label does not satisfy the requirement and is still synthesized`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule {
        public required init(c: AppContext) {}
      }
      """,
      expandedSource: """
        final class MyModule {
          public required init(c: AppContext) {}

          public weak var appContext: AppContext?

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }
        }

        extension MyModule: AnyModule {
        }
        """
    )
  }

  @Test
  func `definition() is stamped with @ModuleDefinitionBuilder`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        public func definition() -> ModuleDefinition {
          Name("MyModule")
        }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @ModuleDefinitionBuilder
          public func definition() -> ModuleDefinition {
            Name("MyModule")
          }

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }
        }
        """
    )
  }

  @Test
  func `definition() that already has @ModuleDefinitionBuilder is not stamped twice`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @ModuleDefinitionBuilder
        public func definition() -> ModuleDefinition {
          Name("MyModule")
        }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @ModuleDefinitionBuilder
          public func definition() -> ModuleDefinition {
            Name("MyModule")
          }

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Name("MyModule")
            ]
          }
        }
        """
    )
  }
}
