import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, symlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { build, env, linkOutput, reports, root } from './paths.mjs';

const [task, ...args] = process.argv.slice(2);
function run(command, parameters, cwd = root) {
  const result = spawnSync(command, parameters, { cwd, env, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} exited with ${result.status ?? result.signal}`);
}
function tsc(parameters) {
  run('pnpm', ['exec', 'tsc', ...parameters]);
}
function forge(parameters) {
  run('forge', parameters);
}
function compile() {
  forge(['build']);
}
function typegen() {
  linkOutput('sdk', join(build, 'generated'));
  if (!existsSync(join(build, 'node_modules')))
    symlinkSync(join(root, 'node_modules'), join(build, 'node_modules'), 'dir');
  run('pnpm', [
    'exec',
    'abi-typegen',
    'generate',
    '--config',
    'abi-typegen.toml',
    '--artifacts',
    env.FOUNDRY_OUT,
    '--out',
    join(root, 'sdk'),
    '--clean',
  ]);
}
function buildPackage() {
  compile();
  typegen();
  linkOutput('dist', join(build, 'dist'));
  tsc(['--project', 'tsconfig.json', '--outDir', join(build, 'dist')]);
  tsc([
    '--target',
    'es2020',
    '--module',
    'commonjs',
    '--moduleResolution',
    'node',
    '--esModuleInterop',
    '--strict',
    '--skipLibCheck',
    '--declaration',
    '--outDir',
    join(build, 'dist/contracts'),
    ...readdirSync(join(root, 'sdk'))
      .filter((file) => file.endsWith('.ts'))
      .map((file) => join(root, 'sdk', file)),
  ]);
}
function typescript(coverage = false) {
  run('pnpm', ['exec', 'vitest', 'run', '--configLoader', 'runner', ...(coverage ? ['--coverage'] : [])]);
}
function checkSolidityCoverage(file) {
  const entries = readFileSync(file, 'utf8')
    .split('end_of_record')
    .filter((record) => /SF:.*contracts\//.test(record));
  if (entries.length !== 2) throw new Error(`Expected coverage for both production files; found ${entries.length}.`);
  for (const record of entries) {
    for (const [found, hit] of [
      ['LF', 'LH'],
      ['FNF', 'FNH'],
      ['BRF', 'BRH'],
    ]) {
      const foundMetric = record.match(new RegExp(`^${found}:(\\d+)`, 'm'));
      const hitMetric = record.match(new RegExp(`^${hit}:(\\d+)`, 'm'));
      if (!foundMetric || !hitMetric) throw new Error(`Missing ${found}/${hit} coverage metrics.`);
      const total = Number(foundMetric[1]);
      const covered = Number(hitMetric[1]);
      if (covered !== total)
        throw new Error(`Incomplete ${found} coverage in ${record.match(/SF:(.*)/)?.[1]}: ${covered}/${total}`);
    }
  }
}

switch (task) {
  case 'compile':
    compile();
    break;
  case 'typegen':
    compile();
    typegen();
    break;
  case 'build':
    buildPackage();
    break;
  case 'typecheck':
    buildPackage();
    tsc(['--project', 'tsconfig.test.json']);
    break;
  case 'typescript':
    buildPackage();
    typescript();
    break;
  case 'solidity':
    forge(['test', ...args]);
    break;
  case 'fuzz':
    forge(['test', '--match-test', 'testFuzz', ...args]);
    break;
  case 'invariant':
    forge(['test', '--match-contract', 'RandomVDFInvariantTest', ...args]);
    break;
  case 'test':
    buildPackage();
    tsc(['--project', 'tsconfig.test.json']);
    typescript();
    forge(['test', ...args]);
    break;
  case 'coverage': {
    buildPackage();
    typescript(true);
    mkdirSync(join(reports, 'solidity'), { recursive: true });
    const file = join(reports, 'solidity/lcov.info');
    forge(['coverage', '--exclude-tests', '--report', 'lcov', '--report-file', file, ...args]);
    checkSolidityCoverage(file);
    console.log(`100% production Solidity line, function, and branch coverage. Reports: ${reports}`);
    break;
  }
  case 'benchmark':
    buildPackage();
    run('node', ['scripts/benchmark.cjs', ...args]);
    break;
  case 'pack': {
    buildPackage();
    const staging = join(build, 'package');
    mkdirSync(staging, { recursive: true });
    const manifest = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
    delete manifest.scripts;
    delete manifest.devDependencies;
    writeFileSync(join(staging, 'package.json'), `${JSON.stringify(manifest, null, 2)}\n`);
    cpSync(join(build, 'dist'), join(staging, 'dist'), { recursive: true });
    cpSync(join(root, 'contracts'), join(staging, 'contracts'), { recursive: true });
    cpSync(join(root, 'README.md'), join(staging, 'README.md'));
    cpSync(join(root, 'CHANGELOG.md'), join(staging, 'CHANGELOG.md'));
    cpSync(join(root, 'sloth.svg'), join(staging, 'sloth.svg'));
    run('pnpm', ['pack', '--pack-destination', join(build, 'packages')], staging);
    break;
  }
  default:
    throw new Error(`Unknown project task: ${task}`);
}
