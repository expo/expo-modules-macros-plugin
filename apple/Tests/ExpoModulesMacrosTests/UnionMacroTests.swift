import ExpoModulesMacros
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let unionMacroSpecs: [String: MacroSpec] = [
  "Union": MacroSpec(type: UnionMacro.self, conformances: ["JavaScriptDecodable", "JavaScriptEncodable"])
]

private func assertExpansion(
  _ original: String,
  expandedSource expected: String,
  diagnostics: [DiagnosticSpec] = [],
  applyFixIts: [String]? = nil,
  fixedSource: String? = nil,
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
    macroSpecs: unionMacroSpecs,
    applyFixIts: applyFixIts,
    fixedSource: fixedSource,
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

@Suite("@Union macro")
struct UnionMacroTests {
  @Test
  func `Cases decode in declaration order and encode through their payload type`() {
    assertExpansion(
      """
      @Union
      enum Source {
        case text(String)
        case options(SourceOptions)
      }
      """,
      expandedSource: """
        enum Source {
          case text(String)
          case options(SourceOptions)

          private func _assertTypesConformance() {
            func options<T: JavaScriptDecodable & JavaScriptEncodable>(_: T.Type) {
            }
            options(SourceOptions.self)
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            if let payload = try? String.decode(value, in: runtime) {
              return .text(payload)
            }
            if let payload = try? SourceOptions.decode(value, in: runtime) {
              return .options(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: value.kind.rawValue, expected: ["String", "SourceOptions"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .text(let payload):
              return try String.encode(payload, in: runtime)
            case .options(let payload):
              return try SourceOptions.encode(payload, in: runtime)
            }
          }

          public func `as`(_ type: String.Type) throws -> String {
            if case .text(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: _payloadTypeName, expected: ["String"]))
          }

          public func `as`(_ type: SourceOptions.Type) throws -> SourceOptions {
            if case .options(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: _payloadTypeName, expected: ["SourceOptions"]))
          }

          private var _payloadTypeName: String {
            switch self {
            case .text:
              return "String"
            case .options:
              return "SourceOptions"
            }
          }
        }

        extension Source: JavaScriptDecodable, JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Primitive-only payloads emit no conformance assertion`() {
    assertExpansion(
      """
      @Union
      enum Size {
        case named(String)
        case points(Double)
      }
      """,
      expandedSource: """
        enum Size {
          case named(String)
          case points(Double)

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            if let payload = try? String.decode(value, in: runtime) {
              return .named(payload)
            }
            if let payload = try? Double.decode(value, in: runtime) {
              return .points(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Size", received: value.kind.rawValue, expected: ["String", "Double"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .named(let payload):
              return try String.encode(payload, in: runtime)
            case .points(let payload):
              return try Double.encode(payload, in: runtime)
            }
          }

          public func `as`(_ type: String.Type) throws -> String {
            if case .named(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Size", received: _payloadTypeName, expected: ["String"]))
          }

          public func `as`(_ type: Double.Type) throws -> Double {
            if case .points(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Size", received: _payloadTypeName, expected: ["Double"]))
          }

          private var _payloadTypeName: String {
            switch self {
            case .named:
              return "String"
            case .points:
              return "Double"
            }
          }
        }

        extension Size: JavaScriptDecodable, JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Composed payload types are decoded, encoded, and asserted verbatim`() {
    assertExpansion(
      """
      @Union
      enum Input {
        case single(Point)
        case many([Point])
        case keyed([String: Point])
        case maybe(Int?)
      }
      """,
      expandedSource: """
        enum Input {
          case single(Point)
          case many([Point])
          case keyed([String: Point])
          case maybe(Int?)

          private func _assertTypesConformance() {
            func single<T: JavaScriptDecodable & JavaScriptEncodable>(_: T.Type) {
            }
            single(Point.self)
            func many<T: JavaScriptDecodable & JavaScriptEncodable>(_: T.Type) {
            }
            many([Point].self)
            func keyed<T: JavaScriptDecodable & JavaScriptEncodable>(_: T.Type) {
            }
            keyed([String: Point].self)
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            if let payload = try? Point.decode(value, in: runtime) {
              return .single(payload)
            }
            if let payload = try? [Point].decode(value, in: runtime) {
              return .many(payload)
            }
            if let payload = try? [String: Point].decode(value, in: runtime) {
              return .keyed(payload)
            }
            if let payload = try? Int?.decode(value, in: runtime) {
              return .maybe(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Input", received: value.kind.rawValue, expected: ["Point", "[Point]", "[String: Point]", "Int?"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .single(let payload):
              return try Point.encode(payload, in: runtime)
            case .many(let payload):
              return try [Point].encode(payload, in: runtime)
            case .keyed(let payload):
              return try [String: Point].encode(payload, in: runtime)
            case .maybe(let payload):
              return try Int?.encode(payload, in: runtime)
            }
          }

          public func `as`(_ type: Point.Type) throws -> Point {
            if case .single(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Input", received: _payloadTypeName, expected: ["Point"]))
          }

          public func `as`(_ type: [Point].Type) throws -> [Point] {
            if case .many(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Input", received: _payloadTypeName, expected: ["[Point]"]))
          }

          public func `as`(_ type: [String: Point].Type) throws -> [String: Point] {
            if case .keyed(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Input", received: _payloadTypeName, expected: ["[String: Point]"]))
          }

          public func `as`(_ type: Int?.Type) throws -> Int? {
            if case .maybe(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Input", received: _payloadTypeName, expected: ["Int?"]))
          }

          private var _payloadTypeName: String {
            switch self {
            case .single:
              return "Point"
            case .many:
              return "[Point]"
            case .keyed:
              return "[String: Point]"
            case .maybe:
              return "Int?"
            }
          }
        }

        extension Input: JavaScriptDecodable, JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `A labeled associated value is constructed with its label`() {
    assertExpansion(
      """
      @Union
      enum Reference {
        case id(value: Int)
        case name(_ value: String)
      }
      """,
      expandedSource: """
        enum Reference {
          case id(value: Int)
          case name(_ value: String)

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            if let payload = try? Int.decode(value, in: runtime) {
              return .id(value: payload)
            }
            if let payload = try? String.decode(value, in: runtime) {
              return .name(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Reference", received: value.kind.rawValue, expected: ["Int", "String"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .id(let payload):
              return try Int.encode(payload, in: runtime)
            case .name(let payload):
              return try String.encode(payload, in: runtime)
            }
          }

          public func `as`(_ type: Int.Type) throws -> Int {
            if case .id(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Reference", received: _payloadTypeName, expected: ["Int"]))
          }

          public func `as`(_ type: String.Type) throws -> String {
            if case .name(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Reference", received: _payloadTypeName, expected: ["String"]))
          }

          private var _payloadTypeName: String {
            switch self {
            case .id:
              return "Int"
            case .name:
              return "String"
            }
          }
        }

        extension Reference: JavaScriptDecodable, JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Several elements in one case declaration are separate alternatives`() {
    assertExpansion(
      """
      @Union
      enum Scalar {
        case flag(Bool), count(Int)
      }
      """,
      expandedSource: """
        enum Scalar {
          case flag(Bool), count(Int)

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            if let payload = try? Bool.decode(value, in: runtime) {
              return .flag(payload)
            }
            if let payload = try? Int.decode(value, in: runtime) {
              return .count(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Scalar", received: value.kind.rawValue, expected: ["Bool", "Int"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .flag(let payload):
              return try Bool.encode(payload, in: runtime)
            case .count(let payload):
              return try Int.encode(payload, in: runtime)
            }
          }

          public func `as`(_ type: Bool.Type) throws -> Bool {
            if case .flag(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Scalar", received: _payloadTypeName, expected: ["Bool"]))
          }

          public func `as`(_ type: Int.Type) throws -> Int {
            if case .count(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Scalar", received: _payloadTypeName, expected: ["Int"]))
          }

          private var _payloadTypeName: String {
            switch self {
            case .flag:
              return "Bool"
            case .count:
              return "Int"
            }
          }
        }

        extension Scalar: JavaScriptDecodable, JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Implicitly-unwrapped optional payload normalizes to optional in expressions`() {
    assertExpansion(
      """
      @Union
      enum Slot {
        case record(MyRecord!)
      }
      """,
      expandedSource: """
        enum Slot {
          case record(MyRecord!)

          private func _assertTypesConformance() {
            func record<T: JavaScriptDecodable & JavaScriptEncodable>(_: T.Type) {
            }
            record(MyRecord.self)
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            if let payload = try? MyRecord?.decode(value, in: runtime) {
              return .record(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Slot", received: value.kind.rawValue, expected: ["MyRecord!"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .record(let payload):
              return try MyRecord?.encode(payload, in: runtime)
            }
          }

          public func `as`(_ type: MyRecord?.Type) throws -> MyRecord? {
            if case .record(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Slot", received: _payloadTypeName, expected: ["MyRecord!"]))
          }

          private var _payloadTypeName: String {
            switch self {
            case .record:
              return "MyRecord!"
            }
          }
        }

        extension Slot: JavaScriptDecodable, JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Non-case members are ignored`() {
    assertExpansion(
      """
      @Union
      enum Source {
        case text(String)

        static let fallback = Source.text("")

        var isText: Bool {
          if case .text = self { return true }
          return false
        }
      }
      """,
      expandedSource: """
        enum Source {
          case text(String)

          static let fallback = Source.text("")

          var isText: Bool {
            if case .text = self { return true }
            return false
          }

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            if let payload = try? String.decode(value, in: runtime) {
              return .text(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: value.kind.rawValue, expected: ["String"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .text(let payload):
              return try String.encode(payload, in: runtime)
            }
          }

          public func `as`(_ type: String.Type) throws -> String {
            if case .text(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: _payloadTypeName, expected: ["String"]))
          }

          private var _payloadTypeName: String {
            switch self {
            case .text:
              return "String"
            }
          }
        }

        extension Source: JavaScriptDecodable, JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Conformances already declared are not repeated`() {
    assertExpansion(
      """
      @Union
      enum Source: JavaScriptDecodable, Sendable {
        case text(String)
      }
      """,
      expandedSource: """
        enum Source: JavaScriptDecodable, Sendable {
          case text(String)

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            if let payload = try? String.decode(value, in: runtime) {
              return .text(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: value.kind.rawValue, expected: ["String"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .text(let payload):
              return try String.encode(payload, in: runtime)
            }
          }

          public func `as`(_ type: String.Type) throws -> String {
            if case .text(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: _payloadTypeName, expected: ["String"]))
          }

          private var _payloadTypeName: String {
            switch self {
            case .text:
              return "String"
            }
          }
        }

        extension Source: JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Both conformances already declared emit no extension`() {
    assertExpansion(
      """
      @Union
      enum Source: JavaScriptDecodable, JavaScriptEncodable {
        case text(String)
      }
      """,
      expandedSource: """
        enum Source: JavaScriptDecodable, JavaScriptEncodable {
          case text(String)

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            if let payload = try? String.decode(value, in: runtime) {
              return .text(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: value.kind.rawValue, expected: ["String"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .text(let payload):
              return try String.encode(payload, in: runtime)
            }
          }

          public func `as`(_ type: String.Type) throws -> String {
            if case .text(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: _payloadTypeName, expected: ["String"]))
          }

          private var _payloadTypeName: String {
            switch self {
            case .text:
              return "String"
            }
          }
        }
        """
    )
  }

  @Test
  func `Applying @Union to a struct produces a diagnostic`() {
    assertExpansion(
      """
      @Union
      struct NotAUnion {
        var value: String
      }
      """,
      expandedSource: """
        struct NotAUnion {
          var value: String
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Union can only be applied to an enum",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `Applying @Union to a generic enum produces a diagnostic`() {
    assertExpansion(
      """
      @Union
      enum Wrapper<T> {
        case value(T)
      }
      """,
      expandedSource: """
        enum Wrapper<T> {
          case value(T)
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Union cannot be applied to a generic enum: each case's payload type must be concrete so the macro can select its converter.",
          line: 2,
          column: 13
        )
      ]
    )
  }

  @Test
  func `An enum without cases produces a diagnostic`() {
    assertExpansion(
      """
      @Union
      enum Empty {
      }
      """,
      expandedSource: """
        enum Empty {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Union requires at least one case carrying an associated value",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `A case without an associated value produces a diagnostic on the case`() {
    assertExpansion(
      """
      @Union
      enum Source {
        case text(String)
        case none
      }
      """,
      expandedSource: """
        enum Source {
          case text(String)
          case none
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Union case 'none' must carry exactly one associated value: the type this alternative decodes from. A payload-less enum is not a union; make it a raw-value enum conforming to 'Enumerable' instead.",
          line: 4,
          column: 8
        )
      ]
    )
  }

  @Test
  func `A case with several associated values produces a diagnostic on the case`() {
    assertExpansion(
      """
      @Union
      enum Source {
        case pair(String, Int)
      }
      """,
      expandedSource: """
        enum Source {
          case pair(String, Int)
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Union case 'pair' must carry exactly one associated value, but has 2. Group them in a @Record type and use it as the single payload.",
          line: 3,
          column: 8
        )
      ]
    )
  }

  @Test
  func `A case repeating an earlier payload type produces a diagnostic on the later case`() {
    assertExpansion(
      """
      @Union
      enum Source {
        case text(String)
        case keyed([String : Int])
        case name(String)
        case dictionary([String: Int])
      }
      """,
      expandedSource: """
        enum Source {
          case text(String)
          case keyed([String : Int])
          case name(String)
          case dictionary([String: Int])
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Union case 'name' repeats the payload type 'String' of case 'text' and can never be decoded: alternatives are tried in declaration order and the first match wins.",
          line: 5,
          column: 8
        ),
        DiagnosticSpec(
          message:
            "@Union case 'dictionary' repeats the payload type '[String: Int]' of case 'keyed' and can never be decoded: alternatives are tried in declaration order and the first match wins.",
          line: 6,
          column: 8
        ),
      ]
    )
  }

  @Test
  func `A qualified conformance in the inheritance clause is recognized`() {
    assertExpansion(
      """
      @Union
      enum Source: ExpoModulesJSI.JavaScriptEncodable {
        case text(String)
      }
      """,
      expandedSource: """
        enum Source: ExpoModulesJSI.JavaScriptEncodable {
          case text(String)

          @JavaScriptActor
          public static func decode(_ value: borrowing JavaScriptValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
            if let payload = try? String.decode(value, in: runtime) {
              return .text(payload)
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: value.kind.rawValue, expected: ["String"]))
          }

          @JavaScriptActor
          public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
            switch value {
            case .text(let payload):
              return try String.encode(payload, in: runtime)
            }
          }

          public func `as`(_ type: String.Type) throws -> String {
            if case .text(let payload) = self {
              return payload
            }
            throw Exceptions.UnionCaseMismatch((unionName: "Source", received: _payloadTypeName, expected: ["String"]))
          }

          private var _payloadTypeName: String {
            switch self {
            case .text:
              return "String"
            }
          }
        }

        extension Source: JavaScriptDecodable {
        }
        """
    )
  }

  @Test
  func `A default value on an associated value produces a diagnostic with a fix-it removing it`() {
    assertExpansion(
      """
      @Union
      enum Source {
        case text(String = "")
        case count(Int)
      }
      """,
      expandedSource: """
        enum Source {
          case text(String = "")
          case count(Int)
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Union case 'text' cannot give its associated value a default: the payload is always decoded from the JavaScript value, so the default would never apply. Remove '= \"\"'.",
          line: 3,
          column: 20,
          fixIts: [FixItSpec(message: "Remove the default value")]
        )
      ],
      fixedSource: """
        @Union
        enum Source {
          case text(String)
          case count(Int)
        }
        """
    )
  }

  @Test
  func `An indirect enum nested in another type extends the qualified type`() {
    assertExpansion(
      """
      struct Outer {
        @Union
        indirect enum Node {
          case leaf(Int)
          case children([Node])
        }
      }
      """,
      expandedSource: """
        struct Outer {
          indirect enum Node {
            case leaf(Int)
            case children([Node])

            private func _assertTypesConformance() {
              func children<T: JavaScriptDecodable & JavaScriptEncodable>(_: T.Type) {
              }
              children([Node].self)
            }

            @JavaScriptActor
            public static func decode(_ value: borrowing JavaScriptValue, in runtime: borrowing JavaScriptRuntime) throws -> Self {
              if let payload = try? Int.decode(value, in: runtime) {
                return .leaf(payload)
              }
              if let payload = try? [Node].decode(value, in: runtime) {
                return .children(payload)
              }
              throw Exceptions.UnionCaseMismatch((unionName: "Node", received: value.kind.rawValue, expected: ["Int", "[Node]"]))
            }

            @JavaScriptActor
            public static func encode(_ value: Self, in runtime: borrowing JavaScriptRuntime) throws -> JavaScriptValue {
              switch value {
              case .leaf(let payload):
                return try Int.encode(payload, in: runtime)
              case .children(let payload):
                return try [Node].encode(payload, in: runtime)
              }
            }

            public func `as`(_ type: Int.Type) throws -> Int {
              if case .leaf(let payload) = self {
                return payload
              }
              throw Exceptions.UnionCaseMismatch((unionName: "Node", received: _payloadTypeName, expected: ["Int"]))
            }

            public func `as`(_ type: [Node].Type) throws -> [Node] {
              if case .children(let payload) = self {
                return payload
              }
              throw Exceptions.UnionCaseMismatch((unionName: "Node", received: _payloadTypeName, expected: ["[Node]"]))
            }

            private var _payloadTypeName: String {
              switch self {
              case .leaf:
                return "Int"
              case .children:
                return "[Node]"
              }
            }
          }
        }

        extension Outer.Node: JavaScriptDecodable, JavaScriptEncodable {
        }
        """
    )
  }

  @Test
  func `Diagnostics of different kinds are all reported together`() {
    assertExpansion(
      """
      @Union
      enum Source {
        case text(String)
        case none
        case pair(Int, Int)
        case again(String)
      }
      """,
      expandedSource: """
        enum Source {
          case text(String)
          case none
          case pair(Int, Int)
          case again(String)
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Union case 'none' must carry exactly one associated value: the type this alternative decodes from. A payload-less enum is not a union; make it a raw-value enum conforming to 'Enumerable' instead.",
          line: 4,
          column: 8
        ),
        DiagnosticSpec(
          message:
            "@Union case 'pair' must carry exactly one associated value, but has 2. Group them in a @Record type and use it as the single payload.",
          line: 5,
          column: 8
        ),
        DiagnosticSpec(
          message:
            "@Union case 'again' repeats the payload type 'String' of case 'text' and can never be decoded: alternatives are tried in declaration order and the first match wins.",
          line: 6,
          column: 8
        ),
      ]
    )
  }
}
