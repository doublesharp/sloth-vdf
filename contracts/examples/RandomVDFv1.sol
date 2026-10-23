// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SlothVDF} from '../SlothVDF.sol';

contract RandomVDFv1 {
    // Largest 256-bit prime, congruent to 3 modulo 4.
    uint256 public constant prime = 2 ** 256 - 189;
    // Calibrate against fast solvers, then check verification gas on the target chain.
    uint256 public immutable iterations;
    // address -> vdf seed
    mapping(address => uint256) public seeds;
    // The future block that supplies entropy after the request is committed.
    mapping(address => uint256) public seedBlocks;

    uint256 public proof;
    bool public proven;

    error InvalidProof();
    error AlreadyProven();
    error SeedAlreadyCreated();
    error SeedNotReady();
    error SeedExpired();
    error InvalidIterations();

    constructor(uint256 _iterations) {
        if (_iterations == 0) revert InvalidIterations();
        iterations = _iterations;
    }

    function createSeed() external {
        if (proven) revert AlreadyProven();
        uint256 target = seedBlocks[msg.sender];
        if (target != 0 && (seeds[msg.sender] != 0 || block.number <= target + 256)) revert SeedAlreadyCreated();
        // Bind any application-specific wager or choice here, before the entropy exists.
        seedBlocks[msg.sender] = block.number + 1;
    }

    function finalizeSeed() external {
        if (proven) revert AlreadyProven();
        uint256 target = seedBlocks[msg.sender];
        if (target == 0 || block.number <= target) revert SeedNotReady();
        if (block.number > target + 256) revert SeedExpired();
        if (seeds[msg.sender] != 0) revert SeedAlreadyCreated();
        bytes32 entropy = blockhash(target);
        if (entropy == bytes32(0)) revert SeedNotReady();
        seeds[msg.sender] = 1
            + (uint256(keccak256(abi.encode(address(this), block.chainid, msg.sender, target, entropy))) % (prime - 1));
    }

    function prove(uint256 _proof) external {
        if (proven) revert AlreadyProven();
        if (seeds[msg.sender] == 0) revert SeedNotReady();
        if (!SlothVDF.verify(_proof, seeds[msg.sender], prime, iterations)) revert InvalidProof();

        // use the proof as a provable random number
        proof = _proof;
        proven = true;
    }
}
