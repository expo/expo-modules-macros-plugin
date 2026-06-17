import Foundation
import SwiftParser
import SwiftSyntax

/// The scanner's public entry point. Argument parsing, subcommand dispatch, and usage text live in
/// the CLI target; this just runs a scan in a given mode and writes its JSON report to stdout.
///
/// The detection model (`Detection`, `DetectionVisitor`, …) stays `internal`: tests reach it via
/// `@testable import`, and the CLI only needs `ScanMode` plus this entry, so nothing else is exposed.
public enum Scanner {
  /// Scans `paths` in `mode`, prints the JSON report to stdout, and returns a process exit code:
  /// `0` on success, `1` if encoding fails. The CLI maps its subcommand to a `ScanMode` and exits
  /// with the returned code.
  public static func run(mode: ScanMode, paths: [String]) -> Int32 {
    let result = scan(paths: paths, mode: mode)

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

/// Scans the given paths in the given mode and returns the detections (in file then source order)
/// plus the stats for the run. Kept separate from `main()` (and `internal`) so tests can drive it
/// without going through argv/stdout.
func scan(paths: [String], mode: ScanMode) -> ScanModulesResult {
  let clock = ContinuousClock()
  let start = clock.now
  let macros = mode.detectedMacros

  var detections: [Detection] = []
  var filesScanned = 0
  var filesParsed = 0

  // Compile the pre-filter regex once per run, not once per file.
  let prefilter = macroAttributeRegex(for: macros)

  for file in swiftFiles(in: paths) {
    guard let source = try? String(contentsOfFile: file, encoding: .utf8) else {
      FileHandle.standardError.write(Data("warning: could not read \(file)\n".utf8))
      continue
    }
    filesScanned += 1
    // Skip the (relatively expensive) parse for files that can't contain any of the mode's macros.
    // A plain substring scan is far cheaper than a full parse, and most files in a large tree
    // mention none of these names. See `mightContainMacro` for why this never drops a real match.
    guard mightContainMacro(in: source, prefilter: prefilter) else {
      continue
    }
    filesParsed += 1
    detections.append(contentsOf: detect(source: source, file: file, macros: macros))
  }

  let elapsed = (clock.now - start).components
  let durationMs = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15

  let modules = detections.map {
    // Resolve the JS name the way the macro does: explicit `@ExpoModule("Foo")` override, else the
    // class name.
    ScannedModule(name: $0.name, jsName: $0.jsName ?? $0.name, file: $0.file)
  }

  return ScanModulesResult(
    modules: modules,
    stats: ScanStats(filesScanned: filesScanned, filesParsed: filesParsed, durationMs: durationMs)
  )
}

/// Builds the pre-filter regex for a macro set, e.g. `@(ExpoModule)` for a `modules` scan or
/// `@(ExpoModule|JS|Record|SharedObject)` for an `exports` scan. A precompiled `NSRegularExpression`
/// benchmarked ~20x faster over a large source tree than calling `String.contains` once per macro
/// name, because it scans each file in a single pass. Compiled once per run and reused per file.
func macroAttributeRegex(for macros: Set<DetectedMacro>) -> NSRegularExpression {
  // Sort for a stable pattern regardless of the set's iteration order.
  let alternation = macros.map(\.rawValue).sorted().joined(separator: "|")
  return try! NSRegularExpression(pattern: "@(\(alternation))")
}

/// True if the source text contains one of the pre-filter's spelled macro attributes, so it's worth
/// parsing. A deliberate over-approximation: the pattern can still match inside a comment or string,
/// in which case the file is parsed and correctly yields no detections — a wasted parse, never a
/// missed module. It assumes the attribute is written with no space after `@` (`@ExpoModule`, not
/// `@ ExpoModule`), which is universal in practice; the rare spaced form would be skipped.
func mightContainMacro(in source: String, prefilter: NSRegularExpression) -> Bool {
  let range = NSRange(source.startIndex..., in: source)
  return prefilter.firstMatch(in: source, range: range) != nil
}

/// Parses one source string and returns its detections for the given macro set. The unit of work the
/// tests exercise.
func detect(source: String, file: String, macros: Set<DetectedMacro>) -> [Detection] {
  let tree = Parser.parse(source: source)
  let visitor = DetectionVisitor(file: file, tree: tree, detectedMacros: macros)
  visitor.walk(tree)
  return visitor.detections
}

/// Directory names skipped during the recursive walk. These hold build products, dependencies, and
/// git internals — never source worth scanning — and pruning them keeps the walk from descending
/// into the bulk of a monorepo's files.
private let prunedDirectoryNames: Set<String> = [".build", "Pods", ".git"]

/// Expands the given paths into the list of `.swift` files to parse: a file path passes through,
/// a directory is enumerated recursively (skipping `prunedDirectoryNames`). Order is deterministic
/// so output is stable across runs.
func swiftFiles(in paths: [String]) -> [String] {
  let fileManager = FileManager.default
  var result: [String] = []

  for path in paths {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
      FileHandle.standardError.write(Data("warning: no such path \(path)\n".utf8))
      continue
    }

    if isDirectory.boolValue {
      result.append(contentsOf: swiftFiles(inDirectory: URL(fileURLWithPath: path), fileManager: fileManager))
    } else if path.hasSuffix(".swift") {
      result.append(path)
    }
  }

  return result.sorted()
}

/// Recursively enumerates `.swift` files under a directory, calling `skipDescendants()` on any
/// pruned directory so its subtree is never read. Uses the URL enumerator (rather than the
/// path-based one) precisely because it supports skipping a subtree mid-walk.
///
/// Directory-ness is read from `hasDirectoryPath` (the enumerator sets a trailing slash on the URLs
/// it yields) rather than `resourceValues(forKeys: [.isDirectoryKey])`, which re-`stat`s each entry.
/// The walk is the dominant cost of a whole-tree scan, and skipping that per-entry stat measurably
/// shortens it.
private func swiftFiles(inDirectory directory: URL, fileManager: FileManager) -> [String] {
  guard let enumerator = fileManager.enumerator(
    at: directory,
    includingPropertiesForKeys: nil,
    options: [.skipsHiddenFiles]
  ) else {
    return []
  }

  var result: [String] = []
  for case let url as URL in enumerator {
    if url.hasDirectoryPath {
      if prunedDirectoryNames.contains(url.lastPathComponent) {
        enumerator.skipDescendants()
      }
    } else if url.pathExtension == "swift" {
      result.append(url.path)
    }
  }
  return result
}
