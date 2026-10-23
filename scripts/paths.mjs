import { createHash } from 'node:crypto';
import { existsSync, lstatSync, mkdirSync, realpathSync, symlinkSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
if (!existsSync('/Volumes/Scratch')) throw new Error('Mount /Volumes/Scratch before running project tools.');
const checkout = `${basename(root)}-${createHash('sha256').update(realpathSync(root)).digest('hex').slice(0, 8)}`;
export const build = join('/Volumes/Scratch/sloth-vdf/build', checkout);
export const reports = join('/Volumes/Scratch/sloth-vdf/reports', checkout);
for (const dir of [build, reports, join(build, 'tmp')]) mkdirSync(dir, { recursive: true });

export function linkOutput(name, target) {
  mkdirSync(target, { recursive: true });
  const link = join(root, name);
  try {
    const stat = lstatSync(link);
    if (!stat.isSymbolicLink() || realpathSync(link) !== realpathSync(target)) {
      throw new Error(`Refusing to replace existing ${link}; move it aside before building.`);
    }
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    symlinkSync(target, link, 'dir');
  }
}

export const env = {
  ...process.env,
  TMPDIR: join(build, 'tmp'),
  FOUNDRY_OUT: join(build, 'out'),
  FOUNDRY_CACHE_PATH: join(build, 'cache'),
  FOUNDRY_TEST_FAILURES_FILE: join(build, 'cache/test-failures'),
  FOUNDRY_FUZZ_FAILURE_PERSIST_DIR: join(build, 'cache/fuzz'),
  FOUNDRY_INVARIANT_FAILURE_PERSIST_DIR: join(build, 'cache/invariant'),
  SLOTH_BUILD_DIR: build,
  SLOTH_VITE_CACHE_DIR: join(build, 'vite'),
  SLOTH_MODULE_CACHE_DIR: join(build, 'vitest-cache'),
  SLOTH_COVERAGE_DIR: join(reports, 'typescript'),
};
