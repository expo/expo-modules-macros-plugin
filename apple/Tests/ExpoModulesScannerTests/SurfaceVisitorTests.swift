@testable import ExpoModulesScanner
import Foundation
import SwiftParser
import Testing

/// Parses a source string and returns the exported surface the visitor extracts. The file name is
/// fixed so any per-type `file` field is stable across runs.
private func surface(_ source: String) -> SurfaceVisitor {
  let tree = Parser.parse(source: source)
  let visitor = SurfaceVisitor(file: "Test.swift")
  visitor.walk(tree)
  return visitor
}

@Suite("Exports surface: modules")
struct ModuleSurfaceTests {
  @Test
  func `Extracts a module's @JS functions with names, params, and effects`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule("Greeter")
        final class GreeterModule {
          @JS
          func greet(name: String, loud: Bool = false) -> String { "" }

          @JS("doWork")
          func performWork() async throws {}

          // Not exported: no @JS.
          func helper() {}
        }
        """
      ).modules.first)

    #expect(module.name == "GreeterModule")
    #expect(module.jsName == "Greeter")
    #expect(module.functions.map(\.name) == ["greet", "performWork"])

    let greet = try #require(module.functions.first { $0.name == "greet" })
    #expect(greet.jsName == "greet")
    #expect(greet.returns == .primitive(name: "String", jsType: .string))
    #expect(greet.isAsync == false)
    #expect(greet.isThrowing == false)
    #expect(greet.parameters.map(\.name) == ["name", "loud"])
    #expect(greet.parameters.map(\.type) == [.primitive(name: "String", jsType: .string), .primitive(name: "Bool", jsType: .boolean)])
    // A defaulted parameter is omittable, so it's reported optional.
    #expect(greet.parameters.map(\.isOptional) == [false, true])

    let work = try #require(module.functions.first { $0.name == "performWork" })
    // The @JS("doWork") override becomes the JS name; the Swift name is kept separately.
    #expect(work.jsName == "doWork")
    #expect(work.isAsync == true)
    #expect(work.isThrowing == true)
    // A Void return is dropped to nil.
    #expect(work.returns == nil)
  }

  @Test
  func `Extracts @JS properties with type and settability`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule
        final class M {
          @JS var counter = 0
          @JS var status: String { "ok" }
          @JS let id: String
          @JS var name: String {
            get { "" }
            set {}
          }
          @JS var observed: Int = 0 {
            didSet {}
          }
        }
        """
      ).modules.first)

    let byName = Dictionary(uniqueKeysWithValues: module.properties.map { ($0.name, $0) })

    // Stored var: typed from its literal default, settable.
    #expect(byName["counter"]?.type == .primitive(name: "Int", jsType: .number))
    #expect(byName["counter"]?.isSettable == true)
    // Getter-only computed var: read-only.
    #expect(byName["status"]?.type == .primitive(name: "String", jsType: .string))
    #expect(byName["status"]?.isSettable == false)
    // let: never settable.
    #expect(byName["id"]?.isSettable == false)
    // Computed var with an explicit set: settable.
    #expect(byName["name"]?.isSettable == true)
    // Observed stored var (`didSet`): still backed by storage, so settable.
    #expect(byName["observed"]?.isSettable == true)
  }

  @Test
  func `Resolves a module's jsName: explicit override, else the class name`() {
    #expect(surface("@ExpoModule\nfinal class Plain {}").modules.first?.jsName == "Plain")
    #expect(surface("@ExpoModule(\"JS\")\nfinal class Renamed {}").modules.first?.jsName == "JS")
  }
}

@Suite("Exports surface: shared objects")
struct SharedObjectSurfaceTests {
  @Test
  func `Extracts a shared object's constructor, functions, and properties`() throws {
    let shared = try #require(
      surface(
        """
        @SharedObject
        final class Cache: SharedObject {
          @JS
          init(name: String, size: Int?) {}

          @JS
          func clear() {}

          @JS
          let id: String
        }
        """
      ).sharedObjects.first)

