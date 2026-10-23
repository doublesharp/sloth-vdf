// SPDX-License-Identifier: MIT
// https://eprint.iacr.org/2015/366.pdf

pragma solidity ^0.8.0;

library SlothVDF {
    error InvalidParameters();
    error InvalidSeed();

    struct SlothParams {
        // randomized minting
        uint256 seed;
        // large prime used for VDF
        uint256 prime;
        // iterations for the VDF
        uint128 iterations;
        // randomized minting
        uint16 offset;
    }

    /// @dev verify sloth result proof, starting from seed, over prime , for iterations
    /// @param _proof result
    /// @param _seed seed
    /// @param _prime prime
    /// @param _iterations number of iterations
    /// @dev The caller must supply a trusted prime congruent to 3 modulo 4.
    /// @return true if the canonical proof reverses to the seed
    function verify(uint256 _proof, uint256 _seed, uint256 _prime, uint256 _iterations) internal pure returns (bool) {
        if (_prime <= 3 || _prime % 4 != 3 || _iterations == 0) return false;
        _seed %= _prime;
        if (_seed == 0 || _proof == 0 || _proof >= _prime) return false;

        uint256 mask = permutationMask(_prime);
        uint256 _i = _iterations;
        while (_i != 0) {
            --_i;
            uint256 squared = mulmod(_proof, _proof, _prime);
            // Odd roots encode a nonresidue input; even roots encode a residue.
            _proof = (_proof & 1) == 0 ? squared : _prime - squared;
            _proof = permute(_proof, mask, _prime);
        }

        return _seed == _proof;
    }

    /// @dev Flip the lower half of the field's bits, as in the Sloth reference implementation.
    function permutationMask(uint256 _prime) private pure returns (uint256) {
        uint256 bits = 0;
        for (uint256 value = _prime; value != 0; value >>= 1) {
            ++bits;
        }
        return (uint256(1) << (bits / 2)) - 1;
    }

    /// @dev Cycle-walk XOR on [1, p - 1]. This permutation is its own inverse.
    function permute(uint256 value, uint256 mask, uint256 _prime) private pure returns (uint256) {
        uint256 flipped = value ^ mask;
        return flipped == 0 || flipped >= _prime ? value : flipped;
    }

    /// @dev pow(base, exponent, modulus)
    /// @param b base
    /// @param e exponent
    /// @param m modulus
    function bexmod(uint256 b, uint256 e, uint256 m) internal pure returns (uint256 r) {
        r = 1;

        for (; e > 0; e >>= 1) {
            if (e & 1 == 1) {
                r = mulmod(r, b, m);
            }

            b = mulmod(b, b, m);
        }
    }

    /// @dev compute sloth starting from seed, over prime, for iterations
    /// @param _seed seed
    /// @param _prime prime
    /// @param _iterations number of iterations
    /// @return sloth result
    function compute(uint256 _seed, uint256 _prime, uint256 _iterations) internal pure returns (uint256) {
        if (_prime <= 3 || _prime % 4 != 3 || _iterations == 0) revert InvalidParameters();
        // Equivalent to (p + 1) / 4 without overflowing uint256.
        uint256 e = (_prime >> 2) + 1;
        _seed %= _prime;
        if (_seed == 0) revert InvalidSeed();
        uint256 mask = permutationMask(_prime);

        for (uint256 _i = _iterations; _i != 0; --_i) {
            uint256 input = permute(_seed, mask, _prime);
            uint256 root = bexmod(input, e, _prime);
            bool residue = mulmod(root, root, _prime) == input;
            // Choose the even root for residues and the odd root for nonresidues.
            if (((root & 1) == 0) != residue) root = _prime - root;
            _seed = root;
        }

        return _seed;
    }
}
