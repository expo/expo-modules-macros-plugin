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
  events: ExportedEvent[];
  /** Absolute source path. */
  file: string;
}

/** One `@Event var`: a typed event JS listens for by name, rather than calls. */
export interface ExportedEvent {
  /** The Swift property name, e.g. `onStatusChange`. */
  name: string;
  /**
   * The name JS listens under: the `@Event("x")` override, else `name` with a conventional `on`
   * prefix stripped and decapitalized (`onStatusChange` -> `statusChange`).
   */
  jsName: string;
  /** The payload type, absent for a no-payload `() -> Void` event. */
  payload?: TypeNode;
  /** `@Event(sync: true)`, dispatching inline on the JS thread instead of scheduling. */
  sync: boolean;
}

/** A `@SharedObject` type: a JS class with an optional constructor plus its `@JS` members. */
export interface ExportedSharedObject {
  name: string;
  jsName: string;
  /** The `@JS init` parameters, or absent when there's none. At most one constructor. */
  constructorParameters?: ExportedParameter[];
  functions: ExportedFunction[];
  properties: ExportedProperty[];
  events: ExportedEvent[];
  file: string;
}

/** A `@Record` type and its properties. */
export interface ExportedRecord {
  name: string;
  properties: ExportedRecordProperty[];
  file: string;
}

/**
 * One case of a reported enum.
 *
 * What `rawValue` carries depends on the enum's raw type:
 * - `String`: always present. A case writing none takes its own name, so nothing is left to derive.
 * - an integer type: present only where written. Swift continues from the preceding case's value
 *   (`case a = 1; case b` makes `b` 2), and that carry is yours to apply.
 * - no raw type: always absent, since the enum has no raw values.
 */
export interface ExportedEnumCase {
  /** The case name as declared. */
  name: string;
  /** The raw value as source text, quotes included (`"active"`, `3`), or absent per the rule above. */
  rawValue?: string;
}

/**
 * An `Enumerable` enum: a type crossing the boundary as its raw value rather than as an object.
 * Detected by conformance, not by a macro attribute, so it carries no `jsName`.
 */
export interface ExportedEnum {
  name: string;
  /** The raw value type as written, absent for a bare `Enumerable` conformance with no raw type. */
  rawType?: TypeNode;
  cases: ExportedEnumCase[];
  file: string;
}

/** The exported types grouped by kind. */
export interface ExportedSurface {
  modules: ExportedModule[];
  sharedObjects: ExportedSharedObject[];
  records: ExportedRecord[];
  enums: ExportedEnum[];
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
  /** Of those, how many matched the pre-filter (a macro attribute or a scanned conformance). */
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
export const SUPPORTED_SCAN_EXPORTS_SCHEMA_VERSION = 3;
