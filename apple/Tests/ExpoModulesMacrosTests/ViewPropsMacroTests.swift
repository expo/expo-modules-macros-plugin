import ExpoModulesMacros
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let viewPropsMacroSpecs: [String: MacroSpec] = [
  "ViewProps": MacroSpec(type: ViewPropsMacro.self, conformances: ["AnyViewProps"])
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
    macroSpecs: viewPropsMacroSpecs,
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

@Suite("@ViewProps macro")
struct ViewPropsMacroTests {
  @Test
  func `Value props get a case and a bit; events get a name`() {
    assertExpansion(
      """
      @ViewProps
      struct CardProps {
        var color: UIColor = .red
        var radius: CGFloat = 0
        var onTap: (TapEvent) -> Void
      }
      """,
      expandedSource: """
        struct CardProps {
          var color: UIColor = .red
          var radius: CGFloat = 0
          var onTap: (TapEvent) -> Void

          public enum PropName: String, CaseIterable {
            case color
            case radius
          }

          public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let color = PropSet(rawValue: 1 << 0)
            public static let radius = PropSet(rawValue: 1 << 1)
          }

          public static let _eventNames: [String] = ["onTap"]

          public typealias Diff = PropsDiff<Self>
        }

        extension CardProps: AnyViewProps {
          public static var allProps: PropSet {
            return [.color, .radius]
          }

          public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            case .radius:
              return .radius
            }
          }
        }
        """
    )
  }

  @Test
  func `Bits follow declaration order`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var a: Int = 0
        var b: Int = 0
        var c: Int = 0
      }
      """,
      expandedSource: """
        struct Props {
          var a: Int = 0
          var b: Int = 0
          var c: Int = 0

          public enum PropName: String, CaseIterable {
            case a
            case b
            case c
          }

          public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let a = PropSet(rawValue: 1 << 0)
            public static let b = PropSet(rawValue: 1 << 1)
            public static let c = PropSet(rawValue: 1 << 2)
          }

          public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>
        }

        extension Props: AnyViewProps {
          public static var allProps: PropSet {
            return [.a, .b, .c]
          }

          public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .a:
              return .a
            case .b:
              return .b
            case .c:
              return .c
            }
          }
        }
        """
    )
  }

  @Test
  func `Event names are emitted verbatim, keeping the on prefix`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var onTap: () -> Void
        var onClose: (CloseEvent) -> Void
      }
      """,
      expandedSource: """
        struct Props {
          var onTap: () -> Void
          var onClose: (CloseEvent) -> Void

          public enum PropName: String, CaseIterable {
          }

          public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }
          }

          public static let _eventNames: [String] = ["onTap", "onClose"]

          public typealias Diff = PropsDiff<Self>
        }

        extension Props: AnyViewProps {
          public static var allProps: PropSet {
            return []
          }

          public static func propSet(for name: PropName) -> PropSet {
            return []
          }
        }
        """
    )
  }

  @Test
  func `A Sendable function property is still an event`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var onTap: @Sendable (TapEvent) -> Void
      }
      """,
      expandedSource: """
        struct Props {
          var onTap: @Sendable (TapEvent) -> Void

          public enum PropName: String, CaseIterable {
          }

          public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }
          }

          public static let _eventNames: [String] = ["onTap"]

          public typealias Diff = PropsDiff<Self>
        }

        extension Props: AnyViewProps {
          public static var allProps: PropSet {
            return []
          }

          public static func propSet(for name: PropName) -> PropSet {
            return []
          }
        }
        """
    )
  }

  @Test
  func `Static, private and computed properties are ignored`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var color: UIColor = .red
        static var shared: Int = 0
        private var hidden: Int = 0
        lazy var deferred: Int = 0
        var derived: Int {
          return 1
        }
      }
      """,
      expandedSource: """
        struct Props {
          var color: UIColor = .red
          static var shared: Int = 0
          private var hidden: Int = 0
          lazy var deferred: Int = 0
          var derived: Int {
            return 1
          }

          public enum PropName: String, CaseIterable {
            case color
          }

          public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let color = PropSet(rawValue: 1 << 0)
          }

          public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>
        }

        extension Props: AnyViewProps {
          public static var allProps: PropSet {
            return [.color]
          }

          public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            }
          }
        }
        """
    )
  }

  @Test
  func `An optional value prop is a normal prop`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var radius: CGFloat?
      }
      """,
      expandedSource: """
        struct Props {
          var radius: CGFloat?

          public enum PropName: String, CaseIterable {
            case radius
          }

          public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let radius = PropSet(rawValue: 1 << 0)
          }

          public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>
        }

        extension Props: AnyViewProps {
          public static var allProps: PropSet {
            return [.radius]
          }

          public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .radius:
              return .radius
            }
          }
        }
        """
    )
  }

  @Test
  func `A conformance already declared is not repeated`() {
    assertExpansion(
      """
      @ViewProps
      struct Props: AnyViewProps {
        var color: UIColor = .red
      }
      """,
      expandedSource: """
        struct Props: AnyViewProps {
          var color: UIColor = .red

          public enum PropName: String, CaseIterable {
            case color
          }

          public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let color = PropSet(rawValue: 1 << 0)
          }

          public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>
        }

        extension Props {
          public static var allProps: PropSet {
            return [.color]
          }

          public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .color:
              return .color
            }
          }
        }
        """
    )
  }

  @Test
  func `Applying @ViewProps to a class produces a diagnostic`() {
    assertExpansion(
      """
      @ViewProps
      class Props {
        var color: UIColor = .red
      }
      """,
      expandedSource: """
        class Props {
          var color: UIColor = .red
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ViewProps can only be applied to a struct — the class form (for SwiftUI views) is not supported yet",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `An optional event prop produces a diagnostic`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var onTap: ((TapEvent) -> Void)?
      }
      """,
      expandedSource: """
        struct Props {
          var onTap: ((TapEvent) -> Void)?
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "Event props cannot be optional — 'onTap' is registered once at view creation, so its presence can't vary. Drop the '?'",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `A leftover @Field attribute produces a diagnostic`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        @Field
        var color: UIColor = .red
      }
      """,
      expandedSource: """
        struct Props {
          @Field
          var color: UIColor = .red
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Field is no longer used — @ViewProps treats every stored property as a prop. Remove the @Field attribute",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `A property with no determinable type produces a diagnostic`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var items = makeItems()
      }
      """,
      expandedSource: """
        struct Props {
          var items = makeItems()
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ViewProps props must declare an explicit type — 'items' has none",
          line: 1,
          column: 1
        )
      ]
    )
  }
}
