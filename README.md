# Sloth Verifiable Delay Function

<p align="center">
  <img src="https://raw.githubusercontent.com/doublesharp/sloth-vdf/main/sloth.svg" height="20"/>
</p>

This module implements the Sloth VDF algorithm in JavaScript, TypeScript, and Soldity 0.8 for generating provable random numbers.

## Install

```shell
npm install -D @0xdoublesharp/sloth-vdf
```

```shell
yarn add -D @0xdoublesharp/sloth-vdf
```

## Solidity

```ts
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { SlothVDF } from '@0xdoublesharp/sloth-vdf/contracts/SlothVDF.sol';

contract RandomVDFv1 {
  // large prime
  uint256 public prime = 432211379112113246928842014508850435796007;
  // adjust for block finality
  uint256 public iterations = 1000;
  // increment nonce to increase entropy
  uint256 private nonce;
  // address -> vdf seed
  mapping(address => uint256) public seeds;

  uint256 public proof;

  error InvalidProof();
  error AlreadyProven();

  function createSeed() external payable {
    // commit funds/tokens/etc here
    // create a pseudo random seed as the input
    uint256 _nonce = nonce++;
    seeds[msg.sender] = uint256(
      keccak256(abi.encodePacked(msg.sender, _nonce, block.timestamp, blockhash(block.number - 1)))
    );
  }

  function prove(uint256 _proof) external {
    if (proof != 0) revert AlreadyProven();
    if (!SlothVDF.verify(_proof, seeds[msg.sender], prime, iterations)) revert InvalidProof();

    // use the proof as a provable random number
    proof = _proof;
  }
}
```

### JavaScript / TypeScript

```ts
describe('Sloth VDF', () => {
  it('Prove', async () => {
    const { sender, randomVDFv1 } = await loadFixture(fixtures);

    const prime = BigInt((await randomVDFv1.prime()).toString());
    const iterations = BigInt((await randomVDFv1.iterations()).toNumber());
    console.log('prime', prime.toString());
    console.log('iterations', iterations.toString());

    const tx = await randomVDFv1.createSeed();
    await tx.wait();

    const seed = BigInt((await randomVDFv1.seeds(sender.address)).toString());
    console.log('seed', seed.toString());

    let start = Date.now();
    const badproof = sloth.computeBeacon(seed, prime, BigInt(1));
    console.log('compute time', Date.now() - start, 'ms', 'bad proof', badproof);
    start = Date.now();
    const proof = sloth.computeBeacon(seed, prime, iterations);
    console.log('compute time', Date.now() - start, 'ms', 'vdf proof', proof);

    await expect(randomVDFv1.prove(badproof)).to.be.revertedWithCustomError(randomVDFv1, 'InvalidProof');
    await expect(randomVDFv1.prove(proof)).to.not.be.reverted;
    await expect(randomVDFv1.prove(proof)).to.be.revertedWithCustomError(randomVDFv1, 'AlreadyProven');
  });
});
```
