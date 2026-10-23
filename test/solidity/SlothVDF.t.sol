// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from 'forge-std/Test.sol';
import {SlothVDF} from '../../contracts/SlothVDF.sol';
import {SlothHarness} from './helpers/SlothHarness.sol';
import {SlothReference} from './helpers/SlothReference.sol';

contract SlothVDFTest is Test {
    uint256 constant PRIME = 2 ** 256 - 189;
    SlothHarness harness;

    function setUp() public {
        harness = new SlothHarness();
    }

    function test_ExhaustiveSmallFieldsMatchReferenceAndHaveUniqueOutputs() public view {
        uint256[5] memory primes = [uint256(7), 11, 19, 23, 31];
        for (uint256 i; i < primes.length; ++i) {
            uint256 p = primes[i];
            for (uint256 seed = 1; seed < p; ++seed) {
                uint256 proof = harness.compute(seed, p, 3);
                assertEq(proof, SlothReference.compute(seed, p, 3));
                for (uint256 candidate = 1; candidate < p; ++candidate) {
                    assertEq(harness.verify(candidate, seed, p, 3), candidate == proof);
                }
            }
        }
    }

    function test_InvalidParametersAndSeeds() public {
        uint256[9] memory invalid = [uint256(0), 1, 2, 3, 4, 5, 8, 9, 13];
        for (uint256 i; i < invalid.length; ++i) {
            assertFalse(harness.verify(1, 1, invalid[i], 1));
            vm.expectRevert(SlothVDF.InvalidParameters.selector);
            harness.compute(1, invalid[i], 1);
        }
        assertFalse(harness.verify(1, 1, 11, 0));
        vm.expectRevert(SlothVDF.InvalidParameters.selector);
        harness.compute(1, 11, 0);
        assertFalse(harness.verify(1, 0, 11, 1));
        assertFalse(harness.verify(1, 22, 11, 1));
        vm.expectRevert(SlothVDF.InvalidSeed.selector);
        harness.compute(0, 11, 1);
        vm.expectRevert(SlothVDF.InvalidSeed.selector);
        harness.compute(22, 11, 1);
    }

    function test_RejectsNoncanonicalAndOppositeProofs() public view {
        uint256 proof = harness.compute(2, 11, 4);
        assertFalse(harness.verify(0, 2, 11, 4));
        assertFalse(harness.verify(11, 2, 11, 4));
        assertFalse(harness.verify(proof + 11, 2, 11, 4));
        assertFalse(harness.verify(type(uint256).max, 2, 11, 4));
        assertFalse(harness.verify(11 - proof, 2, 11, 4));
    }

    function test_FieldBoundariesAndSeedReduction() public view {
        uint256[6] memory seeds =
            [uint256(1), 2, (uint256(1) << 128) - 1, uint256(1) << 128, PRIME - 1, type(uint256).max];
        for (uint256 i; i < seeds.length; ++i) {
            uint256 proof = harness.compute(seeds[i], PRIME, 2);
            assertEq(proof, SlothReference.compute(seeds[i], PRIME, 2));
            assertTrue(harness.verify(proof, seeds[i], PRIME, 2));
        }
        assertEq(harness.compute(13, 11, 4), harness.compute(2, 11, 4));
    }

    function test_ModularExponentiation() public view {
        assertEq(harness.pow(0, 0, 11), 1);
        assertEq(harness.pow(0, 1, 11), 0);
        assertEq(harness.pow(3, 2, 11), 9);
        assertEq(harness.pow(3, 3, 11), 5);
    }

    function testFuzz_RoundTripAndReference(uint256 rawSeed, uint8 rawRounds) public view {
        uint256 seed = 1 + rawSeed % (PRIME - 1);
        uint256 rounds = 1 + uint256(rawRounds) % 12;
        uint256 proof = harness.compute(seed, PRIME, rounds);
        assertEq(proof, SlothReference.compute(seed, PRIME, rounds));
        assertTrue(harness.verify(proof, seed, PRIME, rounds));
        uint256 wrong = proof == PRIME - 1 ? 1 : proof + 1;
        assertFalse(harness.verify(wrong, seed, PRIME, rounds));
    }

    function testFuzz_ProofAcceptanceMatchesIndependentOracle(uint256 seed, uint256 candidate, uint8 rounds)
        public
        view
    {
        seed = 1 + seed % 30;
        candidate %= 32;
        uint256 count = 1 + uint256(rounds) % 8;
        assertEq(harness.verify(candidate, seed, 31, count), candidate == SlothReference.compute(seed, 31, count));
    }

    function testFuzz_ModularExponentiation(uint256 base, uint256 exponent, uint256 modulus) public view {
        modulus = bound(modulus, 2, type(uint256).max);
        assertEq(harness.pow(base, exponent, modulus), SlothReference.pow(base, exponent, modulus));
    }
}
