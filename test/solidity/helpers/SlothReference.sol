// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Independent oracle: Euler's criterion selects +/- input before the EVM modexp
// precompile extracts a root. It does not call the implementation under test.
library SlothReference {
    function pow(uint256 base, uint256 exponent, uint256 prime) internal view returns (uint256 result) {
        bytes memory input = abi.encode(uint256(32), uint256(32), uint256(32), base, exponent, prime);
        (bool success, bytes memory output) = address(5).staticcall(input);
        require(success, 'modexp failed');
        return abi.decode(output, (uint256));
    }

    function compute(uint256 seed, uint256 prime, uint256 iterations) internal view returns (uint256 value) {
        uint256 bits;
        for (uint256 remaining = prime; remaining > 0; remaining >>= 1) {
            ++bits;
        }
        uint256 mask = (uint256(1) << (bits / 2)) - 1;
        value = seed % prime;
        for (uint256 i; i < iterations; ++i) {
            uint256 mixed = value ^ mask;
            if (mixed == 0 || mixed >= prime) mixed = value;
            bool residue = pow(mixed, (prime - 1) / 2, prime) == 1;
            value = pow(residue ? mixed : prime - mixed, (prime >> 2) + 1, prime);
            if ((value % 2 == 0) != residue) value = prime - value;
        }
    }
}
