import Foundation

/// Command-line front end for the scanner: parses the subcommand and paths, then delegates to the
/// matching `Scanner` entry (which runs the scan and writes its JSON output). Lives in the library
/// so the macro plugin executable can dispatch into it: the compiler always launches that executable
/// without arguments and speaks the plugin protocol over stdin, so any argument means a scanner
/// invocation. Each path may be a `.swift` file or a directory (scanned recursively for `.swift`
/// files).
///
/// Subcommands:
///   scan-modules   <path>...   fast: top-level `@ExpoModule` types, for autolinking
///   scan-exports   <path>...   deep: full JS-exported surface, for TS type generation
public enum ScannerCLI {
  /// Runs the CLI for the given arguments (argv without the executable path) and returns the
  /// process exit code: `0` on success, `1` if encoding the report fails, `2` on a usage error.
  public static func run(arguments: [String]) -> Int32 {
    // `-h`/`--help` anywhere is treated as a help request: print usage to stdout and exit 0.
    if arguments.contains(where: { $0 == "-h" || $0 == "--help" }) {
      printUsage(to: .standardOutput)
      return 0
    }

    guard let subcommand = arguments.first else {
      printUsage()
      return 2
    }
    let paths = Array(arguments.dropFirst())

    switch subcommand {
    case "scan-modules":
      guard !paths.isEmpty else {
        return usageError("scan-modules requires at least one path")
      }
      return Scanner.runModules(paths: paths)

    case "scan-exports":
      guard !paths.isEmpty else {
        return usageError("scan-exports requires at least one path")
      }
      return Scanner.runExports(paths: paths)

    default:
      return usageError("unknown subcommand '\(subcommand)'")
    }
  }
}

/// The invoked executable's basename, so the usage text matches however the tool was launched
/// (the `ExpoModulesMacros-tool` shipped in the package, or a locally built copy).
private var toolName: String {
  return (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "ExpoModulesScanner"
}

private var usageText: String {
  """
  usage: \(toolName) <subcommand> <path> [<path> ...]

  subcommands:
    scan-modules   fast scan for top-level @ExpoModule types (autolinking)
    scan-exports   deep scan of the full JS-exported surface (type generation)

  options:
    -h, --help     print this help and exit

  """
}

/// Prints the usage text to the given handle. Goes to stdout when help was explicitly requested
/// (a successful action), stderr when it accompanies a usage error.
private func printUsage(to handle: FileHandle = .standardError) {
  handle.write(Data(usageText.utf8))
}

/// Reports a usage error on stderr, followed by the usage text, and returns the usage exit code.
private func usageError(_ message: String) -> Int32 {
  FileHandle.standardError.write(Data("error: \(message)\n".utf8))
  printUsage()
  return 2
}
