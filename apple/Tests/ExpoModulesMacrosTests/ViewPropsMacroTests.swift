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
          public static let allProps = PropSet(rawValue: 0b11)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
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
          public static let allProps = PropSet(rawValue: 0b111)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
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
          public static let allProps = PropSet(rawValue: 0)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
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
          public static let allProps = PropSet(rawValue: 0)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
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
          public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
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
          public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
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
          public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
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
          line: 3,
          column: 14,
          fixIts: [FixItSpec(message: "Make 'onTap' non-optional")]
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
          line: 3,
          column: 3,
          fixIts: [FixItSpec(message: "Remove the '@Field' attribute")]
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

  @Test
  func `More than 64 value props produces a diagnostic`() {
    // The changed-props mask is a single UInt64, so the 65th value prop has no bit.
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var p0: Int = 0
        var p1: Int = 0
        var p2: Int = 0
        var p3: Int = 0
        var p4: Int = 0
        var p5: Int = 0
        var p6: Int = 0
        var p7: Int = 0
        var p8: Int = 0
        var p9: Int = 0
        var p10: Int = 0
        var p11: Int = 0
        var p12: Int = 0
        var p13: Int = 0
        var p14: Int = 0
        var p15: Int = 0
        var p16: Int = 0
        var p17: Int = 0
        var p18: Int = 0
        var p19: Int = 0
        var p20: Int = 0
        var p21: Int = 0
        var p22: Int = 0
        var p23: Int = 0
        var p24: Int = 0
        var p25: Int = 0
        var p26: Int = 0
        var p27: Int = 0
        var p28: Int = 0
        var p29: Int = 0
        var p30: Int = 0
        var p31: Int = 0
        var p32: Int = 0
        var p33: Int = 0
        var p34: Int = 0
        var p35: Int = 0
        var p36: Int = 0
        var p37: Int = 0
        var p38: Int = 0
        var p39: Int = 0
        var p40: Int = 0
        var p41: Int = 0
        var p42: Int = 0
        var p43: Int = 0
        var p44: Int = 0
        var p45: Int = 0
        var p46: Int = 0
        var p47: Int = 0
        var p48: Int = 0
        var p49: Int = 0
        var p50: Int = 0
        var p51: Int = 0
        var p52: Int = 0
        var p53: Int = 0
        var p54: Int = 0
        var p55: Int = 0
        var p56: Int = 0
        var p57: Int = 0
        var p58: Int = 0
        var p59: Int = 0
        var p60: Int = 0
        var p61: Int = 0
        var p62: Int = 0
        var p63: Int = 0
        var p64: Int = 0
      }
      """,
      expandedSource: """
        struct Props {
          var p0: Int = 0
          var p1: Int = 0
          var p2: Int = 0
          var p3: Int = 0
          var p4: Int = 0
          var p5: Int = 0
          var p6: Int = 0
          var p7: Int = 0
          var p8: Int = 0
          var p9: Int = 0
          var p10: Int = 0
          var p11: Int = 0
          var p12: Int = 0
          var p13: Int = 0
          var p14: Int = 0
          var p15: Int = 0
          var p16: Int = 0
          var p17: Int = 0
          var p18: Int = 0
          var p19: Int = 0
          var p20: Int = 0
          var p21: Int = 0
          var p22: Int = 0
          var p23: Int = 0
          var p24: Int = 0
          var p25: Int = 0
          var p26: Int = 0
          var p27: Int = 0
          var p28: Int = 0
          var p29: Int = 0
          var p30: Int = 0
          var p31: Int = 0
          var p32: Int = 0
          var p33: Int = 0
          var p34: Int = 0
          var p35: Int = 0
          var p36: Int = 0
          var p37: Int = 0
          var p38: Int = 0
          var p39: Int = 0
          var p40: Int = 0
          var p41: Int = 0
          var p42: Int = 0
          var p43: Int = 0
          var p44: Int = 0
          var p45: Int = 0
          var p46: Int = 0
          var p47: Int = 0
          var p48: Int = 0
          var p49: Int = 0
          var p50: Int = 0
          var p51: Int = 0
          var p52: Int = 0
          var p53: Int = 0
          var p54: Int = 0
          var p55: Int = 0
          var p56: Int = 0
          var p57: Int = 0
          var p58: Int = 0
          var p59: Int = 0
          var p60: Int = 0
          var p61: Int = 0
          var p62: Int = 0
          var p63: Int = 0
          var p64: Int = 0
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ViewProps supports at most 64 value props (the changed-props mask is a UInt64), but this type declares 65; 'p64' is the first over the limit. Event props don't count toward it",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `Exactly 64 value props fills the mask without a diagnostic`() {
    // The boundary case: 64 props occupy bits 0...63 of the UInt64 mask exactly.
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var p0: Int = 0
        var p1: Int = 0
        var p2: Int = 0
        var p3: Int = 0
        var p4: Int = 0
        var p5: Int = 0
        var p6: Int = 0
        var p7: Int = 0
        var p8: Int = 0
        var p9: Int = 0
        var p10: Int = 0
        var p11: Int = 0
        var p12: Int = 0
        var p13: Int = 0
        var p14: Int = 0
        var p15: Int = 0
        var p16: Int = 0
        var p17: Int = 0
        var p18: Int = 0
        var p19: Int = 0
        var p20: Int = 0
        var p21: Int = 0
        var p22: Int = 0
        var p23: Int = 0
        var p24: Int = 0
        var p25: Int = 0
        var p26: Int = 0
        var p27: Int = 0
        var p28: Int = 0
        var p29: Int = 0
        var p30: Int = 0
        var p31: Int = 0
        var p32: Int = 0
        var p33: Int = 0
        var p34: Int = 0
        var p35: Int = 0
        var p36: Int = 0
        var p37: Int = 0
        var p38: Int = 0
        var p39: Int = 0
        var p40: Int = 0
        var p41: Int = 0
        var p42: Int = 0
        var p43: Int = 0
        var p44: Int = 0
        var p45: Int = 0
        var p46: Int = 0
        var p47: Int = 0
        var p48: Int = 0
        var p49: Int = 0
        var p50: Int = 0
        var p51: Int = 0
        var p52: Int = 0
        var p53: Int = 0
        var p54: Int = 0
        var p55: Int = 0
        var p56: Int = 0
        var p57: Int = 0
        var p58: Int = 0
        var p59: Int = 0
        var p60: Int = 0
        var p61: Int = 0
        var p62: Int = 0
        var p63: Int = 0
      }
      """,
      expandedSource: """
        struct Props {
          var p0: Int = 0
          var p1: Int = 0
          var p2: Int = 0
          var p3: Int = 0
          var p4: Int = 0
          var p5: Int = 0
          var p6: Int = 0
          var p7: Int = 0
          var p8: Int = 0
          var p9: Int = 0
          var p10: Int = 0
          var p11: Int = 0
          var p12: Int = 0
          var p13: Int = 0
          var p14: Int = 0
          var p15: Int = 0
          var p16: Int = 0
          var p17: Int = 0
          var p18: Int = 0
          var p19: Int = 0
          var p20: Int = 0
          var p21: Int = 0
          var p22: Int = 0
          var p23: Int = 0
          var p24: Int = 0
          var p25: Int = 0
          var p26: Int = 0
          var p27: Int = 0
          var p28: Int = 0
          var p29: Int = 0
          var p30: Int = 0
          var p31: Int = 0
          var p32: Int = 0
          var p33: Int = 0
          var p34: Int = 0
          var p35: Int = 0
          var p36: Int = 0
          var p37: Int = 0
          var p38: Int = 0
          var p39: Int = 0
          var p40: Int = 0
          var p41: Int = 0
          var p42: Int = 0
          var p43: Int = 0
          var p44: Int = 0
          var p45: Int = 0
          var p46: Int = 0
          var p47: Int = 0
          var p48: Int = 0
          var p49: Int = 0
          var p50: Int = 0
          var p51: Int = 0
          var p52: Int = 0
          var p53: Int = 0
          var p54: Int = 0
          var p55: Int = 0
          var p56: Int = 0
          var p57: Int = 0
          var p58: Int = 0
          var p59: Int = 0
          var p60: Int = 0
          var p61: Int = 0
          var p62: Int = 0
          var p63: Int = 0

          public enum PropName: String, CaseIterable {
            case p0
            case p1
            case p2
            case p3
            case p4
            case p5
            case p6
            case p7
            case p8
            case p9
            case p10
            case p11
            case p12
            case p13
            case p14
            case p15
            case p16
            case p17
            case p18
            case p19
            case p20
            case p21
            case p22
            case p23
            case p24
            case p25
            case p26
            case p27
            case p28
            case p29
            case p30
            case p31
            case p32
            case p33
            case p34
            case p35
            case p36
            case p37
            case p38
            case p39
            case p40
            case p41
            case p42
            case p43
            case p44
            case p45
            case p46
            case p47
            case p48
            case p49
            case p50
            case p51
            case p52
            case p53
            case p54
            case p55
            case p56
            case p57
            case p58
            case p59
            case p60
            case p61
            case p62
            case p63
          }

          public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let p0 = PropSet(rawValue: 1 << 0)
            public static let p1 = PropSet(rawValue: 1 << 1)
            public static let p2 = PropSet(rawValue: 1 << 2)
            public static let p3 = PropSet(rawValue: 1 << 3)
            public static let p4 = PropSet(rawValue: 1 << 4)
            public static let p5 = PropSet(rawValue: 1 << 5)
            public static let p6 = PropSet(rawValue: 1 << 6)
            public static let p7 = PropSet(rawValue: 1 << 7)
            public static let p8 = PropSet(rawValue: 1 << 8)
            public static let p9 = PropSet(rawValue: 1 << 9)
            public static let p10 = PropSet(rawValue: 1 << 10)
            public static let p11 = PropSet(rawValue: 1 << 11)
            public static let p12 = PropSet(rawValue: 1 << 12)
            public static let p13 = PropSet(rawValue: 1 << 13)
            public static let p14 = PropSet(rawValue: 1 << 14)
            public static let p15 = PropSet(rawValue: 1 << 15)
            public static let p16 = PropSet(rawValue: 1 << 16)
            public static let p17 = PropSet(rawValue: 1 << 17)
            public static let p18 = PropSet(rawValue: 1 << 18)
            public static let p19 = PropSet(rawValue: 1 << 19)
            public static let p20 = PropSet(rawValue: 1 << 20)
            public static let p21 = PropSet(rawValue: 1 << 21)
            public static let p22 = PropSet(rawValue: 1 << 22)
            public static let p23 = PropSet(rawValue: 1 << 23)
            public static let p24 = PropSet(rawValue: 1 << 24)
            public static let p25 = PropSet(rawValue: 1 << 25)
            public static let p26 = PropSet(rawValue: 1 << 26)
            public static let p27 = PropSet(rawValue: 1 << 27)
            public static let p28 = PropSet(rawValue: 1 << 28)
            public static let p29 = PropSet(rawValue: 1 << 29)
            public static let p30 = PropSet(rawValue: 1 << 30)
            public static let p31 = PropSet(rawValue: 1 << 31)
            public static let p32 = PropSet(rawValue: 1 << 32)
            public static let p33 = PropSet(rawValue: 1 << 33)
            public static let p34 = PropSet(rawValue: 1 << 34)
            public static let p35 = PropSet(rawValue: 1 << 35)
            public static let p36 = PropSet(rawValue: 1 << 36)
            public static let p37 = PropSet(rawValue: 1 << 37)
            public static let p38 = PropSet(rawValue: 1 << 38)
            public static let p39 = PropSet(rawValue: 1 << 39)
            public static let p40 = PropSet(rawValue: 1 << 40)
            public static let p41 = PropSet(rawValue: 1 << 41)
            public static let p42 = PropSet(rawValue: 1 << 42)
            public static let p43 = PropSet(rawValue: 1 << 43)
            public static let p44 = PropSet(rawValue: 1 << 44)
            public static let p45 = PropSet(rawValue: 1 << 45)
            public static let p46 = PropSet(rawValue: 1 << 46)
            public static let p47 = PropSet(rawValue: 1 << 47)
            public static let p48 = PropSet(rawValue: 1 << 48)
            public static let p49 = PropSet(rawValue: 1 << 49)
            public static let p50 = PropSet(rawValue: 1 << 50)
            public static let p51 = PropSet(rawValue: 1 << 51)
            public static let p52 = PropSet(rawValue: 1 << 52)
            public static let p53 = PropSet(rawValue: 1 << 53)
            public static let p54 = PropSet(rawValue: 1 << 54)
            public static let p55 = PropSet(rawValue: 1 << 55)
            public static let p56 = PropSet(rawValue: 1 << 56)
            public static let p57 = PropSet(rawValue: 1 << 57)
            public static let p58 = PropSet(rawValue: 1 << 58)
            public static let p59 = PropSet(rawValue: 1 << 59)
            public static let p60 = PropSet(rawValue: 1 << 60)
            public static let p61 = PropSet(rawValue: 1 << 61)
            public static let p62 = PropSet(rawValue: 1 << 62)
            public static let p63 = PropSet(rawValue: 1 << 63)
          }

          public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>
        }

        extension Props: AnyViewProps {
          public static let allProps = PropSet(rawValue: 0b1111111111111111111111111111111111111111111111111111111111111111)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .p0:
              return .p0
            case .p1:
              return .p1
            case .p2:
              return .p2
            case .p3:
              return .p3
            case .p4:
              return .p4
            case .p5:
              return .p5
            case .p6:
              return .p6
            case .p7:
              return .p7
            case .p8:
              return .p8
            case .p9:
              return .p9
            case .p10:
              return .p10
            case .p11:
              return .p11
            case .p12:
              return .p12
            case .p13:
              return .p13
            case .p14:
              return .p14
            case .p15:
              return .p15
            case .p16:
              return .p16
            case .p17:
              return .p17
            case .p18:
              return .p18
            case .p19:
              return .p19
            case .p20:
              return .p20
            case .p21:
              return .p21
            case .p22:
              return .p22
            case .p23:
              return .p23
            case .p24:
              return .p24
            case .p25:
              return .p25
            case .p26:
              return .p26
            case .p27:
              return .p27
            case .p28:
              return .p28
            case .p29:
              return .p29
            case .p30:
              return .p30
            case .p31:
              return .p31
            case .p32:
              return .p32
            case .p33:
              return .p33
            case .p34:
              return .p34
            case .p35:
              return .p35
            case .p36:
              return .p36
            case .p37:
              return .p37
            case .p38:
              return .p38
            case .p39:
              return .p39
            case .p40:
              return .p40
            case .p41:
              return .p41
            case .p42:
              return .p42
            case .p43:
              return .p43
            case .p44:
              return .p44
            case .p45:
              return .p45
            case .p46:
              return .p46
            case .p47:
              return .p47
            case .p48:
              return .p48
            case .p49:
              return .p49
            case .p50:
              return .p50
            case .p51:
              return .p51
            case .p52:
              return .p52
            case .p53:
              return .p53
            case .p54:
              return .p54
            case .p55:
              return .p55
            case .p56:
              return .p56
            case .p57:
              return .p57
            case .p58:
              return .p58
            case .p59:
              return .p59
            case .p60:
              return .p60
            case .p61:
              return .p61
            case .p62:
              return .p62
            case .p63:
              return .p63
            }
          }
        }
        """
    )
  }

  @Test
  func `A stored property with observers is still a prop`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var color: UIColor = .red {
          didSet {
            print(color)
          }
        }
      }
      """,
      expandedSource: """
        struct Props {
          var color: UIColor = .red {
            didSet {
              print(color)
            }
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
          public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
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
  func `Several bindings in one declaration are separate props`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var a: Int = 0, b: Int = 0
      }
      """,
      expandedSource: """
        struct Props {
          var a: Int = 0, b: Int = 0

          public enum PropName: String, CaseIterable {
            case a
            case b
          }

          public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let a = PropSet(rawValue: 1 << 0)
            public static let b = PropSet(rawValue: 1 << 1)
          }

          public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>
        }

        extension Props: AnyViewProps {
          public static let allProps = PropSet(rawValue: 0b11)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .a:
              return .a
            case .b:
              return .b
            }
          }
        }
        """
    )
  }

  @Test
  func `An escaped name drops its backticks in the wire key`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var `default`: Int = 0
      }
      """,
      expandedSource: """
        struct Props {
          var `default`: Int = 0

          public enum PropName: String, CaseIterable {
            case `default` = "default"
          }

          public struct PropSet: OptionSet, Sendable {
            public let rawValue: UInt64

            public init(rawValue: UInt64) {
              self.rawValue = rawValue
            }

            public static let `default` = PropSet(rawValue: 1 << 0)
          }

          public static let _eventNames: [String] = []

          public typealias Diff = PropsDiff<Self>
        }

        extension Props: AnyViewProps {
          public static let allProps = PropSet(rawValue: 0b1)

          /// `@inlinable` so core's raw-key fold can inline the lookup across the module boundary:
          /// it runs once per changed key per props batch.
          @inlinable
          public static func propSet(for name: PropName) -> PropSet {
            switch name {
            case .`default`:
              return .`default`
            }
          }
        }
        """
    )
  }

  @Test
  func `Optional spelled generically is still a rejected event`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var onTap: Optional<() -> Void>
      }
      """,
      expandedSource: """
        struct Props {
          var onTap: Optional<() -> Void>
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "Event props cannot be optional — 'onTap' is registered once at view creation, so its presence can't vary. Drop the '?'",
          line: 3,
          column: 14,
          fixIts: [FixItSpec(message: "Make 'onTap' non-optional")]
        )
      ]
    )
  }

  @Test
  func `A prop named rawValue produces a diagnostic`() {
    // It would emit a PropSet static member shadowing the option set's own storage.
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var rawValue: Int = 0
      }
      """,
      expandedSource: """
        struct Props {
          var rawValue: Int = 0
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "'rawValue' can't be used as a prop name — it collides with the synthesized PropSet's storage. Rename the property",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `A tuple-destructuring property produces a diagnostic`() {
    assertExpansion(
      """
      @ViewProps
      struct Props {
        var (a, b) = (1, 2)
      }
      """,
      expandedSource: """
        struct Props {
          var (a, b) = (1, 2)
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ViewProps does not support tuple-destructuring properties — declare each prop separately",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `A generic props struct produces a diagnostic`() {
    assertExpansion(
      """
      @ViewProps
      struct Props<T> {
        var value: T
      }
      """,
      expandedSource: """
        struct Props<T> {
          var value: T
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@ViewProps does not support generic types — a view's props type must be concrete",
          line: 1,
          column: 1
        )
      ]
    )
  }

  @Test
  func `The @Field diagnostic offers a removal fix-it`() {
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
          line: 3,
          column: 3,
          fixIts: [FixItSpec(message: "Remove the '@Field' attribute")]
        )
      ],
      applyFixIts: ["Remove the '@Field' attribute"],
      fixedSource: """
        @ViewProps
        struct Props {
          var color: UIColor = .red
        }
        """
    )
  }

  @Test
  func `The optional-event diagnostic offers an unwrapping fix-it`() {
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
          line: 3,
          column: 14,
          fixIts: [FixItSpec(message: "Make 'onTap' non-optional")]
        )
      ],
      applyFixIts: ["Make 'onTap' non-optional"],
      fixedSource: """
        @ViewProps
        struct Props {
          var onTap: (TapEvent) -> Void
        }
        """
    )
  }
}
