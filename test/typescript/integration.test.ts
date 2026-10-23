import { spawn, type ChildProcess } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import fc from 'fast-check';
import { createPublicClient, createTestClient, createWalletClient, http, type Abi, type Address, type Hex } from 'viem';
import { foundry } from 'viem/chains';
import { getRandomVDFv1Contract, RandomVDFv1Abi } from '../../sdk';
import sloth from '../../src';

const PRIME = (1n << 256n) - 189n;
const build = process.env.SLOTH_BUILD_DIR!;
function artifact(source: string, contract: string): { abi: Abi; bytecode: { object: Hex } } {
  return JSON.parse(readFileSync(join(build, 'out', source, `${contract}.json`), 'utf8'));
}
async function unusedPort(): Promise<number> {
  const server = createServer();
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = (server.address() as { port: number }).port;
  await new Promise<void>((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
  return port;
}

describe('compiled Solidity and generated viem bindings on Anvil', () => {
  let anvil: ChildProcess | undefined;
  let url: string;
  let account: Address;
  let harness: Address;
  let publicClient: ReturnType<typeof createPublicClient>;
  let wallet: ReturnType<typeof createWalletClient>;
  let testClient: ReturnType<typeof createTestClient>;
  let harnessAbi: Abi;

  beforeAll(async () => {
    const port = await unusedPort();
    url = `http://127.0.0.1:${port}`;
    anvil = spawn('anvil', ['--host', '127.0.0.1', '--port', String(port), '--silent', '--hardfork', 'paris']);
    let startupError: Error | undefined;
    let output = '';
    anvil.on('error', (error) => {
      startupError = error;
    });
    anvil.stderr?.on('data', (chunk) => {
      output += String(chunk);
    });
    publicClient = createPublicClient({ chain: foundry, transport: http(url, { retryCount: 0 }), pollingInterval: 10 });
    wallet = createWalletClient({ chain: foundry, transport: http(url) });
    testClient = createTestClient({ chain: foundry, mode: 'anvil', transport: http(url) });
    let ready = false;
    for (let i = 0; i < 100; ++i) {
      if (startupError) throw startupError;
      if (anvil.exitCode !== null) throw new Error(`Anvil exited: ${output}`);
      try {
        await publicClient.getChainId();
        ready = true;
        break;
      } catch {
        /* Wait for our local process. */
      }
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    if (!ready) throw new Error(`Anvil did not start: ${output}`);
    [account] = await wallet.getAddresses();
    const compiled = artifact('SlothHarness.sol', 'SlothHarness');
    harnessAbi = compiled.abi;
    const hash = await wallet.deployContract({
      abi: harnessAbi,
      bytecode: compiled.bytecode.object,
      account,
      chain: foundry,
    });
    harness = (await publicClient.waitForTransactionReceipt({ hash })).contractAddress!;
  });

  afterAll(async () => {
    if (anvil && anvil.exitCode === null) {
      const exited = new Promise<void>((resolve) => anvil!.once('exit', () => resolve()));
      anvil.kill('SIGTERM');
      await exited;
    }
  });

  it('matches Solidity evaluation and verification for randomized inputs', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.bigInt({ min: 1n, max: PRIME - 1n }),
        fc.bigInt({ min: 1n, max: 8n }),
        async (seed, rounds) => {
          const proof = sloth.computeBeacon(seed, PRIME, rounds);
          const actual = await publicClient.readContract({
            address: harness,
            abi: harnessAbi,
            functionName: 'compute',
            args: [seed, PRIME, rounds],
          });
          expect(actual).toBe(proof);
          const valid = await publicClient.readContract({
            address: harness,
            abi: harnessAbi,
            functionName: 'verify',
            args: [proof, seed, PRIME, rounds],
          });
          expect(valid).toBe(true);
        }
      ),
      { numRuns: 32, seed: 0xe7 }
    );
  });

  it('uses generated bindings for the complete commit, future seed, and proof flow', async () => {
    const compiled = artifact('RandomVDFv1.sol', 'RandomVDFv1');
    const hash = await wallet.deployContract({
      abi: RandomVDFv1Abi,
      bytecode: compiled.bytecode.object,
      args: [1000n],
      account,
      chain: foundry,
    });
    const address = (await publicClient.waitForTransactionReceipt({ hash })).contractAddress!;
    const reader = getRandomVDFv1Contract(address, publicClient);
    const writer = getRandomVDFv1Contract(address, wallet);
    await publicClient.waitForTransactionReceipt({ hash: await writer.write.createSeed({ account, chain: foundry }) });
    expect(await reader.read.seeds([account])).toBe(0n);
    await testClient.mine({ blocks: 2 });
    await publicClient.waitForTransactionReceipt({
      hash: await writer.write.finalizeSeed({ account, chain: foundry }),
    });
    const seed = await reader.read.seeds([account]);
    const prime = await reader.read.prime();
    const rounds = await reader.read.iterations();
    const proof = sloth.computeBeacon(seed, prime, rounds);
    const gas = await publicClient.estimateContractGas({
      address,
      abi: RandomVDFv1Abi,
      functionName: 'prove',
      args: [proof],
      account,
    });
    await publicClient.waitForTransactionReceipt({
      hash: await writer.write.prove([proof], { account, chain: foundry }),
    });
    expect(await reader.read.proof()).toBe(proof);
    expect(await reader.read.proven()).toBe(true);
    console.log(`Local Anvil prove() gas at ${rounds} rounds: ${gas}`);
  });
});
