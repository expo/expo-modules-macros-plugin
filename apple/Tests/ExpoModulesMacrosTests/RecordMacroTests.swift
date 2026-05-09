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
  func `Struct with @Field properties uses property names as keys`() {
    assertExpansion(
      """
      @Record
      struct Options: Record {
        @Field var name: String = ""
        @Field var count: Int = 0
      }
      """,
      expandedSource: """
        struct Options: Record {
          @Field var name: String = ""
          @Field var count: Int = 0

          public static func _recordFields(of instance: Self) -> [RecordFieldDescriptor] {
            var fields: [RecordFieldDescriptor] = []
            fields.append(RecordFieldDescriptor(key: "name", isRequired: false, field: instance._name))
            fields.append(RecordFieldDescriptor(key: "count", isRequired: false, field: instance._count))
            return fields
          }
        }

        extension Options: _RecordFieldsProvider {
        }
        """
    )
  }

  @Test
  func `String literal in @Field overrides the property name`() {
    assertExpansion(
      """
      @Record
      struct Options: Record {
        @Field("custom_key") var flag: Bool = false
      }
      """,
      expandedSource: """
        struct Options: Record {
          @Field("custom_key") var flag: Bool = false

          public static func _recordFields(of instance: Self) -> [RecordFieldDescriptor] {
            var fields: [RecordFieldDescriptor] = []
            fields.append(RecordFieldDescriptor(key: "custom_key", isRequired: false, field: instance._flag))
            return fields
          }
        }

        extension Options: _RecordFieldsProvider {
        }
        """
    )
  }

  @Test
  func `Explicit .keyed option overrides the property name`() {
    assertExpansion(
      """
      @Record
      struct Options: Record {
        @Field(.keyed("custom_key")) var flag: Bool = false
        @Field(.required) var count: Int = 0
      }
      """,
      expandedSource: """
        struct Options: Record {
          @Field(.keyed("custom_key")) var flag: Bool = false
          @Field(.required) var count: Int = 0

          public static func _recordFields(of instance: Self) -> [RecordFieldDescriptor] {
            var fields: [RecordFieldDescriptor] = []
            fields.append(RecordFieldDescriptor(key: "custom_key", isRequired: false, field: instance._flag))
            fields.append(RecordFieldDescriptor(key: "count", isRequired: true, field: instance._count))
            return fields
          }
        }

        extension Options: _RecordFieldsProvider {
        }
        """
    )
  }

  @Test
  func `.required option emits true in the isRequired tuple slot`() {
    assertExpansion(
      """
      @Record
      struct Options: Record {
        @Field(.required) var name: String = ""
        @Field var count: Int = 0
      }
      """,
      expandedSource: """
        struct Options: Record {
          @Field(.required) var name: String = ""
          @Field var count: Int = 0

          public static func _recordFields(of instance: Self) -> [RecordFieldDescriptor] {
            var fields: [RecordFieldDescriptor] = []
            fields.append(RecordFieldDescriptor(key: "name", isRequired: true, field: instance._name))
            fields.append(RecordFieldDescriptor(key: "count", isRequired: false, field: instance._count))
            return fields
          }
        }

        extension Options: _RecordFieldsProvider {
        }
        """
    )
  }

  @Test
  func `Properties without @Field are ignored`() {
    assertExpansion(
      """
      @Record
      struct Options: Record {
        @Field var name: String = ""
        var transient: Int = 0
        let helper = "x"
      }
      """,
      expandedSource: """
        struct Options: Record {
          @Field var name: String = ""
          var transient: Int = 0
          let helper = "x"

          public static func _recordFields(of instance: Self) -> [RecordFieldDescriptor] {
            var fields: [RecordFieldDescriptor] = []
            fields.append(RecordFieldDescriptor(key: "name", isRequired: false, field: instance._name))
            return fields
          }
        }

        extension Options: _RecordFieldsProvider {
        }
        """
    )
  }

  @Test
  func `Class without inheritance emits a non-overriding class method and gets Record conformance`() {
    assertExpansion(
      """
      @Record
      final class Options {
        @Field var name: String = ""
      }
      """,
      expandedSource: """
        final class Options {
          @Field var name: String = ""

          public class func _recordFields(of instance: Self) -> [RecordFieldDescriptor] {
            var fields: [RecordFieldDescriptor] = []
            fields.append(RecordFieldDescriptor(key: "name", isRequired: false, field: instance._name))
            return fields
          }
        }

        extension Options: Record, _RecordFieldsProvider {
        }
        """
    )
  }

  @Test
  func `Struct without explicit Record conformance gets it from the macro`() {
    assertExpansion(
      """
      @Record
      struct Options {
        @Field var name: String = ""
      }
      """,
      expandedSource: """
        struct Options {
          @Field var name: String = ""

          public static func _recordFields(of instance: Self) -> [RecordFieldDescriptor] {
            var fields: [RecordFieldDescriptor] = []
            fields.append(RecordFieldDescriptor(key: "name", isRequired: false, field: instance._name))
            return fields
          }
        }

        extension Options: Record, _RecordFieldsProvider {
        }
        """
    )
  }

  @Test
  func `Struct with explicit Record conformance only gets _RecordFieldsProvider added`() {
    assertExpansion(
      """
      @Record
      struct Options: Record, Sendable {
        @Field var name: String = ""
      }
      """,
      expandedSource: """
        struct Options: Record, Sendable {
          @Field var name: String = ""

          public static func _recordFields(of instance: Self) -> [RecordFieldDescriptor] {
            var fields: [RecordFieldDescriptor] = []
            fields.append(RecordFieldDescriptor(key: "name", isRequired: false, field: instance._name))
            return fields
          }
        }

        extension Options: _RecordFieldsProvider {
        }
        """
    )
  }

  @Test
  func `Subclass concatenates inherited fields via super`() {
    assertExpansion(
      """
      @Record
      final class Child: Parent {
        @Field var extra: String = ""
      }
      """,
      expandedSource: """
        final class Child: Parent {
          @Field var extra: String = ""

          public override class func _recordFields(of instance: Self) -> [RecordFieldDescriptor] {
            var fields: [RecordFieldDescriptor] = super._recordFields(of: instance)
            fields.append(RecordFieldDescriptor(key: "extra", isRequired: false, field: instance._extra))
            return fields
          }
        }
        """
    )
  }

  @Test
  func `Empty record produces an empty fields array`() {
    assertExpansion(
      """
      @Record
      struct Empty: Record {
      }
      """,
      expandedSource: """
        struct Empty: Record {

          public static func _recordFields(of instance: Self) -> [RecordFieldDescriptor] {
            var fields: [RecordFieldDescriptor] = []
            return fields
          }
        }

        extension Empty: _RecordFieldsProvider {
        }
        """
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
}
