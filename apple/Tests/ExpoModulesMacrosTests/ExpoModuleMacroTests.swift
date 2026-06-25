import ExpoModulesMacros
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macroSpecs: [String: MacroSpec] = [
  "JS": MacroSpec(type: JSMacro.self),
  "Event": MacroSpec(type: EventMacro.self),
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
  func `Module with no exposed members emits the resolved name and an empty definition`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
      }
      """,
      expandedSource: """
        final class MyModule: Module {

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
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

          public static let _jsName = "CustomName"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
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

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("greet") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "greet", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let result = self.greet(name: arg0)
              return try String.encode(result, in: runtime)
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

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("add") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "add", received: arguments.count, required: 2, maximum: 2))
              }
              let arg0 = try Double.decode(arguments.unownedValue(at: 0), in: runtime)
              let arg1 = try Double.decode(arguments.unownedValue(at: 1), in: runtime)
              let result = self.add(arg0, to: arg1)
              return try Double.encode(result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Trailing defaulted parameter widens the arity range and branches the call`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        func resize(width: Int, height: Int = 100) -> Bool { true }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func resize(width: Int, height: Int = 100) -> Bool { true }

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("resize") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count >= 1 && arguments.count <= 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "resize", received: arguments.count, required: 1, maximum: 2))
              }
              let arg0 = try Int.decode(arguments.unownedValue(at: 0), in: runtime)
              let result = switch arguments.count {
              case 1:
                self.resize(width: arg0)
              default:
                let arg1 = try Int.decode(arguments.unownedValue(at: 1), in: runtime)
                self.resize(width: arg0, height: arg1)
              }
              return try Bool.encode(result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Trailing optional parameter is passed nil when omitted`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        func tag(name: String, note: String?) { }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func tag(name: String, note: String?) { }

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("tag") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count >= 1 && arguments.count <= 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "tag", received: arguments.count, required: 1, maximum: 2))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              switch arguments.count {
              case 1:
                self.tag(name: arg0, note: nil)
              default:
                let arg1 = try String?.decode(arguments.unownedValue(at: 1), in: runtime)
                self.tag(name: arg0, note: arg1)
              }
              return .undefined
            }
          }
        }
        """
    )
  }

  @Test
  func `Only-defaulted parameters make every argument omittable (required count zero)`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        func ping(times: Int = 1) -> Int { times }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func ping(times: Int = 1) -> Int { times }

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("ping") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count >= 0 && arguments.count <= 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "ping", received: arguments.count, required: 0, maximum: 1))
              }
              let result = switch arguments.count {
              case 0:
                self.ping()
              default:
                let arg0 = try Int.decode(arguments.unownedValue(at: 0), in: runtime)
                self.ping(times: arg0)
              }
              return try Int.encode(result, in: runtime)
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
            func transform<A0: JavaScriptDecodable, Return: JavaScriptEncodable>(_: A0.Type, _: Return.Type) {
            }
            transform(MyRecord.self, [MyRecord].self)
          }

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("transform") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "transform", received: arguments.count, required: 2, maximum: 2))
              }
              let arg0 = try MyRecord.decode(arguments.unownedValue(at: 0), in: runtime)
              let arg1 = try Int.decode(arguments.unownedValue(at: 1), in: runtime)
              let result = self.transform(value: arg0, count: arg1)
              return try [MyRecord].encode(result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Multiple non-primitive arguments get indexed decodable slots in the assertion`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        func merge(primary: MyRecord, secondary: OtherRecord) -> MyRecord { primary }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func merge(primary: MyRecord, secondary: OtherRecord) -> MyRecord { primary }

          private func _assertTypesConformance_merge() {
            func merge<A0: JavaScriptDecodable, A1: JavaScriptDecodable, Return: JavaScriptEncodable>(_: A0.Type, _: A1.Type, _: Return.Type) {
            }
            merge(MyRecord.self, OtherRecord.self, MyRecord.self)
          }

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("merge") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "merge", received: arguments.count, required: 2, maximum: 2))
              }
              let arg0 = try MyRecord.decode(arguments.unownedValue(at: 0), in: runtime)
              let arg1 = try OtherRecord.decode(arguments.unownedValue(at: 1), in: runtime)
              let result = self.merge(primary: arg0, secondary: arg1)
              return try MyRecord.encode(result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Getter-only non-primitive property asserts only the encodable direction`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        var cache: MyRecord { MyRecord() }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          var cache: MyRecord { MyRecord() }

          private func _assertTypesConformance_cache() {
            func cache<Return: JavaScriptEncodable>(_: Return.Type) {
            }
            cache(MyRecord.self)
          }

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let cacheDescriptor = runtime.createObject()
            cacheDescriptor.setProperty("enumerable", value: true)
            cacheDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              return try MyRecord.encode(self.cache, in: runtime)
            }
            object.defineProperty("cache", descriptor: cacheDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `Implicitly-unwrapped optional return normalizes to optional in the cast expression`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        func make(count: Int) -> MyRecord! { nil }
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          func make(count: Int) -> MyRecord! { nil }

          private func _assertTypesConformance_make() {
            func make<Return: JavaScriptEncodable>(_: Return.Type) {
            }
            make(MyRecord.self)
          }

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("make") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "make", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try Int.decode(arguments.unownedValue(at: 0), in: runtime)
              let result = self.make(count: arg0)
              return try MyRecord?.encode(result, in: runtime)
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
            func describe<A0: JavaScriptDecodable>(_: A0.Type) {
            }
            describe(MyRecord.self)
          }

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("describe") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "describe", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try MyRecord.decode(arguments.unownedValue(at: 0), in: runtime)
              let result = self.describe(arg0)
              return try String.encode(result, in: runtime)
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

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("doReset") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "doReset", received: arguments.count, required: 0, maximum: 0))
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

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("doWork") { [self] this, arguments in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "doWork", received: arguments.count, required: 0, maximum: 0))
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

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("fetchValue") { [self] this, arguments in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "fetchValue", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let result = try await self.fetchValue(key: arg0)
              return try Int.encode(result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Getter-only property binds a get-only accessor via defineProperty`() {
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

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let statusDescriptor = runtime.createObject()
            statusDescriptor.setProperty("enumerable", value: true)
            statusDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              return try String.encode(self.status, in: runtime)
            }
            object.defineProperty("status", descriptor: statusDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `Settable stored property binds both a getter and a setter`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        var ready: Bool = false
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          var ready: Bool = false

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let readyDescriptor = runtime.createObject()
            readyDescriptor.setProperty("enumerable", value: true)
            readyDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              return try Bool.encode(self.ready, in: runtime)
            }
            readyDescriptor.setProperty("set") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              self.ready = try Bool.decode(arguments.unownedValue(at: 0), in: runtime)
              return .undefined
            }
            object.defineProperty("ready", descriptor: readyDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `Non-primitive property captures appContext and routes through the dynamic converter`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        var config: MyRecord
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          var config: MyRecord

          private func _assertTypesConformance_config() {
            func config<A0: JavaScriptDecodable, Return: JavaScriptEncodable>(_: A0.Type, _: Return.Type) {
            }
            config(MyRecord.self, MyRecord.self)
          }

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let configDescriptor = runtime.createObject()
            configDescriptor.setProperty("enumerable", value: true)
            configDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              return try MyRecord.encode(self.config, in: runtime)
            }
            configDescriptor.setProperty("set") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              self.config = try MyRecord.decode(arguments.unownedValue(at: 0), in: runtime)
              return .undefined
            }
            object.defineProperty("config", descriptor: configDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `Implicitly-unwrapped optional property normalizes the type to optional in the cast expressions`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @JS
        var config: MyRecord!
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          var config: MyRecord!

          private func _assertTypesConformance_config() {
            func config<A0: JavaScriptDecodable, Return: JavaScriptEncodable>(_: A0.Type, _: Return.Type) {
            }
            config(MyRecord.self, MyRecord.self)
          }

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let configDescriptor = runtime.createObject()
            configDescriptor.setProperty("enumerable", value: true)
            configDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              return try MyRecord?.encode(self.config, in: runtime)
            }
            configDescriptor.setProperty("set") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              self.config = try MyRecord?.decode(arguments.unownedValue(at: 0), in: runtime)
              return .undefined
            }
            object.defineProperty("config", descriptor: configDescriptor)
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

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("greet") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "greet", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let result = self.greet(name: arg0)
              return try String.encode(result, in: runtime)
            }
            let statusDescriptor = runtime.createObject()
            statusDescriptor.setProperty("enumerable", value: true)
            statusDescriptor.setProperty("get") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              return try String.encode(self.status, in: runtime)
            }
            object.defineProperty("status", descriptor: statusDescriptor)
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

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("compute") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "compute", received: arguments.count, required: 0, maximum: 0))
              }
              let result = self.compute()
              return try Int.encode(result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Sync @Event member is stamped with @JavaScriptActor while the async default is not`() {
    assertExpansion(
      """
      @ExpoModule
      final class MyModule: Module {
        @Event(sync: true)
        var onTick: () -> Void

        @Event
        var onReady: () -> Void
      }
      """,
      expandedSource: """
        final class MyModule: Module {
          @JavaScriptActor
          var onTick: () -> Void {
            get {
              { [weak self] in
                self?.emitSync(event: "tick")
              }
            }
          }

          private func _assertTypesConformance_onTick() {
            func onTick<E: EventEmitter>(_: E.Type) {
            }
            onTick(MyModule.self)
          }
          var onReady: () -> Void {
            get {
              { [weak self] in
                self?.emit(event: "ready")
              }
            }
          }

          private func _assertTypesConformance_onReady() {
            func onReady<E: EventEmitter>(_: E.Type) {
            }
            onReady(MyModule.self)
          }

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
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

          public static let _jsName = "MyModule"

          public weak var appContext: AppContext?

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
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

          public static let _jsName = "MyModule"

          public weak var appContext: AppContext?

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
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

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
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

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
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

          public static let _jsName = "MyModule"

          public weak var appContext: AppContext?

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
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

          public static let _jsName = "MyModule"

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
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

          public static let _jsName = "MyModule"

          public weak var appContext: AppContext?

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
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

          public static let _jsName = "MyModule"

          public weak var appContext: AppContext?

          public required init(appContext: AppContext) {
            self.appContext = appContext
          }

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
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

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
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

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return []
          }
        }
        """
    )
  }
}
