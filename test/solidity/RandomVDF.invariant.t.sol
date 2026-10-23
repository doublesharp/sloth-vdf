// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from 'forge-std/Test.sol';
import {StdInvariant} from 'forge-std/StdInvariant.sol';
import {RandomVDFv1} from '../../contracts/examples/RandomVDFv1.sol';
import {SlothReference} from './helpers/SlothReference.sol';

contract RandomVDFHandler is Test {
    struct Model {
        uint256 target;
        uint256 seed;
    }
    RandomVDFv1 public app;
    address[3] public actors = [address(0xA11CE), address(0xB0B), address(0xCA11)];
    Model[3] public model;
    mapping(uint256 => bytes32) public hashes;
    bool public closed;
    uint256 public result;
    uint256 public calls;
    uint256 public completed;
    uint256 public requests;
    uint256 public finalizations;
    uint256 public rejected;

    constructor() {
        vm.roll(100);
        app = new RandomVDFv1(3);
    }

    function request(uint8 rawActor) public {
        ++calls;
        uint256 index = uint256(rawActor) % 3;
        Model storage state = model[index];
        bool allowed = !closed && (state.target == 0 || (state.seed == 0 && block.number > state.target + 256));
        vm.prank(actors[index]);
        (bool success,) = address(app).call(abi.encodeCall(app.createSeed, ()));
        assertEq(success, allowed, 'request model');
        if (success) {
            state.target = block.number + 1;
            ++requests;
        } else {
            ++rejected;
        }
    }

    function advance(uint16 rawBlocks, bytes32 entropy) public {
        ++calls;
        vm.roll(vm.getBlockNumber() + bound(uint256(rawBlocks), 1, 300));
        uint256 current = vm.getBlockNumber();
        for (uint256 i; i < 3; ++i) {
            uint256 target = model[i].target;
            if (target != 0 && current > target && current <= target + 256) {
                if (hashes[target] == bytes32(0)) hashes[target] = keccak256(abi.encode(target, entropy));
                vm.setBlockhash(target, hashes[target]);
            }
        }
    }

    function finalize(uint8 rawActor) public {
        ++calls;
        uint256 index = uint256(rawActor) % 3;
        Model storage state = model[index];
        bool allowed = !closed && state.target != 0 && block.number > state.target && block.number <= state.target + 256
            && state.seed == 0 && hashes[state.target] != bytes32(0);
        // Foundry replaces synthetic block hashes between isolated invariant calls.
        // Restore the immutable model hash in this call before the app reads it.
        if (allowed) vm.setBlockhash(state.target, hashes[state.target]);
        vm.prank(actors[index]);
        (bool success,) = address(app).call(abi.encodeCall(app.finalizeSeed, ()));
        assertEq(success, allowed, 'finalize model');
        if (success) {
            state.seed = 1
                + uint256(
                    keccak256(
                        abi.encode(address(app), block.chainid, actors[index], state.target, hashes[state.target])
                    )
                ) % (app.prime() - 1);
            ++finalizations;
        } else {
            ++rejected;
        }
    }

    function prove(uint8 rawActor, bool correct, uint256 candidate) public {
        ++calls;
        uint256 index = uint256(rawActor) % 3;
        uint256 seed = model[index].seed;
        uint256 expected = seed == 0 ? 0 : SlothReference.compute(seed, app.prime(), 3);
        if (correct) candidate = expected;
        bool allowed = !closed && seed != 0 && candidate == expected;
        vm.prank(actors[index]);
        (bool success,) = address(app).call(abi.encodeCall(app.prove, (candidate)));
        assertEq(success, allowed, 'proof model');
        if (success) {
            closed = true;
            result = candidate;
            ++completed;
        } else {
            ++rejected;
        }
    }

    function restart() public {
        ++calls;
        // Retain terminal state long enough for the other operations to attack it.
        if (!closed) return;
        app = new RandomVDFv1(3);
        delete model;
        closed = false;
        result = 0;
    }
}

contract RandomVDFInvariantTest is StdInvariant, Test {
    RandomVDFHandler handler;

    function setUp() public {
        handler = new RandomVDFHandler();
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.request.selector;
        selectors[1] = handler.advance.selector;
        selectors[2] = handler.finalize.selector;
        selectors[3] = handler.prove.selector;
        selectors[4] = handler.restart.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_ContractMatchesIndependentLifecycleModel() public view {
        RandomVDFv1 app = handler.app();
        assertEq(app.proven(), handler.closed());
        assertEq(app.proof(), handler.result());
        assertEq(app.iterations(), 3);
        assertEq(app.prime(), 2 ** 256 - 189);
        for (uint256 i; i < 3; ++i) {
            (uint256 target, uint256 seed) = handler.model(i);
            address actor = handler.actors(i);
            assertEq(app.seedBlocks(actor), target);
            assertEq(app.seeds(actor), seed);
            if (seed != 0) {
                assertGt(seed, 0);
                assertLt(seed, app.prime());
            }
        }
        assertEq(address(app).balance, 0);
    }

    function test_HandlerReachesAndChecksEveryLifecyclePhase() public {
        handler.request(0);
        handler.request(0); // A duplicate request must fail without changing state.
        handler.advance(2, keccak256('entropy'));
        handler.finalize(0);
        handler.prove(1, true, 0); // Another account has no seed.
        handler.prove(0, true, 0);
        handler.request(1);
        handler.finalize(0);
        handler.prove(0, true, 0);
        invariant_ContractMatchesIndependentLifecycleModel();
        assertEq(handler.requests(), 1);
        assertEq(handler.finalizations(), 1);
        assertEq(handler.completed(), 1);
        assertEq(handler.rejected(), 5);
        handler.restart();
        invariant_ContractMatchesIndependentLifecycleModel();
    }
}