    #expect(shared.name == "Cache")
    #expect(shared.jsName == "Cache")
    #expect(shared.constructorParameters?.map(\.name) == ["name", "size"])
    // An optional-typed parameter is omittable.
    #expect(shared.constructorParameters?.map(\.isOptional) == [false, true])
    #expect(shared.functions.map(\.name) == ["clear"])
    #expect(shared.properties.map(\.name) == ["id"])
    #expect(shared.properties.first?.isSettable == false)
  }

  @Test
  func `Reports a nil constructor when there's no @JS init`() throws {
    let shared = try #require(
      surface(
        """
        @SharedObject
        final class Cache: SharedObject {
          @JS func clear() {}
        }
        """
      ).sharedObjects.first)
    #expect(shared.constructorParameters == nil)
  }
}

@Suite("Exports surface: records")
struct RecordSurfaceTests {
  @Test
  func `Extracts record properties, excluding non-stored and non-eligible ones`() throws {
    let record = try #require(
      surface(
        """
        @Record
        struct Options {
          var name: String
          var retries: Int = 3
          var note: String?
          private var secret: Int = 0
          static var shared: Int = 0
          var computed: Int { 1 }
        }
        """
      ).records.first)

    #expect(record.name == "Options")
    // private, static, and computed properties are excluded.
    #expect(record.properties.map(\.name) == ["name", "retries", "note"])

    let byName = Dictionary(uniqueKeysWithValues: record.properties.map { ($0.name, $0) })
    // A property is required only when it has no default and isn't optional.
    #expect(byName["name"]?.isOptional == false)
    #expect(byName["name"]?.hasDefault == false)
    #expect(byName["name"]?.isRequired == true)
    // A defaulted property is not required.
    #expect(byName["retries"]?.hasDefault == true)
    #expect(byName["retries"]?.isOptional == false)
    #expect(byName["retries"]?.isRequired == false)
    // An optional property is not required (decodes to nil when omitted), even with no written default.
    #expect(byName["note"]?.isOptional == true)
    #expect(byName["note"]?.hasDefault == false)
    #expect(byName["note"]?.isRequired == false)
  }
}

@Suite("Exports surface: enums")
struct EnumSurfaceTests {
  @Test
  func `Extracts an Enumerable enum's raw type and cases`() throws {
    let enumeration = try #require(
      surface(
        """
        enum Status: String, Enumerable {
          case active = "active"
          case idle
        }
        """
      ).enums.first)

