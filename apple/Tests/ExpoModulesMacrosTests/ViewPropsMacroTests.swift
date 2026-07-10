import ExpoModulesMacros
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let viewPropsMacroSpecs: [String: MacroSpec] = [
  "ViewProps": MacroSpec(type: ViewPropsMacro.self)
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
    macroSpecs: viewPropsMacroSpecs,
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
  func `Value props become PropName cases and function-typed props are excluded as events`() {
    assertExpansion(
      """
      @ViewProps
      struct CardProps {
        var title: String
        var color: UIColor = .red
        var radius: CGFloat?
        var onTap: (TapEvent) -> Void
        var onClose: () -> Void
      }
      """,
      expandedSource: """
        struct CardProps {
          var title: String
          var color: UIColor = .red
          var radius: CGFloat?
          var onTap: (TapEvent) -> Void
          var onClose: () -> Void

          public enum PropName: String, CaseIterable {
            case title
            case color
            case radius
          }

          public typealias Diff = PropsDiff<CardProps>
        }

        extension CardProps: AnyViewProps {
        }
        """
    )
  }

  @Test
  func `@Sendable and parenthesized function types are recognized as events`() {
    assertExpansion(
      """
      @ViewProps
      struct CardProps {
        var scale: Double = 1
        var onLoad: @Sendable (LoadEvent) -> Void
        var onError: ((ErrorEvent) -> Void)
      }
      """,
      expandedSource: """
        struct CardProps {
          var scale: Double = 1
          var onLoad: @Sendable (LoadEvent) -> Void
          var onError: ((ErrorEvent) -> Void)

          public enum PropName: String, CaseIterable {
            case scale
          }

          public typealias Diff = PropsDiff<CardProps>
        }

        extension CardProps: AnyViewProps {
        }
        """
    )
  }

  @Test
  func `A props type with only events gets an empty PropName enum`() {
    assertExpansion(
      """
      @ViewProps
      struct TouchableProps {
        var onTap: (TapEvent) -> Void
      }
      """,
      expandedSource: """
        struct TouchableProps {
          var onTap: (TapEvent) -> Void

          public enum PropName: String, CaseIterable {
          }

          public typealias Diff = PropsDiff<TouchableProps>
        }

        extension TouchableProps: AnyViewProps {
        }
        """
    )
  }

  @Test
  func `Literal defaults infer the prop type`() {
    assertExpansion(
      """
      @ViewProps
      struct ToggleProps {
        var enabled = true
      }
      """,
      expandedSource: """
        struct ToggleProps {
          var enabled = true

          public enum PropName: String, CaseIterable {
            case enabled
          }

          public typealias Diff = PropsDiff<ToggleProps>
        }

        extension ToggleProps: AnyViewProps {
        }
        """
    )
  }

  @Test
  func `static, private, fileprivate, lazy and computed properties are excluded`() {
    assertExpansion(
      """
      @ViewProps
      struct CardProps {
        var title: String
        static let shared = "x"
        private var secret: Int = 0
        fileprivate var hidden: Bool = false
        lazy var expensive: Int = makeExpensive()
        var computed: Int { 1 }
      }
      """,
      expandedSource: """
        struct CardProps {
          var title: String
          static let shared = "x"
          private var secret: Int = 0
          fileprivate var hidden: Bool = false
          lazy var expensive: Int = makeExpensive()
          var computed: Int { 1 }

          public enum PropName: String, CaseIterable {
            case title
          }

          public typealias Diff = PropsDiff<CardProps>
        }

        extension CardProps: AnyViewProps {
        }
        """
    )
  }

  @Test
  func `An already-declared AnyViewProps conformance is not duplicated`() {
    assertExpansion(
      """
      @ViewProps
      struct CardProps: AnyViewProps {
        var title: String
      }
      """,
      expandedSource: """
        struct CardProps: AnyViewProps {
          var title: String

          public enum PropName: String, CaseIterable {
            case title
          }

          public typealias Diff = PropsDiff<CardProps>
        }
        """
    )
  }

  @Test
  func `A property without an explicit or literal-inferable type is rejected`() {
    assertExpansion(
      """
      @ViewProps
      struct CardProps {
        var items = []
      }
      """,
      expandedSource: """
        struct CardProps {
          var items = []
        }

        extension CardProps: AnyViewProps {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ViewProps properties must declare an explicit type: 'items' has none",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `An optional function type is rejected`() {
    assertExpansion(
      """
      @ViewProps
      struct CardProps {
        var onTap: ((TapEvent) -> Void)?
      }
      """,
      expandedSource: """
        struct CardProps {
          var onTap: ((TapEvent) -> Void)?
        }

        extension CardProps: AnyViewProps {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ViewProps event 'onTap' can't have an optional function type: an event prop is always present. Remove the '?'",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `@Field is rejected`() {
    assertExpansion(
      """
      @ViewProps
      struct CardProps {
        @Field var title: String = ""
      }
      """,
      expandedSource: """
        struct CardProps {
          @Field var title: String = ""
        }

        extension CardProps: AnyViewProps {
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Field is not used with @ViewProps: every stored property is a prop. Remove the @Field attribute",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `Classes are rejected until the SwiftUI props path lands`() {
    assertExpansion(
      """
      @ViewProps
      class PanelProps {
        var title: String = ""
      }
      """,
      expandedSource: """
        class PanelProps {
          var title: String = ""
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ViewProps classes (SwiftUI observable props) aren't supported yet: apply it to a struct",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `Non-type declarations are rejected`() {
    assertExpansion(
      """
      @ViewProps
      enum CardProps {
        case none
      }
      """,
      expandedSource: """
        enum CardProps {
          case none
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ViewProps can only be applied to a struct",
          line: 1,
          column: 1
        )
      ]
    )
  }
}
