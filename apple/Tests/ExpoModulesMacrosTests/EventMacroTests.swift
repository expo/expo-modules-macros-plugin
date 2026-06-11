import ExpoModulesMacros
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let eventMacroSpecs: [String: MacroSpec] = [
  "Event": MacroSpec(type: EventMacro.self)
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
    macroSpecs: eventMacroSpecs,
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

@Suite("@Event macro")
struct EventMacroTests {
  @Test
  func `Payload event expands to a dispatching getter and a conformance assertion`() {
    assertExpansion(
      """
      class MyModule: Module {
        @Event
        var onProgress: (ProgressEvent) -> Void
      }
      """,
      expandedSource: """
        class MyModule: Module {
          var onProgress: (ProgressEvent) -> Void {
            get {
              { [weak self] payload in
                self?.emit(event: "progress", payload: payload)
              }
            }
          }

          private func _assertTypesConformance_onProgress() {
            func onProgress<P: AnyArgument, E: EventEmitter>(_: P.Type, _: E.Type) {
            }
            onProgress(ProgressEvent.self, MyModule.self)
          }
        }
        """
    )
  }

  @Test
  func `No-payload event dispatches through the payload-less emit overload`() {
    assertExpansion(
      """
      class MyModule: Module {
        @Event
        var onReady: () -> Void
      }
      """,
      expandedSource: """
        class MyModule: Module {
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
        }
        """
    )
  }

  @Test
  func `Name argument overrides the JS event name`() {
    assertExpansion(
      """
      class MyModule: Module {
        @Event("progress")
        var onProgress: (ProgressEvent) -> Void
      }
      """,
      expandedSource: """
        class MyModule: Module {
          var onProgress: (ProgressEvent) -> Void {
            get {
              { [weak self] payload in
                self?.emit(event: "progress", payload: payload)
              }
            }
          }

          private func _assertTypesConformance_onProgress() {
            func onProgress<P: AnyArgument, E: EventEmitter>(_: P.Type, _: E.Type) {
            }
            onProgress(ProgressEvent.self, MyModule.self)
          }
        }
        """
    )
  }

  @Test
  func `Leading acronym after the on prefix is decapitalized`() {
    assertExpansion(
      """
      class MyModule: Module {
        @Event
        var onURLChange: () -> Void
      }
      """,
      expandedSource: """
        class MyModule: Module {
          var onURLChange: () -> Void {
            get {
              { [weak self] in
                self?.emit(event: "urlChange")
              }
            }
          }

          private func _assertTypesConformance_onURLChange() {
            func onURLChange<E: EventEmitter>(_: E.Type) {
            }
            onURLChange(MyModule.self)
          }
        }
        """
    )
  }

  @Test
  func `Name without the on prefix passes through verbatim`() {
    assertExpansion(
      """
      class MyModule: Module {
        @Event
        var online: () -> Void
      }
      """,
      expandedSource: """
        class MyModule: Module {
          var online: () -> Void {
            get {
              { [weak self] in
                self?.emit(event: "online")
              }
            }
          }

          private func _assertTypesConformance_online() {
            func online<E: EventEmitter>(_: E.Type) {
            }
            online(MyModule.self)
          }
        }
        """
    )
  }

  @Test
  func `Primitive payload asserts only the emitter conformance`() {
    assertExpansion(
      """
      class MyModule: Module {
        @Event
        var onCount: (Int) -> Void
      }
      """,
      expandedSource: """
        class MyModule: Module {
          var onCount: (Int) -> Void {
            get {
              { [weak self] payload in
                self?.emit(event: "count", payload: payload)
              }
            }
          }

          private func _assertTypesConformance_onCount() {
            func onCount<E: EventEmitter>(_: E.Type) {
            }
            onCount(MyModule.self)
          }
        }
        """
    )
  }

  @Test
  func `Attributed function type is unwrapped to the underlying event`() {
    assertExpansion(
      """
      class MyModule: Module {
        @Event
        var onReady: @Sendable () -> Void
      }
      """,
      expandedSource: """
        class MyModule: Module {
          var onReady: @Sendable () -> Void {
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
        }
        """
    )
  }

  @Test
  func `Sync event dispatches through emitSync`() {
    assertExpansion(
      """
      class MyModule: Module {
        @Event(sync: true)
        var onTick: (TickEvent) -> Void
      }
      """,
      expandedSource: """
        class MyModule: Module {
          var onTick: (TickEvent) -> Void {
            get {
              { [weak self] payload in
                self?.emitSync(event: "tick", payload: payload)
              }
            }
          }

          private func _assertTypesConformance_onTick() {
            func onTick<P: AnyArgument, E: EventEmitter>(_: P.Type, _: E.Type) {
            }
            onTick(TickEvent.self, MyModule.self)
          }
        }
        """
    )
  }

  @Test
  func `Sync event combines with a name override`() {
    assertExpansion(
      """
      class MyModule: Module {
        @Event("onTick", sync: true)
        var onTick: () -> Void
      }
      """,
      expandedSource: """
        class MyModule: Module {
          var onTick: () -> Void {
            get {
              { [weak self] in
                self?.emitSync(event: "onTick")
              }
            }
          }

          private func _assertTypesConformance_onTick() {
            func onTick<E: EventEmitter>(_: E.Type) {
            }
            onTick(MyModule.self)
          }
        }
        """
    )
  }

  @Test
  func `Event declared in an extension asserts the extended type`() {
    assertExpansion(
      """
      extension MyModule {
        @Event
        var onReady: () -> Void
      }
      """,
      expandedSource: """
        extension MyModule {
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
        }
        """
    )
  }

  @Test
  func `Let binding produces a diagnostic with a fix-it replacing it with var`() {
    assertExpansion(
      """
      class MyModule: Module {
        @Event
        let onReady: () -> Void
      }
      """,
      expandedSource: """
        class MyModule: Module {
          let onReady: () -> Void
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Event must be applied to a 'var': it expands into a computed property, which a 'let' cannot be. The synthesized property is read-only anyway.",
          line: 3,
          column: 3,
          fixIts: [FixItSpec(message: "Replace 'let' with 'var'")]
        )
      ],
      fixedSource: """
        class MyModule: Module {
          @Event
          var onReady: () -> Void
        }
        """
    )
  }

  @Test
  func `Combining @Event with @JS produces a diagnostic`() {
    assertExpansion(
      """
      class MyModule: Module {
        @JS
        @Event
        var onProgress: (ProgressEvent) -> Void
      }
      """,
      expandedSource: """
        class MyModule: Module {
          @JS
          var onProgress: (ProgressEvent) -> Void
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message:
            "@Event and @JS cannot be combined on the same property; an event is exposed to JS on its own, so remove one of the attributes",
          line: 3,
          column: 3
        )
      ]
    )
  }

  @Test
  func `Static property produces a diagnostic`() {
    assertExpansion(
      """
      class MyModule: Module {
        @Event
        static var onReady: () -> Void
      }
      """,
      expandedSource: """
        class MyModule: Module {
          static var onReady: () -> Void
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Event must be an instance property; events are emitted from a module or shared object instance.",
          line: 2,
          column: 3
        )
      ]
    )
  }

  @Test
  func `Non-function type produces a diagnostic`() {
    assertExpansion(
      """
      class MyModule: Module {
        @Event
        var onProgress: String
      }
      """,
      expandedSource: """
        class MyModule: Module {
          var onProgress: String
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Event property must declare a function type, such as '(Payload) -> Void' or '() -> Void'",
          line: 2,
          column: 3
        )
      ]
    )
  }

  @Test
  func `Optional function type produces a diagnostic`() {
    assertExpansion(
      """
      class MyModule: Module {
        @Event
        var onProgress: ((ProgressEvent) -> Void)?
      }
      """,
      expandedSource: """
        class MyModule: Module {
          var onProgress: ((ProgressEvent) -> Void)?
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Event property must declare a function type, such as '(Payload) -> Void' or '() -> Void'",
          line: 2,
          column: 3
        )
      ]
    )
  }

  @Test
  func `Non-Void return produces a diagnostic`() {
    assertExpansion(
      """
      class MyModule: Module {
        @Event
        var onProgress: (ProgressEvent) -> Bool
      }
      """,
      expandedSource: """
        class MyModule: Module {
          var onProgress: (ProgressEvent) -> Bool
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Event function type must return 'Void'; an event dispatches to JS and has no return value",
          line: 2,
          column: 3
        )
      ]
    )
  }

  @Test
  func `Multiple payload parameters produce a diagnostic`() {
    assertExpansion(
      """
      class MyModule: Module {
        @Event
        var onProgress: (Double, String) -> Void
      }
      """,
      expandedSource: """
        class MyModule: Module {
          var onProgress: (Double, String) -> Void
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Event function type takes at most one payload parameter; combine multiple values into a single record",
          line: 2,
          column: 3
        )
      ]
    )
  }

  @Test
  func `Initial value produces a diagnostic`() {
    assertExpansion(
      """
      class MyModule: Module {
        @Event
        var onReady: () -> Void = {}
      }
      """,
      expandedSource: """
        class MyModule: Module {
          var onReady: () -> Void = {}
        }
        """,
      diagnostics: [
        DiagnosticSpec(
          message: "@Event property cannot have an initial value; the macro synthesizes the closure",
          line: 2,
          column: 3
        )
      ]
    )
  }
}
