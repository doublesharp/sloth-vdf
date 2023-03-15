// SPDX-License-Identifier: MIT
// https://eprint.iacr.org/2015/366.pdf

pragma solidity ^0.8.0;

// TODO: checking for quadratic residues has been removed, unclear of implications

import {UnsafeMath} from '@0xdoublesharp/unsafe-math/contracts/UnsafeMath.sol';

library SlothVDF {
    using UnsafeMath for uint256;

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
    /// @return true if y is a quadratic residue modulo p
    function verify(uint256 _proof, uint256 _seed, uint256 _prime, uint256 _iterations) internal pure returns (bool) {
        uint256 _i = _iterations;
        while (_i != 0) {
            _i = _i.dec();
            _proof = mulmod(_proof, _proof, _prime);
        }

        _seed %= _prime;

        if (_seed == _proof) return true;

        if (_prime - _seed == _proof) return true;

        return false;
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
        uint256 e = _prime.inc() >> 2;
        _seed %= _prime;

        for (uint256 _i = _iterations; _i != 0; _i = _i.dec()) {
            _seed = bexmod(_seed, e, _prime);
        }

        return _seed;
    }
}
