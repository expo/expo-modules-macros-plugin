import Foundation

/// Which Expo macro was found on a declaration. The scanner recognizes the entry-point macros that
/// mark a type or member as part of a module's JS surface, plus `@Record` for convertible types.
enum DetectedMacro: String, Codable, CaseIterable {
  case expoModule = "ExpoModule"
  case js = "JS"
  case sharedObject = "SharedObject"
  case record = "Record"
}

/// What a scan looks for. The CLI exposes one subcommand per mode; they serve different consumers and
/// will eventually produce different output shapes, so this drives both the macro filter and (later)
/// the depth of extraction.
public enum ScanMode {
  /// Fast path for `expo-modules-autolinking`: only top-level `@ExpoModule` types (the module class
  /// names autolinking registers). The narrowest pre-filter and no member walking.
  case modules

  /// Deep path for TypeScript type generation: every entry-point macro and (eventually) the full
  /// member surface each type exports to JS. Not yet implemented — see the `scan-exports` stub.
  case exports

  /// The macros a scan in this mode reports. `modules` is intentionally `@ExpoModule`-only.
  var detectedMacros: Set<DetectedMacro> {
    switch self {
    case .modules:
      return [.expoModule]
    case .exports:
      return Set(DetectedMacro.allCases)
    }
  }
}

/// A single argument passed to a macro, e.g. `"Foo"` or `classes: [Bar.self]`. The label is `nil`
/// for positional arguments; `value` is the argument expression's source text as written.
struct MacroArgument: Codable, Equatable {
  /// The argument label (`classes` in `classes: [Bar.self]`), or `nil` for a positional argument.
  let label: String?

  /// The argument value exactly as written in source, e.g. `"Foo"` (including the quotes) or
  /// `[Bar.self]`. Kept as text because a syntactic scan can't resolve these to runtime values.
  let value: String
}

/// A single annotated declaration the scanner found, with just enough to locate it and know
/// what it is. Member-level details (parameters, types) are intentionally out of scope for this
/// first prototype — see the `@JS` member walk in the macros for where that would live.
struct Detection: Codable, Equatable {
  /// The macro spelled on the declaration (without the leading `@`).
  let macro: DetectedMacro

  /// The declared name, e.g. the class name for `@ExpoModule`, or the func/var/init name for `@JS`.
  let name: String

  /// The kind of declaration the macro was attached to: `class`, `struct`, `func`, `var`, `init`, …
  let declarationKind: String

  /// The explicit JS name override when written as `@ExpoModule("Foo")` / `@JS("bar")` /
  /// `@SharedObject("Baz")`, otherwise `nil` (the name defaults to `name` at expansion time).
  let jsName: String?

  /// Every argument passed to the macro, in source order, e.g. `@ExpoModule("Foo", classes: [Bar.self])`
  /// yields a positional `"Foo"` and a `classes:` argument. Empty when the macro is written bare.
  let arguments: [MacroArgument]

  /// Source location, relative to the path the scanner was invoked with.
  let file: String
  let line: Int
  let column: Int
}

/// Counts describing how much work the scan did, so callers can see the pre-filter's effect: of all
/// the `.swift` files read, how many actually needed parsing, and how long the run took.
struct ScanStats: Codable, Equatable {
  /// `.swift` files the walk found and read (after directory pruning).
  let filesScanned: Int

  /// Of those, how many contained a macro attribute and so were parsed with SwiftSyntax.
  let filesParsed: Int

  /// Wall-clock duration of the scan, in milliseconds (walking, reading, filtering, and parsing).
  let durationMs: Double
}

/// One module in the `scan-modules` output. Trimmed to what `expo-modules-autolinking` needs to
/// register a module: the Swift class name, the JS name it registers under, and the file it's in.
/// The richer fields the visitor captures (declaration kind, raw macro arguments, line/column) are
/// dropped here — they're redundant for this command (the macro is always `@ExpoModule` on a class)
/// and belong to the deep `scan-exports` surface instead.
struct ScannedModule: Codable, Equatable {
  /// The Swift class name the module is declared as.
  let name: String

  /// The fully-resolved JS module name: the `@ExpoModule("Foo")` override when present, otherwise the
  /// class name. Resolved here (rather than left `nil`) so it matches how the macro derives the name
  /// and the consumer never has to apply the fallback itself.
  let jsName: String

  /// Source file the module was found in, relative to the path the scanner was invoked with.
  let file: String
}

/// The `scan-modules` result: the detected modules plus the stats describing the run. Encoded as the
/// command's JSON output. (`scan-exports` will return its own shape when implemented; the two
/// commands serve different consumers and aren't expected to share an envelope.)
struct ScanModulesResult: Codable, Equatable {
  let modules: [ScannedModule]
  let stats: ScanStats
}
