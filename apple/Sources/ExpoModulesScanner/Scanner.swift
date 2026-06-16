import Foundation
import SwiftParser
import SwiftSyntax

/// The scanner's command-line entry point. Lives in the library (rather than the executable's
/// top-level code) so the parsing/detection logic stays `@testable`-importable; the executable
/// target is a one-line call to `Scanner.main()`.
///
/// The detection model (`Detection`, `DetectionVisitor`, …) stays `internal`: tests reach it via
/// `@testable import`, and the CLI only needs this one public entry, so nothing else is exposed.
public enum Scanner {
  /// Reads paths from the process arguments, scans them, prints the JSON report to stdout, and
  /// exits non-zero on a usage error. Each path may be a `.swift` file or a directory (scanned
  /// recursively for `.swift` files).
  public static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())

    guard !arguments.isEmpty else {
      FileHandle.standardError.write(Data("usage: \(toolName) <path> [<path> ...]\n".utf8))
      exit(2)
    }

    let result = scan(paths: arguments)

    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(result)
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
      FileHandle.standardError.write(Data("error: failed to encode results: \(error)\n".utf8))
      exit(1)
    }
  }
}

private let toolName = "ExpoModulesScanner"

/// Scans the given paths and returns the detections (in file then source order) plus the stats for
/// the run. Kept separate from `main()` (and `internal`) so tests can drive it without going through
/// argv/stdout.
func scan(paths: [String]) -> ScanResult {
  let clock = ContinuousClock()
  let start = clock.now

  var detections: [Detection] = []
  var filesScanned = 0
  var filesParsed = 0

  for file in swiftFiles(in: paths) {
    guard let source = try? String(contentsOfFile: file, encoding: .utf8) else {
      FileHandle.standardError.write(Data("warning: could not read \(file)\n".utf8))
      continue
    }
    filesScanned += 1
    // Skip the (relatively expensive) parse for files that can't contain any recognized macro.
    // A plain substring scan is far cheaper than a full parse, and most files in a large tree
    // mention none of these names. See `mightContainMacro` for why this never drops a real match.
    guard mightContainMacro(in: source) else {
      continue
    }
    filesParsed += 1
    detections.append(contentsOf: detect(source: source, file: file))
  }

  let elapsed = (clock.now - start).components
  let durationMs = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15

  return ScanResult(
    detections: detections,
    stats: ScanStats(filesScanned: filesScanned, filesParsed: filesParsed, durationMs: durationMs)
  )
}

/// Matches a spelled macro attribute, e.g. `@ExpoModule`. Including the `@` keeps the check specific:
/// `@JS` won't collide with common substrings like `JSON` the way a bare `JS` would. Compiled once
/// and reused — a precompiled `NSRegularExpression` benchmarked ~20x faster over a large source tree
/// than calling `String.contains` once per macro name, because it scans each file in a single pass.
private let macroAttributeRegex: NSRegularExpression = {
  let alternation = DetectedMacro.allCases.map(\.rawValue).joined(separator: "|")
  return try! NSRegularExpression(pattern: "@(\(alternation))")
}()

/// True if the source text contains a spelled macro attribute, so it's worth parsing. A deliberate
/// over-approximation: the pattern can still match inside a comment or string, in which case the
/// file is parsed and correctly yields no detections — a wasted parse, never a missed module. It
/// assumes the attribute is written with no space after `@` (`@ExpoModule`, not `@ ExpoModule`),
/// which is universal in practice; the rare spaced form would be skipped.
func mightContainMacro(in source: String) -> Bool {
  let range = NSRange(source.startIndex..., in: source)
  return macroAttributeRegex.firstMatch(in: source, range: range) != nil
}

/// Parses one source string and returns its detections. The unit of work the tests exercise.
func detect(source: String, file: String) -> [Detection] {
  let tree = Parser.parse(source: source)
  let visitor = DetectionVisitor(file: file, tree: tree)
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
