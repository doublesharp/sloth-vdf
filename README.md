<p align="center">
  <img src="./sloth.svg" width="88" height="88" alt="A sloth hanging from a branch" />
</p>

<h1 align="center">Sloth VDF</h1>

<p align="center">Commit a choice. Reveal a future seed. Compute a delayed, verifiable result.</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#using-the-library">Usage</a> ·
  <a href="#testing">Testing</a>
</p>

Sloth VDF pairs an off-chain TypeScript evaluator with an inexpensive Solidity verifier. It is intended for EVM applications that lock a decision before a result can be computed, including applications on fast chains such as Sonic and HyperEVM.

**Version 0.0.3 repairs the Sloth rounds.** Proofs from `0.0.2` and earlier are incompatible. Upgrade the evaluator and Solidity verifier together, and recompute proofs with the repaired implementation. See the [release notes](CHANGELOG.md).

## Quick start

### Install the package

```sh
pnpm add @0xdoublesharp/sloth-vdf@0.0.3
```

The package includes the TypeScript evaluator, Solidity sources, and generated viem bindings. Install `viem` if you use the generated bindings. Consumers do not need Foundry or a Scratch volume to use the published package.

### Develop from source

You need **Node.js 22.12+**, **pnpm 11.21**, [Foundry](https://getfoundry.sh/introduction/installation/) with `forge` and `anvil` on your PATH, and a mounted `/Volumes/Scratch`.

```sh
pnpm install --frozen-lockfile
pnpm build
pnpm test
```

The build compiles Solidity, runs **abi-typegen** to generate viem bindings, and builds the TypeScript package. Build artifacts, generated files, dependency contents, and coverage reports live on Scratch. The checkout contains small links to `dist`, `sdk`, and dependencies for normal local imports.

## How it works

```text
Commit choices       Obtain the seed          Compute off-chain       Verify on-chain
createSeed()   ───►   finalizeSeed()    ───►    computeBeacon()   ───►   prove()
                     after a future block     sequential rounds       reverse the rounds
```

A Sloth round applies a reversible bit permutation, then a modular square-root permutation. Each round depends on the previous output. Verification runs backwards using a modular square and the inverse permutation. The signed root convention gives each seed a unique accepted output.

The [example contract](contracts/examples/RandomVDFv1.sol) makes the seed available **after** the request:

| Step | Action | What becomes fixed |
| --- | --- | --- |
| 1 | Deploy `RandomVDFv1(iterations)` | The work required for every proof |
| 2 | Call `createSeed()` | The caller and the next block used for entropy |
| 3 | Wait until that block is complete, then call `finalizeSeed()` | A nonzero seed bound to the caller, contract, chain, and target block hash |
| 4 | Read the seed, compute the result, and call `prove(result)` | The verified result; the example then closes |

Finalize within **256 blocks** of the target height, while its hash remains available. A pending seed cannot be replaced; an expired request that was never finalized may be restarted. The example accepts one global result and does not accept ETH.

**The delay starts when the target block hash becomes available.** Anyone can derive the seed at that point, even before `finalizeSeed()` is called.

## Using the library

### TypeScript

```ts
import sloth from '@0xdoublesharp/sloth-vdf';

const prime = (1n << 256n) - 189n;
const iterations = 1000n; // Example only. Calibrate this count before deployment.
const seed = 123456789n;

const result = sloth.computeBeacon(seed, prime, iterations);
const valid = sloth.verifyBeacon(result, seed, prime, iterations);
```

### Solidity

```solidity
import {SlothVDF} from '@0xdoublesharp/sloth-vdf/contracts/SlothVDF.sol';

bool valid = SlothVDF.verify(result, seed, prime, iterations);
```

Both implementations use the same rules:

- Supply a **trusted prime** greater than 3 and congruent to 3 modulo 4. Checks validate its shape, not its primality.
- Use positive iterations and uint256 inputs. A seed must be nonzero modulo the prime.
- Submit a canonical result between `1` and `prime - 1`.

`SlothVDF.compute()` is available in Solidity for integrations that need it. Computing off-chain avoids its execution cost.

### Generated viem bindings

`pnpm typegen` generates the example ABI and typed client helpers. Local tests import them from `sdk`; built packages export them from `@0xdoublesharp/sloth-vdf/contracts`.

```ts
import sloth from '@0xdoublesharp/sloth-vdf';
import { getRandomVDFv1Contract } from '@0xdoublesharp/sloth-vdf/contracts';

const reads = getRandomVDFv1Contract(address, publicClient);
const writes = getRandomVDFv1Contract(address, walletClient);

await publicClient.waitForTransactionReceipt({
  hash: await writes.write.createSeed({ account, chain }),
});
// Wait until the current block number is greater than reads.read.seedBlocks([account]).
await publicClient.waitForTransactionReceipt({
  hash: await writes.write.finalizeSeed({ account, chain }),
});

const seed = await reads.read.seeds([account]);
const prime = await reads.read.prime();
const iterations = await reads.read.iterations();
const result = sloth.computeBeacon(seed, prime, iterations);

await publicClient.waitForTransactionReceipt({
  hash: await writes.write.prove([result], { account, chain }),
});
```

## Choosing a delay

Iterations specify work, not seconds. Start with a local measurement:

```sh
pnpm benchmark 1000
```

Increase the count to increase sequential work. Then benchmark optimized native solvers, account for specialized hardware and known cryptanalytic speedups, and choose a safety margin for your application. JavaScript timings cannot establish a guaranteed minimum delay.

Verification gas also grows with the iteration count. Measure `prove()` on the target network. HyperEVM has separate small and large block gas budgets, so a transaction that fits one may not fit the other. See the [HyperEVM block documentation](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm/dual-block-architecture).

## Testing

```sh
pnpm test                 # Typecheck, TypeScript tests, Anvil integration, Solidity tests
pnpm coverage             # Require full production-source coverage in both languages
pnpm test:fuzz            # Foundry fuzz tests, 512 cases per property
pnpm test:invariant       # Stateful lifecycle model, 128 runs × 64 calls
FOUNDRY_PROFILE=deep pnpm test:fuzz
FOUNDRY_PROFILE=deep pnpm test:invariant
```

The suites check:

- Agreement with an independent mathematical implementation, including exhaustive small fields and 256-bit boundary inputs.
- Exact proof acceptance, malformed inputs, canonical output rules, and modular exponentiation.
- Future-block timing, expiry boundaries, account binding, locked seeds, and single-result finality.
- Randomized sequences of requests, block advances, finalizations, submissions, and new example deployments against a separate lifecycle model.
- TypeScript/Solidity agreement and the full 1,000-round flow through generated viem bindings on local Anvil.

Coverage commands fail if production TypeScript statements, lines, functions, or branches are uncovered, or production Solidity lines, functions, or branches are uncovered. Passing coverage measures exercised code; it does not prove the cryptographic delay assumption.

Use `pnpm run pack` to create a publishable tarball under Scratch. It stages real build files, so the package does not depend on checkout symlinks.

## Publishing

The [publish workflow](.github/workflows/publish.yml) uses the npm trusted publisher configured for `doublesharp/sloth-vdf` and `publish.yml`. It publishes with GitHub OIDC and provenance; no npm token is needed.

1. Bump `package.json` to a new version, commit it, and push it to GitHub.
2. Create and push a matching tag, such as `v0.0.3` for version `0.0.3`.
3. Publish a GitHub release for that tag. The workflow tests the code, checks coverage, builds the tarball, and publishes it to npm.

Stable releases use npm's `latest` tag. Versions with a prerelease suffix, or releases marked as prereleases on GitHub, use `next`. The workflow rejects release tags that do not match the package version.

To validate the workflow without publishing, open **Actions → Publish to npm → Run workflow** and leave **dry_run** enabled. Dry runs use a temporary prerelease version in the Scratch tarball, so npm can validate an already-published source version. A manual run with `dry_run` disabled must select a matching version tag. The workflow does not change the repository's version or create releases automatically.

## Security model

A valid proof establishes the correct result for the seed and iteration count. It does **not** establish the exact moment a participant learned that result.

For the intended commit-before-outcome behavior, the application must lock every outcome-dependent choice before the entropy exists. The example marks that integration point in `createSeed()`. It does not implement a wager or enforce an application-specific commitment.

A future block hash also has assumptions: block producers can influence it, users can create requests from several accounts, and solvers can withhold unfavorable results. This example is not a complete unbiased lottery or production randomness service. Chain finality alone does not resolve those incentives.

The repaired implementation restores the inter-round permutation and root-sign rules. It removes the direct exponent-collapse shortcut in the older implementation. Sloth still relies on computational assumptions, and [research on algebraic delay functions](https://eprint.iacr.org/2024/873) motivates conservative calibration and independent cryptographic review.

## References

- [A random zoo: sloth, unicorn, and trx](https://eprint.iacr.org/2015/366), Lenstra and Wesolowski.
- [Sloth reference implementation](https://github.com/randomchain/pysloth/blob/master/sloth.c).
- [Reversible proofs of sequential work](https://secpriv.wien/fulltext/publik_302143.pdf), including the signed square-root construction.
- [abi-typegen](https://github.com/doublesharp/abi-typegen), typed bindings from Foundry artifacts.

The sloth artwork retains the attribution in [sloth.svg](sloth.svg).
