import { ethers, deployments } from 'hardhat';
import { expect } from 'chai';

import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';

import { RandomVDFv1 } from '../sdk/types';
import sloth from '../dist';

async function fixtures() {
  const [sender] = await ethers.getSigners();

  const RandomVDFv1 = await ethers.getContractFactory('RandomVDFv1');
  const randomVDFv1 = await RandomVDFv1.deploy();

  return { sender, randomVDFv1 };
}

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
