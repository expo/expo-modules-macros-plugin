import Foundation

/// The scanner's public entry point. Argument parsing, subcommand dispatch, and usage text live in
/// the CLI target; this just runs a command and writes its JSON report to stdout.
///
/// The detection model (`Detection`, `DetectionVisitor`, …) stays `internal`: tests reach it via
/// `@testable import`, and the CLI only needs these entries, so nothing else is exposed.
public enum Scanner {
  /// Runs the `scan-modules` command over `paths`, prints the JSON report to stdout, and returns a
  /// process exit code: `0` on success, `1` if encoding fails. (The deep `scan-exports` command has
  /// its own `runExports` entry returning its own result type.)
  ///
  /// `platform` and `defines` (the `--platform` and `--define` options) form the configuration that
  /// `#if` conditions are evaluated against; see `ScanBuildConfiguration`.
  public static func runModules(paths: [String], platform: String? = nil, defines: [String] = []) -> Int32 {
    let configuration = ScanBuildConfiguration(platform: platform, defines: Set(defines))
    let result = scanModules(paths: paths, configuration: configuration)

    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data("\n".utf8))
      return 0
    } catch {
      FileHandle.standardError.write(Data("error: failed to encode results: \(error)\n".utf8))
      return 1
    }
  }
}

/// One module in the `scan-modules` output. Trimmed to what `expo-modules-autolinking` needs to
/// register a module: the Swift class name, the JS name it registers under, and the file it's in.
/// The richer fields the visitor captures (declaration kind, raw macro arguments, line/column) are
/// dropped here — they're redundant for this command (the macro is always `@ExpoModule` on a class)
/// and the deep `scan-exports` surface carries the richer per-member detail instead.
struct ScannedModule: Codable, Equatable {
  /// The Swift class name the module is declared as.
  let name: String

  /// The fully-resolved JS module name: the `@ExpoModule("Foo")` override when present, otherwise the
  /// class name. Resolved here (rather than left `nil`) so it matches how the macro derives the name
  /// and the consumer never has to apply the fallback itself.
  let jsName: String

  /// The class's spelled access modifier (`open`, `public`, `package`, `fileprivate`, `private`),
  /// or `internal` when none is written. The generated modules provider references the class from
  /// the app target, which requires `public`/`open`, so the consumer uses this to skip inaccessible
  /// classes with a diagnostic instead of emitting a provider that fails to compile.
  let accessLevel: String

  /// Source file the module was found in, relative to the path the scanner was invoked with.
  let file: String
}

/// Version of the `scan-modules` output shape. Bumped on any breaking change to the envelope or to
/// `ScannedModule`, so `expo-modules-autolinking` can verify it understands the output before
/// trusting it (and fall back to config-declared modules when it doesn't).
let scanModulesSchemaVersion = 1

/// The `scan-modules` result: the detected modules plus the stats describing the run. Encoded as the
/// command's JSON output. (`scan-exports` returns its own `ScanExportsResult` shape; the two commands
/// serve different consumers and don't share an envelope.)
struct ScanModulesResult: Codable, Equatable {
  let schemaVersion: Int
  let modules: [ScannedModule]

  /// Warnings for `#if` conditions the scan couldn't answer statically (see `ScanWarning`). Carried
  /// in the report rather than on stderr so the consumer can attach them to its own output.
  let warnings: [ScanWarning]

  let stats: ScanStats
}

/// Scans the given paths for top-level `@ExpoModule` types and returns the modules (in file then
/// source order) plus the stats for the run — the `scan-modules` command. Kept separate from the
/// public entry (and `internal`) so tests can drive it without going through argv/stdout.
func scanModules(paths: [String], configuration: ScanBuildConfiguration = .init(platform: nil, defines: [])) -> ScanModulesResult {
  let scan = collectDetections(paths: paths, macros: [.expoModule], configuration: configuration)

  let modules = scan.detections.map {
    // Resolve the JS name the way the macro does: explicit `@ExpoModule("Foo")` override, else the
    // class name.
    ScannedModule(name: $0.name, jsName: $0.jsName ?? $0.name, accessLevel: $0.accessLevel, file: $0.file)
  }

  return ScanModulesResult(
    schemaVersion: scanModulesSchemaVersion,
    modules: modules,
    warnings: scan.warnings,
    stats: scan.stats
  )
}
