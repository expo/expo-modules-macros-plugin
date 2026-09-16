/**
 * Hand-written mirrors of the scanner's JSON output. The Swift `Codable` types in
 * `apple/Sources/ExpoModulesScanner` are the source of truth; these are kept in sync by hand, which
 * is why each command carries a `schemaVersion` the wrapper checks at runtime.
 */

/** The JS `typeof` category a boundary type reports, mirroring `JSType`. */
export type JSType =
  | 'undefined'
  | 'object'
  | 'boolean'
  | 'number'
  | 'bigint'
  | 'string'
  | 'symbol'
  | 'function';

/**
 * A boundary type as a tagged tree, mirroring `TypeNode`. Discriminate on `kind`.
 *
 * `unknown` carries no `typeof`, and an `optional` reports its *wrapped* node's category, so
 * `(Int, String)?` (an optional around an unknown) has none either. Every other node always has one.
 * The absent (`undefined`) case is carried by the `optional` wrapper itself rather than by its
 * wrapped node.
 */
export type TypeNode =
  | { kind: 'primitive'; typeof: JSType; name: string }
  | { kind: 'optional'; typeof?: JSType; wrapped: TypeNode }
  | { kind: 'array'; typeof: JSType; element: TypeNode }
  | { kind: 'dictionary'; typeof: JSType; key: TypeNode; value: TypeNode }
  | { kind: 'promise'; typeof: JSType; value: TypeNode }
  | {
      kind: 'function';
      typeof: JSType;
      parameters: TypeNode[];
      /** Absent for a `Void` result. */
      returns?: TypeNode;
      async: boolean;
      throws: boolean;
    }
  /** Any other named type (record, shared object, enum, ...); `name` may be qualified. */
  | { kind: 'ref'; typeof: JSType; name: string }
  /** A type the scanner couldn't interpret; `text` is its source spelling. */
  | { kind: 'unknown'; text: string };

/** One parameter of a `@JS` function or `@JS init`. */
export interface ExportedParameter {
  /** The argument label, or `_` when unlabeled. */
  label: string;
  /** The internal parameter name. */
  name: string;
  type: TypeNode;
  /** True when the caller may omit it: a default value or an optional type. */
  optional: boolean;
}

/** One `@JS func` on a module or shared object. */
export interface ExportedFunction {
  name: string;
  /** The JS name it binds under: the `@JS("x")` override, else `name`. */
  jsName: string;
  parameters: ExportedParameter[];
  /** Absent for a `Void` return. */
  returns?: TypeNode;
  async: boolean;
  throws: boolean;
  static: boolean;
}

/** One `@JS var` on a module or shared object. */
export interface ExportedProperty {
  name: string;
  jsName: string;
  /** Absent when the type isn't determinable syntactically; the macro binds it getter-only. */
  type?: TypeNode;
  readonly: boolean;
  static: boolean;
}

/** One `@Record` property: a data slot, not a JS accessor. */
export interface ExportedRecordProperty {
  name: string;
  type: TypeNode;
  /** Optional-typed. */
  optional: boolean;
  /** Whether JS must supply it: neither defaulted nor optional. */
  required: boolean;
}

/** An `@ExpoModule` type and its `@JS` surface. */
export interface ExportedModule {
  name: string;
  /** The JS module name: `@ExpoModule("Foo")` override, else the class name. */
  jsName: string;
  functions: ExportedFunction[];
  properties: ExportedProperty[];
  /** Absolute source path. */
  file: string;
}

/** A `@SharedObject` type: a JS class with an optional constructor plus its `@JS` members. */
export interface ExportedSharedObject {
  name: string;
  jsName: string;
  /** The `@JS init` parameters, or absent when there's none. At most one constructor. */
  constructorParameters?: ExportedParameter[];
  functions: ExportedFunction[];
  properties: ExportedProperty[];
  file: string;
}

/** A `@Record` type and its properties. */
export interface ExportedRecord {
  name: string;
  properties: ExportedRecordProperty[];
  file: string;
}

/** The exported types grouped by kind. */
export interface ExportedSurface {
  modules: ExportedModule[];
  sharedObjects: ExportedSharedObject[];
  records: ExportedRecord[];
}

/** A `#if` condition the scan couldn't answer statically. */
export interface ScanWarning {
  message: string;
  file: string;
  line: number;
}

/** Counts describing how much work a scan did. */
export interface ScanStats {
  /** `.swift` files the walk found and read. */
  filesScanned: number;
  /** Of those, how many contained a macro attribute and so were parsed. */
  filesParsed: number;
  /** Wall-clock duration of the scan, in milliseconds. */
  durationMs: number;
}

/**
 * An Apple OS the scanner attributes modules to, spelled as `os(...)` spells it. The casing is part
 * of the output contract, so consumers with a lowercase convention must fold the case themselves.
 */
export type ScannedPlatform = 'iOS' | 'macOS' | 'tvOS' | 'watchOS' | 'visionOS';

/** One module in the `scan-modules` output. */
export interface ScannedModule {
  name: string;
  /** The resolved JS name: the `@ExpoModule("Foo")` override, else the class name. */
  jsName: string;
  /**
   * The spelled access level, or `internal` when none is written. The generated provider references
   * the class from the app target, so anything below `public` can't be registered.
   */
  accessLevel: string;
  /**
   * The OSes whose builds include this class, resolved from the enclosing `#if` conditions. An
   * unconditional module lists every OS. Empty means no build is known to include it, so don't
   * register it.
   */
  platforms: ScannedPlatform[];
  file: string;
}

/** The `scan-modules` result. */
export interface ScanModulesResult {
  schemaVersion: number;
  modules: ScannedModule[];
  warnings: ScanWarning[];
  stats: ScanStats;
}

/** The `scan-exports` result. */
export interface ScanExportsResult {
  schemaVersion: number;
  exports: ExportedSurface;
  stats: ScanStats;
}

/**
 * The output schema versions this package was written against. The wrapper compares these to the
 * `schemaVersion` in each report and throws on a mismatch, so a binary/wrapper version skew surfaces
 * as a clear error instead of silently misread fields.
 */
export const SUPPORTED_SCAN_MODULES_SCHEMA_VERSION = 2;
export const SUPPORTED_SCAN_EXPORTS_SCHEMA_VERSION = 1;
