import ExpoModulesMacros
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let sharedObjectMacroSpecs: [String: MacroSpec] = [
  "JS": MacroSpec(type: JSMacro.self),
  "ExpoModule": MacroSpec(type: ExpoModuleMacro.self, conformances: ["AnyModule"]),
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

          public static func _synthesizedClassDefinition() -> ClassDefinition {
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

          public static func _synthesizedClassDefinition() -> ClassDefinition {
            return Class("MyCache", Cache.self) {
            }
          }
        }
        """
    )
  }

  @Test
  func `Sync method binds via _decorateSharedObject, unwrapping the receiver from this`() {
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

          public static func _synthesizedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
            }
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "get", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let result = _self.get(arg0)
              return try String?.encode(result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Async method binds through the async setProperty overload`() {
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
          @JavaScriptActor
          func load() async throws {}

          public static func _synthesizedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
            }
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("loadAsync") { this, arguments in
              let _self = try SharedObject.native(from: this.asObject(), as: Cache.self)
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "loadAsync", received: arguments.count, required: 0, maximum: 0))
              }
              try await _self.load()
              return .undefined
            }
          }
        }
        """
    )
  }

  @Test
  func `A non-primitive property routes through the dynamic converter and unwraps the receiver`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        var owner: SomeType!
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          var owner: SomeType!

          private func _assertTypesConformance_owner() {
            func owner<A0: JavaScriptDecodable, Return: JavaScriptEncodable>(_: A0.Type, _: Return.Type) {
            }
            owner(SomeType.self, SomeType.self)
          }

          public static func _synthesizedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
            }
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let ownerDescriptor = runtime.createObject()
            ownerDescriptor.setProperty("enumerable", value: true)
            ownerDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              return try SomeType?.encode(_self.owner, in: runtime)
            }
            ownerDescriptor.setProperty("set") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              _self.owner = try SomeType?.decode(arguments.unownedValue(at: 0), in: runtime)
              return .undefined
            }
            prototype.defineProperty("owner", descriptor: ownerDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `A primitive computed property binds a get-only accessor, unwrapping the receiver`() {
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

          public static func _synthesizedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
            }
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let sizeDescriptor = runtime.createObject()
            sizeDescriptor.setProperty("enumerable", value: true)
            sizeDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              return try Int.encode(_self.size, in: runtime)
            }
            prototype.defineProperty("size", descriptor: sizeDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `@JS init binds a _constructSharedObject that builds the instance from JS arguments`() {
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

          public static func _synthesizedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
            }
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Cache", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
            return Cache(name: arg0)
          }
        }
        """
    )
  }

  @Test
  func `Mixed members: init constructs, method and property decorate`() {
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

          public static func _synthesizedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
            }
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              guard arguments.count == 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "get", received: arguments.count, required: 1, maximum: 1))
              }
              let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              let result = _self.get(arg0)
              return try String?.encode(result, in: runtime)
            }
            let sizeDescriptor = runtime.createObject()
            sizeDescriptor.setProperty("enumerable", value: true)
            sizeDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              return try Int.encode(_self.size, in: runtime)
            }
            prototype.defineProperty("size", descriptor: sizeDescriptor)
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Cache", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try String.decode(arguments.unownedValue(at: 0), in: runtime)
            return Cache(name: arg0)
          }
        }
        """
    )
  }

  @Test
  func `Trailing defaulted parameter branches the call through the unwrapped receiver`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        func resize(width: Int, height: Int = 100) -> Bool { true }
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          func resize(width: Int, height: Int = 100) -> Bool { true }

          public static func _synthesizedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
            }
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("resize") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              guard arguments.count >= 1 && arguments.count <= 2 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "resize", received: arguments.count, required: 1, maximum: 2))
              }
              let arg0 = try Int.decode(arguments.unownedValue(at: 0), in: runtime)
              let result: Bool
              switch arguments.count {
              case 1:
                result = _self.resize(width: arg0)
              default:
                let arg1 = try Int.decode(arguments.unownedValue(at: 1), in: runtime)
                result = _self.resize(width: arg0, height: arg1)
              }
              return try Bool.encode(result, in: runtime)
            }
          }
        }
        """
    )
  }

  @Test
  func `Settable stored property binds a getter and setter through the unwrapped receiver`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        var name: String = ""
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          var name: String = ""

          public static func _synthesizedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
            }
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            let nameDescriptor = runtime.createObject()
            nameDescriptor.setProperty("enumerable", value: true)
            nameDescriptor.setProperty("get") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              return try String.encode(_self.name, in: runtime)
            }
            nameDescriptor.setProperty("set") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              _self.name = try String.decode(arguments.unownedValue(at: 0), in: runtime)
              return .undefined
            }
            prototype.defineProperty("name", descriptor: nameDescriptor)
          }
        }
        """
    )
  }

  @Test
  func `No-argument void method calls through and returns undefined`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        func clear() {}
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          func clear() {}

          public static func _synthesizedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
            }
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("clear") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "clear", received: arguments.count, required: 0, maximum: 0))
              }
              _self.clear()
              return .undefined
            }
          }
        }
        """
    )
  }

  @Test
  func `No-argument init constructs without an arity guard body`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        init() {}
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          init() {}

          public static func _synthesizedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
            }
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 0 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Cache", received: arguments.count, required: 0, maximum: 0))
            }
            return Cache()
          }
        }
        """
    )
  }

  @Test
  func `Non-primitive constructor argument decodes through the dynamic converter`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        init(config: MyRecord) {}
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          init(config: MyRecord) {}

          public static func _synthesizedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
            }
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Cache", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try MyRecord.decode(arguments.unownedValue(at: 0), in: runtime)
            return Cache(config: arg0)
          }
        }
        """
    )
  }

  @Test
  func `Implicitly-unwrapped constructor argument normalizes to optional in the cast expression`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        init(config: MyRecord!) {}
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          init(config: MyRecord!) {}

          public static func _synthesizedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
            }
          }

          @JavaScriptActor
          public override class func _constructSharedObject(this: JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime) throws -> SharedObject? {
            guard arguments.count == 1 else {
              throw Exceptions.ArgumentsRangeMismatch((functionName: "Cache", received: arguments.count, required: 1, maximum: 1))
            }
            let arg0 = try MyRecord?.decode(arguments.unownedValue(at: 0), in: runtime)
            return Cache(config: arg0)
          }
        }
        """
    )
  }

  @Test
  func `Implicitly-unwrapped method argument and return normalize to optional through the receiver`() {
    assertExpansion(
      """
      @SharedObject
      final class Cache: SharedObject {
        @JS
        func resolve(_ input: MyRecord!) -> MyRecord! { input }
      }
      """,
      expandedSource: """
        final class Cache: SharedObject {
          @JavaScriptActor
          func resolve(_ input: MyRecord!) -> MyRecord! { input }

          private func _assertTypesConformance_resolve() {
            func resolve<A0: JavaScriptDecodable, Return: JavaScriptEncodable>(_: A0.Type, _: Return.Type) {
            }
            resolve(MyRecord.self, MyRecord.self)
          }

          public static func _synthesizedClassDefinition() -> ClassDefinition {
            return Class("Cache", Cache.self) {
            }
          }

          @JavaScriptActor
          public override class func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            prototype.setProperty("resolve") { (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              let _self = try SharedObject.native(from: this.asObject(in: runtime), as: Cache.self)
              guard arguments.count >= 0 && arguments.count <= 1 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "resolve", received: arguments.count, required: 0, maximum: 1))
              }
              let result: MyRecord?
              switch arguments.count {
              case 0:
                result = _self.resolve(nil)
              default:
                let arg0 = try MyRecord?.decode(arguments.unownedValue(at: 0), in: runtime)
                result = _self.resolve(arg0)
              }
              return try MyRecord?.encode(result, in: runtime)
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
  func `classes: list emits _synthesizedClassDefinition() entries`() {
    assertExpansion(
      """
      @ExpoModule(classes: [Cache.self, UserSession.self])
      final class MyModule: Module {
      }
      """,
      expandedSource: """
        final class MyModule: Module {

          public static let _jsName = "MyModule"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Cache._synthesizedClassDefinition(),
              UserSession._synthesizedClassDefinition()
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

          public static let _jsName = "CustomName"

          public func _synthesizedDefinition() -> [AnyDefinition] {
            return [
              Cache._synthesizedClassDefinition()
            ]
          }

          @JavaScriptActor
          public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime) throws {
            object.setProperty("ping") { [self] (this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer) in
              guard arguments.count == 0 else {
                throw Exceptions.ArgumentsRangeMismatch((functionName: "ping", received: arguments.count, required: 0, maximum: 0))
              }
              let result = self.ping()
              return try String.encode(result, in: runtime)
            }
          }
        }
        """
    )
  }
}
