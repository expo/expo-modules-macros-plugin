import Foundation
import SwiftParser
import SwiftSyntax

extension Scanner {
  /// Runs `scan-exports` over `paths`, prints the JSON report to stdout, and returns the exit code
  /// (`0` on success, `1` if encoding fails). The deep counterpart to `runModules`.
  public static func runExports(paths: [String]) -> Int32 {
    let result = scanExports(paths: paths)

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

/// Scans `paths` for `@ExpoModule`, `@SharedObject`, and `@Record` types plus `Enumerable` enums, and
/// returns their exported surface plus the run's stats. Separate from the public entry so tests can
/// drive it without argv/stdout. The shared `scanFiles` walk + pre-filter selects files; a
/// `SurfaceVisitor` extracts each one.
///
/// The pre-filter omits `@Event`: an event only declares a member of one of these three types, so a
/// file containing one already matches on its enclosing type. It does include `Enumerable`, which is a
/// conformance rather than an attribute: an enum is commonly declared in a file of its own, which no
/// macro attribute would match.
func scanExports(paths: [String]) -> ScanExportsResult {
  var modules: [ExportedModule] = []
  var sharedObjects: [ExportedSharedObject] = []
  var records: [ExportedRecord] = []
  var enums: [ExportedEnum] = []

  let stats = scanFiles(
    paths: paths,
    macros: [.expoModule, .sharedObject, .record],
    conformances: [enumerableConformanceName]
  ) { source, file in
    let tree = Parser.parse(source: source)
    let visitor = SurfaceVisitor(file: file)
    visitor.walk(tree)
    modules.append(contentsOf: visitor.modules)
    sharedObjects.append(contentsOf: visitor.sharedObjects)
    records.append(contentsOf: visitor.records)
    enums.append(contentsOf: visitor.enums)
  }

  return ScanExportsResult(
    schemaVersion: scanExportsSchemaVersion,
    exports: ExportedSurface(
      modules: modules, sharedObjects: sharedObjects, records: records, enums: enums),
    stats: stats
  )
}
