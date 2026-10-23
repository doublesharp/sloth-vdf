const { randomBytes } = require('node:crypto');
const { performance } = require('node:perf_hooks');
const sloth = require('../dist').default;

const requested = process.argv[2] || '1000';
if (!/^[1-9][0-9]*$/.test(requested)) throw new Error('Usage: pnpm benchmark <positive iterations>');
const iterations = BigInt(requested);
const prime = (1n << 256n) - 189n;
const samples = [];
for (let i = 0; i < 6; ++i) {
  const seed = 1n + (BigInt(`0x${randomBytes(32).toString('hex')}`) % (prime - 1n));
  const start = performance.now();
  const proof = sloth.computeBeacon(seed, prime, iterations);
  const elapsed = performance.now() - start;
  if (!sloth.verifyBeacon(proof, seed, prime, iterations)) throw new Error('Verification failed');
  if (i > 0) samples.push(elapsed);
}
samples.sort((a, b) => a - b);
console.log(`Iterations: ${iterations}`);
console.log(`Compute time: min ${samples[0].toFixed(2)} ms, median ${samples[2].toFixed(2)} ms`);
console.log('Local JavaScript timings are not a lower bound for optimized or specialized solvers.');
console.log('Choose a safety margin and measure prove() gas on the target chain before deployment.');