    #expect(enumeration.name == "Status")
    #expect(enumeration.rawType == .primitive(name: "String", jsType: .string))
    #expect(enumeration.cases.map(\.name) == ["active", "idle"])
    // A String raw value is reported decoded: the value, not its source spelling. A case with no
    // written value takes the case's own name.
    #expect(enumeration.cases.map(\.rawValue) == ["active", "idle"])
  }

  @Test
  func `Reports an Int-backed enum and its written raw values`() throws {
    let enumeration = try #require(
      surface(
        """
        enum Priority: Int, Enumerable {
          case low = 1
          case high = 2
        }
        """
      ).enums.first)

    #expect(enumeration.rawType == .primitive(name: "Int", jsType: .number))
    #expect(enumeration.cases.map(\.rawValue) == ["1", "2"])
  }

  @Test
  func `Reports a bare Enumerable conformance with no raw type`() throws {
    let enumeration = try #require(
      surface(
        """
        enum Mode: Enumerable {
          case on
          case off
        }
        """
      ).enums.first)

    // Nothing precedes the conformance, so there's no raw type to report.
    #expect(enumeration.rawType == nil)
    #expect(enumeration.cases.map(\.name) == ["on", "off"])
  }

  @Test
  func `Accepts a qualified Enumerable spelling`() {
    let visitor = surface(
      """
      enum Status: String, ExpoModulesCore.Enumerable {
        case active
      }
      """
    )
    #expect(visitor.enums.map(\.name) == ["Status"])
  }

  @Test
  func `Ignores an enum that doesn't conform to Enumerable`() {
    let visitor = surface(
      """
      enum Plain: String {
        case a
      }
      enum Bare {
        case b
      }
      """
    )
    // A raw value alone doesn't make an enum convertible: core keys on the conformance.
    #expect(visitor.enums.isEmpty)
  }

  @Test
  func `Ignores a nested Enumerable enum`() {
    let visitor = surface(
      """
      @ExpoModule
      final class M {
        enum Status: String, Enumerable {
          case active
        }
      }
      """
    )
    // Top-level only, matching how every other type in the surface is collected.
    #expect(visitor.enums.isEmpty)
  }

  @Test
  func `Skips cases carrying associated values`() throws {
    let enumeration = try #require(
      surface(
        """
        enum Mixed: Enumerable {
          case plain
          case payload(Int)
        }
        """
      ).enums.first)

    // An associated value has no raw value, so it can't cross the boundary as one.
    #expect(enumeration.cases.map(\.name) == ["plain"])
  }

  @Test
  func `Reports no raw type when a protocol precedes the conformance`() {
    let visitor = surface(
      """
      enum A: Codable, Enumerable { case a }
      enum B: CaseIterable, Enumerable { case b }
      enum C: Sendable, Enumerable { case c }
      """
    )

    // All three are legal raw-value-less enums: a protocol written first is not a raw type, and
    // reporting one would have a generator emit the enum as a `Codable`-typed value.
    #expect(visitor.enums.map(\.name) == ["A", "B", "C"])
    #expect(visitor.enums.allSatisfy { $0.rawType == nil })
  }

  @Test
  func `Reports only the raw values a case writes, not Swift's implicit continuation`() throws {
    let enumeration = try #require(
      surface(
        """
        enum Continued: Int, Enumerable {
          case a = 1
          case b
          case c = 10
          case d
        }
        """
      ).enums.first)

    // `b` is 2 and `d` is 11, each continuing from the preceding explicit value, written or derived.
    // One unreadable expression would corrupt every case after it, so Int is never derived and the
    // consumer applies the continuation rule. Only String, which has no carry, is filled in.
    #expect(enumeration.cases.map(\.rawValue) == ["1", nil, "10", nil])
  }

  @Test
  func `Derives a String raw value for every case that writes none`() throws {
    let enumeration = try #require(
      surface(
        """
        enum Status: String, Enumerable {
          case playing
          case paused
          case stopped = "halted"
        }
        """
      ).enums.first)

    // The invariant a consumer relies on: a String-backed enum reports a raw value on *every* case,
    // so there is nothing left to derive on the other side of the boundary.
    #expect(enumeration.cases.map(\.rawValue) == ["playing", "paused", "halted"])
  }

  @Test
  func `Derives String raw values through a qualified raw type`() throws {
    let enumeration = try #require(
      surface(
        """
        enum Status: Swift.String, Enumerable {
          case active
        }
        """
      ).enums.first)

    // `Swift.String` is a legal raw type that parses as a `.ref` rather than a `.primitive`; the
    // invariant has to hold for it too.
    #expect(enumeration.cases.map(\.rawValue) == ["active"])
  }

  @Test
  func `Falls back to the derived name for an interpolated raw value`() throws {
    let enumeration = try #require(
      surface(
        #"""
        enum Status: String, Enumerable {
          case a = "x\(y)"
          case b = "plain"
        }
        """#
      ).enums.first)

    // An interpolated literal isn't a legal raw value, and its source text isn't the value, so it's
    // not passed through. Reporting the derived name keeps the String invariant intact.
    #expect(enumeration.cases.map(\.rawValue) == ["a", "plain"])
  }

  @Test
  func `Decodes a raw string literal and falls back on an escape`() throws {
    let enumeration = try #require(
      surface(
        #"""
        enum Status: String, Enumerable {
          case a = #"raw"#
          case b = "tab\there"
        }
        """#
      ).enums.first)

    // A raw literal's delimiters are stripped like any other's. An escape would need real unescaping
    // to become its value, so that case falls back to the derived name rather than reporting `\t`
    // as the two characters it is written as.
    #expect(enumeration.cases.map(\.rawValue) == ["raw", "b"])
  }

  @Test
  func `Reports an integer raw value as written, not decoded`() throws {
    let enumeration = try #require(
      surface(
        """
        enum Priority: Int, Enumerable {
          case low = 1
          case shifted = 1 << 3
        }
        """
      ).enums.first)

    // An integer raw value may be any literal expression, so it stays source text: the scanner can't
    // evaluate `1 << 3`, and reporting it verbatim is the honest answer.
    #expect(enumeration.cases.map(\.rawValue) == ["1", "1 << 3"])
  }

  @Test
  func `Leaves a raw value alone when the enum has no String raw type`() throws {
    let ints = try #require(
      surface("enum P: Int, Enumerable { case low = 1\n case high }").enums.first)
    let bare = try #require(
      surface("enum M: Enumerable { case on }").enums.first)

    // Nothing to derive without a String raw type: an Int case carries the continuation rule, and a
    // raw-value-less enum has no raw values at all.
    #expect(ints.cases.map(\.rawValue) == ["1", nil])
    #expect(bare.cases.map(\.rawValue) == [nil])
  }

  @Test
  func `Reports each case of a multi-case declaration`() throws {
    let enumeration = try #require(
      surface(
        """
        enum Status: String, Enumerable {
          case active, idle
        }
        """
      ).enums.first)

    #expect(enumeration.cases.map(\.name) == ["active", "idle"])
  }
}

@Suite("Exports surface: unions")
struct UnionSurfaceTests {
  @Test
  func `Extracts a union's members in declaration order`() throws {
    let union = try #require(
      surface(
        """
        @Union
        enum Source {
          case text(String)
          case count(Int)
          case options(SourceOptions)
        }
        """
      ).unions.first)

    #expect(union.name == "Source")
    #expect(union.members.map(\.name) == ["text", "count", "options"])
    #expect(
      union.members.map(\.type) == [
        .primitive(name: "String", jsType: .string),
        .primitive(name: "Int", jsType: .number),
        .ref(name: "SourceOptions"),
      ])
  }

  @Test
  func `Keeps declaration order, which decides which overlapping payload wins`() throws {
    let union = try #require(
      surface(
        """
        @Union
        enum Number {
          case whole(Int)
          case fractional(Double)
        }
        """
      ).unions.first)

    // Decode takes the first payload that succeeds, so the reported order is the decode order. A
    // consumer that reorders these describes a different union.
    #expect(union.members.map(\.name) == ["whole", "fractional"])
  }

  @Test
  func `Reports a labeled associated value by its type`() throws {
    let union = try #require(
      surface(
        """
        @Union
        enum Identifier {
          case id(value: Int)
        }
        """
      ).unions.first)

    // The label is Swift-side construction detail; the boundary only sees the payload type.
    #expect(union.members.map(\.name) == ["id"])
    #expect(union.members.map(\.type) == [.primitive(name: "Int", jsType: .number)])
  }

  @Test
  func `Skips cases the macro rejects`() throws {
    let union = try #require(
      surface(
        """
        @Union
        enum Mixed {
          case text(String)
          case none
          case pair(Int, Int)
          case defaulted(Int = 0)
        }
        """
      ).unions.first)

    // Each of the three is a macro error, so no such alternative exists at runtime and reporting one
    // would describe a union the module never accepts.
    #expect(union.members.map(\.name) == ["text"])
  }

  @Test
  func `Reports each case of a multi-case declaration`() throws {
    let union = try #require(
      surface(
        """
        @Union
        enum Source {
          case text(String), count(Int)
        }
        """
      ).unions.first)

    #expect(union.members.map(\.name) == ["text", "count"])
  }

  @Test
  func `Ignores an enum without the @Union attribute`() {
    let visitor = surface(
      """
      enum Plain {
        case text(String)
      }
      enum Raw: String {
        case a
      }
      """
    )
    // Detection is attribute-driven: no @Union, no report.
    #expect(visitor.unions.isEmpty)
  }

  @Test
  func `Reports an enum that is both @Union and Enumerable only as a union`() {
    let visitor = surface(
      """
      @Union
      enum Weird: String, Enumerable {
        case text(String)
      }
      """
    )

    // @Union is checked first and wins. Its cases carry payloads rather than raw values, so there
    // would be nothing to report as an enum, and reporting the type in both arrays would describe two
    // contradictory JS types for one declaration.
    #expect(visitor.unions.map(\.name) == ["Weird"])
    #expect(visitor.enums.isEmpty)
  }

  @Test
  func `Reports a union and an Enumerable enum side by side`() {
    let visitor = surface(
      """
      @Union
      enum Source {
        case text(String)
      }

      enum Status: String, Enumerable {
        case active
      }
      """
    )

    // The two kinds coexist in one file: one recognized by attribute, the other by conformance.
    #expect(visitor.unions.map(\.name) == ["Source"])
    #expect(visitor.enums.map(\.name) == ["Status"])
  }

  @Test
  func `Ignores a nested @Union`() {
    let visitor = surface(
      """
      @ExpoModule
      final class M {
        @Union
        enum Source {
          case text(String)
        }
      }
      """
    )
    // Top-level only, matching how every other type in the surface is collected.
    #expect(visitor.unions.isEmpty)
  }

  @Test
  func `Reports a union whose payloads are composed types`() throws {
    let union = try #require(
      surface(
        """
        @Union
        enum Payload {
          case many([String])
          case maybe(Int?)
          case table([String: Double])
        }
        """
      ).unions.first)

    #expect(
      union.members.map(\.type) == [
        .array(element: .primitive(name: "String", jsType: .string)),
        .optional(wrapped: .primitive(name: "Int", jsType: .number)),
        .dictionary(
          key: .primitive(name: "String", jsType: .string),
          value: .primitive(name: "Double", jsType: .number)),
      ])
  }
}

@Suite("Exports surface: events")
struct EventSurfaceTests {
  @Test
  func `Extracts @Event members with payload, JS name, and sync flag`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule
        final class PlayerModule {
          @Event
          var onStatusChange: (StatusPayload) -> Void

          @Event
          var onFinish: () -> Void

          @Event("legacyName")
          var onRenamed: (Int) -> Void

          @Event(sync: true)
          var onTick: (Double) -> Void

          // Not an event: a plain @JS member.
          @JS
          func play() {}
        }
        """
      ).modules.first)

    #expect(module.events.map(\.name) == ["onStatusChange", "onFinish", "onRenamed", "onTick"])

    // The conventional `on` prefix is stripped for the JS name; the Swift name is kept separately.
    let status = try #require(module.events.first { $0.name == "onStatusChange" })
    #expect(status.jsName == "statusChange")
    #expect(status.payload == .ref(name: "StatusPayload"))
    #expect(status.isSync == false)

    // A `() -> Void` event has no payload.
    let finish = try #require(module.events.first { $0.name == "onFinish" })
    #expect(finish.jsName == "finish")
    #expect(finish.payload == nil)

    // An explicit override is used verbatim, never transformed.
    let renamed = try #require(module.events.first { $0.name == "onRenamed" })
    #expect(renamed.jsName == "legacyName")

    let tick = try #require(module.events.first { $0.name == "onTick" })
    #expect(tick.isSync == true)

    // Events are collected separately from functions and properties.
    #expect(module.functions.map(\.name) == ["play"])
    #expect(module.properties.isEmpty)
  }

  /// Pins the derivation against `EventMacro`'s copy: a drift produces listener names the module
  /// never emits.
  @Test(arguments: [
    ("onStatusChange", "statusChange"),
    // A leading acronym run keeps its last capital, which starts the next word.
    ("onURLChange", "urlChange"),
    ("onURL", "url"),
    // No `on` prefix, or no capital after it: passed through verbatim.
    ("statusChange", "statusChange"),
    ("online", "online"),
    ("on", "on"),
  ])
  func `Derives the JS event name the way the macro does`(swiftName: String, expected: String) throws {
    let module = try #require(
      surface(
        """
        @ExpoModule
        final class EventsModule {
          @Event
          var \(swiftName): (Int) -> Void
        }
        """
      ).modules.first)

    #expect(module.events.map(\.jsName) == [expected])
  }

  @Test
  func `Extracts @Event members on a shared object`() throws {
    let sharedObject = try #require(
      surface(
        """
        @SharedObject
        final class Download: SharedObject {
          @Event
          var onProgress: (Double) -> Void
        }
        """
      ).sharedObjects.first)

    let progress = try #require(sharedObject.events.first)
    #expect(progress.name == "onProgress")
    #expect(progress.jsName == "progress")
    #expect(progress.payload == .primitive(name: "Double", jsType: .number))
  }

  /// Every shape `EventMacro.validatedEvent(of:on:)` rejects. None expands to an event at runtime.
  @Test
  func `Skips an @Event the macro would reject`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule
        final class BadEventsModule {
          // Not a function type.
          @Event
          var notAFunction: Int

          // No type annotation at all.
          @Event
          var untyped = 0

          // Events are emitted from an instance.
          @Event
          static var onStatic: (Int) -> Void

          // The macro synthesizes a computed getter, which a 'let' cannot be.
          @Event
          let onLet: (Int) -> Void

          // An event dispatches to JS and has no return value.
          @Event
          var onReturns: (Int) -> String

          // At most one payload parameter.
          @Event
          var onTwoParams: (Int, String) -> Void

          // The macro synthesizes the getter, so hand-written accessors are rejected.
          @Event
          var onComputed: (Int) -> Void { { _ in } }

          // An initial value is rejected; the macro synthesizes the closure.
          @Event
          var onInitialized: (Int) -> Void = { _ in }

          @Event
          var onValid: () -> Void
        }
        """
      ).modules.first)

    #expect(module.events.map(\.name) == ["onValid"])
  }

  /// The macro accepts all four spellings, so the surface must too. The shared `isVoidType` accepts
  /// only the first two, which is why the event path has its own check.
  @Test
  func `Accepts every spelling of a Void event return`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule
        final class VoidSpellingsModule {
          @Event
          var onPlain: (Int) -> Void

          @Event
          var onEmptyTuple: (Int) -> ()

          @Event
          var onQualified: (Int) -> Swift.Void

          @Event
          var onParenthesized: (Int) -> (Void)
        }
        """
      ).modules.first)

    #expect(module.events.map(\.name) == ["onPlain", "onEmptyTuple", "onQualified", "onParenthesized"])
  }

  /// `@JS` and `@Event` on one property is a macro error. The scanner doesn't diagnose, but must
  /// not report the member twice.
  @Test
  func `Reports a property carrying both @JS and @Event only once`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule
        final class ConflictModule {
          @JS
          @Event
          var onBoth: (Int) -> Void
        }
        """
      ).modules.first)

    #expect(module.events.isEmpty)
    #expect(module.properties.map(\.name) == ["onBoth"])
  }

  @Test
  func `Unwraps attributed and parenthesized event function types`() throws {
    let module = try #require(
      surface(
        """
        @ExpoModule
        final class WrappedModule {
          @Event
          var onSendable: @Sendable (Int) -> Void

          @Event
          var onParenthesized: ((String) -> Void)
        }
        """
      ).modules.first)

    #expect(module.events.map(\.jsName) == ["sendable", "parenthesized"])
    #expect(module.events.map(\.payload) == [
      .primitive(name: "Int", jsType: .number),
      .primitive(name: "String", jsType: .string),
    ])
  }
}

@Suite("Exports surface: scoping")
struct SurfaceScopingTests {
  @Test
  func `Ignores non-Expo types and nested types`() {
    let visitor = surface(
      """
      final class Plain {
        @JS func notExported() {}
      }
      @ExpoModule
      final class Outer {
        @JS func exported() {}
        @ExpoModule
        final class Nested {
          @JS func nested() {}
        }
      }
      """
    )
    // A plain class contributes nothing, and a nested @ExpoModule isn't descended into.
    #expect(visitor.modules.map(\.name) == ["Outer"])
    #expect(visitor.modules.first?.functions.map(\.name) == ["exported"])
  }

  @Test
  func `Routes each macro to its own bucket`() {
    let visitor = surface(
      """
      @ExpoModule final class M {}
      @SharedObject final class S: SharedObject {}
      @Record struct R { var x: Int = 0 }
      enum E: String, Enumerable { case a }
      @Union enum U { case a(Int) }
      """
    )
    #expect(visitor.modules.map(\.name) == ["M"])
    #expect(visitor.sharedObjects.map(\.name) == ["S"])
    #expect(visitor.records.map(\.name) == ["R"])
    #expect(visitor.enums.map(\.name) == ["E"])
    #expect(visitor.unions.map(\.name) == ["U"])
  }
}

@Suite("scan-exports over a directory")
struct ScanExportsTests {
  /// Writes `files` (relative path, contents) into a fresh temp tree, runs `scanExports` over its
  /// root, and hands the result to `body`. The tree is removed afterward.
  private func withTree(
    _ files: [(String, String)],
    _ body: (ScanExportsResult) throws -> Void
  ) throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("scanner-exports-\(ProcessInfo.processInfo.globallyUniqueString)")
    defer { try? fileManager.removeItem(at: root) }

    for (relativePath, contents) in files {
      let url = root.appendingPathComponent(relativePath)
      try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    try body(scanExports(paths: [root.path]))
  }

  @Test
  func `Collects every kind across a tree, with absolute file paths and stats`() throws {
    try withTree([
      ("Module.swift", "@ExpoModule\nfinal class M { @JS func f() {} }"),
      ("Shared.swift", "@SharedObject\nfinal class S: SharedObject { @JS init() {} }"),
      ("Options.swift", "@Record\nstruct R { var name: String }"),
      ("Status.swift", "enum E: String, Enumerable { case a }"),
      ("Source.swift", "@Union\nenum U { case text(String) }"),
      ("Plain.swift", "final class Plain {}"),
    ]) { result in
      #expect(result.exports.modules.map(\.name) == ["M"])
      #expect(result.exports.sharedObjects.map(\.name) == ["S"])
      #expect(result.exports.records.map(\.name) == ["R"])
      // An enum in a file carrying no macro attribute is still found: the pre-filter admits it on
      // the bare `Enumerable` conformance.
      #expect(result.exports.enums.map(\.name) == ["E"])
      #expect(result.exports.unions.map(\.name) == ["U"])
      // Reported paths are absolute.
      #expect(result.exports.modules.first?.file.hasPrefix("/") == true)
      #expect(result.schemaVersion == scanExportsSchemaVersion)
      // All six files are read; the plain one (no macro, no conformance) isn't parsed.
      #expect(result.stats.filesScanned == 6)
      #expect(result.stats.filesParsed == 5)
    }
  }
}
