import { describe, expect, it } from 'vitest';
import fc from 'fast-check';
import sloth from '../../src';
import { reference } from './reference';

const PRIME = (1n << 256n) - 189n;
const LIMIT = 1n << 256n;

describe('Sloth evaluation and verification', () => {
  it('matches the independent definition over complete small fields', () => {
    for (const prime of [7n, 11n, 19n, 23n, 31n, 43n, 59n, 67n, 71n, 79n, 83n, 103n, 107n, 127n, 131n, 139n]) {
      for (let seed = 1n; seed < prime; ++seed) {
        for (let rounds = 1n; rounds <= 5n; ++rounds) {
          const proof = sloth.computeBeacon(seed, prime, rounds);
          expect(proof).toBe(reference(seed, prime, rounds));
          expect(sloth.verifyBeacon(proof, seed, prime, rounds)).toBe(true);
        }
      }
    }
  });

  it('accepts exactly one output for each seed', () => {
    for (const prime of [7n, 11n, 19n, 23n, 31n, 43n]) {
      for (let seed = 1n; seed < prime; ++seed) {
        const expected = reference(seed, prime, 3n);
        for (let proof = 1n; proof < prime; ++proof) {
          expect(sloth.verifyBeacon(proof, seed, prime, 3n)).toBe(proof === expected);
        }
      }
    }
  });

  it.each([0n, 1n, 2n, 3n, 4n, 5n, 8n, 9n, 13n, LIMIT + 3n])('rejects invalid modulus %s', (prime) => {
    expect(() => sloth.computeBeacon(1n, prime, 1n)).toThrow(RangeError);
    expect(sloth.verifyBeacon(1n, 1n, prime, 1n)).toBe(false);
  });

  it.each([-1n, 0n, LIMIT])('rejects invalid iteration count %s', (rounds) => {
    expect(() => sloth.computeBeacon(1n, PRIME, rounds)).toThrow(RangeError);
    expect(sloth.verifyBeacon(1n, 1n, PRIME, rounds)).toBe(false);
  });

  it.each([-1n, 0n, PRIME, LIMIT])('rejects invalid seed %s', (seed) => {
    expect(() => sloth.computeBeacon(seed, PRIME, 1n)).toThrow(RangeError);
    expect(sloth.verifyBeacon(1n, seed, PRIME, 1n)).toBe(false);
  });

  it.each([-1n, 0n, PRIME, PRIME + 1n, LIMIT])('rejects noncanonical proof %s', (proof) => {
    expect(sloth.verifyBeacon(proof, 2n, PRIME, 1n)).toBe(false);
  });

  it('handles maximal uint256 seeds and reduces inputs modulo the prime', () => {
    for (const seed of [1n, 2n, (1n << 128n) - 1n, 1n << 128n, PRIME - 1n, LIMIT - 1n]) {
      const proof = sloth.computeBeacon(seed, PRIME, 5n);
      expect(proof).toBe(reference(seed, PRIME, 5n));
      expect(sloth.verifyBeacon(proof, seed, PRIME, 5n)).toBe(true);
    }
    expect(sloth.computeBeacon(13n, 11n, 4n)).toBe(sloth.computeBeacon(2n, 11n, 4n));
  });

  it('matches the independent oracle for randomized 256-bit seeds and round counts', () => {
    fc.assert(
      fc.property(fc.bigInt({ min: 1n, max: PRIME - 1n }), fc.bigInt({ min: 1n, max: 32n }), (seed, rounds) => {
        const proof = sloth.computeBeacon(seed, PRIME, rounds);
        expect(proof).toBe(reference(seed, PRIME, rounds));
        expect(sloth.verifyBeacon(proof, seed, PRIME, rounds)).toBe(true);
        expect(sloth.verifyBeacon(PRIME - proof, seed, PRIME, rounds)).toBe(false);
        const wrong = proof === PRIME - 1n ? 1n : proof + 1n;
        expect(sloth.verifyBeacon(wrong, seed, PRIME, rounds)).toBe(false);
      }),
      { numRuns: 256, seed: 0x5107 }
    );
  });
});
