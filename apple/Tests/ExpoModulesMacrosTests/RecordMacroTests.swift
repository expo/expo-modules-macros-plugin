import ExpoModulesMacros
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let recordMacroSpecs: [String: MacroSpec] = [
  "Record": MacroSpec(type: RecordMacro.self)
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
    macroSpecs: recordMacroSpecs,
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

@Suite("@Record macro")
struct RecordMacroTests {
  @Test
  func `All stored properties become record properties with requiredness inferred from the declaration`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var name: String
        var count: Int = 0
        var note: String?
      }
      """,
      expandedSource: """
        struct Options {
          var name: String
          var count: Int = 0
          var note: String?

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(name: String, count: Int, note: String? = nil) {
            self.name = name
            self.count = count
            self.note = note
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let nameJSValue = object.getProperty("name")
            guard !nameJSValue.isUndefined() else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.getDynamicType().cast(jsValue: nameJSValue, appContext: appContext) as! String
            let countJSValue = object.getProperty("count")
            let count = countJSValue.isUndefined() ? 0 : try Int.getDynamicType().cast(jsValue: countJSValue, appContext: appContext) as! Int
            let noteJSValue = object.getProperty("note")
            let note: String? = (noteJSValue.isUndefined() || noteJSValue.isNull()) ? nil : try String?.getDynamicType().cast(jsValue: noteJSValue, appContext: appContext) as! String?
            return Self(name: name, count: count, note: note)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let nameValue = dictionary["name"]
            guard let nameValue else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.getDynamicType().cast(nameValue, appContext: appContext) as! String
            let countValue = dictionary["count"]
            let count = countValue == nil ? 0 : try Int.getDynamicType().cast(countValue, appContext: appContext) as! Int
            let noteValue = dictionary["note"]
            let note: String? = (noteValue == nil || noteValue! is NSNull) ? nil : try String?.getDynamicType().cast(noteValue, appContext: appContext) as! String?
            return Self(name: name, count: count, note: note)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["name"] = self.name
            dictionary["count"] = self.count
            dictionary["note"] = self.note
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let object = try appContext.runtime.createObject()
            object.setProperty("name", value: try String.getDynamicType().convertToJS(self.name, appContext: appContext))
            object.setProperty("count", value: try Int.getDynamicType().convertToJS(self.count, appContext: appContext))
            object.setProperty("note", value: try String?.getDynamicType().convertToJS(self.note, appContext: appContext))
            return object
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `Non-primitive properties are checked in a single conformance-assertion peer`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var primary: MyRecord
        var tags: [String]
        var count: Int = 0
      }
      """,
      expandedSource: """
        struct Options {
          var primary: MyRecord
          var tags: [String]
          var count: Int = 0

          private func _assertTypesConformance() {
            func primary<T: AnyArgument>(_: T.Type) {
            }
            primary(MyRecord.self)
            func tags<T: AnyArgument>(_: T.Type) {
            }
            tags([String].self)
          }

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(primary: MyRecord, tags: [String], count: Int) {
            self.primary = primary
            self.tags = tags
            self.count = count
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let primaryJSValue = object.getProperty("primary")
            guard !primaryJSValue.isUndefined() else {
              throw RecordPropertyRequiredException("primary")
            }
            let primary = try MyRecord.getDynamicType().cast(jsValue: primaryJSValue, appContext: appContext) as! MyRecord
            let tagsJSValue = object.getProperty("tags")
            guard !tagsJSValue.isUndefined() else {
              throw RecordPropertyRequiredException("tags")
            }
            let tags = try [String].getDynamicType().cast(jsValue: tagsJSValue, appContext: appContext) as! [String]
            let countJSValue = object.getProperty("count")
            let count = countJSValue.isUndefined() ? 0 : try Int.getDynamicType().cast(jsValue: countJSValue, appContext: appContext) as! Int
            return Self(primary: primary, tags: tags, count: count)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let primaryValue = dictionary["primary"]
            guard let primaryValue else {
              throw RecordPropertyRequiredException("primary")
            }
            let primary = try MyRecord.getDynamicType().cast(primaryValue, appContext: appContext) as! MyRecord
            let tagsValue = dictionary["tags"]
            guard let tagsValue else {
              throw RecordPropertyRequiredException("tags")
            }
            let tags = try [String].getDynamicType().cast(tagsValue, appContext: appContext) as! [String]
            let countValue = dictionary["count"]
            let count = countValue == nil ? 0 : try Int.getDynamicType().cast(countValue, appContext: appContext) as! Int
            return Self(primary: primary, tags: tags, count: count)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["primary"] = self.primary
            dictionary["tags"] = self.tags
            dictionary["count"] = self.count
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let object = try appContext.runtime.createObject()
            object.setProperty("primary", value: try MyRecord.getDynamicType().convertToJS(self.primary, appContext: appContext))
            object.setProperty("tags", value: try [String].getDynamicType().convertToJS(self.tags, appContext: appContext))
            object.setProperty("count", value: try Int.getDynamicType().convertToJS(self.count, appContext: appContext))
            return object
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `Property types are inferred from scalar literal defaults when the annotation is omitted`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var name = "foo"
        var ratio = 1.0
        var count = 0
        var flag = false
      }
      """,
      expandedSource: """
        struct Options {
          var name = "foo"
          var ratio = 1.0
          var count = 0
          var flag = false

          public init() {
          }

          public init(name: String, ratio: Double, count: Int, flag: Bool) {
            self.name = name
            self.ratio = ratio
            self.count = count
            self.flag = flag
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let nameJSValue = object.getProperty("name")
            let name = nameJSValue.isUndefined() ? "foo" : try String.getDynamicType().cast(jsValue: nameJSValue, appContext: appContext) as! String
            let ratioJSValue = object.getProperty("ratio")
            let ratio = ratioJSValue.isUndefined() ? 1.0 : try Double.getDynamicType().cast(jsValue: ratioJSValue, appContext: appContext) as! Double
            let countJSValue = object.getProperty("count")
            let count = countJSValue.isUndefined() ? 0 : try Int.getDynamicType().cast(jsValue: countJSValue, appContext: appContext) as! Int
            let flagJSValue = object.getProperty("flag")
            let flag = flagJSValue.isUndefined() ? false : try Bool.getDynamicType().cast(jsValue: flagJSValue, appContext: appContext) as! Bool
            return Self(name: name, ratio: ratio, count: count, flag: flag)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let nameValue = dictionary["name"]
            let name = nameValue == nil ? "foo" : try String.getDynamicType().cast(nameValue, appContext: appContext) as! String
            let ratioValue = dictionary["ratio"]
            let ratio = ratioValue == nil ? 1.0 : try Double.getDynamicType().cast(ratioValue, appContext: appContext) as! Double
            let countValue = dictionary["count"]
            let count = countValue == nil ? 0 : try Int.getDynamicType().cast(countValue, appContext: appContext) as! Int
            let flagValue = dictionary["flag"]
            let flag = flagValue == nil ? false : try Bool.getDynamicType().cast(flagValue, appContext: appContext) as! Bool
            return Self(name: name, ratio: ratio, count: count, flag: flag)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["name"] = self.name
            dictionary["ratio"] = self.ratio
            dictionary["count"] = self.count
            dictionary["flag"] = self.flag
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let object = try appContext.runtime.createObject()
            object.setProperty("name", value: try String.getDynamicType().convertToJS(self.name, appContext: appContext))
            object.setProperty("ratio", value: try Double.getDynamicType().convertToJS(self.ratio, appContext: appContext))
            object.setProperty("count", value: try Int.getDynamicType().convertToJS(self.count, appContext: appContext))
            object.setProperty("flag", value: try Bool.getDynamicType().convertToJS(self.flag, appContext: appContext))
            return object
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `A non-literal default without an annotation still requires an explicit type`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var items = []
      }
      """,
      expandedSource: """
        struct Options {
          var items = []
        }

        extension Options: Record {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Record properties must declare an explicit type — 'items' has none",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `static, private and fileprivate properties and computed properties are excluded`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var name: String
        static let shared = "x"
        private var secret: Int = 0
        fileprivate var hidden: Bool = false
        var computed: Int { 1 }
      }
      """,
      expandedSource: """
        struct Options {
          var name: String
          static let shared = "x"
          private var secret: Int = 0
          fileprivate var hidden: Bool = false
          var computed: Int { 1 }

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(name: String) {
            self.name = name
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let nameJSValue = object.getProperty("name")
            guard !nameJSValue.isUndefined() else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.getDynamicType().cast(jsValue: nameJSValue, appContext: appContext) as! String
            return Self(name: name)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let nameValue = dictionary["name"]
            guard let nameValue else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.getDynamicType().cast(nameValue, appContext: appContext) as! String
            return Self(name: name)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["name"] = self.name
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let object = try appContext.runtime.createObject()
            object.setProperty("name", value: try String.getDynamicType().convertToJS(self.name, appContext: appContext))
            return object
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `Empty record synthesizes the full surface with no properties`() {
    assertExpansion(
      """
      @Record
      struct Empty {
      }
      """,
      expandedSource: """
        struct Empty {

          public init() {

          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            return Self()
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            return Self()
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let object = try appContext.runtime.createObject()
            return object
          }
        }

        extension Empty: Record {
        }
        """
    )
  }

  @Test
  func `Struct with only defaulted properties gets an explicit init() for Record conformance`() {
    assertExpansion(
      """
      @Record
      struct Point {
        var x: Double = 0
        var y: Double = 0
      }
      """,
      expandedSource: """
        struct Point {
          var x: Double = 0
          var y: Double = 0

          public init() {
          }

          public init(x: Double, y: Double) {
            self.x = x
            self.y = y
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let xJSValue = object.getProperty("x")
            let x = xJSValue.isUndefined() ? 0 : try Double.getDynamicType().cast(jsValue: xJSValue, appContext: appContext) as! Double
            let yJSValue = object.getProperty("y")
            let y = yJSValue.isUndefined() ? 0 : try Double.getDynamicType().cast(jsValue: yJSValue, appContext: appContext) as! Double
            return Self(x: x, y: y)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let xValue = dictionary["x"]
            let x = xValue == nil ? 0 : try Double.getDynamicType().cast(xValue, appContext: appContext) as! Double
            let yValue = dictionary["y"]
            let y = yValue == nil ? 0 : try Double.getDynamicType().cast(yValue, appContext: appContext) as! Double
            return Self(x: x, y: y)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["x"] = self.x
            dictionary["y"] = self.y
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let object = try appContext.runtime.createObject()
            object.setProperty("x", value: try Double.getDynamicType().convertToJS(self.x, appContext: appContext))
            object.setProperty("y", value: try Double.getDynamicType().convertToJS(self.y, appContext: appContext))
            return object
          }
        }

        extension Point: Record {
        }
        """
    )
  }

  @Test
  func `Subclass chains to super for the write side and inlines property defaults`() {
    assertExpansion(
      """
      @Record
      final class Child: Parent {
        var extra: String = ""
      }
      """,
      expandedSource: """
        final class Child: Parent {
          var extra: String = ""

          public init(extra: String) {
            self.extra = extra
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let extraJSValue = object.getProperty("extra")
            let extra = extraJSValue.isUndefined() ? "" : try String.getDynamicType().cast(jsValue: extraJSValue, appContext: appContext) as! String
            return Self(extra: extra)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let extraValue = dictionary["extra"]
            let extra = extraValue == nil ? "" : try String.getDynamicType().cast(extraValue, appContext: appContext) as! String
            return Self(extra: extra)
          }

          public override func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary = super.toDictionary(appContext: appContext)
            dictionary["extra"] = self.extra
            return dictionary
          }

          @JavaScriptActor
          public override func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let object = try super.toObject(appContext: appContext)
            object.setProperty("extra", value: try String.getDynamicType().convertToJS(self.extra, appContext: appContext))
            return object
          }
        }
        """
    )
  }

  @Test
  func `Class without inheritance gets the Record conformance`() {
    assertExpansion(
      """
      @Record
      final class Options {
        var name: String
      }
      """,
      expandedSource: """
        final class Options {
          var name: String

          public init(name: String) {
            self.name = name
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let nameJSValue = object.getProperty("name")
            guard !nameJSValue.isUndefined() else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.getDynamicType().cast(jsValue: nameJSValue, appContext: appContext) as! String
            return Self(name: name)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let nameValue = dictionary["name"]
            guard let nameValue else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.getDynamicType().cast(nameValue, appContext: appContext) as! String
            return Self(name: name)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["name"] = self.name
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let object = try appContext.runtime.createObject()
            object.setProperty("name", value: try String.getDynamicType().convertToJS(self.name, appContext: appContext))
            return object
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `Type already declaring Record does not get a redundant extension`() {
    assertExpansion(
      """
      @Record
      struct Options: Record {
        var name: String
      }
      """,
      expandedSource: """
        struct Options: Record {
          var name: String

          public init() {
            fatalError("\\(Self.self) has required properties and cannot be created with init(); construct it through the @Record-synthesized from(dictionary:) or from(object:) factories")
          }

          public init(name: String) {
            self.name = name
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let nameJSValue = object.getProperty("name")
            guard !nameJSValue.isUndefined() else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.getDynamicType().cast(jsValue: nameJSValue, appContext: appContext) as! String
            return Self(name: name)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let nameValue = dictionary["name"]
            guard let nameValue else {
              throw RecordPropertyRequiredException("name")
            }
            let name = try String.getDynamicType().cast(nameValue, appContext: appContext) as! String
            return Self(name: name)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["name"] = self.name
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let object = try appContext.runtime.createObject()
            object.setProperty("name", value: try String.getDynamicType().convertToJS(self.name, appContext: appContext))
            return object
          }
        }
        """
    )
  }

  @Test
  func `A leftover @Field attribute produces a diagnostic`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var name: String
        @Field var defaultName = "foo"
      }
      """,
      expandedSource: """
        struct Options {
          var name: String
          @Field var defaultName = "foo"
        }

        extension Options: Record {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Field is no longer used — @Record treats every stored property as a record property. Remove the @Field attribute",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `Applying @Record to an enum produces a diagnostic`() {
    assertExpansion(
      """
      @Record
      enum NotARecord {
      }
      """,
      expandedSource: """
        enum NotARecord {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Record can only be applied to a struct or class",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `Author-declared init() is not duplicated`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var x: Double = 0
        var y: Double = 0

        init() {
          x = 1
          y = 2
        }
      }
      """,
      expandedSource: """
        struct Options {
          var x: Double = 0
          var y: Double = 0

          init() {
            x = 1
            y = 2
          }

          public init(x: Double, y: Double) {
            self.x = x
            self.y = y
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let xJSValue = object.getProperty("x")
            let x = xJSValue.isUndefined() ? 0 : try Double.getDynamicType().cast(jsValue: xJSValue, appContext: appContext) as! Double
            let yJSValue = object.getProperty("y")
            let y = yJSValue.isUndefined() ? 0 : try Double.getDynamicType().cast(jsValue: yJSValue, appContext: appContext) as! Double
            return Self(x: x, y: y)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let xValue = dictionary["x"]
            let x = xValue == nil ? 0 : try Double.getDynamicType().cast(xValue, appContext: appContext) as! Double
            let yValue = dictionary["y"]
            let y = yValue == nil ? 0 : try Double.getDynamicType().cast(yValue, appContext: appContext) as! Double
            return Self(x: x, y: y)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["x"] = self.x
            dictionary["y"] = self.y
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let object = try appContext.runtime.createObject()
            object.setProperty("x", value: try Double.getDynamicType().convertToJS(self.x, appContext: appContext))
            object.setProperty("y", value: try Double.getDynamicType().convertToJS(self.y, appContext: appContext))
            return object
          }
        }

        extension Options: Record {
        }
        """
    )
  }

  @Test
  func `Author-declared memberwise init is not duplicated`() {
    assertExpansion(
      """
      @Record
      struct Options {
        var x: Double = 0
        var y: Double = 0

        init(x: Double, y: Double) {
          self.x = x
          self.y = y
        }
      }
      """,
      expandedSource: """
        struct Options {
          var x: Double = 0
          var y: Double = 0

          init(x: Double, y: Double) {
            self.x = x
            self.y = y
          }

          public init() {
          }

          @JavaScriptActor
          public static func from(object: borrowing JavaScriptObject, appContext: AppContext) throws -> Self {
            let xJSValue = object.getProperty("x")
            let x = xJSValue.isUndefined() ? 0 : try Double.getDynamicType().cast(jsValue: xJSValue, appContext: appContext) as! Double
            let yJSValue = object.getProperty("y")
            let y = yJSValue.isUndefined() ? 0 : try Double.getDynamicType().cast(jsValue: yJSValue, appContext: appContext) as! Double
            return Self(x: x, y: y)
          }

          public static func from(dictionary: [String: Any], appContext: AppContext) throws -> Self {
            let xValue = dictionary["x"]
            let x = xValue == nil ? 0 : try Double.getDynamicType().cast(xValue, appContext: appContext) as! Double
            let yValue = dictionary["y"]
            let y = yValue == nil ? 0 : try Double.getDynamicType().cast(yValue, appContext: appContext) as! Double
            return Self(x: x, y: y)
          }

          public func toDictionary(appContext: AppContext? = nil) -> [String: Any] {
            var dictionary: [String: Any] = [:]
            dictionary["x"] = self.x
            dictionary["y"] = self.y
            return dictionary
          }

          @JavaScriptActor
          public func toObject(appContext: AppContext) throws -> JavaScriptObject {
            let object = try appContext.runtime.createObject()
            object.setProperty("x", value: try Double.getDynamicType().convertToJS(self.x, appContext: appContext))
            object.setProperty("y", value: try Double.getDynamicType().convertToJS(self.y, appContext: appContext))
            return object
          }
        }

        extension Options: Record {
        }
        """
    )
  }
}
