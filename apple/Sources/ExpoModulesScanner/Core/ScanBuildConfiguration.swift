import SwiftIfConfig
import SwiftSyntax

/// The build configuration that `#if` conditions are evaluated against during a scan, built from
/// the CLI's `--platform` and `--define` options. The scan is static: it knows the target OS and
/// the spelled compilation flags, and nothing else. Every condition it cannot answer throws, which
/// SwiftIfConfig turns into an inactive region plus a diagnostic, so an unanswerable `#if` skips
/// its declarations and surfaces a warning instead of guessing.
struct ScanBuildConfiguration: BuildConfiguration {
  /// The target OS name to answer `os(...)` with, as spelled in the condition (`iOS`, `macOS`,
  /// `tvOS`, `watchOS`, `visionOS`; compared case-insensitively), or `nil` when no `--platform`
  /// was given, in which case `os(...)` conditions are unanswerable.
  let platform: String?

  /// The conditional compilation flags treated as set, from repeated `--define` options.
  let defines: Set<String>

  func isCustomConditionSet(name: String) throws -> Bool {
    return defines.contains(name)
  }

  func isActiveTargetOS(name: String) throws -> Bool {
    guard let platform else {
      throw ScanConfigurationError("cannot evaluate 'os(\(name))': no --platform was given")
    }
    return name.lowercased() == platform.lowercased()
  }

  // MARK: - Unanswerable conditions

  // These vary within a single platform's build (device vs simulator, arm64 vs x86_64) or depend
  // on the consumer's toolchain, so a static scan has no correct answer. Throwing makes the region
  // inactive and emits a warning naming the condition.

  func hasFeature(name: String) throws -> Bool {
    throw ScanConfigurationError("cannot evaluate 'hasFeature(\(name))' in a static scan")
  }

  func hasAttribute(name: String) throws -> Bool {
    throw ScanConfigurationError("cannot evaluate 'hasAttribute(\(name))' in a static scan")
  }

  func canImport(importPath: [(TokenSyntax, String)], version: CanImportVersion) throws -> Bool {
    let module = importPath.map(\.1).joined(separator: ".")
    throw ScanConfigurationError("cannot evaluate 'canImport(\(module))' in a static scan")
  }

  func isActiveTargetArchitecture(name: String) throws -> Bool {
    throw ScanConfigurationError("cannot evaluate 'arch(\(name))' in a static scan")
  }

  func isActiveTargetEnvironment(name: String) throws -> Bool {
    throw ScanConfigurationError("cannot evaluate 'targetEnvironment(\(name))' in a static scan")
  }

  func isActiveTargetRuntime(name: String) throws -> Bool {
    throw ScanConfigurationError("cannot evaluate '_runtime(\(name))' in a static scan")
  }

  func isActiveTargetPointerAuthentication(name: String) throws -> Bool {
    throw ScanConfigurationError("cannot evaluate '_ptrauth(\(name))' in a static scan")
  }

  // MARK: - Fixed answers

  // Non-throwing protocol requirements, so they need a value. These are constant across Apple
  // targets (the only ones Expo modules compile for), except the versions, which assume a current
  // toolchain; a module class gated on a *lower* Swift version would be wrongly included, which is
  // rare enough to accept for a scan.

  var targetPointerBitWidth: Int { 64 }
  var targetAtomicBitWidths: [Int] { [32, 64, 128] }
  var endianness: Endianness { .little }
  var languageVersion: VersionTuple { VersionTuple(6) }
  var compilerVersion: VersionTuple { VersionTuple(6, 2) }
}

/// An unanswerable `#if` condition. SwiftIfConfig converts the thrown error into a diagnostic on
/// the condition's node and treats the region as inactive.
struct ScanConfigurationError: Error, CustomStringConvertible {
  let description: String

  init(_ description: String) {
    self.description = description
  }
}
