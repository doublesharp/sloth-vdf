const modulusExponent = (base: bigint, exponent: bigint, modulus: bigint) => {
  let result = 1n;
  for (; exponent > 0n; exponent >>= 1n) {
    if (exponent & 1n) {
      result = (result * base) % modulus;
    }
    base = (base * base) % modulus;
  }
  return result;
};

const sloth = {
  computeBeacon(seed: bigint, prime: bigint, iterations: bigint) {
    const exponent = (prime + 1n) >> 2n;
    let beacon = seed % prime;
    for (let i = 0n; i < iterations; ++i) {
      beacon = modulusExponent(beacon, exponent, prime);
    }
    return beacon;
  },
  verifyBeacon(beacon: bigint, seed: bigint, prime: bigint, iterations: bigint) {
    for (let i = 0n; i < iterations; ++i) {
      beacon = (beacon * beacon) % prime;
    }
    seed %= prime;
    if (seed == beacon) return true;
    if (prime - seed === beacon) return true;
    return false;
  },
};

export default sloth;
