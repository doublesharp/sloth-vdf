// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SlothVDF} from '../../../contracts/SlothVDF.sol';

contract SlothHarness {
    function compute(uint256 seed, uint256 prime, uint256 iterations) external pure returns (uint256) {
        return SlothVDF.compute(seed, prime, iterations);
    }

    function verify(uint256 proof, uint256 seed, uint256 prime, uint256 iterations) external pure returns (bool) {
        return SlothVDF.verify(proof, seed, prime, iterations);
    }

    function pow(uint256 base, uint256 exponent, uint256 modulus) external pure returns (uint256) {
        return SlothVDF.bexmod(base, exponent, modulus);
    }
}
