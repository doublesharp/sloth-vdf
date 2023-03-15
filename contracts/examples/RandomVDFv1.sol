// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SlothVDF} from '../SlothVDF.sol';

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
