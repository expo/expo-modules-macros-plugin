@testable import ExpoModulesScanner
import Testing

/// Covers the CLI's argument handling and exit codes. The scans it dispatches to are covered by
/// `ScanModulesTests` and the visitor suites; success paths print JSON to stdout, so only the
/// non-printing paths are asserted here.
@Suite("Scanner CLI")
struct ScannerCLITests {
  @Test
  func `No arguments is a usage error`() {
    #expect(ScannerCLI.run(arguments: []) == 2)
  }

  @Test(arguments: [["-h"], ["--help"], ["scan-modules", "--help"]])
  func `Help requests exit successfully`(arguments: [String]) {
    #expect(ScannerCLI.run(arguments: arguments) == 0)
  }

  @Test(arguments: [["scan-modules"], ["scan-exports"]])
  func `A subcommand without paths is a usage error`(arguments: [String]) {
    #expect(ScannerCLI.run(arguments: arguments) == 2)
  }

  @Test
  func `An unknown subcommand is a usage error`() {
    #expect(ScannerCLI.run(arguments: ["scan-everything", "/tmp"]) == 2)
  }

  @Test(arguments: [["scan-modules", "--platform"], ["scan-modules", "/tmp", "--define"]])
  func `An option without its value is a usage error`(arguments: [String]) {
    #expect(ScannerCLI.run(arguments: arguments) == 2)
  }

  @Test
  func `scan-modules rejects --platform`() {
    #expect(ScannerCLI.run(arguments: ["scan-modules", "--platform", "iOS", "/tmp"]) == 2)
  }

  @Test
  func `scan-exports rejects the scan-modules options`() {
    #expect(ScannerCLI.run(arguments: ["scan-exports", "--platform", "iOS", "/tmp"]) == 2)
    #expect(ScannerCLI.run(arguments: ["scan-exports", "--define", "DEBUG", "/tmp"]) == 2)
  }
}
