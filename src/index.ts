import { execFile } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

import {
  ScanExportsResult,
  ScanModulesResult,
  SUPPORTED_SCAN_EXPORTS_SCHEMA_VERSION,
  SUPPORTED_SCAN_MODULES_SCHEMA_VERSION,
} from './types';

export * from './types';

/** Options accepted by `scanModules`, mirroring the CLI's `scan-modules` flags. */
export interface ScanModulesOptions {
  /**
   * Evaluate `#if os(...)` against this platform (`iOS`, `macOS`, `tvOS`, ...). Without it,
   * os-conditional declarations are skipped and reported in the result's `warnings`.
   */
  platform?: string;

  /** Conditional compilation flags to treat as set, e.g. `['DEBUG']`. */
  defines?: string[];

  /** Overrides the scanner binary path. Defaults to the one shipped with this package. */
  binaryPath?: string;
}

/** Options accepted by `scanExports`. The deep scan doesn't evaluate `#if`, so it takes no flags. */
export interface ScanExportsOptions {
  /** Overrides the scanner binary path. Defaults to the one shipped with this package. */
  binaryPath?: string;
}

/**
 * Thrown when the scanner exits non-zero. Exit code 2 is a usage error (bad subcommand or flags) and
 * 1 means the report couldn't be encoded; both put a message on stderr, carried here as `stderr`.
 */
export class ScannerError extends Error {
  constructor(
    message: string,
    readonly exitCode: number | null,
    readonly stderr: string
  ) {
    super(message);
    this.name = 'ScannerError';
  }
}

/** Thrown when the binary's output schema doesn't match what these types were written against. */
export class ScannerSchemaVersionError extends Error {
  constructor(
    readonly command: string,
    readonly found: number,
    readonly expected: number
  ) {
    super(
      `\`${command}\` returned schema version ${found}, but this package understands ${expected}. ` +
        'The scanner binary and this wrapper are out of sync; align their versions.'
    );
    this.name = 'ScannerSchemaVersionError';
  }
}

/**
 * Absolute path to the scanner binary shipped with this package. It doubles as the macro plugin
 * executable, so it lives next to the Swift package rather than in a `bin` directory.
 */
export function getScannerBinaryPath(): string {
  return path.join(__dirname, '..', 'apple', 'ExpoModulesMacros-tool');
}

/**
 * Runs a scanner subcommand and parses its JSON report.
 *
 * The scan is CPU-bound in Swift and can emit a large report, so stdout is buffered with a raised
 * `maxBuffer` rather than streamed: the report is only usable once complete anyway.
 */
function runScanner<T>(binaryPath: string, args: string[]): Promise<T> {
  return new Promise((resolve, reject) => {
    if (!fs.existsSync(binaryPath)) {
      reject(
        new ScannerError(
          `The scanner binary is missing at ${binaryPath}. Run \`npm run build\` in this package to build it.`,
          null,
          ''
        )
      );
      return;
    }

    execFile(
      binaryPath,
      args,
      { maxBuffer: 256 * 1024 * 1024, encoding: 'utf8' },
      (error, stdout, stderr) => {
        if (error) {
          const exitCode = typeof error.code === 'number' ? error.code : null;
          reject(
            new ScannerError(
              `\`${path.basename(binaryPath)} ${args.join(' ')}\` failed: ${stderr.trim() || error.message}`,
              exitCode,
              stderr
            )
          );
          return;
        }

        try {
          resolve(JSON.parse(stdout) as T);
        } catch (parseError) {
          reject(
            new ScannerError(
              `Could not parse the scanner's JSON output: ${(parseError as Error).message}`,
              0,
              stderr
            )
          );
        }
      }
    );
  });
}

/**
 * Fast scan for top-level `@ExpoModule` types, for autolinking. Each path is a `.swift` file or a
 * directory, scanned recursively.
 *
 * Conditions the scan can't answer statically come back in `warnings` rather than throwing, so the
 * caller can surface them alongside its own diagnostics.
 */
export async function scanModules(
  paths: string[],
  options: ScanModulesOptions = {}
): Promise<ScanModulesResult> {
  if (paths.length === 0) {
    throw new TypeError('scanModules requires at least one path');
  }

  const args = ['scan-modules'];
  if (options.platform) {
    args.push('--platform', options.platform);
  }
  for (const define of options.defines ?? []) {
    args.push('--define', define);
  }
  args.push(...paths);

  const result = await runScanner<ScanModulesResult>(
    options.binaryPath ?? getScannerBinaryPath(),
    args
  );

  if (result.schemaVersion !== SUPPORTED_SCAN_MODULES_SCHEMA_VERSION) {
    throw new ScannerSchemaVersionError(
      'scan-modules',
      result.schemaVersion,
      SUPPORTED_SCAN_MODULES_SCHEMA_VERSION
    );
  }
  return result;
}

/**
 * Deep scan of the full JS-exported surface, for TypeScript type generation. Each path is a `.swift`
 * file or a directory, scanned recursively.
 *
 * Unlike `scanModules`, this doesn't evaluate `#if` blocks, so it takes no platform or define
 * options: conditional declarations are reported as if their conditions held.
 */
export async function scanExports(
  paths: string[],
  options: ScanExportsOptions = {}
): Promise<ScanExportsResult> {
  if (paths.length === 0) {
    throw new TypeError('scanExports requires at least one path');
  }

  const result = await runScanner<ScanExportsResult>(options.binaryPath ?? getScannerBinaryPath(), [
    'scan-exports',
    ...paths,
  ]);

  if (result.schemaVersion !== SUPPORTED_SCAN_EXPORTS_SCHEMA_VERSION) {
    throw new ScannerSchemaVersionError(
      'scan-exports',
      result.schemaVersion,
      SUPPORTED_SCAN_EXPORTS_SCHEMA_VERSION
    );
  }
  return result;
}
