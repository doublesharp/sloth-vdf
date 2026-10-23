// The oracle uses Euler's criterion before extracting a root of +/- input.
// Keep it independent of the implementation's square-and-compare optimization.
export function pow(base: bigint, exponent: bigint, modulus: bigint): bigint {
  if (exponent === 0n) return 1n;
  const half = pow(base, exponent / 2n, modulus);
  const squared = (half * half) % modulus;
  return exponent % 2n ? (squared * base) % modulus : squared;
}

export function reference(seed: bigint, prime: bigint, rounds: bigint): bigint {
  const mask = (1n << BigInt(Math.floor(prime.toString(2).length / 2))) - 1n;
  let value = seed % prime;
  for (let i = 0n; i < rounds; ++i) {
    let mixed = value ^ mask;
    if (mixed === 0n || mixed >= prime) mixed = value;
    const residue = pow(mixed, (prime - 1n) / 2n, prime) === 1n;
    value = pow(residue ? mixed : prime - mixed, (prime + 1n) / 4n, prime);
    if ((value % 2n === 0n) !== residue) value = prime - value;
  }
  return value;
}
