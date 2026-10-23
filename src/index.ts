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

// The modulus must be a trusted prime. These checks do not establish primality.
const validParameters = (prime: bigint, iterations: bigint) =>
  prime > 3n && prime < 1n << 256n && prime % 4n === 3n && iterations > 0n && iterations < 1n << 256n;

const permutationMask = (prime: bigint) => (1n << BigInt(Math.floor(prime.toString(2).length / 2))) - 1n;

// Cycle-walk XOR on the nonzero field elements. Applying it twice restores the input.
const permute = (value: bigint, mask: bigint, prime: bigint) => {
  const flipped = value ^ mask;
  return flipped === 0n || flipped >= prime ? value : flipped;
};

const sloth = {
  computeBeacon(seed: bigint, prime: bigint, iterations: bigint) {
    if (!validParameters(prime, iterations)) throw new RangeError('Invalid Sloth parameters');
    if (seed < 0n || seed >= 1n << 256n || seed % prime === 0n) throw new RangeError('Invalid Sloth seed');
    const exponent = (prime + 1n) >> 2n;
    const mask = permutationMask(prime);
    let beacon = seed % prime;
    for (let i = 0n; i < iterations; ++i) {
      const input = permute(beacon, mask, prime);
      let root = modulusExponent(input, exponent, prime);
      const residue = (root * root) % prime === input;
      if (((root & 1n) === 0n) !== residue) root = prime - root;
      beacon = root;
    }
    return beacon;
  },
  verifyBeacon(beacon: bigint, seed: bigint, prime: bigint, iterations: bigint) {
    if (!validParameters(prime, iterations)) return false;
    if (seed < 0n || seed >= 1n << 256n || seed % prime === 0n || beacon <= 0n || beacon >= prime) return false;
    const mask = permutationMask(prime);
    for (let i = 0n; i < iterations; ++i) {
      const squared = (beacon * beacon) % prime;
      beacon = (beacon & 1n) === 0n ? squared : prime - squared;
      beacon = permute(beacon, mask, prime);
    }
    return seed % prime === beacon;
  },
};

export default sloth;
