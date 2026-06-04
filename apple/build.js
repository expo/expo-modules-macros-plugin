#!/usr/bin/env node

const { spawn } = require('node:child_process');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

/**
 * Runs a command and resolves when it exits successfully.
 */
function spawnAsync(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: 'inherit', ...options });
    child.once('error', reject);
    child.once('close', (code, signal) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`\`${command} ${args.join(' ')}\` exited with ${signal ?? `code ${code}`}`));
      }
    });
  });
}

/**
 * Builds the macro plugin for the given architecture and returns the path to the built binary.
 * SwiftPM always builds macro tools for the host architecture, so the x86_64 slice
 * is built by running the whole toolchain under Rosetta with `arch -x86_64`.
 */
async function buildForArch(arch) {
  const buildArgs = ['build', '-c', 'release'];
  if (arch === os.machine()) {
    await spawnAsync('swift', buildArgs, { cwd: __dirname });
  } else {
    await spawnAsync('arch', [`-${arch}`, 'swift', ...buildArgs], { cwd: __dirname });
  }

  const binPath = path.join(__dirname, `.build/${arch}-apple-macosx/release/ExpoModulesMacros-tool`);
  try {
    await fs.access(binPath);
  } catch {
    throw new Error(`Could not find the built ExpoModulesMacros-tool at ${binPath}`);
  }
  return binPath;
}

/**
 * Checks whether the toolchain can run for the given architecture,
 * e.g. x86_64 on Apple Silicon requires Rosetta to be installed.
 */
async function canBuildForArch(arch) {
  if (arch === os.machine()) {
    return true;
  }
  try {
    await spawnAsync('arch', [`-${arch}`, 'swift', '--version'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

async function main() {
  const outputPath = path.join(__dirname, 'ExpoModulesMacros-tool');

  const archs = [];
  for (const arch of ['arm64', 'x86_64']) {
    if (await canBuildForArch(arch)) {
      archs.push(arch);
    } else {
      console.warn(`The Swift toolchain cannot run for ${arch} - the built binary will not support ${arch} Macs.`);
    }
  }
  if (archs.length === 0) {
    throw new Error('The Swift toolchain is not available for any supported architecture');
  }

  // Builds run sequentially as SwiftPM locks the shared .build directory.
  const binPaths = [];
  for (const arch of archs) {
    binPaths.push(await buildForArch(arch));
  }

  await fs.rm(outputPath, { force: true });
  if (binPaths.length > 1) {
    await spawnAsync('lipo', ['-create', ...binPaths, '-output', outputPath]);
  } else {
    await fs.copyFile(binPaths[0], outputPath);
  }

  await spawnAsync('strip', [outputPath]);
  await spawnAsync('lipo', ['-info', outputPath]);
}

main().catch((error) => {
  console.error('Build failed:', error.message);
  process.exit(1);
});
